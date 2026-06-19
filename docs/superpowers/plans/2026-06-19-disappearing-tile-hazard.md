# Disappearing Tile Hazard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the MVP arena floor into a grid of disappearing tiles (`solid → warning → gone → solid`) so a body standing on a vanishing tile falls through and is eliminated, giving the arena real telegraphed danger and exercising the post-swap grace window through a second source.

**Architecture:** A new pure, time-injected, lune-tested `TileFieldModel` decides one thing — a tile's phase at a given time. A new server-glue module `HazardSystem` builds the tile grid procedurally at runtime (replacing the baseplate) and a token-gated loop maps each tile's phase to part properties (`Color`/`Transparency`/`CanCollide`), which replicate to clients for free. Death is purely geometric and reuses the existing void monitor: `VOID_Y` is raised to just under the tiles, so falling through a `gone` tile crosses it in ~0.6s and routes through the already-built grace-gated `RoundManager.eliminateFromHazard`. No new death code.

**Tech Stack:** Luau (Roblox), Rojo project layout (`src/shared`, `src/server`), lune for terminal unit tests of pure modules.

**Spec:** [docs/superpowers/specs/2026-06-19-disappearing-tile-hazard-design.md](../specs/2026-06-19-disappearing-tile-hazard-design.md)

---

## File Structure

- **Create** `src/shared/TileFieldModel.luau` — pure phase decision (`phaseAt`, `offsetFor`). No Roblox APIs, no clock reads, no RNG. Single responsibility: a tile's phase.
- **Create** `tests/tile_field_model.spec.luau` — lune test for `TileFieldModel`, following the `do`-block / `expect`/`fail` pattern in `tests/grace_model.spec.luau`.
- **Create** `src/server/HazardSystem.luau` — server glue: `build()` (remove baseplate, construct the tile grid once, store per-tile offsets), `start(startTime)` (force solid + run the apply loop), `stop()` (kill loop + force solid). Owns all Roblox APIs the hazard touches.
- **Modify** `src/shared/Config.luau` — add tile tunables (timing, grid, geometry, colors); raise `VOID_Y` from `-50` to `-4`.
- **Modify** `src/server/RoundManager.luau` — require `HazardSystem`; `start()` calls `build()` once; `beginRound()` calls `start(now())`; `endRound()` calls `stop()`.
- **Modify** `default.project.json` — remove the `Baseplate` instance (the tile field is the floor now).
- **Modify** `CHANGELOG.md`, `docs/body-swap-royale-gdd.md`, `docs/body-swap-royale-tdd.md` — status updates.
- **Create** `docs/smoke-tests/2026-06-19-disappearing-tile-smoke-test.md` — manual 2-client runtime procedure.

> **Note on test coverage:** `TileFieldModel` is pure and fully lune-tested (Task 1). `HazardSystem` and the `RoundManager`/geometry wiring are Roblox-runtime behavior lune cannot reach (parts, collision, physics, replication) — verified by code-grep checks here and by the manual 2-client Studio smoke test (Task 6), matching the established split for this project.

> **Refinement from the spec:** the spec's data-flow sketched `init.server` calling `HazardSystem.build()`. The plan calls it from `RoundManager.start()` instead, leaving `init.server` untouched. RoundManager already owns the other Roblox-side systems (`BodyManager`/`ControlManager`/`SwapController`) and `init.server` is deliberately thin (it only routes join/leave and calls `RoundManager.start()`). The spec's intent — build the arena once at startup, before the first round — is preserved.

> **Test runner:** lune tests run from the repo root with `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>` (a `.spec.luau` requires the module via a relative path, e.g. `require("../src/shared/TileFieldModel")`).

---

## Task 1: Pure `TileFieldModel` module (TDD)

**Files:**
- Create: `src/shared/TileFieldModel.luau`
- Test: `tests/tile_field_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/tile_field_model.spec.luau`:

```lua
local TileFieldModel = require("../src/shared/TileFieldModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local DUR = { solid = 4, warning = 2, gone = 1.5 } -- period = 7.5
local PERIOD = DUR.solid + DUR.warning + DUR.gone

-- offset 0: walk a single period across every boundary.
do
	local function phase(t)
		return TileFieldModel.phaseAt(t, 0, 0, DUR)
	end
	expect(phase(0) == "solid", "t=0 must be solid")
	expect(phase(3.999) == "solid", "just before solid end must be solid")
	expect(phase(4) == "warning", "at solid end must be warning")
	expect(phase(5.999) == "warning", "just before warning end must be warning")
	expect(phase(6) == "gone", "at warning end must be gone")
	expect(phase(7.499) == "gone", "just before period end must be gone")
	expect(phase(7.5) == "solid", "at period wrap must be solid again")
	print("tile: phase boundaries (offset 0) OK")
end

-- a non-zero offset shifts the timeline by exactly `offset`.
do
	local a = TileFieldModel.phaseAt(2, 0, 1, DUR) -- (2 - 0 + 1) = 3
	local b = TileFieldModel.phaseAt(3, 0, 0, DUR) -- (3 - 0 + 0) = 3
	expect(a == b, "offset must shift the timeline by exactly offset")
	print("tile: offset shift OK")
end

-- round-start safety: at now == roundStart, every offset in [0, solid) is solid.
do
	for i = 0, 39 do
		local offset = (i / 40) * DUR.solid -- spans [0, solid)
		local p = TileFieldModel.phaseAt(100, 100, offset, DUR)
		expect(p == "solid", "offset in [0, solid) must be solid at roundStart")
	end
	print("tile: round-start all-solid invariant OK")
end

-- monotonic progression solid -> warning -> gone -> solid within one period.
do
	local seen = {}
	local order = {}
	local prev = nil
	for k = 0, 75 do
		local t = (k / 75) * PERIOD
		local p = TileFieldModel.phaseAt(t, 0, 0, DUR)
		if p ~= prev then
			order[#order + 1] = p
			prev = p
		end
		seen[p] = true
	end
	expect(seen.solid and seen.warning and seen.gone, "all three phases must appear")
	expect(order[1] == "solid" and order[2] == "warning" and order[3] == "gone",
		"phases must progress solid -> warning -> gone")
	print("tile: monotonic progression OK")
end

-- offsetFor: deterministic, and always in [0, solid).
do
	local o1 = TileFieldModel.offsetFor(3, 5, DUR.solid)
	local o2 = TileFieldModel.offsetFor(3, 5, DUR.solid)
	expect(o1 == o2, "offsetFor must be deterministic for the same coords")
	for row = 0, 7 do
		for col = 0, 7 do
			local o = TileFieldModel.offsetFor(row, col, DUR.solid)
			expect(o >= 0 and o < DUR.solid, "offsetFor must be in [0, solid)")
		end
	end
	print("tile: offsetFor determinism + range OK")
end

print("ALL TileFieldModel TESTS PASSED")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/tile_field_model.spec.luau`
Expected: FAIL — the module does not exist yet (require error like `Tried to require nonexistent file` / module not found).

- [ ] **Step 3: Write minimal implementation**

Create `src/shared/TileFieldModel.luau`:

