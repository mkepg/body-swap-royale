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

-- The Hex-A-Gone arena's descriptor, derived from the hex Config. The flat-top
-- field's world half-width is ~ HEX_SIZE * 1.5 * HEX_RADIUS; pad by one tile so
-- the dressing clears the outermost tiles. depth = floor span below the top.
function ArenaDescriptor.hex()
	local halfWidth = Config.HEX_SIZE * 1.5 * Config.HEX_RADIUS + Config.HEX_SIZE
	local extent = halfWidth * 2
	return {
		center = Vector3.new(0, Config.TILE_SURFACE_Y, 0),
		footprint = Vector2.new(extent, extent),
		depth = Config.HEX_FLOOR_GAP * (Config.HEX_FLOOR_COUNT - 1),
		accent = Config.HEX_FLOOR_COLORS[1],
	}
end

return ArenaDescriptor
