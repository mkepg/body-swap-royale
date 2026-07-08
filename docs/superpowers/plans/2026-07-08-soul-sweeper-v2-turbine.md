# Soul Sweeper v2 — "Soul Turbine" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Soul Sweeper as a single Soul-Turbine annulus arena with solid physics beams, and convert the world to a persistent two-arena layout with per-round rotation and full idle-arena dormancy.

**Architecture:** The pure `SweeperModel` (unchanged) stays the single source of truth for beam angles — server Heartbeat animation, the anti-cheat strike backstop, and all client cosmetics derive from it. `SweeperHazard` v2 owns collision geometry (segmented annulus, hub, two solid beams) and returns `{sweeps, reseeds}` effects; `RoundManager` gains per-round arena rotation (pure `ArenaRotationModel`), a `LiveArena` workspace attribute, per-round spawn-slot assignment via a new `spawnCFrame(index)` interface method, and grace-body collision-group flips. The client rewrites `SweeperController` as a single shared cosmetic loop (telegraph, wake channels, rotors, chase, shaft) fully gated on `LiveArena`.

**Tech Stack:** Luau, Rojo, rokit/lune, Roblox Studio MCP (verification + asset sourcing — NOW AVAILABLE), PhysicsService collision groups.

**Spec:** `docs/superpowers/specs/2026-07-08-soul-sweeper-v2-turbine-design.md` (read it first — every task below implements a numbered spec section).

**Conventions:** identical to the v1 plan (`docs/superpowers/plans/2026-07-07-soul-sweeper-arena.md` header): pure modules in `src/shared/` lune-tested via `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`; full suite must stay green after every task (`for f in tests/*.spec.luau; do lune run "$f" || break; done` — 23 suites today, 24 after Task 1). Commit per task, no Co-Authored-By on task commits.

---

## File Structure

- Create `src/shared/ArenaRotationModel.luau` + `tests/arena_rotation_model.spec.luau` (pure).
- Modify `src/shared/Config.luau` — SWEEP_* v2 rework; `ACTIVE_ARENA` → `ARENA_OVERRIDE`; `LOBBY_FACE_TARGET`.
- Modify `src/shared/ArenaDescriptor.luau` — sweeper() v2 (annulus), `all()`; drop `forActive()`.
- Modify `src/server/ArenaHazard.luau` — contract adds `id` + `spawnCFrame`.
- Modify `src/server/ArenaRegistry.luau` — `all()` / `get(id)` / `ids()`; drop `forActive()`.
- Modify `src/server/HexHazard.luau` — `id = "hex"`, `spawnCFrame(index)` (hex spiral math).
- Rewrite `src/server/SweeperHazard.luau` — annulus/hub/beams geometry, collision groups, Heartbeat animation, backstop + reseeds, ring spawns.
- Modify `src/server/BodyManager.luau` — add `setArenaSlot(player, cf)` (creation-time hex default stays).
- Modify `src/server/RoundManager.luau` — rotation, build-all, `LiveArena`, per-round slots, grace collision groups, apply reseeds.
- Rewrite `src/client/SweeperController.luau` — v2 cosmetics + dormancy (beams no longer client-built).
- Modify `src/client/ArenaDressing.luau` — dress ALL descriptors.
- Modify `src/client/init.client.luau` — start SweeperController unconditionally (self-gating).
- Docs: new smoke doc `docs/smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md`; CHANGELOG; roadmap.

**MCP-gated (controller executes directly, not subagents):** Task 9 (Studio verification), Task 10 (asset sourcing).

---

## Task 1: `ArenaRotationModel` (pure, TDD)

**Files:** Create `src/shared/ArenaRotationModel.luau`; Test `tests/arena_rotation_model.spec.luau`.

- [ ] **Step 1: Failing test** — create `tests/arena_rotation_model.spec.luau`:

```lua
local M = require("../src/shared/ArenaRotationModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local IDS = { "hex", "sweeper" }

-- alternation: nil/unknown current -> first; known current -> next, wrapping.
do
	expect(M.next(nil, IDS, "") == "hex", "no current -> first arena")
	expect(M.next("hex", IDS, "") == "sweeper", "hex -> sweeper")
	expect(M.next("sweeper", IDS, "") == "hex", "sweeper wraps back to hex")
	expect(M.next("bogus", IDS, "") == "hex", "unknown current -> first arena")
	print("rotation: alternation OK")
end

-- override pins when it names a known arena; unknown override falls back to rotation.
do
	expect(M.next("hex", IDS, "hex") == "hex", "override pins hex")
	expect(M.next("sweeper", IDS, "hex") == "hex", "override pins regardless of current")
	expect(M.next("hex", IDS, "nope") == "sweeper", "unknown override -> normal rotation")
	expect(M.next("hex", IDS, nil) == "sweeper", "nil override -> normal rotation")
	print("rotation: override OK")
end

-- single-arena list is stable.
do
	expect(M.next(nil, { "hex" }, "") == "hex", "single arena -> itself")
	expect(M.next("hex", { "hex" }, "") == "hex", "single arena repeats")
	print("rotation: single-arena OK")
end

print("ALL ArenaRotationModel TESTS PASSED")
```

