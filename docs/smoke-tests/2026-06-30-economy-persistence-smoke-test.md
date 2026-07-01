# Economy & Persistence — 2-Client Smoke Test (2026-06-30)

Covers the server/client glue that lune can't: `EconomyService`, `ProfileStore`
(DataStore), the `RoundManager` award seam, and `ClientEconomyHud`. Pure logic
(`RewardModel` / `ProgressionModel` / `ProfileModel` / `RewardScreenModel`) is lune-green.

**Setup:** Studio, 2 players (Test → Clients and Servers → 2 players, Start). DataStore
API access must be enabled for the place: **Game Settings → Security → Enable Studio
Access to API Services**. If it is OFF, every DataStore call throws, every player gets a
default profile with `ok=false`, and nothing persists — so confirm it is ON first.

## Checks

1. **Persistent readout on join.** Each client shows a top-left "N Coins / Level L"
   readout immediately after spawn (from `ProfileUpdated`). A brand-new test player
   reads "0 Coins / Level 1". (On join, `ProfileUpdated` fires before any `RewardGranted`.)
2. **Earn on round end.** Play a full round to a winner. Both clients see the centered
   reward panel pop in: `+Coins`, `+XP`, a level line, and a filled level bar. The
   top-left Coins total increases by exactly the panel's `+Coins`. The panel auto-hides
   after ~4.5s (`PANEL_VISIBLE_SECONDS`).
3. **Survival-depth gradient.** The winner's `+Coins`/`+XP` exceeds an early casualty's
   (more swaps survived → more reward). Force quick swaps with `RoundManager.forceSwap()`
   in the command bar to build up `survivedSwaps` if needed.
4. **Level-up callout.** Accumulate XP across rounds (or temporarily lower
   `Config.PROGRESSION_XP_COEFF`) until a level threshold is crossed; the reward panel
   reads "Level Up!  N", shows the green ("win") accent, and the bar resets low.
5. **Persistence across rejoin.** Note a client's Coins total, leave, rejoin → the total
   is restored (saved on `PlayerRemoving`).
6. **No-clobber on failed load.** Temporarily turn OFF API services (or point
   `Config.DATASTORE_NAME` at a throwaway and force a throw); confirm the session still
   plays/earns, the console logs `load failed … will NOT be saved`, and the real saved
   value is untouched after the session ends. Restore the setting afterward.
7. **Shutdown flush.** Earn coins, then stop the server (don't leave first); rejoin a
   fresh server → the earnings persisted (`BindToClose` flushed).
8. **Disconnect mid-round (expected forfeit).** If a player disconnects during the
   Active phase, they get NO `RewardGranted` for that round — their profile was already
   saved + dropped on leave, so `awardRound` no-ops for them. Their pre-round total is
   intact on rejoin. This is expected, not a bug; observe it once so it isn't surprising.

## Direct-trigger shortcuts (command bar, server side)

- Force a reward without playing a whole round (verifies the panel + balance path):
  `require(game.ServerScriptService.Server.EconomyService).awardRound(game.Players:GetPlayers()[1], { survivedSwaps = 1, isWinner = true, participated = true })`
- Inspect a cached profile:
  `print(require(game.ServerScriptService.Server.EconomyService).getProfile(game.Players:GetPlayers()[1]))`

## XP-fill animation checks (2026-07-01)

8. **Smooth fill.** On the reward panel, the XP bar fills smoothly from its prior
   fraction to the new one (not an instant snap), finishing in ~1.2s, and the `+XP`
   number counts up from `+0` to the full amount in step with the bar.
9. **Level-up moment.** Award enough XP to cross a level (lower `Config.PROGRESSION_XP_COEFF`
   temporarily, or use the direct-trigger below with a big XP value): the bar fills to
   full, the panel pops/flashes, the `Level N` label ticks up, the bar resets to empty and
   continues toward the next level. Multiple level-ups chain.
10. **Panel stays long enough.** The panel remains visible through the entire animation
    plus a readable hold (it does not vanish mid-fill).
11. **Re-trigger.** Triggering a second reward while the first is animating cancels the
    first and restarts cleanly (no stuck/garbled bar).

Direct trigger for a big multi-level award (server command bar):
`require(game.ServerScriptService.Server.EconomyService).awardRound(game.Players:GetPlayers()[1], { survivedSwaps = 40, isWinner = true, participated = true })`

## Notes
- Rojo sync can go stale — confirm the place has the latest code (`script_read`) before
  trusting an MCP visual check.
- Keep the test at 2 clients: simultaneous multi-player joins can exhaust the DataStore
  request budget and make loads burn through their retries.
- Confirm the top-left balance panel (≈14px from both edges) doesn't overlap the
  top-center round HUD on narrow viewports.
