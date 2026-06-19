--[[
	SoulPalette -- PURE index -> color mapping for the free Soul halo.
	Location (Roblox): ReplicatedStorage/Shared/SoulPalette  (ModuleScript)

	No Roblox APIs: the palette is INJECTED (Config.SOUL_PALETTE in production,
	plain strings in tests), so this stays a pure, lune-testable index map.
	Each connected player gets a stable index (join order); this returns their
	color, wrapping if there are more players than palette entries.
--]]

local SoulPalette = {}

-- 1-based `index` -> palette color, wrapping modulo palette size.
function SoulPalette.colorForIndex(index, palette)
	local n = #palette
	assert(n > 0, "palette must be non-empty")
	local i = ((index - 1) % n) + 1
	return palette[i]
end

return SoulPalette