- [ ] **Step 2: Run, expect FAIL** (module not found).
- [ ] **Step 3: Implement** `src/shared/ArenaRotationModel.luau`:

```lua
--[[
	ArenaRotationModel -- PURE per-round arena selection.
	Location (Roblox): ReplicatedStorage/Shared/ArenaRotationModel (ModuleScript)

	next(currentId, arenaIds, override) decides which arena hosts the next round:
	  - override naming a known arena pins it (Config.ARENA_OVERRIDE, dev/test),
	  - otherwise simple alternation through arenaIds (wraps),
	  - nil/unknown currentId starts at the first arena.
	No clock reads / RNG (lune-tested).
--]]

local ArenaRotationModel = {}

function ArenaRotationModel.next(currentId, arenaIds, override)
	if override ~= nil and override ~= "" then
		for _, id in ipairs(arenaIds) do
			if id == override then
				return override
			end
		end
	end
	for i, id in ipairs(arenaIds) do
		if id == currentId then
			return arenaIds[(i % #arenaIds) + 1]
		end
	end
	return arenaIds[1]
end

return ArenaRotationModel
```

- [ ] **Step 4: Run, expect PASS**; full suite (now 24) green.
- [ ] **Step 5: Commit** `feat(sweeper-v2): pure ArenaRotationModel + tests`.

---

## Task 2: Config v2 + ArenaDescriptor v2

**Files:** Modify `src/shared/Config.luau`, `src/shared/ArenaDescriptor.luau`.

- [ ] **Step 1: Rework the Config arena-selection + SWEEP_* block.** Replace `Config.ACTIVE_ARENA = "hex"` and the ENTIRE v1 `SWEEP_*` block with:

```lua
-- ===== Arena selection =====
-- Rounds ROTATE between arenas (pure ArenaRotationModel). ARENA_OVERRIDE pins one
-- arena for dev/testing ("hex" | "sweeper"); "" = rotate. Replaces the v1
-- ACTIVE_ARENA build switch: ALL arenas are always built (persistent world).
Config.ARENA_OVERRIDE = ""

-- ===== Soul Sweeper arena v2 -- "Soul Turbine" (see 2026-07-08 spec) =====
-- One annulus platform around a central turbine hub; two solid stacked beams
-- (low amber = JUMP, high crimson = STAY GROUNDED) server-animated from the pure
-- SweeperModel angle(t). Fall off the rim or into the hub gap -> void.
Config.SWEEP_CENTER = Vector3.new(110, 0, 0) -- platform center (hex stays at origin)
Config.SWEEP_SURFACE_Y = 0
Config.SWEEP_PLATFORM_RADIUS = 38    -- outer rim
Config.SWEEP_HOLE_RADIUS = 10        -- center hole (gap ring = HUB..HOLE radius)
Config.SWEEP_HUB_RADIUS = 5          -- turbine pillar inside the hole
Config.SWEEP_PLATFORM_SEGMENTS = 28  -- tangent boxes approximating the annulus
Config.SWEEP_SEGMENT_SLACK = 1.08    -- segment length vs chord (overlap => no seams)
Config.SWEEP_PLATFORM_THICKNESS = 2
Config.SWEEP_PLATFORM_COLOR = Color3.fromRGB(20, 26, 48)   -- dark glass/metal indigo
Config.SWEEP_ACCENT = Color3.fromRGB(244, 162, 97)         -- turbine amber
Config.SWEEP_VOID_Y = Config.SWEEP_SURFACE_Y - 24 -- kill-plane (a visible fall beat)
Config.SWEEP_STAND_BAND = 6          -- Y band above/below the surface that counts as "on" it
Config.SWEEP_SPAWN_RADIUS = 24       -- spawn ring (mid-annulus)

-- The two beams (flat list -- one platform). Each: baseAngle, direction, baseSpeed
-- (rad/s), armCount, class. Radius band + arc half-width attached at build time.
Config.SWEEP_BEAMS = {
	{ baseAngle = 0, direction = 1, baseSpeed = 0.7, armCount = 1, class = "low" },
	{ baseAngle = math.pi, direction = -1, baseSpeed = 0.55, armCount = 1, class = "high" },
}
Config.SWEEP_BEAM_HALF_WIDTH = math.rad(9)
Config.SWEEP_SPEED_RAMP_PER_SEC = 0.02
Config.SWEEP_SPEED_MAX = 2.5
Config.SWEEP_AIRBORNE_BAND = 3
Config.SWEEP_AIRBORNE_VY = 8
Config.SWEEP_OFF_MARGIN = 4          -- backstop re-pivot pushes this far past the rim
Config.SWEEP_RESIST_TICKS = 3        -- consecutive struck ticks before the backstop fires
Config.SWEEP_RESEED_MARGIN = math.rad(12) -- extra arc where movement validation is reseeded

-- Physical beams (server parts) + cosmetics.
Config.SWEEP_BEAM_LOW_Y = 1.2
Config.SWEEP_BEAM_HIGH_Y = 5.5       -- must clear a grounded body; live-tuning knob
Config.SWEEP_BEAM_SIZE = Vector3.new(1.2, 1.0, 1.0) -- cross-section (length computed)
Config.SWEEP_BEAM_LOW_COLOR = Color3.fromRGB(244, 162, 97)  -- amber: JUMP
Config.SWEEP_BEAM_HIGH_COLOR = Color3.fromRGB(225, 75, 75)  -- crimson: STAY GROUNDED
Config.SWEEP_TELEGRAPH_LEAD = 0.35
Config.SWEEP_TUMBLE_SECONDS = 0.6

-- Soul Turbine dressing (client; budgets: <=180 parts, one shared loop, <=40 writes/frame).
Config.SWEEP_WAKE_CHANNELS = 36      -- radial floor strips igniting in the low beam's wake
Config.SWEEP_WAKE_FADE = 1.2         -- seconds a wake strip takes to fade
Config.SWEEP_CHASE_STUDS = 32        -- rim marquee chase lights
Config.SWEEP_STANDBY_TRANSPARENCY = 0.85 -- dormant-arena Neon dim (one-time flip)

-- Hybrid assets ("" => procedural fallback; filled by the MCP sourcing task).
Config.SWEEP_DISC_MATERIAL = ""
Config.SWEEP_BEAM_MATERIAL = ""
Config.SWEEP_HUB_MESH = ""
```

Also change `Config.LOBBY_FACE_TARGET` to `Vector3.new(55, 0, 0)` (midpoint between arenas) and update its comment.

- [ ] **Step 2: ArenaDescriptor v2.** Replace `sweeper()` and `forActive()` with:

```lua
-- Soul Sweeper v2 descriptor: one annulus level at the platform surface.
function ArenaDescriptor.sweeper()
	local extent = Config.SWEEP_PLATFORM_RADIUS * 2
	return {
		center = Vector3.new(Config.SWEEP_CENTER.X, Config.SWEEP_SURFACE_Y, Config.SWEEP_CENTER.Z),
		footprint = Vector2.new(extent, extent),
		depth = Config.SWEEP_SURFACE_Y - Config.SWEEP_VOID_Y,
		accent = Config.SWEEP_ACCENT,
		levels = { { y = Config.SWEEP_SURFACE_Y, color = Config.SWEEP_ACCENT } },
	}
end

-- Every arena's descriptor (persistent world: the client dresses ALL of them).
function ArenaDescriptor.all()
	return { ArenaDescriptor.hex(), ArenaDescriptor.sweeper() }
end
```

Grep the repo for remaining `forActive` / `ACTIVE_ARENA` references — they are updated in Tasks 5–7; note them, don't fix here.

- [ ] **Step 3:** Full suite green (24). **Commit** `feat(sweeper-v2): Config rework + annulus descriptor + all()`.

---

## Task 3: Interface v2 — `id` + `spawnCFrame`, registry, BodyManager setter

**Files:** Modify `src/server/ArenaHazard.luau`, `src/server/ArenaRegistry.luau`, `src/server/HexHazard.luau`, `src/server/BodyManager.luau`.

- [ ] **Step 1: Contract.** In `ArenaHazard.luau`: extend the doc header with `id: string` (arena identifier), `spawnCFrame(index) -> CFrame` (1-based round spawn slot), and the v2 `effects` shape `{ sweeps = {...}, reseeds = { body, ... } }`. In `validate`, add `"spawnCFrame"` to the method list and `assert(type(h.id) == "string" and h.id ~= "", "ArenaHazard.id must be a non-empty string")`.