```lua
--[[
	TileFieldModel (shared) -- pure, time-injected decision for a disappearing-tile
	floor. Answers exactly one question: what phase is a tile in right now?
	("solid" | "warning" | "gone"). Knows nothing about Roblox parts, collision,
	color, or death -- the server glue (HazardSystem) maps phase -> part properties,
	and death stays geometric (fall-through -> the existing void monitor).

	Pure like RoundState / GraceModel: no clock reads, no RNG; lune-tested.
--]]

local TileFieldModel = {}

-- Phase of a single tile at time `now`, given the round's start time and the
-- tile's fixed phase offset. durations = { solid, warning, gone } in seconds.
function TileFieldModel.phaseAt(now, roundStart, offset, durations)
	local period = durations.solid + durations.warning + durations.gone
	local t = (now - roundStart + offset) % period
	if t < durations.solid then
		return "solid"
	elseif t < durations.solid + durations.warning then
		return "warning"
	else
		return "gone"
	end
end

-- Deterministic per-tile phase offset in [0, solid). Same coords -> same value
-- every round, so the floor is solid at roundStart and the drop pattern is
-- learnable. Pure hash (no RNG, no bitops) -- behaves identically in lune and
-- Roblox.
function TileFieldModel.offsetFor(row, col, solid)
	local h = math.sin(row * 12.9898 + col * 78.233) * 43758.5453
	local frac = h - math.floor(h) -- pseudo-random in [0, 1)
	return frac * solid
end

return TileFieldModel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/tile_field_model.spec.luau`
Expected: PASS — ends with `ALL TileFieldModel TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/TileFieldModel.luau tests/tile_field_model.spec.luau
git commit -m "feat: pure TileFieldModel (disappearing-tile phase decision)"
```

---

## Task 2: `Config` tunables + raised `VOID_Y`

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Raise `VOID_Y` and update its comment**

In `src/shared/Config.luau`, replace this block:

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

with:

```lua
-- RoundManager loop tunables (server-owned clocks + the void death source).
-- LOBBY_COUNTDOWN_SECONDS: pre-round countdown once enough players are present.
-- ROUND_END_SECONDS: winner-display window before resetting to Lobby.
-- VOID_Y: a controlled body whose root falls below this Y is eliminated. With the
-- disappearing-tile floor (TILE_SURFACE_Y = 0), this sits a few studs under the
-- tile bottoms, so falling through a `gone` tile crosses it in ~0.6s -- quick
-- enough for the post-swap grace window (1.5s) to protect a freshly-swapped body.
-- Still far above Workspace.FallenPartsDestroyHeight (default -500).
Config.LOBBY_COUNTDOWN_SECONDS = 5
Config.ROUND_END_SECONDS = 5
Config.VOID_Y = -4
```

- [ ] **Step 2: Add the tile tunables**

In `src/shared/Config.luau`, immediately after the `Config.VOID_Y = -4` line (and before the population-thresholds block), add:

```lua

-- Disappearing-tile hazard (the MVP arena floor). The pure TileFieldModel decides
-- each tile's phase from these durations; HazardSystem maps phase -> part props.
-- A tile cycles solid -> warning(red) -> gone(no collision) -> solid.
Config.TILE_SOLID_SECONDS = 4 -- standable time per cycle
Config.TILE_WARNING_SECONDS = 2 -- red telegraph (GDD §5: "red 2s before")
Config.TILE_GONE_SECONDS = 1.5 -- vanished (fall-through) window
-- Grid geometry. GRID_SIZE x GRID_SIZE tiles of TILE_SIZE studs each, centered on
-- the X/Z origin; top face at TILE_SURFACE_Y. 8x8 @ 8 studs = a 64x64 arena.
Config.TILE_GRID_SIZE = 8
Config.TILE_SIZE = 8
Config.TILE_SURFACE_Y = 0
Config.TILE_THICKNESS = 1
Config.TILE_COLOR_SOLID = Color3.fromRGB(150, 150, 150) -- neutral grey
Config.TILE_COLOR_WARNING = Color3.fromRGB(200, 40, 40) -- alarm red
```

- [ ] **Step 3: Sanity-check the file loads (no syntax error)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/grace_model.spec.luau`
Expected: PASS (unchanged). This doesn't import `Config`, but running an existing suite confirms the toolchain is healthy after the edit. (`Config` itself uses `Color3`, a Roblox global, so it is not directly lune-loadable — it is exercised at runtime in Task 6.)

- [ ] **Step 4: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat: add tile-hazard tunables; raise VOID_Y to the tile kill plane"
```

