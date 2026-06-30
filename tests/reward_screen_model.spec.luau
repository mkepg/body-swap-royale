local RewardScreenModel = require("../src/shared/RewardScreenModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- No grant -> panel hidden.
do
	local d = RewardScreenModel.display(nil, { level = 5, progress = 0.2 })
	expect(d.visible == false, "no grant hides panel")
	print("reward-screen: hidden OK")
end

-- A normal grant renders +Coins / +XP and a plain level line.
do
	local d = RewardScreenModel.display(
		{ coins = 27, xp = 40, leveledUp = false },
		{ level = 6, progress = 0.5 }
	)
	expect(d.visible == true, "grant shows panel")
	expect(d.coinsText == "+27 Coins", "got " .. tostring(d.coinsText))
	expect(d.xpText == "+40 XP", "got " .. tostring(d.xpText))
	expect(d.levelText == "Level 6", "got " .. tostring(d.levelText))
	expect(d.levelBarProgress == 0.5, "progress passed through")
	expect(d.leveledUp == false, "no level-up flag")
	print("reward-screen: grant OK")
end

-- A level-up grant calls it out.
do
	local d = RewardScreenModel.display(
		{ coins = 95, xp = 150, leveledUp = true },
		{ level = 7, progress = 0.1 }
	)
	expect(d.leveledUp == true, "level-up flagged")
	expect(d.levelText == "Level Up!  7", "got " .. tostring(d.levelText))
	print("reward-screen: level-up OK")
end

print("ALL RewardScreenModel TESTS PASSED")
