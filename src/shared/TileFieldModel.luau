--[[
	TileFieldModel (shared) -- pure, time-injected decision for a disappearing-tile
	floor. Answers exactly one question: what phase is a tile in right now?
	("solid" | "warning" | "gone"). Knows nothing about Roblox parts, collision,
	color, or death -- the server glue (HazardSystem) maps phase -> part properties,
	and death stays geometric (fall-through -> the existing void monitor).

	Pure like RoundState / GraceModel: no clock reads, no RNG; lune-tested.
--]]

local TileFieldModel = {}

-- Phase of a single tile at time `now`, given the round's start time and the
-- tile's fixed phase offset. durations = { solid, warning, gone } in seconds.
function TileFieldModel.phaseAt(now, roundStart, offset, durations)
	local period = durations.solid + durations.warning + durations.gone
	local t = (now - roundStart + offset) % period
	if t < durations.solid then
		return "solid"
	elseif t < durations.solid + durations.warning then
		return "warning"
	else
		return "gone"
	end
end

-- Deterministic per-tile phase offset in [0, solid). Same coords -> same value
-- every round, so the floor is solid at roundStart and the drop pattern is
-- learnable. Pure hash (no RNG, no bitops) -- behaves identically in lune and
-- Roblox.
function TileFieldModel.offsetFor(row, col, solid)
	local h = math.sin(row * 12.9898 + col * 78.233) * 43758.5453
	local frac = h - math.floor(h) -- pseudo-random in [0, 1)
	return frac * solid
end

return TileFieldModel