- [ ] **Step 2: Registry.** Replace `ArenaRegistry.forActive()` with:

```lua
local ARENAS = { HexHazard, SweeperHazard } -- rotation order

function ArenaRegistry.all()
	for _, a in ipairs(ARENAS) do ArenaHazard.validate(a) end
	return ARENAS
end

function ArenaRegistry.ids()
	local ids = {}
	for _, a in ipairs(ARENAS) do ids[#ids + 1] = a.id end
	return ids
end

function ArenaRegistry.get(id)
	for _, a in ipairs(ARENAS) do
		if a.id == id then return a end
	end
	error("ArenaRegistry.get: unknown arena id " .. tostring(id))
end
```

- [ ] **Step 3: HexHazard.** Add `HexHazard.id = "hex"` and (requires `HexGrid`):

```lua
-- Round spawn slot: the existing hex spawn spiral (same math BodyManager uses for
-- its creation-time default), exposed through the interface for per-round assignment.
local HEX_SLOTS = HexGrid.spawnSlots(Config.HEX_RADIUS)

function HexHazard.spawnCFrame(index)
	local o = Config.SPAWN_ORIGIN
	local slot = HEX_SLOTS[index] or HEX_SLOTS[#HEX_SLOTS]
	local dx, dz = HexGrid.toWorld(slot.q, slot.r, Config.HEX_SIZE)
	return CFrame.new(o.X + dx, o.Y, o.Z + dz)
end
```

Also add a temporary `SweeperHazard.id = "sweeper"` + stub `spawnCFrame` returning `CFrame.new(Config.SWEEP_CENTER + Vector3.new(0, 5, 0))` so `validate` passes until Task 5 replaces it (note in code: Task 5 fills this in).

- [ ] **Step 4: BodyManager.** Add (near `resetBody`):

```lua
-- Per-round arena slot assignment (persistent-world rotation): RoundManager sets each
-- participant's slot from the LIVE arena's spawnCFrame at round start. The creation-time
-- hex default above remains only as a harmless placeholder until the first round.
function BodyManager.setArenaSlot(player, cf)
	BodyManager.arenaSlotByOwner[player] = cf
end
```

(Verify `arenaSlotByOwner` is the exported table name by reading the file; adapt if it is module-local — if so, export a setter over the local.)

- [ ] **Step 5:** Full suite green. **Commit** `feat(sweeper-v2): ArenaHazard id+spawnCFrame, registry all/get, BodyManager.setArenaSlot`.

---

## Task 4: SweeperHazard v2 — geometry + collision groups

**Files:** Rewrite `src/server/SweeperHazard.luau` (keep the module doc-header style; spec §3, §4).

- [ ] **Step 1: Rewrite build/lifecycle.** Key requirements (write the full module; `step`/animation land in Task 5):

```lua
-- Collision groups: registered ONCE in build() (before any body can be flagged).
local PhysicsService = game:GetService("PhysicsService")
local function ensureCollisionGroups()
	pcall(function() PhysicsService:RegisterCollisionGroup("SweepBeam") end)
	pcall(function() PhysicsService:RegisterCollisionGroup("GraceBody") end)
	PhysicsService:CollisionGroupSetCollidable("SweepBeam", "GraceBody", false)
end
```

- `build()`: `ensureCollisionGroups()`; destroy Baseplate/SpawnLocations (keep the v1 pattern); create `SweeperField` folder; build:
  - **Annulus:** `Config.SWEEP_PLATFORM_SEGMENTS` anchored boxes on `WorldLayout.ring(center.X, center.Z, midRadius, segments)` where `midRadius = (SWEEP_HOLE_RADIUS + SWEEP_PLATFORM_RADIUS)/2`; each box `Size = Vector3.new(chord * SWEEP_SEGMENT_SLACK, SWEEP_PLATFORM_THICKNESS, SWEEP_PLATFORM_RADIUS - SWEEP_HOLE_RADIUS)` with `chord = 2 * midRadius * math.sin(math.pi / segments)`, positioned at the ring point with top at `SWEEP_SURFACE_Y`, **oriented tangent** (`CFrame.lookAt(here, nextPoint)` — note lookAt aims -Z along the tangent so the Z axis is tangential; size the box accordingly: `Size = Vector3.new(width_radial, thickness, chord*slack)` with X radial. Pick ONE consistent convention and match size axes to it — copy the lobby-barrier segment orientation from `src/server/LobbyArea.luau` which solved exactly this). Color `SWEEP_PLATFORM_COLOR`, `Glass` material at 0 transparency (fallback look), named `SweepFloor_<i>`.
  - **Hub pillar:** anchored Cylinder radius `SWEEP_HUB_RADIUS`, from ~6 below the surface to ~8 above, at `SWEEP_CENTER` (Cylinder axis vertical via the 90° Z-roll proven in v1), `CanCollide = true`, default group, named `SweepHub`.
  - **Two beam parts:** for each `Config.SWEEP_BEAMS[i]`: anchored box, length `span = SWEEP_PLATFORM_RADIUS - SWEEP_HUB_RADIUS`, `Size = Vector3.new(span, SWEEP_BEAM_SIZE.Y, SWEEP_BEAM_SIZE.Z)`, Neon, class color, `CanCollide = true`, `CollisionGroup = "SweepBeam"`, named `SweepBeam_low` / `SweepBeam_high`, parked at `baseAngle` at height `surface + SWEEP_BEAM_LOW_Y/HIGH_Y`. Position helper (used by park + Task 5 animation):

