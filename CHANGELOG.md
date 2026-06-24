# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Hex-A-Gone arena** (replaces the time-driven square disappearing-tile floor):
  - **Rendering + depth revision (2026-06-24):** each tile is now ONE true
    hexagonal-prism `MeshPart` (built once via `AssetService` EditableMesh from the
    new pure `src/shared/HexPrism.luau`, then cloned) — fixes the inter-tile gaps and
    the z-fighting when a stepped tile recolored. `HexPrism.build` returns vertex +
    triangle lists with computed-outward face normals, lune-tested
    (`tests/hex_prism.spec.luau`). Floors raised to **7** (`HEX_FLOOR_COUNT`), each a
    **distinct color** (`HEX_FLOOR_COLORS`). Tiles tuned to a fine honeycomb matching
    the reference look: smaller + more (`HEX_SIZE` 6 → 4, `HEX_RADIUS` 3 → 5 = 91
    tiles/floor), each rendered/collided **inset** by `HEX_GAP` (0.3) from the lattice
    so distinct tiles leave a thin grout seam with zero coincident geometry (kills the
    residual edge z-fighting). Vertical separation widened hard (`HEX_FLOOR_GAP` 10 →
    50; `VOID_Y` → -304). Retired `TILE_COLOR_SOLID`.
  - `src/shared/HexGrid.luau` — pure, Roblox-free flat-top hex geometry (`tiles`,
    axial↔world `toWorld`/`fromWorld` via cube-rounding, outward-spiral
    `spawnSlots`, vertical `floorAt` banding). Number-in/number-out like
    `SpawnLayout`; unit tested with lune (`tests/hex_grid.spec.luau`).
  - `src/shared/HexErosionModel.luau` — pure, Roblox-free step-driven erosion
    (`arm` → grace-gated, idempotent erosion start; `phaseAt` → monotonic
    `solid`/`warning`/`gone`). Supersedes the cyclic `TileFieldModel`; unit tested
    with lune (`tests/hex_erosion_model.spec.luau`).
  - `src/server/HazardSystem.luau` — rewritten to build the arena as **three
    stacked hexagonal floors** (each hex = 3 rotated `Block` parts; replaces the
    baseplate) and erode them step-driven: a hex arms when a body stands on it,
    warns, then vanishes for good. Driven per-tick by `RoundManager`'s void monitor
    via `step(now, samples)` (one server loop). Falling lands you on the floor
    below; only a fall off the lowest floor crosses `Config.VOID_Y` → the existing
    grace-gated void monitor (no new death path). The hex under a freshly-swapped
    body won't arm until its grace ends.
  - `Config` hex tunables (`HEX_RADIUS`, `HEX_SIZE`, `HEX_FLOOR_COUNT`,
    `HEX_FLOOR_GAP`, `HEX_STAND_BAND`, `HEX_GONE_DELAY_SECONDS`; reused
    `TILE_SURFACE_Y`/`TILE_THICKNESS`/`TILE_COLOR_SOLID`/`TILE_COLOR_WARNING`).
  - `BodyManager` round-start spawns now land on hex centers
    (`HexGrid.spawnSlots`) on the top floor; `Config.VOID_Y` relocated to `-24`
    (below the lowest hex floor). Removed `TileFieldModel` and the square-tile
    `Config` fields (`TILE_SOLID_SECONDS`/`TILE_WARNING_SECONDS`/`TILE_GONE_SECONDS`/
    `TILE_GRID_SIZE`/`TILE_SIZE`/`ARENA_PER_ROW`/`ARENA_SPACING`).
- `src/shared/GraceModel.luau` — pure, Roblox-free post-swap grace state machine
  (per-player `graceUntil`/`graceMinFloor`/`hasMoved` + `canDieFromHazard`,
  TDD §2). Time-agnostic like `RoundState`/`ControlModel`; unit tested with lune
  (`tests/grace_model.spec.luau`).
- `Config.GRACE_MOVE_EPSILON` — horizontal displacement that ends the grace window
  early once the player has oriented.
