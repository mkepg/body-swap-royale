# RoundManager — Design Spec

**Date:** 2026-06-18
**Status:** Approved (design); implementation pending
**Related:** [TDD §1 Server Systems](../../body-swap-royale-tdd.md#1-systems-architecture) (RoundManager / PlayerStateManager), [TDD §2 Swap & Grace Algorithms](../../body-swap-royale-tdd.md#2-swap--grace-algorithms), [TDD §4 Multiplayer Design](../../body-swap-royale-tdd.md#4-multiplayer-design) (bijection requirement), [TDD §10 MVP Scope](../../body-swap-royale-tdd.md#10-development-roadmap), [GDD §4 Win/Lose Conditions](../../body-swap-royale-gdd.md#4-core-gameplay-mechanics). Builds on the pure modules [`RoundState`](2026-06-18-round-state-design.md) and `ControlModel`.

## Purpose

The prototype has a working swap/control/animation/camera stack and now a pure round-lifecycle state machine (`RoundState`), but nothing drives them: the swap loop runs unconditionally and nothing sequences a round or declares a winner. `RoundManager` is the server-side glue that turns the pure pieces into a playable MVP win/lose loop.

It owns the master loop and all real clocks, gates swaps to the Active phase, coordinates `RoundState` (lifecycle) with `ControlModel`/`ControlManager`/`BodyManager`/`SwapController` (the controllers↔bodies bijection and body lifecycle), and drives the **death → eliminate → winner-announcement** path through a minimal void death source.

## Scope

**In scope:**
- A new server glue module `RoundManager` that sequences `Lobby → Active → Ended → reset` on real clocks.
- Gating the periodic swap to the Active phase, with the swap roster sourced from `RoundState`'s alive set.
- A minimal **void** death source (root-height monitor) wired to logical elimination.
- Round-boundary body/control reset (revive-free reposition + control reset to own bodies).
- One new pure `ControlModel` op (`resetControl`) and its lune test.
- New server→client remotes (`RoundStateChanged`, `EliminationEvent`, `SpectateBody`) and a thin client handler (centered text + spectator camera).
- New `Config` constants and a manual 2-client Studio smoke test.

**Out of scope (later steps):**
- The **post-swap grace window** (`CanDieFromHazard`, grace timers, `HasMovedSinceSwap`) — the next step after this spine.
- Telegraphed hazards beyond the void (disappearing tiles, sweeping beams, crushers, etc.).
- Swap preview/warning, the Soul identity system, the real HUD.
- Currency/XP/DataStore rewards.
- Server-side movement validation (anti-cheat).
- Lobby matchmaking, multiple maps, round modifiers.
- GDD §4 simultaneous-death ordering ("most-recently-swapped eliminated first") — `RoundManager` processes eliminations in monitor order; deterministic ordering is deferred.

## Design decisions (resolved during brainstorming)

1. **Spine first, grace deferred.** This spec delivers the smallest unit that still produces a real winner: sequencing + gating + coordination + a void death source. The grace window is a separate follow-up.
2. **`RoundManager` is pure Roblox glue — no new lune module.** All lifecycle decisions already live in `RoundState` (a pure, lune-tested module); the time-driven orchestration lives in glue and is covered by a Studio smoke test, matching the established split.
3. **Swap roster = `RoundState`'s alive set.** Not `SwapController`'s old "controls a living body" filter. This keeps the bodies handed to the derangement exactly equal to the set of alive controllers (TDD §4 bijection requirement); eliminated players' bodies fall out of swaps automatically.
4. **Round reset = revive-free reposition + control reset to own bodies.** At each `beginRound`: reposition every present player's body to its spawn and reset control so everyone starts in their **own** avatar body. Identical, predictable starting state every round.
5. **Elimination is logical, not a Humanoid death.** The void path does **not** set `Humanoid.Health = 0` (dead Roblox Humanoids do not cleanly revive from `Health = Max`). Instead the body is **parked** (anchored aside) and round reset just repositions it — no revive, no model destroyed, bijection intact. A `Humanoid.Died → RoundManager.eliminate` hook is still wired (idempotent) so future health-based hazards get elimination for free; the spine never triggers it.
6. **Client display: minimal text + spectator note.** A thin client handler renders centered text for phase/countdown, elimination, and winner, and retargets the camera of eliminated-but-connected players to a living body. The real HUD remains a separate task.

## Components

| Module | Change | Responsibility |
|--------|--------|----------------|
| **`RoundManager`** (`src/server/RoundManager.luau`, new) | new | Owns the master loop + all clocks. Sequences phases, gates swaps to Active, coordinates `RoundState`/`ControlManager`/`BodyManager`/`SwapController`, runs the void monitor, broadcasts to clients. |
| `RoundState` (`src/shared/RoundState.luau`, pure) | unchanged | Phase / present / alive / winner. Authoritative survivor set. |
| `ControlModel` (`src/shared/ControlModel.luau`, pure) | **+ `resetControl`** | Set `bodyOf := ownerBody` for all present players, rebuild `controllerOf` from scratch. Returns `{ player, body }` array. Bijection-preserving. Lune-tested. |
| `ControlManager` (`src/server/ControlManager.luau`) | + `resetControl` glue | Applies `resetControl` results (re-grant ownership + fire `SetControlledBody`). |
| `SwapController` (`src/server/SwapController.luau`) | **remove `start()` self-driving loop**; keep `swap(orderedAlive)` | Given the alive roster, guard `>= 2`, call `ControlManager.swap`. `RoundManager` decides *when*; `RoundState` decides *who*. |
| `BodyManager` (`src/server/BodyManager.luau`) | + `resetBody(player)` (reposition to spawn), + `parkBody(player)` (move aside, anchored) | Body lifecycle at round boundaries and on elimination. |
| `Config` (`src/shared/Config.luau`) | + `LOBBY_COUNTDOWN_SECONDS`, `ROUND_END_SECONDS`, `VOID_Y` | New tunables. `CYCLE_SECONDS` stays (tunable down for smoke tests). |
| `Remotes` (`src/shared/Remotes.luau`) | + `RoundStateChanged`, `EliminationEvent`, `SpectateBody` | Server→client events. |
| client (`src/client/ClientControl.luau` or new `src/client/ClientRoundHud.luau`) | + handlers | Centered text + spectator camera retarget. |

## New pure op: `ControlModel.resetControl`

```
function ControlModel.resetControl(model)
    -- For every connected player, set the body they control back to their own
    -- avatar body (ownerBody), rebuilding controllerOf from scratch so no stale
    -- entries survive a prior round's mapping.
    -- Returns: array of { player = <player>, body = <ownBody> } for the glue to
    -- re-grant ownership and fire SetControlledBody.
```

Bijection holds after `resetControl` because each present player has a distinct `ownerBody`; `bodyOf[p] = ownerBody[p]` and `controllerOf[ownerBody[p]] = p` is a clean one-to-one map. `controllerOf` is rebuilt from scratch (old entries cleared) so a body that a stranger controlled last round is correctly handed back to its owner.

## Config constants

```
Config.LOBBY_COUNTDOWN_SECONDS = 5   -- pre-round countdown once canStart is true
Config.ROUND_END_SECONDS       = 5   -- winner display window before reset → Lobby
Config.VOID_Y                  = -50 -- a controlled body whose root falls below this is eliminated
```

`CYCLE_SECONDS` (already 30) and `VOID_Y` are lowered temporarily for the smoke test. `Workspace.FallenPartsDestroyHeight` must sit **below** `VOID_Y` (or be left at its low default) so the engine never destroys a parked/falling body before `RoundManager` parks it.

## Master loop (lifecycle & data flow)

**Join** (`onPlayerAdded`, now routed through `RoundManager`):
`BodyManager.createBody` → `ControlManager.addPlayer` (own body, ownership + `SetControlledBody`) → `RoundState.addPlayer`.

**Lobby:**
Wait until `RoundState.canStart`. Then run a `LOBBY_COUNTDOWN_SECONDS` countdown, broadcasting `RoundStateChanged` each tick. If `present` drops below `MIN_PLAYERS_TO_START` mid-countdown, abort back to Lobby (no round begins).

**beginRound:**
`RoundState.beginRound` → roster → `ControlManager.resetControl` (everyone to own body) → `BodyManager.resetBody` for all present (reposition to spawns) → broadcast `RoundStateChanged(Active)` → start the void monitor.

**Active cycle:**
Every `CYCLE_SECONDS`, if `RoundState.aliveCount >= 2`, build the ordered alive roster and call `SwapController.swap(roster)`. `RoundManager` builds the roster by filtering its own set of connected players through `RoundState.isAlive` (no new `RoundState` accessor needed; the already-approved pure module is untouched). Repeat until `RoundState.getPhase()` becomes `Ended` (via an auto-end inside `eliminate`/`removePlayer`). The wait is interruptible so an end mid-cycle is handled promptly.

**eliminate(player)** (single logical entry point; called by the void monitor, and by the `Humanoid.Died` hook for future hazards):
`RoundState.eliminate(player)` → `{ ended, winner }` → `BodyManager.parkBody(player)` → fire `EliminationEvent` → re-send `SpectateBody` (a currently-alive body) to every eliminated-but-connected player. If `ended`, run **Ended** handling. Idempotent: a no-op for a player already not alive.

**Ended:**
Stop the void monitor → broadcast `RoundStateChanged(Ended, winner)` → wait `ROUND_END_SECONDS` → `RoundState.reset()` → loop back to Lobby (which re-begins automatically if still `canStart`).

**Disconnect** (`onPlayerRemoving`):
`RoundState.removePlayer(player)` (lifecycle; may auto-end) **and** `ControlManager.removePlayer(player)` (absorb + destroy own body). If the removal ended the round, run Ended handling.

### Coordination invariant

The swap roster is exactly `RoundState`'s alive set, so the bodies handed to the derangement always equal the set of alive controllers — the bijection the swap relies on (TDD §4) is preserved across eliminations. Eliminated players' bodies are excluded from swaps because those players are no longer in `alive`.

## Death source (void)

A lightweight monitor runs **only while Active**, at ≈10 Hz (`task.wait(0.1)` loop, or a throttled `Heartbeat`). For each alive player, it reads the root position of the body they currently control; if `Y < Config.VOID_Y`, it calls `RoundManager.eliminate(player)`.

The void path never sets `Humanoid.Health = 0`. The eliminated body is parked (anchored aside via `BodyManager.parkBody`) so it stops falling and is not destroyed by `FallenPartsDestroyHeight`; at the next `beginRound` it is repositioned by `resetBody`.

`Humanoid.Died → RoundManager.eliminate` is connected per body as an extensible hook for future health-based hazards. Because the spine never zeroes health, it never fires here; if it ever does, `eliminate`'s idempotence keeps it safe.

## Remotes (server → client)

| Name | Payload | Purpose |
|------|---------|---------|
| `RoundStateChanged` | `{ phase, secondsRemaining?, aliveCount?, winnerName? }` | Phase transitions and countdown ticks. |
| `EliminationEvent` | `playerName` (fired to all) | Drives "You were eliminated" / "<name> eliminated" text. |
| `SpectateBody` | `body` (fired to one eliminated player) | Client points its camera (`CameraSubject`) at this body **without** taking ownership. |

## Client display

A thin handler (in `ClientControl` or a small sibling `ClientRoundHud`) consumes the three remotes:
- `RoundStateChanged` → centered `ScreenGui` text: phase/countdown during Lobby, cleared during Active, and "Winner: <name>" during Ended.
- `EliminationEvent` → brief centered text ("You were eliminated" if it names the local player, else a lighter "<name> eliminated").
- `SpectateBody` → set `CameraSubject` to the named body's Humanoid (spectate only; the body is not owned and is not driven). Re-targeting on each elimination keeps a dead spectator off a corpse.

The real HUD (timer, player count, current-body indicator) stays a separate 🟡 task.

## Testing

**Pure (lune):** add a `resetControl` case to `tests/control_model.spec.luau`:
- after a swap that moves players off their own bodies, `resetControl` returns everyone to their `ownerBody`;
- `ControlModel.bijectionHolds` is true afterward;
- `controllerOf` has no stale entries from the pre-reset mapping.

Run with `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau`.

**Glue (manual 2-client Studio smoke test):** `RoundManager`, the void monitor, and the client display are runtime behavior lune can't reach. Extend the existing disconnect smoke-test pattern:
1. Two clients join → after the lobby countdown, a round starts (both controlling their own bodies, repositioned to spawns).
2. Walk one client's body into the void (`Y < VOID_Y`) → that player is eliminated, their text shows "You were eliminated," and their camera retargets to the surviving body.
3. The surviving player is declared winner; both clients see "Winner: <name>".
4. After `ROUND_END_SECONDS`, the round resets and a second round begins (proving revive-free reposition + `resetControl`).
5. Verify a disconnect mid-round still ends the round correctly with the remaining player as winner.

Temporarily lower `CYCLE_SECONDS` and raise `VOID_Y` for a quick test.

## Files touched

- `src/server/RoundManager.luau` — new glue module (master loop, clocks, void monitor, broadcasts).
- `src/server/init.server.luau` — route `PlayerAdded`/`PlayerRemoving` through `RoundManager`; remove `SwapController.start()`; start `RoundManager`.
- `src/server/SwapController.luau` — remove the self-driving `start()` loop; `swap(orderedAlive)` guards `>= 2` and calls `ControlManager.swap`.
- `src/server/ControlManager.luau` — add `resetControl` glue.
- `src/server/BodyManager.luau` — add `resetBody` (reposition to spawn) and `parkBody` (anchor aside).
- `src/shared/ControlModel.luau` — add the pure `resetControl` op.
- `src/shared/Config.luau` — add `LOBBY_COUNTDOWN_SECONDS`, `ROUND_END_SECONDS`, `VOID_Y`.
- `src/shared/Remotes.luau` — register `RoundStateChanged`, `EliminationEvent`, `SpectateBody`.
- `src/client/ClientControl.luau` (or new `src/client/ClientRoundHud.luau`) — handle the three remotes.
- `tests/control_model.spec.luau` — add the `resetControl` test.
- `CHANGELOG.md` — record the addition under `[Unreleased]`.
- The Studio smoke-test doc — add the round-loop procedure.
