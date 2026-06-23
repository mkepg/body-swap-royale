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
	print("hexgrid: fromWorld nearest-center OK")
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
	print("hexgrid: floorAt banding OK")
end

print("ALL HexGrid TESTS PASSED")
