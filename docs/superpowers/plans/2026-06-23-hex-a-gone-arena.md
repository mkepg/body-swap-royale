# Hex-A-Gone Arena Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the time-driven square disappearing-tile floor with a step-driven, monotonic, 3-floor hexagonal "Hex-A-Gone" arena where falling drops you a floor and only the bottom eliminates.

**Architecture:** Two new pure, lune-tested modules — `HexGrid` (axial↔world coords, cube-rounding lookup, spawn slots, floor banding) and `HexErosionModel` (step→warning→gone, grace-gated arming). A rewritten `HazardSystem` builds three stacked hex floors (each tile = 3 rotated `Block` parts) and is driven by `RoundManager`'s existing void monitor via a new `step(now, samples)` call — one server loop, not two. Death stays on the existing grace-gated void monitor with `VOID_Y` relocated below floor 3.

**Tech Stack:** Luau, Rojo, lune (pure-module unit tests), Roblox Studio (server-glue smoke test).

**Spec:** `docs/superpowers/specs/2026-06-23-hex-a-gone-arena-design.md`

**Test command (memory):** `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec`

---

### Task 1: `HexGrid` pure module

**Files:**
- Create: `src/shared/HexGrid.luau`
- Test: `tests/hex_grid.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/hex_grid.spec.luau`:

```lua
local HexGrid = require("../src/shared/HexGrid")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- tiles(radius): hexagonal field, count = 1 + 3R(R+1), distinct, center present.
do
	for _, R in ipairs({ 0, 1, 2, 3 }) do
		local t = HexGrid.tiles(R)
		expect(#t == 1 + 3 * R * (R + 1), "tiles count wrong for R=" .. R)
	end
	local t = HexGrid.tiles(3)
	local seen, hasCenter = {}, false
	for _, c in ipairs(t) do
		local key = c.q .. ":" .. c.r
		expect(not seen[key], "duplicate coord " .. key)
		seen[key] = true
		if c.q == 0 and c.r == 0 then hasCenter = true end
	end
	expect(hasCenter, "center tile missing")
	print("hexgrid: tiles count/distinct/center OK")
end

-- toWorld/fromWorld round-trip at every tile center (R=3, size=6).
do
	local size = 6
	for _, c in ipairs(HexGrid.tiles(3)) do
		local dx, dz = HexGrid.toWorld(c.q, c.r, size)
		local q, r = HexGrid.fromWorld(dx, dz, size)
		expect(q == c.q and r == c.r,
			"round-trip failed at (" .. c.q .. "," .. c.r .. ") got (" .. q .. "," .. r .. ")")
	end
	print("hexgrid: toWorld/fromWorld round-trip OK")
end

-- fromWorld near a center resolves to that hex, not a neighbor.
do
	local size = 6
	local dx, dz = HexGrid.toWorld(1, 0, size)
	local q, r = HexGrid.fromWorld(dx + 0.5, dz - 0.5, size)
	expect(q == 1 and r == 0, "small offset must stay on the same hex")
	print("hexgrid: fromWorld nearest-center OK")
end

-- spawnSlots: spiral, distinct, count == tiles count, >= player cap, all in-field.
do
	local slots = HexGrid.spawnSlots(3)
	expect(#slots == 37, "spawnSlots(3) must have 37 slots")
	expect(#slots >= 16, "spawnSlots must cover the 16 player cap")
	expect(slots[1].q == 0 and slots[1].r == 0, "spiral must start at center")
	local seen = {}
	for _, s in ipairs(slots) do
		local key = s.q .. ":" .. s.r
		expect(not seen[key], "spawnSlots duplicate " .. key)
		seen[key] = true
	end
	local valid = {}
	for _, c in ipairs(HexGrid.tiles(3)) do valid[c.q .. ":" .. c.r] = true end
	for _, s in ipairs(slots) do
		expect(valid[s.q .. ":" .. s.r], "spawn slot off-field: " .. s.q .. ":" .. s.r)
	end
	print("hexgrid: spawnSlots OK")
end

-- floorAt: roots map to the floor just below them; airborne/below-all -> nil.
do
	local surfaceY, gap, band, count = 0, 10, 6, 3
	expect(HexGrid.floorAt(2.8, surfaceY, gap, band, count) == 0, "root above floor 0")
	expect(HexGrid.floorAt(-7.2, surfaceY, gap, band, count) == 1, "root above floor 1")
	expect(HexGrid.floorAt(-17.2, surfaceY, gap, band, count) == 2, "root above floor 2")
	expect(HexGrid.floorAt(-3, surfaceY, gap, band, count) == nil, "between floors -> nil")
	expect(HexGrid.floorAt(-30, surfaceY, gap, band, count) == nil, "below all floors -> nil")
	print("hexgrid: floorAt banding OK")
end

print("ALL HexGrid TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_grid.spec`
Expected: FAIL — module `../src/shared/HexGrid` not found / require error.

