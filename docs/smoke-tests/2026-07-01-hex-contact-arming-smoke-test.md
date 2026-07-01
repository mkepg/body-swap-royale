# Smoke Test — Hex Contact-Probe Arming (2026-07-01)

**Status:** RUNTIME-UNVERIFIED until run in Studio.
**Covers:** the server glue that lune can't test — `HazardSystem.step`'s downward
`Spherecast` contact probe (replacing the old `HexGrid.fromWorld`/`floorAt` point-sample).
Pure logic (`HexGrid`, `HexErosionModel`) is unchanged and lune-covered.

**Bug fixed:** Tiles at the arena's outer rim and tiles a body perches on the
edge/side of did NOT arm (the old point-sample rounded a root on the outer half of a
rim tile to a clipped/nonexistent lattice neighbor → `tileByKey` miss → no arm).
The fix sweeps a small sphere (`HEX_GROUND_PROBE_RADIUS = 1.5 studs`) straight down
from each body root, hitting whichever collidable hex part is physically beneath it.

**Note on `screen_capture`:** the MCP `screen_capture` tool renders only the edit
viewport, not the running Play client. All visual checks below require the human to
drive the actual Play session in Studio.

## Setup

1. Open the place in Studio. Start a **2-player** local server
   (Test > Clients and Servers > 2 players, Start).
2. Both bodies spawn on the balcony; a round starts after the lobby countdown and
   bodies are repositioned onto the top hex floor.
3. Keep the command bar handy for `forceSwap`.

## Checks

### 1. Outer-rim tile arming (the primary regression)

- [ ] Walk a body to the **very edge of the pit** — the outermost ring of visible
      tiles (those near the circular boundary at radius ~30 studs). Stand still on one.
- [ ] Within ~1.2 s the tile turns **red (warning)**, then **vanishes**.
      Previously these tiles never armed; any arm here confirms the fix.
- [ ] Try several rim tiles spread around the circle (N, S, E, W edges). All should
      arm. The circle clips the hex lattice at different angles per edge, so test at
      least 4 positions.

### 2. Edge/perched pose arming

- [ ] Find a tile near (but not at) the rim. Position the body so it stands on the
      **edge or corner** of the tile — the HumanoidRootPart hovers over the grout seam
      or the neighboring tile's airspace. The body is visibly partly over the gap.
- [ ] The tile the body is physically resting on should still **turn red, then vanish**
      (the spherecast radius of 1.5 studs bridges the seam). If the root had rounded to
      the wrong hex (old bug), the tile would stay solid.
- [ ] The neighboring tile (the one the root XZ fell over, but the body wasn't on)
      should **not** arm.

### 3. Normal center-of-arena tiles — regression check

- [ ] Walk a body across the center of the arena. Each tile walked across turns red,
      then vanishes — same behavior as before the fix.
- [ ] A tile never stepped on **stays solid** the whole round.

### 4. Airborne body does NOT arm

- [ ] Force a swap from the command bar:
      `require(game.ServerScriptService.Server.RoundManager).forceSwap()`
      or wait for a natural cadence swap.
- [ ] Have a body **jump** over a tile without landing (jump and move laterally so feet
      never touch the tile surface).
- [ ] The tile the body passed over while airborne should **remain solid** — the
      spherecast travels only `HEX_STAND_BAND` (6 studs) downward from the root, so a
      body in mid-air is above that band and the cast misses the floor.

### 5. Grace × arming synergy — regression check

- [ ] Force a swap. Immediately after the swap, stand still on a tile.
- [ ] The tile should **not** start arming during the grace window (≈1.5 s) — same as
      before; `graceBlocked` is still passed through the sample and respected by
      `HexErosionModel.arm`.
- [ ] Once grace ends or the body moves, the tile under it arms normally.

### 6. Gone tiles are never re-armed

- [ ] Step on a tile until it vanishes (CanCollide=false, fully transparent).
- [ ] Walk back over the same spot. The `groundParams` filter has
      `RespectCanCollide=true`, so the spherecast skips the gone tile and hits the
      floor below (or nothing if this is the bottom floor). No ghost re-arm occurs.

### 7. Multi-floor descent — regression check

- [ ] Erode a path through the top floor so a body falls to floor 2. Verify floors 2–7
      erode the same way when walked on.
- [ ] Only falling **off the lowest (7th) floor** → **eliminated** (crossed VOID_Y).
      The void monitor cadence is 0.1 s; elimination fires within one tick.

### 8. Dev switch (optional)

- [ ] Set `Config.HAZARDS_ENABLED = false` in the command bar; replay. Floors build
      and stay solid — no tile ever arms (confirms the `groundParams` guard also
      short-circuits correctly). Restore to `true` after.

## Result

Record pass/fail per check and any tuning notes (probe radius, stand-band height,
gone delay). If a rim tile still fails to arm, note its approximate world XZ and
which floor, so the lattice clipping can be inspected in HexGrid.
