local CadenceModel = require("../src/shared/CadenceModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local function approx(a, b)
	return math.abs(a - b) < 1e-9
end

-- Mirrors the Config defaults (max 20, min 8, floor at 8 swaps, full-weight progress).
local OPTS = { maxInterval = 20, minInterval = 8, swapsToFloor = 8, stallWeight = 1.0 }

-- round start: full lobby, no swaps -> exactly maxInterval.
do
	expect(approx(CadenceModel.interval(8, 8, 0, OPTS), 20), "round start must be maxInterval")
	print("cadence: round start -> max OK")
end

-- final duel in a big lobby (countT == 1) -> exactly minInterval.
do
	expect(approx(CadenceModel.interval(8, 2, 0, OPTS), 8), "final duel (countT=1) -> min")
	print("cadence: final duel -> min OK")
end

-- always within [min, max] for arbitrary / absurd inputs (incl. alive>start, negative swaps).
do
	local cases = {
		{ 8, 8, 0 }, { 8, 2, 100 }, { 16, 1, 0 }, { 2, 2, 0 }, { 2, 2, 1000 }, { 8, 9, 0 }, { 8, 8, -5 },
	}
	for _, c in ipairs(cases) do
		local v = CadenceModel.interval(c[1], c[2], c[3], OPTS)
		expect(v >= OPTS.minInterval - 1e-9 and v <= OPTS.maxInterval + 1e-9,
			"interval out of range for " .. c[1] .. "," .. c[2] .. "," .. c[3])
	end
	print("cadence: always within [min,max] OK")
end

-- non-increasing as aliveCount drops (more eliminations -> faster).
do
	local prev = math.huge
	for alive = 8, 2, -1 do
		local v = CadenceModel.interval(8, alive, 0, OPTS)
		expect(v <= prev + 1e-9, "interval must not increase as aliveCount drops")
		prev = v
	end
	print("cadence: monotonic in aliveCount OK")
end

-- non-increasing as swapsSoFar rises (round drags -> faster).
do
	local prev = math.huge
	for swaps = 0, 12 do
		local v = CadenceModel.interval(8, 8, swaps, OPTS)
		expect(v <= prev + 1e-9, "interval must not increase as swapsSoFar rises")
		prev = v
	end
	print("cadence: monotonic in swapsSoFar OK")
end

-- N=2: countT pinned at 0 (both alive the whole round); progress alone ramps from
-- max down to exactly min by swapsToFloor swaps.
do
	expect(approx(CadenceModel.interval(2, 2, 0, OPTS), 20), "N=2 start -> max")
	expect(approx(CadenceModel.interval(2, 2, 4, OPTS), 14), "N=2 halfway -> 14")
	expect(approx(CadenceModel.interval(2, 2, 8, OPTS), 8), "N=2 at swapsToFloor -> min")
	print("cadence: N=2 progress-only ramp OK")
end

-- divide-by-zero safety at startCount == 2 (denom clamps to 1; no NaN/error).
do
	local v = CadenceModel.interval(2, 2, 0, OPTS)
	expect(v == v, "must not be NaN at startCount==2") -- NaN ~= NaN
	print("cadence: startCount==2 no divide-by-zero OK")
end

print("ALL CADENCEMODEL TESTS PASSED")
