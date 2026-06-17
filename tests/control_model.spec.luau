local ControlModel = require("../src/shared/ControlModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- derange: with a deterministic rng that always returns 1, the result is a fixed,
-- known single-cycle permutation; and no element keeps its original index.
do
	local list = { "a", "b", "c", "d" }
	local rng = function(_n) return 1 end -- always pick j = 1
	ControlModel.derange(list, rng)

	-- Sattolo with j=1 each pass on {a,b,c,d}:
	--   i=4: swap(4,1) -> {d,b,c,a}
	--   i=3: swap(3,1) -> {c,b,d,a}
	--   i=2: swap(2,1) -> {b,c,d,a}
	expect(list[1] == "b", "derange[1] expected b, got " .. tostring(list[1]))
	expect(list[2] == "c", "derange[2] expected c, got " .. tostring(list[2]))
	expect(list[3] == "d", "derange[3] expected d, got " .. tostring(list[3]))
	expect(list[4] == "a", "derange[4] expected a, got " .. tostring(list[4]))
	print("derange: deterministic single-cycle OK")
end

-- derange: n = 2 always swaps (only valid derangement of 2 elements).
do
	local list = { "x", "y" }
	ControlModel.derange(list, function(_n) return 1 end)
	expect(list[1] == "y" and list[2] == "x", "derange n=2 must swap")
	print("derange: n=2 swaps OK")
end

-- new + addPlayer: each player spawns controlling their own avatar body.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")

	expect(ControlModel.controlledBody(m, "A") == "a", "A should control a")
	expect(ControlModel.controlledBody(m, "B") == "b", "B should control b")
	expect(ControlModel.bijectionHolds(m), "bijection should hold after spawns")
	print("addPlayer: self-control + bijection OK")
end

print("ALL CONTROLMODEL TESTS PASSED")
