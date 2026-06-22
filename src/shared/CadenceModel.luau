--[[
	CadenceModel -- PURE dynamic swap-cadence decision.
	Location (Roblox): ReplicatedStorage/Shared/CadenceModel  (ModuleScript)

	Stateless and Roblox-free, like SoulPalette: a pure function of the round's
	current shape. Maps (startCount, aliveCount, swapsSoFar) -> the next swap
	interval in seconds, compressing a calm round-start toward a frantic endgame.

	Two drivers, combined additively then clamped (dynamic-cadence design, Approach A):
	  countT    -- elimination progress: 0 at round start, 1 at the final duel.
	  progressT -- swapsSoFar / swapsToFloor, clamped to [0,1] (the stall-breaker so a
	               round where nobody dies still escalates; it also carries the N=2
	               case, where countT is pinned at 0 because the round ends at 1
	               survivor and nobody is eliminated mid-round).
	  t        = clamp(countT + stallWeight * progressT, 0, 1)
	  interval = lerp(maxInterval, minInterval, t)

	opts = { maxInterval, minInterval, swapsToFloor, stallWeight }. Passed in (not
	read from Config) so tests inject their own values.
--]]

local CadenceModel = {}

local function clamp(x, lo, hi)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

function CadenceModel.interval(startCount, aliveCount, swapsSoFar, opts)
	-- max(startCount - 2, 1) avoids divide-by-zero when startCount == 2 (the MVP
	-- duel): countT then stays 0 and the progress term carries the whole ramp.
	local denom = math.max(startCount - 2, 1)
	local countT = clamp((startCount - aliveCount) / denom, 0, 1)
	local progressT = clamp(swapsSoFar / opts.swapsToFloor, 0, 1)
	local t = clamp(countT + opts.stallWeight * progressT, 0, 1)
	return lerp(opts.maxInterval, opts.minInterval, t)
end

return CadenceModel
