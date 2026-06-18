--[[
	SwapController (server) -- drives the periodic swap.

	Every CYCLE_SECONDS it gathers the connected players who currently control a
	living body and asks ControlManager to rotate their control. The derangement
	itself now lives in the pure ControlModel (ControlManager.swap), so this file
	only decides WHO is eligible and WHEN.

	Depends on:
	  ReplicatedStorage.Shared.Config        (CYCLE_SECONDS)
	  ServerScriptService.Server.ControlManager
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ControlManager = require(script.Parent.ControlManager)

local SwapController = {}

-- Connected players who currently control a living body.
local function getActivePlayers()
	local players = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local body = ControlManager.getControlledBody(player)
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		if body and body.Parent and hum and hum.Health > 0 then
			table.insert(players, player)
		end
	end
	return players
end

function SwapController.swap()
	local players = getActivePlayers()
	if #players < 2 then
		return false, "need >=2 active players"
	end
	local n = ControlManager.swap(players)
	return true, string.format("swapped %d players", n)
end

function SwapController.start()
	task.spawn(function()
		while true do
			task.wait(Config.CYCLE_SECONDS)
			local ok, msg = SwapController.swap()
			print("[BSR] swap:", ok, msg)
		end
	end)
end

return SwapController
