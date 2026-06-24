--[[
	SwapTelegraphModel -- PURE swap-HUD display decision.
	Location (Roblox): ReplicatedStorage/Shared/SwapTelegraphModel  (ModuleScript)

	No Roblox APIs and no clocks: the caller injects `secondsUntilSwap` (and the
	preview length). Returns what the HUD should show, so the client renders and
	lune tests the same logic. Mirrors HexErosionModel / GraceModel.
--]]

local SwapTelegraphModel = {}

-- Given seconds until the next swap and the preview-window length, decide:
--   timerText       : always-on countdown, ceil(secondsUntilSwap) clamped >= 0
--   inPreview       : secondsUntilSwap <= previewSeconds
--   bigCountdownInt : 3 / 2 / 1 during preview (nil at/after the swap or outside)
--   flashAlpha      : 0..1 telegraph intensity, ramping as the swap nears
function SwapTelegraphModel.display(secondsUntilSwap, previewSeconds)
	local s = secondsUntilSwap
	if s < 0 then
		s = 0
	end

	local timerText = tostring(math.ceil(s))
	local inPreview = secondsUntilSwap <= previewSeconds
	local bigCountdownInt = nil
	local flashAlpha = 0

	if inPreview then
		if s > 0 then
			bigCountdownInt = math.ceil(s)
			flashAlpha = (previewSeconds - s) / previewSeconds
			if flashAlpha < 0 then flashAlpha = 0 end
			if flashAlpha > 1 then flashAlpha = 1 end
		else
			-- Swap is due (the countdown hit 0). The actual swap (SetControlledBody)
			-- and the next cycle's deadline arrive a beat later -- server task.wait
			-- overshoot + replication -- so HOLD the flash at peak through that gap
			-- instead of blinking out before the swap is visible. The next cycle's
			-- deadline broadcast (fired right after the commit) clears it.
			flashAlpha = 1
		end
	end

	return {
		timerText = timerText,
		inPreview = inPreview,
		bigCountdownInt = bigCountdownInt,
		flashAlpha = flashAlpha,
	}
end

return SwapTelegraphModel
