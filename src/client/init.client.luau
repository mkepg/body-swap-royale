--[[
	Client bootstrap.
	Location: StarterPlayerScripts/Client  (LocalScript; siblings are child modules)

	Starts the two client-side drivers for the swap mechanic:
	  - ClientControl: input + camera for the body the server hands us control of
	  - ClientAnimator: local, per-body, velocity-driven animation for every body
--]]

local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()

print("[BSR] Client ready (ownership-transfer model).")