- [ ] **Step 3: Write the implementation**

Create `src/shared/HexGrid.luau`:

```lua
--[[
	HexGrid -- PURE flat-top hex geometry for the Hex-A-Gone arena floor.
	Location (Roblox): ReplicatedStorage/Shared/HexGrid (ModuleScript)

	No Roblox APIs (no Vector3/CFrame/Color3), no clocks, no RNG. Number-in /
	number-out; the server glue (HazardSystem/BodyManager) turns the returned
	offsets into world positions. Mirrors the project's other pure modules
	(SpawnLayout, RoundState).

	Axial coords {q, r}, FLAT-TOP orientation. `size` is the hex circumradius
	(center-to-vertex = side length) in studs.
--]]

local HexGrid = {}

local SQRT3 = math.sqrt(3)

-- Axial neighbor directions (flat-top), used by the spawn-slot ring spiral.
local DIRECTIONS = {
	{ 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 },
}

-- All axial {q, r} within `radius` rings of center (hexagonal field).
-- Count = 1 + 3*radius*(radius+1).
function HexGrid.tiles(radius)
	local out = {}
	for q = -radius, radius do
		local rLo = math.max(-radius, -q - radius)
		local rHi = math.min(radius, -q + radius)
		for r = rLo, rHi do
			out[#out + 1] = { q = q, r = r }
		end
	end
	return out
end

-- Flat-top axial -> world center offset (dx, dz studs) from the field center.
function HexGrid.toWorld(q, r, size)
	local dx = size * 1.5 * q
	local dz = size * SQRT3 * (r + q / 2)
	return dx, dz
end

-- Round fractional axial coords to the nearest hex (cube rounding).
local function cubeRound(qf, rf)
	local x, z = qf, rf
	local y = -x - z
	local rx, ry, rz = math.round(x), math.round(y), math.round(z)
	local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
	if dx > dy and dx > dz then
		rx = -ry - rz
	elseif dy > dz then
		ry = -rx - rz
	else
		rz = -rx - ry
	end
	return rx, rz
end

-- Flat-top world offset -> nearest axial q, r.
function HexGrid.fromWorld(dx, dz, size)
	local qf = (2 / 3 * dx) / size
	local rf = (-1 / 3 * dx + SQRT3 / 3 * dz) / size
	return cubeRound(qf, rf)
end

-- Ordered hex centers (outward spiral from center) for round-start body spawns.
-- Returns all in-field tiles in spiral order; the server indexes the first N.
function HexGrid.spawnSlots(radius)
	local slots = { { q = 0, r = 0 } }
	for k = 1, radius do
		-- Start at the ring corner center + k * direction {-1, 1}, walk all 6 sides.
		local q, r = -k, k
		for i = 1, 6 do
			for _ = 1, k do
				slots[#slots + 1] = { q = q, r = r }
				q += DIRECTIONS[i][1]
				r += DIRECTIONS[i][2]
			end
		end
	end
	return slots
end

-- Which stacked floor (0-based, top = 0) a body whose root sits at height `y` is
-- standing on, or nil if airborne/between floors. Floor k's top surface is at
-- surfaceY - k*gap; a root counts as "on" it when within (surf, surf + band].
-- gap > band keeps the bands non-overlapping (no mid-air or wrong-floor arming).
function HexGrid.floorAt(y, surfaceY, gap, band, count)
	for k = 0, count - 1 do
		local surf = surfaceY - k * gap
		if y > surf and y <= surf + band then
			return k
		end
	end
	return nil
end

return HexGrid
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_grid.spec`
Expected: PASS — ends with `ALL HexGrid TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/HexGrid.luau tests/hex_grid.spec.luau
git commit -m "feat(hazard): HexGrid pure module (axial<->world, spawn slots, floor banding)"
```

---

### Task 2: `HexErosionModel` pure module

**Files:**
- Create: `src/shared/HexErosionModel.luau`
- Test: `tests/hex_erosion_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/hex_erosion_model.spec.luau`:

```lua
local HexErosionModel = require("../src/shared/HexErosionModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local DUR = { gone = 1.2 }

-- arm: stays nil unoccupied; sets `now` on first non-grace occupancy; suppressed
-- while graceBlocked; idempotent once armed.
do
	expect(HexErosionModel.arm(nil, false, false, 100) == nil, "unoccupied stays nil")
	expect(HexErosionModel.arm(nil, true, true, 100) == nil, "grace-blocked stays nil")
	expect(HexErosionModel.arm(nil, true, false, 100) == 100, "first non-grace occupancy arms at now")
	-- idempotent: an already-armed tile keeps its original steppedAt.
	expect(HexErosionModel.arm(100, true, false, 250) == 100, "re-arming keeps original steppedAt")
	expect(HexErosionModel.arm(100, false, false, 250) == 100, "armed tile stays armed when vacated")
	print("erosion: arm gating + idempotence OK")
end

-- phaseAt: solid when unarmed; warning before `gone`; gone at/after; monotonic.
do
	expect(HexErosionModel.phaseAt(nil, 999, DUR) == "solid", "unarmed -> solid")
	expect(HexErosionModel.phaseAt(100, 100, DUR) == "warning", "just armed -> warning")
	expect(HexErosionModel.phaseAt(100, 101.19, DUR) == "warning", "before delay -> warning")
	expect(HexErosionModel.phaseAt(100, 101.2, DUR) == "gone", "at delay -> gone")
	expect(HexErosionModel.phaseAt(100, 500, DUR) == "gone", "long after -> gone")
	-- monotonic: once gone, never returns to solid/warning for increasing now.
	local prevRank = 0
	local rank = { solid = 1, warning = 2, gone = 3 }
	for k = 0, 60 do
		local now = 100 + (k / 60) * 3
		local r = rank[HexErosionModel.phaseAt(100, now, DUR)]
		expect(r >= prevRank, "phase must not regress")
		prevRank = r
	end
	print("erosion: phaseAt thresholds + monotonicity OK")
end

print("ALL HexErosionModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_erosion_model.spec`
Expected: FAIL — module not found.

- [ ] **Step 3: Write the implementation**

Create `src/shared/HexErosionModel.luau`:

```lua
--[[
	HexErosionModel -- PURE step-driven, monotonic tile erosion for Hex-A-Gone.
	Location (Roblox): ReplicatedStorage/Shared/HexErosionModel (ModuleScript)

	Answers two questions, no clock reads / RNG (lune-tested, like TileFieldModel
	was for the old cyclic floor):
	  arm     -- when does a tile's erosion timer start? (grace-gated, idempotent)
	  phaseAt -- given that start time + now, what phase is the tile in?

	Monotonic: the caller never clears steppedAt, so a tile goes solid -> warning
	-> gone and never returns within a round. Death stays geometric (a body over a
	gone tile falls past VOID_Y -> the existing void monitor).
--]]

local HexErosionModel = {}

-- Decide a tile's steppedAt (erosion start time):
--   already armed     -> unchanged (idempotent),
--   occupied + !grace  -> now (arm),
--   otherwise          -> nil (stays solid).
-- graceBlocked is true while a body's post-swap grace still shields it, so a
-- freshly-swapped body never arms the tile it is standing on.
function HexErosionModel.arm(steppedAt, occupied, graceBlocked, now)
	if steppedAt ~= nil then
		return steppedAt
	end
	if occupied and not graceBlocked then
		return now
	end
	return nil
end

-- Phase of a tile given its steppedAt (or nil) and now. durations = { gone }.
-- An armed tile shows the warning color for the whole `gone` delay, then drops.
function HexErosionModel.phaseAt(steppedAt, now, durations)
	if steppedAt == nil then
		return "solid"
	elseif now - steppedAt < durations.gone then
		return "warning"
	else
		return "gone"
	end
end

return HexErosionModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_erosion_model.spec`
Expected: PASS — ends with `ALL HexErosionModel TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/HexErosionModel.luau tests/hex_erosion_model.spec.luau
git commit -m "feat(hazard): HexErosionModel pure module (grace-gated arm + monotonic phaseAt)"
```

---

### Task 3: Config — hex tunables, relocate `VOID_Y`, retire square-floor fields

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Relocate `VOID_Y` below floor 3**

In `src/shared/Config.luau`, change the `VOID_Y` line (currently `Config.VOID_Y = -4`) and its comment block. Replace:

```lua
Config.LOBBY_COUNTDOWN_SECONDS = 5
Config.ROUND_END_SECONDS = 5
Config.VOID_Y = -4
```

with:

```lua
Config.LOBBY_COUNTDOWN_SECONDS = 5
Config.ROUND_END_SECONDS = 5
-- A controlled body whose root falls below this Y is eliminated (grace-gated, via
-- the void monitor). With the 3-floor hex arena (floors at 0 / -10 / -20), this
-- sits just under the LOWEST floor, so only a body that falls off floor 3 dies --
-- falling through an upper floor lands on the next floor down. Still far above
-- Workspace.FallenPartsDestroyHeight (default -500).
Config.VOID_Y = -24
```

