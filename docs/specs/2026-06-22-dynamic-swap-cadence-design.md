# Dynamic Swap Cadence — Design

**Date:** 2026-06-22
**Status:** Approved — ready for implementation plan
**Related:** GDD §3 (gameplay loop / "30-second content cycle"), §4 (Round Structure), §5 (Round Modifiers — Double Speed); TDD §2 (Swap algorithms), §10 MVP scope. Builds on the existing `RoundManager` Active loop and the `RoundStateChanged` swap-deadline broadcast.

## Problem

The swap interval is a fixed `Config.CYCLE_SECONDS = 30`. In play (notably at the
current 2-player test scale) the swap stops feeling like the *core* mechanic: a player
fully settles into a body and weathers ~3–4 tile-hazard cycles before the next swap
fires, so the swap reads as an interruption to survival rather than the heartbeat of the
round. The fixed per-swap overhead (`PREVIEW_SECONDS = 3` + `GRACE_SECONDS = 1.5`) is
only ~15% of a 30s cycle; the other ~25.5s is plain survival in one body.

This piece replaces the fixed cycle with a **dynamic cadence**: the swap interval starts
calm at round-start and compresses toward a frantic endgame, so the back half of every
round is swap-forward and the finale is a swap flurry.

## Scope

**In scope**
- A new pure, lune-tested `CadenceModel` that maps the round's current shape
  (`startCount`, `aliveCount`, `swapsSoFar`) to the next swap interval in seconds.
- A small `RoundManager` change: compute the interval each cycle instead of using a fixed
  constant; track round-scoped `startCount` and `swapsSoFar`.
- `Config` changes: remove `CYCLE_SECONDS`, add the cadence tunables.
- Unit tests (`tests/cadence_model.spec.luau`) and a runtime smoke-test doc.

**Explicitly out of scope (deferred / YAGNI)**
- A HUD "swaps are speeding up!" callout — the shrinking countdown already communicates
  it. Revisit only if a playtest says it's unclear.
- Per-modifier cadence (Double Speed, Blackout, …) — Alpha scope; this model gives them a
  clean hook later.
- Any change to the tile-hazard cadence, the preview duration, or the grace durations.
- Any client-side change — the HUD already counts down to the broadcast deadline.

## Design decisions (from brainstorm)

- **Driver: both combined** — alive-count *and* round progress. Alive-count drives the
  elimination-fueled climax; round progress is a stall-breaker so a round where nobody
  dies still escalates.
- **Combine model: Approach A — normalized lerp, additive blend.** `t = clamp(countT +
  stallWeight * progressT, 0, 1)`, then `interval = lerp(max, min, t)`. Chosen over a
  raw-seconds shave (fuzzy endpoints) and an OR-combine (drivers never stack) because it
  guarantees meaningful endpoints (round opens at `max`, final duel reaches `min`) while
  letting both drivers contribute.
- **Envelope: aggressive, 20s → 8s.** Swap-forward from the first cycle; the 8s floor is
  chosen so the fixed 3s preview + 1.5s grace still fit with ~5s of free play.
- **`stallWeight = 1.0` (carries the N=2 case).** At 2 players nobody is eliminated until
  the round ends, so `countT` is pinned at 0 for the whole round — the alive-count driver
  is inert at the scale currently being tested. A full-weight progress term ensures a
  2-player round still ramps the full 20s → 8s. In larger lobbies the two drivers stack
  toward the floor by the climax (the intended aggressive feel); `clamp` bounds the result.
- **Preview/grace stay fixed.** They are the fairness/legibility guarantees from the
  swap-legibility work; shrinking them to fit a short cycle would quietly undo that.

## Architecture

One new pure module, a contained `RoundManager` edit, and a `Config` swap. No new
remotes, no client change.

```
RoundManager (server, owns clocks + round-scoped startCount/swapsSoFar)
   └─ each Active cycle:
        interval = CadenceModel.interval(startCount, aliveCount, swapsSoFar, opts)
        broadcastState(nil, ServerTimeNow() + interval)   -- existing RoundStateChanged
        waitActive(interval - PREVIEW_SECONDS); preview; commit; swapsSoFar += 1
             └─ ClientRoundHud (unchanged) counts down to the broadcast deadline
```

### Component 1 — `src/shared/CadenceModel.luau` (new, pure)

Roblox-free, no clock, no internal state — a pure function of the round's shape, in the
style of `RoundState` / `GraceModel` / `SoulPalette`. Options are passed in (not read from
`Config`) so tests inject their own.

```
CadenceModel.interval(startCount, aliveCount, swapsSoFar, opts) -> number
  -- opts = { maxInterval, minInterval, swapsToFloor, stallWeight }

  local denom    = math.max(startCount - 2, 1)               -- avoid /0 at startCount == 2
  local countT   = clamp((startCount - aliveCount) / denom, 0, 1)  -- 0 at start … 1 at final duel
  local progressT= math.min(swapsSoFar / opts.swapsToFloor, 1)     -- 0 … 1 over the round
  local t        = clamp(countT + opts.stallWeight * progressT, 0, 1)
  return lerp(opts.maxInterval, opts.minInterval, t)         -- 20 … 8
```