```lua
local function beamCFrame(beam, angle, y)
	local c = Config.SWEEP_CENTER
	local mid = Config.SWEEP_HUB_RADIUS + (Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS) / 2
	return CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, -angle, 0) * CFrame.new(mid, Config.SWEEP_SURFACE_Y + y, 0)
end
```

  (Note the `-angle` yaw: Roblox yaw is counter-clockwise about +Y while `atan2(z, x)` angles
  increase clockwise when viewed from +Y with +Z toward the viewer — the strike math and the part
  animation MUST agree; Task 9 verifies this live with a stationary-probe test. If they disagree,
  flip the sign HERE, never in the pure model.)
- `start(now)`: `startClock = now`; set `RoundStartServerT` attribute (v1 pattern). Animation connect happens here too (Task 5).
- `stop()`: disconnect animation; re-park beams at `baseAngle`.
- `descriptor()/voidY()/id/spawnCFrame`: id `"sweeper"`; `voidY() = Config.SWEEP_VOID_Y`; `descriptor() = ArenaDescriptor.sweeper()`; spawnCFrame in Task 5.

- [ ] **Step 2:** Full suite green. **Commit** `feat(sweeper-v2): annulus + hub + solid beam geometry, collision groups`.

---

## Task 5: SweeperHazard v2 — animation, backstop, reseeds, spawns

**Files:** Modify `src/server/SweeperHazard.luau`.

- [ ] **Step 1: Heartbeat animation (live-gated by connection lifetime).**

```lua
local RunService = game:GetService("RunService")
local animConn = nil

local function angleOf(beam, elapsed)
	local speed = SweeperModel.rampedSpeed(beam.baseSpeed, elapsed,
		{ rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX })
	return SweeperModel.beamAngle(beam, 0, speed, elapsed)
end

local function startAnimation()
	if animConn then return end
	animConn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startClock
		for _, rec in ipairs(beamRecs) do -- { beam = config, part = Part, y = height }
			rec.part.CFrame = beamCFrame(rec.beam, angleOf(rec.beam, elapsed), rec.y)
		end
	end)
end

local function stopAnimation()
	if animConn then animConn:Disconnect(); animConn = nil end
	for _, rec in ipairs(beamRecs) do
		rec.part.CFrame = beamCFrame(rec.beam, rec.beam.baseAngle, rec.y) -- park
	end
end
```

`start(now)` calls `startAnimation()`; `stop()` calls `stopAnimation()`. **Dormancy holds by
construction:** only the live arena's `start` runs, so a dormant sweeper has zero per-frame writes.

- [ ] **Step 2: `step` — backstop + reseeds.** Replace the v1 tiered step:

