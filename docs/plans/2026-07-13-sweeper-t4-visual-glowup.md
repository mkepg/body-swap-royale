# Soul Sweeper T4 Visual Glow-Up Implementation Plan

**Goal:** Rebuild the Soul Sweeper arena's dressing to match the T4 thumbnail reference (`docs/marketing/thumbnails/candidates/gemini-t4-master-1.png`) — layered glowing bars, 12-wedge neon-seam disc, continuous rim ring, moat line, glass-lantern hub — with zero gameplay change.

**Architecture:** Spec: `docs/specs/2026-07-13-sweeper-t4-visual-glowup-design.md`. Two-layer pattern preserved: welded bar dressing lives server-side in `SweeperHazard` (it must ride the physics-driven spines); all static/animated cosmetics live client-side in `SweeperController`; the arena-agnostic `ArenaDescriptor`/`ArenaDressing` contract gains a `trim` opt-out. Physics, strike math, kill bands, dormancy mechanism: untouched.

**Tech Stack:** Roblox Luau (Rojo project), lune 0.10.4 for pure-logic suites (`export PATH="$HOME/.rokit/bin:$PATH"`), PowerShell-free.

---

## CRITICAL: Config.luau dev-flip commit hazard

`src/shared/Config.luau` carries two uncommitted dev flips that must NEVER be committed:
`Config.ARENA_OVERRIDE = "sweeper"` (committed value `""`) and
`Config.SOLO_TEST_MODE = true` (committed value `false`).

**Every commit that touches Config.luau MUST use this exact procedure** (interactive `git add -p` is unavailable):

```bash
cd "<repo-root>"
# 1. Temporarily restore committed values (working tree only)
sed -i 's/^Config.ARENA_OVERRIDE = "sweeper"$/Config.ARENA_OVERRIDE = ""/' src/shared/Config.luau
sed -i 's/^Config.SOLO_TEST_MODE = true$/Config.SOLO_TEST_MODE = false/' src/shared/Config.luau
# 2. Stage (plus the task's other files)
git add src/shared/Config.luau <OTHER_FILES>
# 3. Verify no dev-flip is staged — MUST print "clean"
git diff --cached src/shared/Config.luau | grep -E 'ARENA_OVERRIDE|SOLO_TEST_MODE' && echo "HAZARD: ABORT, reset and retry" || echo "clean"
# 4. Commit
git commit -m "<message>"
# 5. Re-apply the dev flips (leave the working tree as found)
sed -i 's/^Config.ARENA_OVERRIDE = ""$/Config.ARENA_OVERRIDE = "sweeper"/' src/shared/Config.luau
sed -i 's/^Config.SOLO_TEST_MODE = false$/Config.SOLO_TEST_MODE = true/' src/shared/Config.luau
# 6. Confirm flips are back (working tree dirty on exactly those two lines)
git diff src/shared/Config.luau | grep -cE '^\+Config\.(ARENA_OVERRIDE = "sweeper"|SOLO_TEST_MODE = true)'   # expect: 2
```

## Test command (used by every task)

```bash
cd "<repo-root>"
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do lune run "$f" || { echo "FAILED: $f"; break; }; done
```
Expected: every suite prints its `... OK` lines; no `ASSERTION FAILED`; loop completes.

---

### Task 1: ArenaDressing trim opt-out (arena-agnostic)

**Files:**
- Modify: `src/shared/ArenaDescriptor.luau` (sweeper descriptor + validate)
- Modify: `src/client/ArenaDressing.luau` (skip trim when opted out)

- [ ] **Step 1: Descriptor — sweeper opts out of trim**

In `src/shared/ArenaDescriptor.luau`, replace the body of `ArenaDescriptor.sweeper()`:

