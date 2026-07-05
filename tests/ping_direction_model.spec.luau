local M = require("../src/shared/PingDirectionModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1) end

local W, H, MARGIN = 1000, 800, 50 -- center = (500, 400)

-- dead-center, in front -> onScreen.
do
	local r = M.resolve(500, 400, 10, W, H, MARGIN)
	expect(r.onScreen, "center in front -> onScreen")
	print("ping: onScreen center OK")
end

-- far off the right, in front -> off-screen, clamped to right margin, points right (~90deg).
do
	local r = M.resolve(5000, 400, 10, W, H, MARGIN)
	expect(not r.onScreen, "off right -> not onScreen")
	expect(near(r.x, W - MARGIN, 2), "clamped to right margin, got " .. r.x)
	expect(near(r.rotationDeg, 90, 1), "points right (~90), got " .. r.rotationDeg)
	print("ping: off-right OK")
end

-- far above, in front -> off-screen, clamped to top margin, points up (~0deg).
do
	local r = M.resolve(500, -5000, 10, W, H, MARGIN)
	expect(not r.onScreen, "above -> not onScreen")
	expect(near(r.y, MARGIN, 2), "clamped to top margin, got " .. r.y)
	expect(near(r.rotationDeg, 0, 1), "points up (~0), got " .. r.rotationDeg)
	print("ping: off-top OK")
end

-- behind camera (z<0), projected point reads bottom-left; must flip to point the true way.
do
	-- target behind + to the true right: WorldToViewportPoint mirrors it to the left.
	local r = M.resolve(200, 400, -10, W, H, MARGIN)
	expect(not r.onScreen, "behind camera -> not onScreen")
	-- projected dx = 200-500 = -300; flipped -> +300 -> points right (~90).
	expect(near(r.rotationDeg, 90, 1), "behind-camera direction flipped, got " .. r.rotationDeg)
	print("ping: behind-camera flip OK")
end

-- a point just inside the margin rect, in front -> onScreen.
do
	local r = M.resolve(MARGIN + 5, 400, 10, W, H, MARGIN)
	expect(r.onScreen, "just inside left margin -> onScreen")
	print("ping: inside-margin OK")
end

print("ALL PingDirectionModel TESTS PASSED")
