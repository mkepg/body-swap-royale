# Post-Swap Grace Window Implementation Plan

**Goal:** Add a post-swap grace window so an inherited body cannot die from hazards for a short window after each swap, giving the player a beat to orient.

**Architecture:** A new pure, time-injected, lune-tested `GraceModel` holds per-player grace state and the `canDieFromHazard` predicate (TDD §2). Thin glue in `RoundManager` owns the real clock (`os.clock()`), stamps grace on each swap, derives the "has moved" signal from observed horizontal displacement inside the existing void monitor, and routes the void death (and any future hazard) through a single `eliminateFromHazard` gate that consults the model before eliminating.

**Tech Stack:** Luau (Roblox), Rojo project layout (`src/shared`, `src/server`), lune for terminal unit tests of pure modules.

**Spec:** [docs/specs/2026-06-18-grace-window-design.md](../specs/2026-06-18-grace-window-design.md)

---

## File Structure

- **Create** `src/shared/GraceModel.luau` — pure grace state machine (`new`, `onSwap`, `markMoved`, `canDieFromHazard`, `clear`). No Roblox APIs; no clock reads. Single responsibility: the grace decision.
- **Create** `tests/grace_model.spec.luau` — lune test for `GraceModel`, following the `do`-block / `expect`/`fail` pattern in `tests/control_model.spec.luau`.
- **Modify** `src/shared/Config.luau` — add `GRACE_MOVE_EPSILON`.
- **Modify** `src/server/RoundManager.luau` — require/instantiate `GraceModel`; add `now()`; stamp grace + capture swap-time positions in `doSwap`; sample horizontal displacement → `markMoved` and gate the void kill in the monitor; add `eliminateFromHazard`; clear grace in `eliminate` and `removePlayer`.
- **Modify** `CHANGELOG.md`, `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md`, `docs/body-swap-royale-tdd.md`, `docs/body-swap-royale-gdd.md` — docs/status.

> **Note on test coverage:** `GraceModel` is pure and fully lune-tested (Task 1). The `RoundManager` glue (Task 3) is Roblox-runtime behavior lune cannot reach — it is verified by code-grep checks here and by the manual 2-client Studio smoke test (Task 4), matching the established split for this project.

---

## Task 1: Pure `GraceModel` module (TDD)

**Files:**
- Create: `src/shared/GraceModel.luau`
- Test: `tests/grace_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/grace_model.spec.luau`:

```lua
local GraceModel = require("../src/shared/GraceModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local GRACE = 1.5
local FLOOR = 0.5

-- no entry: a player who never swapped can always die from a hazard.
do
	local m = GraceModel.new()
	expect(GraceModel.canDieFromHazard(m, "A", 100) == true, "no entry must allow death")
	print("grace: no entry -> can die OK")
end

-- within the floor: protected, and protected EVEN IF moved (floor is unconditional).
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 0) == false, "t=0 within floor must protect")
	expect(GraceModel.canDieFromHazard(m, "A", 0.4) == false, "t<floor must protect")
	GraceModel.markMoved(m, "A")
	expect(GraceModel.canDieFromHazard(m, "A", 0.4) == false, "floor protects even after moving")
	print("grace: hard floor (unconditional) OK")
end

-- after floor, before graceUntil, not moved: still protected.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 1.0) == false, "in grace, not moved -> protected")
	print("grace: in-window, not moved -> protected OK")
end

-- after floor, before graceUntil, moved: early exit -> can die.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	GraceModel.markMoved(m, "A")
	expect(GraceModel.canDieFromHazard(m, "A", 1.0) == true, "moved past floor -> can die (early exit)")
	print("grace: early exit on movement OK")
end

-- at/after graceUntil, not moved: window expired -> can die.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 1.5) == true, "at graceUntil -> can die")
	expect(GraceModel.canDieFromHazard(m, "A", 2.0) == true, "after graceUntil -> can die")
	print("grace: window expiry -> can die OK")
end

-- markMoved on an unknown player is a harmless no-op.
do
	local m = GraceModel.new()
	GraceModel.markMoved(m, "ghost") -- must not error
	expect(GraceModel.canDieFromHazard(m, "ghost", 0) == true, "unknown player has no grace")
	print("grace: markMoved no-op on unknown OK")
end

-- clear: removes the entry, so canDieFromHazard returns true again.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 0) == false, "precondition: protected")
	GraceModel.clear(m, "A")
	expect(GraceModel.canDieFromHazard(m, "A", 0) == true, "cleared -> can die")
	print("grace: clear OK")
end

print("ALL GRACEMODEL TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/grace_model.spec.luau`
Expected: FAIL — the require of `../src/shared/GraceModel` errors because the module does not exist yet (e.g. "module not found" / cannot open file).

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/GraceModel.luau`:

```lua
--[[
	GraceModel -- PURE post-swap grace state.
	Location (Roblox): ReplicatedStorage/Shared/GraceModel  (ModuleScript)

	Time-agnostic, like RoundState (takes thresholds) and ControlModel (takes
	randint): it never reads a clock. The glue passes `now` and the grace
	durations in. Holds per-player { graceUntil, graceMinFloor, hasMoved } and
	answers the single question a hazard asks before eliminating a player:
	canDieFromHazard. Keys are opaque (Player instances in production, strings in
	tests).

	Decision (TDD §2 Grace Window Logic):
	  no entry                          -> can die (no grace; e.g. round-start spawn)
	  now < graceMinFloor               -> protected (hard floor, checked first)
	  now < graceUntil and not hasMoved -> protected (still orienting)
	  otherwise                         -> can die
--]]