```lua
local strikeTicks = {} -- [body] = consecutive struck ticks (backstop debounce)

function SweeperHazard.step(now, samples)
	local sweeps, reseeds = {}, {}
	if not Config.HAZARDS_ENABLED then return { sweeps = sweeps, reseeds = reseeds } end
	local elapsed = now - startClock
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	local c = Config.SWEEP_CENTER
	for _, s in ipairs(samples) do
		local dx, dz = s.position.X - c.X, s.position.Z - c.Z
		local radius = math.sqrt(dx * dx + dz * dz)
		local dy = s.position.Y - Config.SWEEP_SURFACE_Y
		local onPlatform = radius >= Config.SWEEP_HUB_RADIUS and radius <= Config.SWEEP_PLATFORM_RADIUS
			and math.abs(dy) <= Config.SWEEP_STAND_BAND
		if onPlatform and not s.graceBlocked then
			local angle = math.atan2(dz, dx)
			local airborne = dy > Config.SWEEP_AIRBORNE_BAND or (s.velocityY or 0) > Config.SWEEP_AIRBORNE_VY
			-- Reseed movement validation for any body in/near an arc (beam shoves are
			-- huge input-less displacements the validator must not score).
			local nearArc = false
			for _, beam in ipairs(activeBeams) do -- beams with radius band + widened half-width attached
				local a = SweeperModel.beamAngle(beam, 0, SweeperModel.rampedSpeed(beam.baseSpeed, elapsed, speedOpts), elapsed)
				if SweeperModel.angularDistance(angle, a) < Config.SWEEP_BEAM_HALF_WIDTH + Config.SWEEP_RESEED_MARGIN then
					nearArc = true
					break
				end
			end
			if nearArc then reseeds[#reseeds + 1] = s.body end
			-- Backstop: only a body that STAYS in the arc (resisting the physics shove)
			-- for SWEEP_RESIST_TICKS consecutive ticks is force-swept.
			if SweeperModel.isStruck({ radius = radius, angle = angle, airborne = airborne },
				activeBeams, elapsed, speedOpts) then
				strikeTicks[s.body] = (strikeTicks[s.body] or 0) + 1
				if strikeTicks[s.body] >= Config.SWEEP_RESIST_TICKS then
					strikeTicks[s.body] = nil
					local tx, tz = SweeperModel.outwardTarget(dx, dz, 0, 0,
						Config.SWEEP_PLATFORM_RADIUS + Config.SWEEP_OFF_MARGIN)
					sweeps[#sweeps + 1] = { player = s.player, body = s.body,
						target = CFrame.new(c.X + tx, s.position.Y, c.Z + tz) }
				end
			else
				strikeTicks[s.body] = nil
			end
		else
			strikeTicks[s.body] = nil
		end
	end
	return { sweeps = sweeps, reseeds = reseeds }
end
```

`activeBeams` = the Config beams with `innerRadius = SWEEP_HUB_RADIUS`, `outerRadius =
SWEEP_PLATFORM_RADIUS`, `angularHalfWidth = SWEEP_BEAM_HALF_WIDTH` attached at build (v1
`tierBeams` pattern). Note `outwardTarget` operates in center-relative coordinates (pass `0,0`
as center, add `c` back to the result — as shown).

- [ ] **Step 3: Ring spawns.**

```lua
function SweeperHazard.spawnCFrame(index)
	local c = Config.SWEEP_CENTER
	local pts = WorldLayout.ring(c.X, c.Z, Config.SWEEP_SPAWN_RADIUS, Config.LOBBY_CAPACITY)
	local pt = pts[math.min(index, #pts)]
	local pos = Vector3.new(pt.x, Config.SWEEP_SURFACE_Y + 5, pt.z)
	return CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z)) -- face the turbine
end
```

Also update `HexHazard.step` to return `{ sweeps = {}, reseeds = {} }` (match the v2 effects shape).

- [ ] **Step 4:** Full suite green. **Commit** `feat(sweeper-v2): beam animation, resist backstop, validator reseeds, ring spawns`.

---

## Task 6: RoundManager v2 — rotation, LiveArena, grace groups

**Files:** Modify `src/server/RoundManager.luau`. Read the whole file first; hex behavior must be preserved when `ARENA_OVERRIDE = "hex"`.

- [ ] **Step 1: Round-scoped arena.** Replace the startup-resolved `local arena = ArenaRegistry.forActive()` with:

```lua
local ArenaRotationModel = require(ReplicatedStorage.Shared.ArenaRotationModel)
-- The live arena is chosen PER ROUND (rotation); between rounds `arena` holds the
-- last round's pick (safe: the monitor and swap paths only run during Active).
local arena = ArenaRegistry.all()[1]
local currentArenaId = nil
```

- [ ] **Step 2: beginRound.** At the TOP of `beginRound()` (before the eligible/economy setup):

```lua
	currentArenaId = ArenaRotationModel.next(currentArenaId, ArenaRegistry.ids(), Config.ARENA_OVERRIDE)
	arena = ArenaRegistry.get(currentArenaId)
	workspace:SetAttribute("LiveArena", currentArenaId)
```

Then, in the reset loop, assign slots from the live arena BEFORE `resetBody`. The loop currently
iterates `Players:GetPlayers()`; give participants stable 1-based indices:

