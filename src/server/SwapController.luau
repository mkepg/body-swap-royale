--[[
	SwapController (server) -- THE core mechanic.
	Location: ServerScriptService/Server/SwapController  (ModuleScript)

	Every CYCLE_SECONDS, derange who controls which body so nobody keeps the body
	they were just in. A swap is just rotating network ownership across the pool
	of currently-controlled bodies -- atomic, cheap, and non-destructive.

	Depends on:
	  ReplicatedStorage.Shared.Config        (CYCLE_SECONDS)
	  ServerScriptService.Server.ControlManager (does the actual ownership transfer)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ControlManager = require(script.Parent.ControlManager)

local SwapController = {}

-- Sattolo's algorithm: one pass, single-cycle permutation = always a derangement.
-- Drawing j from 1..i-1 (never i) is exactly what guarantees no fixed point,
-- so no player ever keeps the body they were just in. Correct down to n = 2.
local function sattoloDerangement(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i - 1)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Players who are connected and currently control a living body.
local function getActive()
	local players, bodies = {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		local body = ControlManager.getControlledBody(p)
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		if body and body.Parent and hum and hum.Health > 0 then
			table.insert(players, p)
			table.insert(bodies, body)
		end
	end
	return players, bodies
end

function SwapController.swap()
	local players, bodies = getActive()
	if #players < 2 then
		return false, "need >=2 active players"
	end

	-- Derange the current bodies: newBodies[i] ~= bodies[i] for every i.
	local newBodies = table.clone(bodies)
	sattoloDerangement(newBodies)

	-- Apply: rotate network ownership (not Character), so it's atomic and
	-- nothing is created or destroyed. ControlManager also notifies each client.
	for i, player in ipairs(players) do
		ControlManager.assignOne(player, newBodies[i], true)
	end

	return true, string.format("swapped %d players", #players)
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
