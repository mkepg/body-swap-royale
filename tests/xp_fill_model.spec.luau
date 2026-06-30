local XpFillModel = require("../src/shared/XpFillModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local function approx(a, b)
	return math.abs(a - b) < 1e-6
end

-- Flat curve: every level costs 100. maxLevel high so no clamping.
local FLAT = { maxLevel = 100, xpForLevel = function() return 100 end }

-- No level-up: fills within the current level.
do
	local r = XpFillModel.build({ level = 3, xpIntoLevel = 20, xpForNext = 100 }, 30, FLAT)
	expect(#r.segments == 1, "one segment, got " .. tostring(#r.segments))
	local s = r.segments[1]
	expect(s.level == 3, "segment level 3")
	expect(approx(s.fromProgress, 0.2), "from 0.2, got " .. tostring(s.fromProgress))
	expect(approx(s.toProgress, 0.5), "to 0.5, got " .. tostring(s.toProgress))
	expect(s.xpSpan == 30, "span 30, got " .. tostring(s.xpSpan))
	expect(s.levelUpAfter == false, "no level-up")
	expect(r.totalSpan == 30, "totalSpan 30")
	expect(r.finalLevel == 3, "final level 3")
	expect(approx(r.finalProgress, 0.5), "final progress 0.5")
	print("xp-fill: no-levelup OK")
end

-- Exactly one level-up.
do
	local r = XpFillModel.build({ level = 3, xpIntoLevel = 80, xpForNext = 100 }, 50, FLAT)
	expect(#r.segments == 2, "two segments, got " .. tostring(#r.segments))
	expect(approx(r.segments[1].fromProgress, 0.8), "seg1 from 0.8")
	expect(approx(r.segments[1].toProgress, 1), "seg1 to 1.0")
	expect(r.segments[1].xpSpan == 20, "seg1 span 20")
	expect(r.segments[1].levelUpAfter == true, "seg1 levels up")
	expect(r.segments[2].level == 4, "seg2 level 4")
	expect(approx(r.segments[2].fromProgress, 0), "seg2 from 0")
	expect(approx(r.segments[2].toProgress, 0.3), "seg2 to 0.3")
	expect(r.segments[2].xpSpan == 30, "seg2 span 30")
	expect(r.segments[2].levelUpAfter == false, "seg2 no level-up")
	expect(r.totalSpan == 50, "totalSpan 50")
	expect(r.finalLevel == 4, "final level 4")
	expect(approx(r.finalProgress, 0.3), "final progress 0.3")
	print("xp-fill: one-levelup OK")
end

-- Lands exactly on a level boundary: one full segment, ends at the new level / 0 progress.
do
	local r = XpFillModel.build({ level = 3, xpIntoLevel = 80, xpForNext = 100 }, 20, FLAT)
	expect(#r.segments == 1, "one segment")
	expect(approx(r.segments[1].toProgress, 1), "fills to full")
	expect(r.segments[1].levelUpAfter == true, "levels up")
	expect(r.finalLevel == 4, "final level 4")
	expect(approx(r.finalProgress, 0), "final progress 0 (fresh level)")
	print("xp-fill: exact-boundary OK")
end

-- Multiple level-ups in one award.
do
	local r = XpFillModel.build({ level = 1, xpIntoLevel = 0, xpForNext = 100 }, 250, FLAT)
	expect(#r.segments == 3, "three segments, got " .. tostring(#r.segments))
	expect(r.segments[1].levelUpAfter == true and r.segments[2].levelUpAfter == true, "first two level up")
	expect(r.segments[3].levelUpAfter == false, "last does not")
	expect(r.segments[3].level == 3, "ends on level 3")
	expect(approx(r.segments[3].toProgress, 0.5), "ends at 0.5")
	expect(r.totalSpan == 250, "totalSpan 250")
	expect(r.finalLevel == 3 and approx(r.finalProgress, 0.5), "final 3 @ 0.5")
	print("xp-fill: multi-levelup OK")
end

-- Max-level clamp: the fill stops at maxLevel, bar rests full, excess discarded.
do
	local opts = { maxLevel = 100, xpForLevel = function() return 100 end }
	local r = XpFillModel.build({ level = 99, xpIntoLevel = 0, xpForNext = 100 }, 500, opts)
	expect(#r.segments == 1, "one segment (then clamps)")
	expect(r.segments[1].level == 99, "segment level 99")
	expect(r.segments[1].levelUpAfter == true, "levels up into max")
	expect(r.totalSpan == 100, "only 100 of the 500 fills the bar")
	expect(r.finalLevel == 100, "final level 100 (max)")
	expect(approx(r.finalProgress, 1), "rests full at max")
	print("xp-fill: max-clamp OK")
end

-- Already at max: nothing animates, rests full.
do
	local r = XpFillModel.build({ level = 100, xpIntoLevel = 0, xpForNext = 0 }, 50, FLAT)
	expect(#r.segments == 0, "no segments")
	expect(r.totalSpan == 0, "no span")
	expect(r.finalLevel == 100, "stays max")
	expect(approx(r.finalProgress, 1), "rests full")
	print("xp-fill: already-max OK")
end

-- Zero / negative delta: nothing animates, rests at the start fraction.
do
	local r = XpFillModel.build({ level = 2, xpIntoLevel = 30, xpForNext = 100 }, 0, FLAT)
	expect(#r.segments == 0, "no segments for 0 delta")
	expect(r.finalLevel == 2 and approx(r.finalProgress, 0.3), "rests at start 0.3")
	local n = XpFillModel.build({ level = 2, xpIntoLevel = 30, xpForNext = 100 }, -10, FLAT)
	expect(#n.segments == 0, "no segments for negative delta")
	print("xp-fill: zero-negative OK")
end

-- Invariant: sum of xpSpan equals totalSpan, on a varied curve.
do
	local opts = { maxLevel = 100, xpForLevel = function(l) return 100 + l end }
	local r = XpFillModel.build({ level = 5, xpIntoLevel = 10, xpForNext = 105 }, 400, opts)
	local sum = 0
	for _, s in ipairs(r.segments) do sum += s.xpSpan end
	expect(sum == r.totalSpan, "sum(xpSpan) == totalSpan")
	print("xp-fill: span-invariant OK")
end

print("ALL XpFillModel TESTS PASSED")
