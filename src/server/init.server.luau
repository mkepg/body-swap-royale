--[[
	Server bootstrap (Init) -- ownership-transfer model.
	Location: ServerScriptService/Server  (Script; siblings are its child modules)

	Players have NO Character; they're disembodied controllers. Each gets a
	persistent body wearing their avatar, and starts by controlling their own.
	Every CYCLE_SECONDS the SwapController rotates ownership so nobody keeps it.

	Animation is driven client-side per body (see Client/ClientAnimator); there
	is no server-side animator.
--]]

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local BodyManager = require(script.BodyManager)
local ControlManager = require(script.ControlManager)
local SwapController = require(script.SwapController)

local function onPlayerAdded(player)
	local body = BodyManager.createBody(player)        -- persistent avatar body
	ControlManager.assignOne(player, body, false)      -- start in your own body
	print(string.format("[BSR] %s -> own body (%s)", player.Name, body.Name))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	ControlManager.release(player)
	BodyManager.removeBody(player)
end)

SwapController.start()
print("[BSR] Server ready (ownership-transfer model). Swap loop active.")
