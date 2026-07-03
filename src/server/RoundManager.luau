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
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local RoundState = require(ReplicatedStorage.Shared.RoundState)
local GraceModel = require(ReplicatedStorage.Shared.GraceModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CadenceModel = require(ReplicatedStorage.Shared.CadenceModel)
local ControlModel = require(ReplicatedStorage.Shared.ControlModel)
local BodyManager = require(script.Parent.BodyManager)
local ControlManager = require(script.Parent.ControlManager)
local SwapController = require(script.Parent.SwapController)
local HazardSystem = require(script.Parent.HazardSystem)
local LobbyArea = require(script.Parent.LobbyArea)
local EconomyService = require(script.Parent.EconomyService)

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

-- Round-scoped dynamic-cadence state (reset in beginRound). cadenceStartCount is the
-- alive count at round start; swapsSoFar counts swaps committed this round. CadenceModel
-- maps these -> the next swap interval (20s calm round-start -> 8s frantic endgame).
local cadenceStartCount = 0
local swapsSoFar = 0

-- Economy: per-player swaps-survived counter (a placement proxy) + the round's
-- participant set, so endRound can award everyone who played. `awarded` guards
-- against double-paying a single round-end. All reset in beginRound.
local survivedSwaps = {}     -- [player] = int
local roundParticipants = {} -- [player] = true
local awarded = false

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

-- A player is a valid participant only if they currently control a fully-spawned
-- body: it exists, is parented in the world, and has a HumanoidRootPart. Guards
-- against a present-but-bodyless player (e.g. an avatar load that produced no
-- usable body, leaving the client with only a camera) being counted toward round
-- start or handed into the swap derangement.
local function hasValidBody(player)
	local body = ControlManager.getControlledBody(player)
	return body ~= nil and body.Parent ~= nil and body:FindFirstChild("HumanoidRootPart") ~= nil
end

-- The set of connected players that currently have a valid body. Passed to
-- RoundState.beginRound so only they become round participants (alive).
local function eligibleSet()
	local set = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if hasValidBody(p) then
			set[p] = true
		end
	end
	return set
end

-- How many connected players have a valid body right now.
local function validBodiedCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if hasValidBody(p) then
			n += 1
		end
	end
	return n
end

-- Round-start gate: the pure lifecycle gate (enough present, in Lobby) AND enough
-- of those players actually have a valid body. Stops a round from starting while a
-- present player is still bodyless (camera-only).
local function readyToStart()
	return RoundState.canStart(model) and validBodiedCount() >= Config.MIN_PLAYERS_TO_START
end

-- The ordered alive roster = connected, alive players that ALSO have a valid body.
-- The body check is defensive (alive players normally always have a body, since it
-- is only destroyed on disconnect, which un-alives them), guaranteeing the swap
-- derangement never receives a bodyless participant.
local function aliveRoster()
	local roster = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if RoundState.isAlive(model, p) and hasValidBody(p) then
			roster[#roster + 1] = p
		end
	end
	return roster
end

-- Current-state floor probe (doom-exclusion, spec 2026-07-03 §4). A body is SAFE iff
-- a downward ray from its root to the kill-plane (VOID_Y), excluding all player bodies,
-- hits solid floor. RespectCanCollide=true means a gone (CanCollide=false) hex tile is
-- correctly NOT floor. Arena-agnostic: any arena's floors are solid parts; VOID_Y is a
-- per-arena Config value. Bodies with no floor before the void are void-bound (doomed)
-- and must be excluded from the derangement so they are never handed to a victim.
local function hasFloorBeneath(body)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bodiesFolder = Workspace:FindFirstChild("Bodies")
	params.FilterDescendantsInstances = bodiesFolder and { bodiesFolder } or {}
	params.RespectCanCollide = true
	local origin = root.Position
	local downTo = Config.VOID_Y - origin.Y -- negative: from root down to the kill-plane
	if downTo >= 0 then
		return false -- root is already at/below the kill-plane: no floor "before the void"
	end
	local hit = Workspace:Raycast(origin, Vector3.new(0, downTo, 0), params)
	return hit ~= nil
end

-- Is the body `player` currently controls safe to swap right now?
local function isBodySafe(player)
	return hasFloorBeneath(ControlManager.getControlledBody(player))
end

-- True iff every player in the plan currently has a safe (non-void-bound) body. Used
-- so the commit re-plans over the safe subset even when the plan is otherwise CURRENT:
-- the pre-swap rim-jump happens DURING the preview, so a still-alive planned player can
-- become doomed just before commit.
local function planAllSafe(plan)
	for _, pair in ipairs(plan.to) do
		if not isBodySafe(pair.player) then
			return false
		end
	end
	return true
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
		if body then
			body:SetAttribute("GraceProtected", true) -- client shimmer follows this
		end
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

-- Commit a planned swap. The commit is authoritative over the CURRENT roster: if the
-- plan went stale during the preview (someone died/left, an absorb moved a survivor),
-- OR any planned player became void-bound (doom-exclusion), recompute over the live,
-- currently-safe roster before applying. Doomed bodies are excluded from the
-- derangement (they keep their current controller and die for their own grief). Aborts
-- if fewer than 2 safe players remain (the round is ending).
local function commitSwap(plan)
	if not planIsCurrent(plan) or not planAllSafe(plan) then
		local roster = ControlModel.filterSafe(aliveRoster(), isBodySafe)
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
		body:SetAttribute("GraceProtected", false)
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
			local t = now()
			-- One server loop now drives BOTH void death and hex erosion: gather a
			-- body sample per alive player (position + whether grace still shields it)
			-- and hand them to HazardSystem.step after the per-player death check.
			local samples = {}
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
						-- Erosion sample. graceBlocked reuses the SAME grace gate as
						-- hazard death: while a freshly-swapped body still can't die
						-- from a hazard, the hex under it won't arm either. Computed
						-- AFTER the move check, so moving (which clears grace) also
						-- un-blocks arming. HazardSystem raycasts from `position` to
						-- find the tile actually under the body (hex logic stays there).
						local graceBlocked = not GraceModel.canDieFromHazard(grace, player, t)
						-- Mirror the authoritative grace gate onto the body so the client
						-- shimmer follows it instead of guessing from local input. On-change
						-- only (avoid per-tick replication spam). graceBlocked == protected.
						if body:GetAttribute("GraceProtected") ~= graceBlocked then
							body:SetAttribute("GraceProtected", graceBlocked)
						end
						samples[#samples + 1] = {
							position = root.Position,
							graceBlocked = graceBlocked,
						}
						-- Void death source, gated by the post-swap grace window.
						if root.Position.Y < Config.VOID_Y then
							RoundManager.eliminateFromHazard(player)
						end
					end
				end
			end
			HazardSystem.step(t, samples)
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
		if not readyToStart() then
			broadcastState() -- back to plain Lobby (dropped below threshold or a body went invalid)
			return true
		end
		broadcastState(remaining)
		task.wait(1)
		remaining -= 1
	end
	return false
end

local function beginRound()
	local eligible = eligibleSet()
	RoundState.beginRound(model, eligible) -- Lobby -> Active; only valid-bodied present players become alive
	-- Economy: snapshot participants + zero their swaps-survived for this round.
	survivedSwaps = {}
	roundParticipants = {}
	for player in pairs(eligible) do
		roundParticipants[player] = true
		survivedSwaps[player] = 0
	end
	awarded = false
	cadenceStartCount = RoundState.aliveCount(model)
	swapsSoFar = 0
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
-- (interval - PREVIEW), then run the PREVIEW window (plan + per-client preview,
-- re-planning if the roster churns), then commit the swap at T0.
local function runActivePhase()
	while RoundState.getPhase(model) == "Active" do
		-- Dynamic cadence: the interval shrinks as players are eliminated and as the
		-- round drags on (CadenceModel). The HUD counts down to this broadcast deadline.
		-- Opts are read from Config each cycle so a smoke-test command-bar tweak of the
		-- CADENCE_* tunables takes effect on the next swap.
		local interval = CadenceModel.interval(
			cadenceStartCount, RoundState.aliveCount(model), swapsSoFar, {
				maxInterval = Config.CADENCE_MAX_INTERVAL,
				minInterval = Config.CADENCE_MIN_INTERVAL,
				swapsToFloor = Config.CADENCE_SWAPS_TO_FLOOR,
				stallWeight = Config.CADENCE_STALL_WEIGHT,
			})
		broadcastState(nil, workspace:GetServerTimeNow() + interval)

		-- Free play.
		waitActive(interval - Config.PREVIEW_SECONDS)
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
			swapsSoFar += 1 -- advances the cadence progress term (counts planned swaps; a
			-- late roster-collapse abort inside commitSwap is benign -- the round is ending)
			-- Economy: every participant still alive just survived this swap.
			for player in pairs(roundParticipants) do
				if RoundState.isAlive(model, player) then
					survivedSwaps[player] = (survivedSwaps[player] or 0) + 1
				end
			end
		end
	end
end

local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
	-- Economy: award every participant exactly once for this round (survival-depth).
	if not awarded then
		awarded = true
		for player in pairs(roundParticipants) do
			EconomyService.awardRound(player, {
				survivedSwaps = survivedSwaps[player] or 0,
				isWinner = player == winner,
				participated = true,
			})
		end
	end
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
	-- Capture aliveness BEFORE RoundState drops the player. The rescue below applies
	-- only when an ELIMINATED leaver's disconnect-absorb would hand the parked body it
	-- was controlling to a still-ALIVE survivor -- which would otherwise strand that
	-- survivor on the balcony and stop the round from ever ending (disconnect-strand spec).
	local leaverWasAlive = RoundState.isAlive(model, player)
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	local decision = ControlManager.removePlayer(player) -- absorb + destroy the leaver's own body
	-- Alive-aware rescue: reposition the survivor's newly-absorbed body back into the
	-- arena and re-assert their ownership (reposition-then-re-own, like beginRound, so
	-- the teleport replicates onto the client-owned body). Their camera follows the
	-- body's humanoid, so no extra remote is needed.
	if not leaverWasAlive and decision and decision.reassign
		and RoundState.isAlive(model, decision.reassign.player) then
		BodyManager.sendToArena(decision.reassign.body)
		ControlManager.regrantControl(decision.reassign.player)
	end
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
	HazardSystem.build() -- construct the 3-floor hex arena once (replaces the baseplate)
	LobbyArea.build() -- construct the elevated lobby balcony once
	task.spawn(function()
		while true do
			-- Re-broadcast the Lobby state on every poll, not just once. FireAllClients
			-- is fire-and-forget: the single up-front send raced the client's listener
			-- (which connects after server boot) and was lost. With 2+ players the
			-- countdown's per-second broadcasts masked it, but a lone player -- for whom
			-- readyToStart() is never true -- got no further state and so never saw the
			-- lobby banner. Re-sending each poll syncs late/lone clients reliably; the
			-- client renders it idempotently (no pop-in re-trigger, no dot-anim reset).
			while not readyToStart() do
				broadcastState() -- Lobby
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
