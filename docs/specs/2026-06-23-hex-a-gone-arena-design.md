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
| Layers | **Multi-layer**, 7 floors (tunable in Config) — *revised from 3 on 2026-06-24* |
| Tile shape | **Hexagons** (true Hex-A-Gone look) |
| Hex construction | **5-part composed hexagon** per tile: 1 central `Block` + 4 `WedgePart` end-caps, meeting edge-to-edge with no overlap — *revised again on 2026-06-25* from the EditableMesh path, which silently no-ops in places where Experience Settings > Security > Allow Mesh/Image Access is off (`pcall` returned ok but the resulting MeshPart has no triangles → rendered as its rectangular AABB, the "squares with gaps" bug). The wedge composition uses stock parts only — guaranteed to render — and still has zero coincident geometry (no z-fighting on recolor). `HexPrism` is retained for the future EditableMesh path if the security setting is enabled. |
| Floor color | Each floor a **distinct solid color** (`Config.HEX_FLOOR_COLORS`, 7-step palette top→bottom) — *added 2026-06-24* |
| Vertical gap | `HEX_FLOOR_GAP = 50` studs (deep, clearly-separated pit) — *raised 10 → 28 → 50 over 2026-06-24* |
| Tile size / count | Small tiles, fine honeycomb: `HEX_SIZE = 4`, `HEX_RADIUS = 5` (91 tiles/floor) — *revised from size 6 / radius 3 on 2026-06-24 to match the reference look* |
| Tile seam | Each tile rendered/collided **inset** by `HEX_GAP = 0.3` studs from the lattice radius → a thin grout seam between distinct tiles, and **zero coincident geometry** (the real z-fighting fix) — *added 2026-06-24*. The lattice (`HexGrid`) still spaces centers by full `HEX_SIZE`, so occupancy lookup is unaffected. |
| Erosion | **Step-driven, monotonic** (gone never returns within a round) |
| Death model | **Unchanged** — existing grace-gated void monitor, with `VOID_Y` relocated below the lowest floor; intermediate floors are real `CanCollide` so a fall lands on the next floor |
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

### Pure module — `HexPrism` (`src/shared/HexPrism.luau`, lune-tested) — *added 2026-06-24*

Flat-top hexagonal-prism mesh geometry, so each tile is one true hexagon (no overlapping parts → no z-fighting; exact shape → no gaps).

- `HexPrism.build(size, thickness)` → `{ vertices = {{x,y,z}×12}, triangles = {{i0,i1,i2}×20} }`. Vertices 1–6 top ring (`+thickness/2`), 7–12 bottom ring, all on the circumradius. Triangle order: 4 top-fan, 4 bottom-fan, 12 side; each wound (via a computed-normal flip helper) so its normal points outward (top +Y, bottom −Y, sides radial). The winding is the load-bearing, un-eyeballable bit — the lune test asserts the per-face normal directions.

### Server glue — `HazardSystem` rewrite (`src/server/HazardSystem.luau`)

