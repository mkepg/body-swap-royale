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

-- swap: 3 players, deterministic rng -> single-cycle derangement of current bodies.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.addPlayer(m, "C", "c")

	local pairs_ = ControlModel.swap(m, { "A", "B", "C" }, function(_n) return 1 end)

	-- No player keeps their previous body.
	expect(ControlModel.controlledBody(m, "A") ~= "a", "A must not keep a")
	expect(ControlModel.controlledBody(m, "B") ~= "b", "B must not keep b")
	expect(ControlModel.controlledBody(m, "C") ~= "c", "C must not keep c")

	-- Still a bijection (every body controlled once, every player controls once).
	expect(ControlModel.bijectionHolds(m), "bijection must survive swap")

	-- Returned pairs describe exactly who now controls what.
	expect(#pairs_ == 3, "swap should return 3 pairs")
	for _, pr in ipairs(pairs_) do
		expect(ControlModel.controlledBody(m, pr.player) == pr.body, "pair must match model")
	end
	print("swap: derangement + bijection + pairs OK")
end

-- swap: 2 players always exchange.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.swap(m, { "A", "B" }, function(_n) return 1 end)
	expect(ControlModel.controlledBody(m, "A") == "b", "A should now control b")
	expect(ControlModel.controlledBody(m, "B") == "a", "B should now control a")
	print("swap: n=2 exchange OK")
end

print("ALL CONTROLMODEL TESTS PASSED")
