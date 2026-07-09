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
local MovementValidator = require(ReplicatedStorage.Shared.MovementValidator)
local ControlModel = require(ReplicatedStorage.Shared.ControlModel)
local ArenaRotationModel = require(ReplicatedStorage.Shared.ArenaRotationModel)
local BodyManager = require(script.Parent.BodyManager)
local ControlManager = require(script.Parent.ControlManager)
local SwapController = require(script.Parent.SwapController)
local ArenaRegistry = require(script.Parent.ArenaRegistry)
local LobbyArea = require(script.Parent.LobbyArea)
local EconomyService = require(script.Parent.EconomyService)
local HintService = require(script.Parent.HintService)

local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")
local SwapPreview = Remotes.get("SwapPreview")

local RoundManager = {}
local model = RoundState.new(Config.MIN_PLAYERS_TO_START, Config.MIN_PLAYERS_TO_CONTINUE)
-- The live arena is chosen PER ROUND (rotation); between rounds `arena` holds the
-- last round's pick (safe: the monitor and swap paths only run during Active).
local arena = ArenaRegistry.all()[1]
local currentArenaId = nil

-- Post-swap grace: per-player timers + a server-derived "has moved" flag (pure
-- decision in GraceModel). swapPos holds each player's controlled-body root
-- position at its last swap, so the void monitor can derive horizontal travel.
local grace = GraceModel.new()
local swapPos = {} -- [player] = Vector3

-- Movement validation (server-authoritative anti-cheat). The pure MovementValidator
-- judges each owned body's per-tick motion; the glue below holds the only Roblox-typed
-- state. `lastPos` is the previous tick's root position (to derive deltas); `validAnchor`
-- is the most recent CLEAN + GROUNDED pose (the rubber-band target). Jump launch speed is
-- derived from gravity + JUMP_HEIGHT (kept out of the pure model, which only multiplies).
local validator = MovementValidator.new()
local lastPos = {}       -- [body] = Vector3
local validAnchor = {}   -- [body] = CFrame
local lastMonitorT = nil -- previous monitor-tick timestamp (measured dt)
local jumpSpeed = math.sqrt(2 * Workspace.Gravity * Config.JUMP_HEIGHT)

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
	-- Sweeper beams are CanCollide = false, so RespectCanCollide rays ignore them
	-- natively -- no collision-group trick needed to keep a moving beam from faking
	-- a floor under a falling body.
	local origin = root.Position
	local downTo = arena.voidY() - origin.Y -- negative: from root down to the kill-plane
	if downTo >= 0 then
		return false -- root is already at/below the kill-plane: no floor "before the void"
	end
	local hit = Workspace:Raycast(origin, Vector3.new(0, downTo, 0), params)
	return hit ~= nil
end

-- Movement-validation bookkeeping ------------------------------------------------

-- A server-initiated PivotTo (round start / end / elimination / rescue) moves a body far
-- in one tick; clearing its tracking makes the next monitor tick re-seed cleanly instead
-- of reading the teleport as a violation.
local function noteServerReposition(body)
	if not body then return end
	lastPos[body] = nil
	validAnchor[body] = nil
	MovementValidator.reseed(validator, body)
end

-- Drop all validation state for a destroyed body (disconnect), so the tables never leak.
local function forgetBodyValidation(body)
	if not body then return end
	lastPos[body] = nil
	validAnchor[body] = nil
	MovementValidator.forget(validator, body)
end

