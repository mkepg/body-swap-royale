# Soul Sweeper v2.3 — Collision Fix Implementation Plan

**Goal:** Fix the inverted vertical-state classification (measured: standing root = 3.001 > band 3) and the radius-growing kill zone; park both bars together at round start with players spawning on the opposite arc; redress the bars as machine-arm + Neon-energy-edge.

**Spec:** `docs/specs/2026-07-09-soul-sweeper-v2_3-collision-fix-design.md` (read FIRST — root causes + exact decisions).

**Conventions:** as prior plans; suite green after every task (24 files); commit per task.

---

## Task 1: Pure — constant-width `isStruckSwept` + `WorldLayout.arc` (TDD)

**Files:** `src/shared/SweeperModel.luau`, `src/shared/WorldLayout.luau`, `tests/sweeper_model.spec.luau`, `tests/world_layout.spec.luau`

- [ ] **Step 1 (failing tests):** In `tests/sweeper_model.spec.luau`, rewrite the `isStruckSwept` block: beam entries now use `killHalfWidth` (studs) instead of `angularHalfWidth`. Re-base the existing cases (crossed/ahead/airborne-clears/grounded-clears-high/reverse/seam-wrap/re-park-guard/first-tick/radius-band) with `killHalfWidth = 2` at radius 30 (local half-angle ≈ asin(2/30) ≈ 0.0667 — pick body/beam angles accordingly: e.g. "crossed" sweep 0.1→0.5 body 0.3 still works; "first tick instantaneous hit" body angle must be within 0.0667 of the bar, e.g. 0.05; "miss" at 0.5). ADD the constant-width property case:

```lua
	-- Constant-width property: the SAME 1.5-stud offset from the bar kills at every
	-- radius; the ANGULAR offset that equals 1.5 studs at r=15 (0.1 rad) is a MISS at
	-- r=50 (where 0.1 rad = 5 studs > the 2-stud kill half-width).
	local b = { prevAngle = nil, angle = 0, direction = 1, class = "low",
		innerRadius = 6, outerRadius = 52, killHalfWidth = 2 }
	expect(M.isStruckSwept({ radius = 15, angle = 1.5 / 15, airborne = false }, { b }),
		"1.5 studs off at r=15 -> struck")
	expect(M.isStruckSwept({ radius = 50, angle = 1.5 / 50, airborne = false }, { b }),
		"1.5 studs off at r=50 -> struck (constant width)")
	expect(not M.isStruckSwept({ radius = 50, angle = 0.1, airborne = false }, { b }),
		"0.1 rad at r=50 is 5 studs off -> miss (no angular widening)")
```

  In `tests/world_layout.spec.luau`, ADD an `arc` block: count=5 over spread=π centered at π → endpoints at π/2 and 3π/2 radius-exact, middle point at π; count=1 → single center point; even spacing between consecutive points.
- [ ] **Step 2:** Run both spec files → FAIL. **Step 3:** Implement:
  - `SweeperModel.isStruckSwept`: replace `beam.angularHalfWidth` with a derived local pad:

