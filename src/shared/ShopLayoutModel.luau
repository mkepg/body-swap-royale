--[[
	ShopLayoutModel -- PURE responsive shop geometry (spec §6.2): viewport + inset
	in, panel/sheet mode + pixel dimensions out. Same pattern as TouchJumpLayout.
	Modes: "panel" (right-anchored side panel; world visible) and "sheet"
	(full-height takeover when a usable panel would cover > 55% of width).
--]]

local ShopLayoutModel = {}

local PANEL_FRACTION = 0.38
local PANEL_MIN, PANEL_MAX = 330, 460
-- Threshold is applied to the CLAMPED panel width: on a small viewport the desired
-- 38% shrinks below PANEL_MIN and clamps back up, so a usable side panel ends up
-- covering ~half the screen -- past this point it dominates the world and becomes a
-- full-height sheet instead (spec §6.2 "> 55% width" intent, measured post-clamp).
local SHEET_THRESHOLD = 0.5
local MARGIN = 10
local CARD_MIN = 44

function ShopLayoutModel.layout(vp)
	local panelW = math.clamp(math.floor(vp.w * PANEL_FRACTION), PANEL_MIN, PANEL_MAX)
	local mode = (panelW / vp.w) > SHEET_THRESHOLD and "sheet" or "panel"
	local safeTop = (vp.insetTop or 0) + MARGIN
	local w = mode == "sheet" and (vp.w - MARGIN * 2) or panelW
	local innerW = w - 26 -- paddings
	local columns = math.max(2, math.floor(innerW / 150))
	local cardW = math.floor((innerW - (columns - 1) * 8) / columns)
	local cardH = math.max(CARD_MIN, math.floor(cardW * 0.82))
	local scale = math.clamp(vp.h / 1080, 0.85, 1.0)
	return {
		mode = mode,
		panelW = w,
		panelTopPx = safeTop,
		panelBottomMarginPx = MARGIN,
		columns = columns,
		cardW = cardW,
		cardH = cardH,
		tabH = math.max(32, math.floor(34 * scale)),
		headerH = math.max(40, math.floor(46 * scale)),
		typeScale = scale,
	}
end

return ShopLayoutModel
