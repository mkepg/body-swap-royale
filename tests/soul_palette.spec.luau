local SoulPalette = require("../src/shared/SoulPalette")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local P = { "red", "green", "blue" } -- 3-entry palette

-- 1-based index maps straight through within palette size.
do
	expect(SoulPalette.colorForIndex(1, P) == "red", "index 1 -> red")
	expect(SoulPalette.colorForIndex(2, P) == "green", "index 2 -> green")
	expect(SoulPalette.colorForIndex(3, P) == "blue", "index 3 -> blue")
	print("soul: in-range mapping OK")
end

-- distinct indices within the palette give distinct colors.
do
	local a = SoulPalette.colorForIndex(1, P)
	local b = SoulPalette.colorForIndex(2, P)
	local c = SoulPalette.colorForIndex(3, P)
	expect(a ~= b and b ~= c and a ~= c, "first N indices must be distinct")
	print("soul: distinctness OK")
end

-- wraps modulo palette size past the end.
do
	expect(SoulPalette.colorForIndex(4, P) == "red", "index 4 wraps to red")
	expect(SoulPalette.colorForIndex(6, P) == "blue", "index 6 wraps to blue")
	expect(SoulPalette.colorForIndex(7, P) == "red", "index 7 wraps to red")
	print("soul: wrap OK")
end

-- deterministic: same inputs, same output.
do
	expect(SoulPalette.colorForIndex(5, P) == SoulPalette.colorForIndex(5, P), "deterministic")
	print("soul: determinism OK")
end

print("ALL SoulPalette TESTS PASSED")
