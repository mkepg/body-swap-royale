--[[
	ShopModel -- PURE Soul Shop purchase/equip decisions (spec 2026-07-16 §4.2).
	Roblox-free: catalog + prices are injected. The SERVER is the only caller that
	mutates real profiles; the client may reuse validate* for optimistic UI states.
	Errors are short string codes forwarded to the client via ShopResult.
	Location (Roblox): ReplicatedStorage/Shared/ShopModel  (ModuleScript)
--]]

local ShopModel = {}

function ShopModel.priceOf(item, prices)
	return item.price or prices[item.rarity]
end

local function owns(profile, itemId)
	for _, id in ipairs(profile.ownedItems) do
		if id == itemId then return true end
	end
	return false
end

function ShopModel.validatePurchase(profile, catalog, prices, itemId)
	local item = catalog.byId(itemId)
	if not item then
		return { ok = false, err = "unknown_item" }
	end
	if owns(profile, itemId) then
		return { ok = false, err = "already_owned" }
	end
	if profile.coins < ShopModel.priceOf(item, prices) then
		return { ok = false, err = "insufficient_coins" }
	end
	return { ok = true, item = item }
end

-- Deduct + own + auto-equip (spec decision #5). Caller must have validated.
function ShopModel.applyPurchase(profile, item, prices)
	profile.coins -= ShopModel.priceOf(item, prices)
	profile.ownedItems[#profile.ownedItems + 1] = item.id
	profile.equipped[item.kind] = item.id
end

-- kind is only required for itemId == "default" (nothing to look up).
function ShopModel.validateEquip(profile, catalog, itemId, kind)
	if itemId == "default" then
		return { ok = true, kind = kind }
	end
	local item = catalog.byId(itemId)
	if not item then
		return { ok = false, err = "unknown_item" }
	end
	if not owns(profile, itemId) then
		return { ok = false, err = "not_owned" }
	end
	return { ok = true, item = item, kind = item.kind }
end

function ShopModel.applyEquip(profile, kind, itemIdOrDefault)
	profile.equipped[kind] = itemIdOrDefault ~= "default" and itemIdOrDefault or nil
end

return ShopModel
