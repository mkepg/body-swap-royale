# Soul Sweeper v2.4 — Hitbox↔Visual Alignment + Dim Pass Implementation Plan

**Goal:** Kills fire only when a bar visibly touches the body (kill band derived from the mesh + render-lag-compensated strike window), and the arena's Neon dressing dims to accent level so bars/floor/players stay readable.

**Architecture:** Two new pure functions in `SweeperModel` (lune-tested) carry the logic: `killHalfWidth` derives the kill band from the same thickness constant that sizes the bar mesh, and `delayedWindow` picks the strike-test sweep window `SWEEP_STRIKE_LAG_TICKS` monitor ticks in the past from a per-beam measured-angle history (matching what clients render through the replication interpolation buffer). `SweeperHazard` glue feeds them; a flag-gated lag probe (server attribute + client print) measures the real render lag. The dim pass is constant changes in `SweeperController`.

**Tech Stack:** Luau (Rojo project), lune for pure-module tests, Studio MCP for live verification.

**Spec:** `docs/specs/2026-07-09-soul-sweeper-v2_4-hitbox-visual-alignment-design.md`

---

## ⚠️ Commit hygiene — dev flips (EVERY task)

`src/shared/Config.luau` currently carries two UNCOMMITTED dev flips that must NEVER land in a commit:
`Config.SOLO_TEST_MODE = true` (line ~195) and `Config.ARENA_OVERRIDE = "sweeper"` (line ~91).

Whenever a task stages `Config.luau`:
1. Edit the flips to production values: `SOLO_TEST_MODE = false`, `ARENA_OVERRIDE = ""`.
2. `git add` the task's files (explicit paths only — never `git add -A`/`-u`).
3. Restore the flips in the working tree: `SOLO_TEST_MODE = true`, `ARENA_OVERRIDE = "sweeper"` (staged snapshot is unaffected).
4. Verify the staged diff is clean: `git diff --cached src/shared/Config.luau | grep -E "SOLO_TEST_MODE|ARENA_OVERRIDE"` → must print **nothing** (the comment block around them is untouched).
5. Commit.

Test command prefix (Git Bash): `export PATH="$HOME/.rokit/bin:$PATH"`

---

### Task 1: Derived kill band (`killHalfWidth`)

**Files:**
- Modify: `src/shared/SweeperModel.luau` (insert after the `clears` function, ~line 55)
- Modify: `src/shared/Config.luau:133-137` (the KILL_HALF block)
- Modify: `src/server/SweeperHazard.luau:124-133` (killHalf/beamThickness)
- Test: `tests/sweeper_model.spec.luau` (insert after the `clears` block, ~line 45)

- [ ] **Step 1: Write the failing test**

Insert into `tests/sweeper_model.spec.luau` after the `clears` do-block:

```lua
-- killHalfWidth (v2.4): kill band DERIVED from the bar's visible thickness + the
-- body contact pad, so hitbox and mesh share one knob and cannot drift.
do
	expect(near(M.killHalfWidth(1, 0.5), 1.0), "low bar: 1 thick + 0.5 pad -> 1.0")
	expect(near(M.killHalfWidth(3, 0.5), 2.0), "high bar: 3 thick + 0.5 pad -> 2.0")
	expect(near(M.killHalfWidth(2, 0), 1.0), "zero pad -> exactly the visible half")
	print("sweeper: killHalfWidth OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: FAIL — `attempt to call a nil value` (killHalfWidth not defined)

- [ ] **Step 3: Implement `SweeperModel.killHalfWidth`**

Insert into `src/shared/SweeperModel.luau` after the `clears` function (before the `isStruckSwept` doc comment):

```lua
-- v2.4: the kill band half-width is DERIVED from the bar's visible thickness --
-- half the root-spine thickness (the visible bar edge) + the struck body's own
-- half-extent around its sampled root point (Config.SWEEP_BODY_CONTACT_PAD). One
-- constant sizes both the mesh and the hitbox, so they can never drift apart.
function SweeperModel.killHalfWidth(thickness, contactPad)
	return thickness / 2 + contactPad
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: PASS — all blocks print OK, ends `ALL SweeperModel TESTS PASSED`

- [ ] **Step 5: Replace the Config KILL_HALF constants**

In `src/shared/Config.luau`, replace:

