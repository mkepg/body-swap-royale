local HexGrid = require("../src/shared/HexGrid")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- tiles(radius): hexagonal field, count = 1 + 3R(R+1), distinct, center present.
do
	for _, R in ipairs({ 0, 1, 2, 3 }) do
		local t = HexGrid.tiles(R)
		expect(#t == 1 + 3 * R * (R + 1), "tiles count wrong for R=" .. R)
	end
	local t = HexGrid.tiles(3)
	local seen, hasCenter = {}, false
	for _, c in ipairs(t) do
		local key = c.q .. ":" .. c.r
		expect(not seen[key], "duplicate coord " .. key)
		seen[key] = true
		if c.q == 0 and c.r == 0 then hasCenter = true end
	end
	expect(hasCenter, "center tile missing")
	print("hexgrid: tiles count/distinct/center OK")
end

-- toWorld/fromWorld round-trip at every tile center (R=3, size=6).
do
	local size = 6
	for _, c in ipairs(HexGrid.tiles(3)) do
		local dx, dz = HexGrid.toWorld(c.q, c.r, size)
		local q, r = HexGrid.fromWorld(dx, dz, size)
		expect(q == c.q and r == c.r,
			"round-trip failed at (" .. c.q .. "," .. c.r .. ") got (" .. q .. "," .. r .. ")")
	end
	print("hexgrid: toWorld/fromWorld round-trip OK")
end

-- fromWorld near a center resolves to that hex, not a neighbor.
do
	local size = 6
	local dx, dz = HexGrid.toWorld(1, 0, size)
	local q, r = HexGrid.fromWorld(dx + 0.5, dz - 0.5, size)
	expect(q == 1 and r == 0, "small offset must stay on the same hex")
	-- near the boundary toward the +q neighbor, still inside hex (1,0)
	local bx, bz = HexGrid.toWorld(1, 0, size)
	local nq, nr = HexGrid.fromWorld(bx + 4.0, bz, size)
	expect(nq == 1 and nr == 0, "point near the +q boundary must stay on hex (1,0)")
	print("hexgrid: fromWorld nearest-center OK")
end

-- fromWorld must never return IEEE-754 negative zero. Cube re-derivation produces
-- `-0` at the centre tile (q=0, r=0); since `0 == -0` numerically but `tostring(-0)
-- == "-0"`, a stringified key like "floor:q:r" silently misses the lookup. Numeric
-- equality alone (the round-trip check above) does NOT catch this -- the assertion
-- has to inspect tostring.
do
	local q, r = HexGrid.fromWorld(0, 0, 6)
	expect(q == 0 and r == 0, "fromWorld(0,0) numeric == (0,0)")
	expect(tostring(q) == "0", "fromWorld(0,0) q tostring must be \"0\", got " .. tostring(q))
	expect(tostring(r) == "0", "fromWorld(0,0) r tostring must be \"0\", got " .. tostring(r))
	-- Same check via the field's actual centre toWorld() output (round-trip through 0):
	local cdx, cdz = HexGrid.toWorld(0, 0, 6)
	local cq, cr = HexGrid.fromWorld(cdx, cdz, 6)
	expect(tostring(cq) == "0" and tostring(cr) == "0", "centre tile must stringify to \"0\":\"0\"")
	print("hexgrid: fromWorld negative-zero canonicalised OK")
end

-- spawnSlots: spiral, distinct, count == tiles count, >= player cap, all in-field.
do
	local slots = HexGrid.spawnSlots(3)
	expect(#slots == 37, "spawnSlots(3) must have 37 slots")
	expect(#slots >= 16, "spawnSlots must cover the 16 player cap")
	expect(slots[1].q == 0 and slots[1].r == 0, "spiral must start at center")
	local seen = {}
	for _, s in ipairs(slots) do
		local key = s.q .. ":" .. s.r
		expect(not seen[key], "spawnSlots duplicate " .. key)
		seen[key] = true
	end
	local valid = {}
	for _, c in ipairs(HexGrid.tiles(3)) do valid[c.q .. ":" .. c.r] = true end
	for _, s in ipairs(slots) do
		expect(valid[s.q .. ":" .. s.r], "spawn slot off-field: " .. s.q .. ":" .. s.r)
	end
	-- spiral order: center, then ring 1 (dist 1), then ring 2 (dist 2), ...
	local function ringDist(s) return math.max(math.abs(s.q), math.abs(s.r), math.abs(s.q + s.r)) end
	expect(ringDist(slots[1]) == 0, "slot 1 is the center")
	for i = 2, 7 do expect(ringDist(slots[i]) == 1, "slots 2-7 are ring 1") end
	for i = 8, 19 do expect(ringDist(slots[i]) == 2, "slots 8-19 are ring 2") end
	print("hexgrid: spawnSlots OK")
end

-- floorAt: roots map to the floor just below them; airborne/below-all -> nil.
do
	local surfaceY, gap, band, count = 0, 10, 6, 3
	expect(HexGrid.floorAt(2.8, surfaceY, gap, band, count) == 0, "root above floor 0")
	expect(HexGrid.floorAt(-7.2, surfaceY, gap, band, count) == 1, "root above floor 1")
	expect(HexGrid.floorAt(-17.2, surfaceY, gap, band, count) == 2, "root above floor 2")
	expect(HexGrid.floorAt(-3, surfaceY, gap, band, count) == nil, "between floors -> nil")
	expect(HexGrid.floorAt(-30, surfaceY, gap, band, count) == nil, "below all floors -> nil")
	expect(HexGrid.floorAt(0, surfaceY, gap, band, count) == nil, "exactly at surface is airborne (open lower bound)")
	print("hexgrid: floorAt banding OK")
end

-- tilesInCircle(ringRadius, size, worldRadius): hex tiles whose WORLD center is within
-- worldRadius -> a circular field clipped from the hex lattice.
do
	local SQRT3 = math.sqrt(3)
	local size, R = 4, 30
	local c = HexGrid.tilesInCircle(9, size, R)
	expect(#c > 0, "tilesInCircle returns tiles")
	for _, t in ipairs(c) do
		local dx = size * 1.5 * t.q
		local dz = size * SQRT3 * (t.r + t.q / 2)
		expect(dx * dx + dz * dz <= R * R + 1e-6, "every tile within worldRadius (got q=" .. t.q .. " r=" .. t.r .. ")")
	end
	local hasCenter, hasFar = false, false
	for _, t in ipairs(c) do
		if t.q == 0 and t.r == 0 then hasCenter = true end
		if t.q == 9 and t.r == 0 then hasFar = true end -- dx=54 > 30, must be clipped
	end
	expect(hasCenter, "center tile (0,0) is included")
	expect(not hasFar, "a far corner outside the circle is excluded")
	expect(#c < #HexGrid.tiles(9), "the circle clips the hex-field corners")
	print("hexgrid: tilesInCircle OK")
end

print("ALL HexGrid TESTS PASSED")
