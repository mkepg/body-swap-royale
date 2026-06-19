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

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
ClientSwapHud.start()

print("[BSR] Client ready (ownership-transfer model).")