-- Validate one owned body for one monitor tick. Reduces the body to scalar deltas, asks the
-- pure MovementValidator, and on a confirmed violation snaps it back to its last valid grounded
-- pose (reposition-then-re-own). `player` is the current controller (for the re-own). `dt` is the
-- measured seconds since the last tick.
local function validateBody(player, body, dt)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pos = root.Position
	local prev = lastPos[body]
	if not prev then
		-- First sight (or just after a server reposition): seed and skip; no delta yet.
		lastPos[body] = pos
		validAnchor[body] = body:GetPivot()
		MovementValidator.reseed(validator, body)
		return
	end
	local delta = pos - prev
	local hasFloor = hasFloorBeneath(body) -- the ONE ray per body per tick (reused below)
	local decision = MovementValidator.step(validator, body, {
		horizDelta = Vector3.new(delta.X, 0, delta.Z).Magnitude,
		vertDelta = delta.Y,
		dt = dt,
		hasFloor = hasFloor,
	}, {
		walkSpeed = Config.WALK_SPEED,
		horizontalSlack = Config.MOVE_HORIZONTAL_SLACK,
		jumpSpeed = jumpSpeed,
		verticalSlack = Config.MOVE_VERTICAL_SLACK,
		minFallEpsilon = Config.MOVE_MIN_FALL_EPSILON,
		violationTicks = Config.MOVE_VIOLATION_TICKS,
	})
	if decision.correct then
		local anchor = validAnchor[body]
		if anchor then
			-- Reposition-then-re-own: pivot (zeroes velocity) then re-assert ownership so the
			-- snap replicates onto the client-owned body. Same primitive as the disconnect rescue.
			BodyManager.pivotTo(body, anchor)
			ControlManager.regrantControl(player)
			lastPos[body] = anchor.Position -- next delta is measured from where we put it
		end
	else
		lastPos[body] = pos
		if hasFloor then
			validAnchor[body] = body:GetPivot() -- only anchor on a clean, grounded pose
		end
	end
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
		HintService.fireTrigger(pair.player, "SwapPreview")
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
	for _, p in ipairs(players) do
		HintService.fireTrigger(p, "ControlSwap")
	end
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
		-- Re-assert ownership after the server pivot (reposition-then-re-own), so the
		-- teleport replicates onto the client-owned body -- uniform with beginRound's
		-- resetBody->resetControl and the disconnect rescue's sendToArena->regrantControl
		-- (review Action #4; matters for the fast-falling elimination case under latency).
		ControlManager.regrantControl(player)
		noteServerReposition(body) -- the send-to-lobby pivot is server-initiated, not a cheat
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
	lastMonitorT = nil
	task.spawn(function()
		while monitorToken == token do
			local t = now()
			local dt = lastMonitorT and (t - lastMonitorT) or 0.1
			if dt <= 0 then dt = 0.1 end
			lastMonitorT = t
			-- Movement validation runs for EVERY owned body (alive or eliminated) -- one
			-- invariant: all owned bodies are validated. This also contains an eliminated
			-- player's balcony body (a teleport back toward the arena is snapped away).
			if Config.MOVE_VALIDATION_ENABLED then
				for _, player in ipairs(Players:GetPlayers()) do
					local body = ControlManager.getControlledBody(player)
					if body then
						validateBody(player, body, dt)
					end
				end
			end
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
							player = player,
							body = body,
							velocityY = root.AssemblyLinearVelocity.Y,
						}
						-- Void death source, gated by the post-swap grace window.
						if root.Position.Y < arena.voidY() then
							RoundManager.eliminateFromHazard(player)
						end
					end
				end
			end
			local effects = arena.step(t, samples)
			-- Beam touch = elimination (spec 2026-07-09 v2.2): route each struck player
			-- through the SAME grace-gated chokepoint as void death. Deterministic server
			-- math on server-owned physics state -- no knockback, nothing to desync.
			if effects and effects.eliminations then
				for _, p in ipairs(effects.eliminations) do
					RoundManager.eliminateFromHazard(p)
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
	currentArenaId = ArenaRotationModel.next(currentArenaId, ArenaRegistry.ids(), Config.ARENA_OVERRIDE)
	arena = ArenaRegistry.get(currentArenaId)
	workspace:SetAttribute("LiveArena", currentArenaId)
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
	local slotIndex = 0
	for _, p in ipairs(Players:GetPlayers()) do
		slotIndex += 1
		BodyManager.setArenaSlot(p, arena.spawnCFrame(slotIndex)) -- live arena's round spawn slot
		BodyManager.resetBody(p) -- reposition own body to spawn + unanchor
		noteServerReposition(BodyManager.getOwnBody(p)) -- don't read the spawn teleport as a violation
	end
	ControlManager.resetControl() -- everyone back on their own body (+ retarget)
	-- Round-start grace (2026-07-03 review recommendation, now load-bearing: beams
	-- kill on touch, so every player gets the standard orient beat before the bars
	-- -- or the hex tiles -- can hurt them).
	local participants = {}
	for player in pairs(roundParticipants) do
		participants[#participants + 1] = player
	end
	stampGrace(participants)
	broadcastState() -- phase Active
	arena.start(now()) -- tile floor begins its cycles (solid at round start)
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
	arena.stop() -- freeze tiles solid for the Ended/Lobby floor
	workspace:SetAttribute("LiveArena", "")
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
		noteServerReposition(BodyManager.getOwnBody(p))
	end
	ControlManager.resetControl()
	RoundState.reset(model) -- Ended -> Lobby
	broadcastState() -- phase Lobby
end

-- ===== lifecycle entry points (called by init.server) =====

-- Guards addPlayer against overlapping calls for the same player. BodyManager.createBody
-- YIELDS (avatar web calls + retry backoff), so the reconciler sweep (below) can fire
-- again for a player whose PlayerAdded-driven addPlayer is still mid-build; without this,
-- that interleaving would build two bodies and double-register the player.
local addInProgress = {} -- [player] = true while a body build is running

-- Idempotent + re-entrancy-safe: a no-op if the player is already embodied
-- (BodyManager.getOwnBody ~= nil) or a build is already in flight for them. Safe to
-- call repeatedly -- PlayerAdded calls it once; the reconciler sweep in start() calls
-- it again for any connected-but-bodiless player until it succeeds.
function RoundManager.addPlayer(player)
	if BodyManager.getOwnBody(player) ~= nil or addInProgress[player] then
		return
	end
	addInProgress[player] = true
	-- pcall so a throw from createBody (which is designed never to throw, but this
	-- last-resort net must be fail-safe regardless) still clears addInProgress. A
	-- leaked `true` would permanently block this player's re-embodiment, since the
	-- top guard also gates every reconciler retry.
	local ok, body = pcall(BodyManager.createBody, player)
	addInProgress[player] = nil -- always cleared, even on throw
	if not ok then
		warn(string.format("[BSR] createBody(%s) errored; reconciler will retry: %s", player.Name, tostring(body)))
		return
	end
	if not body then
		-- Every build attempt failed (see BodyManager.buildAvatarBody). Do not poison
		-- the control map with a nil body or register a bodyless player as present.
		-- The player stays connected as a bodiless spectator (camera only); the
		-- reconciler sweep in RoundManager.start() will retry.
		warn(string.format("[BSR] %s joined with no body; reconciler will retry", player.Name))
		return
	end
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
	local leaverBody = BodyManager.getOwnBody(player) -- captured before ControlManager destroys it
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	local decision = ControlManager.removePlayer(player) -- absorb + destroy the leaver's own body
	forgetBodyValidation(leaverBody) -- the leaver's body is destroyed; drop its tracking
	-- Alive-aware rescue: reposition the survivor's newly-absorbed body back into the
	-- arena and re-assert their ownership (reposition-then-re-own, like beginRound, so
	-- the teleport replicates onto the client-owned body). Their camera follows the
	-- body's humanoid, so no extra remote is needed.
	if not leaverWasAlive and decision and decision.reassign
		and RoundState.isAlive(model, decision.reassign.player) then
		BodyManager.sendToArena(decision.reassign.body)
		ControlManager.regrantControl(decision.reassign.player)
		noteServerReposition(decision.reassign.body) -- rescued survivor's body was server-pivoted
	end
	GraceModel.clear(grace, player)
	swapPos[player] = nil
	addInProgress[player] = nil -- clear a stale guard if the player disconnected mid-build
	-- If the disconnect ended the round, the Active loop observes phase Ended and
	-- runs endRound; no special handling needed here.
end

-- Debug helper for the Studio smoke test: force a swap now instead of waiting the
-- cycle. Safe to call from the command bar.
function RoundManager.forceSwap()
	doSwap()
end

-- Tear down + rebuild a player whose REGISTERED own body is no longer intact
-- (unparented / engine-destroyed parts -- e.g. a grace-shielded fall that beat the
-- 10 Hz void monitor to Workspace.FallenPartsDestroyHeight). Such a body never
-- heals on its own, and it used to BLIND the bodiless sweep: getOwnBody was still
-- set, so the sweep never retried, stranding whoever controlled the wreck
-- camera-only for the rest of the server's life (and hanging the round -- a
-- rootless body skips the void-death check, so its rider could never be
-- eliminated). Sequenced to preserve the control bijection + round invariants:
--   1. eliminate the RIDER (whoever controls the wreck): their ride is gone --
--      same semantics as dying to the void (idempotent no-op if not alive);
--   2. eliminate the OWNER too if they are alive on some OTHER body: their avatar
--      body is being torn down, and eliminate() first parks the body they control;
--   3. ControlManager.removePlayer applies the lune-tested absorb rule and
--      destroys the wreck; a rider reassigned by the absorb (always just
--      eliminated) is parked on their balcony slot, reposition-then-re-own;
--   4. the sweep's existing bodiless branch then rebuilds the owner exactly like
--      a late joiner (fresh body on the balcony, next round entry).
local function healBrokenBody(owner)
	local broken = BodyManager.getOwnBody(owner)
	local rider = ControlManager.getController(broken)
	warn(string.format("[BSR] %s's body is broken (unparented/destroyed parts); rebuilding (rider: %s)",
		owner.Name, rider and rider.Name or "none"))
	if rider then
		RoundManager.eliminate(rider)
	end
	if rider ~= owner then
		RoundManager.eliminate(owner)
	end
	local decision = ControlManager.removePlayer(owner)
	if decision and decision.reassign then
		BodyManager.sendToLobby(decision.reassign.player, decision.reassign.body)
		ControlManager.regrantControl(decision.reassign.player)
		noteServerReposition(decision.reassign.body)
	end
	forgetBodyValidation(broken)
	-- Owner stays present in RoundState (they are still connected); the sweep's
	-- addPlayer call right after re-embodies them.
end

function RoundManager.start()
	for _, a in ipairs(ArenaRegistry.all()) do
		a.build() -- persistent world: EVERY arena is constructed once at startup
	end
	LobbyArea.build() -- construct the elevated lobby balcony once
	-- Re-embodiment net: a connected player with no own body (every build attempt
	-- failed on join) is re-embodied here. Arena-/phase-agnostic and idempotent (addPlayer's
	-- own guard prevents a double build). A mid-round heal gives the player a balcony body
	-- that joins the next round, exactly like a late joiner. Each player is pcall-isolated:
	-- this loop is the last-resort recovery and never restarts, so an uncaught throw would
	-- unwind out of both the for and the while true and silently disable recovery for the
	-- server's lifetime. The p.Parent == Players guard also skips a player who left during a
	-- previous player's build yield (no wasted avatar web build + misleading warn).
	task.spawn(function()
		while true do
			task.wait(Config.BODY_RECONCILE_SECONDS)
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Parent == Players then
					-- Health check must match the CONSUMERS' definition of usable
					-- (hasValidBody / the client's camera), not mere registration: a
					-- registered-but-broken body would otherwise blind this sweep
					-- forever. Tear the wreck down first; the bodiless branch below
					-- then rebuilds in the same pass.
					local own = BodyManager.getOwnBody(p)
					if own and not BodyManager.isIntact(own) then
						local ok, err = pcall(healBrokenBody, p)
						if not ok then
							warn(string.format("[BSR] reconciler healBrokenBody(%s) errored: %s", p.Name, tostring(err)))
						end
					end
					if not BodyManager.getOwnBody(p) then
						local ok, err = pcall(RoundManager.addPlayer, p)
						if not ok then
							warn(string.format("[BSR] reconciler addPlayer(%s) errored: %s", p.Name, tostring(err)))
						end
					end
				end
			end
		end
	end)
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
