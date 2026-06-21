--[[
	SpawnLayout -- PURE slot geometry.
	Location (Roblox): ReplicatedStorage/Shared/SpawnLayout  (ModuleScript)

	No Roblox APIs (no Vector3/CFrame/Color3), no clocks, no RNG. Number-in /
	number-out; the server glue (BodyManager) turns the returned components into
	CFrames. Mirrors the project's other pure modules (TileFieldModel, RoundState).

	Two layouts:
	  arenaSlot -- the in-arena spawn row (reproduces the math BodyManager used
	               inline: body `index` at originX + (index-1)*spacing, tile centers).
	  lobbySlot -- a centered grid on the elevated lobby balcony.
--]]

local SpawnLayout = {}

-- Arena spawn slot for 1-based `index`. Returns world components x, y, z.
-- x = originX + (index-1)*spacing; y, z pass through. This MUST match the
-- positions BodyManager produced before extraction (tile-center invariant).
function SpawnLayout.arenaSlot(index, originX, originY, originZ, spacing)
	return originX + (index - 1) * spacing, originY, originZ
end

-- Balcony grid offset for 1-based `index`, from the pad center.
-- `perRow` columns, `rows` total rows, `spacing` studs between slots.
-- Columns fill left-to-right, wrapping to the next row every `perRow`.
-- Both axes are centered on 0, so the grid straddles the pad origin.
-- Returns dx, dz offsets (the server adds the balcony origin + height + facing).
function SpawnLayout.lobbySlot(index, perRow, rows, spacing)
	local i = index - 1
	local col = i % perRow
	local row = math.floor(i / perRow)
	local dx = (col - (perRow - 1) / 2) * spacing
	local dz = (row - (rows - 1) / 2) * spacing
	return dx, dz
end

return SpawnLayout
