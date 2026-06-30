local RewardModel = require("../src/shared/RewardModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local OPTS = {
	xpBase = 25, xpPerSwap = 5, xpWin = 100,
	coinsBase = 15, coinsPerSwap = 4, coinsWin = 40,
}

-- Participation only (0 swaps, not winner): base coins + base xp.
do
	local r = RewardModel.rewardFor({ survivedSwaps = 0, isWinner = false, participated = true }, OPTS)
	expect(r.xp == 25, "base xp, got " .. tostring(r.xp))
	expect(r.coins == 15, "base coins, got " .. tostring(r.coins))
	print("reward: participation-only OK")
end

-- Per-swap scaling (3 swaps, not winner).
do
	local r = RewardModel.rewardFor({ survivedSwaps = 3, isWinner = false, participated = true }, OPTS)
	expect(r.xp == 25 + 15, "xp 25+5*3, got " .. tostring(r.xp))
	expect(r.coins == 15 + 12, "coins 15+4*3, got " .. tostring(r.coins))
	print("reward: per-swap OK")
end

-- Winner bonus on top of swaps (5 swaps + win).
do
	local r = RewardModel.rewardFor({ survivedSwaps = 5, isWinner = true, participated = true }, OPTS)
	expect(r.xp == 25 + 25 + 100, "xp 25+25+100, got " .. tostring(r.xp))
	expect(r.coins == 15 + 20 + 40, "coins 15+20+40, got " .. tostring(r.coins))
	print("reward: winner-bonus OK")
end

-- Non-participant earns nothing.
do
	local r = RewardModel.rewardFor({ survivedSwaps = 9, isWinner = false, participated = false }, OPTS)
	expect(r.xp == 0 and r.coins == 0, "non-participant earns 0")
	print("reward: non-participant OK")
end

-- Defensive: negative/nil survivedSwaps clamps to 0.
do
	local r = RewardModel.rewardFor({ survivedSwaps = -4, isWinner = false, participated = true }, OPTS)
	expect(r.xp == 25 and r.coins == 15, "negative swaps clamp to base")
	print("reward: negative-clamp OK")
end

print("ALL RewardModel TESTS PASSED")
