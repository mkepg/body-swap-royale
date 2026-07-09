# Soul Sweeper v2.2 — Touch Elimination (deterministic beams, physics knockback removed)

**Date:** 2026-07-09
**Status:** 🟡 Spec'd (user-directed redesign; implementation pending)
**Branch:** `feat/soul-sweeper-arena`
**Amends:** the [v2.1 spec](2026-07-09-soul-sweeper-v2_1-jumpclub-refinement-design.md) — beam
CONTACT semantics only. Geometry, motorized rotation (visual), measured-pose angle source,
dormancy, rotation, wake channels, and the true-circle annulus all carry forward.

---

## 1. The problem (playtest, 2026-07-09)

Physics knockback is unreliable in practice: players hit by a bar are sometimes "magically
teleported off the platform." Root cause: the **anti-cheat resist backstop misfires on honest
players** — when the physics shove fails to clear a body from the bar's arc within
`SWEEP_RESIST_TICKS` (easy at 10 Hz with a 9°-half-width bar), the server classifies them as a
resister and hard re-pivots them past the rim. The physics mechanic and its deterministic
backstop fight each other.

**Directive:** stop relying on physics knockback entirely. **A rotating beam instantly
eliminates any player it touches** — deterministic, responsive, identical on every client.

## 2. Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Contact semantics | **Touch = elimination.** A non-grace body caught by a bar (per the class rules below) is eliminated via the existing grace-gated `RoundManager.eliminateFromHazard(player)` chokepoint — the same path as void death. No shove, no re-pivot, no knockback. |
| 2 | Class rules unchanged | Low bar still **jumpable** (airborne clears it); high bar still **duckable-by-standing** (grounded clears it). Touching only kills when the read is failed — the skill stays; only the failure consequence changes (death instead of shove). |
| 3 | Detection | The 10 Hz measured-pose strike math, upgraded with **swept-interval detection**: each tick the pure model tests whether the bar's arc **crossed the body's angle since the previous tick** (`prevAngle → angle` along the spin direction, padded by the half-width), not just instantaneous overlap. No rotation speed can tunnel past a player. Guard: a sweep span > 1 rad (a re-park/teleport jump, not real rotation) falls back to the instantaneous check so a parked-bar snap can never kill half the ring; the first tick after `start()` (no prevAngle) is instantaneous too. |
| 4 | Beams non-collidable | `CanCollide = false` on every assembly part. The bars physically touch nothing; motors keep spinning them (verified-smooth visuals, dormancy braking unchanged). |
| 5 | Machinery DELETED | The resist backstop (`strikeTicks`, `SWEEP_RESIST_TICKS`), validator reseeds (`effects.reseeds`, `SWEEP_RESEED_MARGIN`), the outward re-pivot (`SweeperModel.outwardTarget`, `SWEEP_OFF_MARGIN`, `effects.sweeps`), the `SweptAt` tumble (server stamp + client `watchTumble` + `SWEEP_TUMBLE_SECONDS` + `ClientControl.getBody`), and the **entire collision-group system** (`ensureCollisionGroups`, `SweepBeam`/`GraceBody` groups, `setGraceCollision`/`clearAllGraceCollision` in RoundManager, the floor probe's `GraceBody` ray group — all existed solely for physical beam↔body interaction; with non-collidable beams, `RespectCanCollide` rays ignore bars natively and grace protection is purely the `graceBlocked` strike skip). `SWEEP_BEAM_DENSITY` also retired (density only mattered for contact impulses). |
| 6 | Effects contract v3 | `step(now, samples) -> { eliminations = { player, ... } }`. RoundManager calls `eliminateFromHazard` per entry (grace gate double-checks). Hex returns `{ eliminations = {} }`. |
| 7 | Round-start grace (scope addition, flagged) | With instant kill, a player spawned near a parked bar's angle would die in second one with zero warning. `beginRound` now **stamps the standard grace window for all participants** (existing `stampGrace` machinery — the round-start grace the 2026-07-03 review recommended as "cheap, high-feel"). Side effect on hex: spawn tiles don't arm for the first `GRACE_SECONDS` (1.5 s) — the review considered exactly that desirable. |
| 8 | Death feel | Elimination reuses the existing pipeline (body → balcony, `EliminationEvent` broadcast). No new death flourish in v2.2; polish later if the cut feels abrupt. |

## 3. Pure model changes (`SweeperModel`)

- **Add** `isStruckSwept(body, beams)`: `body = { radius, angle, airborne }`; each beam =
  `{ angle, prevAngle?, direction, class, innerRadius, outerRadius, angularHalfWidth }`.
  Logic per beam: skip if `clears(class, airborne)` or radius outside band. Compute the swept
  span `s = ((angle - prevAngle) * direction) % TAU` (measured convention: `direction = +1`
  means the measured angle increases — the v2.1 `motorTarget` negation guarantees this).
  If `prevAngle` is nil or `s > 1` (re-park jump guard), use the instantaneous
  `angularDistance(bodyAngle, angle) < halfWidth`. Otherwise struck iff the body's offset along
  the spin direction from `prevAngle`, `o = ((bodyAngle - prevAngle) * direction) % TAU`,
  satisfies `o <= s + halfWidth` **or** `o >= TAU - halfWidth` (the trailing pad).
- **Remove** `isStruckAt` (superseded) and `outwardTarget` (+ their test blocks); add a full
  lune block for `isStruckSwept` (both directions, wrap at the seam, span guard, nil prevAngle,
  radius band, clears interplay).

## 4. Glue changes

- **SweeperHazard:** assembly parts `CanCollide = false`, no `CollisionGroup`, no
  `CustomPhysicalProperties`; delete `ensureCollisionGroups`/`strikeTicks`; `step` keeps a
  per-rec `prevAngle`, builds the beams table for `isStruckSwept`, and returns
  `{ eliminations }` (grace-blocked and off-platform samples skipped as today). `stop()` must
  clear stored `prevAngle`s (so the next round's first tick is instantaneous, pairing with the
  span guard).
- **ArenaHazard doc + HexHazard:** effects contract → `{ eliminations = {} }`.
- **RoundManager:** replace the sweeps/reseeds application with
  `for _, p in ipairs(effects.eliminations) do RoundManager.eliminateFromHazard(p) end`;
  delete `setGraceCollision`/`clearAllGraceCollision` + their call sites; revert the floor
  probe's `CollisionGroup = "GraceBody"` line (non-collidable bars are invisible to
  `RespectCanCollide` rays natively); **add round-start grace**: in `beginRound`, after control
  is reset, `stampGrace(<participants>)`.
