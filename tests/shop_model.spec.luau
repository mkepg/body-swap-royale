local ShopModel = require("../src/shared/ShopModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local CATALOG = {
	items = {
		{ id = "color_a", kind = "halo_color", name = "A", rarity = "common" },
		{ id = "style_b", kind = "halo_style", name = "B", rarity = "rare", styleKey = "b" },
		{ id = "trail_c", kind = "trail", name = "C", rarity = "epic", trailKey = "c", price = 77 },
	},
}
CATALOG.byId = function(id)
	for _, it in ipairs(CATALOG.items) do if it.id == id then return it end end
	return nil
end
local PRICES = { common = 200, uncommon = 450, rare = 900, epic = 1800, legendary = 4000 }

local function freshProfile(coins)
	return { coins = coins, totalXp = 0, ownedItems = {}, equipped = {} }
end

-- priceOf: rarity default + per-item override.
do
	expect(ShopModel.priceOf(CATALOG.byId("color_a"), PRICES) == 200, "rarity price")
	expect(ShopModel.priceOf(CATALOG.byId("trail_c"), PRICES) == 77, "override price")
	print("shop_model: priceOf OK")
end

-- validatePurchase error paths.
do
	local p = freshProfile(100)
	local r = ShopModel.validatePurchase(p, CATALOG, PRICES, "nope")
	expect(not r.ok and r.err == "unknown_item", "unknown item")
	r = ShopModel.validatePurchase(p, CATALOG, PRICES, "color_a")
	expect(not r.ok and r.err == "insufficient_coins", "insufficient")
	p.coins = 200
	r = ShopModel.validatePurchase(p, CATALOG, PRICES, "color_a")
	expect(r.ok and r.item.id == "color_a", "valid purchase at exact balance")
	ShopModel.applyPurchase(p, r.item, PRICES)
	r = ShopModel.validatePurchase(p, CATALOG, PRICES, "color_a")
	expect(not r.ok and r.err == "already_owned", "already owned")
	print("shop_model: validatePurchase OK")
end

-- applyPurchase: deducts, owns, auto-equips.
do
	local p = freshProfile(1000)
	local item = CATALOG.byId("style_b")
	ShopModel.applyPurchase(p, item, PRICES)
	expect(p.coins == 100, "coins deducted (1000-900)")
	expect(p.ownedItems[1] == "style_b", "owned")
	expect(p.equipped.halo_style == "style_b", "auto-equipped")
	print("shop_model: applyPurchase OK")
end

-- validateEquip / applyEquip incl. "default".
do
	local p = freshProfile(2000)
	local r = ShopModel.validateEquip(p, CATALOG, "trail_c")
	expect(not r.ok and r.err == "not_owned", "equip unowned")
	r = ShopModel.validateEquip(p, CATALOG, "nope")
	expect(not r.ok and r.err == "unknown_item", "equip unknown")
	ShopModel.applyPurchase(p, CATALOG.byId("trail_c"), PRICES)
	r = ShopModel.validateEquip(p, CATALOG, "trail_c")
	expect(r.ok, "equip owned")
	-- default clears any kind, always valid
	r = ShopModel.validateEquip(p, CATALOG, "default", "trail")
	expect(r.ok, "default always valid")
	ShopModel.applyEquip(p, "trail", "default")
	expect(p.equipped.trail == nil, "default clears slot")
	print("shop_model: equip OK")
end

print("ALL shop_model tests passed")
