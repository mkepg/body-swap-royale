# RoundManager Implementation Plan

**Goal:** Build `RoundManager`, the server-side glue that drives the MVP win/lose loop — sequencing `Lobby → Active → Ended → reset`, gating swaps to the Active phase, coordinating `RoundState` with `ControlModel`/`ControlManager`/`BodyManager`/`SwapController`, and wiring a minimal void death source through to a declared winner.

**Architecture:** `RoundManager` owns the master loop and all real clocks; the pure decisions already live in `RoundState` (phase/alive/winner) and `ControlModel` (controllers↔bodies bijection). One new pure op — `ControlModel.resetControl` — is added (lune-tested); everything else in this plan is Roblox glue, validated by a manual 2-client Studio smoke test. The swap roster each cycle is exactly `RoundState`'s alive set, so the bodies handed to the derangement always equal the set of alive controllers. Elimination is *logical* (never `Humanoid.Health = 0`): the dead body is parked (anchored), and round reset repositions it — no revive, no destruction, bijection intact.

**Tech Stack:** Luau, Rojo, lune (terminal test runner, pinned in `rokit.toml`).

**Spec:** [docs/specs/2026-06-18-round-manager-design.md](../specs/2026-06-18-round-manager-design.md)

**Lune test command (Tasks 1 and the final check):**
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau
```
lune runs the whole spec file at once; there is no per-test selection. "Verify it fails" means run the file and see the new assertion/`require` error; "verify it passes" means the file prints `ALL CONTROLMODEL TESTS PASSED`.

**Branch:** The spec is committed on `main`. Create a feature branch for the implementation before Task 1:
```bash
git checkout -b feat/round-manager
```

**Coherence note (read before starting):** Tasks 5–8 are interdependent server glue with no automated tests. Between Task 5 (slimming `SwapController`) and Task 8 (rewiring `init.server`), the server will **not** boot cleanly in Studio — that is expected. The whole server-glue set is validated together by the **Task 11 smoke test**. Commit each task anyway (frequent commits); just don't expect a runnable Studio session until Task 8 lands.

---

### Task 1: `ControlModel.resetControl` (pure, lune-tested)

The one new piece of pure logic: reset every connected player's control back to their own avatar body, rebuilding `controllerOf` from scratch so no stale mapping from the previous round survives.

**Files:**
- Modify: `src/shared/ControlModel.luau`
- Modify: `tests/control_model.spec.luau`

- [ ] **Step 1: Write the failing test**

In `tests/control_model.spec.luau`, insert this block immediately **before** the final `print("ALL CONTROLMODEL TESTS PASSED")` line:

```lua
-- resetControl: after a swap moves players off their own bodies, resetControl
-- returns everyone to their OWN avatar body and rebuilds a clean bijection.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.addPlayer(m, "C", "c")
	ControlModel.swap(m, { "A", "B", "C" }, function(_n) return 1 end) -- nobody on own body

	expect(ControlModel.controlledBody(m, "A") ~= "a", "precondition: A off own body")

	local pairs_ = ControlModel.resetControl(m)

	expect(ControlModel.controlledBody(m, "A") == "a", "A back on own body a")
	expect(ControlModel.controlledBody(m, "B") == "b", "B back on own body b")
	expect(ControlModel.controlledBody(m, "C") == "c", "C back on own body c")
	expect(ControlModel.bijectionHolds(m), "bijection holds after resetControl")

	-- controllerOf has no stale entries: exactly the three own bodies, each -> owner.
	expect(m.controllerOf["a"] == "A" and m.controllerOf["b"] == "B" and m.controllerOf["c"] == "C",
		"controllerOf maps each own body to its owner")

	-- returned pairs describe the reset mapping.
	expect(#pairs_ == 3, "resetControl returns one pair per player")
	for _, pr in ipairs(pairs_) do
		expect(ControlModel.controlledBody(m, pr.player) == pr.body, "pair matches model")
		expect(pr.body == m.ownerBody[pr.player], "pair body is the player's own body")
	end
	print("resetControl: everyone back on own body + clean bijection OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau
```
Expected: FAIL — `attempt to call a nil value (field 'resetControl')`.

- [ ] **Step 3: Write minimal implementation**

In `src/shared/ControlModel.luau`, add this function immediately **before** the final `return ControlModel`:

```lua
-- Reset every connected player's control back to their OWN avatar body
-- (ownerBody). Rebuilds controllerOf from scratch so a body a stranger controlled
-- last round is cleanly handed back to its owner with no stale entries. Used by
-- the server glue at each round start to get an identical, predictable starting
-- state. Returns an array of { player = <player>, body = <ownBody> } so the glue
-- can re-grant network ownership and fire SetControlledBody.
function ControlModel.resetControl(model)
	model.controllerOf = {}
	local result = {}
	for player in pairs(model.players) do
		local own = model.ownerBody[player]
		model.bodyOf[player] = own
		model.controllerOf[own] = player
		result[#result + 1] = { player = player, body = own }
	end
	return result
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau
```
Expected: PASS — includes `resetControl: everyone back on own body + clean bijection OK`, ending with `ALL CONTROLMODEL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/ControlModel.luau tests/control_model.spec.luau
git commit -m "feat: ControlModel.resetControl (return all players to own bodies)"
```

---

### Task 2: Config constants

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Add the round-loop tunables**

In `src/shared/Config.luau`, immediately after the `Config.GRACE_FLOOR_SECONDS = 0.5` line (end of the "Round timing" block), add:

```lua

-- RoundManager loop tunables (server-owned clocks + the void death source).
-- LOBBY_COUNTDOWN_SECONDS: pre-round countdown once enough players are present.
-- ROUND_END_SECONDS: winner-display window before resetting to Lobby.
-- VOID_Y: a controlled body whose root falls below this Y is eliminated. It sits
-- well above Workspace.FallenPartsDestroyHeight (default -500), so a falling body
-- is caught and parked here long before the engine would destroy it.
Config.LOBBY_COUNTDOWN_SECONDS = 5
Config.ROUND_END_SECONDS = 5
Config.VOID_Y = -50
```

- [ ] **Step 2: Sanity-check the toolchain still runs**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau
```
Expected: still prints `ALL CONTROLMODEL TESTS PASSED` (confirms nothing else broke; Config isn't imported there).

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat: add RoundManager loop tunables to Config"
```

---

### Task 3: Register the new remotes

**Files:**
- Modify: `src/shared/Remotes.luau`

- [ ] **Step 1: Add the three server→client events**

In `src/shared/Remotes.luau`, change the `REMOTE_EVENTS` line from:

```lua
local REMOTE_EVENTS = { "SetControlledBody" }
```

to:

```lua
local REMOTE_EVENTS = { "SetControlledBody", "RoundStateChanged", "EliminationEvent", "SpectateBody" }
```

- [ ] **Step 2: Commit**

```bash
git add src/shared/Remotes.luau
git commit -m "feat: register RoundStateChanged / EliminationEvent / SpectateBody remotes"
```

---

### Task 4: `BodyManager.resetBody` + `parkBody` + spawn storage

`resetBody` repositions a player's own body to its spawn slot at round start (revive-free — the Humanoid was never killed). `parkBody` anchors an eliminated body so it stops falling and is never destroyed by `FallenPartsDestroyHeight`.

**Files:**
- Modify: `src/server/BodyManager.luau`

- [ ] **Step 1: Add a spawn-CFrame table**

In `src/server/BodyManager.luau`, immediately after the line:

```lua
BodyManager.bodyByOwner = {} -- [player] = body wearing that player's avatar
```

add:

```lua
BodyManager.spawnByOwner = {} -- [player] = CFrame the body spawned at (for round-start reposition)
```

- [ ] **Step 2: Store the spawn CFrame in `createBody`**

In `src/server/BodyManager.luau`, in `createBody`, replace these lines:

```lua
	BodyManager._index += 1
	local pos = Config.SPAWN_ORIGIN + Vector3.new((BodyManager._index - 1) * Config.SPAWN_SPACING, 0, 0)
	body:PivotTo(CFrame.new(pos))
```

with:

```lua
	BodyManager._index += 1
	local pos = Config.SPAWN_ORIGIN + Vector3.new((BodyManager._index - 1) * Config.SPAWN_SPACING, 0, 0)
	local spawnCFrame = CFrame.new(pos)
	body:PivotTo(spawnCFrame)
	BodyManager.spawnByOwner[player] = spawnCFrame
```

- [ ] **Step 3: Clear the spawn entry in `removeBody`**

In `src/server/BodyManager.luau`, in `removeBody`, replace:

```lua
	BodyManager.bodyByOwner[player] = nil
```

with:

```lua
	BodyManager.bodyByOwner[player] = nil
	BodyManager.spawnByOwner[player] = nil
```

- [ ] **Step 4: Add `resetBody` and `parkBody`**

In `src/server/BodyManager.luau`, immediately **before** the final `return BodyManager`, add:

```lua
-- Round start: reposition a player's OWN body to its spawn slot and re-enable
-- physics. The body was never killed (elimination is logical), so no revive is
-- needed -- just unanchor, zero velocity, and pivot back to the spawn CFrame.
function BodyManager.resetBody(player)
	local body = BodyManager.bodyByOwner[player]
	local cf = BodyManager.spawnByOwner[player]
	if not body or not cf then
		return
	end
	local root = body:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	body:PivotTo(cf)
end

-- Elimination: park a body in place so it stops falling and is never destroyed by
-- FallenPartsDestroyHeight. Anchoring the root halts physics; the next round's
-- resetBody unanchors and repositions it.
function BodyManager.parkBody(body)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
	end
end
```

- [ ] **Step 5: Commit**

```bash
git add src/server/BodyManager.luau
git commit -m "feat: BodyManager resetBody/parkBody + spawn-CFrame storage"
```

---

### Task 5: Slim `SwapController` to `swap(orderedAlive)`

`RoundManager` now decides *when* to swap and `RoundState` decides *who*, so `SwapController` loses its self-driving loop and its eligibility filter. It becomes a thin guard over `ControlManager.swap`.

**Files:**
- Modify: `src/server/SwapController.luau`

- [ ] **Step 1: Replace the module body**

Replace the entire contents of `src/server/SwapController.luau` with:

```lua
--[[
	SwapController (server) -- performs one swap over a given roster.

	RoundManager decides WHEN to swap (the cycle clock) and RoundState decides WHO
	is eligible (the alive set). This module just takes the ordered roster of alive
	players and rotates their control via ControlManager (Sattolo derangement lives
	in the pure ControlModel). It no longer owns a loop or an eligibility filter.

	Depends on:
	  ServerScriptService.Server.ControlManager
--]]

local ControlManager = require(script.Parent.ControlManager)

local SwapController = {}

-- Rotate control across `orderedAlive` (the alive roster, built by RoundManager
-- from RoundState). Needs >= 2 players. Returns ok, message.
function SwapController.swap(orderedAlive)
	if #orderedAlive < 2 then
		return false, "need >=2 alive players"
	end
	local n = ControlManager.swap(orderedAlive)
	return true, string.format("swapped %d players", n)
end

return SwapController
```

- [ ] **Step 2: Commit**

```bash
git add src/server/SwapController.luau
git commit -m "refactor: SwapController takes the alive roster; drop self-driving loop"
```

---

### Task 6: `ControlManager.resetControl` glue

**Files:**
- Modify: `src/server/ControlManager.luau`

- [ ] **Step 1: Add the glue function**

In `src/server/ControlManager.luau`, immediately **before** the line `function ControlManager.getControlledBody(player)`, add:

```lua
-- Reset every player to their own avatar body (round start). Applies the pure
-- ControlModel.resetControl, then re-grants network ownership and notifies each
-- client (isSwap = false: a clean spawn-style retarget, no FOV punch).
function ControlManager.resetControl()
	local result = ControlModel.resetControl(model)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, false)
	end
	return result
end

```

- [ ] **Step 2: Commit**

```bash
git add src/server/ControlManager.luau
git commit -m "feat: ControlManager.resetControl glue (re-grant ownership on reset)"
```

---

### Task 7: `RoundManager` module

The master loop. Owns the clocks, the void monitor, the broadcasts, and a debug `forceSwap`.

**Files:**
- Create: `src/server/RoundManager.luau`

- [ ] **Step 1: Create the module**

Create `src/server/RoundManager.luau` with:

```lua
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
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BodyManager = require(script.Parent.BodyManager)
local ControlManager = require(script.Parent.ControlManager)
local SwapController = require(script.Parent.SwapController)

local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")

local RoundManager = {}
local model = RoundState.new(Config.MIN_PLAYERS_TO_START, Config.MIN_PLAYERS_TO_CONTINUE)

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
	end
end

-- ===== elimination =====

-- The single logical elimination entry point. Called by the void monitor (and by
-- the Humanoid.Died hook for future health-based hazards). Idempotent: a no-op for
-- a player who is not currently alive.
function RoundManager.eliminate(player)
	local result = RoundState.eliminate(model, player)
	local body = ControlManager.getControlledBody(player)
	if body then
		BodyManager.parkBody(body)
	end
	EliminationEvent:FireAllClients(player.Name)
	resendSpectate()
	return result
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
					if root and root.Position.Y < Config.VOID_Y then
						RoundManager.eliminate(player)
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
	ControlManager.resetControl() -- everyone back on their own body (+ retarget)
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.resetBody(p) -- reposition own body to spawn
	end
	broadcastState() -- phase Active
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
```

- [ ] **Step 2: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat: RoundManager master loop (sequencing, void monitor, broadcasts)"
```

---

### Task 8: Rewire `init.server`

Route join/leave through `RoundManager` and start its loop instead of the old unconditional swap loop. **After this task the server boots cleanly again.**

**Files:**
- Modify: `src/server/init.server.luau`

- [ ] **Step 1: Replace the module body**

Replace the entire contents of `src/server/init.server.luau` with:

```lua
--[[
	Server bootstrap (Init) -- ownership-transfer model + round lifecycle.
	Location: ServerScriptService/Server  (Script; siblings are its child modules)

	Players have NO Character; they're disembodied controllers. Each gets a
	persistent body wearing their avatar, and starts by controlling their own.
	RoundManager owns the round loop: it sequences Lobby -> Active -> Ended,
	gates swaps to the Active phase, and declares a winner.

	Join/leave are routed through RoundManager so RoundState (lifecycle) and the
	control map (bijection) stay in sync. On disconnect RoundManager applies the
	absorb rule via ControlManager before destroying the leaver's avatar body.
--]]

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local RoundManager = require(script.RoundManager)

local function onPlayerAdded(player)
	RoundManager.addPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	RoundManager.removePlayer(player)
end)

RoundManager.start()
print("[BSR] Server ready (ownership-transfer model + round loop).")
```

- [ ] **Step 2: Commit**

```bash
git add src/server/init.server.luau
git commit -m "feat: route join/leave through RoundManager; start the round loop"
```

---

### Task 9: Client round HUD (text + spectator camera)

**Files:**
- Create: `src/client/ClientRoundHud.luau`
- Modify: `src/client/init.client.luau`

- [ ] **Step 1: Create the HUD module**

Create `src/client/ClientRoundHud.luau` with:

```lua
--[[
	ClientRoundHud -- minimal round feedback.
	Location: StarterPlayerScripts/Client/ClientRoundHud  (ModuleScript)

	Renders centered text from the round remotes (lobby countdown, elimination,
	winner) and, when this client is eliminated, retargets the spectator camera to
	a living body. This is intentionally minimal -- the full HUD is a later task.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")

local ClientRoundHud = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function makeLabel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.18)
	label.Size = UDim2.fromScale(0.8, 0.12)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = gui
	return label
end

function ClientRoundHud.start()
	local label = makeLabel()

	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state.phase == "Lobby" then
			if state.secondsRemaining then
				label.Text = "Round starting in " .. tostring(state.secondsRemaining)
			else
				label.Text = "Waiting for players..."
			end
		elseif state.phase == "Active" then
			label.Text = ""
		elseif state.phase == "Ended" then
			label.Text = state.winnerName and ("Winner: " .. state.winnerName) or "Round over"
		end
	end)

	EliminationEvent.OnClientEvent:Connect(function(playerName)
		if playerName == player.Name then
			label.Text = "You were eliminated"
		end
	end)

	SpectateBody.OnClientEvent:Connect(function(body)
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = hum
		end
	end)
end

return ClientRoundHud
```

- [ ] **Step 2: Start the HUD from the client bootstrap**

In `src/client/init.client.luau`, replace:

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)

ClientControl.start()
ClientAnimator.start()
```

with:

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
```

- [ ] **Step 3: Commit**

```bash
git add src/client/ClientRoundHud.luau src/client/init.client.luau
git commit -m "feat: ClientRoundHud (round text + spectator camera)"
```

---

### Task 10: CHANGELOG + smoke-test doc

**Files:**
- Modify: `CHANGELOG.md`
- Create: `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md`

- [ ] **Step 1: Record the changes in the changelog**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add as the first bullets:

```markdown
- `src/server/RoundManager.luau` — server glue driving the MVP win/lose loop:
  sequences `Lobby → Active → Ended → reset` on real clocks, gates swaps to the
  Active phase (roster = `RoundState`'s alive set), runs a void death monitor that
  logically eliminates a body crossing `Config.VOID_Y` (parked, never killed), and
  broadcasts phase/elimination/spectate to clients. Declares a winner.
- `src/client/ClientRoundHud.luau` — minimal round feedback (lobby countdown,
  "You were eliminated", "Winner: <name>") plus spectator-camera retarget.
- `ControlModel.resetControl` — pure op returning every player to their own avatar
  body with a rebuilt bijection (lune-tested); used at each round start.
- `Config.LOBBY_COUNTDOWN_SECONDS` / `Config.ROUND_END_SECONDS` / `Config.VOID_Y`.
- `RoundStateChanged` / `EliminationEvent` / `SpectateBody` remotes.
```

Then under `### Changed`, add:

```markdown
- `src/server/SwapController.luau` — no longer owns a loop or an eligibility
  filter; `swap(orderedAlive)` performs one swap over the roster RoundManager
  passes. RoundManager decides *when*, RoundState decides *who*.
- `src/server/init.server.luau` — routes join/leave through RoundManager and
  starts the round loop instead of the old unconditional swap loop.
- `src/server/BodyManager.luau` — added `resetBody` (round-start reposition) and
  `parkBody` (anchor an eliminated body), with per-owner spawn-CFrame storage.
```

- [ ] **Step 2: Write the smoke-test procedure**

Create `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md` with:

```markdown
# Round-loop smoke test (manual, 2-client Studio)

Validates the RoundManager win/lose loop, which lune can't reach. Run a **2-player
local server** in Studio (Test → Clients and Servers → 2 → Start).

**Setup for a fast test** (Server view, command bar): temporarily shorten the clocks
so you don't wait 30s per cycle, e.g.
`require(game.ReplicatedStorage.Shared.Config).CYCLE_SECONDS = 8`.

**Procedure & PASS criteria:**
1. **Round start.** After both clients join, the lobby countdown text appears and
   counts down (`LOBBY_COUNTDOWN_SECONDS`), then a round begins: both clients
   control their own body, repositioned to spawn, and the countdown text clears.
2. **Force a swap (optional).** From the Server command bar:
   `require(game.ServerScriptService.Server.RoundManager).forceSwap()` — both
   clients hard-cut to a new body with the FOV punch.
3. **Void death.** Walk one client's body off the arena / below `Config.VOID_Y`
   (default −50). That player sees "You were eliminated" and their camera retargets
   to the surviving body (spectating, not a corpse). `workspace.Bodies` is unchanged
   (the dead body is parked/anchored, **not** destroyed).
4. **Winner.** Both clients see "Winner: <name>" for the surviving player.
5. **Round 2.** After `ROUND_END_SECONDS`, the loop returns to Lobby and a second
   round begins — all bodies repositioned to spawn and everyone back on their own
   body (proves revive-free reset + `resetControl`).
6. **Disconnect win.** In a fresh round, kick one player from the Server command bar:
   `game.Players:GetPlayers()[1]:Kick("test")`. The round ends with the remaining
   player as winner; their controlled body is never yanked (absorb rule still holds).

Bodies are named `Body_<UserId>` under `workspace.Bodies`; players have no
`Character` (`CharacterAutoLoads = false`).
```

- [ ] **Step 3: Final lune check (pure module unaffected)**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau
```
Expected: prints `ALL CONTROLMODEL TESTS PASSED` (the `resetControl` test from Task 1 included).

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md docs/smoke-tests/2026-06-18-round-loop-smoke-test.md
git commit -m "docs: record RoundManager + round-loop smoke test"
```

---

### Task 11: Run the smoke test

**Files:** none (manual validation).

- [ ] **Step 1: Execute the smoke test**

Follow `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md` end to end in Studio with 2 clients. All six PASS criteria must hold. If any fails, fix before considering the plan complete — this is the only validation for the server glue.

---

## Self-Review

**Spec coverage:**
- Components table → `RoundManager` (T7), `ControlModel.resetControl` (T1), `ControlManager.resetControl` (T6), `SwapController` slim (T5), `BodyManager.resetBody/parkBody` (T4), `Config` constants (T2), `Remotes` (T3), client HUD (T9). ✓
- New pure op `resetControl` (bijection, no stale entries, returns pairs) → T1 with lune test. ✓
- Config `LOBBY_COUNTDOWN_SECONDS` / `ROUND_END_SECONDS` / `VOID_Y` → T2. ✓ FallenPartsDestroyHeight-below-VOID_Y noted in the comment (default −500 < −50). ✓
- Master loop (join → Lobby wait → countdown w/ abort → beginRound → Active cycle → eliminate → Ended → reset → loop) → T7 `start`/`runCountdown`/`beginRound`/`runActivePhase`/`endRound`. ✓
- Swap roster = alive set → T7 `aliveRoster`/`doSwap`; gating to Active via `runActivePhase` loop guard. ✓
- Coordination invariant (roster = alive controllers) → T7 builds roster from `RoundState.isAlive`. ✓
- Disconnect handling (RoundState.removePlayer + ControlManager.removePlayer) → T7 `removePlayer`. ✓
- Void death source (≈10 Hz monitor, `Y < VOID_Y`, only while Active) → T7 `startMonitor`/`stopMonitor`. ✓
- Logical elimination + park (no `Health = 0`) → T7 `eliminate` + T4 `parkBody`. ✓
- `Humanoid.Died` extensibility hook — *intentionally deferred*: the spec frames it as wiring for *future* health-based hazards and states the spine never triggers it. Not wired in this plan to avoid dead code; `RoundManager.eliminate` is the documented single entry point future hazards call. (Noted here so it's a conscious omission, not a gap.)
- Remotes + payloads (`RoundStateChanged {phase,secondsRemaining,aliveCount,winnerName}`, `EliminationEvent playerName`, `SpectateBody body`) → T3 register, T7 fire, T9 consume — payload shapes match across producer/consumer. ✓
- Client display (centered text + spectator retarget, no ownership) → T9. ✓
- Round reset = revive-free reposition + reset control to own bodies → T7 `beginRound` (resetControl + resetBody), T4 `resetBody`. ✓
- Testing: pure `resetControl` lune test (T1); 2-client Studio smoke test (T10 doc + T11 run). ✓
- Files touched list in spec → all have tasks: RoundManager (T7), init.server (T8), SwapController (T5), ControlManager (T6), BodyManager (T4), ControlModel (T1), Config (T2), Remotes (T3), client (T9), control_model.spec (T1), CHANGELOG + smoke doc (T10). ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command shows expected output. ✓

**Type consistency:**
- `ControlModel.resetControl(model)` returns `{ player, body }` array — consumed by `ControlManager.resetControl` (T6) iterating `pair.player`/`pair.body`. ✓
- `ControlManager.resetControl()` takes no args (uses module-level `model`), matching the `applyOwnership` signature `(player, body, isSwap)` already in the file. ✓
- `SwapController.swap(orderedAlive)` returns `ok, msg` — `RoundManager.doSwap` consumes both. ✓
- `BodyManager.resetBody(player)` vs `BodyManager.parkBody(body)` — distinct signatures used correctly: `beginRound` calls `resetBody(p)` (player), `eliminate` calls `parkBody(body)` (instance). ✓
- `RoundManager.eliminate/addPlayer/removePlayer/forceSwap/start` — names match `init.server` calls (T8) and the void monitor. ✓
- `RoundStateChanged` payload keys (`phase`, `secondsRemaining`, `aliveCount`, `winnerName`) identical in `broadcastState` (T7) and `ClientRoundHud` (T9). ✓
- `RoundState` API used (`new`, `addPlayer`, `canStart`, `beginRound`, `isAlive`, `aliveCount`, `eliminate`, `removePlayer`, `getPhase`, `getWinner`, `reset`) all exist in the shipped pure module. ✓
