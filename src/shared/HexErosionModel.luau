--[[
	HexErosionModel -- PURE step-driven, monotonic tile erosion for Hex-A-Gone.
	Location (Roblox): ReplicatedStorage/Shared/HexErosionModel (ModuleScript)

	Answers two questions, no clock reads / RNG (lune-tested, pure like the
	project's other shared decision models):
	  arm     -- when does a tile's erosion timer start? (grace-gated, idempotent)
	  phaseAt -- given that start time + now, what phase is the tile in?

	Monotonic: the caller never clears steppedAt, so a tile goes solid -> warning
	-> gone and never returns within a round. Death stays geometric (a body over a
	gone tile falls past VOID_Y -> the existing void monitor).
--]]

local HexErosionModel = {}

-- Decide a tile's steppedAt (erosion start time):
--   already armed     -> unchanged (idempotent),
--   occupied + !grace  -> now (arm),
--   otherwise          -> nil (stays solid).
-- graceBlocked is true while a body's post-swap grace still shields it, so a
-- freshly-swapped body never arms the tile it is standing on.
function HexErosionModel.arm(steppedAt, occupied, graceBlocked, now)
	if steppedAt ~= nil then
		return steppedAt
	end
	if occupied and not graceBlocked then
		return now
	end
	return nil
end

-- Phase of a tile given its steppedAt (or nil) and now. durations = { gone }.
-- An armed tile shows the warning color for the whole `gone` delay, then drops.
function HexErosionModel.phaseAt(steppedAt, now, durations)
	if steppedAt == nil then
		return "solid"
	elseif now - steppedAt < durations.gone then
		return "warning"
	else
		return "gone"
	end
end

return HexErosionModel