```lua
-- Constant stud half-width of each bar's kill band = visible half-thickness +
-- body/latency pad. Replaces the old angular half-width (v2.2), whose physical
-- width grew with radius (~2 studs near the hub, ~8 studs at the rim). Tuning knobs.
Config.SWEEP_BEAM_LOW_KILL_HALF = 2.0
Config.SWEEP_BEAM_HIGH_KILL_HALF = 3.0
```

with:

```lua
-- Kill band half-width is DERIVED, not hand-tuned (v2.4): visible half-thickness
-- (the same SWEEP_BEAM_*_THICKNESS that sizes each root spine) + the body contact
-- pad below -- see SweeperModel.killHalfWidth. The v2.3 KILL_HALF constants carried
-- a ~1.5-stud symmetric "latency pad" that killed before visible contact; render
-- latency is handled separately now (SWEEP_STRIKE_LAG_TICKS, v2.4 part 2), and the
-- pad covers only the struck BODY's own half-extent around its sampled root point.
-- 0.5 = half a normalized-R15 torso depth: the bar edge meeting the body edge when
-- facing it; broadside limb contact errs slightly LATE by design ("only when it
-- visibly touches").
Config.SWEEP_BODY_CONTACT_PAD = 0.5
```

- [ ] **Step 6: Derive killHalf in SweeperHazard (and fix definition order)**

In `src/server/SweeperHazard.luau`, replace:

```lua
-- Constant stud half-width of a beam class's kill band (spec v2.3 §2-3).
local function killHalf(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_KILL_HALF end
	return Config.SWEEP_BEAM_HIGH_KILL_HALF
end

local function beamThickness(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_THICKNESS end
	return Config.SWEEP_BEAM_HIGH_THICKNESS
end
```

with (killHalf must come AFTER beamThickness — it closes over it):

```lua
local function beamThickness(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_THICKNESS end
	return Config.SWEEP_BEAM_HIGH_THICKNESS
end

-- Kill band half-width DERIVED from the same thickness that sizes the root spine
-- (spec v2.4 §2-1): hitbox and mesh cannot drift.
local function killHalf(class)
	return SweeperModel.killHalfWidth(beamThickness(class), Config.SWEEP_BODY_CONTACT_PAD)
end
```

- [ ] **Step 7: Verify no stale references**

Run: `grep -rn "KILL_HALF" src/`
Expected: **no matches** (the only historical mentions live in docs/, which is fine)

- [ ] **Step 8: Full lune suite**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: every suite prints its PASSED line; exit code 0

- [ ] **Step 9: Commit (follow the dev-flip hygiene block above — Config is staged here)**

