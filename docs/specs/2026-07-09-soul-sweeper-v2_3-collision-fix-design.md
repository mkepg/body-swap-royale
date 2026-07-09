# Soul Sweeper v2.3 — Collision Fix, Round-Start Formation, Beam Visual Redesign

**Date:** 2026-07-09
**Status:** 🟡 Spec'd (bug report + directives, root cause verified live; implementation pending)
**Branch:** `feat/soul-sweeper-arena`
**Amends:** the [v2.2 spec](2026-07-09-soul-sweeper-v2_2-touch-elimination-design.md) — vertical-state
classification, kill-zone width, round-start formation, and beam dressing. The touch-elimination
mechanic, swept-interval detection, motors, and dormancy all carry forward.

---

## 1. Bug report (2026-07-09) + verified root causes

**Report:** the HIGH bar eliminates players who are standing still (it shouldn't — standing avoids
it); the LOW bar does NOT eliminate standing players it passes through (it should).

**Root cause 1 (verified live in Studio):** a standing R15 body's root sits at
**3.001 studs** above the surface it stands on — a hair above `SWEEP_AIRBORNE_BAND = 3`. The
server therefore classifies EVERY standing player as *airborne*, which inverts both bars at once:
"airborne" clears the low bar (standing players never die to it) and fails the high bar (standing
players die to it). One threshold, both symptoms. The class logic itself is correct.

**Root cause 2 (found during investigation):** the kill zone is an **angular** half-width
(`SWEEP_BEAM_HALF_WIDTH = 9°`), so its physical width grows with radius — ~2 studs near the hub
but **~8 studs at the rim**: players die visibly before the bar reaches them. A touch-kill bar
must kill in a **constant-width** band matching its visible body.

## 2. Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Airborne threshold | `SWEEP_AIRBORNE_BAND = 4.5` (measured standing root = 3.0; jump apex root = 3.0 + JUMP_HEIGHT 7.2 = 10.2 — 4.5 requires ~1.5 studs of real jump, reached ~instantly at launch; the `SWEEP_AIRBORNE_VY = 8` velocity check already flags the launch frame). Comment records the measured 3.0 so future rig changes re-derive it. |
| 2 | On-platform band | Asymmetric: `dy ∈ [-SWEEP_STAND_BAND (6), +SWEEP_STAND_BAND_UP (13)]`. The old symmetric ±6 skipped a jumping body near apex (root 10.2 > 6) — a player jumping INTO the high bar was unhittable at apex. 13 covers the full jump arc + slack; below −6 still skips (falling into the gap/void). |
| 3 | Constant-width kill zone | Replace angular `SWEEP_BEAM_HALF_WIDTH` with per-class stud half-widths: `SWEEP_BEAM_LOW_KILL_HALF = 2.0`, `SWEEP_BEAM_HIGH_KILL_HALF = 3.0` (visible half-thickness + ~1.5 stud body/latency pad). The pure model converts per body: `localHalfAngle = asin(clamp(killHalf / bodyRadius, 0, 1))` — constant physical width at every radius. Swept-interval logic otherwise unchanged. |
| 4 | Round-start formation | Both bars park on the SAME side: `baseAngle = 0` for BOTH (the high bar moves from π). They still rotate opposite directions at different speeds, so they sweep apart and converge on the far side. Players spawn on the OPPOSITE side: the spawn ring becomes a **140° arc centered at angle π** (r = `SWEEP_SPAWN_RADIUS`), via a new pure `WorldLayout.arc(cx, cz, radius, count, centerAngle, spread)` (lune-tested), slots facing the hub. With base speeds 0.7/0.55 rad/s the first bar reaches the players in ~4.5 s — on top of the 1.5 s round-start grace. |
| 5 | Beam dressing — "machine arm + energy edge" | The bars are kill zones that physically touch nothing, so the visuals say both *machine* and *deadly energy*, in the Soul Turbine vocabulary (dark indigo metal + Neon class colors): **LOW** = slim dark-metal spine carrying an **amber Neon blade strip** along its underside + amber end-emitter orb + hub collar — a glowing cutter line at ankle height that says "hop over me" (and matches the amber wake it leaves). **HIGH** = a chunky dark-metal boom (3 thick) with a **crimson Neon underglow strip** on its bottom face + crimson end lamps + collar — a heavy overhead sweeper that says "danger above: stay grounded". Cream stripes retired. All dressing parts welded to the root spine (massless, non-collidable) as today; the ROOT spine dimensions stay the strike-math reference. |
| 6 | Unchanged | Touch = elimination via the grace-gated chokepoint; swept-interval anti-tunneling; measured-pose angle source; motors + dormancy; wake/chase/rotor cosmetics; round-start grace. |