- [ ] **Step 2: Replace the square-tile hazard block with hex tunables**

Replace the entire disappearing-tile block (the comment starting `-- Disappearing-tile hazard` through `Config.TILE_COLOR_WARNING = ...`, i.e. the current lines for `HAZARDS_ENABLED`, `TILE_SOLID_SECONDS`, `TILE_WARNING_SECONDS`, `TILE_GONE_SECONDS`, `TILE_GRID_SIZE`, `TILE_SIZE`, `TILE_SURFACE_Y`, `TILE_THICKNESS`, `TILE_COLOR_SOLID`, `TILE_COLOR_WARNING`) with:

```lua
-- Hex-A-Gone arena floor. Three stacked hexagonal floors; a hex arms the instant a
-- body stands on it, flashes the warning color for HEX_GONE_DELAY_SECONDS, then
-- vanishes for good (monotonic -- no return that round). Pure decisions live in
-- HexGrid (geometry) + HexErosionModel (arm/phase); HazardSystem maps phase -> parts.
-- HAZARDS_ENABLED: dev/test switch (NOT a gameplay tunable). When false, floors build
-- but never arm (stay solid), so swaps can be observed without bodies falling.
Config.HAZARDS_ENABLED = true
Config.HEX_RADIUS = 3            -- rings from center; tiles/floor = 1+3R(R+1) = 37
Config.HEX_SIZE = 6              -- hex circumradius (center-to-vertex = side) in studs
Config.HEX_FLOOR_COUNT = 3       -- stacked floors
Config.HEX_FLOOR_GAP = 10        -- vertical studs between floors (floors at 0/-10/-20)
Config.HEX_STAND_BAND = 6        -- root-height window above a floor that counts as "on" it
                                 -- (must be < HEX_FLOOR_GAP so floor bands don't overlap)
Config.HEX_GONE_DELAY_SECONDS = 1.2 -- step -> gone delay (warning color shows the whole time)
Config.TILE_SURFACE_Y = 0        -- top-floor surface Y (reused by HazardSystem + spawn)
Config.TILE_THICKNESS = 1        -- hex part thickness
Config.TILE_COLOR_SOLID = Color3.fromRGB(150, 150, 150)   -- neutral grey
Config.TILE_COLOR_WARNING = Color3.fromRGB(200, 40, 40)   -- alarm red (armed/imminent)
```

- [ ] **Step 3: Retire the square arena spawn tunables**

The arena now spawns on hex centers (Task 6), so `ARENA_PER_ROW` / `ARENA_SPACING` are dead. In the `SPAWN_ORIGIN` block, replace:

```lua
Config.SPAWN_ORIGIN = Vector3.new(0, 5, 0) -- grid CENTER (X,Z) + spawn height (Y)
Config.ARENA_PER_ROW = 4                   -- grid columns (rows = ceil(LOBBY_CAPACITY/this))
Config.ARENA_SPACING = 8                   -- studs between slots; = TILE_SIZE so slots hit tile centers
```

with:

```lua
Config.SPAWN_ORIGIN = Vector3.new(0, 5, 0) -- arena center (X,Z) + spawn height (Y)
```

Also shorten the now-stale `SPAWN_ORIGIN` comment paragraph above it (the long "centered GRID / tile centers vs seams" explanation) to a one-line note, since round-start bodies now spawn on hex centers via `HexGrid.spawnSlots`:

```lua
-- Spawn placement for the persistent bodies: round-start bodies drop onto the TOP
-- hex floor at SPAWN_ORIGIN.Y. Arena slot positions come from HexGrid.spawnSlots
-- (an outward spiral of hex centers); the lobby balcony still uses SpawnLayout.
```

- [ ] **Step 4: Sanity-check the file loads (syntax)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec`
Expected: PASS (unrelated test, but it requires nothing removed; confirms no syntax fallout in shared modules touched nearby). If it errors on Config, fix the edit.

- [ ] **Step 5: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(hazard): hex arena Config tunables; relocate VOID_Y below floor 3; retire square-tile fields"
```

---

### Task 4: Rewrite `HazardSystem` for the 3-floor hex arena

**Files:**
- Modify (full rewrite): `src/server/HazardSystem.luau`

No lune test (server glue) — verified by the Task 8 smoke test. This rewrite removes the `TileFieldModel` dependency so Task 5 can delete that module.

- [ ] **Step 1: Replace the file contents**

Overwrite `src/server/HazardSystem.luau` with:

```lua
--[[
	HazardSystem (server) -- the Hex-A-Gone arena floor (the MVP arena).
	Builds THREE stacked hexagonal floors once, then erodes them step-driven during
	Active rounds: a hex arms when a body stands on it, flashes the warning color,
	then vanishes for good (monotonic). Each hex is a cluster of 3 rotated Block
	parts (reads as a hexagon, erodes as a unit) -- no mesh asset, consistent with
	the build-in-code pattern (LobbyArea.build).

	Death is NOT handled here. A body over a `gone` hex falls to the floor below
	(intermediate floors are CanCollide); only a fall off the LOWEST floor crosses
	Config.VOID_Y and is eliminated by the grace-gated void monitor in RoundManager.

	Driven by RoundManager's void monitor (one server loop): each tick it gathers
	body samples and calls HazardSystem.step(now, samples).

	Lifecycle (called by RoundManager):
	  build()          -- once at startup: replace the baseplate, construct 3 hex floors
	  start(startTime) -- beginRound: reset all hexes to solid
	  step(now, samples) -- per tick: arm stepped hexes, apply phases
	  stop()           -- endRound: reset all hexes to solid

	Depends on: ReplicatedStorage.Shared.Config / HexGrid / HexErosionModel
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local HexGrid = require(ReplicatedStorage.Shared.HexGrid)
local HexErosionModel = require(ReplicatedStorage.Shared.HexErosionModel)

local HazardSystem = {}

local SQRT3 = math.sqrt(3)

local tiles = {}      -- array of { parts = {Part,Part,Part}, steppedAt, phase, floor, q, r }
local tileByKey = {}  -- ["floor:q:r"] = tile record

local function keyOf(floor, q, r)
	return floor .. ":" .. q .. ":" .. r
end

local function durations()
	return { gone = Config.HEX_GONE_DELAY_SECONDS }
end

-- Map a phase to a hex tile's 3 parts (caller applies only on change).
local function applyPhase(tile, phase)
	local canCollide, transparency, color
	if phase == "solid" then
		canCollide, transparency, color = true, 0, Config.TILE_COLOR_SOLID
	elseif phase == "warning" then
		canCollide, transparency, color = true, 0, Config.TILE_COLOR_WARNING
	else -- "gone"
		canCollide, transparency, color = false, 1, Config.TILE_COLOR_SOLID
	end
	for _, part in ipairs(tile.parts) do
		part.CanCollide = canCollide
		part.Transparency = transparency
		part.Color = color
	end
end

-- Three Block parts rotated 0/60/120 deg about Y, centered at (cx, *, cz), reading
-- as one flat-top hexagon (a regular hexagon = union of 3 rectangles of size
-- size*sqrt(3) x size). Top faces sit at surfaceY.
local function buildHexParts(folder, cx, cz, surfaceY, floor, q, r)
	local size = Config.HEX_SIZE
	local thickness = Config.TILE_THICKNESS
	local centerY = surfaceY - thickness / 2
	local parts = {}
	for i = 0, 2 do
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(size * SQRT3, thickness, size)
		part.CFrame = CFrame.new(cx, centerY, cz) * CFrame.Angles(0, math.rad(60 * i), 0)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Color = Config.TILE_COLOR_SOLID
		part.Name = string.format("Hex_%d_%d_%d_%d", floor, q, r, i)
		part.Parent = folder
		parts[#parts + 1] = part
	end
	return parts
end

-- Build the 3 stacked hex floors once. The hex field IS the floor, so any leftover
-- floor from the place template is removed: the Baseplate, plus any SpawnLocation
-- (this game never spawns player Characters). Singleton: a second call is a no-op.
function HazardSystem.build()
	if #tiles > 0 then
		return
	end

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local folder = workspace:FindFirstChild("HexField")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "HexField"
		folder.Parent = workspace
	end

	local coords = HexGrid.tiles(Config.HEX_RADIUS)
	for floor = 0, Config.HEX_FLOOR_COUNT - 1 do
		local surfaceY = Config.TILE_SURFACE_Y - floor * Config.HEX_FLOOR_GAP
		for _, c in ipairs(coords) do
			local dx, dz = HexGrid.toWorld(c.q, c.r, Config.HEX_SIZE)
			local parts = buildHexParts(folder, dx, dz, surfaceY, floor, c.q, c.r)
			local tile = { parts = parts, steppedAt = nil, phase = "solid", floor = floor, q = c.q, r = c.r }
			tiles[#tiles + 1] = tile
			tileByKey[keyOf(floor, c.q, c.r)] = tile
		end
	end
end

local function forceAllSolid()
	for _, tile in ipairs(tiles) do
		tile.steppedAt = nil
		tile.phase = "solid"
		applyPhase(tile, "solid")
	end
end

-- Begin an Active round: all hexes solid + un-armed. startTime is accepted for
-- symmetry with the old API but erosion is now driven by step()'s `now`.
function HazardSystem.start(_startTime)
	forceAllSolid()
end

-- Driven each tick by RoundManager's void monitor. samples = array of
-- { dx, dz, y, graceBlocked } (one per alive body, offsets from the field center
-- at origin). Arms the hex each body stands on (grace-gated), then applies the
-- current phase to every tile on change. `now` is os.clock().
function HazardSystem.step(now, samples)
	if Config.HAZARDS_ENABLED then
		for _, s in ipairs(samples) do
			local floor = HexGrid.floorAt(
				s.y, Config.TILE_SURFACE_Y, Config.HEX_FLOOR_GAP, Config.HEX_STAND_BAND, Config.HEX_FLOOR_COUNT)
			if floor then
				local q, r = HexGrid.fromWorld(s.dx, s.dz, Config.HEX_SIZE)
				local tile = tileByKey[keyOf(floor, q, r)]
				if tile then
					tile.steppedAt = HexErosionModel.arm(tile.steppedAt, true, s.graceBlocked, now)
				end
			end
		end
	end
	local dur = durations()
	for _, tile in ipairs(tiles) do
		local phase = HexErosionModel.phaseAt(tile.steppedAt, now, dur)
		if phase ~= tile.phase then
			tile.phase = phase
			applyPhase(tile, phase)
		end
	end
end

-- Stop driving the floor and leave it fully solid + un-armed (Lobby/Ended; parked
-- bodies rest on solid ground next round).
function HazardSystem.stop()
	forceAllSolid()
end

return HazardSystem
```