```bash
git add src/shared/SweeperModel.luau src/shared/Config.luau src/server/SweeperHazard.luau tests/sweeper_model.spec.luau docs/specs/2026-07-09-soul-sweeper-v2_4-hitbox-visual-alignment-design.md docs/plans/2026-07-09-soul-sweeper-v2_4-hitbox-visual-alignment.md
git commit -m "fix(sweeper-v2.4): derive kill band from visible bar thickness

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Render-lag-compensated strike window + lag probe

**Files:**
- Modify: `src/shared/SweeperModel.luau` (insert after `killHalfWidth`)
- Modify: `src/shared/Config.luau` (insert after the SWEEP_BODY_CONTACT_PAD block)
- Modify: `src/server/SweeperHazard.luau` (beamRecs comment ~line 41; lifecycle comment ~line 23; `buildBeamAssembly` return ~line 296; `stop()` ~lines 383-396; `step()` ~lines 425-456)
- Modify: `src/client/SweeperController.luau` (probe accumulators + Heartbeat block)
- Test: `tests/sweeper_model.spec.luau` (insert after the killHalfWidth block from Task 1)

- [ ] **Step 1: Write the failing test**

Insert into `tests/sweeper_model.spec.luau` after the killHalfWidth do-block:

```lua
-- delayedWindow (v2.4): render-lag compensation -- picks the sweep window ending
-- lagTicks samples in the past; nil while the history is too short (caller skips);
-- a window at the very start of history has a nil prev (instantaneous fallback).
do
	local a1, p1 = M.delayedWindow({ 0.1, 0.2, 0.3 }, 1)
	expect(near(a1, 0.2) and near(p1, 0.1), "lag 1 -> window ending one sample back")
	local a2, p2 = M.delayedWindow({ 0.1, 0.2, 0.3 }, 0)
	expect(near(a2, 0.3) and near(p2, 0.2), "lag 0 -> freshest window")
	local a3, p3 = M.delayedWindow({ 0.1 }, 0)
	expect(near(a3, 0.1) and p3 == nil, "single sample -> instantaneous (nil prev)")
	expect(M.delayedWindow({ 0.1 }, 1) == nil, "history shorter than lag -> nil (skip)")
	expect(M.delayedWindow({}, 0) == nil, "empty history -> nil (skip)")
	print("sweeper: delayedWindow OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: FAIL — `attempt to call a nil value` (delayedWindow not defined)

- [ ] **Step 3: Implement `SweeperModel.delayedWindow`**

Insert into `src/shared/SweeperModel.luau` after `killHalfWidth`:

```lua
-- v2.4 render-lag compensation (spec §2-2): pick the sweep window ending `lagTicks`
-- samples in the past from a measured-angle history (oldest first, newest last).
-- Returns the (angle, prevAngle) pair to feed isStruckSwept -- history[0] is nil,
-- so a window at the very start of history degrades to the model's instantaneous
-- first-tick fallback -- or nil when the history is still too short (round start /
-- post-re-park): the caller skips the strike test that tick rather than testing an
-- unlagged window.
function SweeperModel.delayedWindow(history, lagTicks)
	local i = #history - lagTicks
	if i < 1 then
		return nil, nil
	end
	return history[i], history[i - 1]
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/sweeper_model.spec.luau`
Expected: PASS — ends `ALL SweeperModel TESTS PASSED`

- [ ] **Step 5: Add the two Config keys**

In `src/shared/Config.luau`, insert directly after the `Config.SWEEP_BODY_CONTACT_PAD = 0.5` line (before `Config.SWEEP_SPEED_RAMP_PER_SEC`):

```lua
-- v2.4 render-lag compensation (spec §2-2): the strike test runs against the sweep
-- window this many monitor ticks (0.1 s each) in the PAST. Clients render the
-- server-owned bars through Roblox's replication interpolation buffer, so the
-- on-screen bar trails the authoritative pose -- killing on the authoritative
-- window eliminated players before the bar VISIBLY reached them. 1 tick = 100 ms
-- ~= the expected interpolation buffer (probe measurement pending v2.4 live
-- verification -- recorded here once run). 0 disables (freshest window). Integer.
Config.SWEEP_STRIKE_LAG_TICKS = 1
-- Dev/measurement switch (like SOLO_TEST_MODE, NOT a gameplay tunable): when true
-- the server stamps the low bar's authoritative angle as an `AuthAngle` attribute
-- each monitor tick and the client prints a 1 s rolling rendered-vs-authoritative
-- lag readout ([BSR][lagprobe]) -- used to size SWEEP_STRIKE_LAG_TICKS. Leave false.
Config.SWEEP_LAG_PROBE = false
```

- [ ] **Step 6: Rewire SweeperHazard to the angle history**

Four edits in `src/server/SweeperHazard.luau`:

**(a)** Replace the beamRecs comment (~line 41):

```lua
-- { { beam = config, part = Part (the assembly's non-collidable root spine),
--     hinge = HingeConstraint (the motor), y = centerY, prevAngle = number? }, ... }
```

with:

```lua
-- { { beam = config, part = Part (the assembly's non-collidable root spine),
--     hinge = HingeConstraint (the motor), y = centerY,
--     angleHist = { measured angles, oldest first } }, ... }
```

**(b)** In the lifecycle comment (~line 23), replace `clear prevAngle` with `clear angle history`.

**(c)** In `buildBeamAssembly`, replace the return line:

```lua
	return { beam = beam, part = root, hinge = hinge, y = centerY }
```

with:

```lua
	return { beam = beam, part = root, hinge = hinge, y = centerY, angleHist = {} }
```

**(d)** In `stop()`, replace:

```lua
	-- Dormant cost stays ~zero (a braked motor holding a resting bar does no
	-- per-frame Luau work). Clearing prevAngle means the NEXT round's first step()
	-- tick has no prior sample, so SweeperModel.isStruckSwept falls back to the
	-- instantaneous check instead of reading this re-park jump as a
	-- (potentially kill-wide) swept arc.
```

with:

```lua
	-- Dormant cost stays ~zero (a braked motor holding a resting bar does no
	-- per-frame Luau work). Clearing angleHist means the NEXT round's first ticks
	-- have no lagged window yet (SweeperModel.delayedWindow returns nil -> strike
	-- test skipped, covered by round-start grace), so this re-park jump can never
	-- be read as a (potentially kill-wide) swept arc.
```

and, in the loop below it, replace `rec.prevAngle = nil` with `rec.angleHist = {}`.

- [ ] **Step 7: Rewire `step()` to the delayed window (+ server probe stamp)**

In `src/server/SweeperHazard.luau`, replace the step() doc comment (the block starting `-- Per monitor tick: refresh each motor's ramped target speed,` down to `-- Grace-blocked / off-platform bodies are skipped entirely (no strike test run).`) with:

```lua
-- Per monitor tick: refresh each motor's ramped target speed, push each bar's
-- MEASURED angle onto its history, then strike-test the sweep window ending
-- SWEEP_STRIKE_LAG_TICKS ticks ago (SweeperModel.delayedWindow -> isStruckSwept):
-- the swept interval covers the arc's full motion between samples (no rotation
-- speed can tunnel past a player between 10 Hz ticks), and the LAG makes the kill
-- land on the pose clients actually SEE (replication interpolation trails the
-- authoritative pose -- spec v2.4 §2-2). A struck non-grace on-platform body is
-- queued for elimination via the SAME grace-gated chokepoint as void death
-- (RoundManager.eliminateFromHazard). Grace-blocked / off-platform bodies are
-- skipped entirely (no strike test run).
```

and replace the beam loop inside `step()`:

```lua
	local beamsNow = {}
	for i, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = motorTarget(rec.beam, elapsed, speedOpts)
		local angle = measuredAngle(rec)
		beamsNow[i] = {
			angle = angle,
			prevAngle = rec.prevAngle,
			direction = rec.beam.direction,
			class = rec.beam.class,
			innerRadius = Config.SWEEP_HUB_RADIUS,
			outerRadius = Config.SWEEP_PLATFORM_RADIUS,
			killHalfWidth = killHalf(rec.beam.class),
		}
		rec.prevAngle = angle
	end
```

with:

```lua
	local beamsNow = {}
	for _, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = motorTarget(rec.beam, elapsed, speedOpts)
		local hist = rec.angleHist
		hist[#hist + 1] = measuredAngle(rec)
		-- Cap the history at what delayedWindow can ever read (lag + window pair).
		if #hist > Config.SWEEP_STRIKE_LAG_TICKS + 2 then
			table.remove(hist, 1)
		end
		if Config.SWEEP_LAG_PROBE and rec.beam.class == "low" then
			rec.part:SetAttribute("AuthAngle", hist[#hist])
		end
		local angle, prevAngle = SweeperModel.delayedWindow(hist, Config.SWEEP_STRIKE_LAG_TICKS)
		if angle then
			beamsNow[#beamsNow + 1] = {
				angle = angle,
				prevAngle = prevAngle,
				direction = rec.beam.direction,
				class = rec.beam.class,
				innerRadius = Config.SWEEP_HUB_RADIUS,
				outerRadius = Config.SWEEP_PLATFORM_RADIUS,
				killHalfWidth = killHalf(rec.beam.class),
			}
		end
	end
```

- [ ] **Step 8: Client probe readout**

Two edits in `src/client/SweeperController.luau`:

**(a)** Directly above the `RunService.Heartbeat:Connect(function(dt)` line, insert:

```lua
	-- Lag probe accumulators (Config.SWEEP_LAG_PROBE; spec v2.4 §2-3).
	local probeSum, probeMax, probeN, probeWindow = 0, 0, 0, 0
```

**(b)** Inside the `if lowBeamPart then` block, directly after the `local lowAngle = ...` line, insert:

```lua
		-- Dev lag probe: how far the RENDERED bar trails the server's authoritative
		-- angle (stamped as AuthAngle each monitor tick). Positive = rendered pose
		-- is behind. Accuracy is +-half a monitor tick (the stamp is 10 Hz).
		if Config.SWEEP_LAG_PROBE then
			local auth = lowBeamPart:GetAttribute("AuthAngle")
			if auth then
				local lag = ((auth - lowAngle) * lowBeam.direction) % TAU
				if lag > math.pi then lag -= TAU end
				probeSum += lag
				probeN += 1
				if lag > probeMax then probeMax = lag end
				probeWindow += dt
				if probeWindow >= 1 and probeN > 0 then
					local mean = probeSum / probeN
					print(string.format(
						"[BSR][lagprobe] mean %.4f rad / max %.4f rad (%.2f / %.2f studs at r=%d)",
						mean, probeMax, mean * Config.SWEEP_SPAWN_RADIUS,
						probeMax * Config.SWEEP_SPAWN_RADIUS, Config.SWEEP_SPAWN_RADIUS))
					probeSum, probeMax, probeN, probeWindow = 0, 0, 0, 0
				end
			end
		end
```

- [ ] **Step 9: Verify no stale per-rec prevAngle STATE**

Run: `grep -rn "rec\.prevAngle" src/server/ src/client/`
Expected: **no matches** (the per-rec state field is fully replaced by `angleHist`; the local
`prevAngle` + beam-table key inside `step()` legitimately remain — that key is the pure model's
isStruckSwept contract field)

- [ ] **Step 10: Full lune suite**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: every suite passes; exit code 0

- [ ] **Step 11: Commit (follow the dev-flip hygiene block — Config is staged here)**

```bash
git add src/shared/SweeperModel.luau src/shared/Config.luau src/server/SweeperHazard.luau src/client/SweeperController.luau tests/sweeper_model.spec.luau
git commit -m "fix(sweeper-v2.4): strike-test the render-lagged sweep window + lag probe

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Arena dim pass

**Files:**
- Modify: `src/client/SweeperController.luau:45-52` (the transparency constants)

- [ ] **Step 1: Replace the dressing transparency constants**

In `src/client/SweeperController.luau`, replace:

```lua
local WAKE_BASE_TRANSPARENCY = 0.9
local WAKE_LIT_TRANSPARENCY = 0.15
local CHASE_BASE_TRANSPARENCY = 0.6
local CHASE_LIT_TRANSPARENCY = 0.1
local ROTOR_TRANSPARENCY = 0.35
local SHAFT_TRANSPARENCY = 0.7
local LENS_TRANSPARENCY = 0.2
local RIM_ACCENT_TRANSPARENCY = 0
```

with:

```lua
-- v2.4 dim pass (spec §2-4): the dressing is ATMOSPHERE, not signal -- only the
-- bars' kill tells (amber blade / crimson underglow / end emitters, built server-
-- side in SweeperHazard) stay full-brightness Neon. Everything here sits at accent
-- level so the tells, the floor, and other players stay readable under Bloom 0.9.
-- Lit/static values stay below SWEEP_STANDBY_TRANSPARENCY (0.85) so dormancy still
-- visibly dims the arena.
local WAKE_BASE_TRANSPARENCY = 0.9
local WAKE_LIT_TRANSPARENCY = 0.5
local CHASE_BASE_TRANSPARENCY = 0.75
local CHASE_LIT_TRANSPARENCY = 0.4
local ROTOR_TRANSPARENCY = 0.6
local SHAFT_TRANSPARENCY = 0.8
local LENS_TRANSPARENCY = 0.5
local RIM_ACCENT_TRANSPARENCY = 0.55
```

- [ ] **Step 2: Sanity check — no other literal uses of the old values**

Run: `grep -n "TRANSPARENCY" src/client/SweeperController.luau`
Expected: only the constant definitions above plus their existing usages (`WAKE_BASE_TRANSPARENCY`, `CHASE_LIT_TRANSPARENCY`, etc.) — no raw numeric transparency literals for these elements elsewhere

- [ ] **Step 3: Full lune suite (regression guard)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: all pass (client-only change; suite green confirms nothing else drifted)

- [ ] **Step 4: Commit (Config NOT staged — no flip dance needed)**

```bash
git add src/client/SweeperController.luau
git commit -m "feat(sweeper-v2.4): dim dressing Neon to accent level (kill tells stay bright)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Docs — CHANGELOG entry + smoke-test addendum