```lua
	local slotIndex = 0
	for _, p in ipairs(Players:GetPlayers()) do
		slotIndex += 1
		BodyManager.setArenaSlot(p, arena.spawnCFrame(slotIndex))
		BodyManager.resetBody(p)
		noteServerReposition(BodyManager.getOwnBody(p))
	end
```

- [ ] **Step 3: endRound.** After `arena.stop()`, add `workspace:SetAttribute("LiveArena", "")`.

- [ ] **Step 4: start().** Replace `arena.build()` with:

```lua
	for _, a in ipairs(ArenaRegistry.all()) do
		a.build() -- persistent world: EVERY arena is constructed once at startup
	end
```

- [ ] **Step 5: Grace collision groups.** Add a helper and call it at every `GraceProtected`
attribute write (stampGrace `true`, monitor on-change, eliminate `false`):

```lua
-- Grace bodies must not collide with the solid sweep beams (spec §4): mirror the
-- GraceProtected attribute into the body's collision group, on change only.
local function setGraceCollision(body, protected)
	local group = protected and "GraceBody" or "Default"
	for _, part in ipairs(body:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end
```

Call `setGraceCollision(body, true)` in `stampGrace` next to `SetAttribute("GraceProtected", true)`;
`setGraceCollision(body, graceBlocked)` in the monitor's on-change branch; `setGraceCollision(body, false)`
in `eliminate` next to its attribute write.

- [ ] **Step 6: Apply reseeds.** In the monitor where sweeps are applied, extend:

```lua
	if effects and effects.reseeds then
		for _, b in ipairs(effects.reseeds) do
			-- A body being shoved by a beam moves fast with no input; clear its
			-- validation history so the shove is never scored as a violation.
			noteServerReposition(b)
		end
	end
```

- [ ] **Step 7:** Full suite green. Read-through: with `ARENA_OVERRIDE = "hex"` every round picks
hex, `LiveArena = "hex"`, slots come from `HexHazard.spawnCFrame` (identical math to the old
creation-time default) — hex rounds behave as before. **Commit**
`feat(sweeper-v2): per-round rotation, LiveArena signal, grace collision groups, reseeds`.

---

## Task 7: Client v2 — SweeperController rewrite + dress-all

**Files:** Rewrite `src/client/SweeperController.luau`; modify `src/client/ArenaDressing.luau`, `src/client/init.client.luau`.

- [ ] **Step 1: SweeperController v2.** Full rewrite implementing spec §6/§7. Structure:

- **Static build (once, at start()):** all cosmetic parts in a `SweeperDressing` folder (anchored,
  CanCollide/Query/Touch false, CastShadow false — v1 `newBar` helper pattern):
  - 36 wake strips: thin radial Neon boxes flush with the surface (`Y = SWEEP_SURFACE_Y + 0.05`),
    spanning hole→rim, evenly spaced angles, base transparency 0.9, color `SWEEP_ACCENT`.
  - 32 chase studs on the rim (`WorldLayout.ring` at `SWEEP_PLATFORM_RADIUS + 1`), small Neon
    cubes, base transparency 0.6.
  - 2 rotor rings around the hub (cosmetic Neon toruses approximated by 8 small tangent bars each,
    at two heights on the pillar).
  - Light shaft: translucent Neon cylinder (radius ~2.5) rising from `SWEEP_VOID_Y` up through the
    hole to ~20 above the surface, transparency 0.7.
  - Under-structure: 4 angled strut boxes from below converging toward the hub base + 1 lower ring
    of tangent bars (static, SmoothPlastic, dark).
  - 3 spotlight fixtures: housing box + Neon lens disc, angled at the platform from above the rim
    (static).
  - Rim accent ring: `WORLD_TRIM`-style tangent bars at the rim in `SWEEP_ACCENT`.
  - 2 telegraph arcs: thin flat Neon boxes at floor level (one per beam, colored by class,
    transparency 0.5), repositioned per frame ahead of each beam.
  Respect the budget: count parts in the build function and `assert(total <= 180)`.
- **Shared Heartbeat loop (ONE connection):** each frame, `local live = workspace:GetAttribute("LiveArena")`;
  if `live ~= "sweeper"` then **skip entirely** (zero writes). Otherwise read `RoundStartServerT`
  from `SweeperField`, compute `elapsed = Workspace:GetServerTimeNow() - startT`, then:
  - position each telegraph arc at `beamAngle + direction * SWEEP_TELEGRAPH_LEAD`;
  - wake: for each strip, angular distance BEHIND the low beam (signed by direction) maps to
    transparency `0.15 → 0.9` across `SWEEP_WAKE_FADE * lowSpeed` radians — write only strips
    whose value changed meaningfully (>0.02);
  - chase: advance one lit stud every ~0.08 s (3-stud lit window);
  - rotors: counter-rotate the two ring assemblies by small yaw steps.
