# Core Loop Correctness Bundle — Velocity-Zero Handoff + Doom-Exclusion + Authoritative Grace

**Date:** 2026-07-03
**Status:** **APPROVED — ready for planning.**
**Related:** [2026-07-03 Critical Review](../../reviews/2026-07-03-critical-review.md) (§3.3, §2.3, §2.7,
Action List #1–#3), [2026-07-01 Swap Doom-Exclusion](2026-07-01-swap-doom-exclusion-design.md)
(supersedes its "not implemented" status for Layers 1–2), GDD §4–§5 (grace / preview),
TDD §2 (Grace Window Logic, No-Doom Assignment), `GraceModel`, `SwapController`,
`ControlManager`, `RoundManager` void monitor, `SoulController`.

---

## 1. Problem

The moment of a swap handoff is the least-trustworthy moment in the game, and three
distinct defects all live there:

1. **Inherited momentum cancels grace.** The void monitor derives `hasMoved` from *any*
   horizontal drift since the swap ([RoundManager.luau](../../src/server/RoundManager.luau)
   `swapPos` delta). A body that carries its predecessor's launch velocity trips the epsilon
   immediately, so grace ends before the new controller has touched the stick — a real
   correctness gap in *legitimate* swaps, not only under griefing. (Review §2.3.)
2. **Doomed bodies are handed to victims (pre-swap suicide).** A player who knows a swap is
   imminent jumps off the rim just before commit; the inheritor receives an already-falling
   body and dies past `VOID_Y` without ever touching the controls. Timer-only grace is
   *architecturally incapable* of rescuing a below-the-rim body (protection ≠ delay).
   (Bug #2 spec §1–§2; Review Action #2.)
3. **The grace shimmer lies.** `SoulController.playGraceShimmer` approximates the grace window
   from *local input* ([SoulController.luau:101-144](../../src/client/SoulController.luau#L101-L144)),
   while the server ends grace on *horizontal drift*. Inherited momentum ends real grace almost
   immediately while the shimmer keeps pulsing — the player dies visibly shielded, which is
   worse for perceived fairness than no shimmer at all. (Review §2.7.)

These three share one root cause and one fix surface, so they ship together on one branch with
one smoke test. Until they land, **no fairness playtest datapoint is trustworthy** — the grace
tuning would be judged against a grace window that is partly fictional.

**Non-goal:** this bundle does not add movement validation (fly/teleport still survive — that is
Option 2, a separate spec), does not finish the swap preview, and does not stamp grace at round
start. See §7.

---

## 2. Root cause & fix summary

| Defect | Root cause | Fix (this bundle) |
|---|---|---|
| Momentum cancels grace | Body carries predecessor velocity; server infers input from position | **Part A** — zero velocity server-authoritatively at handoff |
| Doomed body handed off | Swap over the full roster ignores whether a body is void-bound | **Part B** — exclude bodies with no floor beneath before `VOID_Y` from the derangement |
| Shimmer desyncs from server | Client re-derives the window from local input | **Part C** — server mirrors its own grace gate to a body attribute; client follows it |

Implementation & review order: **A → B → C.** A shrinks the doom window and makes post-swap
drift genuinely mean "input" before B narrows the remaining case to positional doom. C is
independent but is validated in the same smoke session.

---

## 3. Part A — Velocity-zero at handoff

**Goal:** the new controller always inherits a body at rest; no launch/shove momentum carries
across the swap.

**Why it must be server-authoritative.** The body being handed off is *client-owned*. Writing
`AssemblyLinearVelocity = 0` from the server on a client-owned assembly does not reliably stick —
the owning client's physics simulation overwrites it on its next frame. Velocity must be zeroed
in the brief window where the **server owns the assembly**, i.e. as part of the ownership
transfer itself. This adopts the same `reposition-then-re-own` primitive the review asks to be
made uniform (findings #4/#5).

**Sequence, per swapped body, at commit:**

```
SetNetworkOwner(nil)              -- server takes the body
AssemblyLinearVelocity  = Vector3.zero
AssemblyAngularVelocity = Vector3.zero
SetNetworkOwner(newController)    -- hand to the inheritor, at rest
```

**Where:** `ControlManager` owns the `SetNetworkOwner` call today
([ControlManager.luau:44-52](../../src/server/ControlManager.luau#L44-L52)). Add a
`handoffAtRest(body, newPlayer)` (or fold the zero-velocity step into `applyOwnership`) so the
own→zero→re-own sequence is the single path a swap uses. This is **glue only** — no pure-model
change.

**Interaction with `applyOwnership`'s pcall.** The `SetNetworkOwner` calls stay wrapped, but per
Review Action #5 a failure must `warn` rather than be silently swallowed (an anchored/mid-destroy
root would otherwise leave the model and physics disagreeing). Emitting the warn is in scope for
Part A since we are already editing this call site.

---

## 4. Part B — Doom-exclusion probe

**Rule:**

> At swap commit, a body is **swappable** iff a downward raycast from its root to the arena
> kill-plane (`VOID_Y`), **excluding all player bodies**, hits solid floor. Bodies with **no
> floor beneath them before the void** are **excluded from the derangement** and left with their
> current controller. Sattolo runs over the safe subset only, preserving the bijection.

**Why exclusion, not rescue (settled).** A memory-based "restore to last-safe ground" rescue
breaks on the eroding arena: a remembered position can itself become a hole. A *current-state*
probe is arena-agnostic and robust — losing an upper-floor tile is not a death (7 floors stacked
every 50 studs; only a fall off the *lowest* floor or off the rim reaches `VOID_Y`). Confirmed
empirically in the critical review (§2.4d): through a gone tile, a root→`VOID_Y` ray finds the
next floor at y=−50.

**Pure / glue split** (keeps it lune-testable and arena-agnostic):

- **Glue** (`RoundManager`): compute `hasFloorBeneath(body)` per alive body via one raycast —
  origin = body root, direction = down to `VOID_Y`, `RaycastParams` with `FilterDescendantsInstances`
  excluding **all player bodies** and `RespectCanCollide = true` (so a `CanCollide=false` "gone"
  tile is correctly *not* a floor). No hex knowledge; `VOID_Y` already lives in `Config` and is
  intended to move to `ArenaDescriptor`.
- **Pure** (`SwapController` / small predicate): a `filterSafe(roster, isSafe) → safeRoster`
  step, then the existing `plan(safeRoster)` and the existing `< 2` guard. Number/flag-in →
  roster-out, injected safe-flags, no Roblox types.

**Classification timing:** compute safe/doomed as close to `SetNetworkOwner` as possible (at
commit, inside `commitSwap`), and accept the sub-millisecond race (Bug #2 spec residual #2) —
erosion is on ~1.2 s timescales and cannot flip a body in the commit window.

**Interaction with existing systems** (from Bug #2 spec §6):
- **Preview re-plan (the load-bearing case):** the rim-jump happens *during* the 3 s preview, so a
  player who is in the plan and still alive at commit can nonetheless be doomed. Therefore the
  safe classification must gate the commit **even when the plan is otherwise current** —
  `planIsCurrent` gains a "every planned player is currently-safe" clause, forcing a recompute
  over the safe subset the instant any planned body became void-bound. Skipping this would leave
  the exact exploit open in the exact window it occurs. The commit roster becomes "alive + valid
  body + currently-safe".
- **Grace model:** unchanged. The drift/`hasMoved` logic stays (it still legitimately ends grace
  when the *new* controller walks) but is no longer the exploit-load-bearing protection.
- **Bijection:** Sattolo over the safe subset (size ≥ 2) is still a derangement. Size 1 or 0 →
  no swap this cycle (existing `< 2` guard; coincides with the round ending).

### 4.1 Edge-case & exploit sweep

| Scenario | Outcome | Verdict |
|---|---|---|
| Normal mid-jump over solid floor at T0 | Probe hits floor below → swappable | ✅ no false positive |
| Jump off the rim (void-bound) | No floor before `VOID_Y` → excluded → griefer keeps it → griefer dies | ✅ victim safe |
| Upper-floor tile vanishes exactly at T0 | Probe passes through hole, hits next floor down → swappable → inheritor falls one level, survives | ✅ reviewer edge handled |
| Lowest-floor tile vanishes exactly at T0 | No floor beneath → excluded → griefer keeps it → griefer dies | ✅ victim safe |
| Inherit a *warning* (about-to-erode) tile | Still solid at T0 → swappable; erodes during grace → inheritor drops one level or steps off under grace | ✅ normal gameplay |
| Dodge a bad swap by getting excluded | Requires being void-bound (i.e. dying) → never advantageous | ✅ no incentive |
| Everyone jumps off simultaneously | Swappable set < 2 → no swap → griefers all die → round resolves | ✅ acceptable |
| 2 players, one doomed | Swappable set = 1 → no swap; doomed player dies → other wins | ✅ griefer loses |
| Inherited horizontal momentum after a legit swap | Velocity zeroed at handoff (Part A) → new controller starts at rest | ✅ Layer 1 closed |

---

## 5. Part C — Authoritative grace via boolean body attribute

**Goal:** the shimmer follows the server's real grace gate instead of guessing from local input.

**Server side.** The monitor already computes, per body per tick,
`graceBlocked = not GraceModel.canDieFromHazard(grace, player, t)`
([RoundManager.luau:279](../../src/server/RoundManager.luau#L279)) — this *is* the authoritative
"am I protected right now" signal. Mirror it to a body Attribute named **`GraceProtected`** (bool):

- set `true` in `stampGrace` at commit (before the first monitor tick, so there is no flicker gap);
- in the monitor, write the attribute **on change** to the current `graceBlocked` value (so it
  flips to `false` the tick grace ends — whether by movement clearing `hasMoved`→drift or by the
  window expiring);
- set `false` / clear on elimination and disconnect (grace is already cleared there).

Writing on-change (not every tick) avoids replication spam.

**Client side** (`SoulController`): delete the `os.clock()` timer and the
`InputController.isMoving()` prediction from `playGraceShimmer`. The shimmer now:
- starts when the local controlled body's `GraceProtected` becomes `true`;
- ends when it becomes `false`, via `GetAttributeChangedSignal("GraceProtected")`.

The pulse animation itself is unchanged; only its *lifetime* becomes server-driven. `myBody`
tracking from `SetControlledBody` stays (it still drives halo emphasis); the shimmer simply
decouples its start/stop from the swap event and binds to the attribute instead.

**Cost / fidelity.** Grace-end is quantized to the 10 Hz monitor (~0.1 s) — invisible on a
pulsing highlight. **Zero new remotes** (preserves the zero-C→S posture); the attribute
replicates to all clients, leaving the door open to render *other* players' shields later.

This makes the review's principle literal: cosmetic state is *fed* by authoritative state, not
re-derived.

---

## 6. Testing plan

**Pure (lune):**
- New/extended predicate for the swappable-roster filter (`filterSafe`): given per-player
  `isSafe` flags, assert doomed players are excluded, the plan is computed only over the safe
  subset, and the `< 2` guard holds (safe set of 1 or 0 → no swap, bijection preserved).
- Existing `GraceModel`, `ControlModel`, `SwapController`, `HexErosionModel` suites stay green
  (run the full 18-suite set).

**Studio smoke-test (new doc `docs/smoke-tests/2026-07-03-core-loop-correctness-smoke-test.md`,
needs 2 clients):**
- Pre-swap rim-jump just before a swap → inheritor lands standing, nobody dies unfairly; the
  griefer keeps their own void-bound body and dies.
- Upper-floor tile timed to vanish at T0 → inheritor falls one level and survives.
- Normal jump over solid floor at T0 → *not* excluded (no false positive; swap proceeds).
- Velocity-zero: a legit swap while the predecessor is running → inheritor starts at rest, grace
  is not cut by inherited momentum.
- Authoritative shimmer: the shimmer ends exactly when protection ends (never outlives real
  grace); no die-inside-a-visible-shield.

Server/client glue is not lune-testable (memory: [test-workflow-lune]); the smoke doc is the
acceptance record for the glue, per project convention.

---

## 7. Out of scope (named to prevent creep)

Deferred to their own future specs:
- **Movement validation** (displacement clamp + re-pivot; fly/teleport still survive today) —
  Option 2 / Review Action #6.
- **Swap preview** directional ping + amber danger tint — Option 3 / Review §2.7.
- **Round-start grace stamping** (intro beat) — Review §2.3.
- **Bottom-floor armed-tile-as-doomed** (Bug #2 spec residual #4) — hex-specific, a playtest-data
  call; explicitly *not* folded in now.
- Minimal analytics, coin sink, simultaneous-death tiebreak, `PlayerModule` vendoring,
  RoundManager decomposition.

---

## 8. Definition of done

- Part A: swaps hand off bodies at rest (own→zero→re-own); `SetNetworkOwner` failures `warn`.
- Part B: void-bound bodies are excluded from the derangement via a current-state floor probe;
  pure `filterSafe` predicate lune-tested; edge table (§4.1) holds in smoke.
- Part C: `GraceProtected` attribute mirrors the server gate; client shimmer follows it; the
  local-input prediction is deleted.
- All 18 lune suites pass; the new smoke doc is written and executed at 2 clients.
- GDD §12 / TDD §2 references updated to reflect that Bug #2 Layers 1–2 are now implemented.
