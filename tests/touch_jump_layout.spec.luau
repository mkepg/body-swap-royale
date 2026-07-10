local M = require("../src/shared/TouchJumpLayout")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- Default sizes at scale 1 reproduce the engine's TouchJump exactly
-- (verified against the live PlayerModule source 2026-07-10, classic path).
do
	local phone = M.compute(844, 390, 1) -- landscape phone: minAxis 390 <= 500
	expect(phone.isSmallScreen == true, "phone -> small screen")
	expect(phone.size == 70, "phone base size 70")
	expect(near(phone.xOffset, -(70 * 1.5 - 10)), "phone xOffset = -(size*1.5-10)")
	expect(near(phone.yOffset, -70 - 20), "phone yOffset = -size-20")

	local tablet = M.compute(1180, 820, 1) -- iPad-class: minAxis 820 > 500
	expect(tablet.isSmallScreen == false, "tablet -> large screen")
	expect(tablet.size == 120, "tablet base size 120")
	expect(near(tablet.xOffset, -(120 * 1.5 - 10)), "tablet xOffset formula")
	expect(near(tablet.yOffset, -120 * 1.75), "tablet yOffset = -size*1.75")
	print("touchjump: default sizes OK")
end

-- Comfort scale multiplies SIZE; the position formulas take the scaled size
-- (margins grow with the button -- it can never leave the screen).
do
	local phone = M.compute(844, 390, 1.3)
	expect(phone.size == 91, "70 * 1.3 rounds to 91")
	expect(near(phone.xOffset, -(91 * 1.5 - 10)), "scaled phone xOffset uses scaled size")
	expect(near(phone.yOffset, -91 - 20), "scaled phone yOffset uses scaled size")
	local tablet = M.compute(1180, 820, 1.3)
	expect(tablet.size == 156, "120 * 1.3 = 156")
	expect(near(tablet.yOffset, -156 * 1.75), "scaled tablet yOffset uses scaled size")
	print("touchjump: comfort scale OK")
end

-- Breakpoint boundary + orientation: min axis decides, exactly at <= 500.
do
	expect(M.compute(2000, 500, 1).isSmallScreen == true, "minAxis 500 -> small (inclusive)")
	expect(M.compute(2000, 501, 1).isSmallScreen == false, "minAxis 501 -> large")
	expect(M.compute(390, 844, 1).isSmallScreen == true, "portrait phone -> small (min of both axes)")
	print("touchjump: breakpoint OK")
end

-- Bad scale fails loudly (never a silently invisible/garbage button).
do
	expect(not pcall(M.compute, 844, 390, 0), "scale 0 -> errors")
	expect(not pcall(M.compute, 844, 390, -1), "negative scale -> errors")
	print("touchjump: scale guard OK")
end

print("ALL TouchJumpLayout TESTS PASSED")