local GraceModel = {}

function GraceModel.new()
	return {
		byPlayer = {}, -- [player] = { graceUntil, graceMinFloor, hasMoved }
	}
end

-- Stamp a fresh grace window for `player` at time `now`. Called on each swap.
function GraceModel.onSwap(model, player, now, graceSeconds, floorSeconds)
	model.byPlayer[player] = {
		graceUntil = now + graceSeconds,
		graceMinFloor = now + floorSeconds,
		hasMoved = false,
	}
end

-- The player has oriented (started moving). No-op if no grace entry exists.
function GraceModel.markMoved(model, player)
	local g = model.byPlayer[player]
	if g then
		g.hasMoved = true
	end
end

-- May this player's body be eliminated by a hazard right now?
function GraceModel.canDieFromHazard(model, player, now)
	local g = model.byPlayer[player]
	if not g then
		return true
	end
	if now < g.graceMinFloor then
		return false -- hard floor: always protected briefly, even if moved
	end
	if now < g.graceUntil and not g.hasMoved then
		return false -- still in grace, hasn't oriented yet
	end
	return true
end

-- Drop a player's grace entry (on elimination / disconnect).
function GraceModel.clear(model, player)
	model.byPlayer[player] = nil
end

return GraceModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/grace_model.spec.luau`
Expected: PASS — prints each `grace: ... OK` line and finally `ALL GRACEMODEL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/GraceModel.luau tests/grace_model.spec.luau
git commit -m "$(cat <<'EOF'
feat: pure GraceModel (post-swap grace decision)

Time-injected per-player grace state + canDieFromHazard predicate
(TDD §2): unconditional floor first, then in-window-and-not-moved.
Lune-tested.
EOF
)"
```

---

## Task 2: Config tunable `GRACE_MOVE_EPSILON`

**Files:**
- Modify: `src/shared/Config.luau` (after the existing `Config.GRACE_FLOOR_SECONDS` line)

- [ ] **Step 1: Add the constant**

In `src/shared/Config.luau`, find:

```lua
Config.GRACE_SECONDS = 1.5
Config.GRACE_FLOOR_SECONDS = 0.5
```

Replace with:

```lua
Config.GRACE_SECONDS = 1.5
Config.GRACE_FLOOR_SECONDS = 0.5
-- Horizontal studs of displacement since the last swap that counts as the player
-- having "oriented", ending the post-swap grace window early (the
-- GRACE_FLOOR_SECONDS hard floor still applies first). At WALK_SPEED (16) a body
-- covers ~1.6 studs per 0.1s monitor tick, so 0.5 detects intentional movement
-- quickly while ignoring sampling jitter. Vertical fall does not count.
Config.GRACE_MOVE_EPSILON = 0.5
```

- [ ] **Step 2: Verify the value is present**

Run: `grep -n "GRACE_MOVE_EPSILON" src/shared/Config.luau`
Expected: one match showing `Config.GRACE_MOVE_EPSILON = 0.5`.

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "$(cat <<'EOF'
feat: add Config.GRACE_MOVE_EPSILON

Horizontal displacement threshold that ends the post-swap grace window
early once the player has oriented.
EOF
)"
```

