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

-- (overlaps was removed in v2.3 with the angular kill-zone model; the constant-width
-- radius/pad behavior is covered by the isStruckSwept block below.)

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

-- isStruckSwept: swept-interval strike test on measured angles. A beam kills if its
-- arc CROSSED the body's angle since last tick (prevAngle -> angle along direction),
-- padded by a per-body local half-angle derived from the beam's constant STUD
-- half-width (killHalfWidth) at that body's radius; nil prevAngle or a >1 rad jump
-- (re-park) falls back to the instantaneous check. killHalfWidth = 2 at radius 30 ->
-- localHalfAngle = asin(2/30) ~= 0.0667 rad for every case below.
do
	local function beam(prev, ang, dir, class)
		return { prevAngle = prev, angle = ang, direction = dir, class = class,
			innerRadius = 6, outerRadius = 52, killHalfWidth = 2 }
	end
	local grounded = { radius = 30, angle = 0.3, airborne = false }
	-- bar swept 0.1 -> 0.5 (dir +1): body at 0.3 was crossed -> struck.
	expect(M.isStruckSwept(grounded, { beam(0.1, 0.5, 1, "low") }), "crossed body -> struck")
	-- same sweep but body at 0.8 (ahead, outside pad) -> safe.
	expect(not M.isStruckSwept({ radius = 30, angle = 0.8, airborne = false },
		{ beam(0.1, 0.5, 1, "low") }), "ahead of the sweep -> safe")
	-- airborne clears the low bar even when crossed.
	expect(not M.isStruckSwept({ radius = 30, angle = 0.3, airborne = true },
		{ beam(0.1, 0.5, 1, "low") }), "airborne clears low even when crossed")
	-- grounded clears the high bar even when crossed.
	expect(not M.isStruckSwept(grounded, { beam(0.1, 0.5, 1, "high") }),
		"grounded clears high even when crossed")
	-- direction -1: bar swept 0.5 -> 0.1; body at 0.3 crossed.
	expect(M.isStruckSwept(grounded, { beam(0.5, 0.1, -1, "low") }), "reverse sweep crosses too")
	-- wrap at the seam: bar swept (TAU-0.1) -> 0.1 (dir +1); body at 0.02 crossed.
	expect(M.isStruckSwept({ radius = 30, angle = 0.02, airborne = false },
		{ beam(TAU - 0.1, 0.1, 1, "low") }), "seam wrap crossed")
	-- re-park jump guard: span > 1 rad falls back to instantaneous -> body 1.5 away is safe.
	expect(not M.isStruckSwept({ radius = 30, angle = 1.5, airborne = false },
		{ beam(0, 3, 1, "low") }), "re-park jump cannot kill across the span")
	-- nil prevAngle: instantaneous only.
	expect(M.isStruckSwept({ radius = 30, angle = 0.05, airborne = false },
		{ beam(nil, 0, 1, "low") }), "first tick instantaneous hit")
	expect(not M.isStruckSwept({ radius = 30, angle = 0.5, airborne = false },
		{ beam(nil, 0, 1, "low") }), "first tick instantaneous miss")
	-- radius band still applies.
	expect(not M.isStruckSwept({ radius = 3, angle = 0.3, airborne = false },
		{ beam(0.1, 0.5, 1, "low") }), "inside hub radius -> safe")

	-- Constant-width property: the SAME 1.5-stud offset from the bar kills at every
	-- radius; the ANGULAR offset that equals 1.5 studs at r=15 (0.1 rad) is a MISS at
	-- r=50 (where 0.1 rad = 5 studs > the 2-stud kill half-width).
	local b = { prevAngle = nil, angle = 0, direction = 1, class = "low",
		innerRadius = 6, outerRadius = 52, killHalfWidth = 2 }
	expect(M.isStruckSwept({ radius = 15, angle = 1.5 / 15, airborne = false }, { b }),
		"1.5 studs off at r=15 -> struck")
	expect(M.isStruckSwept({ radius = 50, angle = 1.5 / 50, airborne = false }, { b }),
		"1.5 studs off at r=50 -> struck (constant width)")
	expect(not M.isStruckSwept({ radius = 50, angle = 0.1, airborne = false }, { b }),
		"0.1 rad at r=50 is 5 studs off -> miss (no angular widening)")
	print("sweeper: isStruckSwept OK")
end

print("ALL SweeperModel TESTS PASSED")
