--[[
	ArenaRegistry -- the full set of registered ArenaHazard implementations (persistent
	multi-arena world). RoundManager reads `all()` once at startup to build every arena,
	`ids()` to feed the pure ArenaRotationModel, and `get(id)` each round to resolve the
	live arena.
--]]

local ArenaHazard = require(script.Parent.ArenaHazard)
local HexHazard = require(script.Parent.HexHazard)
local SweeperHazard = require(script.Parent.SweeperHazard)

local ArenaRegistry = {}

local ARENAS = { HexHazard, SweeperHazard } -- rotation order

function ArenaRegistry.all()
	for _, a in ipairs(ARENAS) do
		ArenaHazard.validate(a)
	end
	return ARENAS
end

function ArenaRegistry.ids()
	local ids = {}
	for _, a in ipairs(ARENAS) do
		ids[#ids + 1] = a.id
	end
	return ids
end

function ArenaRegistry.get(id)
	for _, a in ipairs(ARENAS) do
		if a.id == id then
			return a
		end
	end
	error("ArenaRegistry.get: unknown arena id " .. tostring(id))
end

return ArenaRegistry
