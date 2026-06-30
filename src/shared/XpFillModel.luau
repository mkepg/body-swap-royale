--[[
	XpFillModel -- PURE animated-XP-fill timeline. Roblox-free, no clocks/RNG.
	Given the pre-award level state + the XP delta + progression opts, returns the
	ordered fill SEGMENTS the renderer tweens (one per level touched) plus the final
	level/progress. Geometry only -- TIMING lives in the client (Config). The level
	costs are INJECTED (opts.xpForLevel) so this module needs no Roblox `script`
	require, keeping it lune-testable (mirrors how the repo injects dependencies).
	Location (Roblox): ReplicatedStorage/Shared/XpFillModel  (ModuleScript)

	start = { level, xpIntoLevel, xpForNext }   -- xpForNext = 0 at max level
	opts  = { maxLevel, xpForLevel = function(level) -> number }  -- cost to finish `level`
	Returns { segments, totalSpan, finalLevel, finalProgress }.
	segment = { level, fromProgress, toProgress, xpSpan, levelUpAfter }
--]]

local XpFillModel = {}

local function fractionOf(intoLevel, forNext)
	if forNext and forNext > 0 then
		return intoLevel / forNext
	end
	return 0
end

function XpFillModel.build(start, deltaXp, opts)
	local level = start.level
	local intoLevel = start.xpIntoLevel
	local forNext = start.xpForNext
	local remaining = math.max(0, math.floor(deltaXp))

	-- Nothing animates: no XP, already at/over max, or no "next" to fill toward.
	if remaining <= 0 or level >= opts.maxLevel or forNext <= 0 then
		local finalProgress = (level >= opts.maxLevel) and 1 or fractionOf(intoLevel, forNext)
		return {
			segments = {},
			totalSpan = 0,
			finalLevel = math.min(level, opts.maxLevel),
			finalProgress = finalProgress,
		}
	end

	local segments = {}
	local totalSpan = 0
	while remaining > 0 do
		local need = forNext - intoLevel -- XP to finish THIS level
		if remaining < need then
			-- Ends within this level (no level-up).
			local toInto = intoLevel + remaining
			segments[#segments + 1] = {
				level = level,
				fromProgress = fractionOf(intoLevel, forNext),
				toProgress = fractionOf(toInto, forNext),
				xpSpan = remaining,
				levelUpAfter = false,
			}
			totalSpan += remaining
			intoLevel = toInto
			remaining = 0
		else
			-- Fills the rest of this level -> level-up.
			segments[#segments + 1] = {
				level = level,
				fromProgress = fractionOf(intoLevel, forNext),
				toProgress = 1,
				xpSpan = need,
				levelUpAfter = true,
			}
			totalSpan += need
			remaining -= need
			level += 1
			intoLevel = 0
			if level >= opts.maxLevel then
				break -- reached max: stop; bar rests full on the final level
			end
			forNext = opts.xpForLevel(level)
		end
	end

	local finalProgress = (level >= opts.maxLevel) and 1 or fractionOf(intoLevel, forNext)
	return {
		segments = segments,
		totalSpan = totalSpan,
		finalLevel = level,
		finalProgress = finalProgress,
	}
end

return XpFillModel
