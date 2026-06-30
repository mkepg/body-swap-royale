# Animated XP Fill (End-of-Round Reward Panel) — Design Spec

**Date:** 2026-07-01
**Status:** Approved (brainstorm complete)
**Branch:** `feat/economy-persistence` (extends the economy reward panel)
**Builds on:** `2026-06-30-economy-persistence-design.md`

## Goal

Make the end-of-round reward panel's XP bar **animate** instead of snapping. The bar
smoothly fills as XP is awarded; on a level-up it fills to full, plays a pop/flash/level-tick
moment, resets to empty, and continues toward the next level. The `+XP` number counts up in
lockstep. The whole sequence feels smooth, satisfying, and responsive.

## Locked decisions (from brainstorm)

- **Level-up moment:** pop + flash + number tick — bar reaches full, the panel does a quick
  scale-punch with a bright color surge, the `Level N` label increments, the bar snaps to
  empty and continues. No new sourced assets (pure TweenService + HudTheme colors).
- **Pacing:** fixed total fill duration (~1.2s) regardless of XP amount, split across level
  segments proportionally by XP, plus a short ~0.3s pause at each level-up.
- **Labels:** the `+XP` number counts up in sync with the bar; `Level N` ticks at each
  level-up; **Coins render instantly** (XP is the animated focus).

## Architecture & module boundaries

The fill *geometry* (start fraction, each level boundary crossed, end fraction, the XP span
of each segment) is deterministic and Roblox-free — it goes in a **pure, lune-tested module**.
The client only plays tweens. Timing constants live in Config; the pure module carries no
timing or Roblox types.

### New pure module — `src/shared/XpFillModel.luau` (lune-tested)

```
XpFillModel.build(start, deltaXp, opts) -> {
  segments    = { <segment>, ... },  -- ordered; may be empty when nothing animates
  totalSpan   = <number>,            -- sum of segment xpSpan (== clamped delta consumed)
  finalLevel  = <int>,
  finalProgress = <number in [0,1]>,
}
```

- `start = { level, xpIntoLevel, xpForNext }` — the pre-award state. `xpForNext` is the XP
  needed to finish `level` (0 when already at max level).
- `opts = { coeff, exp, maxLevel }` — progression tunables (same ones `ProgressionModel` takes).
- Each **segment** = `{ level, fromProgress, toProgress, xpSpan, levelUpAfter }`:
  - `level` — the level number displayed during this segment.
  - `fromProgress` / `toProgress` — bar fill fraction (0..1) at segment start / end.
  - `xpSpan` — XP represented by this segment (drives proportional duration + the count-up).
  - `levelUpAfter` — `true` when the segment ends by completing the level (a level-up plays
    after it); the next segment starts a fresh level at `fromProgress = 0`.
- The first segment starts at the pre-award fill fraction (`xpIntoLevel/xpForNext`). Subsequent
  segments are fresh levels. The module walks level boundaries using
  `ProgressionModel.xpForLevel(L, opts)` for each crossed level.
- **Clamp at `maxLevel`:** once the final level is `maxLevel`, the bar fills to full and stops
  (excess XP discarded — matches `ProgressionModel` semantics).
- **Degenerate inputs:** `deltaXp <= 0`, or `start.level >= maxLevel`, → `segments = {}`,
  `totalSpan = 0`; the client renders the panel statically (no divide-by-zero).

`XpFillModel` depends only on the pure `ProgressionModel` (pure → pure). It is the single
source of truth for the animation geometry, and the client must not re-derive it.

### Changed: `ClientEconomyHud` becomes the player

`showReward` orchestrates the timeline instead of snapping the bar. It:
1. Renders Coins instantly, sets the bar to the first segment's `fromProgress` and the level
   label to `start.level`, sets `+XP` to `+0 XP`, and pops the panel in (existing `popIn`).
2. Runs a **cancellable** timeline coroutine (token pattern, like the existing `hideToken`):
   - Total fill time `Config.REWARD_XP_FILL_SECONDS` is divided across segments **in
     proportion to each segment's `xpSpan / totalSpan`**. Each segment tweens the fill frame's
     `Size` `fromProgress → toProgress` (linear easing for a steady continuous rate).
   - The `+XP` label counts up `0 → deltaXp` driven by cumulative `xpSpan` consumed (floored,
     formatted `"+N XP"`).
   - At each `levelUpAfter`: panel UIScale `1 → REWARD_LEVELUP_POP_SCALE → 1` (Back easing);
     the bar/panel color surges to `REWARD_LEVELUP_FLASH_COLOR` and back; the `Level N` label
     increments; the bar snaps to empty; hold `Config.REWARD_LEVELUP_PAUSE_SECONDS`.
   - On completion, the bar/level/`+XP` rest exactly on `finalProgress` / `finalLevel` /
     `+deltaXp`.