## 3. Pure model changes

- `SweeperModel.isStruckSwept`: beam entries carry `killHalfWidth` (STUDS) instead of
  `angularHalfWidth`; the function derives the local angular pad per body:
  `halfAngle = math.asin(math.min(1, beam.killHalfWidth / body.radius))` (radius ≥ innerRadius ≥ hub
  keeps it well-defined). Tests updated: constant-width property (same stud offset kills at r=15
  and r=50; the same ANGULAR offset that kills at r=15 misses at r=50), plus the existing
  crossed/ahead/reverse/wrap/guard/first-tick/band/clears cases re-based on stud widths.
- `WorldLayout.arc(cx, cz, radius, count, centerAngle, spread)`: evenly spaced points across the
  arc `[centerAngle - spread/2, centerAngle + spread/2]` (count = 1 → the center point), returning
  `{ {x, z}, ... }` like `ring`. Lune tests: endpoints, center, count-1 degeneracy, spacing.

## 4. Glue changes

- **Config:** `SWEEP_AIRBORNE_BAND = 4.5` (+ measurement comment); add `SWEEP_STAND_BAND_UP = 13`;
  replace `SWEEP_BEAM_HALF_WIDTH` with `SWEEP_BEAM_LOW_KILL_HALF = 2.0` /
  `SWEEP_BEAM_HIGH_KILL_HALF = 3.0`; `SWEEP_BEAMS[2].baseAngle = 0` (high bar starts with the low
  bar); add `SWEEP_SPAWN_ARC = math.rad(140)` + `SWEEP_SPAWN_CENTER_ANGLE = math.pi`.
- **SweeperHazard:** `onPlatform` uses the asymmetric band; `beamsNow` entries carry
  `killHalfWidth` per class; `spawnCFrame` uses `WorldLayout.arc` (count = `LOBBY_CAPACITY`,
  over-cap clamps, faces the hub); `buildBeamAssembly` dressing per §2-5 (root spine unchanged as
  the physics/strike reference; stripes replaced by the metal-housing + Neon-edge dressing).
- **Client:** no changes required (wake reads the root pose; nothing referenced the stripe parts).

## 5. Verification

- **Lune:** updated `isStruckSwept` suite (constant-width property test is the key addition) +
  `WorldLayout.arc` tests; all suites green.
- **Studio MCP (live):** re-measure — standing body `dy = 3.0` < 4.5 → NOT airborne (grounded now
  fails the low bar and clears the high bar, matching intent); parked bars both at angle 0; spawn
  slots clustered around angle π on the far side; dressing renders (amber blade / crimson
  underglow); hex regression; suite of v2.2 checks still green (non-collidable, motor sign).
- **2-client manual:** the smoke doc's v2.2 addendum cases re-run with the fixed thresholds —
  standing under the high bar survives, standing in the low bar dies, jumping clears low, jumping
  into high dies — plus the new round-start formation beat.

## 6. Risks

1. `SWEEP_AIRBORNE_BAND = 4.5` assumes the normalized rig (Config.NORMALIZED_SCALES) keeps the
   standing root at ~3.0 — the comment records the measurement; re-derive if scales change.
2. Kill-pad tuning (`*_KILL_HALF`) is feel work — the 2-client pass owns the final values.
3. Both-bars-same-side start makes the far side briefly safe — intended (the reaction window).