---

## Task 3: `HazardSystem` server glue

**Files:**
- Create: `src/server/HazardSystem.luau`

> Not lune-testable (touches `workspace`, parts, `task.spawn`). Verified by Task 6's smoke test and the code-grep step below.

- [ ] **Step 1: Write the module**

Create `src/server/HazardSystem.luau`:

```lua
--[[
	HazardSystem (server) -- the disappearing-tile floor (the MVP arena).
	Builds the tile grid once, then drives each tile's appearance + collision from
	the pure TileFieldModel during Active rounds.

	Death is NOT handled here. A body over a `gone` (CanCollide=false) tile falls
	past Config.VOID_Y and is eliminated by the existing void monitor in
	RoundManager -- grace-gated, no new death path.

	Lifecycle (called by RoundManager):
	  build()           -- once at startup: replace the baseplate, construct tiles
	  start(startTime)  -- beginRound: force solid + spin the apply loop
	  stop()            -- endRound: kill the loop + force solid

	Depends on: ReplicatedStorage.Shared.Config / TileFieldModel
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local TileFieldModel = require(ReplicatedStorage.Shared.TileFieldModel)

local HazardSystem = {}

local tiles = {} -- array of { part = Part, offset = number, phase = string }
local folder = nil
local roundStart = 0

-- A unique token gates the apply loop; setting it to a new value (or nil) stops
-- any previously-running loop (same pattern as RoundManager's void monitor).
local loopToken = nil

local function durations()
	return {
		solid = Config.TILE_SOLID_SECONDS,
		warning = Config.TILE_WARNING_SECONDS,
		gone = Config.TILE_GONE_SECONDS,
	}
end

-- Map a phase to a tile part's properties. Caller applies only on change.
local function applyPhase(part, phase)
	if phase == "solid" then
		part.CanCollide = true
		part.Transparency = 0
		part.Color = Config.TILE_COLOR_SOLID
	elseif phase == "warning" then
		part.CanCollide = true
		part.Transparency = 0
		part.Color = Config.TILE_COLOR_WARNING
	else -- "gone"
		part.CanCollide = false
		part.Transparency = 1
	end
end

local function forceAllSolid()
	for _, tile in ipairs(tiles) do
		tile.phase = "solid"
		applyPhase(tile.part, "solid")
	end
end

-- Build the tile grid once. The tile field IS the floor, so the baseplate is
-- removed. Idempotent-ish: safe to call once at startup.
function HazardSystem.build()
	local existing = workspace:FindFirstChild("Baseplate")
	if existing then
		existing:Destroy()
	end

	folder = workspace:FindFirstChild("TileField")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TileField"
		folder.Parent = workspace
	end

	local size = Config.TILE_GRID_SIZE
	local tileSize = Config.TILE_SIZE
	local span = size * tileSize
	-- Center the grid on the X/Z origin; first tile center is at -span/2 + half.
	local originOffset = -span / 2 + tileSize / 2
	-- Position so each tile's TOP face sits at TILE_SURFACE_Y.
	local centerY = Config.TILE_SURFACE_Y - Config.TILE_THICKNESS / 2

	for row = 0, size - 1 do
		for col = 0, size - 1 do
			local part = Instance.new("Part")
			part.Anchored = true
			part.Size = Vector3.new(tileSize, Config.TILE_THICKNESS, tileSize)
			part.Position = Vector3.new(
				originOffset + col * tileSize,
				centerY,
				originOffset + row * tileSize
			)
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Color = Config.TILE_COLOR_SOLID
			part.Name = string.format("Tile_%d_%d", row, col)
			part.Parent = folder
			tiles[#tiles + 1] = {
				part = part,
				offset = TileFieldModel.offsetFor(row, col, Config.TILE_SOLID_SECONDS),
				phase = "solid",
			}
		end
	end
end

-- Begin driving tiles for an Active round. startTime is the server clock value
-- captured by RoundManager at beginRound (os.clock()).
function HazardSystem.start(startTime)
	roundStart = startTime
	forceAllSolid()
	local token = {}
	loopToken = token
	task.spawn(function()
		local dur = durations()
		while loopToken == token do
			local now = os.clock()
			for _, tile in ipairs(tiles) do
				local phase = TileFieldModel.phaseAt(now, roundStart, tile.offset, dur)
				if phase ~= tile.phase then
					tile.phase = phase
					applyPhase(tile.part, phase)
				end
			end
			task.wait(0.1)
		end
	end)
end

-- Stop driving tiles and leave a clean, fully-solid floor (Lobby/Ended; parked
-- bodies rest on solid ground).
function HazardSystem.stop()
	loopToken = nil
	forceAllSolid()
end

return HazardSystem
```

