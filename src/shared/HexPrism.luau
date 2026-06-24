--[[
	HexPrism -- PURE pointy-top hexagonal-prism mesh geometry for the Hex-A-Gone tiles.
	Location (Roblox): ReplicatedStorage/Shared/HexPrism (ModuleScript)

	No Roblox APIs (returns plain {x,y,z} vertex arrays + 1-based triangle index
	triples), no clocks, no RNG. The server glue (HazardSystem) feeds these into an
	EditableMesh so each tile is ONE true hexagon (no overlapping parts -> no
	z-fighting; exact geometry -> no gaps). Mirrors the project's other pure modules
	(HexGrid, SpawnLayout).

	Output: { vertices = { {x,y,z}, ... 12 }, triangles = { {i0,i1,i2}, ... 20 } }.
	Vertices 1..6 are the top ring (+thickness/2), 7..12 the bottom ring
	(-thickness/2), both on the circumradius `size`. Vertices are placed at angles
	30 + 60*i (pointy-top: a vertex sits at world +Z, the next at the +X edge top
	corner, etc.). Triangle order is the 4 top-fan, then 4 bottom-fan, then 12 side
	triangles -- each wound so its normal points outward (top +Y, bottom -Y, sides
	radially out). The winding is computed, not hand-ordered, so it is robust and
	lune-verifiable.

	NOTE: currently unused by HazardSystem (which composes tiles from stock Block +
	WedgePart primitives because the EditableMesh API requires Experience Settings >
	Security > Allow Mesh/Image Access). Kept (and lune-tested) so the EditableMesh
	path drops back in cleanly once that setting is enabled.
--]]

local HexPrism = {}

-- Cross product (b-a) x (c-a) for {x,y,z} arrays. Its direction is the face normal
-- for the winding (a, b, c).
local function triNormal(a, b, c)
	local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
	return uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
end

-- Build a pointy-top hex prism of circumradius `size` and `thickness` (studs),
-- centered at the local origin. Vertices at angles 30+60*i (so a vertex sits at
-- world +Z, matching the pointy-top orientation in HexGrid).
function HexPrism.build(size, thickness)
	local hy = thickness / 2
	local verts = {}
	for i = 0, 5 do
		local ang = math.rad(30 + 60 * i)
		verts[i + 1] = { size * math.cos(ang), hy, size * math.sin(ang) }   -- top ring  -> 1..6
	end
	for i = 0, 5 do
		local ang = math.rad(30 + 60 * i)
		verts[7 + i] = { size * math.cos(ang), -hy, size * math.sin(ang) }  -- bottom ring -> 7..12
	end

	local tris = {}
	-- Push triangle (i0, i1, i2), flipping the last two indices if its normal points
	-- away from the desired outward direction (dx, dy, dz).
	local function push(i0, i1, i2, dx, dy, dz)
		local nx, ny, nz = triNormal(verts[i0], verts[i1], verts[i2])
		if nx * dx + ny * dy + nz * dz < 0 then
			i1, i2 = i2, i1
		end
		tris[#tris + 1] = { i0, i1, i2 }
	end

	-- Top face: fan from vertex 1, normal +Y.
	for i = 2, 5 do
		push(1, i, i + 1, 0, 1, 0)
	end
	-- Bottom face: fan from vertex 7, normal -Y.
	for i = 2, 5 do
		push(7, 6 + i, 7 + i, 0, -1, 0)
	end
	-- Side faces: per edge i, two triangles spanning top+bottom, normal radially out.
	for i = 0, 5 do
		local ni = (i + 1) % 6
		local ti, tni = i + 1, ni + 1
		local bi, bni = 7 + i, 7 + ni
		local midAng = math.rad(60 * (i + 0.5))
		local ox, oz = math.cos(midAng), math.sin(midAng)
		push(ti, tni, bni, ox, 0, oz)
		push(ti, bni, bi, ox, 0, oz)
	end

	return { vertices = verts, triangles = tris }
end

return HexPrism
