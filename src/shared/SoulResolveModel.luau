--[[
	SoulResolveModel -- PURE server-authoritative identity resolution (spec §5.4).
	Given a profile's `equipped` map, the catalog, and the auto-assigned palette
	color, returns what the SoulMap broadcast should carry for this player:
	  { fill, colorId?, styleId?, trailId? }
	`fill` is the RESOLVED identity color every consumer agrees on (equipped color's
	fill, else assigned). Invalid/stale/wrong-kind ids degrade silently -- a removed
	catalog item must never error or blank a halo.
	Location (Roblox): ReplicatedStorage/Shared/SoulResolveModel  (ModuleScript)
--]]

local SoulResolveModel = {}

local function validEquip(catalog, id, kind)
	if type(id) ~= "string" then return nil end
	local item = catalog.byId(id)
	return (item and item.kind == kind) and item or nil
end

function SoulResolveModel.resolve(equipped, catalog, assignedFill)
	equipped = equipped or {}
	local colorItem = validEquip(catalog, equipped.halo_color, "halo_color")
	local styleItem = validEquip(catalog, equipped.halo_style, "halo_style")
	local trailItem = validEquip(catalog, equipped.trail, "trail")
	return {
		fill = colorItem and colorItem.fill or assignedFill,
		colorId = colorItem and colorItem.id or nil,
		styleId = styleItem and styleItem.id or nil,
		trailId = trailItem and trailItem.id or nil,
	}
end

return SoulResolveModel
