--[[
	ArenaRotationModel -- PURE per-round arena selection.
	Location (Roblox): ReplicatedStorage/Shared/ArenaRotationModel (ModuleScript)

	next(currentId, arenaIds, override) decides which arena hosts the next round:
	  - override naming a known arena pins it (Config.ARENA_OVERRIDE, dev/test),
	  - otherwise simple alternation through arenaIds (wraps),
	  - nil/unknown currentId starts at the first arena.
	No clock reads / RNG (lune-tested).
--]]

local ArenaRotationModel = {}

function ArenaRotationModel.next(currentId, arenaIds, override)
	if override ~= nil and override ~= "" then
		for _, id in ipairs(arenaIds) do
			if id == override then
				return override
			end
		end
	end
	for i, id in ipairs(arenaIds) do
		if id == currentId then
			return arenaIds[(i % #arenaIds) + 1]
		end
	end
	return arenaIds[1]
end

return ArenaRotationModel
