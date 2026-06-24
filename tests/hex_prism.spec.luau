local HexPrism = require("../src/shared/HexPrism")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- Cross product of (b-a) x (c-a) for vertices given as {x, y, z} arrays.
local function triNormal(a, b, c)
	local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
	return uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
end

local SIZE, THICK = 6, 1

-- Shape: 12 vertices (6 top + 6 bottom), 20 triangles (4 top fan + 4 bottom fan +
-- 12 side). Top verts at +thickness/2, bottom at -thickness/2; all on the
-- circumradius.
do
	local m = HexPrism.build(SIZE, THICK)
	expect(#m.vertices == 12, "hex prism must have 12 vertices")
	expect(#m.triangles == 20, "hex prism must have 20 triangles (4+4+12)")
	for i = 1, 6 do
		expect(math.abs(m.vertices[i][2] - THICK / 2) < 1e-9, "top vertex " .. i .. " must sit at +thickness/2")
	end
	for i = 7, 12 do
		expect(math.abs(m.vertices[i][2] + THICK / 2) < 1e-9, "bottom vertex " .. i .. " must sit at -thickness/2")
	end
	for i = 1, 12 do
		local v = m.vertices[i]
		local r = math.sqrt(v[1] * v[1] + v[3] * v[3])
		expect(math.abs(r - SIZE) < 1e-6, "vertex " .. i .. " must lie on the circumradius")
	end
	-- triangle indices are all in range and non-degenerate
	for _, t in ipairs(m.triangles) do
		for _, idx in ipairs(t) do
			expect(idx >= 1 and idx <= 12, "triangle index out of range")
		end
		expect(t[1] ~= t[2] and t[2] ~= t[3] and t[1] ~= t[3], "degenerate triangle")
	end
	print("hexprism: vertex/triangle counts + placement OK")
end

-- Winding: the FIRST 4 triangles are the top face (normal points +Y), the NEXT 4
-- are the bottom face (normal points -Y), and the LAST 12 are side faces (normal is
-- horizontal and points radially OUTWARD). This is the load-bearing correctness the
-- mesh needs and that can't be eyeballed in Studio.
do
	local m = HexPrism.build(SIZE, THICK)
	local function nz(i)
		local t = m.triangles[i]
		return triNormal(m.vertices[t[1]], m.vertices[t[2]], m.vertices[t[3]])
	end
	for i = 1, 4 do
		local _, ny = nz(i)
		expect(ny > 0, "top triangle " .. i .. " normal must point +Y")
	end
	for i = 5, 8 do
		local _, ny = nz(i)
		expect(ny < 0, "bottom triangle " .. i .. " normal must point -Y")
	end
	for i = 9, 20 do
		local nx, ny, nzc = nz(i)
		expect(math.abs(ny) < 1e-6, "side triangle " .. i .. " normal must be horizontal")
		-- outward: dot with the triangle centroid's horizontal direction > 0
		local t = m.triangles[i]
		local cx = (m.vertices[t[1]][1] + m.vertices[t[2]][1] + m.vertices[t[3]][1]) / 3
		local cz = (m.vertices[t[1]][3] + m.vertices[t[2]][3] + m.vertices[t[3]][3]) / 3
		expect(nx * cx + nzc * cz > 0, "side triangle " .. i .. " normal must point outward")
	end
	print("hexprism: face winding / outward normals OK")
end

print("ALL HexPrism TESTS PASSED")
