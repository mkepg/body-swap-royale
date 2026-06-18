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

-- beginRound: Lobby -> Active; snapshots present into alive; returns the roster.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")

	local roster = RoundState.beginRound(m)

	expect(RoundState.getPhase(m) == "Active", "beginRound enters Active")
	expect(RoundState.aliveCount(m) == 3, "all 3 present are alive at start")
	expect(RoundState.isAlive(m, "A") and RoundState.isAlive(m, "B") and RoundState.isAlive(m, "C"),
		"each present player is alive")
	expect(#roster == 3, "roster lists all starting players")

	-- roster contents equal the present set (order unspecified).
	local seen = {}
	for _, p in ipairs(roster) do
		seen[p] = true
	end
	expect(seen["A"] and seen["B"] and seen["C"], "roster contains exactly the present players")

	expect(not RoundState.canStart(m), "cannot start again while Active")
	print("beginRound: snapshot present->alive + roster OK")
end

-- beginRound: refuses to start below threshold.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	local ok = pcall(RoundState.beginRound, m)
	expect(not ok, "beginRound errors when canStart is false")
	print("beginRound: refuses below threshold OK")
end

-- eliminate: down to one survivor -> Ended with the correct winner.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")
	RoundState.beginRound(m)

	local r1 = RoundState.eliminate(m, "A")
	expect(r1.ended == false, "round continues with 2 alive")
	expect(r1.winner == nil, "no winner while 2 alive")
	expect(RoundState.getPhase(m) == "Active", "still Active after first elimination")

	local r2 = RoundState.eliminate(m, "B")
	expect(r2.ended == true, "round ends when 1 remains")
	expect(r2.winner == "C", "C is the last one standing")
	expect(RoundState.getPhase(m) == "Ended", "phase is Ended")
	expect(RoundState.getWinner(m) == "C", "winner recorded on the model")
	print("eliminate: auto-end + winner OK")
end

-- eliminate: no-op on a non-alive player and outside Active.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")

	-- Before the round starts (Lobby), eliminate does nothing.
	local rLobby = RoundState.eliminate(m, "A")
	expect(rLobby.ended == false and rLobby.winner == nil, "eliminate is a no-op in Lobby")

	RoundState.beginRound(m)
	RoundState.eliminate(m, "A") -- A now dead, B wins -> Ended

	-- Eliminating an already-dead player changes nothing.
	local rDead = RoundState.eliminate(m, "A")
	expect(rDead.ended == false and rDead.winner == nil, "eliminate on dead player is a no-op")
	expect(RoundState.getWinner(m) == "B", "winner unchanged")
	print("eliminate: no-op cases OK")
end

print("ALL ROUNDSTATE TESTS PASSED")