```lua
-- Soul Sweeper v2 descriptor: one annulus level at the platform surface.
-- trim = false: the T4 glow-up's built-in rim ring (SweeperController) replaces
-- the generic ArenaDressing edge trim, so this arena opts out of Layer-2 trim.
function ArenaDescriptor.sweeper()
	local extent = Config.SWEEP_PLATFORM_RADIUS * 2
	return {
		center = Vector3.new(Config.SWEEP_CENTER.X, Config.SWEEP_SURFACE_Y, Config.SWEEP_CENTER.Z),
		footprint = Vector2.new(extent, extent),
		depth = Config.SWEEP_SURFACE_Y - Config.SWEEP_VOID_Y,
		accent = Config.SWEEP_ACCENT,
		levels = { { y = Config.SWEEP_SURFACE_Y, color = Config.SWEEP_ACCENT } },
		trim = false,
	}
end
```

- [ ] **Step 2: Descriptor — validate() understands the opt-out**

Replace the `trimDim` assert in `ArenaDescriptor.validate` with:

```lua
	-- trim defaults to true; trimDim is only meaningful (and required) when trimmed.
	assert(desc.trim == nil or type(desc.trim) == "boolean",
		"ArenaDescriptor.trim must be a boolean when present")
	if desc.trim ~= false then
		assert(type(desc.trimDim) == "number", "ArenaDescriptor.trimDim must be a number")
	end
```

Also update the shape comment at the top of the file: add
`  trim      -- optional (default true): false = arena builds its own border, skip edge trim` under the existing field list.

- [ ] **Step 3: ArenaDressing — skip opted-out descriptors**

In `src/client/ArenaDressing.luau`, at the top of `buildFloorTrim`, add:

```lua
	if desc.trim == false then return end -- arena carries its own built-in border
```

- [ ] **Step 4: Run the suites**

Run the test command (header). Expected: all pass (no suite covers the descriptor — this guards against accidental breakage elsewhere).

- [ ] **Step 5: Commit**

```bash
git add src/shared/ArenaDescriptor.luau src/client/ArenaDressing.luau
git commit -m "feat(sweeper): descriptor trim opt-out; sweeper drops generic edge trim"
```
(Config untouched in this task — no hazard procedure needed.)

---

### Task 2: Server — layered bars (glow core inset in dark shell)

**Files:**
- Modify: `src/shared/Config.luau` (3 new keys — HAZARD procedure on commit)
- Modify: `src/server/SweeperHazard.luau` (`buildBeamAssembly` dressing only)

- [ ] **Step 1: Config — add rail colors**

In `src/shared/Config.luau`, directly under `Config.SWEEP_BEAM_HIGH_COLOR` (≈line 181), add:

```lua
-- T4 glow-up (2026-07-13 spec §4.1): layered bars -- the emissive class-color
-- core is framed by dark structural rails top and bottom (glow inset in shell).
Config.SWEEP_RAIL_COLOR = Color3.fromRGB(24, 30, 56)                 -- dark shell/rails/grooves/hub family
Config.SWEEP_BEAM_LOW_UNDERRAIL_COLOR = Color3.fromRGB(122, 74, 24)  -- bronze under the amber core
Config.SWEEP_BEAM_HIGH_UNDERRAIL_COLOR = Color3.fromRGB(84, 18, 38)  -- deep maroon under the crimson core
```

- [ ] **Step 2: SweeperHazard — spine becomes the emissive core**

In `buildBeamAssembly`, change the root's appearance (size/pose/physics lines stay EXACTLY as they are):

```lua
	root.Name = "SweepBeam_" .. beam.class
	root.Size = Vector3.new(span, thick, thick)
	root.CFrame = beamPose(beam.baseAngle, centerY)
	-- T4 glow-up: the spine IS the emissive core (spec §4.1). Because the kill
	-- band derives from this same part's thickness, hitbox<->visual alignment is
	-- exact by construction (v2.4 invariant strengthened).
	root.Color = color
	root.Material = Enum.Material.Neon
	root.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
	root.CanCollide = false
	root.Parent = folder
```

- [ ] **Step 3: SweeperHazard — replace the class-specific dressing with rails + cap**

Delete the entire `if beam.class == "low" then ... else ... end` dressing block
(housing/blade/emitter and underglow/lamps) and replace it with:

```lua
	-- Layered shell (spec §4.1): dark structural rails frame the glowing core
	-- along its top and bottom edges; a rounded Neon cap closes the rim tip.
	-- Envelope invariant: rails extend 0.25 past the spine's faces (< the 0.3
	-- precedent), so perceived clearance/jump heights are unchanged in practice.
	local RAIL_THICK = 0.25
	local underRail = beam.class == "low" and Config.SWEEP_BEAM_LOW_UNDERRAIL_COLOR
		or Config.SWEEP_BEAM_HIGH_UNDERRAIL_COLOR
	local railLen = span - thick -- stop short of the rounded tip cap
	for _, side in ipairs({
		{ suffix = "_TopRail", yOff = thick / 2 + RAIL_THICK / 2, railColor = Config.SWEEP_RAIL_COLOR },
		{ suffix = "_UnderRail", yOff = -(thick / 2 + RAIL_THICK / 2), railColor = underRail },
	}) do
		local rail = Instance.new("Part")
		rail.Name = root.Name .. side.suffix
		rail.Size = Vector3.new(railLen, RAIL_THICK, thick + 0.3)
		rail.CFrame = root.CFrame * CFrame.new(-thick / 2, side.yOff, 0)
		rail.Color = side.railColor
		rail.Material = Enum.Material.SmoothPlastic
		weldOn(rail)
	end

	local cap = Instance.new("Part")
	cap.Name = root.Name .. "_Cap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(thick, thick, thick)
	cap.CFrame = root.CFrame * CFrame.new(span / 2, 0, 0)
	cap.Color = color
	cap.Material = Enum.Material.Neon
	cap.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
	weldOn(cap)
```

Also update the "Dressing only" comment above `weldOn` (it references the old
amber-blade/crimson-underglow tells): the tell is now the whole class-colored
core + cap; rails are neutral shell.

- [ ] **Step 4: Run the suites**

Run the test command. Expected: all pass (strike math reads size/pose, which are unchanged; `sweeper_model.spec` is pure).

- [ ] **Step 5: Commit (HAZARD procedure)**

Use the Config hazard procedure with
`<OTHER_FILES> = src/server/SweeperHazard.luau` and message
`feat(sweeper): layered bars -- Neon core spine framed by dark rails, rounded tip cap`.

---

### Task 3: Client — delete legacy cosmetics; seams (wake-fused), rim ring, moat line

**Files:**
- Modify: `src/shared/Config.luau` (4 new keys — HAZARD procedure on commit)
- Modify: `src/client/SweeperController.luau`

- [ ] **Step 1: Config — seam/ring keys**

Under the `SWEEP_WAKE_CHANNELS`/`SWEEP_CHASE_STUDS` block (≈line 184), add:

```lua
-- T4 glow-up (2026-07-13 spec §4.2): the disc reads as 12 pie wedges separated
-- by permanent amber seams; the old wake ignition is FUSED into them (seams
-- idle dim, flare behind the low bar). Rim ring + moat line replace chase
-- studs / rim accents / the generic edge trim.
Config.SWEEP_SEAM_COUNT = 12
```

In the `GLOW_DIM_*` block (≈line 373), add (keep alphabetical-ish grouping with the other sweep knobs):

```lua
Config.GLOW_DIM_SWEEP_SEAM = 0.0      -- wedge seam strips incl. flare (SweeperController)
Config.GLOW_DIM_SWEEP_RIM_RING = 0.0  -- continuous rim ring band (SweeperController)
Config.GLOW_DIM_SWEEP_MOAT = 0.0      -- fall-gap inner-rim readability line (SweeperController)
```

(Old keys are deleted in Task 5, after their last consumer dies in this task.)

- [ ] **Step 2: SweeperController — constants block rewrite**

Replace the transparency-constants block (the `WAKE_/CHASE_/ROTOR_/SHAFT_/LENS_/RIM_ACCENT_` constants, ≈lines 56–73) with:

```lua
local SEAM_IDLE_TRANSPARENCY = GlowDim.apply(0.35, Config.GLOW_DIM_SWEEP_SEAM)
local SEAM_FLARE_TRANSPARENCY = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_SEAM)
local RIM_RING_TRANSPARENCY = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_RIM_RING)
local MOAT_TRANSPARENCY = GlowDim.apply(0.5, Config.GLOW_DIM_SWEEP_MOAT)
local DORMANT_TRANSPARENCY = GlowDim.apply(Config.SWEEP_STANDBY_TRANSPARENCY, Config.GLOW_DIM_SWEEP_DORMANT)

-- Seam flare fade-window width in RADIANS (fixed, not speed-scaled) -- the lit
-- trail behind the low bar's measured pose; same rationale as the old wake window.
local SEAM_FLARE_WINDOW = 0.9
```

Update the block's leading comment: dressing is atmosphere; the bars' kill
tells are now the whole server-built cores; idle/lit values stay below
`SWEEP_STANDBY_TRANSPARENCY` (0.85) so dormancy still dims.

- [ ] **Step 3: SweeperController — build-pass rewrite**

Inside `SweeperController.start()`:

a. Replace section 1 (wake channels) with the seam system:

```lua
	----------------------------------------------------------------------------
	-- 1. Wedge seams: SWEEP_SEAM_COUNT radial Neon strips (hole -> rim) in dark
	--    grooves. Permanently visible (idle dim); the Heartbeat loop flares them
	--    behind the low bar -- the old wake beat fused into reference geometry.
	----------------------------------------------------------------------------
	local seamStrips = {}
	do
		local n = Config.SWEEP_SEAM_COUNT
		local len = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HOLE_RADIUS
		local mid = Config.SWEEP_HOLE_RADIUS + len / 2
		for i = 0, n - 1 do
			local angle = (i / n) * TAU
			counted(newPart(folder, "SeamGroove_" .. i, Vector3.new(len, 0.12, 1.6),
				radialCFrame(c, angle, surfaceY + 0.03, mid), Config.SWEEP_RAIL_COLOR,
				Enum.Material.SmoothPlastic, 0))
			local p = counted(newPart(folder, "Seam_" .. i, Vector3.new(len, 0.15, 0.9),
				radialCFrame(c, angle, surfaceY + 0.05, mid), Config.SWEEP_ACCENT,
				Enum.Material.Neon, SEAM_IDLE_TRANSPARENCY))
			seamStrips[#seamStrips + 1] = { part = p, angle = angle, lastTransparency = SEAM_IDLE_TRANSPARENCY }
		end
	end
```

b. Replace section 2 (chase studs) and section 7 (rim accent ring) with ONE rim ring section:

```lua
	----------------------------------------------------------------------------
	-- 2. Rim ring: continuous bright band on the disc's outer edge face (48
	--    tangent segments, slack-overlapped like the floor). Replaces the chase
	--    studs, rim accent bars, and the generic ArenaDressing edge trim.
	----------------------------------------------------------------------------
	local rimRing = {}
	do
		local segs = 48
		local radius = Config.SWEEP_PLATFORM_RADIUS + 0.2
		local pts = WorldLayout.ring(c.X, c.Z, radius, segs)
		local chord = 2 * radius * math.sin(math.pi / segs) * 1.06
		local y = surfaceY - 0.55 -- band top flush with the deck (+0.05)
		for i, pt in ipairs(pts) do
			local nxt = pts[(i % segs) + 1]
			local p = counted(newPart(folder, "RimRing_" .. i, Vector3.new(0.4, 1.2, chord),
				CFrame.lookAt(Vector3.new(pt.x, y, pt.z), Vector3.new(nxt.x, y, nxt.z)),
				Config.SWEEP_ACCENT, Enum.Material.Neon, RIM_RING_TRANSPARENCY))
			rimRing[#rimRing + 1] = { part = p, liveTransparency = RIM_RING_TRANSPARENCY }
		end
	end

	----------------------------------------------------------------------------
	-- 2b. Moat line: faint inner-rim band at the fall-gap's disc edge -- keeps
	--     the hole readable at play speed (fairness; the reference hides it).
	----------------------------------------------------------------------------
	local moatRing = {}
	do
		local segs = 24
		local radius = Config.SWEEP_HOLE_RADIUS - 0.2
		local pts = WorldLayout.ring(c.X, c.Z, radius, segs)
		local chord = 2 * radius * math.sin(math.pi / segs) * 1.06
		local y = surfaceY - 0.2 -- band top flush with the deck (+0.05)
		for i, pt in ipairs(pts) do
			local nxt = pts[(i % segs) + 1]
			local p = counted(newPart(folder, "MoatRing_" .. i, Vector3.new(0.3, 0.5, chord),
				CFrame.lookAt(Vector3.new(pt.x, y, pt.z), Vector3.new(nxt.x, y, nxt.z)),
				Config.SWEEP_ACCENT, Enum.Material.Neon, MOAT_TRANSPARENCY))
			moatRing[#moatRing + 1] = { part = p, liveTransparency = MOAT_TRANSPARENCY }
		end
	end
```

