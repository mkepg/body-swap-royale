# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2026-07-10]

### Added
- **Mobile jump button — default-replica, comfort-scaled, responsive.** Feel-pass report: the
  touch jump button was too small. Root cause: it was a ContextActionService button (CAS-small,
  ignores the TouchGui form-factor rules); the TRUE default TouchJump can't render here (hard-
  gated on `LocalPlayer.Character`, which the ownership-transfer model never sets). Fixed:
  `InputController` now builds a replica of the default button — same engine sprite-sheet art
  (normal + pressed), same ≤500 px min-axis breakpoint and position formulas (verified against
  the live PlayerModule source) — sized by pure `TouchJumpLayout` (lune-tested) ×
  `Config.TOUCH_JUMP_SCALE = 1.3` (≈91 px phones / 156 px tablets; 1.0 = exact default), re-laid
  out on every viewport change (rotation/resize, camera-replacement safe, no listener stacking).
  Hold tracking follows the initiating touch's InputObject (slide-off releases); the
  `RenderPriority.Last` `humanoid.Jump` re-assert is unchanged; visibility follows the humanoid
  binding like the default thumbstick (hides when spectating, pressed sprite reset on release).
  `TOUCH_JUMP_FORCE` dev flag renders it on desktop for Studio verification. CAS jump button
  fully removed. See [spec](superpowers/specs/2026-07-10-mobile-jump-button-design.md) and
  [plan](superpowers/plans/2026-07-10-mobile-jump-button.md).

## [2026-07-09]

### Added
- **Soul Sweeper v2.4 — hitbox↔visual alignment + arena dim pass.** Feel-pass report: players
  died BEFORE the bar visibly touched them, and the Neon glare hurt readability. Two verified
  causes for the early kills: (A) the v2.3 kill half-widths carried a ~1.5-stud symmetric
  "latency pad" (the LOW bar killed across 4 studs while showing 1); (B) clients render the
  server-owned bars through the replication interpolation buffer (~100 ms), so authoritative-pose
  kills always land AHEAD of the rendered bar (~2.2 studs at spawn radius at base speed, growing
  with the ramp). Fixed: kill bands are DERIVED from the visible mesh (pure
  `SweeperModel.killHalfWidth` = spine half-thickness + `SWEEP_BODY_CONTACT_PAD` 0.5; low
  2.0→1.0, high 3.0→2.0; the hand-tuned KILL_HALF constants are retired — hitbox and mesh share
  one thickness knob and cannot drift), and the strike test runs against the sweep window
  `SWEEP_STRIKE_LAG_TICKS` (1 tick = 100 ms) in the past via a per-beam measured-angle history
  (pure `SweeperModel.delayedWindow`, loud-failing on non-integer lag; warm-up ticks skip the
  test, covered by round-start grace; the anti-tunneling tiling is preserved), so kills land on
  the pose players actually SEE. A flag-gated `SWEEP_LAG_PROBE` measures rendered-vs-authoritative
  lag live to size the tick count. Dim pass: dressing Neon dropped to accent level (rim accent
  0→0.55, wake-lit 0.15→0.5, chase 0.1/0.6→0.4/0.75, rotors 0.35→0.6, shaft 0.7→0.8, lenses
  0.2→0.5); the amber-blade / crimson-underglow kill tells stay full-brightness and gain
  contrast. Verified: 24/24 lune suites. See
  [spec](superpowers/specs/2026-07-09-soul-sweeper-v2_4-hitbox-visual-alignment-design.md)
  and [plan](superpowers/plans/2026-07-09-soul-sweeper-v2_4-hitbox-visual-alignment.md).
- **Soul Sweeper v2.3 — collision fix, round-start formation, beam redesign.** Playtest report:
  the HIGH bar killed standing players and the LOW bar spared them — inverted behavior. **Root
  cause (verified live):** a standing normalized-R15 root sits at **3.001 studs** above the
  surface, a hair over `SWEEP_AIRBORNE_BAND = 3`, so every stander was classified *airborne*
  (clears low / fails high — one threshold, both symptoms). Fixed: `SWEEP_AIRBORNE_BAND = 4.5`
  (measurement recorded in the comment). Also fixed while investigating: (1) the kill zone was an
  **angular** half-width that widened to ~8 studs at the rim — replaced by constant stud
  half-widths (`SWEEP_BEAM_LOW/HIGH_KILL_HALF`, pure `isStruckSwept` converts per body radius;
  regression-tested constant-width property); (2) the on-platform band's symmetric ±6 made a
  jump-apex body (root 10.2) unhittable — now asymmetric via `SWEEP_STAND_BAND_UP = 13`.
  **Round start:** both bars park together at angle 0; players spawn on a 140° arc centered
  opposite (new pure `WorldLayout.arc`, lune-tested) — the first bar arrives in ~4.5 s on top of
  the 1.5 s round-start grace. **Beam redesign:** machine-arm + energy-edge (dark platform-metal
  arms carrying the class read as Neon: amber underside blade on the low bar = "hop over me",
  crimson underglow + end lamps on the high boom = "danger above, stay grounded"); cream stripes,
  the dead angular `overlaps`, and the stripe Config keys retired. Verified: 24/24 lune suites.