- **Dormancy flip:** `workspace:GetAttributeChangedSignal("LiveArena")` → one pass setting every
  Neon element to `SWEEP_STANDBY_TRANSPARENCY` (dormant) or its live base value; park telegraphs.
- **Tumble watcher:** keep the v1 `watchTumble(getOwnBody)` verbatim (dedupe + disconnect version).
- **No beam parts are built here** — the server owns them now.

- [ ] **Step 2: ArenaDressing.** Replace the single-descriptor dress with:

```lua
	for _, desc in ipairs(ArenaDescriptor.all()) do
		buildFloorTrim(folder, ArenaDescriptor.validate(desc))
	end
	buildBanner(folder)
```

- [ ] **Step 3: init.client.** Replace the `Config.ACTIVE_ARENA == "sweeper"` guard with an
unconditional `SweeperController.start(ClientControl.getBody)` (it self-gates on `LiveArena`).
Remove the now-unused Config require if nothing else uses it.

- [ ] **Step 4:** Full suite green; grep `src/` for any leftover `ACTIVE_ARENA`/`forActive` (must
be none). **Commit** `feat(sweeper-v2): Soul Turbine client cosmetics + dress-all + dormancy`.

---

## Task 8: Docs

**Files:** Create `docs/smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md`; modify `CHANGELOG.md`, `docs/world-enrichment-roadmap.md`.

- [ ] **Step 1: Smoke doc** covering (2-client unless noted): annulus walk incl. seam crossing +
gap-ring fall + hub non-walkable (solo); beam shove feel + consistency under latency; high-beam
clearance while grounded vs jumping (tuning knob `SWEEP_BEAM_HIGH_Y`); grace pass-through (swap
then stand in the arc); resist backstop (anchor-cheat simulation via command bar); rotation
(hex round → sweeper round → hex) + `LiveArena` flips + spawn rings; dormancy (idle arena dim +
frozen from the lobby, zero motion); wake/telegraph readability after a swap cut; validator
non-interference during shoves. Results section placeholder.
- [ ] **Step 2: CHANGELOG** entry (match style): v2 Soul Turbine rework summary.
- [ ] **Step 3: Roadmap** — update the Soul Sweeper line: v2 turbine redesign + persistent
two-arena world shipped (procedural); link v2 spec/plan.
- [ ] **Step 4: Commit** `docs(sweeper-v2): smoke test + CHANGELOG + roadmap`.

---

## Task 9 (CONTROLLER-EXECUTED, MCP): Studio verification

Run via Studio MCP (Play Solo + `execute_luau`), per spec §9: geometry probes (annulus seam walk
via dropped-part slide or ray sweep at multiple angles, gap-ring drop-through, hub block); yaw
convention check (place a stationary probe at a known polar angle, animate to that angle, assert
overlap — beam part vs strike math MUST agree); collision groups (grace body vs beam pass-through);
backstop trigger (anchored body in arc → swept after 3 ticks); rotation + `LiveArena` + spawn
rings on both arenas across two forced rounds; dormancy (no Heartbeat writes when idle — assert
beam CFrame frozen); hex regression (full hex round with `ARENA_OVERRIDE="hex"`). Record results
in the smoke doc; tune `SWEEP_BEAM_HIGH_Y` / half-width if probes contradict.

## Task 10 (CONTROLLER-EXECUTED, MCP): asset sourcing

Source via MCP: disc material, beam energy material, turbine hub hero mesh → set
`SWEEP_DISC_MATERIAL` / `SWEEP_BEAM_MATERIAL` / `SWEEP_HUB_MESH`; verify sourced + fallback both
render; commit.

---

## Self-review notes (author)

- Spec coverage: §3→T2/T4, §4→T4/T5/T6, §5→T1/T2/T3/T6, §6/§7→T7, §8→T5/T6, §9→T9, sourcing→T10.
- Type consistency: `effects = {sweeps, reseeds}` produced T5, consumed T6; `spawnCFrame` declared
  T3, implemented T3 (hex)/T5 (sweeper), consumed T6; `LiveArena` written T6, read T5 (implicitly
  via start/stop) and T7; `beamCFrame` shared by park (T4) + animation (T5).
- Yaw-sign risk is called out in T4 and verified in T9 — the one place geometry and math can
  disagree; the fix location is pinned (glue, never the pure model).
