local WorldLayout = require("../src/shared/WorldLayout")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function approx(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- ring(cx, cz, radius, count): `count` points, each exactly `radius` from center.
do
	local pts = WorldLayout.ring(10, -5, 20, 8)
	expect(#pts == 8, "ring must return `count` points")
	for _, p in ipairs(pts) do
		local d = math.sqrt((p.x - 10) ^ 2 + (p.z + 5) ^ 2)
		expect(approx(d, 20, 1e-4), "each ring point must be `radius` from center, got " .. d)
	end
	-- first point starts at angle 0 (+X axis)
	expect(approx(pts[1].x, 30) and approx(pts[1].z, -5), "ring point 1 must be at +X")
	print("worldlayout: ring OK")
end

-- paletteIndex(i, len): 1-based, wraps.
do
	expect(WorldLayout.paletteIndex(1, 8) == 1, "paletteIndex(1,8)==1")
	expect(WorldLayout.paletteIndex(8, 8) == 8, "paletteIndex(8,8)==8")
	expect(WorldLayout.paletteIndex(9, 8) == 1, "paletteIndex wraps to 1")
	expect(WorldLayout.paletteIndex(10, 8) == 2, "paletteIndex(10,8)==2")
	print("worldlayout: paletteIndex OK")
end

-- footprintCorners(cx, cz, footX, footZ, margin): 4 corners at half-extent + margin.
do
	local c = WorldLayout.footprintCorners(0, 0, 60, 40, 5)
	expect(#c == 4, "must be 4 corners")
	-- half extents: x=30+5=35, z=20+5=25
	expect(approx(c[1].x, -35) and approx(c[1].z, -25), "corner 1 = (-35,-25)")
	expect(approx(c[3].x, 35) and approx(c[3].z, 25), "corner 3 = (35,25)")
	print("worldlayout: footprintCorners OK")
end

-- wispField is deterministic for a seed, count is exact, points are in-bounds,
-- colorIndex wraps over paletteLen.
do
	local a = WorldLayout.wispField(0, 100, 0, 50, 40, 12, 8, 1234)
	local b = WorldLayout.wispField(0, 100, 0, 50, 40, 12, 8, 1234)
	expect(#a == 12, "wispField count exact")
	for i = 1, #a do
		expect(approx(a[i].x, b[i].x) and approx(a[i].y, b[i].y) and approx(a[i].z, b[i].z),
			"wispField must be deterministic for a seed")
		expect(a[i].x >= -50 and a[i].x <= 50, "wisp x in [-spread,spread]")
		expect(a[i].y >= 100 and a[i].y <= 140, "wisp y in [cy, cy+height]")
		expect(a[i].colorIndex >= 1 and a[i].colorIndex <= 8, "colorIndex within palette")
	end
	local c = WorldLayout.wispField(0, 100, 0, 50, 40, 12, 8, 9999)
	expect(not (approx(a[1].x, c[1].x) and approx(a[1].z, c[1].z)), "different seed -> different field")
	print("worldlayout: wispField OK")
end

print("ALL WorldLayout TESTS PASSED")
