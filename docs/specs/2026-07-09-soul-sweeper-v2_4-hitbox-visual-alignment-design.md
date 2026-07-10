# Soul Sweeper v2.4 — Hitbox↔Visual Alignment + Arena Dim Pass

**Date:** 2026-07-09
**Status:** 🟢 Approved (user feel-pass bug report; root causes verified in code; user approved all three parts)
**Branch:** `feat/soul-sweeper-arena`
**Amends:** the [v2.3 spec](2026-07-09-soul-sweeper-v2_3-collision-fix-design.md) — kill-band width
semantics and cosmetic brightness. Touch-elimination, swept-interval detection, measured-pose angle
source, motors, formation, and dormancy all carry forward.

---

## 1. Bug report (2026-07-09 feel pass) + verified root causes

**Report 1:** players are eliminated BEFORE the bar visibly touches them. Requirement: the hitbox
must closely match the visible mesh — a kill only when the bar visibly makes contact.

**Root cause A (static, Config):** the v2.3 kill half-widths were hand-tuned as "visible
half-thickness + ~1.5-stud body/latency pad". The LOW bar's visible body is 1 stud wide but its
kill band is 4 (4×, kill edge leads the blade by 1.5 studs); the HIGH bar's is 3 visible vs 6
(2×, leads by 1.5). A symmetric pad also cannot express latency, which is directional.

**Root cause B (directional, invisible in Config):** the bars are server-owned unanchored physics;
clients render them through Roblox's replication interpolation buffer (~1 monitor tick, order
100 ms). The strike test runs on the AUTHORITATIVE pose, so on screen every kill lands ahead of
the rendered bar — ~2.2 studs at spawn radius at base speed (0.7 rad/s × 32 studs × 0.1 s), up to
~8 studs at the 2.5 rad/s ramp cap. Grows with the ramp; matches "worse than 1.5 studs" feel.

(The swept-interval math itself has no forward prediction — the lead is entirely A + B.)

**Report 2:** the arena is far too bright/distracting; players can't clearly read the bars, the
platform, and other players. There are NO Light instances — the glare is ~140 Neon cosmetic parts
(worst: 48 rim-accent bars at Transparency 0, 36 wake strips flaring to 0.15, 32 chase studs
strobing at 0.1) amplified by the world-wide Bloom 0.9.

## 2. Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Kill band DERIVED from the mesh | Replace `SWEEP_BEAM_LOW/HIGH_KILL_HALF` with pure `SweeperModel.killHalfWidth(thickness, contactPad) = thickness/2 + contactPad`, fed the SAME `SWEEP_BEAM_*_THICKNESS` that sizes the root spine + new `SWEEP_BODY_CONTACT_PAD = 0.5` (half a normalized-R15 torso depth: beam edge meets body edge when facing the bar; broadside limb contact errs slightly LATE by design). Net: low 2.0 → 1.0, high 3.0 → 2.0. Hitbox and mesh cannot drift — one constant sizes both. |
| 2 | Render-lag compensation | Strike-test the sweep window ending `SWEEP_STRIKE_LAG_TICKS = 1` monitor tick (0.1 s) in the PAST: each beam keeps a short measured-angle history; pure `SweeperModel.delayedWindow(history, lagTicks)` returns the (angle, prevAngle) pair to feed `isStruckSwept`, or nil while history is too short (round start / post-re-park — the caller skips the test that tick; round-start grace 1.5 s dwarfs the 0.2 s warm-up). Consecutive delayed windows still tile the circle, so the anti-tunneling guarantee holds. Body state (position/airborne) stays sampled LIVE — a jump timed to the VISIBLE bar evaluates correctly. |
| 3 | Measure, don't guess | `SWEEP_LAG_PROBE` dev flag (like SOLO_TEST_MODE, default false): server stamps the low bar's authoritative angle as an attribute each tick; the client compares against its rendered pose and prints 1 s rolling mean/max lag (rad + studs at r=32). Used live to validate LAG_TICKS = 1; the measured number gets burned into the Config comment. ±half-tick accuracy is enough to size an integer tick count. |
| 4 | Dim pass — only kill tells stay bright | Client dressing transparencies (SweeperController constants): rim accent 0 → 0.55, wake-lit 0.15 → 0.5, chase lit/base 0.1/0.6 → 0.4/0.75, rotors 0.35 → 0.6, shaft 0.7 → 0.8, lenses 0.2 → 0.5. The amber blade / crimson underglow / end emitters (SweeperHazard dressing) stay full-brightness — they are the gameplay tells, and dimming everything else RAISES their contrast. All live values stay below `SWEEP_STANDBY_TRANSPARENCY` 0.85 so dormancy still reads. `WORLD_BLOOM_INTENSITY` untouched (grades the whole broadcast world, not this arena). |
| 5 | Unchanged | Elimination chokepoint + grace; measured-pose angle source; asymmetric stand band; motors, formation, dormancy, wake/chase/rotor mechanics. |

