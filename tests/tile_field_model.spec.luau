local TileFieldModel = require("../src/shared/TileFieldModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local DUR = { solid = 4, warning = 2, gone = 1.5 } -- period = 7.5
local PERIOD = DUR.solid + DUR.warning + DUR.gone

-- offset 0: walk a single period across every boundary.
do
	local function phase(t)
		return TileFieldModel.phaseAt(t, 0, 0, DUR)
	end
	expect(phase(0) == "solid", "t=0 must be solid")
	expect(phase(3.999) == "solid", "just before solid end must be solid")
	expect(phase(4) == "warning", "at solid end must be warning")
	expect(phase(5.999) == "warning", "just before warning end must be warning")
	expect(phase(6) == "gone", "at warning end must be gone")
	expect(phase(7.499) == "gone", "just before period end must be gone")
	expect(phase(7.5) == "solid", "at period wrap must be solid again")
	print("tile: phase boundaries (offset 0) OK")
end

-- a non-zero offset shifts the timeline by exactly `offset`.
do
	local a = TileFieldModel.phaseAt(2, 0, 1, DUR) -- (2 - 0 + 1) = 3
	local b = TileFieldModel.phaseAt(3, 0, 0, DUR) -- (3 - 0 + 0) = 3
	expect(a == b, "offset must shift the timeline by exactly offset")
	print("tile: offset shift OK")
end

-- round-start safety: at now == roundStart, every offset in [0, solid) is solid.
do
	for i = 0, 39 do
		local offset = (i / 40) * DUR.solid -- spans [0, solid)
		local p = TileFieldModel.phaseAt(100, 100, offset, DUR)
		expect(p == "solid", "offset in [0, solid) must be solid at roundStart")
	end
	print("tile: round-start all-solid invariant OK")
end

-- monotonic progression solid -> warning -> gone -> solid within one period.
do
	local seen = {}
	local order = {}
	local prev = nil
	for k = 0, 75 do
		local t = (k / 75) * PERIOD
		local p = TileFieldModel.phaseAt(t, 0, 0, DUR)
		if p ~= prev then
			order[#order + 1] = p
			prev = p
		end
		seen[p] = true
	end
	expect(seen.solid and seen.warning and seen.gone, "all three phases must appear")
	expect(order[1] == "solid" and order[2] == "warning" and order[3] == "gone",
		"phases must progress solid -> warning -> gone")
	print("tile: monotonic progression OK")
end

-- offsetFor: deterministic, and always in [0, solid).
do
	local o1 = TileFieldModel.offsetFor(3, 5, DUR.solid)
	local o2 = TileFieldModel.offsetFor(3, 5, DUR.solid)
	expect(o1 == o2, "offsetFor must be deterministic for the same coords")
	for row = 0, 7 do
		for col = 0, 7 do
			local o = TileFieldModel.offsetFor(row, col, DUR.solid)
			expect(o >= 0 and o < DUR.solid, "offsetFor must be in [0, solid)")
		end
	end
	print("tile: offsetFor determinism + range OK")
end

print("ALL TileFieldModel TESTS PASSED")
