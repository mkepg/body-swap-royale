# Round-Flow Bookends (Lobby + Results) — Design

**Date:** 2026-06-20
**Status:** Approved — ready for implementation plan
**Related:** GDD §6 (UX), §7 (UI: Lobby UI, End-of-Round UI), TDD §10 MVP scope ("Basic UI (menu, lobby, gameplay, results)"); builds on the existing `RoundStateChanged` round loop.

## Problem

The round loop (`RoundManager`: Lobby → Active → Ended → reset) already declares a
winner and broadcasts everything a UI needs, but the client only renders a single
centered placeholder `TextLabel` (`ClientRoundHud`). There is no real *framing* around
play: the Lobby/waiting state and the end-of-round Result read as debug text.

This piece adds the two **bookends** — a Lobby screen and a Results screen — that frame
the existing in-round HUD, turning the loop into something that feels like a game
session. It is deliberately scoped to those two states.

## Scope

**In scope**
- A Lobby banner (waiting for players / countdown) and a Results banner (winner +
  your outcome + next-round countdown), both over the existing `RoundStateChanged`
  remote.
- A pure, lune-tested presentation model that decides what each banner shows.
- One small server change so the Results "next round in N" is server-truthful.

**Explicitly out of scope (deferred / YAGNI)**
- Main menu / Play gate (the game stays an always-running auto-join loop).
- Lobby player list and map name (minimal lobby chosen).
- Mastery stats / rewards on the Results screen (no such data yet).
- Any new cosmetic/Soul plumbing, new remotes, or new server state for the Lobby.

## Design decisions (from brainstorm)

- **Treatment: keep-arena-visible banner**, not a full-screen takeover. In a body-swap
  game the bodies are the spectacle; a banner lets players watch the winning body on
  the Results screen and the parked bodies during Lobby. (Visual direction B.)
- **Lobby content: minimal** — status line + countdown + an "X / N players" count.
  Leans on the visible parked bodies; avoids adding roster/Soul-color plumbing.
- **Architecture: pure model + thin renderer** (mirrors `SwapTelegraphModel` /
  `GraceModel`), so the presentation decision is Roblox-free and lune-tested.
- **Results countdown: server-tick** — `RoundManager.endRound` ticks the existing
  `secondsRemaining` channel during Ended, keeping the client clock-free (server owns
  clocks).

## Architecture

Three pieces — one new file, one evolved file, one ~6-line server change — all over the
**existing** `RoundStateChanged` remote (no new remotes, no new Lobby server data):

```
RoundManager (server, owns clocks)
   └─ RoundStateChanged { phase, winnerName, secondsRemaining, ... }   (existing remote)
        └─ ClientRoundHud (client renderer)
             ├─ gathers local ctx: localPlayerName, connectedCount, minPlayers
             ├─ RoundScreenModel.display(state, ctx)   (pure decision)
             └─ applies the result to the banner GUI
```

### Component 1 — `src/shared/RoundScreenModel.luau` (new, pure)

Roblox-free, clock-free, no RNG. One function, lune-tested. Mirrors
`SwapTelegraphModel`.

```
RoundScreenModel.display(state, ctx) -> display
```

**Inputs**
- `state` — the `RoundStateChanged` payload; this model reads `phase`, `winnerName`,
  `secondsRemaining` (ignores the swap fields `aliveCount` / `swapAtServerTime`).
- `ctx` — local context the renderer supplies:
  `{ localPlayerName, connectedCount, minPlayers }`.

**Output `display`** — a plain table the renderer applies (no Roblox types):
- `visible` — `false` during **Active** (banner hidden; in-round HUD owns the screen),
  `true` for Lobby/Ended.
- `titleText` — the big line.
- `subtitleText` — the small line under it, or `nil`.
- `bottomText` — the bottom line, or `nil`.
- `winnerName` — the winner's name to show in the fixed `WINNER` label slot, or `nil`
  (only set on Ended when a winner exists; lets the renderer show/hide the mini-label).
- `accent` — a semantic string the renderer maps to a color: `"neutral"`, `"win"`,
  `"lose"`. Keeps `Color3` out of the pure module.

**Decision table**

| phase  | condition                       | titleText                          | subtitleText                    | bottomText                  | winnerName | accent  |
|--------|---------------------------------|------------------------------------|---------------------------------|-----------------------------|------------|---------|
| Lobby  | `secondsRemaining == nil`       | `Waiting for players`              | `{connectedCount} / {minPlayers} players` | —                 | nil        | neutral |
| Lobby  | counting down                   | `Round starting in {secondsRemaining}` | `{connectedCount} / {minPlayers} players` | —             | nil        | neutral |
| Active | —                               | *(visible = false; texts ignored)* | —                               | —                           | nil        | neutral |
| Ended  | `winnerName == localPlayerName` | `Victory`                          | nil                             | `Next round in {secondsRemaining}` | `{winnerName}` | win |
| Ended  | winner exists, ≠ you            | `Defeated`                         | nil                             | `Next round in {secondsRemaining}` | `{winnerName}` | lose |
| Ended  | `winnerName == nil`             | `Round over`                       | nil                             | `Next round in {secondsRemaining}` | nil        | neutral |