- [ ] **Step 2: Verify the module parses and the API is present (code-grep)**

Run: `grep -nE "function HazardSystem\.(build|start|stop)" src/server/HazardSystem.luau`
Expected: three matches — `build`, `start(startTime)`, `stop`.

Run: `grep -n "FindFirstChild(\"Baseplate\")" src/server/HazardSystem.luau`
Expected: one match (the baseplate removal in `build`).

- [ ] **Step 3: Commit**

```bash
git add src/server/HazardSystem.luau
git commit -m "feat: HazardSystem server glue (build + drive the tile floor)"
```

---

## Task 4: Wire `HazardSystem` into the round loop

**Files:**
- Modify: `src/server/RoundManager.luau`

- [ ] **Step 1: Require `HazardSystem`**

In `src/server/RoundManager.luau`, find the server-module requires:

```lua
local BodyManager = require(script.Parent.BodyManager)
local ControlManager = require(script.Parent.ControlManager)
local SwapController = require(script.Parent.SwapController)
```

and add a line after them:

```lua
local BodyManager = require(script.Parent.BodyManager)
local ControlManager = require(script.Parent.ControlManager)
local SwapController = require(script.Parent.SwapController)
local HazardSystem = require(script.Parent.HazardSystem)
```

- [ ] **Step 2: Start the tile field at round start**

In `beginRound`, find:

```lua
	ControlManager.resetControl() -- everyone back on their own body (+ retarget)
	broadcastState() -- phase Active
	startMonitor()
	print("[BSR] round started")
```

and insert the `HazardSystem.start(now())` call so the field begins driving as the round goes Active:

```lua
	ControlManager.resetControl() -- everyone back on their own body (+ retarget)
	broadcastState() -- phase Active
	HazardSystem.start(now()) -- tile floor begins its cycles (solid at round start)
	startMonitor()
	print("[BSR] round started")
```

- [ ] **Step 3: Stop the tile field at round end**

In `endRound`, find:

```lua
local function endRound()
	stopMonitor()
	broadcastState() -- phase Ended (+ winnerName)
```

and add `HazardSystem.stop()`:

```lua
local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	broadcastState() -- phase Ended (+ winnerName)
```

- [ ] **Step 4: Build the arena once at startup**

In `RoundManager.start`, find:

```lua
function RoundManager.start()
	task.spawn(function()
		while true do
```

and build the tile field once before the loop spins (it depends only on `Config`/`TileFieldModel`, so it is safe at startup and the bodies spawn onto the solid floor):

```lua
function RoundManager.start()
	HazardSystem.build() -- construct the tile-field arena once (replaces the baseplate)
	task.spawn(function()
		while true do
```

- [ ] **Step 5: Verify the wiring (code-grep)**

Run: `grep -n "HazardSystem" src/server/RoundManager.luau`
Expected: four matches — the require, `HazardSystem.build()` in `start`, `HazardSystem.start(now())` in `beginRound`, `HazardSystem.stop()` in `endRound`.

