# MVP Movement Validation — Design Spec

**Date:** 2026-07-04
**Status:** Approved for planning
**Source:** Critical review 2026-07-03 §3.2 / Action #6 (and the folded-in Actions #4, #5).
**Depends on / reuses:** the shipped Core Loop Correctness bundle — `RoundManager.hasFloorBeneath`
(the doom-exclusion floor probe), the 10 Hz void monitor, and the reposition-then-re-own primitive.

---

## 1. Problem

Movement is client-authoritative (each player network-owns the body they control — the correct,
falsified-alternatives-tested design for feel). The **only** server elimination check is
`root.Position.Y < Config.VOID_Y`, sampled at 10 Hz ([RoundManager.luau:342](../../../src/server/RoundManager.luau#L342)).
Consequences, all reproducible with off-the-shelf Roblox exploit scripts (no game-specific knowledge):

- **Fly / hover:** a body that holds its Y never crosses `VOID_Y` → guaranteed win, every round.
- **Teleport camping:** move the body off-arena (e.g. onto the balcony) → never observed.
- **Speed:** WalkSpeed is effectively a client-owned property; nothing bounds per-tick displacement.
- **Post-elimination interference:** an eliminated player keeps ownership of a balcony body and can
  teleport it back into the arena as a physical griefing actor the round logic no longer watches.

The remote attack surface is otherwise nil (zero client→server remotes), so **the physics-ownership
channel is the entire exploit surface** — which concentrates the fix in one place. The TDD classifies
this "load-bearing from MVP" (§7); it is the first gate before any playtest with untrusted players,
because a broken win condition also pollutes the fairness data such a playtest exists to collect.

## 2. Goals & non-goals

**Goals**
- An exploiter can no longer guarantee survival: fly, teleport, speed, and upward-launch motion are
  all corrected server-side.
- Eliminated bodies cannot be exploited back into the arena.
- **Honest players are never rubber-banded** — including on a laggy connection. This is a hard
  requirement, not a nice-to-have: a false positive both feels awful and pollutes playtests.
- Negligible performance cost; no new loop, no new replication, no new remotes.
- Pure decision logic, lune-tested; arena-agnostic (no hardcoded geometry, all thresholds from `Config`).

**Non-goals (deferred, logged)**
- **Shove-griefing.** Body↔body collision stays ON (deliberate call). A shove moves the victim's body
  via contact, not via the victim's own illegal input, so a displacement clamp cannot distinguish it
  from legitimate crowding. Revisit with playtest data; not solved blind.
- Kick / ban / flagging of cheaters. The response is pure physics correction (rubber-band), no penalty,
  no accusation, no persistent per-player record.
- Reading `Humanoid.WalkSpeed` or other client-owned properties directly — the *symptom* is
  displacement, which the clamp already bounds, so property tampering is covered without trusting the
  property.

## 3. Enforcement model (decided)

**Rubber-band / soft correction.** On a confirmed violation the server re-pivots the body to its last
valid anchor, zeroes velocity, and re-asserts ownership (reposition-then-re-own). No penalty, no memory.
The exploit simply does not work. This matches the project's established philosophy (doom-exclusion
makes griefing *not work* rather than detecting-and-punishing).

**Uniform over every owned body.** The clamp validates *all* controlled bodies each tick — alive and
eliminated alike — establishing one invariant: **every owned body is validated.** This is what contains
eliminated bodies (a teleport back toward the arena snaps to the last valid anchor) with no special
case, no ownership revocation, and no hardcoded balcony volume.

**Lenient + debounce.** Modest per-tick budgets plus a required run of consecutive violating ticks
before any correction. The debounce — not the slack — is what forgives latency: a lag spike arrives as
a single oversized tick (the server loop runs at a fixed 10 Hz regardless of the client's connection),
then the next tick resets the run. Keeping the slack modest matters because the horizontal slack
doubles as the *permitted speed-hack ceiling* (a body moving at `slack ×` walk speed every tick is never
flagged); leaning on debounce for lag lets the ceiling stay tight. An exploiter gets ~0.5 s of illegal
motion before the snap — still unable to win — while honest lag is untouched.

## 4. Architecture — pure / glue split

Mirrors `GraceModel` / `HexErosionModel`: a Roblox-free pure decision module + thin glue on the
existing monitor. The pure module never sees a `Vector3` or an `Instance` — the glue reduces each body
to scalars and asks the model to judge them.

### 4.1 New pure module — `src/shared/MovementValidator.luau`

Scalar-in / decision-out, opaque keys (Instances in production, strings in tests), no clock.

```
MovementValidator.new() -> state          -- { byBody = { [bodyId] = { violations = int } } }

MovementValidator.step(state, bodyId, sample, opts) -> { correct: bool, reason: string? }
    sample = {
        horizDelta,   -- studs moved horizontally since last sample (>= 0)
        vertDelta,    -- signed Y change since last sample
        dt,           -- seconds since last sample
        hasFloor,     -- bool: is there solid floor between the body and the kill-plane?
    }
    opts = {
        walkSpeed, horizontalSlack,      -- horizontal budget = walkSpeed * dt * horizontalSlack
        jumpSpeed, verticalSlack,        -- rise budget       = jumpSpeed * dt * verticalSlack
        minFallEpsilon,                  -- descent tolerance for the anti-hover check
        violationTicks,                  -- debounce: consecutive violating ticks before correct=true
    }

MovementValidator.reseed(state, bodyId)   -- clear the violation counter (server reposition / first sight)
MovementValidator.forget(state, bodyId)   -- drop all state for a destroyed body / departed player
```

**Purity note on `jumpSpeed`:** the launch speed derives from `sqrt(2 * gravity * JumpHeight)`, which
depends on `Workspace.Gravity` (a Roblox value). The glue computes `jumpSpeed` and passes it in; the
pure model only multiplies. This keeps the model Roblox-free and the physics value injected/testable.

### 4.2 Decision rules (inside `step`)

A tick is a **violation** if ANY predicate holds:

1. **Horizontal displacement:** `horizDelta > walkSpeed * dt * horizontalSlack`.
   Catches speed and horizontal teleport. Downward/lateral falling has no horizontal component beyond
   normal, so honest falls pass.
2. **Vertical rise:** `vertDelta > jumpSpeed * dt * verticalSlack`.
   Catches upward teleport / launch / fly-up. Downward motion is unbounded (gravity accelerates a legit
   fall well past this), so falling never trips it.
3. **Anti-hover (fly):** `hasFloor == false` AND `vertDelta > -minFallEpsilon`.
   A body over the void / a hole with no floor beneath it MUST be losing altitude; one that holds or
   *slowly gains* altitude indefinitely is flying. A legitimate jump across an eroded gap, however,
   ascends over the void before it falls — so its ascent + apex ticks also satisfy this predicate. The
   discriminator between a legal gap-jump and an illegal hover is **duration**: a jump arc's
   non-descending phase is bounded by physics (ascent time `= sqrt(2·JumpHeight/gravity)` ≈ 0.27 s ≈ 3
   ticks at defaults), while a fly is unbounded. This is exactly what the debounce captures — so
   `violationTicks` MUST exceed the maximum legal non-descending run (see §5). `minFallEpsilon` only
   tolerates sampling jitter around zero vertical velocity.

**Debounce:** increment `violations[bodyId]` on any violating tick, reset to 0 on a clean tick. Return
`correct = true` only when the counter reaches `violationTicks`, and reset the counter on that return
(so the next illegal run must re-accumulate).

**First sight:** if the glue has no previous sample for a body it cannot compute deltas; it seeds the
anchor and skips `step` that tick (see 4.3). `reseed` guarantees the counter starts clean.

### 4.3 Glue — inside `RoundManager.startMonitor`

The glue holds the only Roblox-typed state, in two per-body tables:

- `lastPos[body]` = the previous tick's root `Vector3` (to compute deltas).
- `validAnchor[body]` = the most recent root `CFrame` that was **clean AND grounded** (`hasFloor==true`).
  This is the rubber-band target. Snapping a hover-cheater to their previous *airborne* position would
  leave them over the void; snapping to the last grounded spot is the honest correction, and it is also
  the right target for a horizontal/speed snap-back.

Per tick, for **every controlled body** with a root (extend the current alive-only sweep to all bodies
via the control map / `BodyManager.getAllBodies`):

1. If no `lastPos[body]`: seed `lastPos` and `validAnchor` to the current pose, `reseed`, continue.
2. Compute `dt = t - lastT` (measured, so a frame hitch doesn't inflate a false violation),
   `horizDelta = horizontal magnitude of (pos - lastPos[body])`, `vertDelta = pos.Y - lastPos[body].Y`,
   `hasFloor = hasFloorBeneath(body)` (reuse verbatim).
3. `decision = MovementValidator.step(state, body, {...}, opts)`.
4. If `decision.correct`: re-pivot to `validAnchor[body]` + zero velocity + re-own (§4.4). Do **not**
   advance `lastPos`/`validAnchor` to the illegal pose (set `lastPos[body] = validAnchor position`).
5. Else: `lastPos[body] = pos`; if `hasFloor` then `validAnchor[body] = body:GetPivot()`.

**Server-reposition reconciliation.** Every server-initiated `PivotTo` (round-start `resetBody`,
round-end `returnToLobby`, elimination `sendToLobby`, disconnect rescue `sendToArena`) moves a body far
in one tick and must never be read as a violation. All four sites are invoked from `RoundManager`; right
after each, the glue clears `lastPos[body]` and calls `MovementValidator.reseed` so the next tick
re-seeds cleanly. The swap handoff does **not** move a body (it only rotates ownership + zeroes
velocity), so no reseed is needed there. New bodies (`createBody` pivots to a lobby slot) are handled by
the first-sight seed in step 1.

**Lifecycle cleanup:** on `removePlayer` / body destruction, `MovementValidator.forget` + drop
`lastPos`/`validAnchor` so the tables never leak across a session.

### 4.4 Correction primitive — folds in Action #4

The correction is exactly the reposition-then-re-own pattern the review asks to make uniform. Expose a
public `BodyManager.pivotTo(body, cf)` (the existing private `pivotBodyTo`: unanchor, zero linear +
angular velocity, `PivotTo`) and, after pivoting to the anchor, call `ControlManager.regrantControl`
(own → retarget) so the teleport replicates onto the client-owned body.

While making this uniform, **fold in Action #4**: `RoundManager.eliminate` currently calls
`BodyManager.sendToLobby` with no subsequent re-own; add `ControlManager.regrantControl` there too, so
the one load-bearing primitive is applied identically everywhere (this is the fast-falling-body case the
review flagged for 2-client confirmation).

## 5. Config additions

```
Config.MOVE_VALIDATION_ENABLED = true     -- dev/test switch (like HAZARDS_ENABLED), NOT a gameplay tunable
Config.MOVE_HORIZONTAL_SLACK   = 2.0      -- x (WALK_SPEED * dt) per-tick budget = the permitted speed-hack
                                          --   ceiling; debounce (not slack) forgives lag, so keep this tight
Config.MOVE_VERTICAL_SLACK     = 1.5      -- x (jumpSpeed * dt) rise budget (a whole legal jump rises < this in one tick)
Config.MOVE_MIN_FALL_EPSILON   = 0.5      -- studs/tick; descent below which a floorless body counts as hovering
Config.MOVE_VIOLATION_TICKS    = 5        -- consecutive violating ticks (~0.5s at 10Hz) before a correction.
                                          --   MUST exceed the max legal non-descending run (a gap-jump's
                                          --   ascent, ~3 ticks at default gravity + JUMP_HEIGHT); 5 leaves margin.
```

`jumpSpeed` is derived at runtime in the glue: `math.sqrt(2 * Workspace.Gravity * Config.JUMP_HEIGHT)`
(≈53 studs/s at defaults → ≈5.3 studs/tick actual jump rise, under the ×1.5 budget ≈ 8 studs/tick).
Horizontal budget at defaults ≈ 16×0.1×2 = 3.2 studs/tick (a sustained >2× speed hack is corrected; a
single lag spike above it is forgiven by debounce). Tune only with playtest data; if `Workspace.Gravity`
or `JUMP_HEIGHT` change, re-check `MOVE_VIOLATION_TICKS` against the ascent-time formula in §4.2.

## 6. Performance

The only added work is **one bounded downward raycast per owned body per tick** (`hasFloorBeneath`,
already used at swap time) — ≤16 × 10 Hz ≈ 160 rays/s — plus scalar math. The review measured the
existing monitor (≤16 spherecasts + 427 tile-phase evals @ 10 Hz) as *trivial*; this is the same order,
on the same existing loop. No Heartbeat work, no new replication, no new remote. Client cost is zero
except the occasional corrective `PivotTo`, which replicates like any swap reposition. **Optimization in
reserve** (not for MVP): skip the deep probe when a body plainly has ground within `HEX_STAND_BAND`,
reusing HazardSystem's per-body contact result.

## 7. Player experience

- **Honest players:** target is invisible. Normal walking/jumping never exceeds the loose budgets for
  `violationTicks` in a row. The chosen lenient+debounce posture exists precisely to guarantee this.
- **False-positive worst case:** a ~one-tile snap that reads like an ordinary lag correction. The smoke
  test must explicitly confirm honest (including artificially-laggy) play is never corrected.
- **Cheaters:** ~0.5 s of illegal motion then snapped back; no kick, no message → no false-accusation
  blowback and no way to win.
- **Eliminated players:** balcony roaming unchanged (the barrier already contains walking); only a
  teleport/fly attempt snaps back.

## 8. Testing

**Pure — `tests/movement_validator.spec.luau` (lune):**
- legal walk within budget → never corrects;
- horizontal teleport (huge `horizDelta`) → corrects after exactly `violationTicks`, not before;
- upward launch (huge `vertDelta`) → corrects;
- hover over void (`hasFloor=false`, `vertDelta≈0`) → corrects after debounce;
- legit fall over a hole (`hasFloor=false`, `vertDelta` strongly negative) → never corrects;
- jump apex over a hole (1 tick `vertDelta≈0`) → forgiven by debounce;
- one-tick lag spike then normal → forgiven (counter resets on the clean tick);
- `reseed` after a large delta → no correction (server reposition path);
- `forget` drops state;
- opaque string keys throughout (no Roblox types).

**Glue — Studio smoke test doc `docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md`:**
command-bar exploit attempts (teleport a body horizontally / straight up; hold Y over an eroded hole)
→ observe rubber-band within ~0.3 s; two-client honest play (walk/jump/fall/ride-a-swap) → never
corrected; eliminated-body teleport toward the arena → contained; round-start / elimination /
between-round repositions → never self-corrected.

## 9. Folded-in review actions

- **#4** — add `ControlManager.regrantControl` after `BodyManager.sendToLobby` in `eliminate`, so the
  reposition-then-re-own pattern is uniform (done as part of §4.4).
- **#5** — `ClientAnimator.register` retry-until-humanoid-appears (the `SetNetworkOwner` warn half of #5
  already shipped in `applyOwnership`). Small, independent client hardening bundled into this branch.

## 10. Out of scope / logged for later

- Shove-griefing (collision stays on) — playtest-gated.
- Deep-probe optimization (§6) — only if 16-player measurement shows it matters.
- Any cheater penalty/telemetry — the response is correction-only by design.
