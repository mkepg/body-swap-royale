# Hex-A-Gone Arena — Design Spec

**Date:** 2026-06-23
**Status:** Approved for planning
**Supersedes hazard:** the time-driven disappearing-tile floor (`TileFieldModel` + the cyclic part of `HazardSystem`)

## Summary

Replace the current **time-driven** square disappearing-tile floor with a **step-driven, monotonic, multi-floor hexagonal** floor (Fall Guys "Hex-A-Gone"). A hex tile arms the instant a body stands on it, flashes a warning color, then vanishes for good and never returns that round. Three stacked hex floors: falling drops a body to the floor below; only falling off the **bottom** floor eliminates.

### Why (design rationale)

The current floor is impersonal — tiles vanish on a schedule nobody caused. Body Swap Royale's core pillar (GDD §1, §5, §12) is the opposite: *you inherit the consequences of other players' decisions; blame is attributable, deaths are personal.* A step-eroded floor makes the floor a **record of where players have walked**. Combined with the swap, you are dropped into a body sitting in someone else's eroded trail — possibly marooned on an island over the void. That is the signature "inherit the consequences" moment, produced on every swap, which the timed floor cannot create. The mechanic and the swap reinforce each other.

This work intentionally **defers** the remaining MVP "earn currency" economy slice (a deliberate reprioritization toward feel — GDD §12's "does this feel fair/fun?" gate).

## Decisions (locked during brainstorming)

| Decision | Choice |
|----------|--------|
| Layers | **Multi-layer**, 3 floors (tunable in Config) |
| Tile shape | **Hexagons** (true Hex-A-Gone look) |
| Hex construction | Runtime-built cluster of **3 rotated `Block` parts** per tile — no mesh asset, consistent with the build-in-code pattern (`HazardSystem.build`/`LobbyArea.build`) |
| Erosion | **Step-driven, monotonic** (gone never returns within a round) |
| Death model | **Unchanged** — existing grace-gated void monitor, with `VOID_Y` relocated below floor 3; intermediate floors are real `CanCollide` so a fall lands on the next floor |
| Server loops | **Consolidated** — fold erosion into the existing void monitor (one 0.1s loop), not a second loop |
| Client | **No change, no new remote** — tile part property changes replicate as today |

## Architecture

Honors the established pure-core / glue split: pure, Roblox-free, clock-injected modules unit-tested with lune; server glue owns real clocks/positions and gets a Studio smoke test.

### Pure module — `HexGrid` (`src/shared/HexGrid.luau`, lune-tested)

Number-in / number-out like `SpawnLayout`. No Vector3 / CFrame / Color3, no clocks, no RNG.

- `HexGrid.tiles(radius)` → array of `{ q = number, r = number }` axial coords forming a hex-shaped field of the given ring `radius`. Count is `1 + 3·radius·(radius+1)`.
- `HexGrid.toWorld(q, r, size)` → `dx, dz` center offset (studs) from the field center. `size` is the hex circumradius (center-to-vertex).
- `HexGrid.fromWorld(dx, dz, size)` → nearest `{ q, r }` via cube-rounding (the "which hex is this body standing on" lookup).
- `HexGrid.spawnSlots(radius)` → ordered array of `{ q, r }` used for round-start body placement (replaces `SpawnLayout.arenaSlot` for the arena floor only). Ordering should spread bodies across the field (e.g. outward spiral).

Orientation: **flat-top** hexes (choose one orientation and keep `toWorld`/`fromWorld` consistent; document it inline).

### Pure module — `HexErosionModel` (`src/shared/HexErosionModel.luau`, lune-tested)

Replaces `TileFieldModel`'s cyclic logic with two tiny pure decisions. Monotonic — the caller never clears `steppedAt`.

- `HexErosionModel.arm(steppedAt, occupied, graceBlocked, now)` → new `steppedAt`:
  - if `steppedAt ~= nil` → return `steppedAt` unchanged (idempotent once armed),
  - elseif `occupied and not graceBlocked` → return `now`,
  - else → return `nil`.
- `HexErosionModel.phaseAt(steppedAt, now, durations)` → `"solid" | "warning" | "gone"`:
  - `steppedAt == nil` → `"solid"`,
  - `now - steppedAt < durations.gone` → `"warning"` (armed: shows the warning color immediately on step, the telegraph everyone reads),
  - else → `"gone"`.
  - `durations = { gone = number }` — the single step→gone delay. A stepped hex flashes the warning color for the whole delay, then vanishes (Fall-Guys-accurate; no separate grey-then-warn sub-phase).

### Server glue — `HazardSystem` rewrite (`src/server/HazardSystem.luau`)

- `build()` — construct 3 stacked hex floors. Each tile is a small cluster of 3 rotated `Block` parts (60°/120° apart) grouped so the union reads as a hexagon from above and erodes as a unit. Tile record: `{ parts = {Part, Part, Part}, steppedAt = nil|number, phase = "solid", floor = number, q = number, r = number }`. Continues to clear the leftover `Baseplate` / `SpawnLocation` as today. Singleton (second call is a no-op).
- `start(startTime)` — reset all tiles to solid (`steppedAt = nil`), force-apply solid. Does **not** spin its own loop anymore.
- `step(now, samples)` — called by `RoundManager`'s void monitor each tick. `samples` is an array of `{ dx, dz, y, graceBlocked }` (one per alive body, offsets relative to the field center). For each sample: resolve `floor` from the `y` band and `{q,r}` from `HexGrid.fromWorld(dx, dz, size)`; `arm` that tile via `HexErosionModel`. Then for **every** tile, compute `phaseAt(steppedAt, now)` and apply on change to its 3 parts (`CanCollide` / `Transparency` / `Color`).
- `stop()` — force all tiles solid (Lobby/Ended floor for parked bodies); clears `steppedAt`.
- `HAZARDS_ENABLED = false` dev switch: floors build but `step` never arms (floor stays solid), so swaps can be observed without bodies falling.

`HazardSystem` stays decoupled from `GraceModel` / `RoundManager`: `graceBlocked` arrives as plain data in each sample.

### Loop consolidation (`src/server/RoundManager.luau`)

Today two 0.1s loops run: the void monitor (`startMonitor`) and `HazardSystem`'s tile loop. The monitor already computes, per alive player per tick: the controlled body root, horizontal travel since swap (`GRACE_MOVE_EPSILON` → `markMoved`), and the void check. Extend that single loop to also **gather a `samples` array** (`{ dx, dz, y, graceBlocked }` per alive body, where `graceBlocked` = player is still inside the grace window AND has not yet moved) and call `HazardSystem.step(now, samples)` once per tick.

**Load-bearing constraint:** the death branch (`root.Position.Y < VOID_Y` → `eliminateFromHazard`) and the move/grace logic must stay behaviorally identical. The change is purely *additive*: collect samples, call `step`. Covered by the smoke test.

### Death model & vertical geometry

- Floors at `Y = TILE_SURFACE_Y`, `- HEX_FLOOR_GAP`, `- 2·HEX_FLOOR_GAP`. Intermediate floors are real `CanCollide`, so a body falling through a `gone` hex lands on the next floor's solid hex below.
- `VOID_Y` relocates to just **below** floor 3. The grace-gated void monitor eliminates exactly as today — only the kill line moves under the lowest floor. Death path otherwise unchanged.
- Vertical fall does not count as "moved" (grace survives a drop between floors — already handled by the horizontal-only `GRACE_MOVE_EPSILON` check).
- The lobby balcony (`Y=45`) now overlooks a deeper pit — no balcony geometry change.

### Spawn (`src/server/BodyManager.luau`)

- Round-start bodies spawn on **top-floor hex centers** via `HexGrid.spawnSlots`. Only `arenaCFrame(index)` changes (square grid → hex center + `SPAWN_ORIGIN.Y`). The slot allocator / free-list / `arenaSlotByOwner` flow is untouched; `sendToArena` (disconnect rescue) inherits the new positions automatically.
- Balcony placement (`lobbyCFrame` / `SpawnLayout.lobbySlot`) is unchanged.

## Config changes (`src/shared/Config.luau`)

**New:**
- `HEX_RADIUS` — rings from center (default `3` → 37 hexes/floor).
- `HEX_SIZE` — hex circumradius in studs.
- `HEX_FLOOR_COUNT = 3`.
- `HEX_FLOOR_GAP` — vertical studs between floors.
- `HEX_GONE_DELAY_SECONDS` — single step→gone delay (the hex shows the warning color for this whole window, then vanishes).

**Reused:** `TILE_COLOR_SOLID` / `TILE_COLOR_WARNING` for hex phases; `HAZARDS_ENABLED` as the dev switch; `TILE_THICKNESS` for hex part thickness.

**Retired:** cyclic `TILE_SOLID_SECONDS` / `TILE_GONE_SECONDS` semantics; the square arena tunables `ARENA_PER_ROW` / `ARENA_SPACING` (arena now hex). `LOBBY_*` untouched.

**Recomputed:** `VOID_Y` below floor 3.

## Client / legibility

- **No client change, no new remote.** Hex part `Transparency` / `CanCollide` / `Color` changes replicate exactly as the square tiles do today. The warning-color flash is the "this hex is about to drop" read.
- Per-hex sink/shake animation is **out of scope** (later polish).

## Testing

### Pure (lune): `tests/HexGrid.spec`, `tests/HexErosionModel.spec`
- `HexGrid.tiles(radius)` count `= 1 + 3R(R+1)`; no duplicate coords; center present.
- `toWorld`/`fromWorld` round-trip: `fromWorld(toWorld(q,r,size), size) == {q,r}` for all tiles; `fromWorld` near a hex edge resolves to the correct (nearest-center) hex.
- `spawnSlots` returns distinct in-field coords, at least `LOBBY_CAPACITY` of them.
- `HexErosionModel.arm`: stays `nil` when unoccupied; sets `now` on first non-grace occupancy; suppressed (`nil`) while `graceBlocked`; idempotent once armed (re-arming returns the original `steppedAt`).
- `HexErosionModel.phaseAt`: `solid` when `steppedAt nil`; `warning` before `durations.gone`, `gone` at/after it; monotonic (no return to solid for increasing `now`).

### Studio smoke test: `docs/smoke-tests/2026-06-23-hex-a-gone-smoke-test.md` (RUNTIME-UNVERIFIED until run)
2-client procedure:
1. Walk across floor 1 — hexes arm, flash warning, vanish, and do **not** return.
2. Fall through floor 1 → land on floor 2 → through to floor 3 → off floor 3 → eliminated (crossed `VOID_Y`).
3. Floors 2 and 3 stay pristine until a body is on them.
4. Force a swap (`RoundManager.forceSwap()`) onto an eroded trail; confirm the tile under the freshly-swapped body does **not** drop during the grace window, then arms once grace ends or the body moves.
5. Round ends with a winner; the 3-floor pit reads clearly from the balcony.

## Scope / YAGNI

**Out of scope:** hex MeshPart asset (using composed parts); per-hex sink/shake polish; multiple maps; the deferred economy slice.

## Risks & mitigations

1. **Touching the load-bearing void monitor.** Keep the death + move/grace branches behaviorally identical; the change is additive (gather samples, call `step`). Covered by the smoke test.
2. **Composed-hex collision seams** — a body must stand cleanly on 3 overlapping blocks. Tune part sizes/overlap; verify in the smoke test.
3. **`fromWorld` edge-straddle** — a body between two centers arms the nearest hex, which is acceptable (arming the standing-on hex is the goal).
4. **Part count** — 3 floors × ~37 hexes × 3 blocks ≈ 333 parts; negligible at MVP scale.
