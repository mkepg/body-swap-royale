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

-- tierRows(originX, originZ, baseY, halfX, halfZ, rows, rise, depth, perSide, spacing):
-- U-wrap risers (back + 2 wings, front/+Z open). Per row: perSide back orbs +
-- perSide left + perSide right => rows*3*perSide points. y climbs per row; rows
-- recede outward; NOTHING reaches the front edge (z stays <= originZ).
do
	local ox, oz, baseY = 0, -64, 45
	local halfX, halfZ = 24, 24
	local rows, rise, depth, perSide, spacing = 3, 3.5, 3, 5, 7
	local t = WorldLayout.tierRows(ox, oz, baseY, halfX, halfZ, rows, rise, depth, perSide, spacing)
	expect(#t == rows * 3 * perSide, "tierRows count must be rows*3*perSide, got " .. #t)

	-- front edge stays open: no point at/beyond the +Z railing line.
	local maxZ = -math.huge
	for _, p in ipairs(t) do maxZ = math.max(maxZ, p.z) end
	expect(maxZ <= oz + 1e-6, "tierRows must leave the front (+Z) edge open (z <= originZ)")

	-- y spans the 3 rows (rake): lowest = baseY+rise, highest = baseY+rows*rise.
	local minY, maxY = math.huge, -math.huge
	for _, p in ipairs(t) do minY = math.min(minY, p.y); maxY = math.max(maxY, p.y) end
	expect(approx(minY, baseY + rise), "lowest row sits at baseY + rise")
	expect(approx(maxY, baseY + rows * rise), "highest row sits at baseY + rows*rise")

	-- outward recede: a back-row point in row 2 is further -Z than in row 1.
	local backZ = { [1] = math.huge, [2] = math.huge, [3] = math.huge }
	for _, p in ipairs(t) do
		local r = approx(p.y, baseY + rise) and 1 or (approx(p.y, baseY + 2 * rise) and 2 or 3)
		backZ[r] = math.min(backZ[r], p.z)
	end
	expect(backZ[1] > backZ[2] and backZ[2] > backZ[3], "outer rows recede further back (-Z)")

	-- pairwise distinct
	for i = 1, #t do
		for j = i + 1, #t do
			expect(not (approx(t[i].x, t[j].x) and approx(t[i].y, t[j].y) and approx(t[i].z, t[j].z)),
				"tierRows points must be pairwise distinct")
		end
	end
	print("worldlayout: tierRows OK")
end

-- festoonStrand(x1,y1,z1, x2,y2,z2, count, sag): `count` points along the segment
-- with a parabolic droop (0 at the posts, `sag` below mid). Endpoints exact; the
-- droop is symmetric about mid-span.
do
	local pts = WorldLayout.festoonStrand(0, 20, 0, 8, 20, 0, 5, 4)
	expect(#pts == 5, "festoonStrand returns `count` points")
	expect(approx(pts[1].x, 0) and approx(pts[1].y, 20) and approx(pts[1].z, 0), "end 1 at post 1")
	expect(approx(pts[5].x, 8) and approx(pts[5].y, 20) and approx(pts[5].z, 0), "end 2 at post 2")
	expect(approx(pts[3].x, 4) and approx(pts[3].y, 16), "mid-span dips by sag (20-4=16)")
	expect(approx(pts[2].y, pts[4].y), "droop symmetric about mid-span")
	expect(pts[2].y < 20 and pts[3].y < 20 and pts[4].y < 20, "interior bulbs dip below the posts")
	print("worldlayout: festoonStrand OK")
end

-- buntingFlags(x1,z1,x2,z2, y, count): `count` evenly spaced points along the
-- segment at constant height y.
do
	local f = WorldLayout.buntingFlags(-24, -64, 24, -64, 6, 5)
	expect(#f == 5, "buntingFlags returns `count` points")
	for _, p in ipairs(f) do expect(approx(p.y, 6), "bunting y is constant") end
	expect(approx(f[1].x, -24) and approx(f[5].x, 24), "endpoints at the segment ends")
	local g1 = f[2].x - f[1].x
	for i = 2, #f - 1 do
		expect(approx(f[i + 1].x - f[i].x, g1), "bunting points evenly spaced")
	end
	print("worldlayout: buntingFlags OK")
end

print("ALL WorldLayout TESTS PASSED")
