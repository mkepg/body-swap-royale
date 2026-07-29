local SoulResolveModel = require("../src/shared/SoulResolveModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local CATALOG = {}
CATALOG.byId = function(id)
	if id == "color_x" then
		return { id = "color_x", kind = "halo_color", fill = { r = 1, g = 2, b = 3 } }
	elseif id == "style_y" then
		return { id = "style_y", kind = "halo_style", styleKey = "y" }
	end
	return nil
end

local ASSIGNED = { r = 9, g = 9, b = 9 }

-- No equips -> assigned color, no ids.
do
	local r = SoulResolveModel.resolve({}, CATALOG, ASSIGNED)
	expect(r.fill == ASSIGNED, "assigned fallback")
	expect(r.colorId == nil and r.styleId == nil and r.trailId == nil, "no ids")
	print("resolve: fallback OK")
end

-- Equipped color wins; style/trail ids pass through when valid.
do
	local r = SoulResolveModel.resolve(
		{ halo_color = "color_x", halo_style = "style_y" }, CATALOG, ASSIGNED)
	expect(r.fill.r == 1, "equipped fill wins")
	expect(r.colorId == "color_x" and r.styleId == "style_y" and r.trailId == nil, "ids pass")
	print("resolve: equipped OK")
end

-- Stale/wrong-kind ids resolve to assigned/nil, never error.
do
	local r = SoulResolveModel.resolve(
		{ halo_color = "gone", halo_style = "color_x", trail = "gone2" }, CATALOG, ASSIGNED)
	expect(r.fill == ASSIGNED, "stale color -> assigned")
	expect(r.colorId == nil, "stale color id dropped")
	expect(r.styleId == nil, "wrong-kind style dropped")
	expect(r.trailId == nil, "stale trail dropped")
	print("resolve: stale ids OK")
end

-- nil equipped table (defensive) behaves like {}.
do
	local r = SoulResolveModel.resolve(nil, CATALOG, ASSIGNED)
	expect(r.fill == ASSIGNED and r.colorId == nil, "nil equipped tolerated")
	print("resolve: nil equipped OK")
end

print("ALL soul_resolve_model tests passed")
