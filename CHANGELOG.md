# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
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
- `src/server/init.server.luau` — bootstraps the swap mechanic: disables
  `CharacterAutoLoads`, spawns each player a body, assigns initial control, and
  starts the swap loop.
- `src/client/init.client.luau` — bootstraps the client control and animation
  drivers.
- `default.project.json` — explicitly set `Workspace.StreamingEnabled = false`.
  With no player `Character` there is no streaming focus, so streaming withholds
  all spatial parts and clients render only the skybox (GDD §15).

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
