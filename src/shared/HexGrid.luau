--[[
	HexGrid -- PURE flat-top hex geometry for the Hex-A-Gone arena floor.
	Location (Roblox): ReplicatedStorage/Shared/HexGrid (ModuleScript)

	No Roblox APIs (no Vector3/CFrame/Color3), no clocks, no RNG. Number-in /
	number-out; the server glue (HazardSystem/BodyManager) turns the returned
	offsets into world positions. Mirrors the project's other pure modules
	(SpawnLayout, RoundState).

	Axial coords {q, r}, FLAT-TOP orientation. `size` is the hex circumradius
	(center-to-vertex = side length) in studs.
--]]

local HexGrid = {}

local SQRT3 = math.sqrt(3)

-- Axial neighbor directions (flat-top), used by the spawn-slot ring spiral.
local DIRECTIONS = {
	{ 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 },
}

-- All axial {q, r} within `radius` rings of center (hexagonal field).
-- Count = 1 + 3*radius*(radius+1).
function HexGrid.tiles(radius)
	local out = {}
	for q = -radius, radius do
		local rLo = math.max(-radius, -q - radius)
		local rHi = math.min(radius, -q + radius)
		for r = rLo, rHi do
			out[#out + 1] = { q = q, r = r }
		end
	end
	return out
end

-- Flat-top axial -> world center offset (dx, dz studs) from the field center.
function HexGrid.toWorld(q, r, size)
	local dx = size * 1.5 * q
	local dz = size * SQRT3 * (r + q / 2)
	return dx, dz
end

-- Round fractional axial coords to the nearest hex (cube rounding).
local function cubeRound(qf, rf)
	local x, z = qf, rf
	local y = -x - z
	local rx, ry, rz = math.round(x), math.round(y), math.round(z)
	local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
	if dx > dy and dx > dz then
		rx = -ry - rz
	elseif dy > dz then
		ry = -rx - rz
	else
		rz = -rx - ry
	end
	return rx, rz
end

-- Flat-top world offset -> nearest axial q, r.
function HexGrid.fromWorld(dx, dz, size)
	local qf = (2 / 3 * dx) / size
	local rf = (-1 / 3 * dx + SQRT3 / 3 * dz) / size
	return cubeRound(qf, rf)
end

-- Ordered hex centers (outward spiral from center) for round-start body spawns.
-- Returns all in-field tiles in spiral order; the server indexes the first N.
function HexGrid.spawnSlots(radius)
	local slots = { { q = 0, r = 0 } }
	for k = 1, radius do
		-- Start at the ring corner center + k * direction {-1, 1}, walk all 6 sides.
		local q, r = -k, k
		for i = 1, 6 do
			for _ = 1, k do
				slots[#slots + 1] = { q = q, r = r }
				q += DIRECTIONS[i][1]
				r += DIRECTIONS[i][2]
			end
		end
	end
	return slots
end

-- Which stacked floor (0-based, top = 0) a body whose root sits at height `y` is
-- standing on, or nil if airborne/between floors. Floor k's top surface is at
-- surfaceY - k*gap; a root counts as "on" it when within (surf, surf + band].
-- gap > band keeps the bands non-overlapping (no mid-air or wrong-floor arming).
function HexGrid.floorAt(y, surfaceY, gap, band, count)
	for k = 0, count - 1 do
		local surf = surfaceY - k * gap
		if y > surf and y <= surf + band then
			return k
		end
	end
	return nil
end

return HexGrid
