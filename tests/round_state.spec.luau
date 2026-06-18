local RoundState = require("../src/shared/RoundState")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- new + addPlayer + getters: fresh model starts in Lobby, empty, no winner.
do
	local m = RoundState.new(2, 2)
	expect(RoundState.getPhase(m) == "Lobby", "fresh model is in Lobby")
	expect(RoundState.getWinner(m) == nil, "fresh model has no winner")
	expect(RoundState.aliveCount(m) == 0, "fresh model has nobody alive")
	expect(not RoundState.isAlive(m, "A"), "unknown player is not alive")
	print("new: empty Lobby model OK")
end

-- canStart: false below minToStart, true at/above it, false outside Lobby.
do
	local m = RoundState.new(2, 2)
	expect(not RoundState.canStart(m), "0 present < minToStart(2) -> cannot start")
	RoundState.addPlayer(m, "A")
	expect(not RoundState.canStart(m), "1 present < 2 -> cannot start")
	RoundState.addPlayer(m, "B")
	expect(RoundState.canStart(m), "2 present >= 2 -> can start")
	print("canStart: threshold gating OK")
end

print("ALL ROUNDSTATE TESTS PASSED")