**Files:**
- Modify: `CHANGELOG.md` (insert as the FIRST bullet under `## [2026-07-09]` → `### Added`)
- Modify: `docs/smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md` (append a new section at the end)

- [ ] **Step 1: CHANGELOG entry**

Insert as the first bullet under the existing `## [2026-07-09]` / `### Added` heading:

```markdown
- **Soul Sweeper v2.4 — hitbox↔visual alignment + arena dim pass.** Feel-pass report: players
  died BEFORE the bar visibly touched them, and the Neon glare hurt readability. Two verified
  causes for the early kills: (A) the v2.3 kill half-widths carried a ~1.5-stud symmetric
  "latency pad" (the LOW bar killed across 4 studs while showing 1); (B) clients render the
  server-owned bars through the replication interpolation buffer (~100 ms), so authoritative-pose
  kills always land AHEAD of the rendered bar (~2.2 studs at spawn radius at base speed, growing
  with the ramp). Fixed: kill bands are DERIVED from the visible mesh (pure
  `SweeperModel.killHalfWidth` = spine half-thickness + `SWEEP_BODY_CONTACT_PAD` 0.5; low
  2.0→1.0, high 3.0→2.0; the hand-tuned KILL_HALF constants are retired — hitbox and mesh share
  one thickness knob and cannot drift), and the strike test runs against the sweep window
  `SWEEP_STRIKE_LAG_TICKS` (1 tick = 100 ms) in the past via a per-beam measured-angle history
  (pure `SweeperModel.delayedWindow`; warm-up ticks skip the test, covered by round-start grace;
  the anti-tunneling tiling is preserved), so kills land on the pose players actually SEE. A
  flag-gated `SWEEP_LAG_PROBE` measures rendered-vs-authoritative lag live to size the tick
  count. Dim pass: dressing Neon dropped to accent level (rim accent 0→0.55, wake-lit 0.15→0.5,
  chase 0.1/0.6→0.4/0.75, rotors 0.35→0.6, shaft 0.7→0.8, lenses 0.2→0.5); the amber-blade /
  crimson-underglow kill tells stay full-brightness and gain contrast. Verified: full lune run
  green. See [spec](superpowers/specs/2026-07-09-soul-sweeper-v2_4-hitbox-visual-alignment-design.md)
  and [plan](superpowers/plans/2026-07-09-soul-sweeper-v2_4-hitbox-visual-alignment.md).
```