c. DELETE outright: section 3 (rotor rings incl. `buildRotorRing`, `rotor1Bars`, `rotor2Bars`, offsets), section 3b (HubMesh hybrid hook — superseded by Task 4's built hub; NOTE: keep the `ReplicatedStorage` service local — the `Shared` module requires at the top of the file use it), section 4 (light shaft), section 6 (spotlight fixtures). KEEP section 5 (under-structure) and section 8 (smooth annulus) exactly as they are.

d. Update the chase-state comment block (`chaseIndex/chaseAccum/chaseWindow`): delete those three locals.

- [ ] **Step 4: SweeperController — dormancy + Heartbeat rewrite**

a. Replace the `staticNeon` assembly and `setLive` with:

```lua
	local staticNeon = {}
	for _, b in ipairs(rimRing) do staticNeon[#staticNeon + 1] = b end
	for _, b in ipairs(moatRing) do staticNeon[#staticNeon + 1] = b end

	local function setLive(live)
		for _, e in ipairs(staticNeon) do
			e.part.Transparency = live and e.liveTransparency or DORMANT_TRANSPARENCY
		end
		local resetTo = (not live) and DORMANT_TRANSPARENCY or nil
		for _, s in ipairs(seamStrips) do
			s.part.Transparency = resetTo or SEAM_IDLE_TRANSPARENCY
			s.lastTransparency = nil -- force a resync on the next live tick
		end
	end
```

b. In the Heartbeat handler: keep the low-bar re-find and the lag probe as-is;
retarget the wake loop at the seams (same math, new names):

```lua
		for _, s in ipairs(seamStrips) do
			local behind = (lowBeam.direction * (lowAngle - s.angle)) % TAU
			local target
			if behind >= SEAM_FLARE_WINDOW then
				target = SEAM_IDLE_TRANSPARENCY
			else
				target = SEAM_FLARE_TRANSPARENCY
					+ (SEAM_IDLE_TRANSPARENCY - SEAM_FLARE_TRANSPARENCY) * (behind / SEAM_FLARE_WINDOW)
			end
			if s.lastTransparency == nil or math.abs(target - s.lastTransparency) > 0.02 then
				s.part.Transparency = target
				s.lastTransparency = target
			end
		end
```

Then DELETE the chase-advance block and the rotor counter-rotation block at the
end of the handler. The handler ends after the seam loop.

c. The part-budget assert stays `<= 180`; update its neighboring comment if it
itemizes the old elements.

- [ ] **Step 5: Run the suites**

Run the test command. Expected: all pass. Also verify no dangling references:

```bash
grep -nE "wakeStrips|chaseStuds|rotor1Bars|rotor2Bars|shaftPart|rimAccentBars|WAKE_|CHASE_|ROTOR_|SHAFT_|LENS_|RIM_ACCENT_|HubMesh|SweeperAssets" src/client/SweeperController.luau
```
Expected: no output.

- [ ] **Step 6: Commit (HAZARD procedure)**

`<OTHER_FILES> = src/client/SweeperController.luau`, message
`feat(sweeper): 12-wedge seam system (wake fused), rim ring + moat line; retire chase/rotors/shaft/lenses/HubMesh hook`.

---

### Task 4: Client — hub stack with glass-encased lantern

**Files:**
- Modify: `src/shared/Config.luau` (1 new key — HAZARD procedure on commit)
- Modify: `src/client/SweeperController.luau` (new build section; dormancy hookup)

- [ ] **Step 1: Config — lantern knob**

Next to the Task-3 GLOW_DIM keys, add:

```lua
Config.GLOW_DIM_SWEEP_LANTERN = 0.0   -- hub lantern core (SweeperController)
```

- [ ] **Step 2: SweeperController — lantern constant**

Next to the Task-3 constants, add:

```lua
local LANTERN_TRANSPARENCY = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_LANTERN)
```

- [ ] **Step 3: Build the hub stack**

Insert a new section 3 (where the rotor rings used to live), after the rim/moat
sections. Heights are studs relative to `surfaceY`; vertical cylinders use the
established Z-roll convention (Size.X = height, Y/Z = diameter):

```lua
	----------------------------------------------------------------------------
	-- 3. Hub stack (spec §4.3): flared skirt into the moat, stacked drums with
	--    a shadow groove, high-bar ledge, GLASS-encased amber lantern core with
	--    a PointLight, bezel rings, rounded cap. Replaces the rotor rings /
	--    light shaft / spotlight fixtures / HubMesh hook. All non-collidable
	--    cosmetics; the server's collidable r=6 pillar + motor axle are untouched.
	----------------------------------------------------------------------------
	local lanternCore, lanternLight
	do
		local function cyl(name, radius, yBottom, yTop, cylColor, material, transparency)
			local p = newPart(folder, name, Vector3.new(yTop - yBottom, radius * 2, radius * 2),
				CFrame.new(c.X, surfaceY + (yBottom + yTop) / 2, c.Z) * CFrame.Angles(0, 0, math.rad(90)),
				cylColor, material, transparency)
			p.Shape = Enum.PartType.Cylinder
			return counted(p)
		end
		local grooveColor = Color3.fromRGB(10, 13, 30)
		-- Skirt: flares down into the fall-gap; max radius 8.5 < HOLE_RADIUS 12,
		-- so the moat stays open (and lethal). Non-collidable like everything here.
		cyl("HubSkirt1", 8.5, -2.5, -0.8, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubSkirt2", 7.6, -0.8, 0.2, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		-- Drums hug the collidable pillar (visual overhang 0.3, cosmetic-only).
		cyl("HubDrum1", 6.3, 0.2, 3.3, Config.SWEEP_PLATFORM_COLOR, Enum.Material.Metal, 0)
		cyl("HubGroove", 5.95, 3.3, 3.5, grooveColor, Enum.Material.SmoothPlastic, 0)
		cyl("HubDrum2", 6.15, 3.5, 6.8, Config.SWEEP_PLATFORM_COLOR, Enum.Material.Metal, 0)
		-- Ledge sits ABOVE the high-bar collar's sweep (collar top ~ y 9.0).
		cyl("HubLedge", 7.2, 9.3, 9.7, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubBezelLow", 3.8, 9.9, 10.3, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		-- Lantern: outer GLASS wall (visible transparency), inner Neon core with
		-- an air gap, per the reference read (glow embedded in glass).
		local glass = cyl("HubLanternGlass", 3.4, 10.2, 14.0,
			Color3.fromRGB(205, 222, 255), Enum.Material.Glass, 0.45)
		glass.CastShadow = false
		lanternCore = cyl("HubLanternCore", 2.3, 10.5, 13.7,
			Config.SWEEP_ACCENT, Enum.Material.Neon, LANTERN_TRANSPARENCY)
		lanternLight = Instance.new("PointLight")
		lanternLight.Color = Config.SWEEP_ACCENT
		lanternLight.Brightness = 2
		lanternLight.Range = 26
		lanternLight.Parent = lanternCore
		cyl("HubBezelHigh", 3.8, 13.9, 14.3, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubCap", 3.2, 14.3, 15.3, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubCapTop", 2.6, 15.3, 15.7, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
	end
```

- [ ] **Step 4: Dormancy hookup**

In the `staticNeon` assembly add the core, and gate the light in `setLive`:

```lua
	staticNeon[#staticNeon + 1] = { part = lanternCore, liveTransparency = LANTERN_TRANSPARENCY }
```

and as the first line inside `setLive`:

```lua
		lanternLight.Enabled = live
```

- [ ] **Step 5: Run the suites + reference scan**

Run the test command (expected: all pass), then:

```bash
grep -nE "buildRotorRing|LightShaft|SpotHousing|SpotLens" src/client/SweeperController.luau
```
Expected: no output.

- [ ] **Step 6: Commit (HAZARD procedure)**

`<OTHER_FILES> = src/client/SweeperController.luau`, message
`feat(sweeper): hub stack -- skirt, stacked drums, ledge, glass-encased lantern core + light, cap`.

---

### Task 5: Config cleanup — delete dead keys, repo-wide sweep

**Files:**
- Modify: `src/shared/Config.luau` (HAZARD procedure on commit)

- [ ] **Step 1: Delete the dead keys**

Remove these lines from `src/shared/Config.luau` (and any comment lines that
describe only them):
`SWEEP_WAKE_CHANNELS`, `SWEEP_CHASE_STUDS`, `GLOW_DIM_SWEEP_WAKE`,
`GLOW_DIM_SWEEP_CHASE`, `GLOW_DIM_SWEEP_ROTOR`, `GLOW_DIM_SWEEP_SHAFT`,
`GLOW_DIM_SWEEP_LENS`, `GLOW_DIM_SWEEP_RIM`, `GLOW_DIM_SWEEP_TRIM`.

- [ ] **Step 2: Prove nothing references them**

```bash
grep -rnE "SWEEP_WAKE_CHANNELS|SWEEP_CHASE_STUDS|GLOW_DIM_SWEEP_(WAKE|CHASE|ROTOR|SHAFT|LENS|RIM|TRIM)\b" src/ tests/ scripts/
```
Expected: no output. (`GLOW_DIM_SWEEP_RIM_RING` must NOT match — note the `\b`.)

- [ ] **Step 3: Run ALL suites**

Run the test command. Expected: every suite passes (glow_dim.spec tests the
pure `GlowDim.apply`, not specific keys — but this run proves it).

- [ ] **Step 4: Commit (HAZARD procedure)**

`<OTHER_FILES>` = none (Config only), message
`chore(sweeper): drop retired cosmetic Config keys (wake/chase/rotor/shaft/lens/rim/trim)`.

---

### Task 6: Studio visual pass + CHANGELOG (ORCHESTRATOR — main session, not a subagent)

Per spec §6: Rojo serve check → Studio Play solo (dev flips pin sweeper/solo) →
`screen_capture` at a reference-like angle → element-by-element compare vs
`gemini-t4-master-1.png` → tune §4.4 visual tunables (≤2 iterations, re-capture,
commits via HAZARD procedure if Config colors change) → console error scan →
CHANGELOG entry under `## [2026-07-13]` summarizing the glow-up (elements added,
elements retired, knobs, spec/plan links) → commit CHANGELOG.

---

## Self-review notes

- Spec coverage: §4.1→Task 2, §4.2→Tasks 3–4, §4.3→Task 1, §4.4→Tasks 2/3/4/5,
  §4.5→hazard header, §5→each task's suite run, §6→Task 6. No gaps.
- Names consistent across tasks: `SWEEP_RAIL_COLOR` (T2, reused T3/T4),
  `seamStrips`/`rimRing`/`moatRing` (T3, dormancy T3/T4), `lanternCore`/
  `lanternLight` (T4). `counted`, `newPart`, `radialCFrame`, `weldOn`,
  `WorldLayout.ring` all pre-exist in the target files.
- Part budget: 12 grooves + 12 seams + 48 rim + 24 moat + 12 hub + 1 annulus +
  16 under-structure ≈ 125 ≤ 180 assert. ✓