---

## Task 3: Wire grace into `RoundManager` glue

**Files:**
- Modify: `src/server/RoundManager.luau`

All edits are exact string replacements against the current file.

- [ ] **Step 1: Require GraceModel**

Find:

```lua
local Config = require(ReplicatedStorage.Shared.Config)
local RoundState = require(ReplicatedStorage.Shared.RoundState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
```

Replace with:

```lua
local Config = require(ReplicatedStorage.Shared.Config)
local RoundState = require(ReplicatedStorage.Shared.RoundState)
local GraceModel = require(ReplicatedStorage.Shared.GraceModel)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
```

- [ ] **Step 2: Add grace state + clock helper**

Find:

```lua
local RoundManager = {}
local model = RoundState.new(Config.MIN_PLAYERS_TO_START, Config.MIN_PLAYERS_TO_CONTINUE)
```

Replace with:

```lua
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
```

- [ ] **Step 3: Stamp grace + capture swap-time positions in `doSwap`**

Find:

```lua
local function doSwap()
	local roster = aliveRoster()
	if #roster >= 2 then
		local ok, msg = SwapController.swap(roster)
		print("[BSR] swap:", ok, msg)
	end
end
```

Replace with:

```lua
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
```

- [ ] **Step 4: Add the `eliminateFromHazard` gate and clear grace in `eliminate`**

Find:

```lua
	EliminationEvent:FireAllClients(player.Name)
	resendSpectate()
	return result
end
```

Replace with:

```lua
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
```

- [ ] **Step 5: Sample movement and gate the void kill in the monitor**

Find:

```lua
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
```

Replace with:

```lua
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
```

- [ ] **Step 6: Clear grace on disconnect in `removePlayer`**

Find:

```lua
function RoundManager.removePlayer(player)
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	ControlManager.removePlayer(player)    -- absorb + destroy the leaver's own body
	if RoundState.getPhase(model) == "Active" then
		resendSpectate() -- the alive set may have shrunk
	end
```

Replace with:

```lua
function RoundManager.removePlayer(player)
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	ControlManager.removePlayer(player)    -- absorb + destroy the leaver's own body
	GraceModel.clear(grace, player)
	swapPos[player] = nil
	if RoundState.getPhase(model) == "Active" then
		resendSpectate() -- the alive set may have shrunk
	end
```

- [ ] **Step 7: Verify the wiring is present and consistent**

Run: `grep -n "GraceModel\.\|eliminateFromHazard\|swapPos\|local function now" src/server/RoundManager.luau`
Expected matches (order may vary):
- `local GraceModel = require(...)`
- `local grace = GraceModel.new()`
- `local swapPos = {}`
- `local function now()`
- `GraceModel.onSwap(grace, player, t, ...)` in `doSwap`
- `GraceModel.markMoved(grace, player)` in the monitor
- `if root.Position.Y < Config.VOID_Y then` followed by `RoundManager.eliminateFromHazard(player)`
- `function RoundManager.eliminateFromHazard(player)` calling `GraceModel.canDieFromHazard(grace, player, now())`
- `GraceModel.clear(grace, player)` in both `eliminate` and `removePlayer`

Also confirm the void monitor no longer calls `RoundManager.eliminate` directly:
Run: `grep -n "RoundManager.eliminate(player)" src/server/RoundManager.luau`
Expected: the only match is **inside** `eliminateFromHazard` (the monitor itself calls `eliminateFromHazard`).

