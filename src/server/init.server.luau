--[[
	Server bootstrap (Init) -- ownership-transfer model + round lifecycle.
	Location: ServerScriptService/Server  (Script; siblings are its child modules)

	Players have NO Character; they're disembodied controllers. Each gets a
	persistent body wearing their avatar, and starts by controlling their own.
	RoundManager owns the round loop: it sequences Lobby -> Active -> Ended,
	gates swaps to the Active phase, and declares a winner.

	Join/leave are routed through RoundManager so RoundState (lifecycle) and the
	control map (bijection) stay in sync. On disconnect RoundManager applies the
	absorb rule via ControlManager before destroying the leaver's avatar body.
--]]

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local RoundManager = require(script.RoundManager)

local function onPlayerAdded(player)
	RoundManager.addPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	RoundManager.removePlayer(player)
end)

RoundManager.start()
print("[BSR] Server ready (ownership-transfer model + round loop).")
