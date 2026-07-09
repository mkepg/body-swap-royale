--[[
	Config
	Location: ReplicatedStorage/Shared/Config  (ModuleScript)
	Single source of truth for tunable values. Shared by server and client.
--]]

local Config = {}

-- Round timing (used from step 5/6 onward)
Config.PREVIEW_SECONDS = 3

-- Dynamic swap cadence. The swap interval is no longer fixed: the pure CadenceModel
-- compresses it from CADENCE_MAX_INTERVAL (calm round-start) toward
-- CADENCE_MIN_INTERVAL (frantic endgame), driven by alive-count + round progress.
-- INVARIANT: CADENCE_MIN_INTERVAL MUST stay > PREVIEW_SECONDS so the 3s preview
-- window always fits inside the shortest cycle.
Config.CADENCE_MAX_INTERVAL = 20   -- round-start ceiling (seconds)
Config.CADENCE_MIN_INTERVAL = 8    -- endgame floor (seconds)
Config.CADENCE_SWAPS_TO_FLOOR = 8  -- swaps for the stall-breaker (progress term) to reach the floor
Config.CADENCE_STALL_WEIGHT = 1.0  -- progress-term weight; 1.0 so the ramp still works at N=2
Config.GRACE_SECONDS = 1.5
Config.GRACE_FLOOR_SECONDS = 0.5
-- Horizontal studs of displacement since the last swap that counts as the player
-- having "oriented", ending the post-swap grace window early (the
-- GRACE_FLOOR_SECONDS hard floor still applies first). At WALK_SPEED (16) a body
-- covers ~1.6 studs per 0.1s monitor tick, so 0.5 detects intentional movement
-- quickly while ignoring sampling jitter. Vertical fall does not count.
Config.GRACE_MOVE_EPSILON = 0.5

-- RoundManager loop tunables (server-owned clocks).
-- LOBBY_COUNTDOWN_SECONDS: pre-round countdown once enough players are present.
-- ROUND_END_SECONDS: winner-display window before resetting to Lobby.
Config.LOBBY_COUNTDOWN_SECONDS = 5
Config.ROUND_END_SECONDS = 5
-- (VOID_Y is defined with the hex floor params below, since it tracks the lowest floor.)

-- Hex-A-Gone arena floor. Seven stacked hexagonal floors; a hex arms the instant a
-- body stands on it, flashes the warning color for HEX_GONE_DELAY_SECONDS, then
-- vanishes for good (monotonic -- no return that round). Pure decisions live in
-- HexGrid (geometry) + HexErosionModel (arm/phase) + HexPrism (tile mesh); HazardSystem
-- builds one true hexagonal MeshPart per tile (EditableMesh, no gaps / no z-fighting)
-- and maps phase -> part props. HAZARDS_ENABLED: dev/test switch (NOT a gameplay
-- tunable). When false, floors build but never arm (stay solid), so swaps can be
-- observed without bodies falling.
Config.HAZARDS_ENABLED = true
Config.HEX_RADIUS = 5            -- rings from center; drives the spawn spiral (spawnSlots).
                                 -- The pit FIELD is a CIRCLE now (see HEX_CIRCLE_RADIUS), not the hexagon.
Config.HEX_SIZE = 4              -- LATTICE hex circumradius (tile centers + occupancy lookup); small
Config.HEX_CIRCLE_RADIUS = 30   -- the pit is a TRUE CIRCLE: hex tiles clipped to this world
                                 -- radius (HazardSystem) -> ~68 tiles/floor; the edge trim hugs it.
                                 -- tiles -> many distinct hexagons, ~one body per tile
Config.HEX_GAP = 0.3            -- studs each tile is INSET from the lattice radius, so neighbors
                                 -- don't touch: a THIN grout seam between tiles + zero coincident
                                 -- geometry (no z-fighting). Rendered/collided radius = HEX_SIZE - HEX_GAP.
