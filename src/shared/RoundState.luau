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

return RoundState
