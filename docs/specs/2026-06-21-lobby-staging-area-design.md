# Lobby Staging Area (Elevated Balcony) — Design

**Date:** 2026-06-21
**Status:** Approved — ready for implementation plan
**Related:** GDD §4 (Core Gameplay — round flow), §6 (UX); TDD §4 (Multiplayer / Lobby Structure & Match Lifecycle), §10 MVP scope ("Lobby matchmaking (basic, no skill tiers)"). Builds on the existing `RoundManager` round loop and the round-flow bookends (`RoundScreenModel` / `ClientRoundHud`).

## Problem

The round loop reads as a real session now (Lobby → Active → Ended → reset, with framed banners), but there is **no physical waiting space**. Between rounds, bodies just sit scattered across the arena exactly where the round left them — survivors standing on the spot, eliminated bodies parked (anchored) where they died — on a frozen-solid tile floor. The inter-round wait is "standing around in the dead arena."

This piece adds a real **lobby staging area**: an *elevated balcony* overlooking the arena where players gather between rounds and watch from above, turning the wait into anticipation. It is deliberately scoped to the physical space + the body lifecycle that moves players to/from it; it is **not** matchmaking, ready-up, or any HUD change.

## Scope

**In scope**
- An elevated balcony platform overlooking the arena, with full fall protection (a glass railing on the arena-facing side).
- A pure, lune-tested `SpawnLayout` module that computes both the arena spawn slots (reproducing today's math exactly) and the balcony grid slots.
- A `LobbyArea` server module that builds the balcony geometry once.
- The body lifecycle that places players on the balcony on join and between rounds, and teleports them into the arena at round start.
- A **victory cam**: during the Ended results window, every present player's camera frames the winner standing in the arena below (reuses the existing `SpectateBody` remote).
- **Eliminated players return to the lobby (added 2026-06-21):** on elimination, the body the player was controlling (now out of the round) is sent up to their balcony slot, still under their control — so they walk the balcony and watch the rest of the round from above, rather than leaving a parked corpse in the arena. This replaces the old close-up spectate (camera on a living body).

**Explicitly out of scope (deferred / YAGNI)**
- Matchmaking, skill tiers, ready-up buttons, lobby player list, map/modifier selection.
- Any change to the lobby countdown, the bookend banners, or `RoundScreenModel`.
- A true free-fly **overview** camera (the project has no free-cam code; the `CameraSubject`-on-winner victory cam is the chosen "look at the arena" treatment).
- Decorations / podium / signage (the existing bookend banners carry all messaging).
- Fixing the arena's pre-existing >5-body single-row spawn limitation (noted in `Config.SPAWN_ORIGIN`); arena slots are reproduced unchanged.

## Design decisions (from brainstorm)

- **Approach B — elevated balcony** over a side pad (A) or an in-place zone (C): the elevation gives "look down on the arena" anticipation passively (the third-person own-body camera looks past the body into the pit) and lets the Ended victory cam frame the champion below.
- **Pure `SpawnLayout`** mirrors the project's pure-module pattern (`TileFieldModel`, `GraceModel`, `RoundState`): Roblox-free, number-in/number-out, lune-tested. The current inline arena-slot math in `BodyManager` moves here.
- **Relocation happens at the Lobby transition, not at `endRound` start**, so the Ended beat keeps the winner in the arena for the victory cam; everyone teleports up together afterward.
- **Victory cam reuses `SpectateBody`** — both `SpectateBody` (`ClientRoundHud`) and `SetControlledBody` (`ClientControl`) already set `camera.CameraSubject`, so firing `SpectateBody(winnerBody)` to all present locks every camera on the champion, and the subsequent `resetControl` (`SetControlledBody`) naturally pulls each camera back to the player's own body. No new camera code.
- **Eliminated → lobby relocates the *controlled* body, not the own body (added 2026-06-21).** In the ownership model the player's own avatar is usually driven by a live opponent mid-round, so it can't be moved; the body that *is* free is the one they were controlling (the one that just died, now excluded from `aliveRoster`). Sending that body to the balcony keeps the control map untouched — it's never swapped or void-killed (both gate on aliveness), and round-end `resetControl` reshuffles everyone to own bodies as before. Teleporting it up also catches the fall, so the old anchor-in-place `parkBody` is no longer needed. The close-up spectate (`resendSpectate`/`firstAliveBody`) is removed; `SpectateBody` remains only for the victory cam.
- **No HUD work**: the existing Lobby/Results banners simply play over the gathered balcony instead of the dead arena.

## Architecture

```
RoundManager.start
   ├─ HazardSystem.build()            (existing — builds the arena floor)
   └─ LobbyArea.build()               (new — builds the elevated balcony once)

BodyManager  (uses SpawnLayout for BOTH slot kinds)
   ├─ arenaSlotByOwner[player]        (CFrame — today's spawn slot, unchanged math)
   ├─ lobbySlotByOwner[player]        (CFrame — a balcony grid slot, facing the arena)
   ├─ createBody       → spawns onto the BALCONY slot
   ├─ resetBody        → pivots OWN body to the ARENA slot   (round start)
   ├─ returnToLobby    → pivots OWN body to the BALCONY slot  (round end)
   └─ sendToLobby      → pivots a GIVEN body to the BALCONY slot (elimination)

RoundManager lifecycle
   ├─ beginRound : resetBody → arena, resetControl, hazards start   (unchanged)
   ├─ eliminate  : sendToLobby(controlled body) → balcony, still controlled  (new)
   ├─ endRound (Ended window) : SpectateBody(winnerBody) → all present   (victory cam)
   └─ endRound (→ Lobby reset): returnToLobby(all present), then resetControl
```

### Component 1 — `src/shared/SpawnLayout.luau` (new, pure)

Roblox-free (no `Vector3` / `CFrame` / Roblox globals), no clocks, no RNG. Number-in / number-out; the server glue converts the returned offsets into `CFrame`s. Lune-tested.

Proposed surface (final names may be refined in the plan, but the contract is):

```
-- Arena: reproduce today's exact row math. Body index is 1-based.
-- Returns the world position components for body `index`.
SpawnLayout.arenaSlot(index, originX, originY, originZ, spacing) -> x, y, z

-- Balcony: a centered grid. `index` 1-based; `perRow` columns; `spacing` studs.
-- Returns offsets from the balcony origin (server adds origin + facing).
SpawnLayout.lobbySlot(index, perRow, spacing) -> dx, dz
```

**`arenaSlot` contract (must not regress):** with `originX,originY,originZ = SPAWN_ORIGIN.X/Y/Z` and `spacing = SPAWN_SPACING`, body `index` lands at `x = originX + (index-1)*spacing`, `y = originY`, `z = originZ`. This reproduces today's positions exactly (X = −4, 4, 12, 20, 28 …; tile-center invariant preserved). It is a pure extraction of the inline math now in `BodyManager.createBody`.

**`lobbySlot` contract:** lays body `index` into a `perRow`-wide grid centered on (0,0): rows fill front-to-back, columns left-to-right, centered so the grid straddles the origin. Slots are distinct, non-overlapping (spacing > body width), and for `index ∈ [1, perRow*maxRows]` stay within the balcony footprint. The server adds `LOBBY_ORIGIN` and orients each slot to face the arena.

### Component 2 — `src/server/LobbyArea.luau` (new, server)

Mirrors `HazardSystem.build()`: constructs the balcony geometry **once**, parented under a named folder in `workspace` (e.g. `workspace.LobbyArea`). Idempotent (rebuild guard like `BodyManager.ensureFolder`).

Geometry (all values are `Config` tunables; numbers below are the shipped values):
- **Platform:** an anchored, `CanCollide` `Part`, top surface at the balcony floor height, sized to comfortably hold the balcony grid (`48 × 48` studs). Friendly soft-blue to echo the lobby banner.
- **Placement:** `LOBBY_ORIGIN = (0, 45, −64)` — raised ~45 studs and set back behind the arena's −Z edge (arena spans X,Z ∈ [−32, 32], surface Y = 0), so standing bodies that face +Z look down and across into the pit.
- **Fall protection (load-bearing — it floats over the void):** full-perimeter barriers, **taller than a jump** (`LOBBY_WALL_HEIGHT = 12` vs `JUMP_HEIGHT = 7.2`) so a body can't hop out. Three solid walls; the **arena-facing side** is a **transparent but `CanCollide`** glass railing so the downward view is unobstructed but no body can walk *or jump* off.
- `LobbyArea` exposes only `build()`. Slot *positions* are owned by `BodyManager` (via `SpawnLayout` + `Config`), keeping all body-positioning logic in one place; `LobbyArea` is geometry-only.

### Component 3 — `src/server/BodyManager.luau` (changed)

- Replace the inline arena-slot math in `createBody` with `SpawnLayout.arenaSlot(...)` (positions unchanged).
- Compute and store **both** slots per player from a stable per-body index:
  - `arenaSlotByOwner[player]` — the existing arena spawn `CFrame` (currently `spawnByOwner`; keep or rename, the plan decides).
  - `lobbySlotByOwner[player]` — a balcony grid `CFrame` built from `SpawnLayout.lobbySlot(...)` + `LOBBY_ORIGIN`, oriented to face the arena (`CFrame.lookAt` toward arena center) so the avatar and its camera point at the pit.
- **`createBody` spawns onto the balcony slot** (not the arena), since a joining player starts in the waiting/lobby state. A few studs above the balcony surface so the body settles, mirroring the arena drop.
- A shared local `placeOnLobbySlot(player, body)` does the work (guard on missing slot/root, `Anchored = false`, zero linear/angular velocity, `PivotTo(lobbySlotByOwner[player])`). Two public wrappers use it:
  - **`returnToLobby(player)`** — places the player's **own** body (`bodyByOwner[player]`). Used by `RoundManager` at the Lobby reset.
  - **`sendToLobby(player, body)`** — places an **arbitrary given** body on the player's slot. Used on elimination to relocate the body the player was controlling.
- `resetBody` (arena slot) is unchanged. **`parkBody` is removed** — nothing anchors a body anymore; elimination now teleports the dead body up to the balcony (which catches the fall), and round transitions always unanchor + pivot.
- `removeBody` clears both slot tables.

### Component 4 — `src/server/RoundManager.luau` (changed)

- **`start`:** call `LobbyArea.build()` alongside the existing `HazardSystem.build()`.
- **`eliminate` (added 2026-06-21):** replace `BodyManager.parkBody(body)` with `BodyManager.sendToLobby(player, body)` where `body = ControlManager.getControlledBody(player)` — the eliminated player's controlled body goes up to their balcony slot, still under their control. The old `resendSpectate()` call (and the now-dead `resendSpectate`/`firstAliveBody` helpers) are removed; eliminated players watch from the balcony, not via a close-up spectate camera.
- **`endRound`, Ended window (victory cam):** at the start of the Ended results beat, fire `SpectateBody:FireClient(p, winnerBody)` to **every present player** so all cameras frame the winner standing in the arena. Bodies are *not* relocated here (winner stays put so the cam has a subject; already-eliminated players are up on the balcony, where the victory cam pulls their camera down to the winner). If there is no winner (disconnect-decided round, `winnerName == nil`), skip the victory cam. The existing per-second `broadcastState(remaining)` countdown tick is unchanged.
- **`endRound`, → Lobby reset:** after the Ended countdown, before/at `RoundState.reset`, relocate everyone to the balcony: for each present player `BodyManager.returnToLobby(player)`, **then** `ControlManager.resetControl()`. Ordering mirrors `beginRound` (unanchor + pivot **before** `SetNetworkOwner`, which errors on an anchored part). `resetControl` fires `SetControlledBody(ownBody)`, which pulls each camera off the victory-cam subject and back onto the player's own body — now standing on the balcony. The subsequent `broadcastState()` → Lobby is unchanged.
- **`addPlayer`:** unchanged call shape — `createBody` now places the body on the balcony, so a mid-round joiner (added to `present`, not `alive`) waits on the balcony instead of loose in the live arena. No new logic in `addPlayer`.

### Component 5 — `src/shared/Config.luau` (new tunables)

Add a documented block (final names per the plan), e.g.:
- `LOBBY_ORIGIN = Vector3.new(0, 45, -64)` — balcony surface-center origin (bodies spawn a few studs above).
- `LOBBY_PAD_SIZE` / `LOBBY_WALL_HEIGHT` (taller than `JUMP_HEIGHT`) / railing thickness — balcony geometry.
- `LOBBY_PER_ROW = 4`, `LOBBY_SPACING ≈ 10` — balcony grid.
- `LOBBY_FACE_TARGET = Vector3.new(0, 0, 0)` — the point bodies/cameras face (arena center).
- Colors (soft-blue platform; glass-railing transparency).

Each value carries a comment explaining the geometric reasoning (matching the existing `Config` house style, e.g. the tile-center note).

## Testing

- **Lune unit test** — `tests/spawn_layout.spec.luau`:
  - `arenaSlot` reproduces today's documented positions exactly (assert X = −4, 4, 12, 20, 28 for index 1..5 at the real `SPAWN_ORIGIN`/`SPAWN_SPACING` numbers; assert `y == originY`, `z == originZ`).
  - `lobbySlot` grid: slots for index 1..N are pairwise distinct, spaced ≥ `spacing`, wrap into rows at `perRow`, and stay within the documented balcony footprint; grid is centered on the origin.
  - Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec`.
- **Studio smoke test** — new `docs/smoke-tests/2026-06-21-lobby-staging-area-smoke-test.md`, a 2-client procedure (keep `Config.HAZARDS_ENABLED = false` so the floor stays safe while observing the loop):
  1. **Join:** both clients spawn on the **balcony**, can walk around behind the railing, and looking forward see the arena below. Cannot walk off — and cannot **jump** over the railing (walls are taller than a jump).
  2. **Round start:** at `beginRound`, both bodies teleport down into the **arena** spawn slots; camera retargets to the own body in the arena; hazards (if enabled) start.
  3. **Mid-round elimination (3+ players):** with a third client, drop one body into the void mid-round. That eliminated player's body teleports up to the **balcony** and they keep walking it around / watching the round below — no parked corpse in the arena.
  4. **Round end (victory cam):** force a finish (drop a body into the void). During the Ended "Next round in N" window, **all** clients' cameras frame the **winner** standing in the arena.
  5. **Lobby reset:** after the countdown, all bodies teleport up to the **balcony** in their **own** body, cameras pulled back onto themselves; the Lobby banner shows over the balcony.
  6. **Mid-round join:** a client joining during Active appears on the **balcony** (not loose in the arena) and is folded into the arena at the next `beginRound`.

## Edge cases & robustness

- **No winner (disconnect-decided round):** `winnerName == nil` → skip the victory cam; the → Lobby relocation still runs (everyone goes to the balcony). No stale spectate target.
- **`SetNetworkOwner` on an anchored part:** avoided by `returnToLobby` unanchoring before `resetControl` runs (same ordering invariant as `beginRound`).
- **Eliminated player mid-round:** the body they were controlling is sent to their balcony slot the instant they die, still under their control, so they walk the balcony / watch from above. They're excluded from `aliveRoster`, so that body is never swapped (`SwapController.plan` only sees alive players) nor void-killed (the void monitor only checks alive players). At round end `resetControl` returns them to their own body like everyone else. Sattolo guarantees no fixed point, so the controlled body is never the player's own — moving it can't disturb a live opponent.
- **Last elimination ends the round:** with `MIN_PLAYERS_TO_CONTINUE = 2`, eliminating the second-to-last player drops alive to 1 and ends the round, so the **winner is never eliminated** and always remains in the arena as the victory-cam subject; the just-eliminated loser is on the balcony and the victory cam pulls their camera to the winner.
- **Body with no `HumanoidRootPart`:** the shared `placeOnLobbySlot` guard makes `returnToLobby` / `sendToLobby` no-op (same guard as `resetBody`).
- **Fall protection is load-bearing:** the balcony floats over the void; the perimeter barriers (incl. the `CanCollide` glass railing) must fully enclose the walkable area **and be taller than a jump** (`LOBBY_WALL_HEIGHT = 12` > `JUMP_HEIGHT = 7.2`), or a player could walk/jump a controlled body off and trigger a void death between rounds. The smoke test explicitly checks walking *and jumping* the railing.
- **Arena spawn math unchanged:** `SpawnLayout.arenaSlot` is asserted to reproduce the current positions, so the disappearing-tile interaction (tile-center spawns) is not regressed.

## Known limitations (deferred — surfaced in review 2026-06-21)

These are accepted for the MVP (2-friends playtest) and noted for later hardening; none are introduced by the eliminated-→-lobby change beyond what's marked:

- **Concurrent disconnect during the post-death window can transiently yank an eliminated player.** `ControlModel` is deliberately *unaware of death* — an eliminated player keeps their `bodyOf`/`controllerOf` entries (only `RoundState.alive` changes). If another player disconnects while an eliminated player is on the balcony, the tested **absorb rule** may reassign that eliminated player onto an arena body (and the disconnecting player's avatar body — possibly the one the eliminated player is standing in — is destroyed). The glitch is visual and is cleaned up by `resetControl` at round end. A proper fix (teaching the disconnect/absorb path about death) is entangled with the load-bearing, lune-tested disconnect design and deserves its own brainstorm — **not** hacked onto this branch.
- **`BodyManager._index` is never reclaimed.** It increments per join for the whole server session, so the 17th *cumulative* join computes an off-pad balcony slot (and an off-field arena slot). This is the **same accepted limitation** as the arena's single-row spawn (see the `Config.SPAWN_ORIGIN` note: "Fine for the 2-player MVP — when raising player count, spread across rows or enlarge the grid"). Fix both together (a freed-index free-list) when raising player counts.
- **Victory-cam subject can vanish if the winner's body owner disconnects** during the `ROUND_END_SECONDS` countdown (the avatar body is destroyed on disconnect). Rare; `resetControl` retargets every camera when the countdown ends.

## Files touched

| File | Change |
|------|--------|
| `src/shared/SpawnLayout.luau` | **new** — pure arena + balcony slot math |
| `src/server/LobbyArea.luau` | **new** — builds the elevated balcony geometry once |
| `src/server/BodyManager.luau` | use `SpawnLayout`; store arena + balcony slots; `createBody` → balcony; new `returnToLobby` + `sendToLobby` (shared `placeOnLobbySlot`); `parkBody` removed |
| `src/server/RoundManager.luau` | `start` builds the balcony; `eliminate` sends the controlled body to the balcony (spectate helpers removed); `endRound` victory cam + relocate-to-balcony at Lobby reset |
| `src/shared/Config.luau` | new balcony geometry / grid / color tunables |
| `tests/spawn_layout.spec.luau` | **new** — lune unit test for `SpawnLayout` |
| `docs/smoke-tests/2026-06-21-lobby-staging-area-smoke-test.md` | **new** — 2-client runtime check |
