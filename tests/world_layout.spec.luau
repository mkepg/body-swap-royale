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
		expect(a[i].z >= -50 and a[i].z <= 50, "wisp z in [-spread,spread]")
		expect(a[i].colorIndex >= 1 and a[i].colorIndex <= 8, "colorIndex within palette")
	end
	local c = WorldLayout.wispField(0, 100, 0, 50, 40, 12, 8, 9999)
	expect(not (approx(a[1].x, c[1].x) and approx(a[1].z, c[1].z)), "different seed -> different field")
	print("worldlayout: wispField OK")
end

-- cluster(cx, cz, baseY, n, spacing): `n` points in a single centered row along X
-- at constant y=baseY, z=cz; gap `spacing`; the group straddles (cx, cz).
do
	local cx, cz, baseY, n, spacing = 12, -64, 47, 6, 3
	local c = WorldLayout.cluster(cx, cz, baseY, n, spacing)
	expect(#c == n, "cluster returns `n` points, got " .. #c)

	-- constant y and z
	local sumX = 0
	for _, p in ipairs(c) do
		expect(approx(p.y, baseY), "cluster y is constant (baseY)")
		expect(approx(p.z, cz), "cluster z is constant (cz)")
		sumX += p.x
	end
	-- centered on cx (mean x == cx)
	expect(approx(sumX / n, cx), "cluster is centered on cx")

	-- even spacing along X
	local g = c[2].x - c[1].x
	expect(approx(g, spacing), "cluster spacing == `spacing`")
	for i = 2, #c - 1 do
		expect(approx(c[i + 1].x - c[i].x, g), "cluster points evenly spaced")
	end

	-- pairwise distinct
	for i = 1, #c do
		for j = i + 1, #c do
			expect(not approx(c[i].x, c[j].x), "cluster points must be distinct")
		end
	end
	print("worldlayout: cluster OK")
end

-- arc(cx, cz, radius, count, centerAngle, spread): `count` evenly spaced points across
-- the arc [centerAngle - spread/2, centerAngle + spread/2], each exactly `radius` from
-- center; count == 1 collapses to the single center point.
do
	local cx, cz, radius = 4, -9, 25
	local centerAngle, spread = math.pi, math.pi
	local pts = WorldLayout.arc(cx, cz, radius, 5, centerAngle, spread)
	expect(#pts == 5, "arc must return `count` points")
	for _, p in ipairs(pts) do
		local d = math.sqrt((p.x - cx) ^ 2 + (p.z - cz) ^ 2)
		expect(approx(d, radius, 1e-4), "each arc point must be `radius` from center, got " .. d)
	end
	-- endpoints at centerAngle - spread/2 (= pi/2) and centerAngle + spread/2 (= 3pi/2)
	local aStart, aEnd = centerAngle - spread / 2, centerAngle + spread / 2
	expect(approx(pts[1].x, cx + radius * math.cos(aStart)) and approx(pts[1].z, cz + radius * math.sin(aStart)),
		"arc first point at centerAngle - spread/2")
	expect(approx(pts[5].x, cx + radius * math.cos(aEnd)) and approx(pts[5].z, cz + radius * math.sin(aEnd)),
		"arc last point at centerAngle + spread/2")
	-- middle point (i=3 of 5) sits at centerAngle exactly
	expect(approx(pts[3].x, cx + radius * math.cos(centerAngle)) and approx(pts[3].z, cz + radius * math.sin(centerAngle)),
		"arc middle point at centerAngle")

	-- count == 1 collapses to the single center point
	local single = WorldLayout.arc(cx, cz, radius, 1, centerAngle, spread)
	expect(#single == 1, "arc count=1 returns exactly one point")
	expect(approx(single[1].x, cx + radius * math.cos(centerAngle))
		and approx(single[1].z, cz + radius * math.sin(centerAngle)),
		"arc count=1 point sits at centerAngle")

	-- even spacing between consecutive points: measure the angle BETWEEN consecutive
	-- points via the dot product (robust to the atan2 +-pi seam, which this arc crosses).
	local function stepAngle(p1, p2)
		local cosStep = ((p1.x - cx) * (p2.x - cx) + (p1.z - cz) * (p2.z - cz)) / (radius * radius)
		return math.acos(math.clamp(cosStep, -1, 1))
	end
	local step = stepAngle(pts[1], pts[2])
	for i = 2, #pts - 1 do
		expect(approx(stepAngle(pts[i], pts[i + 1]), step, 1e-4), "arc points evenly spaced")
	end
	print("worldlayout: arc OK")
end

print("ALL WorldLayout TESTS PASSED")