Config.HEX_FLOOR_COUNT = 7       -- stacked floors
Config.HEX_FLOOR_GAP = 50        -- vertical studs between floors (floors at 0/-50/.../-300)
-- A controlled body whose root falls below this Y is eliminated (grace-gated, via the
-- void monitor). Computed to sit 4 studs under the LOWEST floor, so only a body that
-- falls off the bottom floor dies (an upper-floor fall lands on the next floor down).
-- Stays above Workspace.FallenPartsDestroyHeight (default -500).
Config.VOID_Y = -(Config.HEX_FLOOR_COUNT - 1) * Config.HEX_FLOOR_GAP - 4
Config.HEX_STAND_BAND = 6        -- root-height window above a floor that counts as "on" it
                                 -- (must be < HEX_FLOOR_GAP so floor bands don't overlap)
Config.HEX_GROUND_PROBE_RADIUS = 1.5 -- contact-probe sphere radius (studs): the downward
                                     -- spherecast that finds which tile a body stands on. >0 so a
                                     -- body over the HEX_GAP grout seam still hits its tile; keep it
                                     -- well under the tile radius (HEX_SIZE - HEX_GAP) so it never
                                     -- catches a neighbor.
Config.HEX_GONE_DELAY_SECONDS = 1.2 -- step -> gone delay (warning color shows the whole time)
Config.TILE_SURFACE_Y = 0        -- top-floor surface Y (reused by HazardSystem + spawn)
Config.TILE_THICKNESS = 1        -- hex part thickness
Config.TILE_COLOR_WARNING = Color3.fromRGB(200, 40, 40)   -- alarm red (armed/imminent)
-- One distinct solid color per floor (top -> bottom), so depth reads at a glance.
-- Indexed by floor+1 (floor is 0-based). Length MUST be >= HEX_FLOOR_COUNT. The
-- warning red above is deliberately kept out of this palette so "about to drop" is
-- never confused with a floor color.
Config.HEX_FLOOR_COLORS = {
	Color3.fromRGB(245, 200, 70),   -- 1 amber (top)
	Color3.fromRGB(140, 210, 90),   -- 2 green
	Color3.fromRGB(70, 200, 180),   -- 3 teal
	Color3.fromRGB(80, 160, 240),   -- 4 blue
	Color3.fromRGB(150, 120, 235),  -- 5 indigo
	Color3.fromRGB(215, 110, 225),  -- 6 magenta
	Color3.fromRGB(120, 120, 140),  -- 7 slate (bottom)
}

-- ===== Arena selection =====
-- Rounds ROTATE between arenas (pure ArenaRotationModel). ARENA_OVERRIDE pins one
-- arena for dev/testing ("hex" | "sweeper"); "" = rotate. Replaces the v1
-- ACTIVE_ARENA build switch: ALL arenas are always built (persistent world).
Config.ARENA_OVERRIDE = ""

-- ===== Soul Sweeper arena v2.2 -- "Soul Turbine" touch elimination (see
-- 2026-07-09 v2.2 spec) =====
-- One annulus platform around a central turbine hub; two beams (low amber =
-- JUMP, high crimson = STAY GROUNDED) are non-collidable deterministic
-- touch-elimination zones -- a struck non-grace body dies via the grace-gated
-- hazard chokepoint (RoundManager.eliminateFromHazard), no shove/knockback.
-- Motors still physically spin the (non-collidable) assemblies for the
-- visual. Fall off the rim or into the hub gap -> void.
Config.SWEEP_CENTER = Vector3.new(140, 0, 0) -- platform center (hex stays at origin)
Config.SWEEP_SURFACE_Y = 0
Config.SWEEP_PLATFORM_RADIUS = 52   -- outer rim
Config.SWEEP_HOLE_RADIUS = 12       -- center hole (gap ring = HUB..HOLE radius)
Config.SWEEP_HUB_RADIUS = 6         -- turbine pillar inside the hole
Config.SWEEP_PLATFORM_SEGMENTS = 48 -- tangent boxes approximating the annulus
Config.SWEEP_SEGMENT_SLACK = 1.08    -- segment length vs chord (overlap => no seams)
Config.SWEEP_PLATFORM_THICKNESS = 2
Config.SWEEP_PLATFORM_COLOR = Color3.fromRGB(20, 26, 48)   -- dark glass/metal indigo
Config.SWEEP_ACCENT = Color3.fromRGB(244, 162, 97)         -- turbine amber
Config.SWEEP_VOID_Y = Config.SWEEP_SURFACE_Y - 24 -- kill-plane (a visible fall beat)
Config.SWEEP_STAND_BAND = 6          -- Y band BELOW the surface that counts as "on" it
                                     -- (below this = fallen into the gap; see STAND_BAND_UP for above)
-- Upper on-platform band: must exceed the jump-apex root height (10.2 = measured
-- standing root 3.0 + JUMP_HEIGHT 7.2) so a jumper stays strikeable at apex; the
-- asymmetric lower SWEEP_STAND_BAND above still skips a body fallen below the surface.
Config.SWEEP_STAND_BAND_UP = 13
Config.SWEEP_SPAWN_RADIUS = 32      -- spawn ring (mid-annulus)
-- Round-start spawn arc: players cluster on the FAR side from where both beams park
-- (angle 0 -- see SWEEP_BEAMS below), a 140-degree arc centered on angle pi.
Config.SWEEP_SPAWN_CENTER_ANGLE = math.pi
Config.SWEEP_SPAWN_ARC = math.rad(140)

-- The two beams (flat list -- one platform). Each: baseAngle, direction, baseSpeed
-- (rad/s), armCount, class. Radius band + kill half-width attached at build time.
-- Both bars PARK TOGETHER at angle 0 (spec v2.3 SS2-4); players spawn on the
-- opposite arc (SWEEP_SPAWN_CENTER_ANGLE/ARC above). They still rotate opposite
-- directions at different speeds, so they sweep apart and converge on the far side.
Config.SWEEP_BEAMS = {
	{ baseAngle = 0, direction = 1, baseSpeed = 0.7, armCount = 1, class = "low" },
	{ baseAngle = 0, direction = -1, baseSpeed = 0.55, armCount = 1, class = "high" },
}
-- Constant stud half-width of each bar's kill band = visible half-thickness +
-- body/latency pad. Replaces the old angular half-width (v2.2), whose physical
-- width grew with radius (~2 studs near the hub, ~8 studs at the rim). Tuning knobs.
Config.SWEEP_BEAM_LOW_KILL_HALF = 2.0
Config.SWEEP_BEAM_HIGH_KILL_HALF = 3.0
Config.SWEEP_SPEED_RAMP_PER_SEC = 0.02
Config.SWEEP_SPEED_MAX = 2.5
-- Measured 2026-07-09: a standing normalized-R15 root sits 3.001 studs above the
-- surface it stands on; 4.5 requires ~1.5 studs of real jump (apex = 10.2). Re-derive
-- if NORMALIZED_SCALES change.
Config.SWEEP_AIRBORNE_BAND = 4.5
Config.SWEEP_AIRBORNE_VY = 8

-- Solid machine-bar beams (Jump Club idiom): unanchored welded assemblies driven by
-- HingeConstraint motors on the hub axle (spec 2026-07-09 §2-4/§2-6). BOTTOM faces are
-- the gameplay knobs: the low bar must be jumpable, the high bar must clear a grounded
-- body. Stripes are alternating welded segments (no textures needed).
Config.SWEEP_BEAM_LOW_BOTTOM = 0.6    -- low bar underside (jumpable; top = bottom + thickness)
Config.SWEEP_BEAM_LOW_THICKNESS = 1
Config.SWEEP_BEAM_HIGH_BOTTOM = 5.5   -- high bar underside: THE grounded-clearance knob
Config.SWEEP_BEAM_HIGH_THICKNESS = 3
Config.SWEEP_BEAM_STRIPES = 6         -- alternating colored segments per bar
Config.SWEEP_BEAM_STRIPE_COLOR = Color3.fromRGB(245, 238, 220) -- warm cream (both bars)
Config.SWEEP_BEAM_MOTOR_TORQUE = 1e9  -- players can never stall a bar
Config.SWEEP_HUB_TOP = 10             -- hub pillar top (studs above surface; axle must
                                      -- reach past the thick bar's top at 5.5+3)
Config.SWEEP_BEAM_LOW_COLOR = Color3.fromRGB(244, 162, 97)  -- amber: JUMP
Config.SWEEP_BEAM_HIGH_COLOR = Color3.fromRGB(225, 75, 75)  -- crimson: STAY GROUNDED

-- Soul Turbine dressing (client; budgets: <=180 parts, one shared loop, <=40 writes/frame).
Config.SWEEP_WAKE_CHANNELS = 36      -- radial floor strips igniting in the low beam's wake
Config.SWEEP_CHASE_STUDS = 32        -- rim marquee chase lights
Config.SWEEP_STANDBY_TRANSPARENCY = 0.85 -- dormant-arena Neon dim (one-time flip)

-- ===== Hybrid assets (each with a code-only fallback) =====
-- SWEEP_DISC_MATERIAL: a MaterialVariant NAME resolved against the place's
-- MaterialService (sourced via Studio MCP 2026-07-09; alternate takes parked in
-- MaterialService.AssistantMaterials). A variant only renders when the part's
-- Material equals its BaseMaterial, hence the *_BASE key. "" => stock Glass look.
Config.SWEEP_DISC_MATERIAL = "SweeperStageFloor"
Config.SWEEP_DISC_MATERIAL_BASE = "Metal"
-- (v2.1: the beams are solid striped SmoothPlastic machine bars now -- the old Neon
-- beam-material slot was retired with the light-beam look.)
-- The hub hero mesh is PRESENCE-based, not ID-based: the client clones
-- ReplicatedStorage.SweeperAssets.HubMesh when it exists. That folder lives in the
-- place file, OUTSIDE Rojo's ReplicatedStorage.Shared mapping, so syncs never touch
-- it. Absent => the procedural hub pillar + rotor rings stand alone.

-- Round population thresholds (consumed by RoundState via the server glue).
-- MIN_PLAYERS_TO_START gates beginning a round; default 2 keeps the MVP playable
-- with two friends, and it can be raised toward the GDD's 4/6 numbers later with
-- no logic change. MIN_PLAYERS_TO_CONTINUE encodes the last-one-standing rule:
-- the round ends the instant fewer than this many remain alive. Keep it at 2
-- (end at 1 survivor); values > 2 have no single winner and are unsupported.
Config.MIN_PLAYERS_TO_START = 2
Config.MIN_PLAYERS_TO_CONTINUE = 2

-- Movement, normalized so avatar choice never confers an advantage.
Config.WALK_SPEED = 16
Config.JUMP_HEIGHT = 7.2

-- ===== Movement validation (server-authoritative anti-cheat) =====
-- The void monitor rubber-bands any owned body whose motion is physically impossible
-- (fly / teleport / speed), snapping it to its last valid grounded pose. Pure decision
-- lives in MovementValidator; the glue is in RoundManager.startMonitor. Lenient + debounced
-- so honest laggy players are never corrected (see the 2026-07-04 spec).
Config.MOVE_VALIDATION_ENABLED = true  -- dev/test switch (like HAZARDS_ENABLED), NOT a gameplay tunable
Config.MOVE_HORIZONTAL_SLACK = 2.0     -- x (WALK_SPEED * dt) per-tick budget = the permitted speed-hack
                                       -- ceiling; debounce (not slack) forgives lag, so keep this tight.
Config.MOVE_VERTICAL_SLACK = 1.5       -- x (jumpSpeed * dt) rise budget; a whole legal jump rises < this
                                       -- in a single 0.1s tick, so only a fly-up launch exceeds it.
Config.MOVE_MIN_FALL_EPSILON = 0.5     -- studs/tick; a floorless body descending slower than this counts
                                       -- as hovering (a real fall accelerates well past it).
Config.MOVE_VIOLATION_TICKS = 5        -- consecutive violating ticks (~0.5s at 10Hz) before a correction.
                                       -- MUST exceed the longest legal non-descending run -- a gap-jump's
                                       -- ascent, ceil(sqrt(2*JUMP_HEIGHT/gravity)/0.1) ~= 3 ticks at default
                                       -- gravity; 5 leaves margin. Re-check if gravity/JUMP_HEIGHT change.

-- Avatar dimensions: appearance is personal, physics is uniform.
Config.NORMALIZED_SCALES = {
	HeightScale = 1,
	WidthScale = 1,
	HeadScale = 1,
	DepthScale = 1,
	BodyTypeScale = 0,
	ProportionScale = 0,
}

-- Spawn placement for the persistent bodies: round-start bodies drop onto the TOP
-- hex floor at SPAWN_ORIGIN.Y. Arena slot positions come from HexGrid.spawnSlots
-- (an outward spiral of hex centers); the lobby balcony still uses SpawnLayout.
Config.SPAWN_ORIGIN = Vector3.new(0, 5, 0) -- arena center (X,Z) + spawn height (Y)

-- Lobby staging area: an elevated balcony overlooking the arena. Players wait
-- here between rounds and on join; LobbyArea builds the geometry and BodyManager
-- places bodies on the grid slots (pure SpawnLayout). The arena spans X,Z in
-- [-32,32] at surface Y=0, so the lobby DISC sits RAISED and SET BACK behind the
-- -Z edge; standing bodies look down into the pit. The disc floats over the void,
-- so the rim BARRIER is LOAD-BEARING: a gap would let a controlled body walk/jump
-- off and die between rounds.
Config.LOBBY_ORIGIN = Vector3.new(0, 64, -120) -- disc top-surface center (set well back + elevated so the whole pit is in view)
Config.LOBBY_DISC_RADIUS = 54   -- walkable disc radius (large; holds the 4x4 body grid with lots of room)
Config.LOBBY_DISC_THICKNESS = 2 -- disc vertical thickness (top face sits at LOBBY_ORIGIN.Y)
Config.LOBBY_DISC_COLOR = Color3.fromRGB(40, 42, 58) -- dark metal top
-- LOBBY_WALL_* now describe the INVISIBLE rim barrier. Height must exceed a jump so a
-- body can't hop off (JUMP_HEIGHT = 7.2). The barrier is a gap-free ring of segments.
Config.LOBBY_WALL_HEIGHT = 12 -- barrier height (> JUMP_HEIGHT)
Config.LOBBY_WALL_THICKNESS = 1 -- barrier radial thickness
Config.LOBBY_BARRIER_SEGMENTS = 48 -- ring segments (high = a smooth, perfectly-round rim)
Config.LOBBY_BARRIER_SLACK = 1.1   -- segment length vs chord (overlap => NO gaps)
Config.LOBBY_CAPACITY = 16 -- grid sized for up to this many bodies
Config.LOBBY_PER_ROW = 4 -- body grid columns (rows = ceil(CAPACITY/PER_ROW))
Config.LOBBY_SPACING = 10 -- studs between grid slots
Config.LOBBY_SPAWN_DROP = 5 -- studs above the disc a body spawns at (settles down)
Config.LOBBY_FACE_TARGET = Vector3.new(70, 0, 0) -- bodies face this (midpoint between the two arenas)

-- Default R15 animation asset IDs, consumed by the client animation driver.
-- Bodies aren't player Characters, so the engine's Animate script can't drive
-- them -- the ClientAnimator plays these per-body from velocity + floor state.
Config.ANIM = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
}

-- Swap telegraph + Soul (the swap-legibility piece).
-- SWAP_WARNING_SOUND_ID: the "incoming" rumble played once when the 3s telegraph
-- begins. Leave "" to keep the telegraph silent (it is fully communicative
-- visually -- accessibility). Set to an "rbxassetid://..." string to enable.
Config.SWAP_WARNING_SOUND_ID = ""
-- TELEGRAPH_FLASH_COLOR: the warm base color of the full-screen flash that ramps
-- up over the 3s preview window.
Config.TELEGRAPH_FLASH_COLOR = Color3.fromRGB(255, 110, 40)
-- SOUL_PALETTE: distinct, mobile-legible colors auto-assigned one per player (by
-- join order, wrapping) as their persistent identity halo. The free "which body
-- am I?" anchor (GDD §5). Index->color mapping is the pure SoulPalette module.
Config.SOUL_PALETTE = {
	Color3.fromRGB(255, 80, 80),    -- red
	Color3.fromRGB(80, 160, 255),   -- blue
	Color3.fromRGB(90, 220, 120),   -- green
	Color3.fromRGB(255, 210, 70),   -- yellow
	Color3.fromRGB(200, 110, 255),  -- purple
	Color3.fromRGB(255, 150, 60),   -- orange
	Color3.fromRGB(80, 230, 230),   -- cyan
	Color3.fromRGB(255, 130, 200),  -- pink
}

-- ===== Broadcast World Shell ("Soul Festival Sky") -- Slice 1 ============
-- All client-side cosmetic. Every assetId below has a code-only fallback: an
-- empty string ("") means "skip the asset, use the procedural fallback", so the
-- shell renders with no uploaded assets. Reuses Config.SOUL_PALETTE for colors.

-- Atmosphere / lighting grade (warm dusk: amber -> rose -> violet). Set client-side.
Config.WORLD_CLOCK_TIME = 17.2                                  -- golden-hour sun angle
Config.WORLD_AMBIENT = Color3.fromRGB(95, 70, 110)             -- soft violet fill
Config.WORLD_OUTDOOR_AMBIENT = Color3.fromRGB(150, 110, 130)   -- warm outdoor fill
Config.WORLD_FOG_COLOR = Color3.fromRGB(255, 175, 150)         -- warm haze
Config.WORLD_ATMOSPHERE_DENSITY = 0.05  -- light: let the dusk skybox read through (heavy haze muddies it)
Config.WORLD_ATMOSPHERE_HAZE = 0.4
Config.WORLD_ATMOSPHERE_DECAY = Color3.fromRGB(120, 70, 130)   -- deep violet horizon decay (distinct from Color)
Config.WORLD_BLOOM_INTENSITY = 0.9
Config.WORLD_COLORCORRECTION_TINT = Color3.fromRGB(255, 225, 235)
Config.WORLD_COLORCORRECTION_SATURATION = 0.06
-- Dusk skybox: six face assetIds. Leave all "" to use the gradient fallback
-- (Atmosphere + Lighting tint only, no Sky instance). Faces below are from the
-- free Creator Store "Sunset Dawn Skybox" (assetId 325545295) -- warm dusk,
-- cloud-based, no terrain. Swap to "" per face to fall back to the gradient.
Config.WORLD_SKYBOX = {
	Up = "rbxassetid://323493360",
	Down = "rbxassetid://323494368",
	Left = "rbxassetid://323494252",
	Right = "rbxassetid://323494067",
	Front = "rbxassetid://323494130",
	Back = "rbxassetid://323494035",
}

-- Soul-wisps: drifting glowing orbs colored from SOUL_PALETTE, high in the sky.
Config.WORLD_WISP_COUNT = 22            -- mobile-budgeted default
Config.WORLD_WISP_CENTER_Y = 140        -- height above arena center the field sits at
Config.WORLD_WISP_SPREAD = 220          -- horizontal half-extent of the field
Config.WORLD_WISP_HEIGHT = 80           -- vertical thickness of the field
Config.WORLD_WISP_SIZE = 3              -- stud diameter of each wisp
Config.WORLD_WISP_DRIFT_SPEED = 0.4     -- bob cycles/sec
Config.WORLD_WISP_DRIFT_AMP = 6         -- bob amplitude (studs)
Config.WORLD_WISP_SEED = 20260625       -- deterministic field seed

-- Aurora ribbon overhead; flares (brightens) briefly on each swap.
Config.WORLD_AURORA_Y = 200             -- height of the ribbon
Config.WORLD_AURORA_SIZE = Vector3.new(800, 0.2, 220)
Config.WORLD_AURORA_BASE_TRANSPARENCY = 0.85
Config.WORLD_AURORA_FLARE_TRANSPARENCY = 0.45
Config.WORLD_AURORA_FLARE_SECONDS = 1.1
Config.WORLD_AURORA_BASE_COLOR = Color3.fromRGB(200, 110, 255)  -- purple (was SOUL_PALETTE[5] hardcoded)

-- Distant soul-orb crowd: a far ring on the horizon that cheers (bobs) on events.
Config.WORLD_CROWD_RADIUS = 420
Config.WORLD_CROWD_Y = 30
Config.WORLD_CROWD_COUNT = 48
Config.WORLD_CROWD_ORB_SIZE = 8
Config.WORLD_CROWD_CHEER_BOB = 10       -- studs an orb pops up on a cheer
Config.WORLD_CROWD_CHEER_SECONDS = 0.5
Config.WORLD_CROWD_IDLE_AMP = 1.5       -- studs of gentle idle bob
Config.WORLD_CROWD_IDLE_SPEED = 0.5     -- idle bob cycles/sec
Config.WORLD_CROWD_CHEER_SCALE = 0.6    -- orb size pop fraction at full cheer

-- Layer 2 local dressing (parametric from the ArenaDescriptor).
-- Per-floor EDGE TRIM: a floor-colored glowing rim hugging each floor's edge,
-- built as WORLD_TRIM_SEGMENTS thin Neon tangent bars around a ring derived from
-- the descriptor footprint (radius = footprint.X/2 + margin) -- one coherent rim
-- per floor instead of scattered orbs. Replaces the old torches + orb rings.
-- Placed OUTSIDE the outermost tiles so eroding tiles never reveal a glowing plate.
Config.WORLD_TRIM_MARGIN = 6            -- studs outward from footprint half-extent (clears the tiles)
Config.WORLD_TRIM_SEGMENTS = 16        -- tangent bars per floor (enough to read continuous)
Config.WORLD_TRIM_Y = 1.5              -- studs above the floor surface the rim sits
Config.WORLD_TRIM_HEIGHT = 0.8         -- bar vertical thickness
Config.WORLD_TRIM_DEPTH = 1.4          -- bar radial thickness
Config.WORLD_TRIM_LENGTH_SLACK = 1.06  -- segment length vs chord (slightly overlap so the rim closes)
-- Every floor glows by Neon trim alone (no real PointLights) -- uniform lighting
-- across all floors; the dusk ambient (WorldShell) provides the rest.

-- Framed marquee header (banner) on support posts at the balcony's arena-facing edge.
Config.WORLD_BANNER_TEXT = "BODY SWAP ROYALE"
Config.WORLD_BANNER_SIZE = Vector3.new(64, 16, 2)
Config.WORLD_BANNER_HEIGHT = 26                 -- studs above the disc surface (clears the 12-high invisible rim barrier with a gap)
Config.WORLD_BANNER_FORWARD = 6                 -- studs toward the arena from the disc's arena-facing edge
Config.WORLD_BANNER_FRAME_COLOR = Color3.fromRGB(255, 216, 77)   -- glowing amber frame
Config.WORLD_BANNER_BG_TOP = Color3.fromRGB(36, 16, 72)
Config.WORLD_BANNER_BG_BOTTOM = Color3.fromRGB(22, 10, 46)
Config.WORLD_BANNER_TEXT_COLOR = Color3.fromRGB(255, 216, 77)

-- ============ Lobby Grandstand Stage (World Slice 2) ============
-- Consumed by the client LobbyStage module to redress the lobby balcony into a
-- festival grandstand stage. Add-only + non-colliding (LobbyArea geometry is
-- server-owned and untouched). "Magic-Hour Fair": warm festoon lights against the
-- cool dusk/aurora. All heights are relative to the platform top (= LOBBY_ORIGIN.Y).

-- ============ Beyblade lobby cosmetic (client LobbyStage) ============
-- The server LobbyArea builds the load-bearing disc + invisible rim barrier; this
-- block dresses it as a spinning top. All cosmetic parts are non-colliding. Heights
-- are relative to the disc top (= LOBBY_ORIGIN.Y).

-- Round lobby parts (disc, energy rings, taper) are drawn as high-N EditableMesh
-- cylinders on the client -- primitive Part Cylinders facet visibly at this scale.
Config.LOBBY_BEY_SMOOTH_SIDES = 96 -- mesh sides (high = perfectly smooth circle)

-- Energy rings: Neon discs WIDER than the server disc, centered at its mid-height so
-- their rim glows around the disc edge (the opaque disc occludes the center). Ring A
-- (cool) is the visible half of the hybrid fall ring; ring B (warm) is lower + wider.
Config.LOBBY_BEY_RING_COLOR_A = Color3.fromRGB(120, 230, 220)
Config.LOBBY_BEY_RING_COLOR_B = Color3.fromRGB(255, 207, 107)
Config.LOBBY_BEY_RING_OVERHANG_A = 1.4   -- studs ring A extends past the disc radius
Config.LOBBY_BEY_RING_OVERHANG_B = 3.0   -- studs ring B extends past the disc radius
Config.LOBBY_BEY_RING_DROP_B = 1.6       -- studs ring B sits below ring A
Config.LOBBY_BEY_RING_THICKNESS = 0.6
-- Dim ALL the lobby's neon glow (energy rings + spectator orbs) to a soft level via
-- partial transparency -- higher = dimmer/softer (Neon emits less when see-through).
Config.LOBBY_BEY_GLOW_TRANSPARENCY = 0.5

-- Stepped taper body below the disc. Each entry { radiusFrac, depth below the disc
-- top (studs), thickness }. Metal discs of decreasing radius down to a small base.
Config.LOBBY_BEY_STEP_COLOR = Color3.fromRGB(54, 56, 74)
Config.LOBBY_BEY_STEPS = {
	{ 0.82, 4, 3 },
	{ 0.55, 9, 3 },
	{ 0.30, 14, 3 },
}

-- Spectator souls: two cheer-reactive soul-orb clusters at the rim (+/-X).
Config.LOBBY_BEY_CLUSTER_RADIUS = 0.8    -- fraction of disc radius the clusters sit at
Config.LOBBY_BEY_CLUSTER_LIFT = 2.5      -- studs above the disc top

-- Crowd cluster shape + cheer (reused by the spectator souls).
Config.LOBBY_STAGE_CLUSTER_PER_SIDE = 6  -- orbs per cluster (2 => ~12 total)
Config.LOBBY_STAGE_CLUSTER_SPACING = 2.6 -- studs between orbs in a cluster
Config.LOBBY_STAGE_ORB_SIZE = 2.2
Config.LOBBY_STAGE_IDLE_SPEED = 0.5
Config.LOBBY_STAGE_IDLE_AMP = 0.4
Config.LOBBY_STAGE_CHEER_BOB = 6         -- studs an orb pops up on a cheer
Config.LOBBY_STAGE_CHEER_SCALE = 0.5     -- orb size pop fraction at full cheer
Config.LOBBY_STAGE_CHEER_SECONDS = 0.5   -- cheer decay time

-- Hybrid asset field (blank "" => code fallback). Crowd-orb mesh only; the rest of
-- the beyblade ships as code.
Config.LOBBY_STAGE_ORB_MESH = ""

-- ===== Economy & Persistence (Coins + XP + Level) =====
-- Reward formula (RewardModel). XP matches the GDD §9 formula verbatim; coins
-- are tuned to the GDD §8 ~20-100/round range via survival depth (swaps survived).
Config.REWARD_XP_BASE = 25          -- participation
Config.REWARD_XP_PER_SWAP = 5       -- per swap survived
Config.REWARD_XP_WIN = 100          -- winner bonus
Config.REWARD_COINS_BASE = 15       -- participation
Config.REWARD_COINS_PER_SWAP = 4    -- per swap survived
Config.REWARD_COINS_WIN = 40        -- winner bonus

-- Progression (ProgressionModel). XP to advance FROM level L = floor(COEFF * L ^ EXP).
Config.PROGRESSION_XP_COEFF = 100
Config.PROGRESSION_XP_EXP = 1.4
Config.PROGRESSION_MAX_LEVEL = 100

-- Persistence (ProfileStore / EconomyService).
Config.DATASTORE_NAME = "PlayerData_v1"
Config.PROFILE_VERSION = 1
Config.ECONOMY_LOAD_RETRIES = 4         -- load attempts before giving up (then persisted=false)
Config.ECONOMY_SAVE_RETRIES = 3         -- save attempts before logging failure
Config.ECONOMY_RETRY_BACKOFF = 1.0      -- seconds; multiplied by the attempt number
Config.ECONOMY_AUTOSAVE_SECONDS = 120   -- periodic background-save cadence

-- Re-embodiment sweep (RoundManager): how often the server rechecks every connected
-- player for a missing own body (every BodyManager.createBody attempt failed on join)
-- and retries. Short enough that a bodiless-on-join player recovers quickly without
-- meaningfully polling the player list.
Config.BODY_RECONCILE_SECONDS = 2

-- ===== Animated XP fill (reward panel) =====
-- Timing only; the fill GEOMETRY (segments across level boundaries) is pure
-- (XpFillModel). Consumed by ClientEconomyHud's timeline player.
Config.REWARD_XP_FILL_SECONDS = 1.2        -- total bar-fill time, any XP amount
Config.REWARD_LEVELUP_PAUSE_SECONDS = 0.3  -- hold at each level-up (pop/flash)
Config.REWARD_PANEL_HOLD_SECONDS = 2.5     -- readable beat after the animation completes
Config.REWARD_LEVELUP_POP_SCALE = 1.08     -- panel scale-punch peak on level-up
Config.REWARD_LEVELUP_FLASH_COLOR = Color3.fromRGB(255, 246, 200) -- bright surge tint

-- ===== Swap-preview directional ping =====
Config.PING_COLOR = Color3.fromRGB(255, 200, 60)          -- amber; matches the preview Highlight fill
Config.PING_OUTLINE_COLOR = Color3.fromRGB(255, 220, 120)
Config.PING_EDGE_MARGIN = 48        -- px inset from the screen edge for the off-screen arrow
Config.PING_ARROW_SIZE = 44         -- px, off-screen edge arrow
Config.PING_CHEVRON_SIZE = 28       -- px, on-target chevron
Config.PING_CHEVRON_HEIGHT = 3.2    -- studs above the target head

-- ===== First-session hints =====
Config.HINT_FADE_IN = 0.2           -- seconds
Config.HINT_FADE_OUT = 0.3          -- seconds
Config.HINT_LABEL_HEIGHT = 3.4      -- studs above the anchor head
Config.HINT_LABEL_SIZE = Vector2.new(224, 56) -- px billboard size
-- Dev/test switch (like HAZARDS_ENABLED / MOVE_VALIDATION_ENABLED): when true, the
-- first-session hints IGNORE the persisted seenHints gate and fire on EVERY trigger
-- (preview + swap), and DON'T persist -- so you can replay the onboarding hints every
-- round while testing without wiping DataStore or using fresh accounts. NOT a gameplay
-- tunable; leave false in production.
Config.HINT_IGNORE_SEEN = false

return Config
