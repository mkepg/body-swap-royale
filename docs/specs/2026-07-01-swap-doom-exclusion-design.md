# Bug #2 — Pre-Swap Suicide Hand-off: "Swappable = Floor-Beneath" Exclusion

**Date:** 2026-07-01
**Status:** **PROPOSED — NOT IMPLEMENTED.** Author (and reviewer) remain skeptical; this
document exists so the approach can be scrutinized before any code is written. Bug #1
(contact-based tile arming) is being implemented separately this session; Bug #2 is not.
**Related:** [Bug #1 contact-arming](#) (same debugging session), GDD §12 (No-Doom
Assignment, proposed), TDD §2 (No-Doom Assignment Resolution), `GraceModel`, `SwapController`,
`RoundManager` void monitor.

---

## 1. The exploit

Two friends, a live round. Player 1 knows a swap is imminent (the 3s preview highlights
which body each player will inherit, and the HUD counts down to a precise `swapAtServerTime`).
Just before the swap commits, **P1 deliberately jumps off the arena rim.** The swap lands:
P1 is now driving P2's old (safe) body, and **P2 inherits P1's body, which is already
airborne and falling toward the void.** P2 crosses `VOID_Y` a moment later and is eliminated —
despite never having touched the controls. The grace window was supposed to protect the
freshly-swapped player, and it doesn't.

## 2. Root cause (two layers)

**Layer 1 — inherited momentum cancels grace.** The void monitor derives `hasMoved` from
*any* horizontal drift since the swap ([RoundManager.luau](../../src/server/RoundManager.luau) —
`swapPos` delta vs `GRACE_MOVE_EPSILON`). It cannot distinguish "the new controller oriented
themselves" from "the body carries P1's launch velocity." Once the body drifts past the
epsilon, `hasMoved` flips true, and after the 0.5s hard floor `GraceModel.canDieFromHazard`
returns true, so P2 dies.

**Layer 2 (the important one) — timer-only grace cannot rescue a fallen body.** With the
real constants (`VOID_Y = -304`, a rim fall from the top floor ≈ 1.7s, `GRACE_SECONDS = 1.5`),
grace only *delays* the void check. It never moves the body back above `VOID_Y`. The instant
grace expires, a body that is below the arena dies anyway. **The behavior we want — "P2 is
protected" — is architecturally impossible with a timer-only grace.** Protecting P2 requires
either repositioning the doomed body, *not handing it off*, or making the swap timing
unpredictable.

## 3. Rejected approaches

### 3a. Randomized swap timing only (P1's own suggestion)
Keep grace as-is but hide the exact swap moment (random delay after the countdown). This
attacks the *predictability* that lets P1 line up the jump. **Rejected as a sole fix:** it is
probabilistic (a determined griefer still gets lucky), it does nothing for inherited-death
from a non-griefing source (e.g. inheriting a body standing over a tile that erodes mid-preview),
and it sacrifices the deliberately-readable swap cadence (the HUD counts down to a precise
`swapAtServerTime`, which is a feature). May be layered on later as a feel tweak if a residual
timing exploit appears — but it does not close the hole on its own.

### 3b. "Last-safe ground" restore (reposition the doomed body) — REJECTED by the eroding-tile edge
The first serious proposal: each body continuously records its most-recent *grounded* position
(`lastSafe[body]`), and at swap commit any body that is airborne is teleported back to its own
last-safe position (velocity zeroed), reusing the reposition-then-reassert-ownership pattern
already proven in `beginRound` and the disconnect-strand rescue.

**Why it was rejected — the reviewer's edge case:** in an *eroding* arena a remembered
position decays. If P1 arms tile **T**, then times **T** to vanish at the exact swap moment
and hops off, `lastSafe[body]` points at **a hole**. Restoring P2 there simply drops them
through the vanished tile — the exploit survives. **Restoring to a remembered position is not
robust when positions themselves become unsafe.** Any memory-based rescue inherits this flaw.

## 4. Proposed approach — "swappable = floor beneath, before the kill-plane"

**Never hand off a doomed body in the first place — decided by a *current* probe, not memory.**

> At swap commit, a body is **swappable** iff a downward raycast from its root to the arena
> kill-plane (`VOID_Y`), excluding player bodies, hits solid floor. Bodies with **no floor
> beneath them before the void** are **excluded from the derangement** and left with their
> current controller. Sattolo runs over the safe subset only, preserving the bijection.

Additionally, **zero each swapped body's velocity at handoff** so the new controller starts
from rest (matches the "orient after a swap" fantasy) and no inherited momentum carries over —
which also neutralizes Layer 1 without touching the grace model.

### 4a. Why this defeats the reviewer's eroding-tile edge
The key realization: **losing a tile in a stacked arena is not a death.** Hex-A-Gone has 7
solid floors stacked every 50 studs; only a fall off the *lowest* floor (or off the rim past
all floors) reaches `VOID_Y`.

- **P1 arms an *upper*-floor tile T, times it to vanish at T0, hops off.** At T0 the probe from
  P1's body passes *through the hole* and hits the next floor down → **floor beneath → swappable.**
  P2 inherits it, falls one level, lands, survives (+ fresh grace). No void death.
