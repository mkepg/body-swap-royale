--[[
	Server bootstrap (Init) -- ownership-transfer model.
	Location: ServerScriptService/Server  (Script; siblings are its child modules)

	Players have NO Character; they're disembodied controllers. Each gets a
	persistent body wearing their avatar, and starts by controlling their own.
	Every CYCLE_SECONDS the SwapController rotates control so nobody keeps it.

	On disconnect, ControlManager.removePlayer applies the absorb rule so a leaving
	player never yanks a body someone else controls, then destroys the leaver's
	avatar body. (It is NOT safe to destroy the avatar body directly here.)
--]]

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local BodyManager = require(script.BodyManager)
local ControlManager = require(script.ControlManager)
local SwapController = require(script.SwapController)

local function onPlayerAdded(player)
	local body = BodyManager.createBody(player) -- persistent avatar body
	ControlManager.addPlayer(player, body)      -- start in your own body
	print(string.format("[BSR] %s -> own body (%s)", player.Name, body.Name))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	ControlManager.removePlayer(player) -- absorb + destroy; never a bare removeBody
end)

SwapController.start()
print("[BSR] Server ready (ownership-transfer model). Swap loop active.")
