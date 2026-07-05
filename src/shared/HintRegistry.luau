--[[
	HintRegistry -- the SINGLE SOURCE OF TRUTH for first-session / contextual hints.
	Pure data, Roblox-free. Each row:
	  { id, trigger, once, priority, duration, anchor, text }
	 - trigger: a generic gameplay event name fired server-side (HintService.fireTrigger)
	 - once:    gate on the player's persisted seenHints (true = show one time ever)
	 - anchor:  "controlledBody" (the body the player controls WHEN the hint fires) |
	            "target" (the swap-preview highlighted body). NOTE: because the preview
	            fires BEFORE the commit's SetControlledBody, "controlledBody" on a
	            SwapPreview hint resolves to the player's CURRENT (pre-swap) body; on a
	            ControlSwap hint it resolves to the NEW (post-swap) body.
	Adding a hint = adding a row here + firing its trigger. No other plumbing.
	Location (Roblox): ReplicatedStorage/Shared/HintRegistry  (ModuleScript)
--]]

local HintRegistry = {
	{
		id = "swap-preview-intro",
		trigger = "SwapPreview",
		once = true,
		priority = 10,
		duration = 3.0,
		-- On the player's CURRENT body (the ping's edge arrow / highlight points to the
		-- body they'll become) -- the caption sits where their attention already is.
		anchor = "controlledBody",
		text = "You're about to become the highlighted body — get ready!",
	},
	{
		id = "swap-commit-intro",
		trigger = "ControlSwap",
		once = true,
		priority = 10,
		duration = 3.5,
		anchor = "controlledBody",
		text = "Your controls just moved — the glowing halo is always you.",
	},
}

return HintRegistry
