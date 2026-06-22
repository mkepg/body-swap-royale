--[[
	RoundManager (server) -- the master round loop and the only owner of real
	clocks. Sequences Lobby -> Active -> Ended -> reset, gates swaps to Active,
	and coordinates the pure RoundState (phase/alive/winner) with the Roblox-side
	ControlManager / BodyManager / SwapController.

	Pure decisions live elsewhere:
	  RoundState  -- when a round can start / ends, who the winner is.
	  ControlModel (via ControlManager) -- the controllers<->bodies bijection.

	Elimination is LOGICAL: a body crossing VOID_Y is sent up to the lobby balcony
	(still under its player's control), never killed, so the next round just
	repositions it (no Humanoid revive).

	Depends on:
	  ReplicatedStorage.Shared.Config / RoundState / Remotes
	  ServerScriptService.Server.BodyManager / ControlManager / SwapController
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RoundState = require(ReplicatedStorage.Shared.RoundState)
local GraceModel = require(ReplicatedStorage.Shared.GraceModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BodyManager = require(script.Parent.BodyManager)
local ControlManager = require(script.Parent.ControlManager)
local SwapController = require(script.Parent.SwapController)
local HazardSystem = require(script.Parent.HazardSystem)
local LobbyArea = require(script.Parent.LobbyArea)

local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")
local SwapPreview = Remotes.get("SwapPreview")

local RoundManager = {}
local model = RoundState.new(Config.MIN_PLAYERS_TO_START, Config.MIN_PLAYERS_TO_CONTINUE)

-- Post-swap grace: per-player timers + a server-derived "has moved" flag (pure
-- decision in GraceModel). swapPos holds each player's controlled-body root
-- position at its last swap, so the void monitor can derive horizontal travel.
local grace = GraceModel.new()
local swapPos = {} -- [player] = Vector3

-- The single monotonic clock for grace. Pure GraceModel takes `now` injected.
local function now()
	return os.clock()
end

-- A unique token gates the void monitor; setting it to a new value (or nil) stops
-- any previously-running monitor loop.
local monitorToken = nil

-- ===== broadcasts =====

local function broadcastState(secondsRemaining, swapAtServerTime)
	local winner = RoundState.getWinner(model)
	RoundStateChanged:FireAllClients({
		phase = RoundState.getPhase(model),
		aliveCount = RoundState.aliveCount(model),
		winnerName = winner and winner.Name or nil,
		secondsRemaining = secondsRemaining,
		swapAtServerTime = swapAtServerTime,
	})
end

-- ===== alive roster =====

-- The ordered alive roster = connected players filtered by RoundState.isAlive.
-- (No new RoundState accessor needed; the pure module stays untouched.)
local function aliveRoster()
	local roster = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if RoundState.isAlive(model, p) then
			roster[#roster + 1] = p
		end
	end
	return roster
end

-- Tell each player in the plan which body they will inherit (drives the
-- client-side preview highlight). Fired at preview start and on any re-plan.
local function firePreview(plan)
	for _, pair in ipairs(plan.to) do
		SwapPreview:FireClient(pair.player, pair.body)
	end
end

-- After control has been committed, open the post-swap grace window for `players`
-- and record each one's new controlled-body position so the void monitor can
-- derive "has moved" (horizontal travel since the swap).
local function stampGrace(players)
	local t = now()
	for _, player in ipairs(players) do
		GraceModel.onSwap(grace, player, t, Config.GRACE_SECONDS, Config.GRACE_FLOOR_SECONDS)
		local body = ControlManager.getControlledBody(player)
		local root = body and body:FindFirstChild("HumanoidRootPart")
		swapPos[player] = root and root.Position or nil
	end
end

-- A plan is current iff it still matches the live control map AND every player
-- in it is still alive. planStillValid alone only sees control-map changes
-- (disconnect / absorb) because ControlModel is unaware of death -- a hazard
-- death updates RoundState + sends the body to the balcony but leaves bodyOf
-- untouched. Without the aliveness check, a death during the 3s preview would
-- commit a stale plan: a live player would be handed the dead player's balcony
-- body, and the dead player would keep a live body (orphaned next cycle).
local function planIsCurrent(plan)
	if not SwapController.planStillValid(plan) then
		return false
	end
	for _, pair in ipairs(plan.to) do
		if not RoundState.isAlive(model, pair.player) then
			return false
		end
	end
	return true
end

-- Commit a planned swap. The commit is authoritative over the CURRENT roster: if
-- the plan went stale during the preview window (someone died/left, or an absorb
-- moved a survivor), recompute over the live roster before applying. Aborts if
-- fewer than 2 remain (the round is ending).
local function commitSwap(plan)
	if not planIsCurrent(plan) then
		local roster = aliveRoster()
		if #roster < 2 then
			return
		end
		plan = SwapController.plan(roster)
	end
	SwapController.commit(plan)
	local players = {}
	for _, pair in ipairs(plan.to) do
		players[#players + 1] = pair.player
	end
	stampGrace(players)
end

-- Immediate plan+commit (no preview) -- used by forceSwap for the smoke test.
local function doSwap()
	local roster = aliveRoster()
	if #roster >= 2 then
		local plan = SwapController.plan(roster)
		commitSwap(plan)
	end
end

-- ===== elimination =====

-- The single logical elimination entry point. Hazard deaths reach it through
-- eliminateFromHazard (which applies the grace gate); disconnects call it via
-- removePlayer. Idempotent: a no-op for a player who is not currently alive.
function RoundManager.eliminate(player)
	-- Idempotent: if the player isn't currently alive, RoundState.eliminate would
	-- no-op, so skip the side effects (event/relocate) entirely.
	if not RoundState.isAlive(model, player) then
		return { ended = false, winner = nil }
	end
	local result = RoundState.eliminate(model, player)
	-- Send the body they were controlling (now out of the round) up to their
	-- balcony slot, still under their control, so they watch the rest of the round
	-- from the lobby instead of leaving a parked corpse in the arena.
	local body = ControlManager.getControlledBody(player)
	if body then
		BodyManager.sendToLobby(player, body)
	end
	EliminationEvent:FireAllClients(player.Name)
	GraceModel.clear(grace, player)
	swapPos[player] = nil
	return result
end

-- Hazard-sourced elimination passes through the post-swap grace gate: a body still
-- within its grace window cannot be eliminated by a hazard (the void now, and any
-- future hazard). Disconnect-driven elimination does NOT use this path. Idempotent
-- via RoundManager.eliminate.
function RoundManager.eliminateFromHazard(player)
	if GraceModel.canDieFromHazard(grace, player, now()) then
		return RoundManager.eliminate(player)
	end
	return { ended = false, winner = nil }
end

-- ===== void monitor =====

local function startMonitor()
	local token = {}
	monitorToken = token
	task.spawn(function()
		while monitorToken == token do
			for _, player in ipairs(Players:GetPlayers()) do
				if RoundState.isAlive(model, player) then
					local body = ControlManager.getControlledBody(player)
					local root = body and body:FindFirstChild("HumanoidRootPart")
					if root then
						-- Derive HasMovedSinceSwap from horizontal travel since the
						-- last swap; vertical fall does not count (GDD: grace does
						-- not block falling), so a dropped body keeps its window.
						local origin = swapPos[player]
						if origin then
							local d = root.Position - origin
							if Vector3.new(d.X, 0, d.Z).Magnitude > Config.GRACE_MOVE_EPSILON then
								GraceModel.markMoved(grace, player)
								swapPos[player] = nil
							end
						end
						-- Void death source, gated by the post-swap grace window.
						if root.Position.Y < Config.VOID_Y then
							RoundManager.eliminateFromHazard(player)
						end
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

local function stopMonitor()
	monitorToken = nil
end

-- ===== phase handlers =====

-- Pre-round countdown. Returns true if it was aborted (players dropped below the
-- start threshold), false if it ran to completion.
local function runCountdown()
	local remaining = Config.LOBBY_COUNTDOWN_SECONDS
	while remaining > 0 do
		if not RoundState.canStart(model) then
			broadcastState() -- back to plain Lobby
			return true
		end
		broadcastState(remaining)
		task.wait(1)
		remaining -= 1
	end
	return false
end

local function beginRound()
	RoundState.beginRound(model) -- Lobby -> Active; present snapshot into alive
	-- Unanchor + reposition bodies BEFORE re-granting ownership: SetNetworkOwner
	-- errors on an anchored part. (Lobby bodies are already unanchored, so the
	-- unanchor in resetBody is defensive.)
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.resetBody(p) -- reposition own body to spawn + unanchor
	end
	ControlManager.resetControl() -- everyone back on their own body (+ retarget)
	broadcastState() -- phase Active
	HazardSystem.start(now()) -- tile floor begins its cycles (solid at round start)
	startMonitor()
	print("[BSR] round started")
end

-- Wait up to `seconds`, breaking early if the round leaves Active. Polls at the
-- same 0.25s cadence used elsewhere.
local function waitActive(seconds)
	local elapsed = 0
	while elapsed < seconds and RoundState.getPhase(model) == "Active" do
		task.wait(0.25)
		elapsed += 0.25
	end
end

-- Spin during Active. Each cycle: broadcast the swap deadline, free-play for
-- (CYCLE - PREVIEW), then run the PREVIEW window (plan + per-client preview,
-- re-planning if the roster churns), then commit the swap at T0.
local function runActivePhase()
	while RoundState.getPhase(model) == "Active" do
		broadcastState(nil, workspace:GetServerTimeNow() + Config.CYCLE_SECONDS)

		-- Free play.
		waitActive(Config.CYCLE_SECONDS - Config.PREVIEW_SECONDS)
		if RoundState.getPhase(model) ~= "Active" then
			break
		end

		-- Preview window: plan now and tell each client their target body.
		local plan = nil
		local roster = aliveRoster()
		if #roster >= 2 then
			plan = SwapController.plan(roster)
			firePreview(plan)
		end

		local elapsed = 0
		while elapsed < Config.PREVIEW_SECONDS and RoundState.getPhase(model) == "Active" do
			task.wait(0.25)
			elapsed += 0.25
			-- Re-plan if the roster changed mid-preview (death / disconnect / absorb).
			if plan and not planIsCurrent(plan) then
				roster = aliveRoster()
				if #roster >= 2 then
					plan = SwapController.plan(roster)
					firePreview(plan)
				else
					plan = nil
				end
			end
		end
		if RoundState.getPhase(model) ~= "Active" then
			break
		end

		-- Commit at T0.
		if plan then
			commitSwap(plan)
		end
	end
end

local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
	-- Victory cam: while the Results banner is up, point EVERY present player's
	-- camera at the winner standing in the arena below. Bodies are NOT relocated
	-- yet, so the winner stays put as the cam subject. Reuses SpectateBody (the
	-- client sets CameraSubject unconditionally). Skipped if there is no winner
	-- (disconnect-decided round) -- nothing to frame.
	local remaining = Config.ROUND_END_SECONDS
	broadcastState(remaining) -- always show the Results banner at least once (Ended)
	if winner then
		local winnerBody = ControlManager.getControlledBody(winner)
		if winnerBody then
			SpectateBody:FireAllClients(winnerBody)
		end
	end
	while remaining > 1 do
		task.wait(1)
		remaining -= 1
		broadcastState(remaining) -- tick N-1 .. 1
	end
	task.wait(remaining > 0 and 1 or 0) -- wait out the final second (skip if N == 0)
	-- Relocate everyone to the balcony for the Lobby wait. Order mirrors
	-- beginRound: unanchor + pivot (returnToLobby) BEFORE resetControl, which
	-- SetNetworkOwners (errors on an anchored part) and fires SetControlledBody --
	-- pulling each camera off the victory-cam subject back onto its own body,
	-- now standing on the balcony.
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.returnToLobby(p)
	end
	ControlManager.resetControl()
	RoundState.reset(model) -- Ended -> Lobby
	broadcastState() -- phase Lobby
end

-- ===== lifecycle entry points (called by init.server) =====

function RoundManager.addPlayer(player)
	local body = BodyManager.createBody(player)
	ControlManager.addPlayer(player, body) -- start in your own body
	RoundState.addPlayer(model, player)
	print(string.format("[BSR] %s -> own body (%s)", player.Name, body.Name))
end

function RoundManager.removePlayer(player)
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	ControlManager.removePlayer(player)    -- absorb + destroy the leaver's own body
	GraceModel.clear(grace, player)
	swapPos[player] = nil
	-- If the disconnect ended the round, the Active loop observes phase Ended and
	-- runs endRound; no special handling needed here.
end

-- Debug helper for the Studio smoke test: force a swap now instead of waiting the
-- cycle. Safe to call from the command bar.
function RoundManager.forceSwap()
	doSwap()
end

function RoundManager.start()
	HazardSystem.build() -- construct the tile-field arena once (replaces the baseplate)
	LobbyArea.build() -- construct the elevated lobby balcony once
	task.spawn(function()
		while true do
			broadcastState() -- Lobby
			while not RoundState.canStart(model) do
				task.wait(0.25)
			end
			local aborted = runCountdown()
			if not aborted then
				beginRound()
				runActivePhase()
				endRound()
			end
		end
	end)
end

return RoundManager
