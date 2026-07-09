# Soul Sweeper v2.1 — Jump Club Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bigger true-circle Sweeper arena, exactly two motorized solid striped beams with real contact physics, telegraph arcs deleted, measured beam pose as the single angle source of truth.

**Architecture:** Beams become unanchored welded assemblies driven by `HingeConstraint` motors on an anchored hub axle (server-owned; the physics engine rotates them — v2's Heartbeat CFrame stepping is deleted). The strike backstop and client cosmetics read each beam's **measured** angle from its replicated root CFrame via a new pure `SweeperModel.isStruckAt` / the root offset `atan2`. The client renders one seamless EditableMesh annulus (the `LobbyStage.buildEditableCyl` pattern adapted to a ring) over densified invisible-locally collision segments.

**Spec:** `docs/superpowers/specs/2026-07-09-soul-sweeper-v2_1-jumpclub-refinement-design.md` (read FIRST — this plan implements its numbered decisions).

**Conventions:** as v2 plan (`2026-07-08-soul-sweeper-v2-turbine.md` header): lune suite must stay green after every task (`export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done` — 24 suites). Commit per task, no Co-Authored-By.

---

## File Structure

- Modify `src/shared/Config.luau` — scale keys, beam-dimension keys, delete telegraph key.
- Modify `src/shared/SweeperModel.luau` + `tests/sweeper_model.spec.luau` — `isStruckAt` replaces `isStruck`.
- Modify `src/server/SweeperHazard.luau` — densified segments, motorized beam assemblies, measured-angle step, park/brake lifecycle.
- Modify `src/client/SweeperController.luau` — delete telegraphs, smooth annulus, measured-angle wake, rotor height.
- Docs: CHANGELOG, roadmap, smoke-doc addendum.
- **Task 6 (CONTROLLER-EXECUTED, MCP):** live verification per spec §5.

## Task 1: Config v2.1

**Files:** `src/shared/Config.luau`

- [ ] **Step 1:** Apply these value changes (keep each key's comment style; update comments where semantics changed):
  - `SWEEP_CENTER = Vector3.new(140, 0, 0)`; `SWEEP_PLATFORM_RADIUS = 52`; `SWEEP_HOLE_RADIUS = 12`; `SWEEP_HUB_RADIUS = 6`; `SWEEP_PLATFORM_SEGMENTS = 48`; `SWEEP_SPAWN_RADIUS = 32`; `LOBBY_FACE_TARGET = Vector3.new(70, 0, 0)`.
  - DELETE `SWEEP_TELEGRAPH_LEAD`, `SWEEP_BEAM_SIZE`, `SWEEP_BEAM_LOW_Y`, `SWEEP_BEAM_HIGH_Y`.
  - ADD (with comments explaining each; place where the deleted keys were):

```lua
-- Solid machine-bar beams (Jump Club idiom): unanchored welded assemblies driven by
-- HingeConstraint motors on the hub axle (spec 2026-07-09 §2-4/§2-6). BOTTOM faces are
-- the gameplay knobs: the low bar must be jumpable, the high bar must clear a grounded
-- body. Stripes are alternating welded segments (no textures needed).
Config.SWEEP_BEAM_LOW_BOTTOM = 0.6    -- low bar underside (jumpable; top = bottom + thickness)
Config.SWEEP_BEAM_LOW_THICKNESS = 1
Config.SWEEP_BEAM_HIGH_BOTTOM = 5.5   -- high bar underside: THE grounded-clearance knob
Config.SWEEP_BEAM_HIGH_THICKNESS = 3
Config.SWEEP_BEAM_STRIPES = 6         -- alternating colored segments per bar
Config.SWEEP_BEAM_STRIPE_COLOR = Color3.fromRGB(245, 238, 220) -- warm cream (both bars)
Config.SWEEP_BEAM_MOTOR_TORQUE = 1e9  -- players can never stall a bar
Config.SWEEP_BEAM_DENSITY = 8         -- heavy bars: convincing flings, stable under contact
Config.SWEEP_HUB_TOP = 10             -- hub pillar top (studs above surface; axle must
                                      -- reach past the thick bar's top at 5.5+3)
```
  - `SWEEP_BEAM_LOW_COLOR` / `SWEEP_BEAM_HIGH_COLOR` stay (stripe partners of the cream).
- [ ] **Step 2:** Suite green (24). **Commit** `feat(sweeper-v2.1): Config — scale up, machine-bar keys, telegraph key removed`.

## Task 2: SweeperModel — `isStruckAt` (TDD)

**Files:** `src/shared/SweeperModel.luau`, `tests/sweeper_model.spec.luau`

- [ ] **Step 1 (failing tests):** In the spec file, REPLACE the `isStruck` test block with:

```lua
-- isStruckAt: measured-angle strike test (beams carry their CURRENT physical angle).
do
	local beams = {
		{ angle = 0, class = "low", innerRadius = 6, outerRadius = 52, angularHalfWidth = 0.15 },
		{ angle = math.pi, class = "high", innerRadius = 6, outerRadius = 52, angularHalfWidth = 0.15 },
	}
	expect(M.isStruckAt({ radius = 20, angle = 0, airborne = false }, beams),
		"grounded under the low bar -> struck")
	expect(not M.isStruckAt({ radius = 20, angle = 0, airborne = true }, beams),
		"airborne clears the low bar")
	expect(not M.isStruckAt({ radius = 20, angle = math.pi, airborne = false }, beams),
		"grounded clears the high bar")
	expect(M.isStruckAt({ radius = 20, angle = math.pi, airborne = true }, beams),
		"airborne into the high bar -> struck")
	expect(not M.isStruckAt({ radius = 20, angle = 1.5, airborne = false }, beams),
		"between bars -> safe")
	expect(not M.isStruckAt({ radius = 3, angle = 0, airborne = false }, beams),
		"inside the hub radius -> safe")
	print("sweeper: isStruckAt OK")
end
```

- [ ] **Step 2:** Run → FAIL (`isStruckAt` nil).
- [ ] **Step 3:** In `SweeperModel.luau`, REPLACE `isStruck` (delete it — its only consumer was the v2 glue being rewritten in Task 3) with:

```lua
-- Is a body struck by ANY beam, given each beam's MEASURED current angle?
-- body = { radius, angle, airborne }; beams = array of
-- { angle, class, innerRadius, outerRadius, angularHalfWidth }. The glue derives
-- `angle` from the physical bar's replicated pose (atan2 of its center offset from
-- the hub) -- physics, authority, and cosmetics observe one object by construction.
function SweeperModel.isStruckAt(body, beams)
	for _, beam in ipairs(beams) do
		if not SweeperModel.clears(beam.class, body.airborne)
			and SweeperModel.overlaps(body.radius, body.angle, beam.angle, beam) then
			return true
		end
	end
	return false
end
```

- [ ] **Step 4:** Run → PASS; full suite green (`rampedSpeed`/`beamAngle` tests untouched — both still drive the motor target). **Commit** `feat(sweeper-v2.1): pure isStruckAt on measured angles (isStruck removed)`.

## Task 3: SweeperHazard — motorized assemblies + measured-angle step

**Files:** `src/server/SweeperHazard.luau` (read the whole file first)

- [ ] **Step 1: Geometry updates.** `buildHub`: pillar now spans `surface-6 .. surface+Config.SWEEP_HUB_TOP`. `buildAnnulus`: unchanged code (48 segments come from Config).
- [ ] **Step 2: Rewrite `buildBeams` as assemblies.** For each of the two `Config.SWEEP_BEAMS`:

```lua
-- One solid striped machine bar: a root spine + alternating stripe shells + end cap
-- + hub collar, welded rigid, hinged to the anchored hub axle by a motor.
local function buildBeamAssembly(folder, beam)
	local span = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS
	local thick = beam.class == "low" and Config.SWEEP_BEAM_LOW_THICKNESS or Config.SWEEP_BEAM_HIGH_THICKNESS
	local bottom = beam.class == "low" and Config.SWEEP_BEAM_LOW_BOTTOM or Config.SWEEP_BEAM_HIGH_BOTTOM
	local centerY = Config.SWEEP_SURFACE_Y + bottom + thick / 2
	local color = beamColor(beam.class)
	local props = PhysicalProperties.new(Config.SWEEP_BEAM_DENSITY, 0.3, 0.5)
	local c = Config.SWEEP_CENTER

	-- Root spine: the full-span collidable bar (the physics contact surface).
	local root = Instance.new("Part")
	root.Name = "SweepBeam_" .. beam.class
	root.Size = Vector3.new(span, thick, thick)
	root.CFrame = CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, -beam.baseAngle, 0)
		* CFrame.new(Config.SWEEP_HUB_RADIUS + span / 2, centerY, 0)
	root.Color = color
	root.Material = Enum.Material.SmoothPlastic
	root.CanCollide = true
	root.CollisionGroup = "SweepBeam"
	root.CustomPhysicalProperties = props
	root.Parent = folder

	-- Stripes: alternating cream shells welded onto the spine (slightly proud so the
	-- stripe reads; non-colliding so the contact surface stays one clean box).
	local stripeLen = span / Config.SWEEP_BEAM_STRIPES
	for i = 0, Config.SWEEP_BEAM_STRIPES - 1 do
		if i % 2 == 1 then
			local s = Instance.new("Part")
			s.Name = root.Name .. "_Stripe" .. i
			s.Size = Vector3.new(stripeLen, thick + 0.1, thick + 0.1)
			s.CFrame = root.CFrame * CFrame.new(-span / 2 + stripeLen * (i + 0.5), 0, 0)
			s.Color = Config.SWEEP_BEAM_STRIPE_COLOR
			s.Material = Enum.Material.SmoothPlastic
			s.CanCollide = false
			s.CollisionGroup = "SweepBeam"
			s.Massless = true
			s.Parent = folder
			local w = Instance.new("WeldConstraint"); w.Part0 = root; w.Part1 = s; w.Parent = s
		end
	end
	-- End cap (rounded outer tip) + hub collar (mounts the bar on the axle visually).
	local cap = Instance.new("Part")
	cap.Name = root.Name .. "_Cap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(thick + 0.4, thick + 0.4, thick + 0.4)
	cap.CFrame = root.CFrame * CFrame.new(span / 2, 0, 0)
	cap.Color = color
	cap.Material = Enum.Material.SmoothPlastic
	cap.CanCollide = false
	cap.CollisionGroup = "SweepBeam"
	cap.Massless = true
	cap.Parent = folder
	local wc = Instance.new("WeldConstraint"); wc.Part0 = root; wc.Part1 = cap; wc.Parent = cap
	local collar = Instance.new("Part")
	collar.Name = root.Name .. "_Collar"
	collar.Shape = Enum.PartType.Cylinder
	collar.Size = Vector3.new(thick + 1, (Config.SWEEP_HUB_RADIUS + 1) * 2, (Config.SWEEP_HUB_RADIUS + 1) * 2)
	collar.CFrame = CFrame.new(c.X, centerY, c.Z) * CFrame.Angles(0, 0, math.rad(90))
	collar.Color = Config.SWEEP_BEAM_STRIPE_COLOR
	collar.Material = Enum.Material.SmoothPlastic
	collar.CanCollide = false
	collar.CollisionGroup = "SweepBeam"
	collar.Massless = true
	collar.Parent = folder
	local wk = Instance.new("WeldConstraint"); wk.Part0 = root; wk.Part1 = collar; wk.Parent = collar

	-- Motor: anchored hub -> bar assembly, vertical axis at the hub center.
	local a0 = Instance.new("Attachment")
	a0.CFrame = CFrame.new(0, centerY - hubPart.Position.Y + hubCFrameYOffsetIfAny, 0) -- see note
	a0.Axis = Vector3.yAxis -- rotation axis straight up
	a0.Parent = hubPart
	local a1 = Instance.new("Attachment")
	-- the bar's hinge point: at the hub center, i.e. offset -(HUB_RADIUS + span/2) along the bar
	a1.Position = Vector3.new(-(Config.SWEEP_HUB_RADIUS + span / 2), 0, 0)
	a1.Axis = Vector3.yAxis
	a1.Parent = root
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = root.Name .. "_Motor"
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = Config.SWEEP_BEAM_MOTOR_TORQUE
	hinge.MotorMaxAcceleration = math.huge
	hinge.AngularVelocity = 0
	hinge.Parent = root

	root.Anchored = false
	root:SetNetworkOwner(nil) -- server simulates; replication interpolates for clients

	return { beam = beam, part = root, hinge = hinge, y = centerY }
end
```

> **Attachment note (implementer):** `a0`'s CFrame must place the axis point at the hub
> center at `centerY`, expressed in the HUB part's local space; `Axis` must be world-up for
> both attachments (hub is a Z-rolled cylinder — its local axes are rotated; compute the
> local axis accordingly, e.g. via `hubPart.CFrame:VectorToObjectSpace(Vector3.yAxis)` and
> `hubPart.CFrame:PointToObjectSpace(hubWorldAxisPoint)`). Verify with the Task 6 spin probe.
> Weld the stripes AFTER positioning. All assembly parts are group `SweepBeam` so grace
> pass-through covers the whole bar.

- [ ] **Step 3: Lifecycle.** DELETE `startAnimation`/`stopAnimation` + `animConn` (the Heartbeat CFrame stepping). `start(now)`: `startClock = now`; set `RoundStartServerT` (unchanged); set each hinge's `AngularVelocity = beam.direction * SweeperModel.rampedSpeed(beam.baseSpeed, 0, speedOpts)`. `stop()`: each hinge `AngularVelocity = 0`, then re-park each assembly: `root:PivotTo(<baseAngle pose>)` (welded parts follow).
- [ ] **Step 4: `step` on measured angles.** Add a helper + use it for BOTH the reseed scan and the strike test; also refresh the motor targets (the ramp):

```lua
-- The bar's CURRENT physical angle: atan2 of its center offset from the hub.
local function measuredAngle(rec)
	local c = Config.SWEEP_CENTER
	local off = rec.part.Position - Vector3.new(c.X, rec.part.Position.Y, c.Z)
	return math.atan2(off.Z, off.X)
end
```

In `step`: compute `elapsed`, then per beam rec: `rec.hinge.AngularVelocity = rec.beam.direction * SweeperModel.rampedSpeed(rec.beam.baseSpeed, elapsed, speedOpts)` and build `beamsNow[i] = { angle = measuredAngle(rec), class = rec.beam.class, innerRadius = Config.SWEEP_HUB_RADIUS, outerRadius = Config.SWEEP_PLATFORM_RADIUS, angularHalfWidth = Config.SWEEP_BEAM_HALF_WIDTH }`. Replace the old per-sample `angleOf`/`isStruck` calls: reseeds use `SweeperModel.angularDistance(bodyAngle, b.angle) < HALF_WIDTH + RESEED_MARGIN` over `beamsNow`; strikes use `SweeperModel.isStruckAt(bodyPolar, beamsNow)`. `activeBeams` (elapsed-based) is deleted.
- [ ] **Step 5:** Suite green. **Commit** `feat(sweeper-v2.1): motorized striped beam assemblies + measured-angle strikes`.

## Task 4: Client — telegraphs out, smooth annulus in, measured wake

**Files:** `src/client/SweeperController.luau` (read whole file first)

- [ ] **Step 1:** DELETE the telegraph build block and its per-frame positioning (and any dormancy-flip references to the telegraph parts).
- [ ] **Step 2: Smooth annulus (lobby technique).** Adapt `LobbyStage.buildEditableCyl` (read it) to a ring:

```lua
-- A seamless TRUE-CIRCLE annulus (EditableMesh): inner/outer vertex rings top+bottom,
-- top & bottom quad strips + outer and inner skirts. Falls back silently (pcall) to
-- the server's segmented floor look if EditableMesh is unavailable on this client.
local function buildEditableAnnulus(innerR, outerR, thickness, sides)
	local em = AssetService:CreateEditableMesh()
	local ti, to, bi, bo = {}, {}, {}, {}
	for i = 0, sides - 1 do
		local a = (2 * math.pi * i) / sides
		local cx, sz = math.cos(a), math.sin(a)
		ti[i] = em:AddVertex(Vector3.new(innerR * cx, thickness / 2, innerR * sz))
		to[i] = em:AddVertex(Vector3.new(outerR * cx, thickness / 2, outerR * sz))
		bi[i] = em:AddVertex(Vector3.new(innerR * cx, -thickness / 2, innerR * sz))
		bo[i] = em:AddVertex(Vector3.new(outerR * cx, -thickness / 2, outerR * sz))
	end
	for i = 0, sides - 1 do
		local j = (i + 1) % sides
		em:AddTriangle(ti[i], to[j], to[i]); em:AddTriangle(ti[i], ti[j], to[j])   -- top
		em:AddTriangle(bi[i], bo[i], bo[j]); em:AddTriangle(bi[i], bo[j], bi[j])   -- bottom
		em:AddTriangle(to[i], bo[j], bo[i]); em:AddTriangle(to[i], to[j], bo[j])   -- outer skirt
		em:AddTriangle(ti[i], bi[i], bi[j]); em:AddTriangle(ti[i], bi[j], ti[j])   -- inner skirt
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em),
		{ CollisionFidelity = Enum.CollisionFidelity.Box })
	mp.Size = Vector3.new(outerR * 2, thickness, outerR * 2)
	return mp
end
```

Build it at `SWEEP_HOLE_RADIUS`/`SWEEP_PLATFORM_RADIUS`/`SWEEP_PLATFORM_THICKNESS`, 96 sides, positioned so its top = `SWEEP_SURFACE_Y + 0.02`; non-colliding cosmetic (v1 `newPart` property set); apply `SWEEP_PLATFORM_COLOR` + (when `Config.SWEEP_DISC_MATERIAL ~= ""`) the base material + `MaterialVariant`. On SUCCESS: for every `SweepFloor_*` in `workspace.SweeperField`, set `LocalTransparencyModifier = 1` (client-only hide; collision untouched). On pcall FAILURE: skip both (segments stay visible). `counted(...)` the MeshPart.
- [ ] **Step 3: Measured wake.** The wake section currently computes the low beam's angle from `rampedSpeed`/`beamAngle`/elapsed. Replace: find the low bar once per frame (`workspace.SweeperField:FindFirstChild("SweepBeam_low")`, cache the reference, tolerate nil) and compute `lowAngle = atan2(part.Position.Z - c.Z, part.Position.X - c.X)`; wake window uses the CURRENT motor speed approximation — reuse `rampedSpeed` with elapsed from `RoundStartServerT` **only for the fade-window width** (cosmetic), or simplify to a fixed `SWEEP_WAKE_FADE`-radians window; implementer's choice, comment it. Rotor ring 2 moves to `surfaceY + 9.5` (above the thick bar). Everything else (chase, rotors, dormancy flip, tumble) unchanged.
- [ ] **Step 4:** Suite green; grep for `SWEEP_TELEGRAPH_LEAD`/`Telegraph` (zero code refs). **Commit** `feat(sweeper-v2.1): smooth annulus, telegraphs removed, wake reads measured pose`.

## Task 5: Docs

- [ ] CHANGELOG entry (v2.1 summary), roadmap line update, smoke-doc addendum: new cases — fling feel (dropped body launched with velocity), stall attempt (bar wins + backstop), true-circle visual, high-bar clearance re-check at 3-thick. **Commit** `docs(sweeper-v2.1): CHANGELOG + roadmap + smoke additions`.

## Task 6 (CONTROLLER-EXECUTED, MCP): live verification

Per spec §5: motor spin-up (set LiveArena+start via a forced round or attribute sim — note: motors are set in `start()`, so use `ARENA_OVERRIDE="sweeper"` + a 2nd fake... if Play-Solo can't start a round, drive the hinge directly to verify constraint stability), measured-angle probe (bar pose vs `atan2` agreement while spinning), fling test (unanchored dummy part in the bar's path gets real velocity), stall test, EditableMesh annulus + LocalTransparencyModifier, clearances, part counts, hex regression, dormancy re-park.

## Self-review notes (author)

- Spec §2 decisions → T1 (1), T4 (2), T3+T4 (3), T3 (4), T2+T3+T4 (5), T3 (6), T4 (7). §3 deletions → T1/T2/T3/T4. §4 behaviors → T3. All covered.
- Consistency: `isStruckAt(body, beams)` defined T2, consumed T3; `beamsNow` shape matches `overlaps` fields; `SWEEP_HUB_TOP` defined T1, consumed T3; rotor 9.5 (T4) clears high bar top 8.5 (T1/T3); collar radius HUB+1=7 < hole 12 (never blocks the gap visual).
- The a0/a1 attachment axis note is the one fiddly spot — flagged for the implementer + Task 6 probe.
