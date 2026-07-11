local M = require("../src/shared/GlowDim")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- endpoints: factor 0 => base unchanged; factor 1 => fully faded (1).
do
	expect(approx(M.apply(0.5, 0), 0.5), "factor 0 returns base")
	expect(approx(M.apply(0.0, 0), 0.0), "factor 0, base 0")
	expect(approx(M.apply(0.5, 1), 1.0), "factor 1 => 1")
	expect(approx(M.apply(0.0, 1), 1.0), "factor 1 from opaque => 1")
	print("glowdim: endpoints OK")
end

-- interpolation: base + (1-base)*factor.
do
	expect(approx(M.apply(0.0, 0.4), 0.4), "opaque, 0.4 => 0.4")
	expect(approx(M.apply(0.5, 0.4), 0.7), "0.5 base, 0.4 => 0.7")
	expect(approx(M.apply(0.8, 0.5), 0.9), "0.8 base, 0.5 => 0.9")
	print("glowdim: interpolation OK")
end

-- monotonic non-decreasing in factor (dimmer never brightens).
do
	local prev = -1
	for i = 0, 10 do
		local v = M.apply(0.3, i / 10)
		expect(v >= prev - 1e-12, "monotonic in factor")
		prev = v
	end
	print("glowdim: monotonic OK")
end

-- clamps out-of-range inputs; result always in [0,1].
do
	expect(approx(M.apply(0.5, -1), 0.5), "negative factor clamps to 0")
	expect(approx(M.apply(0.5, 2), 1.0), "factor > 1 clamps to 1")
	expect(approx(M.apply(-1, 0.5), 0.5), "negative base clamps to 0 => 0.5")
	expect(approx(M.apply(2, 0.5), 1.0), "base > 1 clamps to 1 => 1")
	print("glowdim: clamp OK")
end

print("ALL GlowDim TESTS PASSED")
