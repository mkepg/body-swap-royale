--[[
	WorldLayout -- PURE placement math for the broadcast world shell.
	Location (Roblox): ReplicatedStorage/Shared/WorldLayout (ModuleScript)

	No Roblox APIs (no Vector3/Color3), no os.clock, no math.random global state.
	Number-in / number-out; client glue (WorldShell/ArenaDressing) turns the
	returned offsets into Vector3s. Mirrors the project's other pure modules
	(HexGrid, SpawnLayout) so it is lune-testable without Roblox.
--]]

local WorldLayout = {}

-- `count` evenly spaced points on a circle of `radius` around (cx, cz).
-- Returns { { x, z }, ... }. Point 1 is at angle 0 (the +X axis); successive
-- points advance by +angle (clockwise viewed top-down from +Y, since +Z is "into" the map).
function WorldLayout.ring(cx, cz, radius, count)
	local out = {}
	for i = 0, count - 1 do
		local a = (2 * math.pi * i) / count
		out[#out + 1] = { x = cx + radius * math.cos(a), z = cz + radius * math.sin(a) }
	end
	return out
end

-- 1-based palette index for the i-th element, wrapping over `len`.
function WorldLayout.paletteIndex(i, len)
	return (i - 1) % len + 1
end

-- The 4 corners of a rectangular footprint (cx,cz / footX,footZ extents),
-- pushed outward by `margin`. Order: (-,-), (+,-), (+,+), (-,+).
function WorldLayout.footprintCorners(cx, cz, footX, footZ, margin)
	local hx = footX / 2 + margin
	local hz = footZ / 2 + margin
	return {
		{ x = cx - hx, z = cz - hz },
		{ x = cx + hx, z = cz - hz },
		{ x = cx + hx, z = cz + hz },
		{ x = cx - hx, z = cz + hz },
	}
end

-- Deterministic pseudo-random wisp positions inside a box volume with base at
-- (cx,cy,cz): x,z in [cx±spread] / [cz±spread], y in [cy, cy+height]. Uses a
-- seeded LCG (no global RNG) so tests are stable. colorIndex wraps over `paletteLen`.
function WorldLayout.wispField(cx, cy, cz, spread, height, count, paletteLen, seed)
	local out = {}
	local s = seed % 2147483647
	if s <= 0 then s += 2147483646 end
	local function rnd()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
	for i = 1, count do
		out[#out + 1] = {
			x = cx + (rnd() * 2 - 1) * spread,
			y = cy + rnd() * height,
			z = cz + (rnd() * 2 - 1) * spread,
			colorIndex = (i - 1) % paletteLen + 1,
		}
	end
	return out
end

-- A small soul cluster: `n` points in a single centered row along X at constant
-- y=baseY and z=cz, gap `spacing`, straddling (cx, cz). Used for the lobby's two
-- wing crowd clusters at the pit-view edges. Returns { { x, y, z }, ... }.
function WorldLayout.cluster(cx, cz, baseY, n, spacing)
	local out = {}
	for k = 0, n - 1 do
		out[#out + 1] = {
			x = cx + (k - (n - 1) / 2) * spacing,
			y = baseY,
			z = cz,
		}
	end
	return out
end

-- Evenly spaced points across an ARC of `spread` radians centered on `centerAngle`
-- (count == 1 -> the single center point). Same {x, z} rows as ring().
function WorldLayout.arc(cx, cz, radius, count, centerAngle, spread)
	local pts = {}
	for i = 1, count do
		local t = count == 1 and 0.5 or (i - 1) / (count - 1)
		local a = centerAngle - spread / 2 + spread * t
		pts[i] = { x = cx + radius * math.cos(a), z = cz + radius * math.sin(a) }
	end
	return pts
end

return WorldLayout
