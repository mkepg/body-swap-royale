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

-- U-wrap crowd risers around a rectangle centered at (originX,originZ) with half-
-- extents halfX/halfZ. Three dressed edges (back -Z + left -X + right +X); the
-- front (+Z) edge is intentionally left open (pit view + victory cam). Row r
-- (1..rows) sits at y = baseY + r*rise and recedes outward by r*depth. Back run:
-- `perSide` points along X centered on originX, gap `spacing`. Wings: `perSide`
-- points filling the BACK HALF of the Z range (never crossing originZ), so no
-- point ever reaches the front. Returns { { x, y, z }, ... }.
function WorldLayout.tierRows(originX, originZ, baseY, halfX, halfZ, rows, rise, depth, perSide, spacing)
	local out = {}
	for r = 1, rows do
		local y = baseY + r * rise
		local o = r * depth
		-- back edge
		local zBack = originZ - halfZ - o
		for k = 0, perSide - 1 do
			local x = originX + (k - (perSide - 1) / 2) * spacing
			out[#out + 1] = { x = x, y = y, z = zBack }
		end
		-- wings: fill the back half along Z (z in (originZ-halfZ, originZ])
		local step = halfZ / perSide
		for k = 1, perSide do
			local z = originZ - halfZ + k * step
			out[#out + 1] = { x = originX - halfX - o, y = y, z = z } -- left wing
			out[#out + 1] = { x = originX + halfX + o, y = y, z = z } -- right wing
		end
	end
	return out
end

-- `count` bulb positions along the segment (x1,y1,z1)->(x2,y2,z2) with a parabolic
-- droop: 0 at the endpoints, `sag` studs below the lerped height at mid-span
-- (droop(t) = sag * 4t(1-t)). Approximates a hanging festoon strand.
function WorldLayout.festoonStrand(x1, y1, z1, x2, y2, z2, count, sag)
	local out = {}
	for i = 0, count - 1 do
		local t = (count == 1) and 0 or i / (count - 1)
		local droop = sag * 4 * t * (1 - t)
		out[#out + 1] = {
			x = x1 + (x2 - x1) * t,
			y = y1 + (y2 - y1) * t - droop,
			z = z1 + (z2 - z1) * t,
		}
	end
	return out
end

return WorldLayout
