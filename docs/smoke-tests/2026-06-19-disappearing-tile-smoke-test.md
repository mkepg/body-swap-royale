# Smoke Test — Disappearing Tile Hazard (2026-06-19)

Runtime behavior lune cannot cover: part construction, collision, physics
fall-through, property replication, and the hazard↔grace interaction. Run in
Roblox Studio with **2 players** (Play Solo gives 1; use Start > "Local Server"
with 2 players, or Team Test).

**Status:** ⬜ not yet validated

## Setup
1. Open the place in Studio, sync via Rojo.
2. Start a 2-player local server (Test > Clients and Servers > 2 players > Start).
3. Wait for the lobby countdown; the round goes Active.

## Checks

### 1. Arena is a tile floor, baseplate gone
- [ ] `Workspace` has a `TileField` folder with 64 `Tile_r_c` parts; no `Baseplate`.
- [ ] At round start the whole floor is solid grey (no red, no gaps).

### 2. Telegraph + vanish cycle
- [ ] Within a few seconds tiles begin turning **red** (warning), then **vanish**
      (transparent + non-collidable) for ~1.5s, then return to solid grey.
- [ ] Tiles do **not** all drop at once — they are staggered.

### 3. Fall-through elimination
- [ ] Stand a body on a tile and stay; when that tile vanishes the body falls
      through and (after crossing `VOID_Y = -4`) is eliminated — the
      `EliminationEvent` fires and the player's HUD shows elimination.
- [ ] The eliminated body is parked (anchored), not destroyed.

### 4. Grace protects a fresh swap (the second-source check)
- [ ] In the command bar run `require(game.ServerScriptService.Server.RoundManager).forceSwap()`
      to swap controls.
- [ ] **The grace beat only fires if the player is swapped onto a tile already in
      `gone`** (or the last sliver of `warning`) — a `solid`/early-`warning` tile
      stays collidable, so the body does not fall and grace never engages. Repeat
      `forceSwap()` until a player lands on a *vanished* tile and confirm they are
      NOT eliminated during the grace floor/window as they begin to fall — they
      get the beat to move to a neighbor tile. (Grace is `GRACE_SECONDS = 1.5`,
      floor `0.5`.) If this case is hard to land with 2 players on the
      deterministic pattern, note that as a finding.

### 5. Round boundaries leave a clean floor
- [ ] When the round ends (one survivor), all tiles return to solid grey.
- [ ] The next round starts on a fully solid floor again.

## Result
Record the date validated and any tuning notes (tile rhythm, grid size, VOID_Y).
