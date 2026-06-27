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
-- A controlled body whose root falls below this Y is eliminated (grace-gated, via
-- the void monitor). With the 7-floor hex arena (floors at 0 / -50 / ... / -300),
-- this sits just under the LOWEST floor, so only a body that falls off floor 7 dies
-- -- falling through an upper floor lands on the next floor down. Still far above
-- Workspace.FallenPartsDestroyHeight (default -500).
Config.VOID_Y = -304

-- Hex-A-Gone arena floor. Seven stacked hexagonal floors; a hex arms the instant a
-- body stands on it, flashes the warning color for HEX_GONE_DELAY_SECONDS, then
-- vanishes for good (monotonic -- no return that round). Pure decisions live in
-- HexGrid (geometry) + HexErosionModel (arm/phase) + HexPrism (tile mesh); HazardSystem
-- builds one true hexagonal MeshPart per tile (EditableMesh, no gaps / no z-fighting)
-- and maps phase -> part props. HAZARDS_ENABLED: dev/test switch (NOT a gameplay
-- tunable). When false, floors build but never arm (stay solid), so swaps can be
-- observed without bodies falling.
Config.HAZARDS_ENABLED = true
Config.HEX_RADIUS = 5            -- rings from center; tiles/floor = 1+3R(R+1) = 91 (fine honeycomb)
Config.HEX_SIZE = 4              -- LATTICE hex circumradius (tile centers + occupancy lookup); small
                                 -- tiles -> many distinct hexagons, ~one body per tile
Config.HEX_GAP = 0.3            -- studs each tile is INSET from the lattice radius, so neighbors
                                 -- don't touch: a THIN grout seam between tiles + zero coincident
                                 -- geometry (no z-fighting). Rendered/collided radius = HEX_SIZE - HEX_GAP.
Config.HEX_FLOOR_COUNT = 7       -- stacked floors
Config.HEX_FLOOR_GAP = 50        -- vertical studs between floors (floors at 0/-50/.../-300)
Config.HEX_STAND_BAND = 6        -- root-height window above a floor that counts as "on" it
                                 -- (must be < HEX_FLOOR_GAP so floor bands don't overlap)
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
Config.LOBBY_ORIGIN = Vector3.new(0, 45, -64) -- disc top-surface center
Config.LOBBY_DISC_RADIUS = 30   -- walkable disc radius (holds the 4x4 body grid + margin)
Config.LOBBY_DISC_THICKNESS = 2 -- disc vertical thickness (top face sits at LOBBY_ORIGIN.Y)
Config.LOBBY_DISC_COLOR = Color3.fromRGB(40, 42, 58) -- dark metal top
-- LOBBY_WALL_* now describe the INVISIBLE rim barrier. Height must exceed a jump so a
-- body can't hop off (JUMP_HEIGHT = 7.2). The barrier is a gap-free ring of segments.
Config.LOBBY_WALL_HEIGHT = 12 -- barrier height (> JUMP_HEIGHT)
Config.LOBBY_WALL_THICKNESS = 1 -- barrier radial thickness
Config.LOBBY_BARRIER_SEGMENTS = 18 -- ring segments (more = rounder fence)
Config.LOBBY_BARRIER_SLACK = 1.1   -- segment length vs chord (overlap => NO gaps)
Config.LOBBY_CAPACITY = 16 -- grid sized for up to this many bodies
Config.LOBBY_PER_ROW = 4 -- body grid columns (rows = ceil(CAPACITY/PER_ROW))
Config.LOBBY_SPACING = 10 -- studs between grid slots
Config.LOBBY_SPAWN_DROP = 5 -- studs above the disc a body spawns at (settles down)
Config.LOBBY_FACE_TARGET = Vector3.new(0, 0, 0) -- bodies face this (arena center)

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

-- Energy rings: Neon discs WIDER than the server disc, centered at its mid-height so
-- their rim glows around the disc edge (the opaque disc occludes the center). Ring A
-- (cool) is the visible half of the hybrid fall ring; ring B (warm) is lower + wider.
Config.LOBBY_BEY_RING_COLOR_A = Color3.fromRGB(120, 230, 220)
Config.LOBBY_BEY_RING_COLOR_B = Color3.fromRGB(255, 207, 107)
Config.LOBBY_BEY_RING_OVERHANG_A = 1.4   -- studs ring A extends past the disc radius
Config.LOBBY_BEY_RING_OVERHANG_B = 3.0   -- studs ring B extends past the disc radius
Config.LOBBY_BEY_RING_DROP_B = 1.6       -- studs ring B sits below ring A
Config.LOBBY_BEY_RING_THICKNESS = 0.6

-- Stepped taper body below the disc, down to a tip. Each entry { radiusFrac, depth
-- below the disc top (studs), thickness }. Metal discs of decreasing radius.
Config.LOBBY_BEY_STEP_COLOR = Color3.fromRGB(54, 56, 74)
Config.LOBBY_BEY_STEPS = {
	{ 0.82, 4, 3 },
	{ 0.55, 9, 3 },
	{ 0.30, 14, 3 },
}
-- Tip: a thin vertical Neon spike at the bottom center.
Config.LOBBY_BEY_TIP_COLOR = Color3.fromRGB(120, 230, 220)
Config.LOBBY_BEY_TIP_DIAMETER = 2.4
Config.LOBBY_BEY_TIP_HEIGHT = 7
Config.LOBBY_BEY_TIP_DEPTH = 19          -- studs below the disc top the tip CENTER sits

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

return Config