- [ ] **Step 8: Confirm the pure tests still pass (no shared-module breakage)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/grace_model.spec.luau && lune run tests/control_model.spec.luau`
Expected: both print their `ALL ... TESTS PASSED` lines. (This does not exercise `RoundManager`, which is Roblox-only; it confirms `GraceModel`/`ControlModel` still load and pass. Runtime behavior is verified by the smoke test in Task 4.)

- [ ] **Step 9: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "$(cat <<'EOF'
feat: gate hazard elimination behind the post-swap grace window

RoundManager now stamps a grace window on each swap, derives
HasMovedSinceSwap from horizontal travel in the void monitor, and routes
the void kill through eliminateFromHazard, which consults GraceModel
before eliminating. Disconnect elimination stays ungated. Clears grace
on eliminate/disconnect.
EOF
)"
```

---

## Task 4: Docs & status

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md`
- Modify: `docs/body-swap-royale-tdd.md`
- Modify: `docs/body-swap-royale-gdd.md`

- [ ] **Step 1: CHANGELOG — add the grace entry**

In `CHANGELOG.md`, find the start of the `### Added` list under `## [Unreleased]`:

```
### Added
- `src/server/RoundManager.luau` — server glue driving the MVP win/lose loop:
```

Insert these two bullets immediately after `### Added` (before the `RoundManager` bullet):

```
- `src/shared/GraceModel.luau` — pure, Roblox-free post-swap grace state machine
  (per-player `graceUntil`/`graceMinFloor`/`hasMoved` + `canDieFromHazard`,
  TDD §2). Time-agnostic like `RoundState`/`ControlModel`; unit tested with lune
  (`tests/grace_model.spec.luau`).
- `Config.GRACE_MOVE_EPSILON` — horizontal displacement that ends the grace window
  early once the player has oriented.
```

Then, in the `### Changed` list of the same file, add this bullet at the end:

```
- `src/server/RoundManager.luau` — routes the void death through a new
  `eliminateFromHazard` gate that consults `GraceModel` (stamped on each swap),
  and derives `HasMovedSinceSwap` from horizontal travel in the void monitor.
  Inherited bodies are protected from hazard death for the post-swap grace window
  (GDD §4). Disconnect elimination remains ungated.
```

- [ ] **Step 2: Smoke test — add the grace procedure**

In `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md`, find step 6 and the trailing paragraph:

```
6. **Disconnect win.** In a fresh round, kick one player from the Server command bar:
   `game.Players:GetPlayers()[1]:Kick("test")`. The round ends with the remaining
   player as winner; their controlled body is never yanked (absorb rule still holds).

Bodies are named `Body_<UserId>` under `workspace.Bodies`; players have no
`Character` (`CharacterAutoLoads = false`).
```

Replace with:

```
6. **Disconnect win.** In a fresh round, kick one player from the Server command bar:
   `game.Players:GetPlayers()[1]:Kick("test")`. The round ends with the remaining
   player as winner; their controlled body is never yanked (absorb rule still holds).
7. **Grace protects after a swap.** Set `C.VOID_Y = 0` so a small drop kills. First,
   *before* any swap, walk a body below Y=0 → it is eliminated immediately (baseline:
   round-start spawn has no grace). Then in a fresh round, `forceSwap()` and
   *immediately* walk/drop that body below Y=0: it is **not** eliminated for ~1.5s
   (`Config.GRACE_SECONDS`), then is eliminated and parked when the window expires.
   The contrast with the baseline is the proof the grace gate works.
8. **Grace early-exit on movement.** `forceSwap()`, move a body horizontally more than
   `Config.GRACE_MOVE_EPSILON` (a step or two) to orient, then drop it below Y=0:
   it is eliminated promptly (the window ended on movement), not after the full ~1.5s.

Bodies are named `Body_<UserId>` under `workspace.Bodies`; players have no
`Character` (`CharacterAutoLoads = false`).
```

- [ ] **Step 3: TDD — flip grace status from 🟡 to 🟢**

In `docs/body-swap-royale-tdd.md`:

