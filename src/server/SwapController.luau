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

-- Rotate control across `orderedAlive` (the alive roster, built by RoundManager
-- from RoundState). Needs >= 2 players. Returns ok, message.
function SwapController.swap(orderedAlive)
	if #orderedAlive < 2 then
		return false, "need >=2 alive players"
	end
	local n = ControlManager.swap(orderedAlive)
	return true, string.format("swapped %d players", n)
end

return SwapController
