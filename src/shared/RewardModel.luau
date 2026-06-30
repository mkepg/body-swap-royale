--[[
	RewardModel -- PURE per-round reward math. Roblox-free, no clocks/RNG.
	ctx  = { survivedSwaps, isWinner, participated }
	opts = { xpBase, xpPerSwap, xpWin, coinsBase, coinsPerSwap, coinsWin }
	Returns { coins, xp }. Survival-depth model: longer survival (more swaps lived
	through) earns more, with a flat participation base and a winner bonus.
	Location (Roblox): ReplicatedStorage/Shared/RewardModel  (ModuleScript)
--]]

local RewardModel = {}

function RewardModel.rewardFor(ctx, opts)
	if not ctx.participated then
		return { coins = 0, xp = 0 }
	end
	local swaps = math.max(0, ctx.survivedSwaps or 0)
	local xp = opts.xpBase + opts.xpPerSwap * swaps
	local coins = opts.coinsBase + opts.coinsPerSwap * swaps
	if ctx.isWinner then
		xp += opts.xpWin
		coins += opts.coinsWin
	end
	return { coins = coins, xp = xp }
end

return RewardModel
