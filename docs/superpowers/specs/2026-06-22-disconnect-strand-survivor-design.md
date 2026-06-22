# Disconnect-Absorb Survivor Rescue — Design (Bug 2 fix)

**Date:** 2026-06-22
**Status:** Approved — ready for implementation plan
**Related:** TDD §4 "Known Open Issue — disconnect cleanup vs. the ownership model" and the deferred *"disconnect-absorb interaction with eliminated players"* limitation; builds on `RoundManager` / `ControlManager` / `ControlModel` / `BodyManager`.

## Problem

In multi-client play, sometimes the round will not end even though only one player is
clearly left in the arena; if the remaining player then swaps, they become a spectator
of the body they previously occupied instead of being declared the winner.

## Root cause (confirmed)

`ControlModel.removePlayer`'s **absorb** rule is *alive-blind* — it only knows the
*connected* set, not who is alive or which bodies are in play. Failure sequence:

1. Player **B is eliminated** (void). `RoundManager.eliminate` drops B from `alive` but
   leaves the control map untouched; `BodyManager.sendToLobby` parks the body B controls
   on the **balcony**. B keeps controlling it (the intended "eliminated players roam the
   balcony" feature).
2. A still-**alive** player **Q** happens to control B's *avatar* body in the arena
   (normal after derangements).
3. **B disconnects.** The absorb sees Q controlling B's avatar (`own`) and moves Q onto
   `freed` = the body B was controlling = the **parked balcony body**. Q is now alive but
   standing on the balcony, above `VOID_Y`, so the void monitor (which only eliminates
   *alive* players whose body is below `VOID_Y`) can never eliminate them.
4. `RoundState` still counts **2 alive**, so the 1-survivor end condition is never met.
5. The next swap deranges those two "alive" players, handing the genuine arena player the
   balcony body — their camera retargets to it (`ClientControl`), so they find themselves
   on the balcony looking down at their former body: the "spectator" symptom.

The strand requires an **eliminated-but-connected player to disconnect** while an alive
player controls their avatar — common in multi-client Studio testing (closing the client
of a player who just died).

## Scope

**In scope (targeted alive-aware fix)**
- Make `RoundManager`'s disconnect handling alive-aware: when the absorb moves a still-alive
  survivor onto a body that is parked out of play, reposition that body back into the arena
  so the survivor keeps playing and the round can resolve normally.

**Explicitly out of scope (YAGNI / not this fix)**
- Restructuring eliminated players out of the `ControlModel` bijection (root refactor).
- The symmetric, *non-breaking* oddity where an absorb moves an *eliminated* player onto an
  arena body (they roam the arena instead of the balcony). It does not block round end; left
  as-is.
- Any change to `ControlModel` (it stays pure and connection-only; its absorb still yields a
  valid bijection).
- Any new remote or client change (the survivor's camera already follows their controlled
  body via the existing `SetControlledBody`).

## Design

The fix lives entirely in the **server glue** (`RoundManager`, with small additions to
`ControlManager` and `BodyManager`). `ControlModel` is untouched — it deliberately knows
nothing about alive/in-play, and `RoundManager` already coordinates `RoundState` +
`ControlManager` + `BodyManager`.

### 1. Trigger (when to rescue)

In `RoundManager.removePlayer(player)`:
- **Before** removing the player, capture `leaverWasAlive = RoundState.isAlive(model, player)`.
- `ControlManager.removePlayer(player)` is changed to **return its absorb decision** (today
  it returns nothing). The decision already carries `reassign = { player = Q, body = freed }`
  (or `nil`).
- **Rescue condition:** `leaverWasAlive == false` **and** `reassign ~= nil` **and**
  `RoundState.isAlive(model, reassign.player) == true`.

This precisely targets the bug (an eliminated leaver handing a parked body to an alive
survivor) and leaves the normal alive-leaver absorb — already covered by `control_model.spec`
and working in play — completely untouched (no needless teleports).

### 2. Rescue action (reposition the survivor into the arena)

When the rescue condition holds, `RoundManager` brings the survivor's newly-assigned body
back into play:
1. `BodyManager.sendToArena(reassign.body)` — reposition the body to its **avatar-owner's
   arena spawn slot** (resolved from the body's `OwnerUserId` attribute → `arenaSlotByOwner`),
   using the shared `pivotBodyTo` primitive (unanchor → zero velocity → `PivotTo`). Mirrors the
   existing `sendToLobby`, but toward the arena slot.
2. `ControlManager.regrantControl(reassign.player)` — re-assert the survivor's network
   ownership of that body (`SetNetworkOwner` + `SetControlledBody`) **after** the pivot.

**Ownership sequencing rationale:** this reposition-then-re-own order mirrors the proven
`beginRound` sequence (`BodyManager.resetBody` for all, *then* `ControlManager.resetControl`),
so the server teleport replicates reliably onto a client-owned body instead of being fought by
client physics. The survivor's camera follows automatically (CameraSubject is the humanoid),
so they see a quick teleport from the balcony into the arena — no new remote.

### 3. Components / files

- **`src/shared/ControlModel.luau`** — *unchanged.*
- **`src/server/ControlManager.luau`** — `removePlayer` returns the `ControlModel.removePlayer`
  decision; add `regrantControl(player)` (re-applies ownership of the player's current
  controlled body via the existing `applyOwnership`, `isSwap = false`).
- **`src/server/BodyManager.luau`** — add `sendToArena(body)`: resolve the body's avatar-owner
  from its `OwnerUserId` attribute, look up `arenaSlotByOwner[owner]`, and `pivotBodyTo` it
  there. No-op if the owner/slot can't be resolved.
- **`src/server/RoundManager.luau`** — capture `leaverWasAlive`; consume the returned absorb
  decision; apply the rescue (steps 1–2) when the trigger holds.

### 4. Edge cases

- **Leaver controlled their own avatar (`freed == own`):** `ControlModel` returns no reassign;
  rescue does not fire (correct — nobody was displaced).
- **Reassigned player is eliminated (not alive):** rescue does not fire; the eliminated player
  roaming a body is acceptable and does not block round end (out of scope, §Scope).
- **`freed`'s avatar-owner already disconnected / no arena slot:** `sendToArena` is a no-op; the
  survivor remains controllable (worst case still on the balcony) — no crash. Not expected,
  since `freed` is a live body whose owner's avatar still exists.
- **Disconnect ends the round anyway:** an eliminated leaver never changes the alive count, so
  `RoundState.removePlayer` will not end the round here; the rescue keeps the genuine 2-alive
  race intact so it can end normally.

## Testing

- **`ControlModel` unit tests are the bijection guard and remain green** (the module is
  unchanged).
- **Runtime smoke test** — add `docs/smoke-tests/2026-06-22-disconnect-strand-smoke-test.md`,
  a 3-client Studio procedure:
  1. Start a 3-player round; force swaps (`RoundManager.forceSwap()`) until an alive player
     controls another player's avatar body.
  2. Eliminate one player (walk their body into the void) so they sit on the balcony, still
     connected.
  3. Confirm the alive player controlling the *eliminated* player's avatar; then disconnect the
     eliminated client (`game.Players:GetPlayers()[i]:Kick("test")`).
  4. **PASS:** the surviving controller is teleported back into the arena (not stranded on the
     balcony); the round continues as a normal 2-alive race and ends with a declared winner;
     no survivor ends up spectating their old body after a swap.

## Definition of done

- Disconnecting an eliminated-but-connected player never strands an alive survivor on the
  balcony; the round always reaches its 1-survivor end condition.
- `ControlModel` is unchanged and all existing lune specs pass.
- The behavior is confirmed by the new disconnect-strand smoke test.
