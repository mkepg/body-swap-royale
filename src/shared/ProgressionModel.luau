--[[
	ProgressionModel -- PURE XP <-> level math. Roblox-free, no clocks/RNG; the
	caller injects tunables via `opts = { coeff, exp, maxLevel }` (server passes
	Config values; tests pass literals). Level is DERIVED from cumulative totalXp,
	never stored, so the curve can change without a data migration.
	Location (Roblox): ReplicatedStorage/Shared/ProgressionModel  (ModuleScript)
--]]

local ProgressionModel = {}

-- XP required to advance FROM `level` to `level + 1`.
function ProgressionModel.xpForLevel(level, opts)
	return math.floor(opts.coeff * level ^ opts.exp)
end

-- Derive { level, xpIntoLevel, xpForNext, progress } from cumulative totalXp.
-- Players start at level 1 with 0 xp; reaching level L costs the sum of
-- xpForLevel(1..L-1). Clamped at opts.maxLevel (full bar, no next).
function ProgressionModel.levelFor(totalXp, opts)
	local level = 1
	local remaining = math.max(0, math.floor(totalXp))
	while level < opts.maxLevel do
		local need = ProgressionModel.xpForLevel(level, opts)
		if remaining < need then
			break
		end
		remaining -= need
		level += 1
	end
	if level >= opts.maxLevel then
		return { level = opts.maxLevel, xpIntoLevel = 0, xpForNext = 0, progress = 1 }
	end
	local need = ProgressionModel.xpForLevel(level, opts)
	return {
		level = level,
		xpIntoLevel = remaining,
		xpForNext = need,
		progress = need > 0 and remaining / need or 0,
	}
end

return ProgressionModel
