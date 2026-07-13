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
	  trim      -- optional (default true): false = arena builds its own border, skip edge trim

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
		trimDim = Config.GLOW_DIM_HEX_TRIM, -- per-arena dim for this arena's edge-trim border
	}
end

-- Soul Sweeper v2 descriptor: one annulus level at the platform surface.
-- trim = false: the T4 glow-up's built-in rim ring (SweeperController) replaces
-- the generic ArenaDressing edge trim, so this arena opts out of Layer-2 trim.
function ArenaDescriptor.sweeper()
	local extent = Config.SWEEP_PLATFORM_RADIUS * 2
	return {
		center = Vector3.new(Config.SWEEP_CENTER.X, Config.SWEEP_SURFACE_Y, Config.SWEEP_CENTER.Z),
		footprint = Vector2.new(extent, extent),
		depth = Config.SWEEP_SURFACE_Y - Config.SWEEP_VOID_Y,
		accent = Config.SWEEP_ACCENT,
		levels = { { y = Config.SWEEP_SURFACE_Y, color = Config.SWEEP_ACCENT } },
		trim = false,
	}
end

-- Every arena's descriptor (persistent world: the client dresses ALL of them).
function ArenaDescriptor.all()
	return { ArenaDescriptor.hex(), ArenaDescriptor.sweeper() }
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
	-- trim defaults to true; trimDim is only meaningful (and required) when trimmed.
	assert(desc.trim == nil or type(desc.trim) == "boolean",
		"ArenaDescriptor.trim must be a boolean when present")
	if desc.trim ~= false then
		assert(type(desc.trimDim) == "number", "ArenaDescriptor.trimDim must be a number")
	end
	for i, lv in ipairs(desc.levels) do
		assert(type(lv.y) == "number", "ArenaDescriptor.levels[" .. i .. "].y must be a number")
		assert(typeof(lv.color) == "Color3", "ArenaDescriptor.levels[" .. i .. "].color must be a Color3")
	end
	return desc
end

return ArenaDescriptor
