local M = require("../src/shared/SweeperModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local TAU = math.pi * 2

-- angularDistance: symmetric, wraps at the 0/2π seam, max is π.
do
	expect(near(M.angularDistance(0, 0), 0), "same angle -> 0")
	expect(near(M.angularDistance(0.1, TAU - 0.1), 0.2), "wraps across the 0/2π seam")
	expect(near(M.angularDistance(TAU - 0.1, 0.1), 0.2), "symmetric across the seam")
	expect(near(M.angularDistance(0, math.pi), math.pi), "opposite -> π (max)")
	expect(near(M.angularDistance(0, math.pi + 1), math.pi - 1), "never exceeds π")
	print("sweeper: angularDistance seam OK")
end

-- beamAngle: base + direction*speed*elapsed + arm offset, normalized to [0, 2π).
do
	local beam = { baseAngle = 0, direction = 1, armCount = 1 }
	expect(near(M.beamAngle(beam, 0, 2, 0), 0), "t=0 -> baseAngle")
	expect(near(M.beamAngle(beam, 0, 2, 1), 2), "advances by speed*elapsed")
	-- direction -1 wraps to just under 2π
	local rev = { baseAngle = 0, direction = -1, armCount = 1 }
	expect(near(M.beamAngle(rev, 0, 1, 1), TAU - 1), "reverse wraps into [0,2π)")
	-- 2 arms are π apart
	local two = { baseAngle = 0, direction = 1, armCount = 2 }
	expect(near(M.beamAngle(two, 0, 0, 0), 0), "arm 0 at base")
	expect(near(M.beamAngle(two, 1, 0, 0), math.pi), "arm 1 offset by π")
	print("sweeper: beamAngle OK")
end

print("ALL SweeperModel TESTS PASSED")
