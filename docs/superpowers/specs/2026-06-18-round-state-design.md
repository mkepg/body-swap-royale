# RoundState — Design Spec

**Date:** 2026-06-18
**Status:** Approved (design); implementation pending
**Related:** [TDD §1 Server Systems](../../body-swap-royale-tdd.md#1-systems-architecture) (RoundManager / PlayerStateManager), [TDD §10 MVP Scope](../../body-swap-royale-tdd.md#10-development-roadmap), [GDD §4 Win/Lose Conditions](../../body-swap-royale-gdd.md#4-core-gameplay-mechanics). Companion to the existing pure module `src/shared/ControlModel.luau`.

## Purpose

The prototype has a working swap/control/animation/camera stack but **no round lifecycle and no way to win or lose** — the swap loop runs unconditionally and nothing tracks who is alive. This is the largest gap to the MVP Definition of Done ("two friends join, play a round with random swaps, orient safely after each swap, see a winner declared, and earn currency").

`RoundState` is the first piece of that gap: a pure, Roblox-free state machine for the round lifecycle (phase + alive set + winner). It is built and unit-tested in isolation before any Roblox wiring, following the pattern established by `ControlModel`.

## Scope

**In scope:** round phase machine, present/alive tracking, winner determination, the player-threshold rules, lune unit tests, and two new `Config` constants.

**Out of scope (later steps):** hazards, the grace window / `CanDieFromHazard`, the Roblox-side RoundManager loop that drives real clocks (`CYCLE_SECONDS`, round-end delay) and calls into this module, currency/DataStore, and any coordination glue between `RoundState` and `ControlModel`.

## Module boundary

`RoundState` is a **separate** pure module from `ControlModel`, matching the existing single-responsibility split:

- `ControlModel` — the controllers↔bodies bijection (spawn / swap / disconnect).
- `RoundState` — the round lifecycle (phase / alive / winner).

`RoundState` knows nothing about bodies or ownership. The server-side glue (a future RoundManager) is responsible for keeping the two in sync — e.g. on elimination it calls `RoundState.eliminate` **and** removes the player from `ControlModel`'s swap pool.

It is **time-agnostic and event-driven**, exactly like `ControlModel`: it holds no clocks and no durations, and advances only on explicit calls. All real timing (the 30s cycle countdown, the round-end delay) lives in the server loop, which calls into `RoundState` at phase boundaries. This keeps the module fully lune-testable with no time mocking.

Opaque keys: player keys are compared with `==`; in production they are `Player` instances, in tests plain strings — identical to `ControlModel`.

## State

`RoundState.new(minToStart, minToContinue)` returns:

```
phase         = "Lobby"     -- "Lobby" | "Active" | "Ended"
present       = {}          -- [player] = true : connected, in the lobby roster
alive         = {}          -- [player] = true : alive in the current Active round
winner        = nil         -- player; set only on a win (alive drops to exactly 1)
minToStart                  -- injected threshold to begin a round
minToContinue               -- injected threshold below which an Active round ends
```

Invariant: `alive ⊆ present` at all times. `winner` is non-nil only when `phase == "Ended"` and the round ended with exactly one survivor.

The server passes the thresholds from new `Config` constants; tests pass literals (mirroring how `ControlModel` injects `randint`).

## Thresholds (Config)

Added to `src/shared/Config.luau`:

```
Config.MIN_PLAYERS_TO_START    = 2   -- need this many present to begin a round
Config.MIN_PLAYERS_TO_CONTINUE = 2   -- an Active round ends when fewer than this remain alive
```

Defaults of 2 keep the MVP playable with two friends now; raising them toward the GDD's 4 / 6 numbers later is a Config change with no logic change. "Continue = 2" means the round ends the instant fewer than 2 players remain alive, so the last one standing wins.

## State machine

```
Lobby  --beginRound (when canStart)-->  Active  --(alive < minToContinue)-->  Ended  --reset-->  Lobby
```

## API

| Function | Behavior | Returns |
|----------|----------|---------|
| `new(minToStart, minToContinue)` | Construct a fresh model in `Lobby`. | model |
| `addPlayer(m, p)` | Add `p` to `present`. A join during `Active` lands in the lobby roster only (spectates this round; eligible next round) — never added to `alive` mid-round. | — |
| `removePlayer(m, p)` | Disconnect: remove `p` from `present` and `alive`. If `Active` and this drops alive below `minToContinue`, auto-end (see win rules). No-op if `p` not present. | `{ ended, winner }` |
| `canStart(m)` | `phase == "Lobby"` and `presentCount >= minToStart`. | boolean |
| `beginRound(m)` | Requires `canStart`. `Lobby → Active`; set `alive` := copy of `present`; clear `winner`. Returns the starting roster as an array so the caller can spawn/assign control. | array of players |
| `eliminate(m, p)` | No-op unless `phase == "Active"` and `p` is alive. Otherwise remove `p` from `alive`; if alive drops below `minToContinue`, auto-end. | `{ ended, winner }` |
| `reset(m)` | `Ended → Lobby`; clear `alive` and `winner`; keep `present` (still-connected players carry to the next round). | — |
| `getPhase(m)` | Current phase. | string |
| `getWinner(m)` | Current winner (or nil). | player \| nil |
| `aliveCount(m)` | Count of `alive`. | number |
| `isAlive(m, p)` | Whether `p` is in `alive`. | boolean |

## Win / edge rules

- **Auto-end at threshold:** when `alive` drops below `minToContinue` (default: to exactly 1), `phase → Ended` and `winner` is set to the single survivor.
- **Drop to 0:** if the alive set reaches 0 (e.g. the last two players disconnect at once), `phase → Ended` with `winner = nil` — the round is aborted and the caller returns to lobby.
- **Terminal Ended:** once `Ended`, further `eliminate` / `removePlayer` are no-ops with respect to phase/winner (no double-declare). `removePlayer` may still drop the player from `present`.
- **Simultaneous deaths** (GDD §4: the most-recently-swapped player is eliminated first) are the **caller's** responsibility to order. `RoundState` processes `eliminate` calls serially in the order given.

## Testing

`tests/round_state.spec.luau`, run with lune in the same plain-assertion style as `tests/control_model.spec.luau`:

1. `canStart` is false below `minToStart`, true at/above it; false outside `Lobby`.
2. `beginRound` snapshots `present` into `alive` and returns the roster; `alive ⊆ present`.
3. `eliminate` down to one survivor → `Ended` with the correct `winner`; the returned `{ ended, winner }` matches.
4. Win via disconnect: `removePlayer` that drops alive to 1 declares the remaining player the winner.
5. Drop to 0 (two simultaneous `removePlayer`s) → `Ended`, `winner == nil`.
6. Post-`Ended` `eliminate` / `removePlayer` are no-ops for phase and winner.
7. `addPlayer` during `Active` adds to `present` but not `alive`.
8. `reset` returns to `Lobby`, clears `alive`/`winner`, keeps still-connected players in `present`.
9. `eliminate` on a non-alive or non-present player, and outside `Active`, is a no-op.
10. `alive ⊆ present` invariant holds across a full Lobby→Active→Ended→reset cycle.

## Files touched

- `src/shared/RoundState.luau` — new pure module.
- `tests/round_state.spec.luau` — new lune test suite.
- `src/shared/Config.luau` — add `MIN_PLAYERS_TO_START`, `MIN_PLAYERS_TO_CONTINUE`.
- `CHANGELOG.md` — record the addition under `[Unreleased]`.