Notes:
- On Ended, the big title is the *outcome word* (`Victory` / `Defeated` / `Round over`);
  the winner's **name** is carried separately in `winnerName` for the fixed `WINNER`
  mini-label slot. This matches the approved mockup (small `WINNER` label above a
  prominent name, with a Victory/Defeated tag).
- `bottomText` on Ended is omitted (`nil`) when `secondsRemaining == nil` (defensive:
  if an Ended broadcast arrives without a countdown value, show no stale "in nil").
- All number interpolation uses the integer `secondsRemaining` the server already sends.

### Component 2 — `src/client/ClientRoundHud.luau` (evolved into the banner renderer)

`ClientRoundHud` already owns the round-flow UI: the placeholder text, the `SpectateBody`
camera retarget, and the `EliminationEvent` notice. It becomes the banner renderer:

- **Build once** in `start()`: a `ScreenGui` (`IgnoreGuiInset = true`,
  `ResetOnSpawn = false`) containing:
  - a **top banner** `Frame` (semi-transparent dark background, teal accent stroke)
    holding: a fixed `WINNER` mini-label (visible only when `display.winnerName ~= nil`)
    + the winner-name label, the big `titleText`, and the `subtitleText`;
  - a **bottom line** `TextLabel` for `bottomText`.
  - `TextScaled` on text for mobile; a text stroke for contrast over the banner.
- **On each `RoundStateChanged`:** gather ctx (`localPlayerName` from
  `Players.LocalPlayer.Name`, `connectedCount` from `#Players:GetPlayers()`,
  `minPlayers` from `Config.MIN_PLAYERS_TO_START`), call `RoundScreenModel.display`,
  push texts into labels, toggle the whole GUI's visibility from `display.visible`, and
  map `accent` → `Color3` (neutral grey-blue / `win` teal / `lose` muted red).
- **Preserved (not regressed):**
  - `SpectateBody.OnClientEvent` → camera retarget to a living body (unchanged).
  - `EliminationEvent.OnClientEvent` → a brief "You were eliminated" notice for the
    local player, shown as a transient line that does not fight the banner (during
    Active the banner is hidden, so it has the screen).
- The old single centered placeholder label is removed (replaced by the banner).

`accent` → `Color3` map lives in the renderer (client), not the model.

### Component 3 — `src/server/RoundManager.luau` (small change)

`endRound` currently does one `broadcastState()` then `task.wait(ROUND_END_SECONDS)`.
Replace with a per-second tick (mirroring `runCountdown`) that calls
`broadcastState(remaining)` each second from `Config.ROUND_END_SECONDS` down to 0, so the
Results banner's "Next round in N" is server-truthful and ticks. `broadcastState`
already includes `winnerName` during Ended, so the winner stays shown throughout. No new
fields, no new remote. After the tick, `RoundState.reset` → Lobby as today.

## Testing

- **Lune unit test** — `tests/round_screen_model.spec.luau` covering every decision-table
  row: lobby-waiting, lobby-counting, active-hidden, ended-victory, ended-defeated,
  ended-no-winner, plus `connectedCount`/`minPlayers` string formatting and the
  `bottomText == nil` when `secondsRemaining` is nil on Ended.
  Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec`.
- **Studio smoke test** — new `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md`,
  a 2-client procedure:
  1. With `Config.HAZARDS_ENABLED = false`, both clients see the Lobby banner:
     "Waiting for players" then "Round starting in N", "2 / 2 players".
  2. During Active the banner is hidden (only the in-round swap HUD shows).
  3. Force a finish (eliminate one body / `RoundManager.forceSwap()` harness), confirm
     Results shows the `WINNER` name with **Victory** on the winner's client and
     **Defeated** on the loser's, "Next round in N" ticking, then returns to the Lobby
     banner.

## Edge cases & accessibility

- **Lobby drops below `minPlayers`:** server sends `secondsRemaining = nil` again → model
  reverts to "Waiting for players" (no special client logic).
- **Disconnect-decided round:** winner set but not local → "Defeated" + spectating;
  `winnerName == nil` → "Round over".
- **No Roblox types in the pure model:** `accent` is a string the renderer maps; the
  model is fully lune-clean.
- **Accessibility/mobile:** `TextScaled`, high-contrast text stroke, `IgnoreGuiInset` so
  the top banner clears the notch; outcome is always carried by a word
  ("Victory"/"Defeated"), never color alone.

## Files touched

| File | Change |
|------|--------|
| `src/shared/RoundScreenModel.luau` | **new** — pure presentation decision |
| `src/client/ClientRoundHud.luau` | evolve placeholder text into the banner renderer; keep spectate + elimination notice |
| `src/server/RoundManager.luau` | `endRound` ticks the Ended countdown via `broadcastState` |
| `tests/round_screen_model.spec.luau` | **new** — lune unit test |
| `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md` | **new** — 2-client runtime check |
