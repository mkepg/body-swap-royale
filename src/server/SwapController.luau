--[[
	SwapController (server) -- performs one swap over a given roster.

	RoundManager decides WHEN to swap (the cycle clock) and RoundState decides WHO
	is eligible (the alive set). This module just takes the ordered roster of alive
	players and rotates their control via ControlManager (Sattolo derangement lives
	in the pure ControlModel). It no longer owns a loop or an eligibility filter.

	Depends on:
	  ServerScriptService.Server.ControlManager
--]]

local ControlManager = require(script.Parent.ControlManager)

local SwapController = {}

-- Compute the next swap over `orderedAlive` WITHOUT applying it (drives the
-- T-3s preview). Returns a plan, or nil + message if too few players.
function SwapController.plan(orderedAlive)
	if #orderedAlive < 2 then
		return nil, "need >=2 alive players"
	end
	return ControlManager.planSwap(orderedAlive)
end

-- Apply a previously computed plan (the authoritative T0 commit). Returns how
-- many players were swapped.
function SwapController.commit(plan)
	return ControlManager.commitSwap(plan)
end

-- True iff `plan` still matches the current control map (re-plan decision).
function SwapController.planStillValid(plan)
	return ControlManager.planStillValid(plan)
end

return SwapController
