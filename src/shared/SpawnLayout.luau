--[[
	SpawnLayout -- PURE slot geometry.
	Location (Roblox): ReplicatedStorage/Shared/SpawnLayout  (ModuleScript)

	No Roblox APIs (no Vector3/CFrame/Color3), no clocks, no RNG. Number-in /
	number-out; the server glue (BodyManager) turns the returned components into
	CFrames. Mirrors the project's other pure modules (TileFieldModel, RoundState).

	Two layouts, both centered grids (shared geometry):
	  arenaSlot -- the in-arena spawn grid. With spacing = TILE_SIZE the slots land
	               on tile CENTERS (never seams) and, sized to the player cap, stay
	               within the tile field -- so no body spawns off the floor.
	  lobbySlot -- a centered grid on the elevated lobby balcony.
--]]

local SpawnLayout = {}

-- Centered grid offset for 1-based `index`: `perRow` columns, `rows` rows, `spacing`
-- studs between slots. Columns fill left-to-right, wrapping every `perRow`; both axes
-- are centered on 0 so the grid straddles the origin. Returns dx, dz offsets.
local function centeredGrid(index, perRow, rows, spacing)
	local i = index - 1
	local col = i % perRow
	local row = math.floor(i / perRow)
	local dx = (col - (perRow - 1) / 2) * spacing
	local dz = (row - (rows - 1) / 2) * spacing
	return dx, dz
end

-- Arena spawn offset for 1-based `index`, from the arena center. A centered grid
-- (was a single unbounded row, which put body 6+ off the field). The server adds
-- the arena origin + spawn height. With spacing = TILE_SIZE and even perRow/rows the
-- offsets are tile centers, never seams.
function SpawnLayout.arenaSlot(index, perRow, rows, spacing)
	return centeredGrid(index, perRow, rows, spacing)
end

-- Balcony grid offset for 1-based `index`, from the pad center. The server adds the
-- balcony origin + height + facing.
function SpawnLayout.lobbySlot(index, perRow, rows, spacing)
	return centeredGrid(index, perRow, rows, spacing)
end

return SpawnLayout
