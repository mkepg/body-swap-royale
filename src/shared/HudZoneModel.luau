--[[
	HudZoneModel -- PURE named HUD zone geometry from viewport + top inset
	(spec §6.3). Fixes the mobile banner-under-Roblox-menu collision at the ROOT:
	every zone consumer inherits safe placement; no per-screen patches. Positions
	are expressed as { anchor = {x,y}, position = { scaleX, offsetX, scaleY,
	offsetY } } plus yOffsetPx convenience for the top zone. HudTheme converts to
	UDim2/Vector2 (Roblox types stay out of here).
--]]

local HudZoneModel = {}

local TOP_MARGIN = 14        -- breathing room below the safe top (the old fixed y)
local MIN_TOP = 14           -- never tighter than the original desktop look

-- vp = { w, h, insetTop }
function HudZoneModel.zones(vp)
	local safeTop = math.max(MIN_TOP, (vp.insetTop or 0) + TOP_MARGIN)
	return {
		top      = { anchor = { x = 0.5, y = 0 },   position = { 0.5, 0, 0, safeTop }, yOffsetPx = safeTop },
		topTimer = { anchor = { x = 0.5, y = 0 },   position = { 0.5, 0, 0, safeTop + math.floor(vp.h * 0.02) } },
		center   = { anchor = { x = 0.5, y = 0.5 }, position = { 0.5, 0, 0.40, 0 } },
		notice   = { anchor = { x = 0.5, y = 0.5 }, position = { 0.5, 0, 0.62, 0 } },
		bottom   = { anchor = { x = 0.5, y = 1 },   position = { 0.5, 0, 0.97, 0 } },
	}
end

-- Banner pixel cap: original 350x168, shrunk on short viewports so the banner +
-- safe top never dominate the screen (<= 30% of height).
function HudZoneModel.bannerCap(vp)
	local h = math.min(168, math.floor(vp.h * 0.30))
	local w = math.min(350, math.floor(h * (350 / 168)))
	return { w = w, h = h }
end

return HudZoneModel