- [ ] **Step 6: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat: drive the tile floor from the round loop (build/start/stop)"
```

---

## Task 5: Remove the baseplate from the project tree

**Files:**
- Modify: `default.project.json`

> `HazardSystem.build()` already destroys a runtime `Baseplate` defensively, but the Rojo tree still defines one. Removing it keeps the source of truth honest: the tile field is the only floor.

- [ ] **Step 1: Delete the `Baseplate` node**

In `default.project.json`, replace the `Workspace` block:

```json
    "Workspace": {
      "$properties": {
        "FilteringEnabled": true,
        "StreamingEnabled": false
      },
      "Baseplate": {
        "$className": "Part",
        "$properties": {
          "Anchored": true,
          "Color": [
            0.38823,
            0.37254,
            0.38823
          ],
          "Locked": true,
          "Position": [
            0,
            -10,
            0
          ],
          "Size": [
            512,
            20,
            512
          ]
        }
      }
    },
```

with:

```json
    "Workspace": {
      "$properties": {
        "FilteringEnabled": true,
        "StreamingEnabled": false
      }
    },
```

- [ ] **Step 2: Verify the JSON is valid and the baseplate is gone**

Run: `python -c "import json; json.load(open('default.project.json')); print('OK')"`
Expected: `OK`

Run: `grep -c "Baseplate" default.project.json`
Expected: `0`

- [ ] **Step 3: Commit**

```bash
git add default.project.json
git commit -m "chore: remove baseplate; the tile field is the arena floor"
```

---

## Task 6: Studio smoke test + status docs

**Files:**
- Create: `docs/smoke-tests/2026-06-19-disappearing-tile-smoke-test.md`
- Modify: `CHANGELOG.md`, `docs/body-swap-royale-gdd.md`, `docs/body-swap-royale-tdd.md`

- [ ] **Step 1: Write the smoke-test procedure**

Create `docs/smoke-tests/2026-06-19-disappearing-tile-smoke-test.md`:

```markdown
# Smoke Test — Disappearing Tile Hazard (2026-06-19)

Runtime behavior lune cannot cover: part construction, collision, physics
fall-through, property replication, and the hazard↔grace interaction. Run in
Roblox Studio with **2 players** (Play Solo gives 1; use Start > "Local Server"
with 2 players, or Team Test).

**Status:** ⬜ not yet validated

## Setup
1. Open the place in Studio, sync via Rojo.
2. Start a 2-player local server (Test > Clients and Servers > 2 players > Start).
3. Wait for the lobby countdown; the round goes Active.

## Checks

### 1. Arena is a tile floor, baseplate gone
- [ ] `Workspace` has a `TileField` folder with 64 `Tile_r_c` parts; no `Baseplate`.
- [ ] At round start the whole floor is solid grey (no red, no gaps).

### 2. Telegraph + vanish cycle
- [ ] Within a few seconds tiles begin turning **red** (warning), then **vanish**
      (transparent + non-collidable) for ~1.5s, then return to solid grey.
- [ ] Tiles do **not** all drop at once — they are staggered.

### 3. Fall-through elimination
- [ ] Stand a body on a tile and stay; when that tile vanishes the body falls
      through and (after crossing `VOID_Y = -4`) is eliminated — the
      `EliminationEvent` fires and the player's HUD shows elimination.
- [ ] The eliminated body is parked (anchored), not destroyed.

### 4. Grace protects a fresh swap (the second-source check)
- [ ] In the command bar run `require(game.ServerScriptService.Server.RoundManager).forceSwap()`
      to swap controls.
- [ ] If a player is swapped onto a tile that is `warning`/`gone`, they are NOT
      eliminated during the grace floor/window even as they fall a little — they
      get the beat to move to a neighbor tile. (Repeat `forceSwap()` a few times
      to land this case; grace is `GRACE_SECONDS = 1.5`, floor `0.5`.)

### 5. Round boundaries leave a clean floor
- [ ] When the round ends (one survivor), all tiles return to solid grey.
- [ ] The next round starts on a fully solid floor again.