- [ ] **Step 2: Verify the existing pure tests still pass (no shared-module breakage)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_grid.spec && lune run tests/hex_erosion_model.spec`
Expected: both PASS. (HazardSystem itself is server glue — not lune-runnable — and is exercised by the Task 8 smoke test.)

- [ ] **Step 3: Commit**

```bash
git add src/server/HazardSystem.luau
git commit -m "feat(hazard): rewrite HazardSystem as 3-floor step-eroded hex arena, step()-driven"
```

---

### Task 5: Remove the retired `TileFieldModel` module + its test

**Files:**
- Delete: `src/shared/TileFieldModel.luau`
- Delete: `tests/tile_field_model.spec.luau`

Nothing references `TileFieldModel` after Task 4 (verified: only HazardSystem + its own test used it).

- [ ] **Step 1: Delete the files**

```bash
git rm src/shared/TileFieldModel.luau tests/tile_field_model.spec.luau
```

- [ ] **Step 2: Verify no lingering references in source**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; grep -rn "TileFieldModel" src/`
Expected: no output (no matches in `src/`). If any appear, remove them.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(hazard): remove retired TileFieldModel (superseded by HexErosionModel)"
```

---

### Task 6: `BodyManager` — spawn round-start bodies on hex centers

**Files:**
- Modify: `src/server/BodyManager.luau`

- [ ] **Step 1: Add the `HexGrid` require + precomputed slots; drop `ARENA_ROWS`**

In `src/server/BodyManager.luau`, after the existing `local SpawnLayout = require(ReplicatedStorage.Shared.SpawnLayout)` line, add:

```lua
local HexGrid = require(ReplicatedStorage.Shared.HexGrid)
```

Then replace the two grid-row derivations:

```lua
-- Grid row counts, derived once from Config (read-only at runtime).
local LOBBY_ROWS = math.ceil(Config.LOBBY_CAPACITY / Config.LOBBY_PER_ROW)
local ARENA_ROWS = math.ceil(Config.LOBBY_CAPACITY / Config.ARENA_PER_ROW)
```

with:

```lua
-- Lobby grid row count, derived once from Config (read-only at runtime).
local LOBBY_ROWS = math.ceil(Config.LOBBY_CAPACITY / Config.LOBBY_PER_ROW)
-- Arena spawn slots: an outward spiral of hex centers (pure HexGrid), indexed by
-- the body's 1-based slot. 37 slots at HEX_RADIUS=3 cover the 16-body cap.
local ARENA_SLOTS = HexGrid.spawnSlots(Config.HEX_RADIUS)
```

- [ ] **Step 2: Rewrite `arenaCFrame` to use hex centers**

Replace:

```lua
-- Arena spawn CFrame for a 1-based body index: a centered grid (pure SpawnLayout)
-- offset from the arena center, at the spawn height. Slots land on tile centers
-- within the field, so no body spawns off the floor.
local function arenaCFrame(index)
	local o = Config.SPAWN_ORIGIN
	local dx, dz = SpawnLayout.arenaSlot(index, Config.ARENA_PER_ROW, ARENA_ROWS, Config.ARENA_SPACING)
	return CFrame.new(o.X + dx, o.Y, o.Z + dz)