- **P1 does this on the *lowest* floor** (the only floor whose loss means the void) → the probe
  finds nothing before `VOID_Y` → **doomed → excluded → P1 keeps their own void-bound body and
  dies for their own grief.** P2 is never handed it.

Either way the victim is safe, and the griefer only ever hurts themselves. No repositioning,
no memory, no eroded-target problem.

## 5. Genericity & scoping (the multi-arena requirement)

- The "floor beneath before `VOID_Y`" probe is **arena-agnostic**: any arena's floors are solid
  parts; the ray finds them. `VOID_Y` is already a per-arena kill-plane in `Config` and is
  intended to move into `ArenaDescriptor`. **No arena-specific safe-zone tables, no hex knowledge.**
- The probe excludes the player bodies (generic), so it works for any floor geometry.
- Velocity-zero-on-handoff is generic.
- A future arena needs **zero** new code for this rule to hold.

## 6. Interaction with existing systems

- **Preview re-plan:** a player who is safe at preview-start but doomed at T0 folds into the
  existing re-plan path (`planIsCurrent` / recompute over the live roster at commit). The commit
  roster changes from "alive + valid body" to "alive + valid body + currently-safe".
- **Grace model:** unchanged. `hasMoved`/`swapPos` drift logic stays (it still legitimately
  ends grace when the *new* controller walks) but is no longer exploit-load-bearing.
- **Disconnect absorb / logical elimination:** unaffected — excluded (doomed) players simply
  remain alive until the void monitor eliminates them via the normal path.
- **Bijection:** Sattolo over the safe subset (size ≥ 2) is still a derangement. Size 1 or 0 →
  no swap this cycle (existing `< 2` guard).

## 7. Edge-case & exploit sweep

| Scenario | Outcome | Verdict |
|---|---|---|
| Normal mid-jump over solid floor at T0 | Probe hits floor below → swappable (not falsely excluded) | ✅ no false positive |
| Jump off the rim (void-bound) | No floor before `VOID_Y` → excluded → griefer keeps it → griefer dies | ✅ victim safe |
| Upper-floor tile vanishes exactly at T0 | Probe hits next floor down → swappable → P2 falls one level, survives | ✅ reviewer edge handled |
| Lowest-floor tile vanishes exactly at T0 | No floor beneath → excluded → griefer keeps it → griefer dies | ✅ victim safe |
| Inherit a *warning* (about-to-erode) tile | Still solid at T0 → swappable; erodes during P2's grace → P2 drops one level or steps off under grace | ✅ normal gameplay, not a free kill |
| Dodge a bad swap by getting excluded | Requires being void-bound (i.e. dying) → never advantageous | ✅ no incentive |
| Everyone jumps off simultaneously | Swappable set < 2 → no swap → griefers all die → round resolves | ✅ acceptable |
| 2 players, one doomed | Swappable set = 1 → no swap; doomed player dies → other wins | ✅ griefer loses |
| Inherited horizontal momentum after a legit swap | Velocity zeroed at handoff → new controller starts at rest | ✅ Layer 1 closed |

## 8. Testing plan

- **Pure (lune):** a small predicate for the swappable-roster filter — given per-player
  "has floor beneath" flags, assert doomed players are excluded, the plan is computed only over
  the safe subset, and the `< 2` guard holds. `GraceModel` / `HexErosionModel` specs stay green.
- **Studio smoke-test:** the pre-swap-suicide hand-off (rim jump just before a swap → the
  inheritor lands standing, nobody dies unfairly); the upper-floor "vanish at T0" case (inheritor
  falls one level and survives); normal play unaffected (jumps don't cause spurious exclusions).

## 9. Residual skepticism / what could still be wrong

This section exists because the approach is **not yet accepted.** Open concerns to validate
before/while building:

1. **The `VOID_Y`-depth probe cost & correctness at scale.** One ray per alive body per tick,
   up to ~304 studs on the top floor. Cheap (≤16 rays), but confirm it never spuriously hits
   world dressing (should be impossible — dressing is client-side / non-colliding) or another
   body (excluded).
2. **Classification timing vs. the ownership handoff.** The safe/doomed classification happens
   at commit; the `SetNetworkOwner` follows within ms. Confirm no body flips doomed in that
   window in a way that matters (erosion is on ~1.2s timescales, so it shouldn't).
3. **Feel of "no swap this cycle."** When the swappable set drops below 2, a cadence beat passes
   with no swap. Confirm this reads as intentional (griefers dying) and not as a stutter.
4. **Bottom-floor warning-tile inheritance.** P2 inheriting a body on a bottom-floor *warning*
   tile relies on grace + reaction to step off before it goes gone. Confirm grace (0.5s hard +
   up to 1.5s) is enough headroom that P1 cannot reliably engineer a kill; if playtest shows
   otherwise, consider treating "standing on an armed bottom tile with nothing below" as doomed
   (hex-specific — would live in the hazard module, not the generic rule).
5. **Is exclusion the right *feel*?** It punishes the griefer (they die) rather than rescuing
   into a swap. That matches "protect the victim" but differs from a No-Doom *rescue*. Confirm
   this is the desired philosophy.

## 10. Decision status

Proposed. Pending P1's review of this document and a decision on whether to (a) accept the
exclusion approach, (b) revisit a rescue variant that is robust to erosion, or (c) gather
playtest data first. **No implementation until explicitly approved.**