- [ ] **Step 2: Smoke-test addendum**

Append at the end of `docs/smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md`:

```markdown
## v2.4 addendum — hitbox↔visual alignment + dim pass (2026-07-09)

Solo-verifiable (`SOLO_TEST_MODE = true` + `ARENA_OVERRIDE = "sweeper"`):

- **SW-V24-1 (visible-contact kill):** stand still in the low bar's path and watch the amber
  blade. PASS = elimination fires only as the blade visibly reaches the body, not studs ahead.
- **SW-V24-2 (jump timing on the VISIBLE bar):** jump keyed to the visible blade's arrival.
  PASS = clean clear; no "invisible edge" kill during ascent.
- **SW-V24-3 (duck-under):** stand grounded as the crimson boom passes. PASS = survive. Then
  jump INTO it. PASS = eliminated only at visible contact.
- **SW-V24-4 (warm-up + round 2):** let the round end and the next begin. PASS = parked bars
  kill nobody during grace; formation unchanged; no strike in the first ~0.2 s (history warm-up).
- **SW-V24-5 (lag probe):** flip `SWEEP_LAG_PROBE = true`, play ~30 s across the ramp, read
  `[BSR][lagprobe]` in the client output. Record mean/max into the `SWEEP_STRIKE_LAG_TICKS`
  Config comment; expect ~1 monitor tick. Flip the probe back to false.
- **SW-V24-6 (dim read):** at round start and mid-ramp: rim/wake/chase/rotors read as accents;
  the amber blade + crimson underglow are the unambiguous brightest elements; the floor and
  other players are clearly visible. Dormant sweeper (hex round live) still visibly dims.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md docs/smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md
git commit -m "docs(sweeper-v2.4): CHANGELOG + smoke addendum

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Live verification (MAIN SESSION — not a subagent task)

Via Studio MCP, dev flips on (`SOLO_TEST_MODE = true`, `ARENA_OVERRIDE = "sweeper"`):

1. Confirm Rojo sync picked up the changes (verify a changed script's `Source` marker in Edit mode).
2. **Probe run:** flip `SWEEP_LAG_PROBE = true` in the working tree, Play Solo, collect
   `[BSR][lagprobe]` lines across ~30 s of ramp (get_console_output), stop, flip back. Record the
   measured mean/max in the `SWEEP_STRIKE_LAG_TICKS` Config comment (replacing "measurement
   pending"; commit that comment with the flip-hygiene dance). If measured lag ≈ 0, discuss
   dropping LAG_TICKS to 0 with the user before changing it.
3. Smoke cases SW-V24-1 … SW-V24-6 (user drives feel; MCP verifies state where possible).
4. Hex regression: one hex round (clear ARENA_OVERRIDE), confirm untouched behavior.
