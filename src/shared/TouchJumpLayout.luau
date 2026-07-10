--[[
	TouchJumpLayout -- PURE layout math for the mobile jump button.
	Location (Roblox): ReplicatedStorage/Shared/TouchJumpLayout (ModuleScript)

	No Roblox globals (lune-tested). Reproduces the DEFAULT TouchJump button's
	form-factor rules -- verified against the live PlayerModule TouchJump source
	2026-07-10 (classic path): breakpoint min(viewport axes) <= 500; base size
	70 px (small screens / phones) else 120 px (tablets+); position offsets
	small: (-(size*1.5 - 10), -size - 20), large: (-(size*1.5 - 10), -size*1.75)
	from the bottom-right corner. `scale` multiplies SIZE only; the position
	formulas take the scaled size, so margins grow with the button and it can
	never leave the screen. The glue (InputController) converts to UDim2.
--]]

local TouchJumpLayout = {}

function TouchJumpLayout.compute(viewportX, viewportY, scale)
	assert(type(scale) == "number" and scale > 0,
		"TouchJumpLayout.compute: scale must be a positive number")
	local minAxis = math.min(viewportX, viewportY)
	local isSmallScreen = minAxis <= 500
	local size = math.floor((isSmallScreen and 70 or 120) * scale + 0.5)
	return {
		size = size,
		xOffset = -(size * 1.5 - 10),
		yOffset = isSmallScreen and (-size - 20) or (-size * 1.75),
		isSmallScreen = isSmallScreen,
	}
end

return TouchJumpLayout
