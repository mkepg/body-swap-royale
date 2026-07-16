--[[
	SoulPaletteData -- the free Soul palette as PLAIN {r,g,b} (0-255) records.
	Roblox-free so lune tests (shop catalog disjointness) can require it directly;
	Config builds the Color3 SOUL_PALETTE from this table. Single source of truth --
	edit colors HERE, never in Config.
	Location (Roblox): ReplicatedStorage/Shared/SoulPaletteData  (ModuleScript)
--]]

return {
	{ r = 255, g = 80,  b = 80 },  -- red
	{ r = 80,  g = 160, b = 255 }, -- blue
	{ r = 90,  g = 220, b = 120 }, -- green
	{ r = 255, g = 210, b = 70 },  -- yellow
	{ r = 200, g = 110, b = 255 }, -- purple
	{ r = 255, g = 150, b = 60 },  -- orange
	{ r = 80,  g = 230, b = 230 }, -- cyan
	{ r = 255, g = 130, b = 200 }, -- pink
}