## 3. Pure model changes (lune-tested)

- `SweeperModel.killHalfWidth(thickness, contactPad)` — the derivation formula, pinned by tests
  (low 1+0.5 → 1.0, high 3+0.5 → 2.0, zero-pad identity).
- `SweeperModel.delayedWindow(history, lagTicks)` — window picker over an oldest-first angle
  history: returns `history[n-lag], history[n-lag-1]`; nil when `n-lag < 1` (skip);
  `history[0]` = nil naturally degrades to the model's instantaneous first-tick fallback.
  Tests: lag-1 pick, lag-0 freshest, single-sample instantaneous, too-short nil, empty nil.

## 4. Glue changes

- **Config:** remove `SWEEP_BEAM_LOW_KILL_HALF`/`SWEEP_BEAM_HIGH_KILL_HALF`; add
  `SWEEP_BODY_CONTACT_PAD = 0.5`, `SWEEP_STRIKE_LAG_TICKS = 1` (+ probe-measured comment),
  `SWEEP_LAG_PROBE = false`.
- **SweeperHazard:** `killHalf(class)` = `SweeperModel.killHalfWidth(beamThickness(class), pad)`
  (moved below `beamThickness` — it now depends on it); beam recs carry `angleHist` (ring, capped
  at `LAG_TICKS + 2`); `step()` pushes the measured angle then strike-tests via `delayedWindow`
  (skipping the beam while nil); `stop()` clears `angleHist` (replaces the old `prevAngle = nil`);
  probe: when flagged, stamp `AuthAngle` on the low bar each tick.
- **SweeperController:** dim-pass constant values (§2-4); probe: when flagged, compare `AuthAngle`
  vs rendered atan2 in the existing Heartbeat, print 1 s rolling stats.

## 5. Verification

- **Lune:** new `killHalfWidth` + `delayedWindow` blocks in `tests/sweeper_model.spec.luau`; full
  suite (24 files) green.
- **Studio MCP (live, solo — dev flips on):** probe run → record measured render lag in the
  Config comment; standing kill fires only at visible bar contact (watch low-bar blade reach the
  body before elimination); jump-over and duck-under still work; re-park + round 2 formation
  unaffected (history warm-up); dim look — bars readable, floor/players clear; hex regression
  (rotation-gated, but confirm hex round unaffected); dormant sweeper still dims to 0.85.
- **User feel pass:** final judge of pad, lag ticks, and brightness values.

## 6. Risks

1. `SWEEP_BODY_CONTACT_PAD = 0.5` errs late for broadside contact (~1-stud limb reach) — chosen
   deliberately per "only when it visibly touches"; the knob is one constant if it feels late.
2. LAG_TICKS is integer-granular (100 ms steps); if the probe measures ~50 ms the choice is 0 or
   1 — keep 1 (late-erring) unless the probe reads ≈0.
3. Warm-up skip (first LAG_TICKS+1 ticks after start/stop) is covered by round-start grace; a
   mid-round re-park never happens (stop() only runs at round end).
