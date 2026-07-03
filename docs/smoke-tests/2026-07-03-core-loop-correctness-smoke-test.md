# Smoke Test — Core Loop Correctness Bundle (2026-07-03)

**Spec:** docs/superpowers/specs/2026-07-03-core-loop-correctness-design.md
**Needs:** 2 Studio clients (Play Solo cannot exercise a real swap between two players).
**Force a swap:** `RoundManager.forceSwap()` from the server command bar (see
docs/smoke-tests/2026-06-18-round-loop-smoke-test.md).

## Part A — velocity-zero at handoff
1. Start a 2-player round. Have Player 1 sprint/leap so their body carries horizontal
   velocity, then trigger a swap at that instant.
   - **Expect:** the inheritor's new body starts at REST (no slide), and grace is NOT
     immediately cancelled by inherited momentum (shimmer persists ~its full window).

## Part B — doom-exclusion
2. **Rim jump (lowest floor / off the rim):** P1 jumps off the arena into the void just
   before a swap commits.
   - **Expect:** P1 KEEPS their own void-bound body and dies; P2 is NOT handed it and
     stays safe. No unfair inherited death.
3. **Upper-floor tile vanish at T0:** P1 stands on an upper floor, times a tile to erode
   at the swap moment, hops off.
   - **Expect:** the inheritor receives a body that finds the next floor down, falls one
     level, and survives (fresh grace). No void death.
4. **No false positive:** a normal jump over solid floor at the swap instant.
   - **Expect:** the player is NOT excluded; the swap proceeds normally.
5. **Both doomed / only one safe:** both players jump off before a swap.
   - **Expect:** safe set < 2 → no swap this cycle; griefers die; round resolves.

## Part C — authoritative grace shimmer
6. After a swap, watch the inheritor's shield shimmer while moving immediately.
   - **Expect:** the shimmer ends exactly when server protection ends (moving after the
     0.5s hard floor clears it); it NEVER pulses after the player can already die.
7. Inherit a body carrying momentum (Part A fixed) then stand still.
   - **Expect:** shimmer runs its full window; no premature end, no die-inside-shield.

## Regression
8. Normal multi-swap round with legit movement: swaps feel unchanged; halos and
   emphasis still follow control; no console errors.
