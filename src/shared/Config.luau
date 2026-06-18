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

-- Round population thresholds (consumed by RoundState via the server glue).
-- Defaults of 2 keep the MVP playable with two friends; raise toward the GDD's
-- 4/6 numbers later with no logic change. "Continue = 2" => the round ends the
-- instant fewer than 2 players remain alive, so the last one standing wins.
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

-- Spawn spreading for the persistent bodies.
Config.SPAWN_ORIGIN = Vector3.new(0, 5, 0)
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