end
```

with:

```lua
-- Arena spawn CFrame for a 1-based body index: a hex center (pure HexGrid) offset
-- from the arena center, at the spawn height. Bodies drop onto the TOP hex floor.
-- Over-cap indices clamp to the last slot (matches the slot allocator's clamp).
local function arenaCFrame(index)
	local o = Config.SPAWN_ORIGIN
	local slot = ARENA_SLOTS[index] or ARENA_SLOTS[#ARENA_SLOTS]
	local dx, dz = HexGrid.toWorld(slot.q, slot.r, Config.HEX_SIZE)
	return CFrame.new(o.X + dx, o.Y, o.Z + dz)
end
```

(`SpawnLayout` is still required and used by `lobbyCFrame` — leave that require in place.)

- [ ] **Step 3: Verify shared/pure tests still pass**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_grid.spec && lune run tests/spawn_layout.spec`
Expected: both PASS. (`BodyManager` is server glue, exercised in the Task 8 smoke test.)

- [ ] **Step 4: Commit**

```bash
git add src/server/BodyManager.luau
git commit -m "feat(hazard): spawn round-start bodies on hex centers (HexGrid.spawnSlots)"
```

---

### Task 7: `RoundManager` — drive hex erosion from the void monitor (loop consolidation)

**Files:**
- Modify: `src/server/RoundManager.luau` (the `startMonitor` function, ~lines 197-228)

**Load-bearing constraint:** the move/grace branch and the death branch (`root.Position.Y < Config.VOID_Y` → `eliminateFromHazard`) must stay behaviorally identical. The change is purely additive: gather a `samples` array and call `HazardSystem.step(now, samples)` once per tick. `HazardSystem` is already required at the top of `RoundManager`.

- [ ] **Step 1: Replace the monitor loop body**

Replace the `startMonitor` function:

```lua
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
```

with:

```lua
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
						-- un-blocks arming.
						local graceBlocked = not GraceModel.canDieFromHazard(grace, player, t)
						samples[#samples + 1] = {
							dx = root.Position.X,
							dz = root.Position.Z,
							y = root.Position.Y,
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
```

- [ ] **Step 2: Verify all pure tests pass (regression sweep)**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in round_state grace_model control_model cadence_model spawn_layout hex_grid hex_erosion_model; do lune run tests/$f.spec || break; done
```
Expected: every spec ends with its `ALL ... TESTS PASSED` line. (`RoundManager` itself is server glue — runtime behavior is covered by the Task 8 smoke test.)

- [ ] **Step 3: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(hazard): drive hex erosion from the void monitor (single server loop)"
```

---

### Task 8: Studio smoke test document

**Files:**
- Create: `docs/smoke-tests/2026-06-23-hex-a-gone-smoke-test.md`

- [ ] **Step 1: Write the smoke-test doc**

Create `docs/smoke-tests/2026-06-23-hex-a-gone-smoke-test.md`:

```markdown
# Smoke Test — Hex-A-Gone Arena (2026-06-23)

**Status:** RUNTIME-UNVERIFIED until run in Studio.
**Covers:** the server glue that lune can't test — `HazardSystem` (3-floor hex build,
step-driven erosion), the `RoundManager` void-monitor consolidation, and
`BodyManager` hex-center spawns. Pure logic (`HexGrid`, `HexErosionModel`) is
lune-covered.

**Spec:** `docs/superpowers/specs/2026-06-23-hex-a-gone-arena-design.md`

## Setup
1. Open the place in Studio. Start a **2-player** local server
   (Test > Clients and Servers > 2 players, Start).
2. Both bodies spawn on the balcony; a round begins after the lobby countdown.

## Checks

### 1. Build & geometry
- [ ] Below the balcony there are **three stacked hexagonal floors** (a `HexField`
      folder in Workspace), each tile reading as a hexagon, top floor at Y=0.
- [ ] No leftover `Baseplate` / `SpawnLocation` remains.
- [ ] At round start every hex is solid grey; bodies stand cleanly on the top floor
      (no falling through seams between the 3 sub-parts of a hex).

### 2. Step-driven, monotonic erosion
- [ ] Walk a body across floor 1: each hex you stand on turns **red (warning)**,
      then **vanishes** ~1.2s later.
- [ ] A vanished hex **does not come back** for the rest of the round.
- [ ] A hex you never touch **stays solid** (erosion is occupancy-driven, not timed).

### 3. Multi-floor descent & death
- [ ] Walk off / erode a path so a body **falls through floor 1 and lands on floor 2**
      (not eliminated). Continue to **floor 3**, then off floor 3 → **eliminated**
      (crossed VOID_Y).
- [ ] Floors 2 and 3 stay pristine until a body is actually on them, then erode the
      same way.

### 4. Swap × grace synergy (the headline interaction)
- [ ] In the command bar run `require(game.ServerScriptService.Server.RoundManager).forceSwap()`
      to force a swap (or wait for a natural one).
- [ ] Immediately after a swap, the hex **under the freshly-swapped body does NOT
      start eroding** during the grace window (no instant red/drop under a still body).
- [ ] Once grace ends (≈1.5s) or the body moves, the hex under it **arms normally**.

### 5. Round end
- [ ] With one body left, the round **ends and declares a winner**; the victory cam
      frames the survivor.
- [ ] Between rounds the floor is **fully solid again** (parked bodies rest safely);
      the next round re-spawns bodies on the top floor and erosion resets.

### 6. Dev switch (optional)
- [ ] Set `Config.HAZARDS_ENABLED = false`, replay: floors build and stay solid; no
      hex ever arms (lets you observe swaps without falls). Restore to `true` after.

## Result
Record pass/fail per check and any tuning notes (hex size, floor gap, gone delay).
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-23-hex-a-gone-smoke-test.md
git commit -m "docs(hazard): Studio smoke test for the Hex-A-Gone arena"
```

---

### Task 9: CHANGELOG + final regression sweep

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a CHANGELOG entry**

Open `CHANGELOG.md`, match the existing format/section style, and add an entry dated 2026-06-23 summarizing: "Replaced the time-driven square disappearing-tile floor with a step-driven, monotonic, 3-floor hexagonal Hex-A-Gone arena (new pure `HexGrid` + `HexErosionModel`; `HazardSystem` rewritten and driven by the consolidated void monitor; bodies spawn on hex centers; `VOID_Y` relocated below floor 3; retired `TileFieldModel` and the square-tile Config fields)." Keep it consistent with how prior entries are phrased.

- [ ] **Step 2: Final full pure-test sweep**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "${f%.luau}" || { echo "FAILED: $f"; break; }; done
```
Expected: every spec ends with its `ALL ... TESTS PASSED` line and none fail. (`tile_field_model.spec` is gone; new `hex_grid`/`hex_erosion_model` specs pass.)

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(hazard): changelog for the Hex-A-Gone arena"
```

---

## Post-plan

After all tasks: the pure logic is lune-verified; the server glue (HazardSystem / RoundManager loop / BodyManager spawns) remains **RUNTIME-UNVERIFIED** until the Task 8 smoke test is run in Studio. Run it before building anything further on top of this floor (and before the deferred economy slice). Then use `superpowers:finishing-a-development-branch` to merge `feat/hex-a-gone-arena`.
```

## Self-Review

**Spec coverage:**
- `HexGrid` (tiles/toWorld/fromWorld/spawnSlots) → Task 1; added `floorAt` (needed by HazardSystem floor banding) → Task 1. ✓
- `HexErosionModel` (arm/phaseAt) → Task 2. ✓
- Config (HEX_* new, VOID_Y relocate, retire square fields) → Task 3. ✓
- HazardSystem rewrite (3 floors, composed hexes, step) → Task 4. ✓
- Remove TileFieldModel → Task 5. ✓
- BodyManager hex spawns → Task 6. ✓
- Loop consolidation in RoundManager → Task 7. ✓
- Death model / VOID_Y geometry → Config Task 3 + verified in smoke Task 8. ✓
- No client change → confirmed (no client task). ✓
- Tests: pure lune (Tasks 1-2) + Studio smoke (Task 8). ✓

**Type/name consistency:** `arm(steppedAt, occupied, graceBlocked, now)` and `phaseAt(steppedAt, now, {gone})` match between Task 2, Task 4, and the tests. `floorAt(y, surfaceY, gap, band, count)` and `toWorld`/`fromWorld`/`spawnSlots`/`tiles` signatures match between Task 1 and Tasks 4/6. Sample shape `{dx, dz, y, graceBlocked}` matches between Task 4 (`step`) and Task 7 (producer). `HazardSystem.step(now, samples)` / `start(_startTime)` / `stop()` / `build()` consistent across Tasks 4 and 7. Config keys (`HEX_RADIUS`, `HEX_SIZE`, `HEX_FLOOR_COUNT`, `HEX_FLOOR_GAP`, `HEX_STAND_BAND`, `HEX_GONE_DELAY_SECONDS`, `TILE_SURFACE_Y`, `TILE_THICKNESS`, `TILE_COLOR_SOLID`, `TILE_COLOR_WARNING`, `VOID_Y`) consistent across Tasks 3/4/6.

**Placeholder scan:** none — every code step shows complete code; commands have expected output.

No issues found.
