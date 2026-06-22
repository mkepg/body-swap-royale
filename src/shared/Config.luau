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

-- RoundManager loop tunables (server-owned clocks + the void death source).
-- LOBBY_COUNTDOWN_SECONDS: pre-round countdown once enough players are present.
-- ROUND_END_SECONDS: winner-display window before resetting to Lobby.
-- VOID_Y: a controlled body whose root falls below this Y is eliminated. With the
-- disappearing-tile floor (TILE_SURFACE_Y = 0), this sits a few studs under the
-- tile bottoms, so falling through a `gone` tile crosses it in ~0.6s -- quick
-- enough for the post-swap grace window (1.5s) to protect a freshly-swapped body.
-- Still far above Workspace.FallenPartsDestroyHeight (default -500).
Config.LOBBY_COUNTDOWN_SECONDS = 5
Config.ROUND_END_SECONDS = 5
Config.VOID_Y = -4

-- Disappearing-tile hazard (the MVP arena floor). The pure TileFieldModel decides
-- each tile's phase from these durations; HazardSystem maps phase -> part props.
-- A tile cycles solid -> warning(red) -> gone(no collision) -> solid.
-- HAZARDS_ENABLED: dev/test switch (NOT a gameplay tunable). When false,
-- HazardSystem builds the floor but never runs the disappearing cycle, so tiles
-- stay solid and nobody falls -- lets you reach/observe the 30s swap without a
-- body dying first. Leave true for real play.
Config.HAZARDS_ENABLED = true
Config.TILE_SOLID_SECONDS = 4 -- standable time per cycle
Config.TILE_WARNING_SECONDS = 2 -- red telegraph (GDD §5: "red 2s before")
Config.TILE_GONE_SECONDS = 1.5 -- vanished (fall-through) window
-- Grid geometry. GRID_SIZE x GRID_SIZE tiles of TILE_SIZE studs each, centered on
-- the X/Z origin; top face at TILE_SURFACE_Y. 8x8 @ 8 studs = a 64x64 arena.
Config.TILE_GRID_SIZE = 8
Config.TILE_SIZE = 8
Config.TILE_SURFACE_Y = 0
Config.TILE_THICKNESS = 1
Config.TILE_COLOR_SOLID = Color3.fromRGB(150, 150, 150) -- neutral grey
Config.TILE_COLOR_WARNING = Color3.fromRGB(200, 40, 40) -- alarm red

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

-- Spawn spreading for the persistent bodies. Bodies spawn along +X at
-- SPAWN_ORIGIN + index*SPAWN_SPACING, dropping onto the solid tile floor.
-- IMPORTANT: spawn positions MUST land on tile CENTERS, not seams. Tile centers
-- sit at multiples of TILE_SIZE offset by TILE_SIZE/2 (here X,Z in {..-4,4,12..});
-- the seams (multiples of TILE_SIZE: ..0,8,16..) are where 2-4 tiles meet. A body
-- standing on a seam/corner is held up by every tile it touches and only falls
-- when they ALL vanish at once -- so it looks invincible. So the origin is a tile
-- center (X=-4, Z=4) and spacing equals TILE_SIZE: each body lands centered on its
-- own tile and drops the instant that tile goes `gone`.
-- NOTE: the field spans X,Z in [-32, +32] (8x8 @ 8 studs). With origin X=-4 and
-- spacing 8, bodies occupy X = -4,4,12,20,28 (tile centers); a 6th body (X=36)
-- would spawn past the field. Fine for the 2-player MVP -- when raising player
-- count, spread across rows (Z) or enlarge the grid.
Config.SPAWN_ORIGIN = Vector3.new(-4, 5, 4)
Config.SPAWN_SPACING = 8

-- Lobby staging area: an elevated balcony overlooking the arena. Players wait
-- here between rounds and on join; LobbyArea builds the geometry and BodyManager
-- places bodies on the grid slots (pure SpawnLayout). The arena spans X,Z in
-- [-32,32] at surface Y=0, so the balcony sits RAISED and SET BACK behind the
-- -Z edge, facing +Z toward the arena center -- standing bodies look down into
-- the pit. The perimeter barriers are LOAD-BEARING: the pad floats over the void,
-- so a gap would let a controlled body walk off and die between rounds.
Config.LOBBY_ORIGIN = Vector3.new(0, 45, -64) -- balcony surface center
Config.LOBBY_PAD_SIZE = Vector3.new(48, 1, 48) -- platform X, thickness(Y), Z
-- LOBBY_WALL_HEIGHT must comfortably exceed a jump so a body can't hop the railing
-- into the void (JUMP_HEIGHT = 7.2; feet clear roughly that high). 12 leaves a safe
-- margin -- the front railing is transparent, so a taller wall doesn't block the view.
Config.LOBBY_WALL_HEIGHT = 12 -- perimeter barrier height (fall protection)
Config.LOBBY_WALL_THICKNESS = 1
Config.LOBBY_CAPACITY = 16 -- grid sized for up to this many bodies
Config.LOBBY_PER_ROW = 4 -- balcony grid columns (rows = ceil(CAPACITY/PER_ROW))
Config.LOBBY_SPACING = 10 -- studs between grid slots
Config.LOBBY_SPAWN_DROP = 5 -- studs above the pad a body spawns at (settles down)
Config.LOBBY_FACE_TARGET = Vector3.new(0, 0, 0) -- bodies face this (arena center)
Config.LOBBY_COLOR_PAD = Color3.fromRGB(120, 170, 230) -- soft blue (echoes lobby banner)
Config.LOBBY_COLOR_WALL = Color3.fromRGB(90, 130, 190) -- slightly darker walls
Config.LOBBY_RAILING_TRANSPARENCY = 0.6 -- arena-facing glass railing (CanCollide, see-through)

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

return Config
