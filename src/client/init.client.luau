--[[
	Client bootstrap.
	Location: StarterPlayerScripts/Client  (LocalScript; siblings are child modules)

	Starts the client-side modules for the swap mechanic:
	  - ClientControl: input + camera for the body the server hands us control of
	  - ClientAnimator: local, per-body, velocity-driven animation for every body
	  - ClientRoundHud: round text (countdown/elimination/winner) + spectator camera
--]]

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
local SweeperController = require(script.SweeperController)

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

-- Soul Sweeper (arena #2) cosmetics: T4 glow-up dressing (wedge seams/rim ring/
-- moat line/hub stack + lantern/annulus).
-- Started unconditionally (persistent two-arena world) -- it self-gates on the
-- server-authoritative LiveArena attribute, so it's fully dormant while hex is live.
SweeperController.start()

print("[BSR] Client ready (ownership-transfer model).")
