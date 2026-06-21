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

-- arenaSlot reproduces today's documented positions exactly.
-- Real values: SPAWN_ORIGIN = (-4, 5, 4), SPAWN_SPACING = 8 -> X = -4,4,12,20,28.
do
	local ox, oy, oz, spacing = -4, 5, 4, 8
	local expectedX = { -4, 4, 12, 20, 28 }
	for i = 1, 5 do
		local x, y, z = SpawnLayout.arenaSlot(i, ox, oy, oz, spacing)
		expect(x == expectedX[i], "arenaSlot X wrong at index " .. i)
		expect(y == oy, "arenaSlot Y must equal originY at index " .. i)
		expect(z == oz, "arenaSlot Z must equal originZ at index " .. i)
	end
	print("spawn: arenaSlot reproduces documented positions OK")
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
