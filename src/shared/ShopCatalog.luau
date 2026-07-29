--[[
	ShopCatalog -- the Soul Shop item catalog (spec 2026-07-16 §4.1/§7). PLAIN DATA:
	colors are {r,g,b} 0-255 tables (lune-safe; clients convert via Color3.fromRGB).
	Item ids are PERMANENT -- they persist in player profiles; rename `name` freely,
	never `id`. Prices default per-rarity from Config.SHOP_PRICES; `price` overrides.
	anim kinds: osc (smooth 2-color), flicker (irregular 2-color), steps (hard snaps),
	sweep (UIGradient band), gradient (multi-stop drift), flash (fill + timed rim
	pulse), hue (full rotation). Static (no anim / flash) fills MUST keep RGB distance
	>= 90 from every SoulPaletteData entry (machine-checked).
	Location (Roblox): ReplicatedStorage/Shared/ShopCatalog  (ModuleScript)
--]]

local ShopCatalog = {}

local function rgb(r, g, b) return { r = r, g = g, b = b } end

ShopCatalog.items = {
	-- ===== Halo colors (15) =====
	-- pale family (static commons)
	{ id = "color_moonlit",   kind = "halo_color", name = "Moonlit",      rarity = "common",
	  fill = rgb(226, 218, 255) },
	{ id = "color_frostbite", kind = "halo_color", name = "Frostbite",    rarity = "common",
	  fill = rgb(190, 235, 255) },
	{ id = "color_seafoam",   kind = "halo_color", name = "Seafoam",      rarity = "common",
	  fill = rgb(170, 255, 190) },
	{ id = "color_roseglass", kind = "halo_color", name = "Roseglass",    rarity = "common",
	  fill = rgb(255, 224, 236) },
	-- living family
	{ id = "color_ember",     kind = "halo_color", name = "Ember",        rarity = "uncommon",
	  fill = rgb(200, 30, 20),
	  anim = { kind = "flicker", to = rgb(255, 150, 54), period = 1.3 } },
	{ id = "color_tidepool",  kind = "halo_color", name = "Tidepool",     rarity = "uncommon",
	  fill = rgb(30, 90, 220),
	  anim = { kind = "osc", to = rgb(45, 220, 200), period = 4 } },
	{ id = "color_cottoncandy", kind = "halo_color", name = "Cotton Candy", rarity = "uncommon",
	  fill = rgb(255, 183, 221),
	  anim = { kind = "osc", to = rgb(178, 216, 255), period = 3.5 } },
	-- broadcast-glitch family (hard step cuts)
	{ id = "color_neonbuzz",  kind = "halo_color", name = "Neon Buzz",    rarity = "uncommon",
	  fill = rgb(255, 233, 201),
	  anim = { kind = "steps", period = 2.8, frames = {
	      { at = 0.00, c = rgb(255, 233, 201) }, { at = 0.07, c = rgb(84, 72, 60) },
	      { at = 0.09, c = rgb(255, 233, 201) }, { at = 0.11, c = rgb(84, 72, 60) },
	      { at = 0.13, c = rgb(255, 233, 201) }, { at = 0.62, c = rgb(255, 233, 201) },
	      { at = 0.64, c = rgb(138, 122, 98) }, { at = 0.66, c = rgb(255, 233, 201) },
	  } } },
	-- dark family
	{ id = "color_void",      kind = "halo_color", name = "Void",         rarity = "rare",
	  fill = rgb(30, 16, 48), luminous = rgb(190, 120, 255) },
	{ id = "color_static",    kind = "halo_color", name = "Static",       rarity = "rare",
	  fill = rgb(205, 212, 222),
	  anim = { kind = "steps", period = 3.4, frames = {
	      { at = 0.00, c = rgb(205, 212, 222) }, { at = 0.22, c = rgb(159, 216, 222) },
	      { at = 0.24, c = rgb(205, 212, 222) }, { at = 0.47, c = rgb(222, 196, 184) },
	      { at = 0.52, c = rgb(205, 212, 222) }, { at = 0.71, c = rgb(170, 182, 216) },
	      { at = 0.74, c = rgb(232, 228, 218) }, { at = 0.76, c = rgb(205, 212, 222) },
	  } } },
	{ id = "color_duskfall",  kind = "halo_color", name = "Duskfall",     rarity = "rare",
	  fill = rgb(232, 106, 154),
	  anim = { kind = "gradient", period = 7, stops = {
	      rgb(122, 75, 214), rgb(232, 106, 154), rgb(255, 179, 92) } } },
	{ id = "color_stormcloud", kind = "halo_color", name = "Stormcloud",  rarity = "rare",
	  fill = rgb(70, 80, 105), luminous = rgb(200, 215, 255),
	  anim = { kind = "flash", period = 4 } },
	{ id = "color_gilded",    kind = "halo_color", name = "Gilded",       rarity = "epic",
	  fill = rgb(201, 154, 46), luminous = rgb(255, 224, 138),
	  anim = { kind = "sweep", to = rgb(255, 224, 138), period = 3 } },
	{ id = "color_aurora",    kind = "halo_color", name = "Aurora",       rarity = "epic",
	  fill = rgb(200, 110, 255),
	  anim = { kind = "osc", to = rgb(120, 255, 180), period = 6 } },
	{ id = "color_prism",     kind = "halo_color", name = "Prism",        rarity = "legendary",
	  fill = rgb(255, 71, 71),
	  anim = { kind = "hue", period = 8, s = 0.72, v = 1.0 } },

	-- ===== Halo styles (5) -- colorless frames =====
	{ id = "style_ring",    kind = "halo_style", name = "Ring",       rarity = "uncommon", styleKey = "ring" },
	{ id = "style_pulse",   kind = "halo_style", name = "Pulse",      rarity = "uncommon", styleKey = "pulse" },
	{ id = "style_orbit",   kind = "halo_style", name = "Twin Orbit", rarity = "rare",     styleKey = "orbit" },
	{ id = "style_eclipse", kind = "halo_style", name = "Eclipse",    rarity = "epic",     styleKey = "eclipse" },
	{ id = "style_seraph",  kind = "halo_style", name = "Seraph",     rarity = "legendary", styleKey = "seraph" },

	-- ===== Soul trails (5) -- inherit wearer's luminous color =====
	{ id = "trail_wisp",      kind = "trail", name = "Wisp",        rarity = "uncommon", trailKey = "wisp" },
	{ id = "trail_stream",    kind = "trail", name = "Soul Stream", rarity = "rare",     trailKey = "stream" },
	{ id = "trail_sparkline", kind = "trail", name = "Sparkline",   rarity = "rare",     trailKey = "sparkline" },
	{ id = "trail_comet",     kind = "trail", name = "Comet",       rarity = "epic",     trailKey = "comet" },
	{ id = "trail_meteor",    kind = "trail", name = "Meteor",      rarity = "legendary", trailKey = "meteor" },
}

local byId = {}
for _, it in ipairs(ShopCatalog.items) do
	byId[it.id] = it
end

function ShopCatalog.byId(id)
	return byId[id]
end

-- The glow-element color: luminous when declared, else fill (spec fill/luminous rule).
function ShopCatalog.luminousOf(item)
	return item.luminous or item.fill
end

return ShopCatalog
