--[[
	Client bootstrap.
	Location: StarterPlayerScripts/Client  (LocalScript; siblings are child modules)

	Starts the client-side modules for the swap mechanic:
	  - ClientControl: input + camera for the body the server hands us control of
	  - ClientAnimator: local, per-body, velocity-driven animation for every body
	  - ClientRoundHud: round text (countdown/elimination/winner) + spectator camera
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)
local ClientSwapHud = require(script.ClientSwapHud)
local SwapPreviewController = require(script.SwapPreviewController)
local SoulController = require(script.SoulController)
local HintController = require(script.HintController)
local WorldShell = require(script.WorldShell)
local ArenaDressing = require(script.ArenaDressing)
local LobbyStage = require(script.LobbyStage)
local ClientEconomyHud = require(script.ClientEconomyHud)
local DeviceOrientation = require(script.DeviceOrientation)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
ClientSwapHud.start()
SwapPreviewController.start()
SoulController.start()
HintController.start()
WorldShell.start()
ArenaDressing.start()
LobbyStage.start()
ClientEconomyHud.start()
DeviceOrientation.start()

-- Soul Sweeper (arena #2) cosmetics: beams + telegraph + tumble. Only started when
-- that arena is active, so the hex path (ACTIVE_ARENA == "hex") is unaffected.
if Config.ACTIVE_ARENA == "sweeper" then
	local SweeperController = require(script.SweeperController)
	SweeperController.start(ClientControl.getBody)
end

print("[BSR] Client ready (ownership-transfer model).")
