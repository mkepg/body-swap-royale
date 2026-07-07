# Soul Sweeper Arena Implementation Plan

**Goal:** Add a second playable arena — Soul Sweeper (Fall Guys "Jump Club" adapted to the swap loop) — behind a thin `ArenaHazard` interface, with hex refactored to sit behind the same interface.

**Architecture:** A pure, lune-tested `SweeperModel` decides beam geometry and strikes from plain numbers. Server `SweeperHazard` builds stacked downward-widening collision discs, samples every body at 10 Hz, and returns outward re-pivot "sweep" requests that `RoundManager` applies with the existing reposition-then-re-own primitive. Beams are cosmetic (client-rendered, server-time-synced); death stays geometric via the existing grace-gated void monitor. `RoundManager` talks to an `ArenaHazard` interface (`HexHazard` | `SweeperHazard`) selected by `Config.ACTIVE_ARENA`.

**Tech Stack:** Luau, Rojo, rokit/lune (pure-logic tests), Roblox Studio + MCP (glue verification), the `ArenaDescriptor` world-shell contract.

**Spec:** `docs/specs/2026-07-07-soul-sweeper-arena-design.md`

**Conventions (match these exactly):**
- Pure modules live in `src/shared/`, are Roblox-free, and are lune-tested from `tests/<snake_case>.spec.luau` with `require("../src/shared/X")` and the local `expect`/`fail` helpers (see `tests/hex_erosion_model.spec.luau`).
- Run tests: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`.
- Run the whole suite: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
- **MCP note:** the Roblox_Studio MCP is currently disconnected. Tasks 1–13 are MCP-independent (pure logic + code, verified by lune + code review). Tasks 14–15 REQUIRE the MCP and must be skipped/deferred until it is reachable — do not block the branch on them.

---

## File Structure

**Pure (shared, lune-tested):**
- Create `src/shared/SweeperModel.luau` — beam angle/speed/overlap/clear/strike/outward math.
- Create `tests/sweeper_model.spec.luau` — its tests.

**Config / descriptor (shared glue, not lune-tested):**
- Modify `src/shared/Config.luau` — add `ACTIVE_ARENA` + the `SWEEP_*` block.
- Modify `src/shared/ArenaDescriptor.luau` — add `sweeper()` + `forActive()`.

**Server hazard interface + implementations:**
- Create `src/server/ArenaHazard.luau` — the interface contract (doc + a `validate` guard).
- Create `src/server/ArenaRegistry.luau` — `forActive()` → the active hazard singleton.
- Create `src/server/HexHazard.luau` — wraps today's `HazardSystem` behind the interface.
- Create `src/server/SweeperHazard.luau` — the new arena (geometry + strike detection).
- Modify `src/server/RoundManager.luau` — talk to the interface; apply sweeps; use `arena.voidY()`.

**Client (cosmetic):**
- Create `src/client/SweeperController.luau` — cosmetic beams + telegraph + tumble.
- Modify `src/client/ArenaDressing.luau` — dress the active arena's descriptor (not hardcoded hex).
- Modify the client bootstrap (the script that calls `ArenaDressing.start()`) — start `SweeperController` when `ACTIVE_ARENA == "sweeper"`.

**Docs:**
- Create `docs/smoke-tests/2026-07-07-soul-sweeper-smoke-test.md`.
- Modify `CHANGELOG.md`, `docs/world-enrichment-roadmap.md`.

**MCP-gated (deferred):**
- Modify `src/shared/Config.luau` — fill `SWEEP_DISC_MATERIAL` / `SWEEP_BEAM_MATERIAL` / `SWEEP_HUB_MESH` asset IDs.

---

## Task 1: SweeperModel — angular helpers (`angularDistance`, `beamAngle`)

**Files:**
- Create: `src/shared/SweeperModel.luau`
- Test: `tests/sweeper_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/sweeper_model.spec.luau`:

```lua
local M = require("../src/shared/SweeperModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local TAU = math.pi * 2

-- angularDistance: symmetric, wraps at the 0/2π seam, max is π.
do
	expect(near(M.angularDistance(0, 0), 0), "same angle -> 0")
	expect(near(M.angularDistance(0.1, TAU - 0.1), 0.2), "wraps across the 0/2π seam")
	expect(near(M.angularDistance(TAU - 0.1, 0.1), 0.2), "symmetric across the seam")
	expect(near(M.angularDistance(0, math.pi), math.pi), "opposite -> π (max)")
	expect(near(M.angularDistance(0, math.pi + 1), math.pi - 1), "never exceeds π")
	print("sweeper: angularDistance seam OK")
end

-- beamAngle: base + direction*speed*elapsed + arm offset, normalized to [0, 2π).
do
	local beam = { baseAngle = 0, direction = 1, armCount = 1 }
	expect(near(M.beamAngle(beam, 0, 2, 0), 0), "t=0 -> baseAngle")
	expect(near(M.beamAngle(beam, 0, 2, 1), 2), "advances by speed*elapsed")
	-- direction -1 wraps to just under 2π
	local rev = { baseAngle = 0, direction = -1, armCount = 1 }
	expect(near(M.beamAngle(rev, 0, 1, 1), TAU - 1), "reverse wraps into [0,2π)")
	-- 2 arms are π apart
	local two = { baseAngle = 0, direction = 1, armCount = 2 }
	expect(near(M.beamAngle(two, 0, 0, 0), 0), "arm 0 at base")
	expect(near(M.beamAngle(two, 1, 0, 0), math.pi), "arm 1 offset by π")
	print("sweeper: beamAngle OK")
end

print("ALL SweeperModel TESTS PASSED")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: FAIL (module `../src/shared/SweeperModel` not found).

- [ ] **Step 3: Write minimal implementation**

Create `src/shared/SweeperModel.luau`:

```lua
--[[
	SweeperModel -- PURE beam geometry for the Soul Sweeper arena (arena #2).
	Location (Roblox): ReplicatedStorage/Shared/SweeperModel (ModuleScript)

	No clock reads / RNG / Roblox globals (lune-tested, like HexErosionModel).
	The glue (SweeperHazard server-side, SweeperController client-side) feeds it
	elapsed seconds since round start + a body's polar position, and gets back
	beam angles and a yes/no strike decision. Angles in radians.
--]]

local SweeperModel = {}

local TAU = math.pi * 2

local function norm(a)
	a = a % TAU
	if a < 0 then a = a + TAU end
	return a
end

-- Minimal wrap-around angular distance in [0, π].
function SweeperModel.angularDistance(a, b)
	local d = norm(a - b)
	if d > math.pi then d = TAU - d end
	return d
end

-- Current angle of one arm of a beam. beam = { baseAngle, direction (+1/-1), armCount }.
-- speed is the (already ramped) angular speed; armIndex is 0-based.
function SweeperModel.beamAngle(beam, armIndex, speed, elapsed)
	local arm = armIndex * (TAU / beam.armCount)
	return norm(beam.baseAngle + beam.direction * speed * elapsed + arm)
end

return SweeperModel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: PASS — prints `ALL SweeperModel TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/SweeperModel.luau tests/sweeper_model.spec.luau
git commit -m "feat(sweeper): pure angular helpers (angularDistance, beamAngle)"
```

---

## Task 2: SweeperModel — `rampedSpeed`, `overlaps`, `clears`

**Files:**
- Modify: `src/shared/SweeperModel.luau`
- Test: `tests/sweeper_model.spec.luau`

- [ ] **Step 1: Add failing tests**

Insert BEFORE the final `print("ALL SweeperModel TESTS PASSED")` in `tests/sweeper_model.spec.luau`:

```lua
-- rampedSpeed: monotonic increase from base, clamped to maxSpeed, floored at elapsed 0.
do
	local opts = { rampPerSecond = 0.1, maxSpeed = 2 }
	expect(near(M.rampedSpeed(1, 0, opts), 1), "elapsed 0 -> base")
	expect(near(M.rampedSpeed(1, 5, opts), 1.5), "ramps up over time")
	expect(near(M.rampedSpeed(1, 1000, opts), 2), "clamped to maxSpeed")
	expect(near(M.rampedSpeed(1, -5, opts), 1), "negative elapsed floored to base")
	print("sweeper: rampedSpeed OK")
end

-- overlaps: inside the radius band AND within the beam's angular half-width.
do
	local opts = { innerRadius = 3, outerRadius = 30, angularHalfWidth = 0.15 }
	expect(M.overlaps(10, 0.0, 0.1, opts), "within band + arc -> true")
	expect(not M.overlaps(10, 0.0, 0.3, opts), "outside arc -> false")
	expect(not M.overlaps(1, 0.0, 0.0, opts), "inside inner radius (hub) -> false")
	expect(not M.overlaps(40, 0.0, 0.0, opts), "beyond outer radius -> false")
	print("sweeper: overlaps OK")
end

-- clears: low beam cleared by being airborne; high beam cleared by being grounded.
do
	expect(M.clears("low", true), "low + airborne -> cleared")
	expect(not M.clears("low", false), "low + grounded -> NOT cleared")
	expect(M.clears("high", false), "high + grounded -> cleared")
	expect(not M.clears("high", true), "high + airborne -> NOT cleared")
	print("sweeper: clears OK")
end
```

- [ ] **Step 2: Run to verify failure**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: FAIL (`rampedSpeed` is nil).

- [ ] **Step 3: Implement**

In `src/shared/SweeperModel.luau`, add before `return SweeperModel`:

```lua
-- Monotonic angular speed-up over the round, clamped. opts = { rampPerSecond, maxSpeed }.
function SweeperModel.rampedSpeed(baseSpeed, elapsed, opts)
	local s = baseSpeed + (opts.rampPerSecond or 0) * math.max(0, elapsed)
	if opts.maxSpeed and s > opts.maxSpeed then
		s = opts.maxSpeed
	end
	return s
end

-- Is a body at polar (radius, angle) under a beam arm currently at beamAngle?
-- opts = { innerRadius, outerRadius, angularHalfWidth }. The hub (< innerRadius) is safe.
function SweeperModel.overlaps(radius, angle, beamAngle, opts)
	if radius < opts.innerRadius or radius > opts.outerRadius then
		return false
	end
	return SweeperModel.angularDistance(angle, beamAngle) < opts.angularHalfWidth
end

-- Does a body's vertical state clear this beam class?
-- "low" is cleared by jumping (airborne); "high" is cleared by staying grounded.
function SweeperModel.clears(class, airborne)
	if class == "low" then
		return airborne == true
	end
	return airborne == false
end
```

- [ ] **Step 4: Run to verify pass**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/shared/SweeperModel.luau tests/sweeper_model.spec.luau
git commit -m "feat(sweeper): rampedSpeed + overlaps + clears"
```

---

## Task 3: SweeperModel — `isStruck` composition + `outwardTarget`

**Files:**
- Modify: `src/shared/SweeperModel.luau`
- Test: `tests/sweeper_model.spec.luau`

- [ ] **Step 1: Add failing tests**

Insert before the final `print(...)` in the spec:

```lua
-- isStruck: composes ramp -> beamAngle -> overlaps -> (not clears) over a tier's beams.
do
	local opts = { rampPerSecond = 0, maxSpeed = 10 }
	local beams = {
		{ baseAngle = 0, direction = 1, baseSpeed = 0, armCount = 1, class = "low",
		  innerRadius = 3, outerRadius = 30, angularHalfWidth = 0.15 },
	}
	-- grounded body directly under the low beam at angle 0 -> struck.
	expect(M.isStruck({ radius = 10, angle = 0, airborne = false }, beams, 0, opts),
		"grounded under low beam -> struck")
	-- same body but airborne -> clears the low beam.
	expect(not M.isStruck({ radius = 10, angle = 0, airborne = true }, beams, 0, opts),
		"airborne clears the low beam")
	-- body away from the arc -> safe.
	expect(not M.isStruck({ radius = 10, angle = 1.0, airborne = false }, beams, 0, opts),
		"outside the arc -> safe")
	-- two-arm beam: arm 1 is at π, so a grounded body at π is struck.
	local two = {
		{ baseAngle = 0, direction = 1, baseSpeed = 0, armCount = 2, class = "low",
		  innerRadius = 3, outerRadius = 30, angularHalfWidth = 0.15 },
	}
	expect(M.isStruck({ radius = 10, angle = math.pi, airborne = false }, two, 0, opts),
		"second arm at π strikes")
	print("sweeper: isStruck OK")
end

-- outwardTarget: unit radial from center through the body, scaled to outRadius.
do
	local x, z = M.outwardTarget(5, 0, 0, 0, 30) -- body east of center
	expect(near(x, 30) and near(z, 0), "pushes straight out east to outRadius")
	local x2, z2 = M.outwardTarget(0, 0, 0, 0, 30) -- body exactly on center (degenerate)
	expect(near(x2, 30) and near(z2, 0), "degenerate center -> default +x")
	print("sweeper: outwardTarget OK")
end
```

- [ ] **Step 2: Run to verify failure**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: FAIL (`isStruck` is nil).

- [ ] **Step 3: Implement**

In `src/shared/SweeperModel.luau`, add before `return SweeperModel`:

```lua
-- Is a body struck by ANY arm of ANY beam on its tier right now?
-- body = { radius, angle, airborne }; beams = array of beam configs, each also carrying
-- { baseSpeed, class, innerRadius, outerRadius, angularHalfWidth }; opts = { rampPerSecond, maxSpeed }.
function SweeperModel.isStruck(body, beams, elapsed, opts)
	for _, beam in ipairs(beams) do
		if not SweeperModel.clears(beam.class, body.airborne) then
			local speed = SweeperModel.rampedSpeed(beam.baseSpeed, elapsed, opts)
			for armIndex = 0, beam.armCount - 1 do
				local a = SweeperModel.beamAngle(beam, armIndex, speed, elapsed)
				if SweeperModel.overlaps(body.radius, body.angle, a, beam) then
					return true
				end
			end
		end
	end
	return false
end

-- Outward radial target for a swept body: the point at `outRadius` from center along the
-- center->body direction. Plain numbers (no Vector3); the glue lifts (x,z) to a CFrame.
function SweeperModel.outwardTarget(bx, bz, cx, cz, outRadius)
	local dx, dz = bx - cx, bz - cz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return cx + outRadius, cz -- degenerate: body on center, pick +x
	end
	return cx + dx / len * outRadius, cz + dz / len * outRadius
end
```

Note: `overlaps` reads `innerRadius`/`outerRadius`/`angularHalfWidth` straight off each `beam` table (the glue includes those fields per beam at build time), so no separate opts table is needed here.

- [ ] **Step 4: Run to verify pass**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/shared/SweeperModel.luau tests/sweeper_model.spec.luau
git commit -m "feat(sweeper): isStruck composition + outwardTarget"
```

---

## Task 4: Config — `ACTIVE_ARENA` + the `SWEEP_*` block

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Add the config**

Add, right after the hex arena block (after `Config.HEX_FLOOR_COLORS = { ... }`, ~line 85):

```lua
-- ===== Arena selection =====
-- Which arena the round loop + client dressing use. "hex" (Hex-A-Gone) or "sweeper"
-- (Soul Sweeper). Selected once at startup by ArenaRegistry (server) and
-- ArenaDescriptor.forActive (client). Round-to-round rotation is a later change.
Config.ACTIVE_ARENA = "hex"

-- ===== Soul Sweeper arena (Arena #2) =====
-- Stacked circular discs over the void, WIDENING downward so a body swept off an upper
-- disc's rim is caught by the wider tier below; only a fall off the bottom disc = void.
-- Beams are cosmetic (client) + pure server strike math (SweeperModel). See the
-- 2026-07-07 spec. All angles in radians.
Config.SWEEP_TIER_COUNT = 3
Config.SWEEP_TOP_SURFACE_Y = 0        -- top (smallest) disc surface Y
Config.SWEEP_TIER_GAP = 50            -- vertical studs between tiers (mirrors HEX_FLOOR_GAP)
Config.SWEEP_TOP_RADIUS = 26          -- top disc radius (studs)
Config.SWEEP_RADIUS_STEP = 10         -- each lower disc is this much WIDER (catch geometry)
Config.SWEEP_DISC_THICKNESS = 2
Config.SWEEP_HUB_RADIUS = 3           -- inner dead zone: beams never strike inside the hub
Config.SWEEP_STAND_BAND = 6           -- root-height window above a tier that counts as "on" it (< SWEEP_TIER_GAP)
Config.SWEEP_AIRBORNE_BAND = 3        -- studs above the surface that count as airborne (clears low beams)
Config.SWEEP_AIRBORNE_VY = 8          -- upward root velocity (studs/s) that also counts as airborne
Config.SWEEP_OFF_MARGIN = 4           -- studs past the rim the sweep pushes a struck body
Config.SWEEP_BEAM_HALF_WIDTH = math.rad(9) -- angular half-width of a beam's strike arc (radians)

-- VOID_Y for the sweeper arena: 4 studs below the bottom disc (same rule hex uses).
Config.SWEEP_VOID_Y = Config.SWEEP_TOP_SURFACE_Y - (Config.SWEEP_TIER_COUNT - 1) * Config.SWEEP_TIER_GAP - 4

-- One distinct color per tier (top -> bottom) for post-swap depth orientation.
Config.SWEEP_TIER_COLORS = {
	Color3.fromRGB(245, 200, 70),   -- top (amber)
	Color3.fromRGB(70, 200, 180),   -- mid (teal)
	Color3.fromRGB(150, 120, 235),  -- bottom (indigo)
}

-- Per-tier beam configs (index = tier+1, top -> bottom). Each tier is an array of beams;
-- each beam = { baseAngle, direction (+1/-1), baseSpeed (rad/s), armCount, class }.
-- innerRadius/outerRadius/angularHalfWidth are attached from Config at build time
-- (hub..rim, SWEEP_BEAM_HALF_WIDTH). Lower tiers sweep faster (the endgame floors).
Config.SWEEP_TIER_BEAMS = {
	{ -- tier 0 (top, slowest): one low arm + one opposing high arm
		{ baseAngle = 0, direction = 1, baseSpeed = 0.6, armCount = 1, class = "low" },
		{ baseAngle = math.pi, direction = -1, baseSpeed = 0.5, armCount = 1, class = "high" },
	},
	{ -- tier 1 (mid): a faster two-arm low sweep
		{ baseAngle = 0, direction = 1, baseSpeed = 0.85, armCount = 2, class = "low" },
	},
	{ -- tier 2 (bottom, fastest): two-arm low + opposing high
		{ baseAngle = 0, direction = 1, baseSpeed = 1.05, armCount = 2, class = "low" },
		{ baseAngle = math.pi / 2, direction = -1, baseSpeed = 0.95, armCount = 1, class = "high" },
	},
}
Config.SWEEP_SPEED_RAMP_PER_SEC = 0.02 -- angular speed-up per second of round
Config.SWEEP_SPEED_MAX = 2.5           -- clamp

-- Cosmetic beam rendering (client).
Config.SWEEP_BEAM_LOW_COLOR = Color3.fromRGB(245, 170, 70)   -- amber: JUMP
Config.SWEEP_BEAM_HIGH_COLOR = Color3.fromRGB(225, 70, 70)   -- red: STAY GROUNDED
Config.SWEEP_BEAM_LOW_Y = 1.2          -- studs above the surface the low bar floats (ankle height)
Config.SWEEP_BEAM_HIGH_Y = 5.5         -- studs above the surface the high bar floats (clears a stander)
Config.SWEEP_BEAM_THICKNESS = 1.0      -- bar cross-section (studs)
Config.SWEEP_TELEGRAPH_LEAD = 0.35     -- radians ahead of a beam the faded telegraph sits
Config.SWEEP_TUMBLE_SECONDS = 0.6      -- cosmetic tumble spin duration on a sweep

-- Hybrid assets (blank "" => procedural fallback; filled by the MCP task later).
Config.SWEEP_DISC_MATERIAL = ""        -- MaterialVariant name / texture assetId for the discs
Config.SWEEP_BEAM_MATERIAL = ""        -- ditto for the beams
Config.SWEEP_HUB_MESH = ""             -- hero mesh assetId for the central emitter hub; fallback = cone
```

- [ ] **Step 2: Verify the suite still passes (no regressions)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: every suite prints its `ALL ... PASSED` line.

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(sweeper): Config block + ACTIVE_ARENA selector"
```

---

## Task 5: ArenaDescriptor — `sweeper()` + `forActive()`

**Files:**
- Modify: `src/shared/ArenaDescriptor.luau`

- [ ] **Step 1: Implement**

In `src/shared/ArenaDescriptor.luau`, add after `ArenaDescriptor.hex()` and before `ArenaDescriptor.validate`:

```lua
-- The Soul Sweeper arena's descriptor. footprint = the bottom (widest) disc's bounding
-- box, so Layer-2 dressing hugs the whole stack. One dressable level per tier (its
-- surface Y + color), top -> bottom, mirroring hex's per-floor levels.
function ArenaDescriptor.sweeper()
	local bottomRadius = Config.SWEEP_TOP_RADIUS + (Config.SWEEP_TIER_COUNT - 1) * Config.SWEEP_RADIUS_STEP
	local extent = bottomRadius * 2
	local levels = {}
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		levels[#levels + 1] = {
			y = Config.SWEEP_TOP_SURFACE_Y - k * Config.SWEEP_TIER_GAP,
			color = Config.SWEEP_TIER_COLORS[math.min(k + 1, #Config.SWEEP_TIER_COLORS)],
		}
	end
	return {
		center = Vector3.new(0, Config.SWEEP_TOP_SURFACE_Y, 0),
		footprint = Vector2.new(extent, extent),
		depth = Config.SWEEP_TIER_GAP * (Config.SWEEP_TIER_COUNT - 1),
		accent = Config.SWEEP_TIER_COLORS[1],
		levels = levels,
	}
end

-- Resolve the descriptor for the active arena (Config.ACTIVE_ARENA). Client dressing
-- consumes this instead of hardcoding a specific arena.
function ArenaDescriptor.forActive()
	if Config.ACTIVE_ARENA == "sweeper" then
		return ArenaDescriptor.sweeper()
	end
	return ArenaDescriptor.hex()
end
```

- [ ] **Step 2: Sanity-check (descriptor validates)**

There is no lune test for descriptors (they use Roblox types). Confirm by reading: `ArenaDescriptor.sweeper()` returns all fields `validate` asserts (`center` Vector3, `footprint` Vector2, `depth` number, `accent` Color3, non-empty `levels` of `{y, color}`). It does.

- [ ] **Step 3: Commit**

```bash
git add src/shared/ArenaDescriptor.luau
git commit -m "feat(sweeper): ArenaDescriptor.sweeper() + forActive()"
```

---

## Task 6: ArenaHazard contract + ArenaRegistry + HexHazard wrapper

**Files:**
- Create: `src/server/ArenaHazard.luau`
- Create: `src/server/HexHazard.luau`
- Create: `src/server/ArenaRegistry.luau`

- [ ] **Step 1: Create the interface contract**

Create `src/server/ArenaHazard.luau`:

```lua
--[[
	ArenaHazard -- the contract between RoundManager and a specific arena's hazard.
	RoundManager is arena-agnostic: it calls this interface, never a concrete arena.

	An ArenaHazard implements:
	  build()                 -- once at startup: construct geometry (replaces baseplate)
	  start(now)              -- beginRound: reset to the round-start state (now = os.clock())
	  step(now, samples)      -- per monitor tick: returns an `effects` table (see below)
	  stop()                  -- endRound: freeze to a safe resting state
	  descriptor()            -- returns the ArenaDescriptor for Layer-2 dressing
	  voidY()                 -- this arena's kill-plane Y

	`samples` = array of { position: Vector3, graceBlocked: boolean, player: Player,
	                       body: Model, velocityY: number } (one per alive body).
	`effects` = { sweeps = { { player, body, target: CFrame }, ... } }
	            -- RoundManager applies each sweep with reposition-then-re-own.
--]]

local ArenaHazard = {}

-- Cheap shape guard so a hazard implementation fails loudly if it's missing a method.
function ArenaHazard.validate(h)
	for _, name in ipairs({ "build", "start", "step", "stop", "descriptor", "voidY" }) do
		assert(type(h[name]) == "function", "ArenaHazard missing method: " .. name)
	end
	return h
end

return ArenaHazard
```

- [ ] **Step 2: Create the hex wrapper**

Create `src/server/HexHazard.luau`:

```lua
--[[
	HexHazard -- the Hex-A-Gone arena behind the ArenaHazard interface. A thin wrapper
	over the (unchanged) HazardSystem singleton so RoundManager can treat every arena
	uniformly. Hex never sweeps bodies (they fall through gone tiles by gravity), so
	step() returns empty effects.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)
local HazardSystem = require(script.Parent.HazardSystem)

local EMPTY = { sweeps = {} }

local HexHazard = {}

function HexHazard.build() HazardSystem.build() end
function HexHazard.start(now) HazardSystem.start(now) end
function HexHazard.stop() HazardSystem.stop() end

-- HazardSystem.step reads only sample.position + sample.graceBlocked; the extra
-- Sweeper fields on each sample are ignored. Hex enqueues no sweeps.
function HexHazard.step(now, samples)
	HazardSystem.step(now, samples)
	return EMPTY
end

function HexHazard.descriptor() return ArenaDescriptor.hex() end
function HexHazard.voidY() return Config.VOID_Y end

return HexHazard
```

- [ ] **Step 3: Create the registry**

Create `src/server/ArenaRegistry.luau`:

```lua
--[[
	ArenaRegistry -- resolves Config.ACTIVE_ARENA to the concrete ArenaHazard singleton.
	RoundManager calls forActive() once at startup and talks to the returned interface.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaHazard = require(script.Parent.ArenaHazard)
local HexHazard = require(script.Parent.HexHazard)
local SweeperHazard = require(script.Parent.SweeperHazard)

local ArenaRegistry = {}

function ArenaRegistry.forActive()
	local hazard
	if Config.ACTIVE_ARENA == "sweeper" then
		hazard = SweeperHazard
	else
		hazard = HexHazard
	end
	return ArenaHazard.validate(hazard)
end

return ArenaRegistry
```

> **Ordering note:** `ArenaRegistry` requires `SweeperHazard`, created in Task 8. To keep the
> branch compiling between tasks, create a minimal `src/server/SweeperHazard.luau` stub in THIS
> task returning a table with no-op `build/start/stop`, `step` → `{ sweeps = {} }`,
> `descriptor` → `ArenaDescriptor.sweeper()`, `voidY` → `Config.SWEEP_VOID_Y`. Task 8 fills it in.

Minimal stub (`src/server/SweeperHazard.luau`) for this task:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)

local EMPTY = { sweeps = {} }
local SweeperHazard = {}

function SweeperHazard.build() end
function SweeperHazard.start(_now) end
function SweeperHazard.stop() end
function SweeperHazard.step(_now, _samples) return EMPTY end
function SweeperHazard.descriptor() return ArenaDescriptor.sweeper() end
function SweeperHazard.voidY() return Config.SWEEP_VOID_Y end

return SweeperHazard
```

- [ ] **Step 4: Verify the suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: all green (these are server modules; the suite is unaffected but confirms no shared breakage).

- [ ] **Step 5: Commit**

```bash
git add src/server/ArenaHazard.luau src/server/HexHazard.luau src/server/ArenaRegistry.luau src/server/SweeperHazard.luau
git commit -m "feat(sweeper): ArenaHazard interface + ArenaRegistry + HexHazard wrapper (+ Sweeper stub)"
```

---

## Task 7: RoundManager — talk to the ArenaHazard interface

**Files:**
- Modify: `src/server/RoundManager.luau`

Goal: replace direct `HazardSystem.*` calls with the resolved `arena`, extend the per-tick sample, apply `effects.sweeps`, and use `arena.voidY()`. Hex behavior must be identical after this task.

- [ ] **Step 1: Swap the require + resolve the arena**

Replace (line ~34):
```lua
local HazardSystem = require(script.Parent.HazardSystem)
```
with:
```lua
local ArenaRegistry = require(script.Parent.ArenaRegistry)
```
And add, right after `local model = RoundState.new(...)` (~line 45):
```lua
-- The active arena hazard (hex or sweeper), resolved once. RoundManager is arena-agnostic.
local arena = ArenaRegistry.forActive()
```

- [ ] **Step 2: Use `arena.voidY()` in the floor probe**

In `hasFloorBeneath` (line ~172), replace both `Config.VOID_Y` reads:
```lua
local downTo = Config.VOID_Y - origin.Y
```
→
```lua
local downTo = arena.voidY() - origin.Y
```
(The comment mentioning `VOID_Y` can stay.)

- [ ] **Step 3: Extend the sample + apply sweeps + use `arena.step`/`voidY` in the monitor**

In `startMonitor`, the sample push (line ~443) currently is:
```lua
samples[#samples + 1] = {
	position = root.Position,
	graceBlocked = graceBlocked,
}
-- Void death source, gated by the post-swap grace window.
if root.Position.Y < Config.VOID_Y then
	RoundManager.eliminateFromHazard(player)
end
```
Replace with:
```lua
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
```
Then replace the `HazardSystem.step(t, samples)` call (line ~454) with:
```lua
local effects = arena.step(t, samples)
-- Apply any sweep requests (Sweeper arena) with reposition-then-re-own: the same
-- primitive as elimination/rescue, so a swept body's snap replicates onto the
-- client-owned body and is never read as a movement-validation violation.
if effects and effects.sweeps then
	for _, s in ipairs(effects.sweeps) do
		s.body:SetAttribute("SweptAt", workspace:GetServerTimeNow()) -- client tumble follows this
		BodyManager.pivotTo(s.body, s.target)
		ControlManager.regrantControl(s.player)
		noteServerReposition(s.body)
	end
end
```

- [ ] **Step 4: Replace the remaining lifecycle calls**

- `beginRound` (line ~504): `HazardSystem.start(now())` → `arena.start(now())`.
- `endRound` (line ~587): `HazardSystem.stop()` → `arena.stop()`.
- `RoundManager.start` (line ~747): `HazardSystem.build()` → `arena.build()`.

- [ ] **Step 5: Verify the suite + read-through**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: all green. Read-through: with `ACTIVE_ARENA="hex"`, `arena` is `HexHazard`, `voidY()` == `Config.VOID_Y`, `step` drives erosion and returns no sweeps — hex is behaviorally unchanged. (Live Studio hex-regression check is deferred to Task 15.)

- [ ] **Step 6: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(sweeper): RoundManager talks to the ArenaHazard interface (hex unchanged)"
```

---

## Task 8: SweeperHazard — procedural geometry + lifecycle

**Files:**
- Modify: `src/server/SweeperHazard.luau` (replace the Task-6 stub)

- [ ] **Step 1: Implement build/start/stop + tier helpers**

Replace `src/server/SweeperHazard.luau` with:

```lua
--[[
	SweeperHazard (server) -- the Soul Sweeper arena behind the ArenaHazard interface.
	Builds SWEEP_TIER_COUNT stacked circular COLLISION discs, WIDENING downward so a body
	swept off an upper disc's rim lands on the wider tier below; only a fall off the bottom
	disc crosses SWEEP_VOID_Y. Beams are cosmetic (client SweeperController); strikes are
	pure server math (SweeperModel), applied as outward re-pivot "sweeps" returned to
	RoundManager. No beam part ever collides with a body.

	Depends on: Config / SweeperModel / ArenaDescriptor.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config)
local SweeperModel = require(ReplicatedStorage.Shared.SweeperModel)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)

local EMPTY = { sweeps = {} }
local SweeperHazard = {}

local tiers = {}      -- [k+1] = { surfaceY, radius, beams }  (0-based tier k)
local startClock = 0  -- os.clock() at round start; elapsed = now - startClock

local function tierRadius(k) return Config.SWEEP_TOP_RADIUS + k * Config.SWEEP_RADIUS_STEP end
local function tierSurfaceY(k) return Config.SWEEP_TOP_SURFACE_Y - k * Config.SWEEP_TIER_GAP end

-- Attach the radius band + arc half-width to each beam config (the pure model reads them).
local function tierBeams(k, radius)
	local out = {}
	for _, b in ipairs(Config.SWEEP_TIER_BEAMS[k + 1] or {}) do
		out[#out + 1] = {
			baseAngle = b.baseAngle, direction = b.direction, baseSpeed = b.baseSpeed,
			armCount = b.armCount, class = b.class,
			innerRadius = Config.SWEEP_HUB_RADIUS,
			outerRadius = radius,
			angularHalfWidth = Config.SWEEP_BEAM_HALF_WIDTH,
		}
	end
	return out
end

local function makeDisc(folder, k)
	local r = tierRadius(k)
	local surfaceY = tierSurfaceY(k)
	local disc = Instance.new("Part")
	disc.Name = string.format("SweepDisc_%d", k)
	disc.Anchored = true
	disc.Shape = Enum.PartType.Cylinder
	-- Cylinder length is along local X; rotate 90° about Z so the round faces point up/down
	-- (a flat horizontal disc). Size = (thickness, diameter, diameter).
	disc.Size = Vector3.new(Config.SWEEP_DISC_THICKNESS, r * 2, r * 2)
	disc.CFrame = CFrame.new(0, surfaceY - Config.SWEEP_DISC_THICKNESS / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = Config.SWEEP_TIER_COLORS[math.min(k + 1, #Config.SWEEP_TIER_COLORS)]
	disc.Material = Enum.Material.SmoothPlastic
	disc.TopSurface = Enum.SurfaceType.Smooth
	disc.BottomSurface = Enum.SurfaceType.Smooth
	disc.Parent = folder

	-- Central emitter hub (procedural cone fallback for the hero mesh; the mesh is wired
	-- in the MCP task). Cosmetic + non-colliding, but server-built so it exists in both.
	local hub = Instance.new("Part")
	hub.Name = string.format("SweepHub_%d", k)
	hub.Anchored = true
	hub.CanCollide = false
	hub.Shape = Enum.PartType.Cylinder
	hub.Size = Vector3.new(4, Config.SWEEP_HUB_RADIUS * 2, Config.SWEEP_HUB_RADIUS * 2)
	hub.CFrame = CFrame.new(0, surfaceY + 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	hub.Color = Config.SWEEP_TIER_COLORS[math.min(k + 1, #Config.SWEEP_TIER_COLORS)]
	hub.Material = Enum.Material.Neon
	hub.Parent = folder
end

function SweeperHazard.build()
	if #tiers > 0 then return end
	-- The sweeper field IS the floor: remove the place template's baseplate + spawns.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then baseplate:Destroy() end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then child:Destroy() end
	end
	local folder = Workspace:FindFirstChild("SweeperField")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SweeperField"
		folder.Parent = Workspace
	end
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		local r = tierRadius(k)
		makeDisc(folder, k)
		tiers[k + 1] = { surfaceY = tierSurfaceY(k), radius = r, beams = tierBeams(k, r) }
	end
end

function SweeperHazard.start(now)
	startClock = now
	-- Publish the round-start time on the SERVER clock -> client, so the cosmetic beams
	-- render at the same elapsed the server strike math uses (both measure real seconds).
	local folder = Workspace:FindFirstChild("SweeperField")
	if folder then
		folder:SetAttribute("RoundStartServerT", Workspace:GetServerTimeNow())
	end
end

function SweeperHazard.stop() end

function SweeperHazard.descriptor() return ArenaDescriptor.sweeper() end
function SweeperHazard.voidY() return Config.SWEEP_VOID_Y end

-- step() is filled in Task 9.
function SweeperHazard.step(_now, _samples) return EMPTY end

return SweeperHazard
```

- [ ] **Step 2: Verify the suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: all green (shared model untouched; server module compiles by inspection).

- [ ] **Step 3: Commit**

```bash
git add src/server/SweeperHazard.luau
git commit -m "feat(sweeper): SweeperHazard procedural discs + hub + lifecycle"
```

---

## Task 9: SweeperHazard.step — strike detection + sweep effects

**Files:**
- Modify: `src/server/SweeperHazard.luau`

- [ ] **Step 1: Implement step + tier location + airborne**

In `src/server/SweeperHazard.luau`, add these helpers above `SweeperHazard.step` and replace the placeholder `step`:

```lua
-- Which tier is this Y on? The tier whose surface is at/just above the body within
-- SWEEP_STAND_BAND. Returns the tier record + its 0-based index, or nil (mid-fall).
local function tierAt(y)
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		local surfaceY = tierSurfaceY(k)
		if y <= surfaceY + Config.SWEEP_STAND_BAND and y >= surfaceY - Config.SWEEP_STAND_BAND then
			return tiers[k + 1], k
		end
	end
	return nil, nil
end
```

Replace `SweeperHazard.step`:

```lua
function SweeperHazard.step(now, samples)
	local sweeps = {}
	if not Config.HAZARDS_ENABLED then
		return { sweeps = sweeps }
	end
	local elapsed = now - startClock
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	for _, s in ipairs(samples) do
		if not s.graceBlocked then -- grace-protected bodies are never swept (free immunity)
			local pos = s.position
			local tier = tierAt(pos.Y)
			if tier then
				local dx, dz = pos.X, pos.Z -- center is (0,0)
				local radius = math.sqrt(dx * dx + dz * dz)
				local angle = math.atan2(dz, dx)
				local airborne = (pos.Y - tier.surfaceY) > Config.SWEEP_AIRBORNE_BAND
					or (s.velocityY or 0) > Config.SWEEP_AIRBORNE_VY
				if SweeperModel.isStruck({ radius = radius, angle = angle, airborne = airborne },
					tier.beams, elapsed, speedOpts) then
					local tx, tz = SweeperModel.outwardTarget(dx, dz, 0, 0, tier.radius + Config.SWEEP_OFF_MARGIN)
					-- Horizontal shove to just past the rim at the body's current height;
					-- gravity then drops it onto the wider tier below (or the void at the bottom).
					local target = CFrame.new(tx, pos.Y, tz)
					sweeps[#sweeps + 1] = { player = s.player, body = s.body, target = target }
				end
			end
		end
	end
	return { sweeps = sweeps }
end
```

- [ ] **Step 2: Verify the suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: all green. (Strike behavior itself is exercised live in Task 15; the decision math is already covered by `sweeper_model.spec.luau`.)

- [ ] **Step 3: Commit**

```bash
git add src/server/SweeperHazard.luau
git commit -m "feat(sweeper): strike detection + outward sweep effects"
```

---

## Task 10: SweeperController — cosmetic beams + predictive telegraph

**Files:**
- Create: `src/client/SweeperController.luau`

- [ ] **Step 1: Implement**

Create `src/client/SweeperController.luau`:

```lua
--[[
	SweeperController (client) -- 100% cosmetic beam rendering for the Soul Sweeper arena.
	Renders per-tier rotating beam bars (low = amber JUMP, high = red STAY GROUNDED) whose
	angle is computed from the pure SweeperModel at the SAME elapsed the server strike math
	uses (round-start server time read from the SweeperField attribute). A faded telegraph
	bar leads each beam so a just-swapped player can read their inherited spot. Never drives
	gameplay -- fed by authoritative state only.

	Location: StarterPlayerScripts/Client/SweeperController (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SweeperModel = require(Shared:WaitForChild("SweeperModel"))

local SweeperController = {}

local function tierRadius(k) return Config.SWEEP_TOP_RADIUS + k * Config.SWEEP_RADIUS_STEP end
local function tierSurfaceY(k) return Config.SWEEP_TOP_SURFACE_Y - k * Config.SWEEP_TIER_GAP end

local function newBar(folder, len, thickness, color, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(len, thickness, thickness)
	p.Parent = folder
	return p
end

-- One rendered arm: the solid beam + a faded leading telegraph bar.
local function buildArms()
	local folder = workspace:FindFirstChild("SweeperBeams")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "SweeperBeams"
	folder.Parent = Workspace

	local arms = {}
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		local r = tierRadius(k)
		for _, beam in ipairs(Config.SWEEP_TIER_BEAMS[k + 1] or {}) do
			local color = beam.class == "low" and Config.SWEEP_BEAM_LOW_COLOR or Config.SWEEP_BEAM_HIGH_COLOR
			local yOff = beam.class == "low" and Config.SWEEP_BEAM_LOW_Y or Config.SWEEP_BEAM_HIGH_Y
			for armIndex = 0, beam.armCount - 1 do
				arms[#arms + 1] = {
					beam = beam, armIndex = armIndex, k = k, radius = r,
					y = tierSurfaceY(k) + yOff,
					bar = newBar(folder, r, Config.SWEEP_BEAM_THICKNESS, color, 0),
					lead = newBar(folder, r, Config.SWEEP_BEAM_THICKNESS, color, 0.65),
				}
			end
		end
	end
	return folder, arms
end

-- Position a bar so its length runs from center out to the rim along `angle`.
local function placeBar(bar, angle, radius, y)
	local dirX, dirZ = math.cos(angle), math.sin(angle)
	local mid = Vector3.new(dirX * radius / 2, y, dirZ * radius / 2)
	bar.CFrame = CFrame.lookAt(mid, mid + Vector3.new(dirX, 0, dirZ)) * CFrame.Angles(0, math.rad(90), 0)
end

function SweeperController.start()
	local _folder, arms = buildArms()
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }

	RunService.RenderStepped:Connect(function()
		local field = Workspace:FindFirstChild("SweeperField")
		local startT = field and field:GetAttribute("RoundStartServerT")
		if not startT then return end -- no active sweeper round: leave bars where they are
		local elapsed = Workspace:GetServerTimeNow() - startT
		for _, a in ipairs(arms) do
			local speed = SweeperModel.rampedSpeed(a.beam.baseSpeed, elapsed, speedOpts)
			local angle = SweeperModel.beamAngle(a.beam, a.armIndex, speed, elapsed)
			placeBar(a.bar, angle, a.radius, a.y)
			local lead = angle + a.beam.direction * Config.SWEEP_TELEGRAPH_LEAD
			placeBar(a.lead, lead, a.radius, a.y)
		end
	end)
end

return SweeperController
```

- [ ] **Step 2: Verify the suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: all green (client module; visual correctness is a Task-15 Studio check).

- [ ] **Step 3: Commit**

```bash
git add src/client/SweeperController.luau
git commit -m "feat(sweeper): client cosmetic beams + predictive telegraph"
```

---

## Task 11: SweeperController — cosmetic tumble on `SweptAt`

**Files:**
- Modify: `src/client/SweeperController.luau`

The server already stamps `body:SetAttribute("SweptAt", ...)` on a sweep (Task 7). The client watches OWN body's `SweptAt` and plays a brief cosmetic spin, debounced so consecutive stamps don't restart it every tick.

- [ ] **Step 1: Implement the tumble watcher**

In `src/client/SweeperController.luau`, add near the top (after the requires):

```lua
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
```

Add this function above `SweeperController.start`:

```lua
-- Watch the local player's controlled body for a server sweep stamp and play a brief
-- cosmetic tumble (a decaying spin on the body's root). Debounced: ignores stamps that
-- arrive while a tumble is already playing. Fed by authoritative state; never drives it.
local function watchTumble(getOwnBody)
	local tumbling = false
	local function attach(body)
		local root = body and body:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local last = 0
		body:GetAttributeChangedSignal("SweptAt"):Connect(function()
			local t = body:GetAttribute("SweptAt")
			if not t or t == last or tumbling then return end
			last = t
			tumbling = true
			task.spawn(function()
				local dur = Config.SWEEP_TUMBLE_SECONDS
				local t0 = os.clock()
				while os.clock() - t0 < dur do
					local f = 1 - (os.clock() - t0) / dur -- decay
					root.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(18 * f))
					RunService.RenderStepped:Wait()
				end
				tumbling = false
			end)
		end)
	end
	-- Re-attach whenever the controlled body changes (SetControlledBody remote already exists).
	task.spawn(function()
		while true do
			attach(getOwnBody())
			task.wait(1)
		end
	end)
end
```

> **Integration note for the implementer:** `getOwnBody` should return the client's currently
> controlled body model. Reuse whatever the client already uses to track it (the same source
> `SoulController`/`ClientControl` reads for the local body, e.g. the `SetControlledBody` remote's
> last value). If a shared accessor exists, pass it; otherwise thread the controlled-body
> reference from the client bootstrap. Do NOT add a client→server remote.

In `SweeperController.start`, add a parameter and call:
```lua
function SweeperController.start(getOwnBody)
	if getOwnBody then watchTumble(getOwnBody) end
	local _folder, arms = buildArms()
	-- ... rest unchanged ...
```

- [ ] **Step 2: Verify the suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: all green.

- [ ] **Step 3: Commit**

```bash
git add src/client/SweeperController.luau
git commit -m "feat(sweeper): cosmetic tumble on server SweptAt stamp"
```

---

## Task 12: Client arena selection — dress + start the active arena

**Files:**
- Modify: `src/client/ArenaDressing.luau`
- Modify: the client bootstrap that calls `ArenaDressing.start()`

- [ ] **Step 1: Dress the active arena**

In `src/client/ArenaDressing.luau`, `ArenaDressing.start()`, replace:
```lua
local desc = ArenaDescriptor.validate(ArenaDescriptor.hex())
```
with:
```lua
local desc = ArenaDescriptor.validate(ArenaDescriptor.forActive())
```
(The floor-trim + banner dressing is footprint-parametric, so it dresses either arena's
descriptor unchanged.)

- [ ] **Step 2: Start SweeperController when the sweeper arena is active**

Find the client bootstrap that calls `ArenaDressing.start()` (search the client tree:
`grep -rl "ArenaDressing" src/client`). In that bootstrap, after starting `ArenaDressing`,
add:

```lua
local Config = require(ReplicatedStorage.Shared.Config) -- if not already required
if Config.ACTIVE_ARENA == "sweeper" then
	local SweeperController = require(script.Parent.SweeperController) -- adjust path to match the bootstrap
	SweeperController.start(getOwnBody) -- pass the client's controlled-body accessor if available; else SweeperController.start()
end
```

> The exact require path + the `getOwnBody` accessor depend on the bootstrap's structure; match
> the surrounding requires. If no controlled-body accessor is readily available, call
> `SweeperController.start()` with no argument (beams + telegraph still work; the tumble is a
> cosmetic nice-to-have that can be wired in a follow-up).

- [ ] **Step 3: Verify the suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add src/client/ArenaDressing.luau src/client/<bootstrap-file>.luau
git commit -m "feat(sweeper): client dresses + starts the active arena"
```

---

## Task 13: Docs — smoke test, CHANGELOG, roadmap

**Files:**
- Create: `docs/smoke-tests/2026-07-07-soul-sweeper-smoke-test.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/world-enrichment-roadmap.md`

- [ ] **Step 1: Write the smoke-test doc**

Create `docs/smoke-tests/2026-07-07-soul-sweeper-smoke-test.md`:

```markdown
# Soul Sweeper — Manual Smoke Test (2026-07-07)

**Requires:** `Config.ACTIVE_ARENA = "sweeper"`. Studio Play (single-client for geometry;
2-client for the swap + latency cases). Beams cosmetic; strikes server-side.

## Setup
1. Set `Config.ACTIVE_ARENA = "sweeper"`. Sync with Rojo, Play.
2. Confirm boot: no console errors; `Workspace.SweeperField` has `SWEEP_TIER_COUNT` discs +
   hubs; discs WIDEN downward; no Baseplate; `Workspace.SweeperBeams` renders rotating bars.

## Cases
1. **Geometry / orientation** — each tier is a distinct color; the bottom disc is widest;
   the kill-plane (`SWEEP_VOID_Y`) sits ~4 studs under the bottom disc.
2. **Beam sync** — a low (amber) bar and a high (red) bar rotate; the faded telegraph leads
   each beam in its rotation direction; lower tiers visibly sweep faster; speed ramps over
   the round.
3. **Low beam = jump** — stand grounded in a low beam's path → swept off (re-pivoted outward)
   → caught by the wider tier below. Jump as it passes → survive.
4. **High beam = stay grounded** — stand grounded under a high beam → survive; jump into it →
   swept off.
5. **Descent + void death** — get swept off the bottom disc → fall past `SWEEP_VOID_Y` →
   eliminated (Elimination event fires; body sent to balcony). Swept off an UPPER disc →
   land on the tier below, still alive.
6. **Grace immunity (observe-first)** — immediately after a swap (or round start), a body in
   a beam's path is NOT swept for the grace window; after grace, normal rules resume.
7. **Cosmetic tumble** — on a sweep, the body plays a brief spin; it does not desync position
   (server owns the outcome).
8. **Swap-onto-incoming-beam** — 2-client: force swaps (`RoundManager.forceSwap()`); confirm a
   player dropped near a beam gets the grace beat and can react; note the inherited-hit feel.
9. **Exploit** — a client holding position in a beam is still swept (server-authoritative);
   movement validator does not fight the sweep (no rubber-band war).

## Results
(Fill in during the session; note any tuning changes to SWEEP_* Config values.)
```

- [ ] **Step 2: Update CHANGELOG**

Add an entry at the top of `CHANGELOG.md` under a new dated heading (match the file's existing
style), summarizing: "Soul Sweeper (arena #2) behind a new `ArenaHazard` interface; hex refactored
behind it; pure `SweeperModel` (lune-tested); server-math strikes + deterministic re-pivot sweep +
cosmetic tumble; `Config.ACTIVE_ARENA` selector; procedural build with a materials + one-hero-mesh
hybrid layer pending asset sourcing."

- [ ] **Step 3: Update the roadmap**

In `docs/world-enrichment-roadmap.md`, add a short note (Parking-lot or a new line) that Arena #2
"Soul Sweeper" has shipped its procedural core behind the `ArenaHazard` interface, with the hybrid
asset layer (materials + hero mesh) pending MCP asset sourcing; link the spec + this plan.

- [ ] **Step 4: Commit**

```bash
git add docs/smoke-tests/2026-07-07-soul-sweeper-smoke-test.md CHANGELOG.md docs/world-enrichment-roadmap.md
git commit -m "docs(sweeper): smoke test + CHANGELOG + roadmap note"
```

---

## Task 14 (MCP-REQUIRED — DEFER if MCP unreachable): source the hybrid assets

**Precondition:** Roblox_Studio MCP reachable. If not, SKIP and leave the procedural fallback.

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Source assets via MCP**

Using the Studio MCP: source/generate (a) a disc surface material, (b) a beam energy material,
(c) one hero mesh for the central emitter hub. Upload so they land in the owner's inventory; note
the resulting asset IDs / MaterialVariant names.

- [ ] **Step 2: Wire the IDs into Config**

Set `Config.SWEEP_DISC_MATERIAL`, `Config.SWEEP_BEAM_MATERIAL`, `Config.SWEEP_HUB_MESH` to the
sourced IDs. Ensure the build code applies them when non-empty and falls back to procedural when
`""` (the disc/hub/beam builders check the field before applying; add the guarded application if
not already present).

- [ ] **Step 3: Verify fallback + sourced both render**

In Studio: with IDs set → sourced look; blank one out → procedural fallback still renders. No
second geometry path — assets only re-dress the procedural parts.

- [ ] **Step 4: Commit**

```bash
git add src/shared/Config.luau src/server/SweeperHazard.luau src/client/SweeperController.luau
git commit -m "feat(sweeper): wire hybrid assets (materials + hero hub mesh) with fallback"
```

---

## Task 15 (MCP-REQUIRED — DEFER if MCP unreachable): live glue verification

**Precondition:** Roblox_Studio MCP reachable.

- [ ] **Step 1: Hex regression** — set `ACTIVE_ARENA="hex"`, Play; confirm hex builds, erodes,
  and eliminations behave exactly as before the interface refactor (Task 7 did not change hex).
- [ ] **Step 2: Sweeper glue** — set `ACTIVE_ARENA="sweeper"`, Play; walk the smoke-test cases
  1–7 solo via MCP `execute_luau`/`start_stop_play`/`get_console_output`; verify disc orientation
  (the Cylinder 90° rotation), tier bands, strike→sweep→tier-catch, grace skip, `SweptAt` tumble.
- [ ] **Step 3: Tune** — adjust `SWEEP_AIRBORNE_BAND`/`_VY`, `SWEEP_BEAM_HALF_WIDTH`, tier speeds
  so a normal jump reliably clears a low beam and a grounded stance reliably survives a high beam.
  Record final values.
- [ ] **Step 4: Fill smoke-test results** and commit any tuning + the results doc.

```bash
git add docs/smoke-tests/2026-07-07-soul-sweeper-smoke-test.md src/shared/Config.luau
git commit -m "test(sweeper): Studio MCP glue verification + tuning"
```

---

## Self-Review notes (author)

- **Spec coverage:** interface (T6/T7), pure model (T1–T3), geometry/descent (T8), strikes+sweep
  (T9), fairness grace-skip (T9 `graceBlocked`), cosmetic beams+telegraph (T10), tumble via
  `SweptAt` (T7 stamp + T11 watcher), arena selection (T4/T5/T12), hybrid build (T8 procedural +
  T14 assets), voidY on the interface (T6/T7), tests (T1–T3), smoke doc (T13). All spec sections map.
- **Type consistency:** beam configs carry `{baseAngle, direction, baseSpeed, armCount, class}` in
  Config (T4) and gain `{innerRadius, outerRadius, angularHalfWidth}` at build (T8 `tierBeams`),
  matching what `SweeperModel.isStruck`/`overlaps` read (T2/T3). `effects.sweeps[i] =
  {player, body, target}` produced in T9, consumed in T7. `SweptAt` stamped in T7, watched in T11.
  `RoundStartServerT` set in T8, read in T10.
- **MCP boundary:** T1–T13 need no MCP; T14–T15 are gated and deferrable without blocking the branch.
```
