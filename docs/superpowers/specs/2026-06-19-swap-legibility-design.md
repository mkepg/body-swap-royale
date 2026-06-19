# Swap Legibility — Design Spec

**Date:** 2026-06-19
**Status:** Approved (brainstorm) — ready for implementation plan
**Companion docs:** [GDD §4/§5/§6](../../body-swap-royale-gdd.md) · [TDD §1/§2/§3](../../body-swap-royale-tdd.md)
**Builds on:** disappearing-tile hazard, grace window, RoundManager round loop (all merged to main).

---

## 1. Goal

Make the swap **readable end-to-end** so a 2-friend demo round *feels* like Body
Swap Royale instead of a silent control glitch. This piece delivers the two
missing legs of the GDD §12 "fairness validation" trio (grace is shipped):

- **Swap Preview** (GDD §4/§5, feature inventory #2)
- **Free Soul halo** (GDD §5, feature inventory #6)

plus the swap **telegraph + live countdown** (the GDD's "universal dread moment")
and the deferred **grace shield shimmer** visual (TDD §2).

After this ships, the project can run the GDD §12 playtest — *"when a player dies
right after a swap, does it feel fair?"* — which gates the No-Doom and Legacy
Scoring decisions.

### Non-goals (explicitly deferred)

- Directional ping toward the target body, and the amber "near-hazard" danger
  tint on the preview (GDD §5 full preview). Highlight only this pass.
- Floor ring under the body (halo only this pass).
- Premium Soul tiers, trails, swap-in signatures (Alpha).
- Blackout modifier preview suppression (no modifiers in MVP).

---

## 2. Scope (the five deliverables)

1. **Live swap timer** — always-visible countdown during Active (counts the full
   cycle down to the swap: ~27s free-play, then the 3s preview).
2. **Swap telegraph (T−3s)** — orange→red screen flash + large centered 3/2/1 +
   an audio "incoming" cue (Config-driven sound id; silent if unset).
3. **Swap preview** — the server *plans* the derangement at T−3s and tells each
   client the body it will inherit; the client highlights that body; the server
   *commits* that exact permutation at T0. Re-plans if the alive roster changes
   during the 3s window.
4. **Free Soul halo** — an overhead halo on each controlled body, colored by a
   per-player auto-assigned distinct color, re-parenting on every swap. The
   local player's own controlled body's halo is emphasized on their screen.
5. **Grace shield shimmer** — a brief shimmer/pulse on the controlled body during
   the post-swap grace window.

---

## 3. Architecture

Four isolated concerns; the ownership-transfer core and the client animation
driver are untouched. New decision logic goes into pure, Roblox-free,
value-injected modules unit-tested with lune (the `TileFieldModel` / `GraceModel`
/ `ControlModel` pattern); Roblox APIs and real clocks stay in the server/client
glue.

| Concern | Pure module(s) | Glue |
|---------|----------------|------|
| Swap timing / telegraph display | `SwapTelegraphModel` | `ClientSwapHud` |
| Swap preview (plan/commit) | `ControlModel` (extended) | `SwapController`, `ControlManager`, `RoundManager` |
| Soul identity | `SoulPalette` | `ControlManager` (broadcast), `SoulController` |
| Grace shimmer | — (reuses `GraceModel`/`Config`) | `SoulController` |

---

## 4. Pure modules (lune-tested)

### 4.1 `SwapTelegraphModel` (new) — `src/shared/SwapTelegraphModel.luau`

Single source of truth for what the swap HUD shows, as a pure function of time
remaining. No clocks, no Roblox APIs.

```
SwapTelegraphModel.display(secondsUntilSwap, previewSeconds) -> {
    timerText      : string,   -- always-on countdown, e.g. "27" (ceil, clamped >= 0)
    inPreview      : boolean,   -- secondsUntilSwap <= previewSeconds
    bigCountdownInt: number?,   -- 3 / 2 / 1 during preview, else nil
    flashAlpha     : number,    -- 0..1 telegraph intensity ramp (0 outside preview)
}
```

**Tests** (`tests/swap_telegraph_model.spec.luau`): outside preview (no flash, nil
big count); at the preview boundary (`secondsUntilSwap == previewSeconds`); each
integer tick inside preview (3/2/1); at and after the swap (`<= 0` → clamped,
not negative). Time is injected by the caller.

### 4.2 `SoulPalette` (new) — `src/shared/SoulPalette.luau`

Deterministic, distinct color assignment.

```
SoulPalette.colorForIndex(index) -> Color3   -- 1-based; wraps modulo palette size
```

The palette itself lives in `Config.SOUL_PALETTE` (injected, not hardcoded in the
module) so it is a pure index→color map. **Tests** (`tests/soul_palette.spec.luau`):
distinct colors for distinct indices within palette size; deterministic; wraps
predictably past the palette size.

### 4.3 `ControlModel` (extended) — `src/shared/ControlModel.luau`

Add a mutation-free plan step so the previewed swap can be committed unchanged.

```
ControlModel.planSwap(model, orderedPlayers, randint) -> plan
    -- pure: deranges a COPY of the players' current bodies; returns the future
    --       assignment { from = {[player]=fromBody}, to = { {player, body}, ... } }
    --       WITHOUT mutating the model. `from` is the source snapshot the plan
    --       was derived from; `to` is the future control map.

ControlModel.applySwap(model, plan)
    -- writes bodyOf / controllerOf from `plan.to`; mutates the model.

ControlModel.planStillValid(model, plan) -> boolean
    -- pure read: true iff, for the plan's players, the model's CURRENT bodyOf
    --      equals plan.from exactly (same player set, same source bodies). False
    --      if any player left, was added, or had its controlled body change
    --      (e.g. a disconnect-absorb moved a survivor onto a vacated body).
    --      This is the re-plan decision helper.
```

`ControlModel.swap` is reimplemented as `applySwap(model, planSwap(...))` — its
external behavior is unchanged, and the existing `control_model.spec` cases
continue to pass.

**Tests** (extend `tests/control_model.spec.luau`): `planSwap` does not mutate the
model (bijection + maps identical before/after a plan); `applySwap(planSwap(...))`
yields the same post-state as the old `swap`; `planStillValid` true for an
unchanged roster, false when a player is removed, and false after a
disconnect-absorb changes a survivor's body; commit after a roster change still
preserves `bijectionHolds`.

---

## 5. Plan / commit semantics (correctness)

The **commit is always authoritative and always over the current alive roster.**
The persisted plan exists only so the *committed* swap equals the *previewed* one
(otherwise Sattolo would re-randomize and the preview would lie).

Sequence per cycle, inside `RoundManager.runActivePhase`:

1. **Free-play** for `CYCLE_SECONDS − PREVIEW_SECONDS`, polling phase (as today;
   an elimination/disconnect that ends the round breaks out).
2. **Preview** for `PREVIEW_SECONDS`:
   - `plan = SwapController.plan(aliveRoster())`.
   - Fire `SwapPreview(targetBody)` to each player in the plan.
   - While waiting, if the plan goes stale (`planStillValid` false) and ≥2 remain,
     re-plan and re-fire `SwapPreview`. Stay interruptible: if the round leaves
     Active, abort — no commit.
3. **Commit**:
   - Re-validate with `planStillValid`; if stale, recompute over the current
     roster (silent — the window is over).
   - `SwapController.commit(plan)` applies ownership rotation.
   - Open the post-swap grace window and record `swapPos` per player (the
     existing `doSwap` logic moves here, unchanged).
   - Broadcast.

The bijection is never at risk: plan is best-effort UI, commit is correct by
construction. `forceSwap` (smoke-test helper) stays an immediate plan+commit with
no preview.

**Edge cases**
- Roster drops below 2 during preview → round ends; commit aborted; clients clear
  the preview highlight on the `Ended` broadcast.
- Roster change at the last instant (between final re-plan and commit) → commit's
  re-validate recomputes silently; the brief preview was slightly stale (accepted).
- A player previewed a target that then died → handled by re-plan; if it slips to
  commit, the recompute covers it.

---

## 6. Server glue

### 6.1 `SwapController` — `src/server/SwapController.luau`
Expose `plan(roster)` (→ plan, via `ControlManager`) and `commit(plan)` (applies
it). Keep `swap(roster)` as `commit(plan(roster))` for `forceSwap`.

### 6.2 `ControlManager` — `src/server/ControlManager.luau`
- Assign each player a Soul color on `addPlayer` (next free `SoulPalette` index;
  stable for the session).
- Add `planSwap` / `commitSwap` wrappers around the new `ControlModel` calls
  (commit applies ownership + fires `SetControlledBody(isSwap=true)` exactly as
  the current `swap` does).
- Broadcast **`SoulMap`** on every control change (`addPlayer`, `commitSwap`,
  `resetControl`, `removePlayer`-absorb): payload `{ {body=<Model>, color=<Color3>} }`
  built from `controllerOf` + the per-player colors.

### 6.3 `RoundManager` — `src/server/RoundManager.luau`
- Restructure `runActivePhase` into the free-play / preview / commit stages of §5.
- Broadcast `swapAtServerTime` (`workspace:GetServerTimeNow() + secondsUntilSwap`)
  on `RoundStateChanged` at each cycle start, so the client timer is clock-synced
  rather than per-second chatty.
- Move the grace-open + `swapPos` recording into the commit step (logic
  unchanged from today's `doSwap`).

---

## 7. Remotes & Config

### Remotes (`src/shared/Remotes.luau`) — add to `REMOTE_EVENTS`
| Name | Direction | Purpose |
|------|-----------|---------|
| `SwapPreview` | Server → Client (per-client) | The body this player will inherit at the next swap |
| `SoulMap` | Server → all | `{ {body, color} }` for every controlled body |

The swap deadline rides the existing `RoundStateChanged` (new field
`swapAtServerTime`). No per-second traffic.

### Config (`src/shared/Config.luau`) — add
- `SWAP_WARNING_SOUND_ID` (string, `""` → telegraph is silent).
- `SOUL_PALETTE` (array of `Color3`, distinct, mobile-legible).
- `TELEGRAPH_FLASH_COLOR` (`Color3`, warm orange→red base for the flash overlay).

`PREVIEW_SECONDS`, `GRACE_SECONDS`, `GRACE_FLOOR_SECONDS`, `CYCLE_SECONDS` already
exist and are reused.

---

## 8. Client modules

### 8.1 `ClientSwapHud` (new) — `src/client/ClientSwapHud.luau`
Always-visible top-center swap countdown. Each frame computes
`secondsUntilSwap = swapAtServerTime − workspace:GetServerTimeNow()` and renders
via `SwapTelegraphModel.display`: the small timer number always, and during
preview the orange→red flash overlay + large centered 3/2/1 + the audio cue
(played once at preview entry, `SWAP_WARNING_SOUND_ID`; skipped if `""`). Hidden
outside the Active phase. Honors a future "reduce flash intensity" toggle via the
`flashAlpha` ceiling (not built now, but the seam exists).

### 8.2 `SwapPreviewController` (new) — `src/client/SwapPreviewController.luau`
On `SwapPreview(body)`, attach a local `Highlight` (selection outline) to that
body. Clear it on `SetControlledBody` (the commit retarget) or on a
`RoundStateChanged` `Ended`.

### 8.3 `SoulController` (new) — `src/client/SoulController.luau`
- Render a halo (`BillboardGui` above the head) on each body listed in `SoulMap`,
  tinted by that body's controller color; reconcile on each `SoulMap` (add new,
  recolor, remove halos for bodies no longer listed).
- **Self-emphasis:** track the local player's controlled body via
  `SetControlledBody` and render its halo with extra emphasis (brighter / size
  bump / a small marker) so "which one is me" is unmistakable right after the cut.
- **Grace shimmer:** on `SetControlledBody(isSwap=true)`, play a brief shimmer /
  pulse on the now-controlled body, fading on the local player's first movement
  input (the client knows its own input) or after `GRACE_SECONDS`, whichever
  first — approximating the server's grace early-exit. Cosmetic only.

### 8.4 `init.client.luau`
Start `ClientSwapHud`, `SwapPreviewController`, `SoulController` alongside the
existing controllers. `ClientRoundHud` is unchanged (lobby/elimination/winner
text + spectate camera).

---

## 9. Testing

### lune (pure logic)
- `tests/swap_telegraph_model.spec.luau` — §4.1 boundaries.
- `tests/soul_palette.spec.luau` — §4.2 distinctness / determinism / wrap.
- extend `tests/control_model.spec.luau` — §4.3 plan non-mutation, commit
  equivalence, `planMatchesRoster`, bijection after roster-changed commit.

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>`.

### Studio smoke test (new doc `docs/smoke-tests/2026-06-19-swap-legibility-smoke-test.md`)
2-client manual run validating, end to end:
- the always-on timer counts down and the telegraph fires at T−3s with flash +
  3/2/1 + audio (if a sound id is set);
- the previewed highlighted body is the one actually inherited at the swap
  (truthful preview);
- halos appear on both bodies in distinct colors, the local body's is emphasized,
  and halos follow control across a swap;
- the grace shimmer plays right after a swap and fades on first movement;
- **roster-changed-during-preview:** eliminate one player during the 3s window
  (time a void death / `forceSwap`) and confirm the surviving swap still commits a
  valid control map (no orphaned/double control) and the round ends cleanly.

Force a swap with `RoundManager.forceSwap()` from the command bar.

---

## 10. Suggested build order

Each stage is independently demoable and testable:

1. **Timer + telegraph** — `SwapTelegraphModel` (+test), `swapAtServerTime`
   broadcast, `ClientSwapHud`. (No control changes yet.)
2. **Plan/commit + preview** — `ControlModel` plan/commit (+tests),
   `SwapController` / `ControlManager` / `RoundManager` restructure, `SwapPreview`
   remote, `SwapPreviewController`.
3. **Soul halos** — `SoulPalette` (+test), color assignment, `SoulMap` broadcast,
   `SoulController` (halos + self-emphasis).
4. **Grace shimmer** — extend `SoulController`.

---

## 11. Risks / watch-items

- **Preview truthfulness vs. roster churn** — the plan/commit re-validation (§5)
  is the load-bearing correctness mechanism; the lune tests must lock the
  bijection-after-change behavior.
- **Soul halo cost on mobile** — the free halo is a lightweight `BillboardGui`
  (TDD §8 budget); no particles this pass. ≤16 halos is trivial.
- **Clock sync** — using `workspace:GetServerTimeNow()` on both sides keeps the
  client timer honest without per-second remotes; verify the displayed number
  doesn't drift across a long session in the smoke test.
- **Audio asset** — `SWAP_WARNING_SOUND_ID` ships empty (silent) until a sound is
  chosen; the telegraph is fully communicative visually without it (accessibility).