- **Client:** delete `watchTumble` + the `start(getOwnBody)` parameter; `init.client` passes
  nothing; remove `ClientControl.getBody` (added solely for the tumble). Wake/chase/rotors/
  annulus/dormancy untouched.
- **Config:** delete `SWEEP_OFF_MARGIN`, `SWEEP_RESIST_TICKS`, `SWEEP_RESEED_MARGIN`,
  `SWEEP_TUMBLE_SECONDS`, `SWEEP_BEAM_DENSITY`. Keep `SWEEP_BEAM_MOTOR_TORQUE` (motors remain).

## 5. Fairness & exploit posture

- **Grace:** `graceBlocked` samples are never struck (existing flag) AND `eliminateFromHazard`
  re-checks the grace gate — double protection, zero new machinery. Round-start grace (§2-7)
  covers the spawn beat.
- **Exploits:** the strike is pure server math on server-owned physics state — a client cannot
  resist, spoof, or desync it. The movement validator no longer needs beam-zone exceptions
  (no shove displacements exist); full validator coverage is RESTORED over the whole platform.
- **Doom-exclusion:** unchanged; the swap never hands out a body already below the rim, and
  beams (non-collidable) cannot fake floor for the probe by construction.

## 6. Verification

- **Lune:** `isStruckSwept` suite (§3); all existing suites stay green (24 files — the sweeper
  spec file shrinks by the removed blocks).
- **Studio MCP:** beams non-collidable + groups gone; boot clean; hex regression; swept-interval
  math sanity via live measured angles; elimination-on-touch requires an Active round →
  2-client manual (smoke doc gains the rewritten cases; shove/backstop cases retired).

## 7. Risks

1. **Touch-kill harshness** — by design (user directive). Tuning levers if playtests want
   mercy: narrower `SWEEP_BEAM_HALF_WIDTH`, slower base speeds, longer `GRACE_SECONDS`.
2. **10 Hz sampling vs a sprinting body** — the swept-interval closes the BAR's motion gap;
   a body sprinting across the arc between ticks (~1.6 studs/tick) is far smaller than the
   half-width pad at any radius ≥ 10; accepted.
3. **Round-start grace touches hex** — intended (review-endorsed); called out in CHANGELOG.
