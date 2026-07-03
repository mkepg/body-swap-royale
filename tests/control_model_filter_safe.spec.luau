local ControlModel = require("../src/shared/ControlModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- All safe: order preserved, nothing dropped.
do
	local safe = { A = true, B = true, C = true }
	local out = ControlModel.filterSafe({ "A", "B", "C" }, function(p) return safe[p] end)
	expect(#out == 3, "all-safe keeps everyone")
	expect(out[1] == "A" and out[2] == "B" and out[3] == "C", "order preserved")
	print("filterSafe: all safe OK")
end

-- One doomed: excluded, order of the rest preserved.
do
	local safe = { A = true, B = false, C = true }
	local out = ControlModel.filterSafe({ "A", "B", "C" }, function(p) return safe[p] end)
	expect(#out == 2, "doomed player excluded")
	expect(out[1] == "A" and out[2] == "C", "remaining order preserved")
	print("filterSafe: one doomed excluded OK")
end

-- Only one safe: returns a size-1 roster (caller's < 2 guard suppresses the swap).
do
	local safe = { A = false, B = true, C = false }
	local out = ControlModel.filterSafe({ "A", "B", "C" }, function(p) return safe[p] end)
	expect(#out == 1 and out[1] == "B", "single safe survivor returned")
	print("filterSafe: single safe OK")
end

-- None safe: empty roster.
do
	local out = ControlModel.filterSafe({ "A", "B" }, function() return false end)
	expect(#out == 0, "none safe -> empty")
	print("filterSafe: none safe OK")
end

-- Does not mutate the input list.
do
	local input = { "A", "B", "C" }
	ControlModel.filterSafe(input, function(p) return p ~= "B" end)
	expect(#input == 3 and input[2] == "B", "input list untouched")
	print("filterSafe: input untouched OK")
end

print("ALL FILTERSAFE TESTS PASSED")
