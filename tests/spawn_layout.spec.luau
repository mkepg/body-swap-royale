local SpawnLayout = require("../src/shared/SpawnLayout")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local function approx(a, b)
	return math.abs(a - b) < 1e-9
end

-- arenaSlot lays a centered grid on tile CENTERS within the field (no longer a
-- single unbounded row -- that row put body 6+ at X>=36, off the [-32,32] field).
-- With spacing = TILE_SIZE (8) and an even perRow/rows, every offset is a multiple
-- of 4 but NOT a multiple of 8, i.e. a tile center, never a seam.
do
	local perRow, rows, spacing = 4, 4, 8
	local slots = {}
	for i = 1, 16 do
		local dx, dz = SpawnLayout.arenaSlot(i, perRow, rows, spacing)
		slots[i] = { dx = dx, dz = dz }
	end

	-- pairwise distinct
	for i = 1, 16 do
		for j = i + 1, 16 do
			expect(not (slots[i].dx == slots[j].dx and slots[i].dz == slots[j].dz),
				"arenaSlot slots " .. i .. " and " .. j .. " overlap")
		end
	end

	-- tile-center invariant: each offset is a multiple of 4 but not of 8 (seams sit
	-- on multiples of 8; a body straddling a seam is held up by all adjacent tiles).
	for i = 1, 16 do
		for _, d in ipairs({ slots[i].dx, slots[i].dz }) do
			expect(d % 4 == 0, "arenaSlot offset must be a multiple of 4 (tile grid) at " .. i)
			expect(d % 8 ~= 0, "arenaSlot offset must avoid seams (multiples of 8) at " .. i)
		end
	end

	-- centered on 0 and within the field footprint (half-span = (n-1)/2*spacing = 12).
	local half = (perRow - 1) / 2 * spacing
	local sumX, sumZ = 0, 0
	for i = 1, 16 do
		sumX += slots[i].dx
		sumZ += slots[i].dz
		expect(math.abs(slots[i].dx) <= half + 1e-9, "arenaSlot dx out of footprint at " .. i)
		expect(math.abs(slots[i].dz) <= half + 1e-9, "arenaSlot dz out of footprint at " .. i)
	end
	expect(approx(sumX, 0) and approx(sumZ, 0), "arenaSlot grid must be centered on 0")

	-- wrap at perRow: index 1 and 5 share a column (same dx), advance a row (differ dz).
	expect(slots[1].dx == slots[5].dx, "arenaSlot must wrap columns at perRow")
	expect(slots[1].dz ~= slots[5].dz, "arenaSlot must advance the row after perRow")
	print("spawn: arenaSlot centered tile-center grid OK")
end

-- lobbySlot lays a centered grid: distinct, spaced, wrapping at perRow.
do
	local perRow, rows, spacing = 4, 4, 10
	local slots = {}
	for i = 1, 16 do
		local dx, dz = SpawnLayout.lobbySlot(i, perRow, rows, spacing)
		slots[i] = { dx = dx, dz = dz }
	end

	-- pairwise distinct
	for i = 1, 16 do
		for j = i + 1, 16 do
			expect(not (slots[i].dx == slots[j].dx and slots[i].dz == slots[j].dz),
				"lobbySlot slots " .. i .. " and " .. j .. " overlap")
		end
	end

	-- columns centered on 0: first row dx = -15,-5,5,15 -> sum 0, spacing 10
	local sum = slots[1].dx + slots[2].dx + slots[3].dx + slots[4].dx
	expect(approx(sum, 0), "lobbySlot columns must be centered on 0")
	expect(approx(slots[2].dx - slots[1].dx, spacing), "lobbySlot column spacing wrong")

	-- rows centered on 0: column-0 dz across rows = -15,-5,5,15 -> sum 0
	local rowSum = slots[1].dz + slots[5].dz + slots[9].dz + slots[13].dz
	expect(approx(rowSum, 0), "lobbySlot rows must be centered on 0")

	-- wrap: index 1 and 5 share a column (same dx), advance a row (differ dz)
	expect(slots[1].dx == slots[5].dx, "lobbySlot must wrap columns at perRow")
	expect(slots[1].dz ~= slots[5].dz, "lobbySlot must advance the row after perRow")

	-- footprint: every offset stays within +/- (span/2); span = (n-1)*spacing
	local halfX = (perRow - 1) / 2 * spacing
	local halfZ = (rows - 1) / 2 * spacing
	for i = 1, 16 do
		expect(math.abs(slots[i].dx) <= halfX + 1e-9, "lobbySlot dx out of footprint at " .. i)
		expect(math.abs(slots[i].dz) <= halfZ + 1e-9, "lobbySlot dz out of footprint at " .. i)
	end
	print("spawn: lobbySlot centered grid OK")
end

print("ALL SpawnLayout TESTS PASSED")
