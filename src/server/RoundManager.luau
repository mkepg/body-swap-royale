--[[
	RoundManager (server) -- the master round loop and the only owner of real
	clocks. Sequences Lobby -> Active -> Ended -> reset, gates swaps to Active,
	and coordinates the pure RoundState (phase/alive/winner) with the Roblox-side
	ControlManager / BodyManager / SwapController.

	Pure decisions live elsewhere:
	  RoundState  -- when a round can start / ends, who the winner is.
	  ControlModel (via ControlManager) -- the controllers<->bodies bijection.

	Elimination is LOGICAL: a body crossing VOID_Y is parked (anchored), never
	killed, so the next round just repositions it (no Humanoid revive).

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

local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")

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

local function broadcastState(secondsRemaining)
	local winner = RoundState.getWinner(model)
	RoundStateChanged:FireAllClients({
		phase = RoundState.getPhase(model),
		aliveCount = RoundState.aliveCount(model),
		winnerName = winner and winner.Name or nil,
		secondsRemaining = secondsRemaining,
	})
end

-- The body of the first currently-alive player (used as a spectate target).
local function firstAliveBody()
	for _, p in ipairs(Players:GetPlayers()) do
		if RoundState.isAlive(model, p) then
			return ControlManager.getControlledBody(p)
		end
	end
	return nil
end

-- Point every eliminated-but-connected player's camera at a living body so they
-- spectate the action instead of a corpse. No-op in Lobby (nobody is alive yet).
local function resendSpectate()
	if RoundState.getPhase(model) == "Lobby" then
		return
	end
	local target = firstAliveBody()
	if not target then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if not RoundState.isAlive(model, p) then
			SpectateBody:FireClient(p, target)
		end
	end
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

local function doSwap()
	local roster = aliveRoster()
	if #roster >= 2 then
		local ok, msg = SwapController.swap(roster)
		print("[BSR] swap:", ok, msg)
		if ok then
			-- Open a grace window for everyone who just swapped, and record the
			-- starting position of the body they now control so the monitor can
			-- tell when they have moved (oriented).
			local t = now()
			for _, player in ipairs(roster) do
				GraceModel.onSwap(grace, player, t, Config.GRACE_SECONDS, Config.GRACE_FLOOR_SECONDS)
				local body = ControlManager.getControlledBody(player)
				local root = body and body:FindFirstChild("HumanoidRootPart")
				swapPos[player] = root and root.Position or nil
			end
		end
	end
end

-- ===== elimination =====

-- The single logical elimination entry point. Hazard deaths reach it through
-- eliminateFromHazard (which applies the grace gate); disconnects call it via
-- removePlayer. Idempotent: a no-op for a player who is not currently alive.
function RoundManager.eliminate(player)
	-- Idempotent: if the player isn't currently alive, RoundState.eliminate would
	-- no-op, so skip the side effects (event/park/spectate) entirely.
	if not RoundState.isAlive(model, player) then
		return { ended = false, winner = nil }
	end
	local result = RoundState.eliminate(model, player)
	local body = ControlManager.getControlledBody(player)
	if body then
		BodyManager.parkBody(body)
	end
	EliminationEvent:FireAllClients(player.Name)
	resendSpectate()
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
	-- errors on an anchored part, and a body parked on elimination last round
	-- stays anchored until resetBody runs.
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.resetBody(p) -- reposition own body to spawn + unanchor
	end
	ControlManager.resetControl() -- everyone back on their own body (+ retarget)
	broadcastState() -- phase Active
	HazardSystem.start(now()) -- tile floor begins its cycles (solid at round start)
	startMonitor()
	print("[BSR] round started")
end

-- Spin during Active: swap every CYCLE_SECONDS until the phase leaves Active
-- (an elimination or disconnect auto-ended it inside RoundState).
local function runActivePhase()
	while RoundState.getPhase(model) == "Active" do
		local elapsed = 0
		while elapsed < Config.CYCLE_SECONDS and RoundState.getPhase(model) == "Active" do
			task.wait(0.25)
			elapsed += 0.25
		end
		if RoundState.getPhase(model) ~= "Active" then
			break
		end
		doSwap()
	end
end

local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	broadcastState() -- phase Ended (+ winnerName)
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
	task.wait(Config.ROUND_END_SECONDS)
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
	if RoundState.getPhase(model) == "Active" then
		resendSpectate() -- the alive set may have shrunk
	end
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
