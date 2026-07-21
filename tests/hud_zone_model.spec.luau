local HudZoneModel = require("../src/shared/HudZoneModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

-- Desktop, inset 36: top zone sits BELOW the inset with margin.
do
	local z = HudZoneModel.zones({ w = 1920, h = 1080, insetTop = 36 })
	expect(z.top.yOffsetPx >= 36 + 10, "top zone clears the inset (+margin)")
	expect(z.top.anchor.x == 0.5 and z.top.anchor.y == 0, "top anchor")
	print("zones: desktop OK")
end

-- Phone (short viewport, bigger relative inset): still clears; banner cap shrinks.
do
	local z = HudZoneModel.zones({ w = 844, h = 390, insetTop = 58 })
	expect(z.top.yOffsetPx >= 58 + 10, "phone top clears inset")
	local cap = HudZoneModel.bannerCap({ w = 844, h = 390, insetTop = 58 })
	expect(cap.h <= 390 * 0.30, "banner cap <= 30% of short viewport height")
	expect(cap.w <= 350 and cap.h <= 168, "cap never exceeds original max")
	print("zones: phone OK")
end

-- topLeft zone: anchored (0,0), clears the inset like `top`.
do
	local z = HudZoneModel.zones({ w = 1920, h = 1080, insetTop = 36 })
	expect(z.topLeft and z.topLeft.anchor.x == 0 and z.topLeft.anchor.y == 0, "topLeft anchored top-left")
	expect(z.topLeft.yOffsetPx >= 36 + 10, "topLeft clears the inset")
	expect(z.topLeft.position[2] == 14, "topLeft x margin 14px")
end

-- Zero inset (Studio edit / desktop app): behaves like the old 14px placement.
do
	local z = HudZoneModel.zones({ w = 1920, h = 1080, insetTop = 0 })
	expect(z.top.yOffsetPx >= 14, "no-inset keeps a minimum margin")
	print("zones: zero inset OK")
end

-- All named zones exist with anchors + positions.
do
	local z = HudZoneModel.zones({ w = 1280, h = 720, insetTop = 36 })
	for _, key in ipairs({ "top", "topLeft", "topTimer", "center", "notice", "bottom" }) do
		expect(z[key] and z[key].anchor and z[key].position, "zone " .. key .. " present")
	end
	print("zones: completeness OK")
end

print("ALL hud_zone_model tests passed")
