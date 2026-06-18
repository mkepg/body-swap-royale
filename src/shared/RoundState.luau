--[[
	RoundState -- PURE round-lifecycle state machine.
	Location (Roblox): ReplicatedStorage/Shared/RoundState  (ModuleScript)

	No Roblox APIs and no clocks. Player keys are opaque, compared with ==;
	in production they are Player instances, in tests plain strings. Mirrors
	ControlModel.

	Tracks ONLY the round lifecycle: phase, who is present (the lobby roster),
	who is alive, and the winner. It knows nothing about bodies or ownership;
	the server glue coordinates it with ControlModel.

	Phases:  "Lobby" -> "Active" -> "Ended" -> (reset) "Lobby".
	Invariant: `alive` is always a subset of `present`.

	Thresholds are injected (the server passes Config values; tests pass
	literals), the same way ControlModel injects `randint`.
--]]

local RoundState = {}

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n += 1
	end
	return n
end

function RoundState.new(minToStart, minToContinue)
	return {
		phase = "Lobby",   -- "Lobby" | "Active" | "Ended"
		present = {},       -- [player] = true : connected, in the lobby roster
		alive = {},         -- [player] = true : alive in the current Active round
		winner = nil,       -- player; set only on a win
		minToStart = minToStart,
		minToContinue = minToContinue,
	}
end

function RoundState.getPhase(model)
	return model.phase
end

function RoundState.getWinner(model)
	return model.winner
end

function RoundState.aliveCount(model)
	return count(model.alive)
end

function RoundState.isAlive(model, player)
	return model.alive[player] == true
end

function RoundState.addPlayer(model, player)
	model.present[player] = true
end

function RoundState.canStart(model)
	return model.phase == "Lobby" and count(model.present) >= model.minToStart
end

-- Lobby -> Active. Snapshots the current `present` set into `alive` and returns
-- the starting roster as an array so the caller can spawn / assign control.
function RoundState.beginRound(model)
	assert(RoundState.canStart(model), "beginRound requires canStart")
	model.phase = "Active"
	model.winner = nil
	model.alive = {}
	local roster = {}
	for player in pairs(model.present) do
		model.alive[player] = true
		roster[#roster + 1] = player
	end
	return roster
end

-- After `alive` shrinks during an Active round, end it if fewer than
-- minToContinue remain. Winner = the sole survivor, or nil if none remain.
-- Returns { ended, winner }.
local function maybeEnd(model)
	if model.phase ~= "Active" then
		return { ended = false, winner = nil }
	end
	if count(model.alive) < model.minToContinue then
		model.phase = "Ended"
		local sole = nil
		for player in pairs(model.alive) do
			sole = player
			break
		end
		model.winner = sole
		return { ended = true, winner = sole }
	end
	return { ended = false, winner = nil }
end

-- Remove a player from the alive set due to death. No-op unless the round is
-- Active and the player is currently alive. May auto-end the round.
function RoundState.eliminate(model, player)
	if model.phase ~= "Active" or not model.alive[player] then
		return { ended = false, winner = nil }
	end
	model.alive[player] = nil
	return maybeEnd(model)
end

-- Handle a disconnect: drop the player from `present` and (if alive) from
-- `alive`. If removing an alive player during an Active round pushes the
-- survivor count below threshold, auto-end. No-op if the player is not present.
function RoundState.removePlayer(model, player)
	if not model.present[player] then
		return { ended = false, winner = nil }
	end
	model.present[player] = nil
	local wasAlive = model.alive[player] == true
	model.alive[player] = nil
	if wasAlive then
		return maybeEnd(model)
	end
	return { ended = false, winner = nil }
end

-- Ended -> Lobby for the next round. Clears `alive` and `winner`; keeps
-- `present` so still-connected players carry over.
function RoundState.reset(model)
	model.phase = "Lobby"
	model.alive = {}
	model.winner = nil
end

return RoundState