3. **Auto-hide:** keep the panel visible for `fillTime + (pause × levelUps) +
   Config.REWARD_PANEL_HOLD_SECONDS` (replaces the hardcoded `PANEL_VISIBLE_SECONDS = 4.5`),
   so the window always covers the full animation plus a readable beat on the final state.
4. A newer `RewardGranted` cancels the running timeline (token) and replays from the new start.

`RewardScreenModel` stays responsible for the static decisions it already owns (visibility,
`coinsText`); the animated `+XP`/`Level`/bar are driven by the client + `XpFillModel`. The two
must agree on the final state (they share the same math), so the rest position matches the
authoritative post-award `ProfileUpdated`.

## Data flow + payload change

Add a pre-award snapshot to the `RewardGranted` remote so the client animation is
self-contained and independent of `ProfileUpdated` arrival order:

```
RewardGranted = { coins, xp, leveledUp, before = { level, xpIntoLevel, xpForNext } }
```

`EconomyService.awardRound` already computes the pre-award level (`before` for the `leveledUp`
check). It will capture the full pre-award view via the `ProgressionModel.levelFor` call it
already makes and include `before = { level, xpIntoLevel, xpForNext }` in the payload. No new
remote; `coins`/`xp`/`leveledUp` are unchanged. `ProfileUpdated` is unchanged and still drives
the persistent top-left readout (the source of truth).

Client flow: on `RewardGranted` → `start = grant.before`, `delta = grant.xp`,
`opts` from Config → `XpFillModel.build` → play the timeline.

## Config additions

```lua
-- Animated XP fill (reward panel). Timing only; the geometry is pure (XpFillModel).
Config.REWARD_XP_FILL_SECONDS = 1.2        -- total bar-fill time, any XP amount
Config.REWARD_LEVELUP_PAUSE_SECONDS = 0.3  -- hold at each level-up (pop/flash)
Config.REWARD_PANEL_HOLD_SECONDS = 2.5     -- readable beat after the animation completes
Config.REWARD_LEVELUP_POP_SCALE = 1.08     -- panel scale-punch peak on level-up
Config.REWARD_LEVELUP_FLASH_COLOR = Color3.fromRGB(255, 246, 200) -- bright surge tint
```

## Edge cases

- **No level-up:** one segment; smooth fill; no pause.
- **Zero/negative delta or already max level:** `segments = {}`, `totalSpan = 0`; panel shows
  statically at `start` (bar at `start` fraction, no animation, normal hold).
- **Reaches max level mid-fill:** final segment fills to full and stops; no further segments.
- **Multiple level-ups in one award:** multiple segments + pauses; total ≈ `1.2 + 0.3 × levels`
  (bounded; realistically 0–1 level-ups per round).
- **Re-trigger mid-animation:** token-cancel the old timeline, snap to the new start, replay.

## Testing & verification

- **Lune** (`tests/xp_fill_model.spec.luau`): no-level-up segment geometry (single segment,
  `fromProgress == start fraction`, correct `toProgress`/`xpSpan`, `levelUpAfter == false`);
  exactly-one level-up (segment 1 ends at `1.0` with `levelUpAfter == true`, segment 2 starts
  at `0`); multi-level-up; landing exactly on a level boundary; max-level clamp (fills to full,
  stops); zero/negative delta (empty segments); invariant `sum(xpSpan) == clamped delta` and
  `finalLevel`/`finalProgress` equal `ProgressionModel.levelFor(startTotal + delta)`.
- **Client glue:** Studio MCP visual check + a new check appended to
  `docs/smoke-tests/2026-06-30-economy-persistence-smoke-test.md` (bar fills smoothly, `+XP`
  counts up, level-up pops/flashes/ticks, panel stays up long enough). GUI is not lune-testable.

## Definition of done

- `XpFillModel` implemented and lune-green; `EconomyService.awardRound` sends `before` in
  `RewardGranted`; `ClientEconomyHud` plays the animated fill with the level-up moment and the
  XP count-up; Config timing tunables added.
- Smoke doc updated; a 2-client (or single-client forced-award) pass confirms the feel.

## Out of scope

- Sound stings / particle bursts (deferred; the pop+flash is asset-free).
- Animating the Coins number (XP is the requested focus).
- Any change to the reward formula, persistence, or the persistent HUD readout's behavior.
