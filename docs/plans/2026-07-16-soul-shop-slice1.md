# Soul Shop Slice 1 Implementation Plan

**Goal:** The first coin sink — a 25-item Soul cosmetic shop (halo colors, halo styles, trails) with direct coin purchases, persistent equips, server-authoritative identity-color resolution, a unified halo rendering pipeline, a responsive shop UI, and a HUD safe-area system that fixes the mobile banner collision.

**Architecture:** Pure lune-tested decision models (`ShopCatalog`, `ShopModel`, `SoulResolveModel`, `SoulAnimModel`, `ShopLayoutModel`, `HudZoneModel`) + thin glue: `EconomyService` grows the validated `ShopRequest` gauntlet, `ControlManager.broadcastSoulMap` broadcasts resolved colors + equip ids, client `SoulStyles` renders ALL halos (free Classic included) from one pipeline, `ClientShopHud` renders the shop from layout-model output. Spec: `docs/specs/2026-07-16-soul-shop-slice1-design.md`.

**Tech Stack:** Luau (Rojo), lune for pure tests (`export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`), Roblox RemoteEvents/BillboardGui/Trail.

**Branch:** `feat/soul-shop-slice1`. **NEVER commit the dev flips in `src/shared/Config.luau`** (`SOLO_TEST_MODE = true`, `ARENA_OVERRIDE = "sweeper"`). Any commit staging Config must use: flip both to production values (`false`, `""`) → `git add src/shared/Config.luau` → verify staged diff clean of flips (`git diff --cached src/shared/Config.luau | grep -E "SOLO_TEST|ARENA_OVERRIDE"` shows only intended changes) → commit → flip back.

**File structure (locked):**

| File | Responsibility |
|---|---|
| `src/shared/SoulPaletteData.luau` (new) | Plain `{r,g,b}` free-palette source of truth (lune-safe) |
| `src/shared/ShopCatalog.luau` (new) | 25 item records, plain data, zero logic |
| `src/shared/ShopModel.luau` (new) | Purchase/equip validation + application (pure) |
| `src/shared/SoulResolveModel.luau` (new) | equipped-vs-assigned color resolution (pure) |
| `src/shared/SoulAnimModel.luau` (new) | color animation math: osc/flicker/steps/hue at time t (pure) |
| `src/shared/ShopLayoutModel.luau` (new) | responsive shop geometry from viewport+inset (pure) |
| `src/shared/HudZoneModel.luau` (new) | HUD zone positions from viewport+inset (pure) |
| `src/shared/ProfileModel.luau` | + `ownedItems`, `equipped` sanitation |
| `src/shared/Remotes.luau` | + `ShopRequest`, `ShopResult` |
| `src/shared/Config.luau` | SOUL_PALETTE from SoulPaletteData; + SHOP_* knobs; PROFILE_VERSION 2 |
| `src/server/EconomyService.luau` | + onShopRequest gauntlet, debounced save, equip-change callback |
| `src/server/ControlManager.luau` | broadcastSoulMap sends resolved color + equip ids |
| `src/server/init.server.luau` | wire ShopRequest + callback injection |
| `src/client/SoulStyles.luau` (new) | halo builders (classic/ring/pulse/orbit/eclipse/seraph) + shared animator |
| `src/client/SoulController.luau` | consume extended SoulMap; SoulStyles pipeline; trails |
| `src/client/HudTheme.luau` | zones via HudZoneModel + re-place on viewport/inset change |
| `src/client/ClientShopHud.luau` (new) | shop panel UI |
| `src/client/init.client.luau` | + ClientShopHud.start() |

---

### Task 1: SoulPaletteData — lune-safe free-palette source of truth

**Files:**
- Create: `src/shared/SoulPaletteData.luau`
- Modify: `src/shared/Config.luau` (SOUL_PALETTE derives from it)
- Test: existing `tests/soul_palette.spec.luau` must stay green

- [ ] **Step 1: Create the data module**

```luau
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
```

- [ ] **Step 2: Derive Config.SOUL_PALETTE from it**

In `src/shared/Config.luau`, replace the `Config.SOUL_PALETTE = { ... 8 Color3 lines ... }` block with:

```luau
local SoulPaletteData = require(script.Parent.SoulPaletteData)
Config.SOUL_PALETTE = {}
for i, c in ipairs(SoulPaletteData) do
	Config.SOUL_PALETTE[i] = Color3.fromRGB(c.r, c.g, c.b)
end
```

(Place the `require` next to Config's other top-of-file locals if it has any; otherwise directly above the block. Keep the original comment block above `Config.SOUL_PALETTE`.)

- [ ] **Step 3: Run the full suite to prove no regression**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || echo "FAILED: $f"; done`
Expected: all 26 suites pass, no `FAILED:` lines.

- [ ] **Step 4: Commit (Config carries dev flips — use the flip procedure from the header)**

```bash
git add src/shared/SoulPaletteData.luau
# flip SOLO_TEST_MODE->false, ARENA_OVERRIDE->"" in Config, then:
git add src/shared/Config.luau
git diff --cached src/shared/Config.luau   # verify ONLY the palette change is staged
git commit -m "refactor(soul): free palette source of truth -> lune-safe SoulPaletteData"
# flip Config dev pins back (SOLO_TEST_MODE=true, ARENA_OVERRIDE="sweeper")
```

---

### Task 2: ShopCatalog — the 25 items + invariants test

**Files:**
- Create: `src/shared/ShopCatalog.luau`
- Test: `tests/shop_catalog.spec.luau`

- [ ] **Step 1: Write the failing test**

```luau
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/shop_catalog.spec.luau`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the catalog**

```luau
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
	  fill = rgb(160, 255, 210) },
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/shop_catalog.spec.luau`
Expected: `ALL shop_catalog tests passed`. If disjointness fails, adjust the flagged fill AND update the spec §7 table in the same commit — never weaken the threshold.

- [ ] **Step 5: Commit**

```bash
git add src/shared/ShopCatalog.luau tests/shop_catalog.spec.luau
git commit -m "feat(shop): 25-item ShopCatalog + invariants incl. free-palette disjointness"
```

---

### Task 3: ShopModel — purchase/equip decisions

**Files:**
- Create: `src/shared/ShopModel.luau`
- Test: `tests/shop_model.spec.luau`

- [ ] **Step 1: Write the failing test**

```luau
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/shop_model.spec.luau`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```luau
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/shop_model.spec.luau`
Expected: `ALL shop_model tests passed`

- [ ] **Step 5: Commit**

```bash
git add src/shared/ShopModel.luau tests/shop_model.spec.luau
git commit -m "feat(shop): pure ShopModel purchase/equip decisions"
```

---

### Task 4: ProfileModel extension + SoulResolveModel

**Files:**
- Modify: `src/shared/ProfileModel.luau`
- Create: `src/shared/SoulResolveModel.luau`
- Test: `tests/profile_model.spec.luau` (extend), `tests/soul_resolve_model.spec.luau` (new)

- [ ] **Step 1: Extend the profile test (append to `tests/profile_model.spec.luau`)**

```luau
-- ===== Slice-1 shop fields (2026-07-16) =====

