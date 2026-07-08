--[[
	ArenaDescriptor -- the contract between the arena-agnostic world shell and a
	specific arena. Glue (uses Roblox Vector/Color types), so NOT lune-tested; the
	hex descriptor is verified by an MCP probe and the smoke test.

	Shape:
	  { center: Vector3, footprint: Vector2, depth: number, accent: Color3 }
	  center    -- arena center (X,Z) + play-surface Y
	  footprint -- X,Z extent of the course (Layer 2 dressing sizes to this)
	  depth     -- how far the course drops below the surface
	  accent    -- theme tint for this arena's dressing

	Future arenas add their own builder here; ArenaDressing consumes whichever
	descriptor it is handed and never reads arena internals.
--]]

local Shared = script.Parent
local Config = require(Shared.Config)

local ArenaDescriptor = {}

-- The Hex-A-Gone arena's descriptor, derived from the hex Config. The pit is a
-- CIRCULAR field of radius HEX_CIRCLE_RADIUS; the footprint is that circle's bounding
-- box, so the dressing (edge trim) hugs the circle via WORLD_TRIM_MARGIN. depth =
-- floor span below the top.
function ArenaDescriptor.hex()
	local halfWidth = Config.HEX_CIRCLE_RADIUS
	local extent = halfWidth * 2
	-- One dressable level per hex floor, top -> bottom, each carrying its floor color.
	local levels = {}
	for k = 0, Config.HEX_FLOOR_COUNT - 1 do
		levels[#levels + 1] = {
			y = Config.TILE_SURFACE_Y - k * Config.HEX_FLOOR_GAP,
			color = Config.HEX_FLOOR_COLORS[k + 1],
		}
	end
	return {
		center = Vector3.new(0, Config.TILE_SURFACE_Y, 0),
		footprint = Vector2.new(extent, extent),
		depth = Config.HEX_FLOOR_GAP * (Config.HEX_FLOOR_COUNT - 1),
		accent = Config.HEX_FLOOR_COLORS[1],
		levels = levels,
	}
end

-- The Soul Sweeper arena's descriptor. footprint = the bottom (widest) disc's bounding
-- box, so Layer-2 dressing hugs the whole stack. One dressable level per tier (its
-- surface Y + color), top -> bottom, mirroring hex's per-floor levels.
function ArenaDescriptor.sweeper()
	local bottomRadius = Config.SWEEP_TOP_RADIUS + (Config.SWEEP_TIER_COUNT - 1) * Config.SWEEP_RADIUS_STEP
	local extent = bottomRadius * 2
	local levels = {}
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		levels[#levels + 1] = {
			y = Config.SWEEP_TOP_SURFACE_Y - k * Config.SWEEP_TIER_GAP,
			color = Config.SWEEP_TIER_COLORS[math.min(k + 1, #Config.SWEEP_TIER_COLORS)],
		}
	end
	return {
		center = Vector3.new(0, Config.SWEEP_TOP_SURFACE_Y, 0),
		footprint = Vector2.new(extent, extent),
		depth = Config.SWEEP_TIER_GAP * (Config.SWEEP_TIER_COUNT - 1),
		accent = Config.SWEEP_TIER_COLORS[1],
		levels = levels,
	}
end

-- Resolve the descriptor for the active arena (Config.ACTIVE_ARENA). Client dressing
-- consumes this instead of hardcoding a specific arena.
function ArenaDescriptor.forActive()
	if Config.ACTIVE_ARENA == "sweeper" then
		return ArenaDescriptor.sweeper()
	end
	return ArenaDescriptor.hex()
end

-- Cheap shape guard so a future arena's hand-built descriptor fails loudly/early
-- rather than producing silently-wrong dressing. Returns the descriptor for chaining.
function ArenaDescriptor.validate(desc)
	assert(typeof(desc.center) == "Vector3", "ArenaDescriptor.center must be a Vector3")
	assert(typeof(desc.footprint) == "Vector2", "ArenaDescriptor.footprint must be a Vector2")
	assert(type(desc.depth) == "number", "ArenaDescriptor.depth must be a number")
	assert(typeof(desc.accent) == "Color3", "ArenaDescriptor.accent must be a Color3")
	assert(type(desc.levels) == "table" and #desc.levels > 0,
		"ArenaDescriptor.levels must be a non-empty array")
	for i, lv in ipairs(desc.levels) do
		assert(type(lv.y) == "number", "ArenaDescriptor.levels[" .. i .. "].y must be a number")
		assert(typeof(lv.color) == "Color3", "ArenaDescriptor.levels[" .. i .. "].color must be a Color3")
	end
	return desc
end

return ArenaDescriptor