```lua
			-- Constant-width kill zone (spec v2.3 §2-3): the pad is a physical stud
			-- width, converted to an angle AT THIS BODY'S RADIUS -- the same visible
			-- bar width kills identically at the hub and at the rim.
			local halfAngle = math.asin(math.min(1, beam.killHalfWidth / body.radius))
```

    used in both the instantaneous branch (`angularDistance < halfAngle`) and the swept branch (`o <= span + halfAngle or o >= TAU - halfAngle`). Update the doc comment (fields list).
  - `WorldLayout.arc(cx, cz, radius, count, centerAngle, spread)` (match `ring`'s style/return shape):

```lua
-- Evenly spaced points across an ARC of `spread` radians centered on `centerAngle`
-- (count == 1 -> the single center point). Same {x, z} rows as ring().
function WorldLayout.arc(cx, cz, radius, count, centerAngle, spread)
	local pts = {}
	for i = 1, count do
		local t = count == 1 and 0.5 or (i - 1) / (count - 1)
		local a = centerAngle - spread / 2 + spread * t
		pts[i] = { x = cx + radius * math.cos(a), z = cz + radius * math.sin(a) }
	end
	return pts
end
```

- [ ] **Step 4:** Both spec files PASS; full suite green. **Commit** `feat(sweeper-v2.3): constant-width kill zone (pure) + WorldLayout.arc`.

## Task 2: Server — thresholds, formation, spawn arc, beam redress

**Files:** `src/shared/Config.luau`, `src/server/SweeperHazard.luau` (read both fully first)

- [ ] **Step 1 Config:**
  - `SWEEP_AIRBORNE_BAND = 4.5` with comment: *measured 2026-07-09: a standing normalized-R15 root sits 3.001 studs above the surface; 4.5 requires ~1.5 studs of real jump (apex = 10.2). Re-derive if NORMALIZED_SCALES change.*
  - ADD `SWEEP_STAND_BAND_UP = 13` (comment: upper on-platform band — must exceed the jump-apex root height 10.2 so a jumper stays strikeable; the lower band `SWEEP_STAND_BAND` still skips bodies fallen below the surface).
  - REPLACE `SWEEP_BEAM_HALF_WIDTH` with `SWEEP_BEAM_LOW_KILL_HALF = 2.0` and `SWEEP_BEAM_HIGH_KILL_HALF = 3.0` (comment: constant stud half-width of each bar's kill band = visible half-thickness + body/latency pad; tuning knobs).
  - `SWEEP_BEAMS`: high bar `baseAngle = math.pi` → `0` (comment: both bars PARK TOGETHER at angle 0; players spawn on the opposite arc — spec v2.3 §2-4).
  - ADD `SWEEP_SPAWN_CENTER_ANGLE = math.pi` and `SWEEP_SPAWN_ARC = math.rad(140)`.
- [ ] **Step 2 SweeperHazard fixes:**
  - `onPlatform`: `radius` bounds unchanged; vertical becomes `dy >= -Config.SWEEP_STAND_BAND and dy <= Config.SWEEP_STAND_BAND_UP` (comment why asymmetric).
  - `beamsNow` entries: replace `angularHalfWidth = ...` with `killHalfWidth = (rec.beam.class == "low" and Config.SWEEP_BEAM_LOW_KILL_HALF or Config.SWEEP_BEAM_HIGH_KILL_HALF)` (a small `killHalf(class)` helper next to `beamColor` is fine).
  - `spawnCFrame`: `WorldLayout.ring(...)` → `WorldLayout.arc(c.X, c.Z, Config.SWEEP_SPAWN_RADIUS, Config.LOBBY_CAPACITY, Config.SWEEP_SPAWN_CENTER_ANGLE, Config.SWEEP_SPAWN_ARC)`; rest unchanged (clamp + face hub).
- [ ] **Step 3 Beam redress (`buildBeamAssembly`):** keep the ROOT spine exactly as-is (size/pose/hinge/motor — it is the strike-math and wake reference). Replace the cream stripe shells with (all welded, massless, `CanCollide=false`, parented like the old dressing):
  - **LOW bar:** a dark-metal spine housing on TOP of the root (span × 0.6 × 0.8, `Metal`, color `Color3.fromRGB(20, 26, 48)` = SWEEP_PLATFORM_COLOR), an **amber Neon blade strip** along the root's UNDERSIDE (span × 0.35 × 0.9, Neon, SWEEP_BEAM_LOW_COLOR, transparency 0), an end-emitter ball (Neon amber, ~1.6 dia) replacing the old cap, and the hub collar recolored to the platform metal.
  - **HIGH bar:** the root spine gets the platform-metal color (`SmoothPlastic` → `Metal`); a **crimson Neon underglow strip** on its BOTTOM face (span × 0.3 × 2.4, Neon, SWEEP_BEAM_HIGH_COLOR), two **crimson end lamps** (Neon balls ~1.2 dia at the outer tip, stacked or side-by-side), and the collar in platform metal.
  - Root spine colors: low root = SWEEP_BEAM_LOW_COLOR is now on the blade, so the low ROOT becomes platform metal too — both bars read as dark machine arms carrying class-colored energy edges. Keep `beamColor` for the Neon parts only (rename usage accordingly).
  - Comment the section: dressing only — the root's dimensions remain the reference the strike math + wake read.
- [ ] **Step 4:** grep `SWEEP_BEAM_HALF_WIDTH|angularHalfWidth` in `src/` → zero. Suite green. **Commit** `feat(sweeper-v2.3): airborne/band fix, same-side start, arc spawns, machine-arm dressing`.

## Task 3: Docs

**Files:** `CHANGELOG.md`, `docs/smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md`

- [ ] CHANGELOG v2.3 entry (root causes incl. the measured 3.001, both fixes, formation, redress). Smoke doc: v2.3 addendum — re-run matrix for the four vertical-state outcomes (stand-low dies / jump-low lives / stand-high lives / jump-high dies), constant-width check near the rim (die only ~2–3 studs from the bar, not ~8), round-start formation (bars together at one side, players opposite, first bar arrives ~4.5 s), dressing eyeball. **Commit** `docs(sweeper-v2.3): CHANGELOG + smoke additions`.

## Task 4 (CONTROLLER-EXECUTED, MCP): live verification

Re-measure standing dy (3.0) vs new band (4.5) → NOT airborne; parked bars both at measured angle ≈ 0; spawn arc slots clustered around π (probe spawnCFrame outputs via a fresh require is NOT possible — instead verify Config + read slot positions after a round OR compute expected from WorldLayout in the probe VM); dressing parts present (blade/underglow/lamps names); v2.2 regression (non-collidable, motor sign, hex). Record in smoke doc; commit.

## Self-review notes
- Spec §2 → T2 (1,2,4 config/glue), §2-3 → T1+T2, §2-5 → T2 step 3, §3 → T1, §5 → T3/T4.
- Consistency: `killHalfWidth` field name matches pure fn (T1) and beamsNow (T2); `WorldLayout.arc` signature matches spawnCFrame call; root spine untouched so wake/measured-angle unaffected.