- `src/server/RoundManager.luau` — server glue driving the MVP win/lose loop:
  sequences `Lobby → Active → Ended → reset` on real clocks, gates swaps to the
  Active phase (roster = `RoundState`'s alive set), runs a void death monitor that
  logically eliminates a body crossing `Config.VOID_Y` (parked, never killed), and
  broadcasts phase/elimination/spectate to clients. Declares a winner.
- `src/client/ClientRoundHud.luau` — minimal round feedback (lobby countdown,
  "You were eliminated", "Winner: <name>") plus spectator-camera retarget.
- `ControlModel.resetControl` — pure op returning every player to their own avatar
  body with a rebuilt bijection (lune-tested); used at each round start.
- `Config.LOBBY_COUNTDOWN_SECONDS` / `Config.ROUND_END_SECONDS` / `Config.VOID_Y`.
- `RoundStateChanged` / `EliminationEvent` / `SpectateBody` remotes.
- `src/shared/RoundState.luau` — pure, Roblox-free round-lifecycle state
  machine (phase `Lobby`/`Active`/`Ended`, present/alive sets, winner). Auto-ends
  when fewer than `Config.MIN_PLAYERS_TO_CONTINUE` remain alive; last one standing
  wins, 0 alive aborts to lobby. Time-agnostic and event-driven like
  `ControlModel`; unit tested with lune (`tests/round_state.spec.luau`).
- `Config.MIN_PLAYERS_TO_START` / `Config.MIN_PLAYERS_TO_CONTINUE` (both default 2).
- `src/shared/ControlModel.luau` — pure, Roblox-free controllers↔bodies state
  machine (spawn / swap / disconnect) maintaining a player↔body bijection. Unit
  tested from the terminal with lune (`tests/control_model.spec.luau`).
- `rokit.toml` — toolchain pinning `lune` (terminal Luau tests) and `rojo`.
- Core body-swap mechanic (ownership-transfer model) ported into the new
  project structure:
  - `src/shared/Config.luau` — single source of truth for tunables (cycle/grace
    timing, normalized avatar scales, walk/jump, spawn layout, R15 animation IDs).
  - `src/shared/Remotes.luau` — runtime creation/lookup of the
    `SetControlledBody` RemoteEvent (replaces the old hand-placed instance, since
    this is a Rojo project with no instance model files).
  - `src/server/BodyManager.luau` — one persistent avatar body per player
    (normalized dimensions), parented to `workspace.Bodies`; never a player's
    `Character`.
  - `src/server/ControlManager.luau` — grants control via `SetNetworkOwner` and
    notifies the owning client.
  - `src/server/SwapController.luau` — Sattolo single-cycle derangement and the
    30-second swap loop.
  - `src/client/ClientControl.luau` — WASD + jump input driving the owned body
    (`Humanoid:Move`, client-predicted), camera retarget, and the 0.3s FOV punch
    on swap.
  - `src/client/ClientAnimator.luau` — per-client, per-body, velocity-driven
    animation (GDD v1.3 model); required because bodies are not `Character`s and
    the default `Animate` cannot drive them.

### Changed
- `Config.VOID_Y` raised from `-50` to `-4` so it sits just under the tile floor;
  falling through a vanished tile is now a quick, grace-protectable death.
- Removed the `Baseplate` from `default.project.json`; the tile field is the floor.
- `src/server/RoundManager.luau` — builds the tile-field arena once at startup
  (`HazardSystem.build()`), starts it driving at round begin (`HazardSystem.start`)
  and freezes it solid at round end (`HazardSystem.stop()`).
- `src/server/init.server.luau` — bootstraps the swap mechanic: disables
  `CharacterAutoLoads`, spawns each player a body, assigns initial control, and
  starts the swap loop.
- `src/client/init.client.luau` — bootstraps the client control and animation
  drivers.
- `default.project.json` — explicitly set `Workspace.StreamingEnabled = false`.
  With no player `Character` there is no streaming focus, so streaming withholds
  all spatial parts and clients render only the skybox (GDD §15).
- `src/server/SwapController.luau` — no longer owns a loop or an eligibility
  filter; `swap(orderedAlive)` performs one swap over the roster RoundManager
  passes. RoundManager decides *when*, RoundState decides *who*.
- `src/server/init.server.luau` — routes join/leave through RoundManager and
  starts the round loop instead of the old unconditional swap loop.
- `src/server/BodyManager.luau` — added `resetBody` (round-start reposition) and
  `parkBody` (anchor an eliminated body), with per-owner spawn-CFrame storage.
- `src/server/RoundManager.luau` — routes the void death through a new
  `eliminateFromHazard` gate that consults `GraceModel` (stamped on each swap),
  and derives `HasMovedSinceSwap` from horizontal travel in the void monitor.
  Inherited bodies are protected from hazard death for the post-swap grace window
  (GDD §4). Disconnect elimination remains ungated.

### Fixed
- Disconnect handling no longer destroys a leaving player's avatar body
  unconditionally. After a swap that body may be controlled by another player;
  the old code yanked them and orphaned the leaver's controlled body.
  `ControlManager.removePlayer` now applies an "absorb" rule (move the other
  controller onto the vacated body, then destroy the leaver's body), preserving
  the controllers↔bodies bijection. Derangement moved from `SwapController` into
  `ControlModel.derange`.

### Removed
- `src/shared/Hello.luau` — generated placeholder module.
