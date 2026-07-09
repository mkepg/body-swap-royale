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

-- (beamAngle was removed in v2.1: the physics engine owns beam poses; consumers
-- read the MEASURED angle off the bar's replicated root instead.)

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
-- An unknown class must fail loudly (never silently behave like "high").
do
	expect(M.clears("low", true), "low + airborne -> cleared")
	expect(not M.clears("low", false), "low + grounded -> NOT cleared")
	expect(M.clears("high", false), "high + grounded -> cleared")
	expect(not M.clears("high", true), "high + airborne -> NOT cleared")
	local ok = pcall(M.clears, "sideways", false)
	expect(not ok, "unknown class -> errors (not silently 'high')")
	print("sweeper: clears OK")
end

-- isStruckAt: measured-angle strike test (beams carry their CURRENT physical angle).
do
	local beams = {
		{ angle = 0, class = "low", innerRadius = 6, outerRadius = 52, angularHalfWidth = 0.15 },
		{ angle = math.pi, class = "high", innerRadius = 6, outerRadius = 52, angularHalfWidth = 0.15 },
	}
	expect(M.isStruckAt({ radius = 20, angle = 0, airborne = false }, beams),
		"grounded under the low bar -> struck")
	expect(not M.isStruckAt({ radius = 20, angle = 0, airborne = true }, beams),
		"airborne clears the low bar")
	expect(not M.isStruckAt({ radius = 20, angle = math.pi, airborne = false }, beams),
		"grounded clears the high bar")
	expect(M.isStruckAt({ radius = 20, angle = math.pi, airborne = true }, beams),
		"airborne into the high bar -> struck")
	expect(not M.isStruckAt({ radius = 20, angle = 1.5, airborne = false }, beams),
		"between bars -> safe")
	expect(not M.isStruckAt({ radius = 3, angle = 0, airborne = false }, beams),
		"inside the hub radius -> safe")
	print("sweeper: isStruckAt OK")
end

-- outwardTarget: unit radial from center through the body, scaled to outRadius.
do
	local x, z = M.outwardTarget(5, 0, 0, 0, 30) -- body east of center
	expect(near(x, 30) and near(z, 0), "pushes straight out east to outRadius")
	local x2, z2 = M.outwardTarget(0, 0, 0, 0, 30) -- body exactly on center (degenerate)
	expect(near(x2, 30) and near(z2, 0), "degenerate center -> default +x")
	print("sweeper: outwardTarget OK")
end

print("ALL SweeperModel TESTS PASSED")
