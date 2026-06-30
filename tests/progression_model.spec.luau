local ProgressionModel = require("../src/shared/ProgressionModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local OPTS = { coeff = 100, exp = 1.4, maxLevel = 100 }

-- xpForLevel(1) = floor(100 * 1^1.4) = 100.
do
	expect(ProgressionModel.xpForLevel(1, OPTS) == 100, "L1 needs 100, got " .. tostring(ProgressionModel.xpForLevel(1, OPTS)))
	print("progression: xpForLevel-base OK")
end

-- xpForLevel is strictly increasing.
do
	local prev = -1
	for level = 1, 50 do
		local need = ProgressionModel.xpForLevel(level, OPTS)
		expect(need > prev, "xpForLevel not increasing at level " .. level)
		prev = need
	end
	print("progression: xpForLevel-monotonic OK")
end

-- 0 xp -> level 1, no progress.
do
	local v = ProgressionModel.levelFor(0, OPTS)
	expect(v.level == 1, "0 xp is level 1, got " .. tostring(v.level))
	expect(v.xpIntoLevel == 0, "0 xp into level")
	expect(v.xpForNext == 100, "next needs 100")
	expect(v.progress == 0, "no progress")
	print("progression: levelFor-zero OK")
end

-- Just below the L1->L2 threshold stays level 1; exactly at it becomes level 2.
do
	local below = ProgressionModel.levelFor(99, OPTS)
	expect(below.level == 1, "99 xp still level 1, got " .. tostring(below.level))
	expect(below.xpIntoLevel == 99, "99 into level 1")
	expect(below.progress > 0 and below.progress < 1, "progress in (0,1), got " .. tostring(below.progress))
	local at = ProgressionModel.levelFor(100, OPTS)
	expect(at.level == 2, "100 xp is level 2, got " .. tostring(at.level))
	expect(at.xpIntoLevel == 0, "0 into level 2")
	print("progression: levelFor-threshold OK")
end

-- Clamp at maxLevel: enormous xp pins to maxLevel with full progress and no next.
do
	local v = ProgressionModel.levelFor(1e12, OPTS)
	expect(v.level == 100, "clamped to maxLevel, got " .. tostring(v.level))
	expect(v.progress == 1, "max level full progress")
	expect(v.xpForNext == 0, "no next at max level")
	print("progression: levelFor-clamp OK")
end

print("ALL ProgressionModel TESTS PASSED")
