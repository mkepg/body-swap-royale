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

-- beginRound with an `eligible` set: only eligible present players become alive
-- (the server passes the set of players who have a valid, spawned body, so a
-- bodyless present player is excluded from the round and its swaps). nil = all.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")

	local roster = RoundState.beginRound(m, { A = true, C = true }) -- B has no body

	expect(RoundState.aliveCount(m) == 2, "only eligible present players are alive")
	expect(RoundState.isAlive(m, "A") and RoundState.isAlive(m, "C"), "A and C are alive")
	expect(not RoundState.isAlive(m, "B"), "ineligible B is not alive despite being present")
	expect(#roster == 2, "roster lists only the eligible players")
	expect(m.present["B"] == true, "B stays present (still in the lobby), just not alive")
	print("beginRound: eligible filter OK")
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

-- eliminate: a dead player while the round is STILL Active is a no-op
-- (exercises the not-alive guard distinctly from the Ended-phase guard).
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")
	RoundState.beginRound(m)

	RoundState.eliminate(m, "A") -- A dead; B and C still alive, round Active
	expect(RoundState.getPhase(m) == "Active", "round still Active with 2 alive")

	local rAgain = RoundState.eliminate(m, "A") -- A already dead, still Active
	expect(rAgain.ended == false and rAgain.winner == nil, "re-eliminating a dead player is a no-op")
	expect(RoundState.aliveCount(m) == 2, "alive count unchanged by no-op")
	expect(RoundState.getPhase(m) == "Active", "phase unchanged by no-op")
	print("eliminate: dead-while-Active no-op OK")
end

-- removePlayer: a disconnect that drops alive to 1 declares the remaining winner.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.beginRound(m)

	local r = RoundState.removePlayer(m, "A")
	expect(r.ended == true, "disconnect to 1 alive ends the round")
	expect(r.winner == "B", "B wins when A disconnects")
	expect(RoundState.getPhase(m) == "Ended", "phase Ended after disconnect win")
	expect(m.present["A"] == nil, "A removed from present")
	print("removePlayer: disconnect win OK")
end

-- removePlayer: dropping the alive set to 0 ends with no winner (round aborted).
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.beginRound(m)

	-- minToContinue is 2, so removing ONE alive player already ends the round
	-- (1 < 2) with the other as winner. To reach 0 we construct the boundary
	-- case directly: a model whose continue threshold is 1, so it only ends at 0.
	local m0 = RoundState.new(2, 1)
	RoundState.addPlayer(m0, "A")
	RoundState.addPlayer(m0, "B")
	RoundState.beginRound(m0)

	local r1 = RoundState.removePlayer(m0, "A")
	expect(r1.ended == false, "with continue=1, 1 alive keeps going")
	local r2 = RoundState.removePlayer(m0, "B")
	expect(r2.ended == true, "0 alive ends the round")
	expect(r2.winner == nil, "0 alive -> no winner")
	expect(RoundState.getPhase(m0) == "Ended", "phase Ended on abort")
	expect(RoundState.getWinner(m0) == nil, "winner stays nil on abort")
	print("removePlayer: drop-to-zero abort OK")
end

-- removePlayer: removing a non-present player is a no-op; removing a present but
-- non-alive (spectating) player does not affect the round outcome.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.beginRound(m)

	local rGhost = RoundState.removePlayer(m, "ghost")
	expect(rGhost.ended == false and rGhost.winner == nil, "removing unknown player is a no-op")

	RoundState.addPlayer(m, "C") -- joins mid-round: present, not alive
	expect(not RoundState.isAlive(m, "C"), "mid-round join is not alive")
	expect(RoundState.aliveCount(m) == 2, "mid-round join does not change alive count")
	local rSpec = RoundState.removePlayer(m, "C")
	expect(rSpec.ended == false and rSpec.winner == nil, "removing a spectator does not end the round")
	expect(RoundState.getPhase(m) == "Active", "round still Active")
	print("removePlayer: no-op cases OK")
end

-- Post-Ended: eliminate / removePlayer are no-ops for phase and winner.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")
	RoundState.beginRound(m)
	RoundState.eliminate(m, "A") -- B, C alive
	RoundState.eliminate(m, "B") -- C wins -> Ended

	local rElim = RoundState.eliminate(m, "C")
	expect(rElim.ended == false and rElim.winner == nil, "eliminate after Ended is a no-op")
	expect(RoundState.getPhase(m) == "Ended", "phase stays Ended")
	expect(RoundState.getWinner(m) == "C", "winner stays C")

	-- removePlayer after Ended may still drop from present, but never re-ends.
	local rRem = RoundState.removePlayer(m, "C")
	expect(rRem.ended == false and rRem.winner == nil, "removePlayer after Ended does not re-end")
	expect(RoundState.getWinner(m) == "C", "winner still C")
	expect(m.present["C"] == nil, "C still dropped from present")
	print("terminal Ended: no-op OK")
end

-- reset + full cycle: Ended -> Lobby keeps still-connected players; alive subset
-- of present holds throughout.
do
	local function aliveSubsetOfPresent(m)
		for p in pairs(m.alive) do
			if not m.present[p] then
				return false
			end
		end
		return true
	end

	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	expect(aliveSubsetOfPresent(m), "invariant holds in Lobby")

	RoundState.beginRound(m)
	expect(aliveSubsetOfPresent(m), "invariant holds in Active")

	RoundState.eliminate(m, "A") -- B wins -> Ended
	expect(aliveSubsetOfPresent(m), "invariant holds in Ended")

	RoundState.reset(m)
	expect(RoundState.getPhase(m) == "Lobby", "reset returns to Lobby")
	expect(RoundState.getWinner(m) == nil, "reset clears winner")
	expect(RoundState.aliveCount(m) == 0, "reset clears alive")
	expect(m.present["A"] and m.present["B"], "still-connected players carry to next round")
	expect(RoundState.canStart(m), "can start the next round with carried players")
	expect(aliveSubsetOfPresent(m), "invariant holds after reset")
	print("reset: full-cycle + invariant OK")
end

-- reset: refuses to run outside the Ended phase (symmetry with beginRound's guard).
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	local okLobby = pcall(RoundState.reset, m)
	expect(not okLobby, "reset errors in Lobby")

	RoundState.beginRound(m)
	local okActive = pcall(RoundState.reset, m)
	expect(not okActive, "reset errors while Active")
	print("reset: refuses outside Ended OK")
end

-- Solo test mode (Config.SOLO_TEST_MODE wires thresholds to 1/1): a single player
-- can start a round, the round does NOT auto-end at 1 alive, and the solo player
-- dying ends it with NO winner (0 alive is not a win).
do
	local m = RoundState.new(1, 1)
	RoundState.addPlayer(m, "A")
	expect(RoundState.canStart(m), "solo mode: 1 present can start")
	local roster = RoundState.beginRound(m)
	expect(#roster == 1 and RoundState.getPhase(m) == "Active", "solo round is Active with 1 alive")
	expect(RoundState.aliveCount(m) == 1, "solo player is alive")
	local r = RoundState.eliminate(m, "A")
	expect(r.ended == true and r.winner == nil, "solo death ends the round with no winner")
	expect(RoundState.getPhase(m) == "Ended", "phase is Ended after the solo death")
	RoundState.reset(m)
	expect(RoundState.canStart(m), "solo mode: next round can start again")
	print("solo mode: 1/1 thresholds OK")
end

print("ALL ROUNDSTATE TESTS PASSED")