`clamp(x,a,b)` and `lerp(a,b,t)` are local helpers in the module.

**Properties (asserted by tests):**
- Round start (`aliveCount == startCount`, `swapsSoFar == 0`) ⇒ exactly `maxInterval`.
- Final duel with prior eliminations (`countT == 1`) ⇒ exactly `minInterval`.
- Result is always within `[minInterval, maxInterval]` for any inputs (including absurd).
- Non-increasing as `aliveCount` drops and as `swapsSoFar` rises.
- N=2 (`startCount == 2`): `countT` pinned at 0; interval ramps to `minInterval` purely via
  the progress term by `swapsToFloor` swaps.
- Divide-by-zero safety at `startCount == 2`.

### Component 2 — `src/server/RoundManager.luau` (edited)

- `beginRound`: capture `startCount = RoundState.aliveCount(model)` and reset
  `swapsSoFar = 0` (round-scoped module-level state, reset every round).
- `runActivePhase`, at the top of each cycle, replace the two `CYCLE_SECONDS` uses:
  ```
  local interval = CadenceModel.interval(
      startCount, RoundState.aliveCount(model), swapsSoFar, cadenceOpts)
  broadcastState(nil, workspace:GetServerTimeNow() + interval)   -- was line 275
  waitActive(interval - Config.PREVIEW_SECONDS)                  -- was line 278
  ```
  where `cadenceOpts` is built once from `Config` (`{ maxInterval = CADENCE_MAX_INTERVAL,
  minInterval = CADENCE_MIN_INTERVAL, swapsToFloor = CADENCE_SWAPS_TO_FLOOR, stallWeight =
  CADENCE_STALL_WEIGHT }`).
- After a swap successfully commits, `swapsSoFar += 1`.
- `forceSwap` is unchanged (immediate plan+commit, no interval).

### Component 3 — `src/shared/Config.luau` (edited)

- **Remove** `CYCLE_SECONDS` (its only runtime uses are the two lines above).
- **Add:**
  ```
  Config.CADENCE_MAX_INTERVAL = 20   -- round-start ceiling (seconds)
  Config.CADENCE_MIN_INTERVAL = 8    -- endgame floor; MUST stay > PREVIEW_SECONDS
  Config.CADENCE_SWAPS_TO_FLOOR = 8  -- swaps for the stall-breaker to reach the floor
  Config.CADENCE_STALL_WEIGHT = 1.0  -- progress-term weight (carries the N=2 case)
  ```
- Document the `CADENCE_MIN_INTERVAL > PREVIEW_SECONDS` invariant next to the constants.

## Edge cases

- **`startCount == 2`** (the MVP duel): denominator `max(startCount - 2, 1)` dodges
  divide-by-zero; `countT` stays 0; progress carries the ramp.
- **Clamping:** `t ∈ [0,1]`, so the interval never exceeds 20s or drops below 8s — a
  chaotic lobby with many early deaths simply pins at the floor (acceptable / desired).
- **Floor sanity:** `CADENCE_MIN_INTERVAL` must stay `> PREVIEW_SECONDS` so the preview
  window always fits; documented beside the constant.
- **Join-in-progress:** new players wait in the lobby and are not added to the alive set
  mid-round, so `aliveCount ≤ startCount` always holds; `clamp` covers any anomaly anyway.

## Testing

**Unit (lune): `tests/cadence_model.spec.luau`** — the six properties listed under
Component 1: start-returns-max, final-duel-returns-min, always-in-range, monotonic in both
inputs, the N=2 progress-only ramp, and divide-by-zero safety at `startCount == 2`.

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/cadence_model.spec`.

**Runtime smoke test:** add `docs/smoke-tests/2026-06-22-dynamic-cadence-smoke-test.md` —
a 2-client Studio run confirming the HUD countdown visibly shrinks cycle-over-cycle and
the swap fires on the shorter deadline. The doc notes that the old `CYCLE_SECONDS` knob is
gone: fast smoke tests now lower `CADENCE_MAX_INTERVAL` / `CADENCE_MIN_INTERVAL` instead.
Update the existing `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md` reference to
`CYCLE_SECONDS` accordingly.

## Definition of done

- `CadenceModel` exists, is pure, and passes its lune spec.
- `RoundManager` computes the interval each cycle from `CadenceModel`; `CYCLE_SECONDS` is
  gone and the project has no remaining runtime reference to it.
- A round visibly opens slow (~20s) and compresses toward ~8s by the endgame, confirmed by
  the smoke test; the HUD countdown matches the actual swap timing with no client change.