-- default() carries empty shop fields.
do
	local p = ProfileModel.default(2)
	expect(type(p.ownedItems) == "table" and #p.ownedItems == 0, "default ownedItems empty")
	expect(type(p.equipped) == "table" and next(p.equipped) == nil, "default equipped empty")
	print("profile: shop defaults OK")
end

-- sanitize: garbage ownedItems/equipped coerced; valid entries kept.
do
	local p = ProfileModel.sanitize({
		coins = 5,
		ownedItems = { "color_void", "", 7, "color_void", "style_ring" },
		equipped = { halo_color = "color_void", trail = 9, bogus_kind = "x", halo_style = "" },
	}, 2)
	expect(#p.ownedItems == 2 and p.ownedItems[1] == "color_void" and p.ownedItems[2] == "style_ring",
		"ownedItems deduped + cleaned")
	expect(p.equipped.halo_color == "color_void", "valid equip kept")
	expect(p.equipped.trail == nil, "non-string equip dropped")
	expect(p.equipped.bogus_kind == nil, "unknown kind dropped")
	expect(p.equipped.halo_style == nil, "empty-string equip dropped")
	print("profile: shop sanitize OK")
end

-- sanitize(nil) still yields clean shop fields.
do
	local p = ProfileModel.sanitize(nil, 2)
	expect(#p.ownedItems == 0 and next(p.equipped) == nil, "nil blob -> empty shop fields")
	print("profile: nil blob shop fields OK")
end
```

- [ ] **Step 2: Run to verify the new blocks fail**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/profile_model.spec.luau`
Expected: FAIL at "default ownedItems empty".

- [ ] **Step 3: Implement in `ProfileModel.luau`**

Add below `toStringList`:

```luau
-- The three equip slots; anything else in a persisted blob is dropped.
local EQUIP_KINDS = { halo_color = true, halo_style = true, trail = true }

-- Map of known kind -> non-empty string item id; everything else -> dropped.
local function toEquipped(v)
	local out = {}
	if type(v) == "table" then
		for kind, id in pairs(v) do
			if EQUIP_KINDS[kind] and type(id) == "string" and id ~= "" then
				out[kind] = id
			end
		end
	end
	return out
end
```

Change `default` and `sanitize`:

```luau
function ProfileModel.default(version)
	return { version = version, coins = 0, totalXp = 0, seenHints = {}, ownedItems = {}, equipped = {} }
end

function ProfileModel.sanitize(blob, version)
	local profile = ProfileModel.default(version)
	if type(blob) == "table" then
		profile.coins = toCount(blob.coins) or 0
		profile.totalXp = toCount(blob.totalXp) or 0
		profile.seenHints = toStringList(blob.seenHints)
		profile.ownedItems = toStringList(blob.ownedItems)
		profile.equipped = toEquipped(blob.equipped)
	end
	return profile
end
```

- [ ] **Step 4: Run profile test**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/profile_model.spec.luau`
Expected: PASS incl. new blocks.

- [ ] **Step 5: Write the failing SoulResolveModel test (`tests/soul_resolve_model.spec.luau`)**

```luau
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

print("ALL soul_resolve_model tests passed")
```

- [ ] **Step 6: Run to verify it fails, then implement**

```luau
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
```

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/soul_resolve_model.spec.luau`
Expected: `ALL soul_resolve_model tests passed`

- [ ] **Step 7: Bump `Config.PROFILE_VERSION` to 2 and add shop knobs (near the economy block, line ~530)**

```luau
Config.PROFILE_VERSION = 2 -- v2: + ownedItems/equipped (Soul Shop slice 1)

-- ===== Soul Shop (slice 1) =====
Config.SHOP_PRICES = { common = 200, uncommon = 450, rare = 900, epic = 1800, legendary = 4000 }
Config.SHOP_RATE_MAX = 5        -- max ShopRequests per window per player
Config.SHOP_RATE_WINDOW = 2     -- seconds
Config.SHOP_SAVE_DEBOUNCE = 5   -- seconds after last purchase before async save
```

- [ ] **Step 8: Run the full suite, then commit (Config flip procedure!)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || echo "FAILED: $f"; done`
Expected: all suites pass (now 28 with the two new specs).

```bash
git add src/shared/ProfileModel.luau src/shared/SoulResolveModel.luau tests/profile_model.spec.luau tests/soul_resolve_model.spec.luau
# flip Config pins -> production, stage, verify, then:
git add src/shared/Config.luau
git diff --cached src/shared/Config.luau   # verify: PROFILE_VERSION + SHOP_* only
git commit -m "feat(shop): profile shop fields (v2) + SoulResolveModel + shop Config knobs"
# flip Config pins back
```

---

### Task 5: SoulAnimModel — pure color animation math

**Files:**
- Create: `src/shared/SoulAnimModel.luau`
- Test: `tests/soul_anim_model.spec.luau`

- [ ] **Step 1: Write the failing test**

```luau
local SoulAnimModel = require("../src/shared/SoulAnimModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b) return math.abs(a - b) < 0.5 end

local FILL = { r = 100, g = 200, b = 0 }

-- nil anim -> fill, always.
do
	local c = SoulAnimModel.colorAt(nil, FILL, 12.34)
	expect(c == FILL, "no anim returns fill identity")
	print("anim: none OK")
end

-- osc: t=0 -> fill, t=period/2 -> to, t=period -> fill (cosine ease).
do
	local anim = { kind = "osc", to = { r = 0, g = 0, b = 100 }, period = 4 }
	local c0 = SoulAnimModel.colorAt(anim, FILL, 0)
	expect(near(c0.r, 100) and near(c0.b, 0), "osc t=0 at fill")
	local ch = SoulAnimModel.colorAt(anim, FILL, 2)
	expect(near(ch.r, 0) and near(ch.b, 100), "osc t=period/2 at to")
	local cf = SoulAnimModel.colorAt(anim, FILL, 4)
	expect(near(cf.r, 100), "osc wraps at period")
	print("anim: osc OK")
end

-- steps: hard snaps, last frame holds to period end.
do
	local anim = { kind = "steps", period = 2, frames = {
		{ at = 0.0, c = { r = 10, g = 0, b = 0 } },
		{ at = 0.5, c = { r = 20, g = 0, b = 0 } },
	} }
	expect(SoulAnimModel.colorAt(anim, FILL, 0.2).r == 10, "steps frame 1")
	expect(SoulAnimModel.colorAt(anim, FILL, 1.2).r == 20, "steps frame 2")
	expect(SoulAnimModel.colorAt(anim, FILL, 1.99).r == 20, "steps holds last")
	expect(SoulAnimModel.colorAt(anim, FILL, 2.2).r == 10, "steps wraps")
	print("anim: steps OK")
end

-- flicker: deterministic for same t; stays within fill..to channel bounds.
do
	local anim = { kind = "flicker", to = { r = 255, g = 150, b = 54 }, period = 1.3 }
	local a = SoulAnimModel.colorAt(anim, { r = 200, g = 30, b = 20 }, 0.7)
	local b = SoulAnimModel.colorAt(anim, { r = 200, g = 30, b = 20 }, 0.7)
	expect(a.r == b.r and a.g == b.g, "flicker deterministic")
	expect(a.r >= 200 - 0.5 and a.r <= 255.5, "flicker r in range")
	print("anim: flicker OK")
end

-- hue: rotates; quarter period apart differ; period apart equal.
do
	local anim = { kind = "hue", period = 8, s = 0.72, v = 1.0 }
	local a = SoulAnimModel.colorAt(anim, FILL, 0)
	local b = SoulAnimModel.colorAt(anim, FILL, 2)
	local c = SoulAnimModel.colorAt(anim, FILL, 8)
	expect(a.r ~= b.r or a.g ~= b.g or a.b ~= b.b, "hue moves")
	expect(near(a.r, c.r) and near(a.g, c.g) and near(a.b, c.b), "hue wraps")
	print("anim: hue OK")
end

print("ALL soul_anim_model tests passed")
```

- [ ] **Step 2: Run to verify it fails, then implement**

```luau
--[[
	SoulAnimModel -- PURE animated-halo-color math (spec §4.1 anim kinds). Given an
	anim spec, the fill, and a time, returns the {r,g,b} to show. Deterministic in t
	(no state, no RNG) so every client renders the same wearer identically and lune
	can pin behavior. Kinds handled HERE: osc, flicker, steps, hue. Kinds handled
	STRUCTURALLY by the renderer (they animate sub-elements, not the flat color):
	sweep/gradient (UIGradient offset via SoulAnimModel.phase) and flash (rim pulse
	via SoulAnimModel.flashOn).
	Location (Roblox): ReplicatedStorage/Shared/SoulAnimModel  (ModuleScript)
--]]

local SoulAnimModel = {}

local function lerp(a, b, k)
	return {
		r = a.r + (b.r - a.r) * k,
		g = a.g + (b.g - a.g) * k,
		b = a.b + (b.b - a.b) * k,
	}
end

-- 0..1 phase within the period (shared by renderer for sweep/gradient offsets).
function SoulAnimModel.phase(anim, t)
	return (t % anim.period) / anim.period
end

-- flash: two quick rim pulses in the first 20% of the period (Stormcloud lightning).
function SoulAnimModel.flashOn(anim, t)
	local p = SoulAnimModel.phase(anim, t)
	return (p >= 0.00 and p < 0.05) or (p >= 0.10 and p < 0.14)
end

local function hsvToRgb(h, s, v) -- h 0..1
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, r2 = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local map = {
		[0] = { v, r2, p }, [1] = { q, v, p }, [2] = { p, v, r2 },
		[3] = { p, q, v }, [4] = { r2, p, v }, [5] = { v, p, q },
	}
	local c = map[i]
	return { r = c[1] * 255, g = c[2] * 255, b = c[3] * 255 }
end

function SoulAnimModel.colorAt(anim, fill, t)
	if not anim then
		return fill
	end
	local p = SoulAnimModel.phase(anim, t)
	if anim.kind == "osc" then
		local k = 0.5 - 0.5 * math.cos(p * 2 * math.pi) -- fill -> to -> fill
		return lerp(fill, anim.to, k)
	elseif anim.kind == "steps" then
		local current = anim.frames[1].c
		for _, frame in ipairs(anim.frames) do
			if p >= frame.at then current = frame.c end
		end
		return current
	elseif anim.kind == "flicker" then
		-- Two incommensurate sines -> irregular but deterministic 0..1 mix.
		local k = 0.5 + 0.25 * math.sin(p * 2 * math.pi * 3)
			+ 0.25 * math.sin(p * 2 * math.pi * 7 + 1.3)
		return lerp(fill, anim.to, math.clamp(k, 0, 1))
	elseif anim.kind == "hue" then
		return hsvToRgb(p, anim.s, anim.v)
	end
	return fill -- sweep/gradient/flash: flat color stays fill; renderer animates
end

return SoulAnimModel
```

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/soul_anim_model.spec.luau`
Expected: `ALL soul_anim_model tests passed`

- [ ] **Step 3: Commit**

```bash
git add src/shared/SoulAnimModel.luau tests/soul_anim_model.spec.luau
git commit -m "feat(shop): pure SoulAnimModel color animation math"
```

---

### Task 6: Server — Remotes, EconomyService gauntlet, resolved SoulMap

**Files:**
- Modify: `src/shared/Remotes.luau:17-22` (REMOTE_EVENTS list)
- Modify: `src/server/EconomyService.luau`
- Modify: `src/server/ControlManager.luau:26-41`
- Modify: `src/server/init.server.luau`

No lune tests (glue); the decisions are already covered by Tasks 2–5. Verified in the Task 10 Studio pass.

- [ ] **Step 1: Add remotes**

In `REMOTE_EVENTS` append:

```luau
	"ShopRequest", -- client->server (THE FIRST): { action = "buy"|"equip", itemId, kind? } -- a CLAIM, validated server-side (spec §5.2)
	"ShopResult",  -- server->client: { ok, action, itemId, err? }
```

- [ ] **Step 2: EconomyService — gauntlet + debounced save + equip callback**

Add requires: `local ShopModel = require(ReplicatedStorage.Shared.ShopModel)`, `local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)`, remote `local ShopResult = Remotes.get("ShopResult")`.

Add state + helpers after `persisted`:

```luau
local rateStamps = {}   -- [player] = { os.clock() of recent requests }
local saveDebounce = {} -- [player] = token table; newest wins

local onEquipChanged = nil -- injected by init.server (avoids Economy<->Control cycle)
function EconomyService.setEquipChangedCallback(cb)
	onEquipChanged = cb
end

local function withinRate(player)
	local now = os.clock()
	local stamps = rateStamps[player] or {}
	local kept = {}
	for _, s in ipairs(stamps) do
		if now - s < Config.SHOP_RATE_WINDOW then kept[#kept + 1] = s end
	end
	kept[#kept + 1] = now
	rateStamps[player] = kept
	return #kept <= Config.SHOP_RATE_MAX
end

local function scheduleSave(player)
	local token = {}
	saveDebounce[player] = token
	task.delay(Config.SHOP_SAVE_DEBOUNCE, function()
		if saveDebounce[player] == token and profiles[player] then
			saveDebounce[player] = nil
			save(player)
		end
	end)
end
```

Add the gauntlet (spec §5.2 order — every numbered gate, none skipped):

```luau
-- The Soul Shop gauntlet (spec §5.2). `payload` is a CLIENT CLAIM: sanitize
-- shape first, then let the pure ShopModel decide. Malformed/over-rate traffic
-- is dropped silently -- honest clients cannot produce it.
function EconomyService.onShopRequest(player, payload)
	if not withinRate(player) then
		return
	end
	if type(payload) ~= "table" or type(payload.itemId) ~= "string"
		or #payload.itemId > 64
		or (payload.action ~= "buy" and payload.action ~= "equip") then
		return
	end
	local profile = profiles[player]
	if not profile or not persisted[player] then
		ShopResult:FireClient(player, { ok = false, action = payload.action,
			itemId = payload.itemId, err = "profile_unavailable" })
		return
	end
	if payload.action == "buy" then
		local r = ShopModel.validatePurchase(profile, ShopCatalog, Config.SHOP_PRICES, payload.itemId)
		if not r.ok then
			ShopResult:FireClient(player, { ok = false, action = "buy",
				itemId = payload.itemId, err = r.err })
			return
		end
		ShopModel.applyPurchase(profile, r.item, Config.SHOP_PRICES)
		scheduleSave(player)
	else -- equip ("default" allowed; kind then required and must be a real slot)
		local kind = payload.kind
		if payload.itemId == "default"
			and kind ~= "halo_color" and kind ~= "halo_style" and kind ~= "trail" then
			return
		end
		local r = ShopModel.validateEquip(profile, ShopCatalog, payload.itemId, kind)
		if not r.ok then
			ShopResult:FireClient(player, { ok = false, action = "equip",
				itemId = payload.itemId, err = r.err })
			return
		end
		ShopModel.applyEquip(profile, r.kind, payload.itemId)
	end
	ShopResult:FireClient(player, { ok = true, action = payload.action, itemId = payload.itemId })
	pushProfile(player)
	if onEquipChanged then
		onEquipChanged() -- re-broadcast SoulMap with the new resolved look
	end
end
```

Also add cleanup in `onPlayerRemoving` (before dropping the profile): `rateStamps[player] = nil; saveDebounce[player] = nil`.

- [ ] **Step 3: ControlManager — resolved-color SoulMap**

Add requires: `local SoulResolveModel = require(ReplicatedStorage.Shared.SoulResolveModel)`, `local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)`, `local EconomyService = require(script.Parent.EconomyService)` (acyclic: EconomyService does not require ControlManager — the equip callback is injected in init.server).

Replace `broadcastSoulMap`:

```luau
-- Broadcast every controlled body's RESOLVED Soul identity (spec §5.4): the
-- equipped premium color when valid, else the auto-assigned palette color --
-- resolved HERE so every consumer of "player X's color" agrees by construction.
-- Entries also carry equip ids for client-side style/anim/trail rendering.
function ControlManager.broadcastSoulMap()
	local list = {}
	for body, player in pairs(model.controllerOf) do
		local assigned = soulColor[player]
		if assigned then
			local profile = EconomyService.getProfile(player)
			local resolved = SoulResolveModel.resolve(
				profile and profile.equipped or nil, ShopCatalog,
				{ r = math.floor(assigned.R * 255 + 0.5),
				  g = math.floor(assigned.G * 255 + 0.5),
				  b = math.floor(assigned.B * 255 + 0.5) })
			list[#list + 1] = {
				body = body,
				color = Color3.fromRGB(resolved.fill.r, resolved.fill.g, resolved.fill.b),
				colorId = resolved.colorId,
				styleId = resolved.styleId,
				trailId = resolved.trailId,
			}
		end
	end
	SoulMap:FireAllClients(list)
end
```

- [ ] **Step 4: Wire init.server**

After the requires: `local ReplicatedStorage = game:GetService("ReplicatedStorage")`, `local Remotes = require(ReplicatedStorage.Shared.Remotes)`, `local ControlManager = require(script.ControlManager)`. After `EconomyService.start()`:

```luau
EconomyService.setEquipChangedCallback(ControlManager.broadcastSoulMap)
Remotes.get("ShopRequest").OnServerEvent:Connect(EconomyService.onShopRequest)
```

- [ ] **Step 5: Full suite + boot check, commit**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || echo "FAILED: $f"; done` — all pass (glue untested by lune, but requires must not break shared modules).
Studio boot sanity happens in Task 10; commit now:

```bash
git add src/shared/Remotes.luau src/server/EconomyService.luau src/server/ControlManager.luau src/server/init.server.luau
git commit -m "feat(shop): ShopRequest gauntlet + resolved-color SoulMap broadcast (first validated C->S remote)"
```

---

### Task 7: HudZoneModel + HudTheme safe-area layer (banner fix)

**Files:**
- Create: `src/shared/HudZoneModel.luau`
- Test: `tests/hud_zone_model.spec.luau`
- Modify: `src/client/HudTheme.luau` (zones consume the model; placed objects re-place on viewport/inset change)

- [ ] **Step 1: Write the failing test**

```luau
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

-- Zero inset (Studio edit / desktop app): behaves like the old 14px placement.
do
	local z = HudZoneModel.zones({ w = 1920, h = 1080, insetTop = 0 })
	expect(z.top.yOffsetPx >= 14, "no-inset keeps a minimum margin")
	print("zones: zero inset OK")
end

-- All named zones exist with anchors + positions.
do
	local z = HudZoneModel.zones({ w = 1280, h = 720, insetTop = 36 })
	for _, key in ipairs({ "top", "topTimer", "center", "notice", "bottom" }) do
		expect(z[key] and z[key].anchor and z[key].position, "zone " .. key .. " present")
	end
	print("zones: completeness OK")
end

print("ALL hud_zone_model tests passed")
```

- [ ] **Step 2: Run to verify it fails, then implement**

```luau
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
```

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hud_zone_model.spec.luau` → `ALL hud_zone_model tests passed`

- [ ] **Step 3: HudTheme integration**

In `src/client/HudTheme.luau`:

1. Requires at top: `local GuiService = game:GetService("GuiService")`, `local ReplicatedStorage = game:GetService("ReplicatedStorage")`, `local HudZoneModel = require(ReplicatedStorage.Shared.HudZoneModel)`.
2. Replace the static `HudTheme.Zone` table + `placeInZone` with a live registry:

```luau
-- Zones are computed from viewport + Roblox top inset (HudZoneModel) and every
-- placed object is re-placed when either changes -- the safe-area layer (spec §6.3).
local placed = setmetatable({}, { __mode = "k" }) -- [guiObject] = zoneKey

local function currentViewport()
	local cam = workspace.CurrentCamera
	local size = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	return { w = size.X, h = size.Y, insetTop = inset.Y }
end

local function zoneData(zoneKey)
	return HudZoneModel.zones(currentViewport())[zoneKey]
end

function HudTheme.placeInZone(guiObject, zoneKey)
	local z = zoneData(zoneKey)
	guiObject.AnchorPoint = Vector2.new(z.anchor.x, z.anchor.y)
	guiObject.Position = UDim2.new(z.position[1], z.position[2], z.position[3], z.position[4])
	placed[guiObject] = zoneKey
end

local function replaceAll()
	for guiObject, zoneKey in pairs(placed) do
		if guiObject.Parent then
			HudTheme.placeInZone(guiObject, zoneKey)
		end
	end
end

-- Re-place on viewport change; camera can be replaced, so rebind like
-- InputController's viewport handling (no listener stacking).
local viewportConn = nil
local function bindViewport()
	if viewportConn then viewportConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(replaceAll)
	end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewport()
	replaceAll()
end)
bindViewport()
```

3. `HudTheme.applyMaxSize` gains banner awareness — replace with:

```luau
function HudTheme.applyMaxSize(guiObject, capKey)
	local c = Instance.new("UISizeConstraint")
	if capKey == "banner" then
		local cap = HudZoneModel.bannerCap(currentViewport())
		c.MaxSize = Vector2.new(cap.w, cap.h)
		-- Re-cap on viewport change alongside re-placement.
		placedCaps = placedCaps or setmetatable({}, { __mode = "k" })
		placedCaps[c] = true
	else
		c.MaxSize = HudTheme.Cap[capKey]
	end
	c.Parent = guiObject
	return c
end
```

and extend `replaceAll` to refresh caps: iterate `placedCaps` (declare `local placedCaps` beside `placed`) setting `c.MaxSize` from `HudZoneModel.bannerCap(currentViewport())`. Keep `HudTheme.Cap` for the non-banner keys.

- [ ] **Step 4: Verify consumers still compile (grep for stale `HudTheme.Zone` reads)**

Run: `grep -rn "HudTheme.Zone" src/client/`
Expected: no direct table reads remain (only `placeInZone` calls). If any exist, convert them to `placeInZone`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/HudZoneModel.luau tests/hud_zone_model.spec.luau src/client/HudTheme.luau
git commit -m "feat(hud): safe-area zone layer (HudZoneModel) -- banner clears Roblox top menu on mobile"
```

---

### Task 8: SoulStyles + SoulController — the unified halo pipeline + trails

**Files:**
- Create: `src/client/SoulStyles.luau`
- Modify: `src/client/SoulController.luau`

All constructions are data-specified below — no taste decisions left to the implementer. Zero particles anywhere.

- [ ] **Step 1: Create `SoulStyles.luau`**

Module contract:

```luau
--[[
	SoulStyles -- ONE construction + animation pipeline for every Soul halo, free
	Classic included (spec §6.1). Builders return { root } gui trees parented into
	the halo BillboardGui; a single shared Heartbeat animator drives every animated
	element (rotation, ripple, color anims via SoulAnimModel) -- per-frame budget:
	<= 16 color writes + <= 3 property writes per visible halo.

	SoulStyles.build(styleKey, colorItem, isMine) -> handle
	  styleKey: "classic"|"ring"|"pulse"|"orbit"|"eclipse"|"seraph"
	  colorItem: ShopCatalog color item or nil (nil => flat resolved color from
	             SoulMap entry.color; no animation)
	  handle = { gui = BillboardGui, setResolvedColor(Color3), destroy() }
	SoulStyles.start() -- binds the shared animator (idempotent)
--]]
```

Construction table (billboard `Size` = mine 42px / other 24px as today; all
sub-sizes in SCALE of the billboard so both sizes work):

| styleKey | Elements (all Frames + UICorner circle unless noted) |
|---|---|
| `classic` | UnderGlow: scale 1.30, color=luminous, transparency 0.72, ZIndex 1. Core: scale 0.92, color=fill, ZIndex 2. Emphasis UIStroke on Core (thickness 3 if mine else 0; color = `(20,24,31)` when fill luminance > 0.75 else white). Void-type colors (luminous ≠ fill and no anim): + Rim ring: scale 1.0 UIStroke thickness 12% of px size, color=luminous. |
| `ring` | Annulus: scale 1.0, BackgroundTransparency 1, UIStroke thickness = 18% of px size, color=fill. UnderGlow as classic at 1.20. Emphasis stroke on a scale-0.5 invisible center frame (keeps rule uniform). |
| `pulse` | Classic core at 0.80 + Ripple: circle scale 0.80→1.52 (tween via animator, 1.6s loop), UIStroke 3px color=luminous, BackgroundTransparency 1, fades stroke transparency 0.2→1 over the loop. |
| `orbit` | Core: scale 0.70 fill. Carrier: invisible frame scale 1.0 rotated by animator (360°/3s). Two satellites: scale 0.25 circles at carrier x=0 and x=1 (AnchorPoint 0.5), color=luminous. |
| `eclipse` | Disc: scale 1.0 color `(25,16,38)`. Corona: UIStroke on disc, thickness 14% px, color=luminous. OuterGlow: scale 1.34 circle, color=luminous, transparency 0.82, ZIndex 0. |
| `seraph` | Core: scale 0.48 fill. Ripple as pulse but 2.4s. ShardRing: invisible carrier scale 1.0, animator-rotated 360°/6s, UIStroke 2px color=luminous transparency 0.25; three Shards: 0.18-scale squares rotated 45°, color=luminous, at carrier top/bottom-left/bottom-right (positions {0.5,0},{0.07,0.78},{0.93,0.78}). |

Color animation binding (per SoulMap entry with a `colorId` whose catalog item has `anim`):
- `osc`/`flicker`/`steps`/`hue`: animator sets each fill-bound element's `BackgroundColor3` from `SoulAnimModel.colorAt(anim, fill, clock)` (shared clock = `os.clock()` so all clients phase-align to within network skew; acceptable).
- `sweep`/`gradient`: element gets a `UIGradient` (sweep: fill→to→fill rotated 25°; gradient: the 3 stops vertical). Animator writes `gradient.Offset = Vector2.new(SoulAnimModel.phase(anim, clock) * 2 - 1, 0)` (sweep) or `(0, phase*2-1)` (gradient).
- `flash`: rim/corona stroke `Transparency = SoulAnimModel.flashOn(anim, clock) and 0 or 0.65`.

The animator is ONE `RunService.Heartbeat` connection iterating a weak-keyed registry of live handles; a handle with no `gui.Parent` is dropped.

- [ ] **Step 2: Rewrite `SoulController` reconcile to consume the pipeline**

Keep: remotes wiring, `reconcileMyBody`, grace shimmer (untouched). Replace `makeHalo`/`applyEmphasis`/halo bookkeeping:

- `halos[body] = { handle, styleKey, colorId, isMine }`. On each SoulMap `reconcile(list)`: for each entry resolve `styleKey = entry.styleId and ShopCatalog.byId(entry.styleId).styleKey or "classic"`, `colorItem = entry.colorId and ShopCatalog.byId(entry.colorId) or nil`. If the cached halo's `styleKey`/`colorId`/`isMine` differ (or no halo), destroy + `SoulStyles.build` fresh, parent to head as today (BillboardGui `StudsOffsetWorldSpace (0, 2.6, 0)`, `AlwaysOnTop`, size 42/24 by mine). Else `handle.setResolvedColor(entry.color)` (flat-color refresh path for non-animated).
- **Trails:** maintain `trails[body] = { instances = {Trail...}, trailKey, colorId }`. On reconcile, if `entry.trailId` changed: destroy + rebuild. Build per spec table:

| trailKey | Trail instances (attachments on `UpperTorso` or fallback `HumanoidRootPart`, vertical spread ±0.5 studs unless noted) |
|---|---|
| `wisp` | 1: Width 0.35 (attachment spread 0.35), Lifetime 0.45, Transparency 0.35→1 |
| `stream` | 1: spread 1.4, Lifetime 0.8, Transparency 0.25→1 |
| `sparkline` | 1: spread 0.9, Lifetime 0.6, WidthScale NumberSequence {1,0.15,1,0.15,1}, Transparency 0.3→1 |
| `comet` | 2: core spread 0.35, Lifetime 1.0, Color = 75% white-mixed luminous; sheath spread 1.8, Lifetime 1.0, Transparency 0.55→1 |
| `meteor` | 2: spreads 0.55 each, offset ±0.8 studs horizontally (shoulder line), Lifetime 1.2; animator alternates their Transparency base 0.25↔0.7 on a 1.1s cycle |

  All trails: `Color = ColorSequence.new(luminous)` (from the entry's colorItem via `ShopCatalog.luminousOf`, else `entry.color`), `FaceCamera = true`, `LightEmission = 0.6`. On swap the reconcile already runs (SoulMap re-broadcast) → rebuild/recolor happens by the same diffing.
- Bodies leaving the map: destroy halo handle AND trail instances (extend the existing cleanup loop).
- `SoulController.start()` calls `SoulStyles.start()` first.

- [ ] **Step 3: Verify the full suite still passes + commit**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || echo "FAILED: $f"; done`

```bash
git add src/client/SoulStyles.luau src/client/SoulController.luau
git commit -m "feat(soul): unified SoulStyles halo pipeline (Classic upgrade) + soul trails"
```

---

### Task 9: ShopLayoutModel + ClientShopHud

**Files:**
- Create: `src/shared/ShopLayoutModel.luau`
- Test: `tests/shop_layout_model.spec.luau`
- Create: `src/client/ClientShopHud.luau`
- Modify: `src/client/init.client.luau` (require + `ClientShopHud.start()` after `ClientEconomyHud.start()`)

- [ ] **Step 1: Write the failing layout test**

```luau
local ShopLayoutModel = require("../src/shared/ShopLayoutModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

-- Desktop 1920x1080: side panel, clamped width, 2 columns.
do
	local L = ShopLayoutModel.layout({ w = 1920, h = 1080, insetTop = 36 })
	expect(L.mode == "panel", "desktop mode")
	expect(L.panelW >= 330 and L.panelW <= 460, "panel width clamped, got " .. L.panelW)
	expect(L.columns == 2, "2 columns")
	expect(L.panelTopPx >= 36 + 10, "panel clears inset")
	print("layout: desktop OK")
end

-- Tablet landscape 1180x820: still a panel.
do
	local L = ShopLayoutModel.layout({ w = 1180, h = 820, insetTop = 36 })
	expect(L.mode == "panel", "tablet mode")
	expect(L.panelW <= 1180 * 0.55, "panel under sheet threshold")
	print("layout: tablet OK")
end

-- Phone landscape 844x390: sheet mode when panel would exceed 55% width.
do
	local L = ShopLayoutModel.layout({ w = 640, h = 360, insetTop = 58 })
	expect(L.mode == "sheet", "small phone -> sheet")
	expect(L.columns >= 2, "sheet keeps >= 2 columns")
	print("layout: phone sheet OK")
end

-- Touch targets never dip below 44px.
do
	for _, vp in ipairs({ { w = 1920, h = 1080, insetTop = 36 }, { w = 844, h = 390, insetTop = 58 },
	                      { w = 640, h = 360, insetTop = 58 } }) do
		local L = ShopLayoutModel.layout(vp)
		expect(L.cardH >= 44, "card height >= 44 at " .. vp.w .. "x" .. vp.h)
		expect(L.tabH >= 32, "tab height reasonable")
	end
	print("layout: touch floor OK")
end

print("ALL shop_layout_model tests passed")
```

- [ ] **Step 2: Run to verify it fails, then implement**

```luau
--[[
	ShopLayoutModel -- PURE responsive shop geometry (spec §6.2): viewport + inset
	in, panel/sheet mode + pixel dimensions out. Same pattern as TouchJumpLayout.
	Modes: "panel" (right-anchored side panel; world visible) and "sheet"
	(full-height takeover when a usable panel would cover > 55% of width).
--]]

local ShopLayoutModel = {}

local PANEL_FRACTION = 0.38
local PANEL_MIN, PANEL_MAX = 330, 460
local SHEET_THRESHOLD = 0.55
local MARGIN = 10
local CARD_MIN = 44

function ShopLayoutModel.layout(vp)
	local panelW = math.clamp(math.floor(vp.w * PANEL_FRACTION), PANEL_MIN, PANEL_MAX)
	local mode = (panelW / vp.w) > SHEET_THRESHOLD and "sheet" or "panel"
	local safeTop = (vp.insetTop or 0) + MARGIN
	local w = mode == "sheet" and (vp.w - MARGIN * 2) or panelW
	local innerW = w - 26 -- paddings
	local columns = math.max(2, math.floor(innerW / 150))
	local cardW = math.floor((innerW - (columns - 1) * 8) / columns)
	local cardH = math.max(CARD_MIN, math.floor(cardW * 0.82))
	local scale = math.clamp(vp.h / 1080, 0.85, 1.0)
	return {
		mode = mode,
		panelW = w,
		panelTopPx = safeTop,
		panelBottomMarginPx = MARGIN,
		columns = columns,
		cardW = cardW,
		cardH = cardH,
		tabH = math.max(32, math.floor(34 * scale)),
		headerH = math.max(40, math.floor(46 * scale)),
		typeScale = scale,
	}
end

return ShopLayoutModel
```

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/shop_layout_model.spec.luau` → pass. Commit:

```bash
git add src/shared/ShopLayoutModel.luau tests/shop_layout_model.spec.luau
git commit -m "feat(shop): pure responsive ShopLayoutModel"
```

- [ ] **Step 3: Build `ClientShopHud.luau`**

Structure (HudTheme language throughout; every size from `ShopLayoutModel.layout(currentViewport())`, re-laid on viewport change exactly like HudTheme's `replaceAll`):

- **ScreenGui** `ShopHud`, `IgnoreGuiInset = true`, `DisplayOrder = HudTheme.DisplayOrder.bookend - 1`, `ResetOnSpawn = false`.
- **Toggle button**: 56px circle (44px floor), bottom-right above the economy HUD corner, coin-purse glyph drawn as two stacked circles (gold `(255,201,77)` + dark slot), `HudTheme.styleText` label "SHOP". Visibility = access rule: track `RoundStateChanged` phase + `EliminationEvent` for the local player; visible when `phase ~= "Active"` or local player eliminated. Hidden when panel open.
- **Panel/sheet** per layout mode: dark `HudTheme.Color.panelDark` at 0.06 transparency, `HudTheme.Radius`, white 2.5px UIStroke. Header row: "SOUL SHOP" (FredokaOne) + coin chip (live `ProfileUpdated` totals; gold text). Tab row: 3 pill buttons (COLORS/STYLES/TRAILS) — active = cyan `(57,214,224)` bg / dark text. Content: `ScrollingFrame` + `UIGridLayout` (`CellSize` from layout cardW/cardH, re-set on re-layout).
- **Cards** built from `ShopCatalog.items` filtered by tab, sorted rarity-order then price. Each card: rarity chip (colors from spec §6.2), live preview — for colors: a 20px `SoulStyles.build("classic", item, false)` billboard content re-parented as plain Frames (build the same construction directly with Frames — expose `SoulStyles.buildPreview(item, px)` returning a Frame for exactly this), for styles: `SoulStyles.buildPreview({ styleKey = it.styleKey }, px)` in identity cyan, for trails: 3-frame horizontal fading ribbon approximation animated by the shared animator. State row: price (gold) / "OWNED → EQUIP" / "EQUIPPED" (from latest `ProfileUpdated` + `ShopResult` events; the client keeps a local `owned`/`equipped` mirror updated from ShopResult successes and full refresh on ProfileUpdated if it carries them — extend `viewOf` in EconomyService to include `ownedItems` and `equipped` so the client mirror is authoritative).
- **Buy flow**: tap card → expands (grid cell spans full row via LayoutOrder + sized frame) showing name, rarity, price, BUY button (gold, `3px` bottom shadow). Tap BUY → `ShopRequest:FireServer({ action = "buy", itemId = it.id })`, button enters 0.5s cooldown. On `ShopResult`: ok+buy → collapse card, tick the coin chip down over 0.4s, `HudTheme.popIn` the card; `insufficient_coins` → chip shake (5 alternating ±6px position tweens, 0.3s) + red flash; `profile_unavailable` → disable shop button + hint label "Profile loading…"; equip flows likewise (`EQUIP` → equip request → EQUIPPED state on ok).
- **Default rows**: each tab's grid starts with a "Default" card (free look, equip = `{ action = "equip", itemId = "default", kind = <tab kind> }`).
- Escape/close: X button top-right of panel + toggle button reopens.

- [ ] **Step 4: EconomyService `viewOf` extension (client mirror)**

In `EconomyService.viewOf` add `ownedItems = profile.ownedItems, equipped = profile.equipped` to the returned table. (ProfileUpdated consumers ignore unknown fields — ClientEconomyHud reads only coins/level/xp.)

- [ ] **Step 5: Wire init.client, run suite, commit**

`init.client.luau`: `local ClientShopHud = require(script.ClientShopHud)` + `ClientShopHud.start()` after `ClientEconomyHud.start()`.

Run: full lune suite → all pass.

```bash
git add src/client/ClientShopHud.luau src/client/init.client.luau src/server/EconomyService.luau
git commit -m "feat(shop): responsive ClientShopHud (panel/sheet modes, live previews, two-tap buy)"
```

---

### Task 10: Studio verification pass (MCP)

**Files:** none (verification); fixes discovered here become micro-commits.

- [ ] **Step 1: Rojo sync + boot.** Confirm `rojo serve` is up (port 34872 in use = already running; verify a changed script via `script_grep` before asking the user to reconnect). Studio Play (solo, `SOLO_TEST_MODE=true` pin active): console clean of errors; `[BSR] Server ready` printed.
- [ ] **Step 2: Shop flow (server `execute_luau`)**: grant test coins — get the local player's profile via `EconomyService` is NOT reachable from the probe require cache (memory: probe require cache is separate!) — instead fire the flow end-to-end from the CLIENT context or via attribute-driven dev hook: add a temporary command `game.Players:GetPlayers()[1]` + directly invoke the remote from a client `execute_luau` context; verify via `ShopResult` client print + coin chip change. Buy `color_void`, `style_eclipse`, `trail_comet`; equip each; confirm halo/trail change on the lobby body via `screen_capture` (camera at the lobby disc).
- [ ] **Step 3: Persistence**: stop Play, re-Play, confirm equipped look reappears (profile round-trip through ProfileStore).
- [ ] **Step 4: Visual pass** (memory: `screen_capture` shows client view during Play; pass explicit camera coords; captures can catch black round-transition fades — retry): Classic-vs-old comparison shot, each style at 42px + 24px on the dusk sky, each animated color (two captures ≥1s apart to prove motion), each trail while walking (drive via `character_navigation` on the body if available, else user-driven).
- [ ] **Step 5: Responsive + banner**: in Studio, resize the viewport through desktop/tablet/phone profiles (or device emulator manually — ask the user to flip if MCP can't): shop panel↔sheet transition, 44px targets, banner clear of the (emulated) top inset at every profile. Screenshot each.
- [ ] **Step 6: Record results** in `docs/smoke-tests/2026-07-16-soul-shop-slice1-smoke-test.md` (pattern: existing smoke docs) — checklist of what passed solo + what's deferred to the 2-client session (other-client halo visibility, rate-limit under spam, swap-recolor timing).
- [ ] **Step 7: Commit smoke doc.**

```bash
git add docs/smoke-tests/2026-07-16-soul-shop-slice1-smoke-test.md
git commit -m "test(shop): slice-1 solo Studio verification record"
```

---

### Task 11: CHANGELOG + docs closeout

**Files:**
- Modify: `CHANGELOG.md` (new dated entry, pattern of 2026-07-14)
- Modify: `docs/body-swap-royale-gdd.md` §8 (one-line pointer: first coin sink shipped, slice-1 catalog)
- Modify: `docs/specs/2026-07-16-soul-shop-slice1-design.md` (only if implementation diverged — record deltas in a §13 amendments block)

- [ ] **Step 1: CHANGELOG entry** summarizing: first coin sink; 25-item catalog; first validated C→S remote (decision record pointer); resolved-color SoulMap; SoulStyles unified pipeline + Classic upgrade; trails; responsive shop; HUD safe-area layer + banner fix; PROFILE_VERSION 2; new lune suites count.
- [ ] **Step 2: GDD §8 note** under Currency Systems: "First coin sink shipped 2026-07-16 (Soul Shop slice 1 — see spec)."
- [ ] **Step 3: Full suite one last time; commit.**

```bash
git add CHANGELOG.md docs/body-swap-royale-gdd.md
git commit -m "docs(shop): CHANGELOG + GDD pointer for Soul Shop slice 1"
```

---

## Self-review (run before execution)

1. **Spec coverage:** §4.1→T2, §4.2→T3, §4.3→T4, §5.1–5.2→T6, §5.3–5.4→T4/T6, §6.1→T5/T8, §6.2→T9, §6.3→T7, §7→T2, §8→T4(knobs), §9→T3/T4/T6 tests, §10→every task's test steps + T10, §12→branch/commit discipline. No gaps.
2. **Placeholders:** none — every code step has complete code or an exact construction table.
3. **Type consistency:** `ShopModel.validatePurchase(profile, catalog, prices, itemId)` matches T6's call; `SoulResolveModel.resolve(equipped, catalog, assignedFill)` matches T6; `ShopCatalog.byId`/`luminousOf` used in T6/T8/T9 as defined in T2; `HudZoneModel.zones/bannerCap` match T7's HudTheme usage; `ShopLayoutModel.layout` fields match T9's consumption.