## Result
Record the date validated and any tuning notes (tile rhythm, grid size, VOID_Y).
```

- [ ] **Step 2: Update the CHANGELOG**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add these bullets at the top of the `Added` list:

```markdown
- `src/shared/TileFieldModel.luau` — pure, Roblox-free disappearing-tile phase
  decision (`phaseAt` → `solid`/`warning`/`gone`, deterministic `offsetFor`).
  Time-agnostic like `RoundState`/`GraceModel`; unit tested with lune
  (`tests/tile_field_model.spec.luau`).
- `src/server/HazardSystem.luau` — server glue building the MVP tile-field arena
  (replaces the baseplate) and driving each tile's color/transparency/collision
  from `TileFieldModel` during Active rounds. Death reuses the existing void
  monitor (no new death path); grace gates it automatically.
- `Config` tile tunables (`TILE_SOLID_SECONDS`, `TILE_WARNING_SECONDS`,
  `TILE_GONE_SECONDS`, `TILE_GRID_SIZE`, `TILE_SIZE`, `TILE_SURFACE_Y`,
  `TILE_THICKNESS`, `TILE_COLOR_SOLID`, `TILE_COLOR_WARNING`).
```

Then, if a `### Changed` subsection exists under `## [Unreleased]`, add the bullet there; otherwise add a `### Changed` subsection after `### Added` with it:

```markdown
- `Config.VOID_Y` raised from `-50` to `-4` so it sits just under the tile floor;
  falling through a vanished tile is now a quick, grace-protectable death.
- Removed the `Baseplate` from `default.project.json`; the tile field is the floor.
```

- [ ] **Step 3: Update the GDD feature-inventory status**

In `docs/body-swap-royale-gdd.md`, replace line 961:

```markdown
8. 🟡 Disappearing tile hazard *(no hazards implemented)*
```

with:

```markdown
8. 🟢 Disappearing tile hazard *(v1.1 — pure `TileFieldModel` + `HazardSystem`; full tile-field arena, death via the existing grace-gated void monitor; visuals are flat colors, polish deferred)*
```

- [ ] **Step 4: Update the TDD status rows**

In `docs/body-swap-royale-tdd.md`, replace line 93:

```markdown
| HazardSystem | Spawns and updates environmental dangers | 🟡 |
```

with:

```markdown
| HazardSystem | Spawns and updates environmental dangers | 🟢 `HazardSystem.luau` (disappearing-tile floor; phase logic in pure `TileFieldModel`) |
```

Then replace line 641:

```markdown
- [ ] 🟡 One arena map with basic hazards — *only a baseplate exists*
```

with:

```markdown
- [x] 🟢 One arena map with basic hazards — *full disappearing-tile floor (`HazardSystem` + `TileFieldModel`); baseplate replaced*
```

- [ ] **Step 5: Verify the doc edits landed**

Run: `grep -n "🟢 Disappearing tile hazard" docs/body-swap-royale-gdd.md`
Expected: one match.

Run: `grep -nE "HazardSystem.luau|full disappearing-tile floor" docs/body-swap-royale-tdd.md`
Expected: two matches (the systems-table row and the MVP-scope row).

- [ ] **Step 6: Commit**

```bash
git add docs/smoke-tests/2026-06-19-disappearing-tile-smoke-test.md CHANGELOG.md docs/body-swap-royale-gdd.md docs/body-swap-royale-tdd.md
git commit -m "docs: smoke test + status for the disappearing tile hazard"
```

---

## Final verification

- [ ] **All lune tests pass**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f"; done`
Expected: every suite ends with its `ALL ... PASSED` line; no `ASSERTION FAILED`.

- [ ] **Run the Studio smoke test** in `docs/smoke-tests/2026-06-19-disappearing-tile-smoke-test.md` and record the result (flip the status from ⬜ to 🟢, add tuning notes). Runtime behavior (parts, physics, replication, grace↔hazard) is only provable here.
```
