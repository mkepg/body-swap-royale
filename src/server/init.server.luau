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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local RoundManager = require(script.RoundManager)
local EconomyService = require(script.EconomyService)
local ControlManager = require(script.ControlManager)

local function onPlayerAdded(player)
	-- Economy persistence yields on DataStore (retry+backoff, seconds on a throttled
	-- first join). Run it on its own thread so embodiment is NEVER gated behind it --
	-- a disembodied (camera-only) player is the bug we are fixing.
	task.spawn(EconomyService.onPlayerAdded, player) -- load/cache the profile + push it to the client
	RoundManager.addPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	RoundManager.removePlayer(player)
	EconomyService.onPlayerRemoving(player) -- save + drop AFTER the round handles the leave
end)

EconomyService.start() -- autosave loop + BindToClose flush
EconomyService.setEquipChangedCallback(ControlManager.broadcastSoulMap)
Remotes.get("ShopRequest").OnServerEvent:Connect(EconomyService.onShopRequest)
RoundManager.start()
print("[BSR] Server ready (ownership-transfer model + round loop + economy).")