- `build()` — construct 7 stacked hex floors. Each tile is composed of 5 anchored parts: 1 central `Block` of size `R × T × R·√3` (the flat-top hex's middle rectangle) + 4 `WedgePart` end-caps, each `T × R/2 × R·√3/2` and rotated so its slanted triangular face lies flat on top with the right-angle pointing inward to the hex center. The 4 wedge triangles + central block tile the hexagon edge-to-edge with no overlap (verified via Studio probe — the 3 top-face vertices of each wedge match the target perimeter coordinates exactly). Colored per floor (`Config.HEX_FLOOR_COLORS`). Tile record: `{ parts = {Block, WedgePart×4}, steppedAt = nil|number, phase = "solid", floor = number, q = number, r = number }`. Continues to clear the leftover `Baseplate` / `SpawnLocation`. Singleton (second call is a no-op).
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
- `VOID_Y` relocates to just **below** the lowest (7th) floor. The grace-gated void monitor eliminates exactly as today — only the kill line moves under the lowest floor. Death path otherwise unchanged.
- Vertical fall does not count as "moved" (grace survives a drop between floors — already handled by the horizontal-only `GRACE_MOVE_EPSILON` check).
- The lobby balcony (`Y=45`) now overlooks a deeper pit — no balcony geometry change.

### Spawn (`src/server/BodyManager.luau`)

- Round-start bodies spawn on **top-floor hex centers** via `HexGrid.spawnSlots`. Only `arenaCFrame(index)` changes (square grid → hex center + `SPAWN_ORIGIN.Y`). The slot allocator / free-list / `arenaSlotByOwner` flow is untouched; `sendToArena` (disconnect rescue) inherits the new positions automatically.
- Balcony placement (`lobbyCFrame` / `SpawnLayout.lobbySlot`) is unchanged.

## Config changes (`src/shared/Config.luau`)

**New:**
- `HEX_RADIUS` — rings from center (default `3` → 37 hexes/floor).
- `HEX_SIZE` — hex circumradius in studs.
- `HEX_RADIUS = 5` / `HEX_SIZE = 4` — small tiles, 91/floor (fine honeycomb) *(revised from 3 / 6)*.
- `HEX_GAP = 0.3` — studs each tile is inset from the lattice radius (thin grout seam; render/collide radius = `HEX_SIZE - HEX_GAP`) *(added 2026-06-24)*.
- `HEX_FLOOR_COUNT = 7` *(revised from 3 on 2026-06-24)*.
- `HEX_FLOOR_GAP = 50` — vertical studs between floors *(raised 10 → 28 → 50 on 2026-06-24)*.
- `HEX_STAND_BAND` — root-height window counting as "on" a floor (must be `< HEX_FLOOR_GAP`).
- `HEX_GONE_DELAY_SECONDS` — single step→gone delay (the hex shows the warning color for this whole window, then vanishes).
- `HEX_FLOOR_COLORS` — 7-step distinct-per-floor solid palette (top→bottom), indexed by `floor+1` *(added 2026-06-24)*.

**Reused:** `TILE_COLOR_WARNING` for the armed/imminent red; `HAZARDS_ENABLED` as the dev switch; `TILE_THICKNESS` for hex part thickness; `TILE_SURFACE_Y` for the top floor.

**Retired:** cyclic `TILE_SOLID_SECONDS` / `TILE_GONE_SECONDS` semantics; the square arena tunables `ARENA_PER_ROW` / `ARENA_SPACING`; `TILE_COLOR_SOLID` (per-floor `HEX_FLOOR_COLORS` replaces it). `LOBBY_*` untouched.

**Recomputed:** `VOID_Y` below the lowest floor (`-304` for 7 floors at gap 50).

## Client / legibility

- **No client change, no new remote.** Hex part `Transparency` / `CanCollide` / `Color` changes replicate exactly as the square tiles do today. The warning-color flash is the "this hex is about to drop" read.
- Per-hex sink/shake animation is **out of scope** (later polish).

## Testing

### Pure (lune): `tests/hex_grid.spec`, `tests/hex_erosion_model.spec`, `tests/hex_prism.spec`
- `HexPrism.build` — 12 vertices / 20 triangles, top & bottom rings at `±thickness/2` on the circumradius, and **each face's computed normal points outward** (top +Y, bottom −Y, sides radial) — the winding correctness that can't be eyeballed in Studio.
- `HexGrid.tiles(radius)` count `= 1 + 3R(R+1)`; no duplicate coords; center present.
- `toWorld`/`fromWorld` round-trip: `fromWorld(toWorld(q,r,size), size) == {q,r}` for all tiles; `fromWorld` near a hex edge resolves to the correct (nearest-center) hex.
- `spawnSlots` returns distinct in-field coords, at least `LOBBY_CAPACITY` of them.
- `HexErosionModel.arm`: stays `nil` when unoccupied; sets `now` on first non-grace occupancy; suppressed (`nil`) while `graceBlocked`; idempotent once armed (re-arming returns the original `steppedAt`).
- `HexErosionModel.phaseAt`: `solid` when `steppedAt nil`; `warning` before `durations.gone`, `gone` at/after it; monotonic (no return to solid for increasing `now`).

### Studio smoke test: `docs/smoke-tests/2026-06-23-hex-a-gone-smoke-test.md` (RUNTIME-UNVERIFIED until run)
2-client procedure:
1. Walk across floor 1 — hexes arm, flash warning, vanish, and do **not** return.
2. Fall through floor 1 → land on floor 2 → continue down the stack → off the lowest (7th) floor → eliminated (crossed `VOID_Y`).
3. Floors 2 and 3 stay pristine until a body is on them.
4. Force a swap (`RoundManager.forceSwap()`) onto an eroded trail; confirm the tile under the freshly-swapped body does **not** drop during the grace window, then arms once grace ends or the body moves.
5. Round ends with a winner; the 3-floor pit reads clearly from the balcony.

## Scope / YAGNI

**Out of scope:** hex MeshPart asset (using composed parts); per-hex sink/shake polish; multiple maps; the deferred economy slice.

## Risks & mitigations

1. **Touching the load-bearing void monitor.** Keep the death + move/grace branches behaviorally identical; the change is additive (gather samples, call `step`). Covered by the smoke test.
2. **Composed-hex collision seams** — a body must stand cleanly on 3 overlapping blocks. Tune part sizes/overlap; verify in the smoke test.
3. **`fromWorld` edge-straddle** — a body between two centers arms the nearest hex, which is acceptable (arming the standing-on hex is the goal).
4. **Part count** — 7 floors × ~37 hexes × 1 MeshPart = 259 parts; negligible at MVP scale.
