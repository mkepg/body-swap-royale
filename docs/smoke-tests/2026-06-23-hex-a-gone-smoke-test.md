# Smoke Test — Hex-A-Gone Arena (2026-06-23)

**Status:** RUNTIME-UNVERIFIED until run in Studio.
**Covers:** the server glue that lune can't test — `HazardSystem` (3-floor hex build,
step-driven erosion), the `RoundManager` void-monitor consolidation, and
`BodyManager` hex-center spawns. Pure logic (`HexGrid`, `HexErosionModel`) is
lune-covered.

**Spec:** `docs/specs/2026-06-23-hex-a-gone-arena-design.md`

## Setup
1. Open the place in Studio. Start a **2-player** local server
   (Test > Clients and Servers > 2 players, Start).
2. Both bodies spawn on the balcony; a round begins after the lobby countdown.

## Checks

### 1. Build & geometry
- [ ] Below the balcony there are **three stacked hexagonal floors** (a `HexField`
      folder in Workspace), each tile reading as a hexagon, top floor at Y=0.
- [ ] No leftover `Baseplate` / `SpawnLocation` remains.
- [ ] At round start every hex is solid grey; bodies stand cleanly on the top floor
      (no falling through seams between the 3 sub-parts of a hex).

### 2. Step-driven, monotonic erosion
- [ ] Walk a body across floor 1: each hex you stand on turns **red (warning)**,
      then **vanishes** ~1.2s later.
- [ ] A vanished hex **does not come back** for the rest of the round.
- [ ] A hex you never touch **stays solid** (erosion is occupancy-driven, not timed).

### 3. Multi-floor descent & death
- [ ] Walk off / erode a path so a body **falls through floor 1 and lands on floor 2**
      (not eliminated). Continue to **floor 3**, then off floor 3 → **eliminated**
      (crossed VOID_Y).
- [ ] Floors 2 and 3 stay pristine until a body is actually on them, then erode the
      same way.

### 4. Swap × grace synergy (the headline interaction)
- [ ] In the command bar run `require(game.ServerScriptService.Server.RoundManager).forceSwap()`
      to force a swap (or wait for a natural one).
- [ ] Immediately after a swap, the hex **under the freshly-swapped body does NOT
      start eroding** during the grace window (no instant red/drop under a still body).
- [ ] Once grace ends (≈1.5s) or the body moves, the hex under it **arms normally**.

### 5. Round end
- [ ] With one body left, the round **ends and declares a winner**; the victory cam
      frames the survivor.
- [ ] Between rounds the floor is **fully solid again** (parked bodies rest safely);
      the next round re-spawns bodies on the top floor and erosion resets.

### 6. Dev switch (optional)
- [ ] Set `Config.HAZARDS_ENABLED = false`, replay: floors build and stay solid; no
      hex ever arms (lets you observe swaps without falls). Restore to `true` after.

## Result
Record pass/fail per check and any tuning notes (hex size, floor gap, gone delay).