- **Soul Sweeper v2.2 — Touch Elimination.** Playtest verdict: physics knockback was unreliable
  in practice — honest players sometimes got "magically teleported off the platform." Root cause:
  the anti-cheat resist backstop misfired when the physics shove failed to clear a body from the
  bar's arc within `SWEEP_RESIST_TICKS`, hard re-pivoting them past the rim. **Directive: stop
  relying on physics knockback entirely.** Beams are now non-collidable (`CanCollide = false`,
  no `CollisionGroup`) deterministic kill zones: a swept-interval strike test on measured poses
  (`SweeperModel.isStruckSwept`, replacing `isStruckAt`) checks whether the bar's arc crossed the
  body's angle since the last tick — anti-tunneling at any ramp speed, with a re-park/teleport
  jump guard (span > 1 rad falls back to the instantaneous check). A struck non-grace body is
  eliminated via the same grace-gated chokepoint as void death (`RoundManager.eliminateFromHazard`)
  — no shove, no re-pivot. Class rules unchanged: jump the low bar, stay grounded under the high
  bar. **Deleted:** the physics knockback + resist backstop (`strikeTicks`, `SWEEP_RESIST_TICKS`),
  validator reseeds (`effects.reseeds`, `SWEEP_RESEED_MARGIN`), the outward re-pivot
  (`SweeperModel.outwardTarget`, `SWEEP_OFF_MARGIN`, `effects.sweeps`), the `SweptAt` client tumble
  (server stamp + `SweeperController.watchTumble` + `SWEEP_TUMBLE_SECONDS` + `ClientControl.getBody`),
  and the entire collision-group system (`ensureCollisionGroups`, `SweepBeam`/`GraceBody` groups,
  `setGraceCollision`/`clearAllGraceCollision`, the floor probe's `GraceBody` ray group) — all
  existed solely for physical beam↔body interaction, which no longer happens. `SWEEP_BEAM_DENSITY`
  also retired (density only mattered for contact impulses). **Added:** round-start grace —
  `RoundManager.beginRound` now stamps the standard grace window for every participant (the
  2026-07-03 review recommendation, now load-bearing: with instant kill, a player spawned near a
  parked bar's angle would otherwise die in second one with zero warning); side effect on hex:
  spawn tiles don't arm for the first `GRACE_SECONDS` either (review-endorsed). With physics
  knockback gone, the movement validator no longer needs beam-zone exceptions — full validator
  coverage is restored platform-wide (no rubber-banding anywhere during normal play). Verified:
  24/24 lune suites. See [spec](superpowers/specs/2026-07-09-soul-sweeper-v2_2-touch-elimination-design.md)
  and [plan](superpowers/plans/2026-07-09-soul-sweeper-v2_2-touch-elimination.md).
- **Soul Sweeper v2.1 — "Jump Club" refinement.** Platform scaled up (`SWEEP_PLATFORM_RADIUS 38→52`,
  `SWEEP_HOLE_RADIUS 10→12`, `SWEEP_HUB_RADIUS 5→6`, anchor offset); true-circle visual via client
  EditableMesh annulus over densified invisible-locally 48-segment collision ring (0.1 stud max
  deviation; `LocalTransparencyModifier = 1` hides server segments when available; fallback: segments
  stay visible). Telegraph arcs removed entirely (readability restored: the two chunky physical bars
  + wake channels are the sole visual feedback). Beams rebuilt as solid striped machine-bar
  assemblies: unanchored welded parts driven by `HingeConstraint` motors on an anchored hub axle
  (real angular velocity → real contact impulses → players flung naturally and consistently). Low
  beam thin (~1×1 cross-section, bottom at 0.6 studs: jumpable); high beam thick (~3×3, bottom at
  5.5 studs: the grounded-clearance knob). Alternating colored segments (cream/amber and cream/crimson
  stripes, `SmoothPlastic`, no Neon). Server-owned physics (`SetNetworkOwner(nil)`); server updates
  motor `AngularVelocity` each 10 Hz monitor tick via `rampedSpeed` (the ramp survives; the v2
  Heartbeat CFrame stepping is deleted). Strike backstop and client wake cosmetics now read each beam's **measured**
  angle from its replicated physical pose (`atan2` of bar-center offset from hub) via new pure
  `SweeperModel.isStruckAt` (replaces elapsed-based `isStruck` — the yaw-sign risk class is retired
  entirely: geometry, physics, authority, and cosmetics observe one physical object). Verified: 24/24
  lune suites. Live verification + MCP asset sourcing pending (Task 6).

## [2026-07-08]

### Added
- **Soul Sweeper v2 — "Soul Turbine" arena rework + persistent two-arena world.** Rebuilt the sweeper
  as a single annulus platform around a central turbine hub; two solid stacked beams (low amber = JUMP,
  high crimson = STAY GROUNDED) server-animated from `SweeperModel` angles every Heartbeat, colliding
  naturally via anchored parts and PhysicsService collision groups. Persistent world: all arenas built
  at startup and permanently visible; per-round rotation via pure `ArenaRotationModel` (lune-tested)
  picks the live arena, `Config.ARENA_OVERRIDE` pins one for testing. Grace bodies (post-swap) use
  collision groups to pass through beams; backstop anti-cheat forces a sweep after 3 ticks of resist.
  MovementValidator reseeds bodies in beam arcs (no rubber-band during legitimate shoves). Client
  rewrote `SweeperController` as single shared Heartbeat loop (telegraph, wake channels, rotor rings,
  chase lights) fully gated on `workspace:GetAttribute("LiveArena")` — dormant arenas cost zero
  per-frame writes (beams parked, cosmetics dimmed one-time). `ArenaHazard` interface gains `id` +
  `spawnCFrame(index)` for per-round slot assignment via `BodyManager.setArenaSlot`. New `ArenaDescriptor.all()`
  for multi-arena dressing. Soul Turbine art pass: procedural annulus + hub + 28-segment floor + wake
  channels + rotor + light shaft + marquee chase + under-structure + spotlights (137 parts, ≤180 budget);
  three Config-gated sourced asset slots (disc/beam materials, hub mesh) with procedural fallbacks.
  Verified: 24/24 lune suites. Studio verification + asset sourcing (Tasks 9–10) pending.

## [2026-07-07]

### Added
- **Soul Sweeper arena (Arena #2)** — Fall Guys "Jump Club" adapted to the swap loop, playable
  behind a new `ArenaHazard` interface with Hex refactored to sit behind the same interface. Pure,
  lune-tested `SweeperModel` decides beam geometry and strikes from plain numbers. Server
  `SweeperHazard` builds stacked downward-widening collision discs, samples every body at 10 Hz,
  and returns outward re-pivot "sweep" requests that `RoundManager` applies. Beams are cosmetic
  (client-rendered, server-time-synced); death stays geometric via the existing grace-gated void
  monitor. Sweeper-specific tunables in `Config.SWEEP_*` block; `Config.ACTIVE_ARENA` selector
  (default `"hex"`). Server geometry: procedural discs + central emitter hubs. Cosmetic layer:
  rotating low (amber: JUMP) and high (red: STAY GROUNDED) beams with faded leading telegraph bars.
  Client tumble on sweep via `SweptAt` attribute stamp. Verified: 23/23 lune suites (pure model +
  hex regression). Procedural build complete; hybrid asset layer (materials + one-hero-mesh)
  pending MCP asset sourcing. Live glue verification + smoke test deferred to Task 15.

## [Unreleased]

### Added
- **Swap-preview directional ping + centralized first-session hints (review Action #7, partial).**
  The preview now guides the eye to an off-camera target — an on-target chevron when it's framed, a
  screen-edge arrow that points toward it (incl. behind-camera) otherwise — via the pure, lune-tested
  `PingDirectionModel` (`SwapPreviewController` rewrite; keeps the amber Highlight). New centralized,
  data-driven hint system decodes the swap for first-timers: `HintRegistry` (rows) + pure `HintModel`
  (`tests/hint_model.spec.luau`) + server-authoritative `HintService` (fires from `RoundManager`;
  no client→server remote) + client `HintController` rendering labels ANCHORED to the player's current
  body during the preview (the ping points to the target) then the Soul halo after the swap
  ("this is you"), once-ever per player via persisted
  `profile.seenHints` (migration-safe, no `PROFILE_VERSION` bump). Tunables in `Config.PING_*` /
  `Config.HINT_*`. Verified: 22/22 lune suites + Studio-MCP glue checks (clean boot/no require cycle,
  `ShowHint` delivery, anchored-label render, `PingDirectionModel` real-VM parity); manual 2-client
  cases pending in `docs/smoke-tests/2026-07-05-preview-ping-hints-smoke-test.md`. Deferred (recorded
  in the spec): danger read, round-start grace, tutorial round, richer hint set.
- **MVP movement validation (server-authoritative anti-cheat).** The 10 Hz void monitor now
  rubber-bands any owned body whose motion is physically impossible — horizontal/vertical
  displacement beyond walk/jump physics (speed, teleport, fly-up) or hovering over the void with no
  floor beneath — snapping it to its last valid grounded pose via reposition-then-re-own. Pure decision
  in `src/shared/MovementValidator.luau` (displacement clamp + anti-hover + a 5-tick debounce so honest
  laggy players are never corrected; lune-tested `tests/movement_validator.spec.luau`); glue in
  `RoundManager.startMonitor` reuses the doom-exclusion `hasFloorBeneath` probe. Validates EVERY owned
  body (alive + eliminated), so an eliminated player can no longer teleport their balcony body back into
  the arena. Closes the "an exploiter literally cannot lose" gap (review 2026-07-03 §3.2 / Action #6).
  Tunables in `Config.MOVE_*`; smoke test `docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md`.
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
  - **Centre-tile negative-zero fix (2026-06-25):** `HexGrid.fromWorld(0, 0, *)`
    returned `q=0, r=-0`. Lua treats `-0 == 0` numerically, so the lune round-trip
    test passed, but `tostring(-0) == "-0"` differs from `"0"`, so HazardSystem's
    string-keyed `tileByKey["floor:q:r"]` lookup silently missed the centre tile of
    every floor — the player assigned the centre spawn slot could never arm the hex
    they were standing on (the "tile doesn't turn red on first contact" bug). Fixed
    by canonicalising `-0` → `0` in `cubeRound` (`return rx + 0, rz + 0`). Added a
    regression test that checks `tostring` of the returned coords, since numeric
    equality alone doesn't catch this class of bug.
  - **Wedge-composed tile fallback (2026-06-25):** the EditableMesh path silently
    no-ops in this place because Experience Settings > Security > Allow Mesh/Image
    Access is off — `pcall` returns ok but the resulting `MeshPart` has no triangles,
    so it rendered as its rectangular AABB (the "squares with gaps" bug). `HazardSystem`
    now composes each tile from **5 stock parts** (1 central `Block` + 4 `WedgePart`
    end-caps) that meet edge-to-edge with NO overlap. Cap rotations derived from a
    Studio probe so each wedge's slanted face lies flat on top with the right-angle
    pointing inward to the hex center; the 4 triangles + central block tile the
    hexagon exactly. Stock parts only — guaranteed to render. `HexPrism` is retained
    (and still lune-tested) for the future EditableMesh path if the security setting
    is enabled later.
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
- **Bodiless spawn, residual holes (2026-07-05).** The 2026-07-03 defense-in-depth fix
  still let the camera-only join recur intermittently because two spots in the join
  pipeline had NO self-healing:
  - **Dead cached camera (client).** `ClientControl` and `ClientRoundHud` cached
    `workspace.CurrentCamera` once at require time — the earliest moment of a cold join,
    exactly when the engine can still replace the startup camera instance. Every retarget
    (spawn, reconcile, per-frame subject write, spectate) then landed on the destroyed
    camera while the player watched the new one: a permanent camera-only spawn with a
    perfectly healthy server, invisible to all four server-side healing layers.
    (`SwapPreviewController` already read the camera live — the inconsistency was the
    tell.) Both modules now read `workspace.CurrentCamera` live at every use, and the
    per-frame re-assert also restores `CameraType.Custom`, so a mid-session camera
    replacement heals within a frame.
  - **Re-embodiment sweep blind to broken bodies (server).** The sweep only retried when
    `getOwnBody(p) == nil`, a weaker health check than the round gate's `hasValidBody`.
    A registered body whose parts were destroyed outside our control — concretely: a
    grace-shielded straight fall from the lowest hex floor reaches the engine's
    `FallenPartsDestroyHeight` (−500) in ~1.43 s, inside the 1.5 s grace window, before
    the void monitor may eliminate it — left a rootless wreck that satisfied the sweep's
    check forever: its controller stranded camera-only AND unkillable (no root ⇒ no void
    check ⇒ the round could hang). The sweep now validates registered bodies with the new
    `BodyManager.isIntact` and heals a wreck via `healBrokenBody`: eliminate the rider
    (idempotent void-death semantics, un-hangs the round), eliminate the owner if alive
    elsewhere, tear down through the lune-tested `ControlModel.removePlayer` absorb rule
    (parking a reassigned rider on their balcony slot, reposition-then-re-own), then
    rebuild the owner like a late joiner.
  - Hardening: `Workspace.FallenPartsDestroyHeight` → −50000 (project file) so the
    engine can never dismember a falling body before the 10 Hz monitor catches it (all
    falling bodies are managed; nothing relies on engine part-GC).
  - The client's `SetControlledBody` handler no longer errors when the fire outruns the
    body's replication (nil argument): it logs and defers to the attribute reconcile.
  - New client watchdog: if a player sits bodiless > 5 s (never legitimate), it warns
    naming the failing layer (Bodies folder missing vs. no `ControllerUserId` match), so
    any future recurrence self-identifies instead of needing a fresh investigation.
  Smoke test: `docs/smoke-tests/2026-07-05-bodyless-spawn-residual-smoke-test.md`.
- Elimination now re-asserts network ownership after `sendToLobby` (uniform reposition-then-re-own,
  review Action #4) so the balcony teleport replicates reliably onto a fast-falling client-owned body.
- `ClientAnimator.register` retries until a body's Humanoid replicates (review Action #5), fixing bodies
  that could go permanently un-animated on a cold join when the rig lagged a frame behind `ChildAdded`.
- **First-join bodiless spawn (camera-only, round won't start) (2026-07-03).**
  Players have no `Character` (`CharacterAutoLoads = false`); each is a disembodied
  controller given a server-built body. Intermittently — most often on a first join —
  a player was left with only a camera, no body, and the round would not start even at
  the minimum player count. Root-caused to four independent, first-join-amplified fault
  paths and fixed with defense-in-depth:
  - **Total body build.** `BodyManager.buildAvatarBody`'s fallback rig build was NOT
    pcall-guarded; when the primary avatar build failed (a correlated avatar/asset-service
    outage), the fallback could also throw, `buildAvatarBody` returned nil, and
    `createBody` crashed indexing `body.Name` — aborting the whole join. It now guards
    both build branches, retries a bounded number of times with backoff, never throws,
    and `createBody`/`RoundManager.addPlayer` tolerate a nil body (log + skip registration,
    no crash). Also drops a body/slot if the player disconnects during the longer build.
  - **Self-healing control assignment.** The `SetControlledBody` RemoteEvent is
    fire-and-forget and was the client's ONLY path to learn its body; the server fires it
    from `PlayerAdded`, often before the client's handler is connected (cold first join),
    so a dropped event stranded the client camera-only with no recovery. The server now
    stamps an authoritative `ControllerUserId` attribute on the body at the single
    ownership choke point (`ControlManager.applyOwnership`), and clients (`ClientControl`,
    `SoulController`) self-heal by re-acquiring the body whose `ControllerUserId` matches
    their own UserId — so a lost assignment (spawn or swap) reconciles within a frame.
  - **Decoupled embodiment from economy.** Body creation was serialized behind
    `EconomyService.onPlayerAdded`'s yielding, retry+backoff DataStore load (seconds on a
    throttled first-join key). The economy load now runs on its own thread
    (`task.spawn`), so embodiment is never gated behind persistence.
  - **Re-embodiment net.** `RoundManager.addPlayer` is now idempotent + re-entrancy-safe
    (an `addInProgress` guard around the yielding build), and a pcall-isolated periodic
    sweep (`Config.BODY_RECONCILE_SECONDS`) re-embodies any connected-but-bodiless player
    as a last resort — arena-/phase-agnostic, so a first-join failure self-heals instead
    of stranding the player.
- Disconnect handling no longer destroys a leaving player's avatar body
  unconditionally. After a swap that body may be controlled by another player;
  the old code yanked them and orphaned the leaver's controlled body.
  `ControlManager.removePlayer` now applies an "absorb" rule (move the other
  controller onto the vacated body, then destroy the leaver's body), preserving
  the controllers↔bodies bijection. Derangement moved from `SwapController` into
  `ControlModel.derange`.

### Removed
- `src/shared/Hello.luau` — generated placeholder module.
