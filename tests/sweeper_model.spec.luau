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

-- rampedSpeed: monotonic increase from base, clamped to maxSpeed, floored at elapsed 0.
do
	local opts = { rampPerSecond = 0.1, maxSpeed = 2 }
	expect(near(M.rampedSpeed(1, 0, opts), 1), "elapsed 0 -> base")
	expect(near(M.rampedSpeed(1, 5, opts), 1.5), "ramps up over time")
	expect(near(M.rampedSpeed(1, 1000, opts), 2), "clamped to maxSpeed")
	expect(near(M.rampedSpeed(1, -5, opts), 1), "negative elapsed floored to base")
	print("sweeper: rampedSpeed OK")
end

-- overlaps: inside the radius band AND within the beam's angular half-width.
do
	local opts = { innerRadius = 3, outerRadius = 30, angularHalfWidth = 0.15 }
	expect(M.overlaps(10, 0.0, 0.1, opts), "within band + arc -> true")
	expect(not M.overlaps(10, 0.0, 0.3, opts), "outside arc -> false")
	expect(not M.overlaps(1, 0.0, 0.0, opts), "inside inner radius (hub) -> false")
	expect(not M.overlaps(40, 0.0, 0.0, opts), "beyond outer radius -> false")
	print("sweeper: overlaps OK")
end

-- clears: low beam cleared by being airborne; high beam cleared by being grounded.
do
	expect(M.clears("low", true), "low + airborne -> cleared")
	expect(not M.clears("low", false), "low + grounded -> NOT cleared")
	expect(M.clears("high", false), "high + grounded -> cleared")
	expect(not M.clears("high", true), "high + airborne -> NOT cleared")
	print("sweeper: clears OK")
end

print("ALL SweeperModel TESTS PASSED")
