--[[
	Config
	Location: ReplicatedStorage/Shared/Config  (ModuleScript)
	Single source of truth for tunable values. Shared by server and client.
--]]

local Config = {}

-- Round timing (used from step 5/6 onward)
Config.CYCLE_SECONDS = 30
Config.PREVIEW_SECONDS = 3
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

-- Default R15 animation asset IDs, consumed by the client animation driver.
-- Bodies aren't player Characters, so the engine's Animate script can't drive
-- them -- the ClientAnimator plays these per-body from velocity + floor state.
Config.ANIM = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
}

return Config
