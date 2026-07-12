--[[
	GlowDim (shared, pure) -- softens a Neon effect's glow by a per-effect dim factor.
	Roblox-free and lune-tested. Raises a base part Transparency toward 1 (Neon emits
	softer the more transparent it is); each visual effect passes its own
	Config.GLOW_DIM_* factor so the whole world dims independently, effect by effect.
	Default factors are 0 (no dim = original brightness).

	Location: ReplicatedStorage/Shared/GlowDim (ModuleScript)
--]]

local GlowDim = {}

local function clamp01(x)
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- base in [0,1] (a part's resting Transparency), factor in [0,1] (0 = unchanged,
-- 1 = fully faded). Returns base + (1 - base) * factor, all clamped to [0,1].
-- Monotonic non-decreasing in factor: factor 0 -> base, factor 1 -> 1.
function GlowDim.apply(baseTransparency, factor)
	local b = clamp01(baseTransparency)
	local f = clamp01(factor)
	return b + (1 - b) * f
end

return GlowDim