(a) Find the §2 heading:

```
### Grace Window Logic *(🟡 designed, not implemented)*
```

Replace with:

```
### Grace Window Logic *(🟢 implemented — `src/shared/GraceModel.luau`)*
```

(b) Find the paragraph after the §2 grace pseudocode:

```
The constants exist (`Config.GRACE_SECONDS = 1.5`, `Config.GRACE_FLOOR_SECONDS = 0.5`) but no hazard/elimination path consumes them yet. `HasMovedSinceSwap` must be derived server-side from observed position change on the client-owned body (the server already needs this signal for movement validation).
```

Replace with:

```
This logic is implemented in the pure `GraceModel` (time-injected, lune-tested). `RoundManager` stamps a window on each swap (`Config.GRACE_SECONDS = 1.5`, `Config.GRACE_FLOOR_SECONDS = 0.5`) and routes the void death through `RoundManager.eliminateFromHazard`, which consults `GraceModel.canDieFromHazard` before eliminating. `HasMovedSinceSwap` is derived server-side from observed **horizontal** position change on the client-owned body (vertical fall does not count, per GDD §4), sampled in the void monitor against the body's swap-time position; the threshold is `Config.GRACE_MOVE_EPSILON`. The client-side grace visual (shield shimmer + Soul pulse) is deferred to the Soul/VFX work.
```

(c) Find the §10 MVP checklist line:

```
- [ ] 🟡 Post-swap grace window (1.5s) — *`GRACE_SECONDS`/`GRACE_FLOOR_SECONDS` defined; no `CanDieFromHazard`*
```

Replace with:

```
- [x] 🟢 Post-swap grace window (1.5s) — *`GraceModel.canDieFromHazard` + `RoundManager.eliminateFromHazard` gate; server-only (visual deferred)*
```

(d) Find in §10 "Prioritized Implementation Order", Priority 1:

```
**Priority 1 (Cannot ship without):** core swap mechanic 🟢 · swap preview 🟡 · post-swap grace window 🟡 · free Soul halo 🟡
```

Replace with:

```
**Priority 1 (Cannot ship without):** core swap mechanic 🟢 · swap preview 🟡 · post-swap grace window 🟢 · free Soul halo 🟡
```

- [ ] **Step 4: GDD — flip the feature-inventory status**

In `docs/body-swap-royale-gdd.md`, find:

```
3. 🟡 Post-swap grace window (1.5s) *(v1.1 — `GRACE_SECONDS` defined, behavior not built)*
```

Replace with:

```
3. 🟢 Post-swap grace window (1.5s) *(v1.1 — `GraceModel` + `RoundManager.eliminateFromHazard` gate; client visual deferred)*
```

- [ ] **Step 5: Verify the status flips landed**

Run: `grep -rn "Post-swap grace window" docs/body-swap-royale-gdd.md docs/body-swap-royale-tdd.md`
Expected: the GDD inventory line and the TDD §10 line both show 🟢 (no remaining 🟡 on a "post-swap grace window" line).

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md docs/smoke-tests/2026-06-18-round-loop-smoke-test.md docs/body-swap-royale-tdd.md docs/body-swap-royale-gdd.md
git commit -m "$(cat <<'EOF'
docs: record post-swap grace window (status 🟡→🟢)

CHANGELOG + smoke-test grace procedure; flip grace status in GDD
inventory and TDD §2/§10.
EOF
)"
```

---

## Done criteria

- `lune run tests/grace_model.spec.luau` passes (and `control_model.spec.luau` still passes).
- The void monitor calls `RoundManager.eliminateFromHazard` (never `eliminate` directly); `eliminateFromHazard` consults `GraceModel.canDieFromHazard`.
- Grace is stamped on swaps only; movement is horizontal-only; grace is cleared on eliminate and disconnect.
- Docs/status updated; CHANGELOG reflects the new module + gate.
- Manual 2-client Studio smoke test (Task 4 steps 7–8) confirms a post-swap void-drop survives the window while a pre-swap drop dies immediately. *(Run by the user; not automatable here.)*
