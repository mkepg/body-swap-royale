local ShopCatalog = require("../src/shared/ShopCatalog")
local SoulPaletteData = require("../src/shared/SoulPaletteData")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local KINDS = { halo_color = true, halo_style = true, trail = true }
local RARITIES = { common = true, uncommon = true, rare = true, epic = true, legendary = true }

-- 25 items, unique ids, valid kinds/rarities, names non-empty.
do
	expect(#ShopCatalog.items == 25, "expected 25 items, got " .. #ShopCatalog.items)
	local seen = {}
	for _, it in ipairs(ShopCatalog.items) do
		expect(type(it.id) == "string" and it.id ~= "", "id must be non-empty string")
		expect(not seen[it.id], "duplicate id: " .. it.id)
		seen[it.id] = true
		expect(KINDS[it.kind], it.id .. ": bad kind " .. tostring(it.kind))
		expect(RARITIES[it.rarity], it.id .. ": bad rarity " .. tostring(it.rarity))
		expect(type(it.name) == "string" and it.name ~= "", it.id .. ": bad name")
		expect(it.price == nil or (type(it.price) == "number" and it.price > 0),
			it.id .. ": bad price override")
	end
	print("catalog: identity invariants OK")
end

-- Kind counts match the spec (15 colors / 5 styles / 5 trails).
do
	local n = { halo_color = 0, halo_style = 0, trail = 0 }
	for _, it in ipairs(ShopCatalog.items) do n[it.kind] += 1 end
	expect(n.halo_color == 15, "expected 15 colors, got " .. n.halo_color)
	expect(n.halo_style == 5, "expected 5 styles, got " .. n.halo_style)
	expect(n.trail == 5, "expected 5 trails, got " .. n.trail)
	print("catalog: kind counts OK")
end

-- Colors: fill present; luminous defaults to fill via luminousOf; styles/trails have keys.
do
	for _, it in ipairs(ShopCatalog.items) do
		if it.kind == "halo_color" then
			expect(type(it.fill) == "table" and it.fill.r and it.fill.g and it.fill.b,
				it.id .. ": fill must be {r,g,b}")
			local lum = ShopCatalog.luminousOf(it)
			expect(lum.r and lum.g and lum.b, it.id .. ": luminousOf broken")
			if not it.luminous then
				expect(lum == it.fill, it.id .. ": luminous must default to fill")
			end
		elseif it.kind == "halo_style" then
			expect(type(it.styleKey) == "string", it.id .. ": missing styleKey")
		else
			expect(type(it.trailKey) == "string", it.id .. ": missing trailKey")
		end
	end
	print("catalog: payload shapes OK")
end

-- byId lookup.
do
	expect(ShopCatalog.byId("color_void").name == "Void", "byId color_void")
	expect(ShopCatalog.byId("nope") == nil, "byId unknown -> nil")
	print("catalog: byId OK")
end

-- Disjointness invariant (spec §3 #7): every STATIC color fill sits at RGB
-- Euclidean distance >= 90 from every free palette entry. Static = anim.kind
-- "none" or "flash" (flash's fill is on screen most of the time).
local function dist(a, b)
	local dr, dg, db = a.r - b.r, a.g - b.g, a.b - b.b
	return math.sqrt(dr * dr + dg * dg + db * db)
end
do
	for _, it in ipairs(ShopCatalog.items) do
		if it.kind == "halo_color" and (it.anim == nil or it.anim.kind == "flash") then
			for i, free in ipairs(SoulPaletteData) do
				local d = dist(it.fill, free)
				expect(d >= 90, string.format(
					"%s too close to free palette #%d (distance %.1f < 90)", it.id, i, d))
			end
		end
	end
	print("catalog: static-fill disjointness OK")
end

print("ALL shop_catalog tests passed")
