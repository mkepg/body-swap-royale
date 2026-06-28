local RoundScreenModel = require("../src/shared/RoundScreenModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local CTX = { localPlayerName = "Mikhael", connectedCount = 2, minPlayers = 2 }

-- Lobby, below the minimum: a friendly wait message and NO raw count line.
do
	local ctx = { localPlayerName = "Mikhael", connectedCount = 1, minPlayers = 2 }
	local d = RoundScreenModel.display({ phase = "Lobby", secondsRemaining = nil }, ctx)
	expect(d.visible == true, "lobby banner is visible")
	expect(d.titleText == "Waiting for other players", "got title: " .. tostring(d.titleText))
	expect(d.titleAnimateDots == true, "wait message animates its trailing dots")
	expect(d.subtitleText == nil, "no count line below the minimum, got: " .. tostring(d.subtitleText))
	expect(d.bottomText == nil, "no bottom line in lobby")
	expect(d.winnerName == nil, "no winner in lobby")
	expect(d.accent == "neutral", "lobby accent is neutral")
	print("round-screen: lobby-below-minimum OK")
end

-- Lobby, minimum reached but no countdown yet: clean player count.
do
	local d = RoundScreenModel.display({ phase = "Lobby", secondsRemaining = nil }, CTX)
	expect(d.titleText == "Players ready", "got title: " .. tostring(d.titleText))
	expect(not d.titleAnimateDots, "ready state does not animate dots")
	expect(d.subtitleText == "2 players", "got subtitle: " .. tostring(d.subtitleText))
	print("round-screen: lobby-ready OK")
end

-- Lobby, counting down (minimum met): title carries the seconds, count stays clean.
do
	local d = RoundScreenModel.display({ phase = "Lobby", secondsRemaining = 4 }, CTX)
	expect(d.titleText == "Round starting in 4", "got title: " .. tostring(d.titleText))
	expect(d.subtitleText == "2 players", "got subtitle: " .. tostring(d.subtitleText))
	print("round-screen: lobby-countdown OK")
end

-- Lobby, single player above a minimum of 1: count line is singular.
do
	local ctx = { localPlayerName = "Mikhael", connectedCount = 1, minPlayers = 1 }
	local d = RoundScreenModel.display({ phase = "Lobby", secondsRemaining = nil }, ctx)
	expect(d.subtitleText == "1 player", "got subtitle: " .. tostring(d.subtitleText))
	print("round-screen: lobby-singular-count OK")
end

-- Active: banner hidden, texts irrelevant.
do
	local d = RoundScreenModel.display({ phase = "Active", secondsRemaining = nil }, CTX)
	expect(d.visible == false, "banner hidden during Active")
	print("round-screen: active-hidden OK")
end

-- Ended, local player won: Victory + win accent + winner name + countdown.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = "Mikhael", secondsRemaining = 5 }, CTX)
	expect(d.visible == true, "results banner is visible")
	expect(d.titleText == "Victory", "got title: " .. tostring(d.titleText))
	expect(d.winnerName == "Mikhael", "winner name shown")
	expect(d.bottomText == "Next round in 5", "got bottom: " .. tostring(d.bottomText))
	expect(d.accent == "win", "win accent")
	print("round-screen: ended-victory OK")
end

-- Ended, someone else won: Defeated + lose accent, still shows the winner's name.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = "Vesper", secondsRemaining = 3 }, CTX)
	expect(d.titleText == "Defeated", "got title: " .. tostring(d.titleText))
	expect(d.winnerName == "Vesper", "winner name shown")
	expect(d.accent == "lose", "lose accent")
	print("round-screen: ended-defeated OK")
end

-- Ended, no winner (e.g. disconnect-decided with none alive): "Round over", neutral.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = nil, secondsRemaining = 2 }, CTX)
	expect(d.titleText == "Round over", "got title: " .. tostring(d.titleText))
	expect(d.winnerName == nil, "no winner name")
	expect(d.accent == "neutral", "neutral accent")
	expect(d.bottomText == "Next round in 2", "got bottom: " .. tostring(d.bottomText))
	print("round-screen: ended-no-winner OK")
end

-- Defensive: Ended without a countdown value shows no stale bottom line.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = "Mikhael", secondsRemaining = nil }, CTX)
	expect(d.bottomText == nil, "no bottom line when secondsRemaining is nil")
	print("round-screen: ended-no-countdown OK")
end

print("ALL RoundScreenModel TESTS PASSED")
