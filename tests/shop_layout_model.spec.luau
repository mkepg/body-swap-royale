local ShopLayoutModel = require("../src/shared/ShopLayoutModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

-- Desktop 1920x1080: side panel, clamped width, 2 columns.
do
	local L = ShopLayoutModel.layout({ w = 1920, h = 1080, insetTop = 36 })
	expect(L.mode == "panel", "desktop mode")
	expect(L.panelW >= 330 and L.panelW <= 460, "panel width clamped, got " .. L.panelW)
	expect(L.columns == 2, "2 columns")
	expect(L.panelTopPx >= 36 + 10, "panel clears inset")
	print("layout: desktop OK")
end

-- Tablet landscape 1180x820: still a panel.
do
	local L = ShopLayoutModel.layout({ w = 1180, h = 820, insetTop = 36 })
	expect(L.mode == "panel", "tablet mode")
	expect(L.panelW <= 1180 * 0.55, "panel under sheet threshold")
	print("layout: tablet OK")
end

-- Small phone landscape: sheet mode when panel would exceed 55% width.
do
	local L = ShopLayoutModel.layout({ w = 640, h = 360, insetTop = 58 })
	expect(L.mode == "sheet", "small phone -> sheet")
	expect(L.columns >= 2, "sheet keeps >= 2 columns")
	print("layout: phone sheet OK")
end

-- Touch targets never dip below 44px.
do
	for _, vp in ipairs({ { w = 1920, h = 1080, insetTop = 36 }, { w = 844, h = 390, insetTop = 58 },
	                      { w = 640, h = 360, insetTop = 58 } }) do
		local L = ShopLayoutModel.layout(vp)
		expect(L.cardH >= 44, "card height >= 44 at " .. vp.w .. "x" .. vp.h)
		expect(L.tabH >= 32, "tab height reasonable")
	end
	print("layout: touch floor OK")
end

print("ALL shop_layout_model tests passed")
