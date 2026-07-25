--[[
	ClientShopHud -- the responsive Soul Shop UI (spec §6.2). Right-anchored side
	panel on wide viewports (world + your body stay visible so equips render live),
	full-height sheet on small ones. All geometry comes from the pure ShopLayoutModel;
	the only pixel literals here are spec'd style constants (rarity chips, colors,
	touch floors). HudTheme language throughout (FredokaOne headings, panelDark,
	white strokes, Radius). Card previews reuse the SAME SoulStyles constructions the
	world halos use -- the preview is the product.
	Location: StarterPlayerScripts/Client/ClientShopHud  (ModuleScript)

	Access rule (spec decision #3): the toggle is visible only when the local player
	is NOT alive in an active round -- phase ~= "Active", or Active-but-eliminated.
	Tracked from RoundStateChanged.phase + EliminationEvent (self), mirroring
	ClientRoundHud's field usage.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local ShopModel = require(Shared:WaitForChild("ShopModel"))
local ShopLayoutModel = require(Shared:WaitForChild("ShopLayoutModel"))
local TouchJumpLayout = require(Shared:WaitForChild("TouchJumpLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))
local SoulStyles = require(script.Parent:WaitForChild("SoulStyles"))

local ShopRequest = Remotes.get("ShopRequest")
local ShopResult = Remotes.get("ShopResult")
local ProfileUpdated = Remotes.get("ProfileUpdated")
local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SoulMap = Remotes.get("SoulMap") -- tracks the local player's resolved soul color (#4 visual)

local ClientShopHud = {}
local player = Players.LocalPlayer

-- ===== style constants (spec §6.2 / §7) ================================
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

-- Pure thousands separator: 7426 -> "7,426" (copied from ClientEconomyHud so the shop
-- reads the balance in the SAME format as the readout). Integer-floored; sign preserved.
local function withCommas(n)
	n = math.floor(n or 0)
	local neg = n < 0
	local s = tostring(math.abs(n))
	local out, count = "", 0
	for i = #s, 1, -1 do
		out = s:sub(i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	return (neg and "-" or "") .. out
end

local CYAN = rgb(57, 214, 224)         -- active tab / equipped accent (free Soul cyan)
local GOLD = rgb(255, 201, 77)         -- coins + price + BUY
local TAB_OFF_BG = rgb(35, 41, 54)     -- #232936
local TAB_OFF_TEXT = rgb(136, 145, 163) -- #8891a3
local CARD_BG = rgb(26, 31, 43)
local RED = rgb(240, 88, 78)

local RARITY_ORDER = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
local RARITY_COLOR = {
	common = rgb(184, 192, 205),
	uncommon = rgb(94, 209, 122),
	rare = rgb(77, 166, 255),
	epic = rgb(176, 108, 240),
	legendary = rgb(255, 201, 77),
}
local FREE_TIER = rgb(139, 147, 166) -- neutral gray for the Default card's "FREE" pill (spec §3)
local PILL_BG = rgb(10, 13, 20)      -- dark translucent capsule behind the corner tier pill (spec §3)

-- ===== interaction + component palette (spec §6.2 polish pass) ==========
local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- close X (drawn bars, not a glyph)
local CLOSE_BG = TAB_OFF_BG
local CLOSE_BG_HOVER = rgb(232, 68, 58)
local CLOSE_BG_PRESS = rgb(205, 52, 44)
local CLOSE_BAR = rgb(231, 236, 245)
local CLOSE_BAR_HOT = rgb(255, 255, 255)

-- BUY (premium gold, raised key)
local BUY_GRAD = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 224, 138)),
	ColorSequenceKeypoint.new(0.5, rgb(255, 201, 77)),
	ColorSequenceKeypoint.new(1, rgb(234, 169, 42)),
})
local BUY_TEXT = rgb(58, 38, 0)
local BUY_HIGHLIGHT = rgb(255, 245, 210)
local BUY_SHADOW = rgb(168, 126, 30)

-- EQUIP (solid secondary key)
local EQUIP_BG = rgb(44, 51, 66)
local EQUIP_BG_HOVER = rgb(55, 64, 86)
local EQUIP_SHADOW = rgb(26, 31, 41)

-- tabs
local TAB_ACTIVE_A = rgb(72, 226, 236)
local TAB_ACTIVE_B = rgb(57, 214, 224)
local TAB_ACTIVE_TEXT = rgb(6, 39, 43)
local TAB_ACTIVE_SHADOW = rgb(31, 154, 162)
local TAB_HOVER_BG = rgb(44, 52, 68)
local TAB_HOVER_TEXT = rgb(194, 203, 219)
local TAB_SHADOW_OFF = rgb(22, 26, 35)

-- toggle
local TOGGLE_GRAD_A = rgb(27, 33, 48)
local TOGGLE_GRAD_B = rgb(17, 22, 31)

local TABS = {
	{ kind = "halo_color", label = "COLORS" },
	{ kind = "halo_style", label = "STYLES" },
	{ kind = "trail", label = "TRAILS" },
}

local PAD = 10          -- panel content inset
local GAP = 8           -- vertical gap between header/tabs/grid + grid cell padding
local CARD_RADIUS = UDim.new(0, 12)
local CAP_TITLE, CAP_BODY = 28, 16
local BUY_DEBOUNCE = 0.5

-- ===== live state ======================================================
local owned = {}                                    -- [itemId] = true
local equipped = { halo_color = nil, halo_style = nil, trail = nil }
local coins = 0                                       -- authoritative (optimistic on buy) balance mirror
local displayedCoins = 0                              -- the value CURRENTLY shown on the chip; the tween animates FROM this
local coinsAnimToken = nil                           -- cancels a running coin count anim
local profileOk = true                               -- false after profile_unavailable, until next ProfileUpdated
local activeTab = "halo_color"
local panelOpen = false
local phase = nil                                    -- from RoundStateChanged
local eliminated = false                             -- self, this round
local expandedId = nil                               -- itemId currently expanded to BUY, or nil
local built = false                                  -- true once build() has created every UI ref
local buildGen = 0                                   -- bumped each rebuildCards; guards the staggered reveal
local localSoulColor = rgb(57, 214, 224)             -- local player's resolved soul color (SoulMap); identity cyan until first broadcast

-- built once
local gui, toggleBtn, panel, closeBtn, titleLabel, coinChip, coinChipCount, coinChipBase, coinChipMed
local tabsRow, headerRow, scroll, grid, hintBox
local tabPills = {}                                  -- [kind] = { pill, label }
local textCaps = {}                                  -- { {constraint, cap} } re-scaled on relayout
local currentCards = {}                              -- array of card tables for the active tab
local cardsById = {}                                 -- [itemId] = card table
local L                                               -- latest layout

-- ===== small helpers ===================================================
local function currentViewport()
	local cam = workspace.CurrentCamera
	local size = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return { w = size.X, h = size.Y, insetTop = GuiService:GetGuiInset().Y }
end

-- Register a text cap so relayout can re-scale it by the live typeScale.
local function capText(label, cap)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = math.max(10, math.floor(cap * (L and L.typeScale or 1)))
	c.Parent = label
	textCaps[#textCaps + 1] = { c = c, cap = cap }
	return c
end

local function eligible()
	return phase ~= "Active" or eliminated
end

local function tweenTo(obj, props)
	TweenService:Create(obj, TWEEN_FAST, props):Play()
end

-- Wire consistent hover (desktop) + press (desktop AND touch) feedback onto `btn`.
-- opts = { hover=fn?, leave=fn?, press=fn?, release=fn? }.
--   * hover/leave run on MouseEnter/MouseLeave -- desktop only; a harmless no-op on
--     touch (those signals just don't fire there).
--   * press/release run on MouseButton1Down/Up, which Roblox ALSO fires for touch taps
--     on a GuiButton -- so one code path covers mouse and touch. We deliberately do NOT
--     also listen to InputBegan/InputEnded, which would double-fire on touch.
--   * A `pressed` flag guards re-entry (no double press/release), and MouseLeave
--     releases a still-held press before running `leave`, so a press dragged off the
--     button resets cleanly instead of sticking.
-- All connections live on `btn`; when it is Destroyed (cards rebuild on tab switch)
-- they die with it. `pressed` is per-call closure state, so nothing leaks module-level.
local function wireInteraction(btn, opts)
	local pressed = false
	if opts.hover then
		btn.MouseEnter:Connect(opts.hover)
	end
	btn.MouseButton1Down:Connect(function()
		if pressed then return end
		pressed = true
		if opts.press then opts.press() end
	end)
	btn.MouseButton1Up:Connect(function()
		if not pressed then return end
		pressed = false
		if opts.release then opts.release() end
	end)
	btn.MouseLeave:Connect(function()
		if pressed then
			pressed = false
			if opts.release then opts.release() end
		end
		if opts.leave then opts.leave() end
	end)
end

-- ===== coin chip =======================================================
-- The single entry point that writes the chip: records what's on screen so the
-- tween always animates FROM the displayed value, not from the (already-decremented)
-- balance mirror.
local function setCoinText(n)
	displayedCoins = math.max(0, math.floor(n + 0.5))
	coinChipCount.Text = withCommas(displayedCoins) -- thousands separator, matching the balance readout (§4)
end

-- Tick the displayed coin count from the value CURRENTLY on screen to `target`
-- (~0.4s), so a purchase reads as spending rather than a silent number swap. Both
-- the optimistic buy result and the authoritative ProfileUpdated route through here,
-- so the shared token makes the last writer win to a consistent target (no fight).
local function animateCoinsTo(target)
	local token = {}
	coinsAnimToken = token
	local from = displayedCoins
	task.spawn(function()
		local t = 0
		local DUR = 0.4
		while t < DUR do
			if coinsAnimToken ~= token then return end
			t = math.min(DUR, t + RunService.Heartbeat:Wait())
			setCoinText(from + (target - from) * (t / DUR))
		end
		if coinsAnimToken == token then
			setCoinText(target)
		end
	end)
end

local function shakeCoinChip()
	-- +/-6px, 5 alternations over 0.3s, then a brief red flash on the chip.
	task.spawn(function()
		local steps = { 6, -6, 6, -6, 0 }
		for _, dx in ipairs(steps) do
			coinChip.Position = coinChipBase + UDim2.fromOffset(dx, 0)
			task.wait(0.3 / #steps)
		end
		coinChip.Position = coinChipBase
	end)
	local base = coinChip.BackgroundColor3
	coinChip.BackgroundColor3 = RED
	TweenService:Create(coinChip, TweenInfo.new(0.35), { BackgroundColor3 = base }):Play()
end

-- ===== previews ========================================================
-- Trails have no SoulStyles.buildPreview -- a cheap static 3-frame gradient ribbon
-- mock in the item's rarity color reads as "a trail" without an animator handle.
local function buildTrailRibbon(item, px)
	local root = Instance.new("Frame")
	root.Size = UDim2.fromOffset(px, px)
	root.BackgroundTransparency = 1
	local tint = RARITY_COLOR[item.rarity] or CYAN
	for i = 1, 3 do
		local ribbon = Instance.new("Frame")
		ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
		ribbon.Position = UDim2.fromScale(0.5, 0.3 + (i - 1) * 0.2)
		ribbon.Size = UDim2.fromScale(0.92, 0.16)
		ribbon.BackgroundColor3 = Color3.new(1, 1, 1)
		ribbon.BorderSizePixel = 0
		ribbon.ZIndex = 3
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = ribbon
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, tint),
			ColorSequenceKeypoint.new(1, tint),
		})
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2 + (i - 1) * 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		grad.Parent = ribbon
		ribbon.Parent = root
	end
	return root
end

-- The SHARED gold coin token (spec §4): HudTheme.makeCoinMedallion, re-parented at a
-- given ZIndex. Under Sibling ZIndexBehavior the facet must ride ABOVE the disc, so we
-- bump both together (makeCoinMedallion pins the facet at disc+1 for the default ZIndex).
local function coinToken(px, z)
	local med = HudTheme.makeCoinMedallion(px)
	med.ZIndex = z
	local facet = med:FindFirstChild("Facet")
	if facet then
		facet.ZIndex = z + 1
	end
	return med
end

-- Default TRAILS card (spec §7, Option A): a "no trail" mock -- a faint dashed line +
-- a dim runner dot. Deliberately NOT a Soul halo, so it reads as "trail off".
local function buildNoTrail(px)
	local root = Instance.new("Frame")
	root.Size = UDim2.fromOffset(px, px)
	root.BackgroundTransparency = 1
	local dashes, dashW, gap = 4, 0.13, 0.08
	local total = dashes * dashW + (dashes - 1) * gap
	local startX = 0.5 - total / 2
	for i = 1, dashes do
		local dash = Instance.new("Frame")
		dash.AnchorPoint = Vector2.new(0, 0.5)
		dash.Position = UDim2.fromScale(startX + (i - 1) * (dashW + gap), 0.5)
		dash.Size = UDim2.fromScale(dashW, 0.05)
		dash.BackgroundColor3 = rgb(139, 147, 166)
		dash.BackgroundTransparency = 0.4
		dash.BorderSizePixel = 0
		dash.ZIndex = 3
		local dc = Instance.new("UICorner")
		dc.CornerRadius = UDim.new(1, 0)
		dc.Parent = dash
		dash.Parent = root
	end
	-- dim gray runner circle at the trailing (left) end of the ghosted wake
	local runner = Instance.new("Frame")
	runner.AnchorPoint = Vector2.new(0.5, 0.5)
	runner.Position = UDim2.fromScale(startX, 0.5)
	runner.Size = UDim2.fromScale(0.2, 0.2)
	runner.BackgroundColor3 = rgb(58, 65, 80)
	runner.BorderSizePixel = 0
	runner.ZIndex = 4
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = runner
	runner.Parent = root
	return root
end

-- The player's CURRENT resolved halo COLOR spec (spec §6): the equipped halo_color item's
-- spec, else a flat spec from the SoulMap-tracked identity color. Shape = what SoulStyles
-- consumes: { fill, luminous, fillRgb, luminousRgb, anim? }.
local function currentColorSpec()
	local id = equipped.halo_color
	if id then
		local item = ShopCatalog.byId(id)
		if item and item.kind == "halo_color" then
			local lum = ShopCatalog.luminousOf(item)
			return {
				fill = Color3.fromRGB(item.fill.r, item.fill.g, item.fill.b),
				luminous = Color3.fromRGB(lum.r, lum.g, lum.b),
				fillRgb = item.fill,
				luminousRgb = lum,
				anim = item.anim,
			}
		end
	end
	local c = localSoulColor
	local rgbTab = { r = c.R * 255, g = c.G * 255, b = c.B * 255 }
	return { fill = c, luminous = c, fillRgb = rgbTab, luminousRgb = rgbTab, anim = nil }
end

-- The player's CURRENT equipped style FRAME key (spec §6), or nil for classic.
local function currentStyleKey()
	local id = equipped.halo_style
	if id then
		local item = ShopCatalog.byId(id)
		return item and item.styleKey or nil
	end
	return nil
end

-- Build a card preview as the RESOLVED COMPOSITE (spec §6): the item shown exactly as it
-- would look on the avatar -- color cards composed with the equipped STYLE, style cards
-- composed with the equipped COLOR, so an equipped card matches the on-body halo. Trails
-- keep their static ribbon mock; the Default TRAILS card is the "no trail" mock (§7).
-- Cleanup contract unchanged: SoulStyles.buildPreview returns the animator root Frame --
-- destroying the card subtree makes the shared animator drop the handle next Heartbeat.
local function buildCardPreview(item, isDefault, px)
	if isDefault then
		if activeTab == "trail" then
			return buildNoTrail(px) -- (#7) "no trail" mock, not a halo
		elseif activeTab == "halo_style" then
			-- classic style, in the player's CURRENT color
			return SoulStyles.buildPreview({ kind = "halo_style", styleKey = "classic" }, px, { colorSpec = currentColorSpec() })
		else
			-- free assigned color, composed with the equipped STYLE
			local c = localSoulColor
			local rgbTab = { r = c.R * 255, g = c.G * 255, b = c.B * 255 }
			return SoulStyles.buildPreview({ kind = "halo_color", fill = rgbTab, luminous = rgbTab }, px, { styleKey = currentStyleKey() })
		end
	end
	if item.kind == "trail" then
		return buildTrailRibbon(item, px)
	elseif item.kind == "halo_color" then
		return SoulStyles.buildPreview(item, px, { styleKey = currentStyleKey() }) -- this color x equipped style
	elseif item.kind == "halo_style" then
		return SoulStyles.buildPreview(item, px, { colorSpec = currentColorSpec() }) -- this style x current color
	end
	return SoulStyles.buildPreview(item, px)
end

-- ===== card ============================================================
local function tabKind()
	return activeTab
end

-- state for a card: "equipped" | "owned" | "buyable"
local function cardStateOf(item, isDefault)
	if isDefault then
		return equipped[tabKind()] == nil and "equipped" or "owned"
	end
	if equipped[item.kind] == item.id then
		return "equipped"
	end
	if owned[item.id] then
		return "owned"
	end
	return "buyable"
end

local function fireEquip(itemId, kind)
	ShopRequest:FireServer({ action = "equip", itemId = itemId, kind = kind })
end

local function fireBuy(itemId)
	ShopRequest:FireServer({ action = "buy", itemId = itemId })
end

local function collapseExpanded()
	local prev = expandedId
	expandedId = nil
	if prev and cardsById[prev] then
		cardsById[prev].refresh()
	end
end

-- Recompute every visible card's state row + glow (cheap; no rebuild, previews kept).
local function refreshCardStates()
	for _, card in ipairs(currentCards) do
		card.refresh()
	end
end

local function makeCard(item, isDefault, order)
	local id = isDefault and "default" or item.id
	local name = isDefault and "Default" or item.name

	local root = Instance.new("TextButton")
	root.Name = "Card_" .. id
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundColor3 = CARD_BG
	root.BackgroundTransparency = 0.05
	root.BorderSizePixel = 0
	root.LayoutOrder = order
	root.ZIndex = 2
	root.Size = UDim2.fromOffset(L.cardW, L.cardH)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = CARD_RADIUS
	corner.Parent = root
	local glow = Instance.new("UIStroke")
	glow.Thickness = 1.5
	glow.Color = rgb(60, 68, 84)
	glow.Transparency = 0.2
	glow.Parent = root

	-- tier presentation (spec §2/§3): NO top accent strip. A clean top-LEFT corner pill --
	-- a small tier-colored dot + the rarity WORD in a dark translucent capsule (the Default
	-- card gets a neutral gray "FREE"). The equipped read stays the surrounding cyan border
	-- (`glow`), so tier and equipped state never fight.
	local rarity = (not isDefault) and item.rarity or nil
	local isLegendary = rarity == "legendary"
	local tierColor = (rarity and RARITY_COLOR[rarity]) or FREE_TIER
	local tierWord = rarity and string.upper(rarity) or "FREE"

	local pillH = math.max(15, math.floor(L.cardH * 0.15))
	local pillTextSize = math.clamp(math.floor(pillH * 0.66), 9, 13)

	local tierPill = Instance.new("Frame")
	tierPill.Name = "TierPill"
	tierPill.AnchorPoint = Vector2.new(0, 0)
	tierPill.Position = UDim2.fromOffset(8, 8)
	tierPill.Size = UDim2.fromOffset(0, pillH)
	tierPill.AutomaticSize = Enum.AutomaticSize.X -- hug the dot + word
	tierPill.BackgroundColor3 = PILL_BG
	tierPill.BackgroundTransparency = 0.3
	tierPill.BorderSizePixel = 0
	tierPill.ZIndex = 5 -- above the preview
	local tpC = Instance.new("UICorner")
	tpC.CornerRadius = UDim.new(0, 8)
	tpC.Parent = tierPill
	local tpPad = Instance.new("UIPadding")
	tpPad.PaddingLeft = UDim.new(0, 6)
	tpPad.PaddingRight = UDim.new(0, 8)
	tpPad.Parent = tierPill
	local tpList = Instance.new("UIListLayout")
	tpList.FillDirection = Enum.FillDirection.Horizontal
	tpList.VerticalAlignment = Enum.VerticalAlignment.Center
	tpList.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tpList.Padding = UDim.new(0, 5)
	tpList.SortOrder = Enum.SortOrder.LayoutOrder
	tpList.Parent = tierPill
	if isLegendary then
		-- legendary flourish: a faint gold rim on the (still dark, consistent) capsule
		local legRim = Instance.new("UIStroke")
		legRim.Color = GOLD
		legRim.Transparency = 0.35
		legRim.Thickness = 1
		legRim.Parent = tierPill
	end

	local tierDot = Instance.new("Frame")
	tierDot.Name = "Dot"
	tierDot.LayoutOrder = 1
	tierDot.Size = UDim2.fromOffset(6, 6)
	tierDot.BackgroundColor3 = tierColor
	tierDot.BorderSizePixel = 0
	tierDot.ZIndex = 6
	local tdC = Instance.new("UICorner")
	tdC.CornerRadius = UDim.new(0.5, 0)
	tdC.Parent = tierDot
	local tdGlow = Instance.new("UIStroke") -- faint tier-colored glow
	tdGlow.Color = tierColor
	tdGlow.Transparency = 0.4
	tdGlow.Thickness = 1
	tdGlow.Parent = tierDot
	tierDot.Parent = tierPill

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "TierWord"
	tierLabel.LayoutOrder = 2
	tierLabel.AutomaticSize = Enum.AutomaticSize.X
	tierLabel.Size = UDim2.fromOffset(0, pillH)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = tierWord
	tierLabel.Font = HudTheme.Font.heading
	tierLabel.TextColor3 = tierColor
	tierLabel.TextSize = pillTextSize
	tierLabel.TextStrokeTransparency = 1
	tierLabel.ZIndex = 6
	tierLabel.Parent = tierPill
	tierPill.Parent = root

	-- sizing for the shared coin token (spec §4): mini medallion for prices, and a fixed
	-- button/price text size so the "[coin] 900" rows lay out crisply next to the token.
	local price = isDefault and 0 or ShopModel.priceOf(item, Config.SHOP_PRICES)
	local miniMed = math.clamp(math.floor(L.cardH * 0.12), 12, 16)
	local btnTextSize = math.clamp(math.floor(L.cardH * 0.14), 12, 16)

	-- preview (centered) -- the RESOLVED composite so an equipped card matches the on-body halo
	local previewPx = math.max(20, math.floor(L.cardH * 0.4))
	local preview = buildCardPreview(item, isDefault, previewPx)
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.Position = UDim2.fromScale(0.5, 0.4)
	preview.ZIndex = 3
	preview.Parent = root

	-- name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = UDim2.fromScale(0.5, 0.72)
	nameLabel.Size = UDim2.fromScale(0.92, 0.18)
	nameLabel.Text = name
	nameLabel.ZIndex = 4
	HudTheme.styleText(nameLabel, "body")
	capText(nameLabel, CAP_BODY)
	nameLabel.Parent = root

	-- state row: a non-interactive label (price / EQUIPPED) + an action button (EQUIP / BUY)
	-- cyan pill behind the EQUIPPED label (a clear equipped read); hidden in other states.
	local statePill = Instance.new("Frame")
	statePill.Name = "StatePill"
	statePill.AnchorPoint = Vector2.new(0.5, 1)
	statePill.Position = UDim2.fromScale(0.5, 0.97)
	statePill.Size = UDim2.fromScale(0.62, 0.2)
	statePill.BackgroundColor3 = CYAN
	statePill.BackgroundTransparency = 0.8
	statePill.BorderSizePixel = 0
	statePill.Visible = false
	statePill.ZIndex = 3
	local spC = Instance.new("UICorner")
	spC.CornerRadius = UDim.new(1, 0)
	spC.Parent = statePill
	local spS = Instance.new("UIStroke")
	spS.Color = CYAN
	spS.Transparency = 0.5
	spS.Thickness = 1
	spS.Parent = statePill
	statePill.Parent = root

	local stateText = Instance.new("TextLabel")
	stateText.BackgroundTransparency = 1
	stateText.AnchorPoint = Vector2.new(0.5, 1)
	stateText.Position = UDim2.fromScale(0.5, 0.97)
	stateText.Size = UDim2.fromScale(0.92, 0.2)
	stateText.Text = ""
	stateText.ZIndex = 4
	HudTheme.styleText(stateText, "heading")
	capText(stateText, CAP_BODY)
	stateText.Parent = root

	-- collapsed BUYABLE price (spec §4): the SHARED coin medallion + the number, centered --
	-- the real currency token, no glyph. stateText now renders ONLY the EQUIPPED word.
	local priceRow = Instance.new("Frame")
	priceRow.Name = "PriceRow"
	priceRow.AnchorPoint = Vector2.new(0.5, 1)
	priceRow.Position = UDim2.fromScale(0.5, 0.97)
	priceRow.Size = UDim2.fromScale(0.92, 0.2)
	priceRow.BackgroundTransparency = 1
	priceRow.Visible = false
	priceRow.ZIndex = 4
	local prList = Instance.new("UIListLayout")
	prList.FillDirection = Enum.FillDirection.Horizontal
	prList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	prList.VerticalAlignment = Enum.VerticalAlignment.Center
	prList.Padding = UDim.new(0, 4)
	prList.SortOrder = Enum.SortOrder.LayoutOrder
	prList.Parent = priceRow
	local priceMed = coinToken(miniMed, 4)
	priceMed.LayoutOrder = 1
	priceMed.Parent = priceRow
	local priceNum = Instance.new("TextLabel")
	priceNum.Name = "Price"
	priceNum.LayoutOrder = 2
	priceNum.BackgroundTransparency = 1
	priceNum.AutomaticSize = Enum.AutomaticSize.X
	priceNum.Size = UDim2.fromOffset(0, miniMed + 4)
	priceNum.Text = withCommas(price)
	priceNum.Font = HudTheme.Font.heading
	priceNum.TextColor3 = GOLD
	priceNum.TextSize = btnTextSize
	priceNum.TextStrokeTransparency = 1
	priceNum.ZIndex = 4
	local priceStroke = Instance.new("UIStroke")
	priceStroke.Thickness = HudTheme.TextStrokeThickness
	priceStroke.Color = HudTheme.Color.textStroke
	priceStroke.Parent = priceNum
	priceNum.Parent = priceRow
	priceRow.Parent = root

	-- action button (EQUIP / BUY) as a raised key: a darker "shadow" frame sits ~3px
	-- below it; hover lifts 1px, press sinks onto the shadow (shadow hidden). Positions
	-- are precomputed so hover/press only nudge the Y offset.
	local ABTN_BASE = UDim2.new(0.5, 0, 0.97, 0)
	local ABTN_HOVER = UDim2.new(0.5, 0, 0.97, -1)
	local ABTN_PRESS = UDim2.new(0.5, 0, 0.97, 3)

	local actionShadow = Instance.new("Frame")
	actionShadow.Name = "ActionShadow"
	actionShadow.AnchorPoint = Vector2.new(0.5, 1)
	actionShadow.Position = UDim2.new(0.5, 0, 0.97, 3)
	actionShadow.Size = UDim2.fromScale(0.86, 0.24)
	actionShadow.BackgroundColor3 = BUY_SHADOW
	actionShadow.BorderSizePixel = 0
	actionShadow.Visible = false
	actionShadow.ZIndex = 4
	local asC = Instance.new("UICorner")
	asC.CornerRadius = UDim.new(0, 10)
	asC.Parent = actionShadow
	actionShadow.Parent = root

	local actionBtn = Instance.new("TextButton")
	actionBtn.AutoButtonColor = false
	actionBtn.AnchorPoint = Vector2.new(0.5, 1)
	actionBtn.Position = ABTN_BASE
	actionBtn.Size = UDim2.fromScale(0.86, 0.24)
	actionBtn.Text = ""
	actionBtn.ZIndex = 5
	actionBtn.Visible = false
	actionBtn.BorderSizePixel = 0
	actionBtn.BackgroundColor3 = EQUIP_BG
	local abc = Instance.new("UICorner")
	abc.CornerRadius = UDim.new(0, 10)
	abc.Parent = actionBtn
	local actionScale = Instance.new("UIScale")
	actionScale.Parent = actionBtn
	-- gold gradient for BUY (toggled off for the flat EQUIP state); on the button, not
	-- its content, so only the fill is tinted (children keep their own colors/tokens).
	local actionGrad = Instance.new("UIGradient")
	actionGrad.Rotation = 90
	actionGrad.Color = BUY_GRAD
	actionGrad.Enabled = false
	actionGrad.Parent = actionBtn

	-- button content row (spec §4): the WORD (EQUIP / BUY) + optional coin medallion + the
	-- price number. A transparent list-laid frame so the button gradient never tints them.
	local actionContent = Instance.new("Frame")
	actionContent.Name = "Content"
	actionContent.BackgroundTransparency = 1
	actionContent.AnchorPoint = Vector2.new(0.5, 0.5)
	actionContent.Position = UDim2.fromScale(0.5, 0.5)
	actionContent.Size = UDim2.fromScale(0.92, 0.74)
	actionContent.ZIndex = 6
	local acList = Instance.new("UIListLayout")
	acList.FillDirection = Enum.FillDirection.Horizontal
	acList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	acList.VerticalAlignment = Enum.VerticalAlignment.Center
	acList.Padding = UDim.new(0, 3)
	acList.SortOrder = Enum.SortOrder.LayoutOrder
	acList.Parent = actionContent
	actionContent.Parent = actionBtn

	local actionText = Instance.new("TextLabel")
	actionText.Name = "Label"
	actionText.LayoutOrder = 1
	actionText.BackgroundTransparency = 1
	actionText.AutomaticSize = Enum.AutomaticSize.X
	actionText.Size = UDim2.fromOffset(0, math.floor(btnTextSize * 1.3))
	actionText.Text = ""
	actionText.Font = HudTheme.Font.heading
	actionText.TextSize = btnTextSize
	actionText.TextStrokeTransparency = 1
	actionText.ZIndex = 6
	local actionStroke = Instance.new("UIStroke")
	actionStroke.Thickness = HudTheme.TextStrokeThickness
	actionStroke.Color = HudTheme.Color.textStroke
	actionStroke.Parent = actionText
	actionText.Parent = actionContent

	-- BUY-only: the shared coin medallion + number (hidden for EQUIP; UIListLayout skips
	-- non-visible children, so "EQUIP" stays centered alone).
	local buyMed = coinToken(miniMed, 6)
	buyMed.Name = "BuyMed"
	buyMed.LayoutOrder = 2
	buyMed.Visible = false
	buyMed.Parent = actionContent

	local buyNum = Instance.new("TextLabel")
	buyNum.Name = "BuyPrice"
	buyNum.LayoutOrder = 3
	buyNum.BackgroundTransparency = 1
	buyNum.AutomaticSize = Enum.AutomaticSize.X
	buyNum.Size = UDim2.fromOffset(0, math.floor(btnTextSize * 1.3))
	buyNum.Text = withCommas(price)
	buyNum.Font = HudTheme.Font.heading
	buyNum.TextColor3 = BUY_TEXT
	buyNum.TextSize = btnTextSize
	buyNum.TextStrokeTransparency = 1
	buyNum.Visible = false
	buyNum.ZIndex = 6
	local buyNumStroke = Instance.new("UIStroke")
	buyNumStroke.Thickness = 1
	buyNumStroke.Color = BUY_HIGHLIGHT
	buyNumStroke.Transparency = 0.4
	buyNumStroke.Parent = buyNum
	buyNum.Parent = actionContent

	actionBtn.Parent = root

	local card = { frame = root, item = item, isDefault = isDefault }

	card.refresh = function()
		local st = cardStateOf(item, isDefault)
		-- glow: equipped cards get the cyan border glow.
		if st == "equipped" then
			glow.Color = CYAN
			glow.Thickness = 2.5
			glow.Transparency = 0
		else
			glow.Color = rgb(60, 68, 84)
			glow.Thickness = 1.5
			glow.Transparency = 0.2
		end

		local isExpanded = (not isDefault) and expandedId == id

		-- reset any lingering hover/press nudge before re-configuring the button
		actionBtn.Position = ABTN_BASE
		actionScale.Scale = 1

		if st == "equipped" then
			statePill.Visible = true
			stateText.Visible = true
			priceRow.Visible = false
			stateText.Text = "EQUIPPED"
			stateText.TextColor3 = CYAN
			actionBtn.Visible = false
			actionShadow.Visible = false
		elseif st == "owned" then
			statePill.Visible = false
			stateText.Visible = false
			priceRow.Visible = false
			actionBtn.Visible = true
			actionShadow.Visible = true
			actionShadow.BackgroundColor3 = EQUIP_SHADOW
			actionGrad.Enabled = false
			actionBtn.BackgroundColor3 = EQUIP_BG
			actionBtn.BackgroundTransparency = 0
			actionText.Text = "EQUIP"
			actionText.TextColor3 = Color3.new(1, 1, 1)
			actionStroke.Color = HudTheme.Color.textStroke
			actionStroke.Thickness = 2
			actionStroke.Transparency = 0
			buyMed.Visible = false
			buyNum.Visible = false
		elseif isExpanded then
			statePill.Visible = false
			stateText.Visible = false
			priceRow.Visible = false
			actionBtn.Visible = true
			actionShadow.Visible = true
			actionShadow.BackgroundColor3 = BUY_SHADOW
			actionGrad.Enabled = true
			actionBtn.BackgroundColor3 = Color3.new(1, 1, 1)
			actionBtn.BackgroundTransparency = 0
			actionText.Text = "BUY"
			actionText.TextColor3 = BUY_TEXT
			actionStroke.Color = BUY_HIGHLIGHT
			actionStroke.Thickness = 1
			actionStroke.Transparency = 0.4
			buyMed.Visible = true -- shared coin token + number, not a glyph
			buyNum.Visible = true
		else -- buyable, collapsed
			statePill.Visible = false
			stateText.Visible = false
			priceRow.Visible = true -- [coin] 900
			actionBtn.Visible = false
			actionShadow.Visible = false
		end
	end

	-- brief red flash (rejected err on this card)
	card.flashError = function()
		local base = root.BackgroundColor3
		root.BackgroundColor3 = RED
		TweenService:Create(root, TweenInfo.new(0.35), { BackgroundColor3 = base }):Play()
	end

	card.pop = function()
		HudTheme.popIn(root)
	end

	-- staggered reveal (spec §8): prep hides the card at scale 0 IMMEDIATELY (so it never
	-- flashes in at full size before its delayed turn); reveal pops it 0->1. Both share the
	-- card's own UIScale, so the buy `pop` above never collides with the reveal.
	card.prepReveal = function()
		local scale = root:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = root
	end
	card.reveal = function()
		HudTheme.popIn(root)
	end

	-- tap on the card body
	root.Activated:Connect(function()
		if not profileOk then return end
		local st = cardStateOf(item, isDefault)
		if st == "equipped" then
			return
		elseif st == "owned" then
			collapseExpanded()
			fireEquip(id, isDefault and tabKind() or item.kind)
		else -- buyable
			if expandedId == id then
				collapseExpanded() -- tapping the expanded card body collapses it
			else
				collapseExpanded()
				expandedId = id
				card.refresh()
			end
		end
	end)

	-- explicit action button (EQUIP or BUY)
	actionBtn.Activated:Connect(function()
		if not profileOk then return end
		local st = cardStateOf(item, isDefault)
		if st == "owned" then
			collapseExpanded()
			fireEquip(id, isDefault and tabKind() or item.kind)
		elseif expandedId == id then
			-- debounce AFTER fire: block a rapid second BUY tap for 0.5s (touch double-fire)
			if os.clock() - (card._lastBuy or -1) >= BUY_DEBOUNCE then
				card._lastBuy = os.clock()
				fireBuy(id)
			end
		end
	end)

	-- hover/press feedback for the action button (state-aware: EQUIP swaps its bg,
	-- BUY lifts + brightens). Cosmetic only -- the Activated buy/equip flow above is
	-- untouched. State is re-read live so a card that changed EQUIP<->BUY under the
	-- cursor animates correctly.
	local function isEquipAction()
		return cardStateOf(item, isDefault) == "owned"
	end
	local actionHover = false
	wireInteraction(actionBtn, {
		hover = function()
			actionHover = true
			if isEquipAction() then
				tweenTo(actionBtn, { Position = ABTN_HOVER, BackgroundColor3 = EQUIP_BG_HOVER })
			else
				tweenTo(actionBtn, { Position = ABTN_HOVER })
				tweenTo(actionScale, { Scale = 1.02 })
			end
		end,
		leave = function()
			actionHover = false
			if isEquipAction() then
				tweenTo(actionBtn, { Position = ABTN_BASE, BackgroundColor3 = EQUIP_BG })
			else
				tweenTo(actionBtn, { Position = ABTN_BASE })
				tweenTo(actionScale, { Scale = 1 })
			end
		end,
		press = function()
			actionBtn.Position = ABTN_PRESS -- sink onto the shadow
			actionScale.Scale = 1
			actionShadow.Visible = false
		end,
		release = function()
			actionBtn.Position = actionHover and ABTN_HOVER or ABTN_BASE
			actionShadow.Visible = actionBtn.Visible
			if actionHover and not isEquipAction() then
				actionScale.Scale = 1.02
			end
		end,
	})

	card.refresh()
	return card
end

-- ===== card grid (re)build ============================================
local function clearCards()
	collapseExpanded()
	currentCards = {}
	cardsById = {}
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy() -- destroys previews too -> SoulStyles animator self-drops them
		end
	end
end

local function sortedItemsForTab()
	local list = {}
	for _, it in ipairs(ShopCatalog.items) do
		if it.kind == activeTab then
			list[#list + 1] = it
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = RARITY_ORDER[a.rarity] or 99, RARITY_ORDER[b.rarity] or 99
		if ra ~= rb then
			return ra < rb
		end
		return ShopModel.priceOf(a, Config.SHOP_PRICES) < ShopModel.priceOf(b, Config.SHOP_PRICES)
	end)
	return list
end

local function rebuildCards()
	clearCards()
	-- bump the build generation so an in-flight staggered reveal from a PREVIOUS build
	-- (e.g. a fast tab-switch) can't un-hide cards that no longer belong to this grid.
	buildGen += 1
	local gen = buildGen

	-- first cell: the free Default card for this tab
	local def = makeCard({ kind = "default" }, true, 0)
	def.frame.Parent = scroll
	currentCards[#currentCards + 1] = def
	cardsById["default"] = def

	for i, item in ipairs(sortedItemsForTab()) do
		local card = makeCard(item, false, i)
		card.frame.Parent = scroll
		currentCards[#currentCards + 1] = card
		cardsById[item.id] = card
	end

	-- staggered reveal (spec §8): hide every card NOW, then pop them in on a short
	-- incremental delay (capped at 0.3s total so it stays quick). The gen guard drops any
	-- delayed reveal whose build has been superseded, so a rapid tab-switch never strands a
	-- card at scale 0. Bounded task.delays -- no persistent RunService loop.
	for i, card in ipairs(currentCards) do
		card.prepReveal()
		task.delay(math.min((i - 1) * 0.03, 0.3), function()
			if buildGen ~= gen then
				return
			end
			card.reveal()
		end)
	end
end

-- ===== tabs ============================================================
-- Active pill = cyan vertical gradient (white base * gradient) + dark text + a soft
-- cyan glow + a darker-cyan bottom shadow. Inactive = flat TAB_OFF_BG. Hover on an
-- inactive pill (wired at build) only lightens it; the active pill ignores hover.
local function paintTabs()
	for _, tab in ipairs(TABS) do
		local entry = tabPills[tab.kind]
		local isActive = tab.kind == activeTab
		if isActive then
			entry.pill.BackgroundColor3 = Color3.new(1, 1, 1)
			entry.gradient.Enabled = true
			entry.stroke.Enabled = true
			entry.shadow.BackgroundColor3 = TAB_ACTIVE_SHADOW
			entry.label.TextColor3 = TAB_ACTIVE_TEXT
		else
			entry.pill.BackgroundColor3 = TAB_OFF_BG
			entry.gradient.Enabled = false
			entry.stroke.Enabled = false
			entry.shadow.BackgroundColor3 = TAB_SHADOW_OFF
			entry.label.TextColor3 = TAB_OFF_TEXT
		end
	end
end

local function selectTab(kind)
	if activeTab == kind then return end
	activeTab = kind
	paintTabs()
	rebuildCards()
end

-- ===== layout application =============================================
-- Bottom-right toggle. On touch devices it must never intersect the TouchJumpLayout
-- rect -- see 2026-07-10 mobile jump spec -- so we compute the live jump rect (same
-- pure module + Config scale InputController uses) and sit 12px ABOVE it, right edge
-- aligned to the jump button's. Non-touch keeps the plain 16px corner. Recomputed on
-- every viewport change (the jump rect moves with the viewport).
local function placeToggle()
	local vp = currentViewport()
	local ts = ShopLayoutModel.layout(vp).typeScale
	local d = math.max(44, math.floor(56 * ts))
	toggleBtn.Size = UDim2.fromOffset(d, d)
	toggleBtn.AnchorPoint = Vector2.new(1, 1)
	if UserInputService.TouchEnabled then
		local j = TouchJumpLayout.compute(vp.w, vp.h, Config.TOUCH_JUMP_SCALE)
		-- right edge aligned to jump's right edge; bottom 12px above jump's top edge
		toggleBtn.Position = UDim2.new(1, j.xOffset + j.size, 1, j.yOffset - 12)
	else
		toggleBtn.Position = UDim2.new(1, -16, 1, -16)
	end
end

-- (Re)build the header coin medallion at a size derived from the live header height, so
-- the SHARED coin token (spec §4) stays crisp across viewports. Cheap: one small Frame.
local function rebuildCoinChipMedallion()
	if not coinChip then
		return
	end
	if coinChipMed then
		coinChipMed:Destroy()
	end
	local medPx = math.max(16, math.floor((L and L.headerH or 46) * 0.5))
	local med = coinToken(medPx, 4)
	med.Name = "CoinMed"
	med.AnchorPoint = Vector2.new(0, 0.5)
	med.Position = UDim2.new(0, math.floor(medPx * 0.4), 0.5, 0)
	med.Parent = coinChip
	coinChipMed = med
end

local function applyLayout()
	L = ShopLayoutModel.layout(currentViewport())
	placeToggle()
	rebuildCoinChipMedallion()

	-- panel geometry
	local top = L.panelTopPx
	local h = 1 -- scale; height = full minus top+bottom offsets
	if L.mode == "sheet" then
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, 0, 0, top)
	else
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, -PAD, 0, top)
	end
	panel.Size = UDim2.new(0, L.panelW, h, -(top + L.panelBottomMarginPx))

	-- header / tabs / scroll vertical stack (manual: scroll fills the remainder)
	local closeD = 44
	headerRow.Position = UDim2.new(0, PAD, 0, PAD)
	headerRow.Size = UDim2.new(1, -(PAD * 2 + closeD + 4), 0, L.headerH)
	tabsRow.Position = UDim2.new(0, PAD, 0, PAD + L.headerH + GAP)
	tabsRow.Size = UDim2.new(1, -PAD * 2, 0, L.tabH)
	local contentTop = PAD + L.headerH + GAP + L.tabH + GAP
	scroll.Position = UDim2.new(0, PAD, 0, contentTop)
	scroll.Size = UDim2.new(1, -PAD * 2, 1, -(contentTop + PAD))

	grid.CellSize = UDim2.fromOffset(L.cardW, L.cardH)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)

	closeBtn.Size = UDim2.fromOffset(closeD, closeD)

	-- re-scale every registered text cap by the live typeScale
	for _, entry in ipairs(textCaps) do
		entry.c.MaxTextSize = math.max(10, math.floor(entry.cap * L.typeScale))
	end
end

-- ===== open / close / access ==========================================
local function updateToggleVisibility()
	toggleBtn.Visible = eligible() and not panelOpen and profileOk
end

local function openPanel()
	if panelOpen or not eligible() or not profileOk then return end
	panelOpen = true
	applyLayout()
	rebuildCards()
	setCoinText(coins)
	panel.Visible = true
	HudTheme.popIn(panel)
	updateToggleVisibility()
end

local function closePanel()
	if not panelOpen then return end
	panelOpen = false
	collapseExpanded()
	panel.Visible = false
	updateToggleVisibility()
end

-- ===== build ===========================================================
local function build()
	L = ShopLayoutModel.layout(currentViewport())

	gui = Instance.new("ScreenGui")
	gui.Name = "ShopHud"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- the shop is a foreground panel -- always above the round banner (#1)
	gui.DisplayOrder = HudTheme.DisplayOrder.bookend + 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ===== toggle button (bottom-right; clear of ClientEconomyHud's top-left/center) =====
	-- Size + position are set by placeToggle() (called via applyLayout at build end).
	toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "ShopToggle"
	toggleBtn.Text = ""
	toggleBtn.AutoButtonColor = false
	toggleBtn.BackgroundColor3 = Color3.new(1, 1, 1) -- white base tinted by the gradient
	toggleBtn.BackgroundTransparency = 0.06
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Visible = false
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0.5, 0)
	tc.Parent = toggleBtn
	local toggleGrad = Instance.new("UIGradient")
	toggleGrad.Rotation = 90
	toggleGrad.Color = ColorSequence.new(TOGGLE_GRAD_A, TOGGLE_GRAD_B)
	toggleGrad.Parent = toggleBtn
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2.5
	ts.Color = HudTheme.Color.panelStroke
	ts.Parent = toggleBtn
	local toggleScale = Instance.new("UIScale")
	toggleScale.Parent = toggleBtn
	-- coin-purse glyph: two stacked gold circles
	for i, cfg in ipairs({ { s = 0.42, y = 0.36 }, { s = 0.5, y = 0.5 } }) do
		local coin = Instance.new("Frame")
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Position = UDim2.fromScale(0.5, cfg.y)
		coin.Size = UDim2.fromScale(cfg.s, cfg.s)
		coin.BackgroundColor3 = i == 1 and rgb(255, 224, 138) or GOLD
		coin.BorderSizePixel = 0
		coin.ZIndex = 2
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0.5, 0)
		cc.Parent = coin
		coin.Parent = toggleBtn
	end
	local shopLabel = Instance.new("TextLabel")
	shopLabel.BackgroundTransparency = 1
	shopLabel.AnchorPoint = Vector2.new(0.5, 1)
	shopLabel.Position = UDim2.fromScale(0.5, 0.98)
	shopLabel.Size = UDim2.fromScale(0.9, 0.26)
	shopLabel.Text = "SHOP"
	shopLabel.ZIndex = 3
	HudTheme.styleText(shopLabel, "heading")
	capText(shopLabel, CAP_BODY)
	shopLabel.Parent = toggleBtn
	local toggleHover = false
	wireInteraction(toggleBtn, {
		hover = function()
			toggleHover = true
			tweenTo(toggleScale, { Scale = 1.04 })
			ts.Color = CYAN
		end,
		leave = function()
			toggleHover = false
			tweenTo(toggleScale, { Scale = 1 })
			ts.Color = HudTheme.Color.panelStroke
		end,
		press = function()
			toggleScale.Scale = 0.97
		end,
		release = function()
			toggleScale.Scale = toggleHover and 1.04 or 1
		end,
	})
	toggleBtn.Activated:Connect(openPanel)
	toggleBtn.Parent = gui

	-- ===== panel =====
	panel = Instance.new("Frame")
	panel.Name = "ShopPanel"
	panel.BackgroundColor3 = HudTheme.Color.panelDark
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 1
	local pc = Instance.new("UICorner")
	pc.CornerRadius = HudTheme.Radius
	pc.Parent = panel
	local ps = Instance.new("UIStroke")
	ps.Thickness = 2.5
	ps.Color = HudTheme.Color.panelStroke
	ps.Parent = panel
	panel.Parent = gui

	-- close X (top-right corner, 44px touch floor). The X is DRAWN from two rotated
	-- bars, not a glyph -- FredokaOne has no U+2715, so a glyph renders as tofu.
	closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Text = ""
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = CLOSE_BG
	closeBtn.BackgroundTransparency = 0.15
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 6
	local clc = Instance.new("UICorner")
	clc.CornerRadius = UDim.new(0.5, 0)
	clc.Parent = closeBtn
	local closeScale = Instance.new("UIScale")
	closeScale.Parent = closeBtn
	local closeBars = {}
	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.Name = rot == 45 and "BarA" or "BarB"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(0.46, 0.09) -- ~20x4px on the 44px button
		bar.BackgroundColor3 = CLOSE_BAR
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		bar.ZIndex = 7
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 2)
		bc.Parent = bar
		bar.Parent = closeBtn
		closeBars[#closeBars + 1] = bar
	end
	closeBtn.Parent = panel
	closeBtn.Activated:Connect(closePanel)
	local function paintCloseBars(c)
		for _, bar in ipairs(closeBars) do
			bar.BackgroundColor3 = c
		end
	end
	local function closeBase()
		tweenTo(closeBtn, { BackgroundColor3 = CLOSE_BG })
		tweenTo(closeScale, { Scale = 1 })
		paintCloseBars(CLOSE_BAR)
	end
	local function closeHot()
		tweenTo(closeBtn, { BackgroundColor3 = CLOSE_BG_HOVER })
		tweenTo(closeScale, { Scale = 1.06 })
		paintCloseBars(CLOSE_BAR_HOT)
	end
	local closeHover = false
	wireInteraction(closeBtn, {
		hover = function()
			closeHover = true
			closeHot()
		end,
		leave = function()
			closeHover = false
			closeBase()
		end,
		press = function()
			closeBtn.BackgroundColor3 = CLOSE_BG_PRESS
			closeScale.Scale = 0.96
			paintCloseBars(CLOSE_BAR_HOT)
		end,
		release = function()
			-- If still hovering (desktop), settle into the hover look; otherwise (a
			-- touch tap, where MouseEnter/Leave don't fire) settle straight to base so
			-- the persistent close button never gets stuck red/enlarged on reopen.
			if closeHover then
				closeHot()
			else
				closeBase()
			end
		end,
	})

	-- header row: title + coin chip
	headerRow = Instance.new("Frame")
	headerRow.Name = "Header"
	headerRow.BackgroundTransparency = 1
	headerRow.ZIndex = 3
	headerRow.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.fromScale(0, 0.5)
	titleLabel.Size = UDim2.fromScale(0.56, 0.86)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = "SOUL SHOP"
	HudTheme.styleText(titleLabel, "title")
	capText(titleLabel, CAP_TITLE)
	titleLabel.Parent = headerRow

	coinChip = Instance.new("Frame")
	coinChip.Name = "CoinChip"
	coinChip.AnchorPoint = Vector2.new(1, 0.5)
	coinChipBase = UDim2.fromScale(1, 0.5)
	coinChip.Position = coinChipBase
	coinChip.Size = UDim2.fromScale(0.42, 0.72)
	coinChip.BackgroundColor3 = rgb(12, 16, 24)
	coinChip.BorderSizePixel = 0
	coinChip.ZIndex = 3
	local ccc = Instance.new("UICorner")
	ccc.CornerRadius = UDim.new(1, 0)
	ccc.Parent = coinChip
	coinChip.Parent = headerRow

	-- the gold coin glyph is the SHARED HudTheme.makeCoinMedallion token (spec §4) -- the
	-- SAME coin the balance readout uses. Built + resized by applyLayout (rebuildCoinChipMed)
	-- so it stays crisp across viewports; the count label reads to its right.

	coinChipCount = Instance.new("TextLabel")
	coinChipCount.BackgroundTransparency = 1
	coinChipCount.AnchorPoint = Vector2.new(1, 0.5)
	coinChipCount.Position = UDim2.fromScale(0.94, 0.5)
	coinChipCount.Size = UDim2.fromScale(0.66, 0.72)
	coinChipCount.TextXAlignment = Enum.TextXAlignment.Right
	coinChipCount.Text = "0"
	coinChipCount.ZIndex = 4
	HudTheme.styleText(coinChipCount, "heading")
	capText(coinChipCount, CAP_BODY)
	coinChipCount.Parent = coinChip

	-- tabs row: 3 equal pills
	tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.BackgroundTransparency = 1
	tabsRow.ZIndex = 3
	tabsRow.Parent = panel
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabsLayout.Padding = UDim.new(0, 6)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabsRow
	for i, tab in ipairs(TABS) do
		local pill = Instance.new("TextButton")
		pill.Name = "Tab_" .. tab.kind
		pill.AutoButtonColor = false
		pill.Text = ""
		pill.LayoutOrder = i
		pill.Size = UDim2.new(1 / 3, -6, 1, 0)
		pill.BackgroundColor3 = TAB_OFF_BG
		pill.BorderSizePixel = 0
		pill.ZIndex = 3
		local pcc = Instance.new("UICorner")
		pcc.CornerRadius = UDim.new(0, 11)
		pcc.Parent = pill

		-- bottom shadow for a raised-key read. A CHILD (not a layout sibling) offset 2px
		-- down at a lower ZIndex, so UIListLayout ignores it and it peeks below the pill.
		local pshadow = Instance.new("Frame")
		pshadow.Name = "Shadow"
		pshadow.AnchorPoint = Vector2.new(0.5, 0.5)
		pshadow.Position = UDim2.new(0.5, 0, 0.5, 2)
		pshadow.Size = UDim2.fromScale(1, 1)
		pshadow.BackgroundColor3 = TAB_SHADOW_OFF
		pshadow.BorderSizePixel = 0
		pshadow.ZIndex = 2
		local psc = Instance.new("UICorner")
		psc.CornerRadius = UDim.new(0, 11)
		psc.Parent = pshadow
		pshadow.Parent = pill

		-- cyan vertical gradient (active only; toggled by paintTabs)
		local pgrad = Instance.new("UIGradient")
		pgrad.Rotation = 90
		pgrad.Color = ColorSequence.new(TAB_ACTIVE_A, TAB_ACTIVE_B)
		pgrad.Enabled = false
		pgrad.Parent = pill

		-- soft cyan glow (active only)
		local pstroke = Instance.new("UIStroke")
		pstroke.Thickness = 1.5
		pstroke.Color = TAB_ACTIVE_B
		pstroke.Transparency = 0.35
		pstroke.Enabled = false
		pstroke.Parent = pill

		local pscale = Instance.new("UIScale")
		pscale.Parent = pill

		local plabel = Instance.new("TextLabel")
		plabel.BackgroundTransparency = 1
		plabel.Size = UDim2.fromScale(0.9, 0.7)
		plabel.AnchorPoint = Vector2.new(0.5, 0.5)
		plabel.Position = UDim2.fromScale(0.5, 0.5)
		plabel.Text = tab.label
		plabel.TextColor3 = TAB_OFF_TEXT
		plabel.ZIndex = 4
		plabel.Font = HudTheme.Font.heading
		plabel.TextScaled = true
		capText(plabel, CAP_BODY)
		plabel.Parent = pill
		pill.Activated:Connect(function()
			selectTab(tab.kind)
		end)
		pill.Parent = tabsRow
		tabPills[tab.kind] = { pill = pill, label = plabel, gradient = pgrad, shadow = pshadow, stroke = pstroke }
		wireInteraction(pill, {
			hover = function()
				if activeTab == tab.kind then return end -- active pill ignores hover
				pill.BackgroundColor3 = TAB_HOVER_BG
				plabel.TextColor3 = TAB_HOVER_TEXT
			end,
			leave = function()
				if activeTab == tab.kind then return end
				pill.BackgroundColor3 = TAB_OFF_BG
				plabel.TextColor3 = TAB_OFF_TEXT
			end,
			press = function()
				pscale.Scale = 0.97
			end,
			release = function()
				pscale.Scale = 1
			end,
		})
	end
	paintTabs()

	-- scrolling card grid
	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = rgb(70, 80, 100) -- thin, low-contrast bar consistent w/ the panel (§8)
	scroll.ScrollBarImageTransparency = 0.35
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ClipsDescendants = true
	scroll.ZIndex = 2
	scroll.Parent = panel
	grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellSize = UDim2.fromOffset(L.cardW, L.cardH)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.Parent = scroll

	-- profile-loading hint (shown on profile_unavailable): an intentional centered pill,
	-- not bare floating text (§8 empty/edge state).
	hintBox = Instance.new("Frame")
	hintBox.Name = "Hint"
	hintBox.AnchorPoint = Vector2.new(0.5, 0.5)
	hintBox.Position = UDim2.fromScale(0.5, 0.5)
	hintBox.Size = UDim2.fromScale(0.66, 0.11)
	hintBox.BackgroundColor3 = PILL_BG
	hintBox.BackgroundTransparency = 0.2
	hintBox.BorderSizePixel = 0
	hintBox.Visible = false
	hintBox.ZIndex = 7
	local hbC = Instance.new("UICorner")
	hbC.CornerRadius = UDim.new(0, 12)
	hbC.Parent = hintBox
	local hbS = Instance.new("UIStroke")
	hbS.Color = HudTheme.Color.panelStroke
	hbS.Transparency = 0.7
	hbS.Thickness = 1.5
	hbS.Parent = hintBox
	local hintText = Instance.new("TextLabel")
	hintText.Name = "Text"
	hintText.BackgroundTransparency = 1
	hintText.AnchorPoint = Vector2.new(0.5, 0.5)
	hintText.Position = UDim2.fromScale(0.5, 0.5)
	hintText.Size = UDim2.fromScale(0.86, 0.62)
	hintText.Text = "Profile loading\u{2026}"
	hintText.ZIndex = 8
	HudTheme.styleText(hintText, "heading")
	capText(hintText, CAP_BODY)
	hintText.Parent = hintBox
	hintBox.Parent = panel

	built = true -- every UI ref now exists; applyProfile may safely touch the UI
	applyLayout()
end

-- ===== remote handling =================================================
local function applyProfile(view)
	profileOk = true
	coins = view.coins or 0

	owned = {}
	for _, id in ipairs(view.ownedItems or {}) do
		owned[id] = true
	end
	-- detect an equipped-HALO change vs the previous mirror: a halo_color/halo_style change
	-- alters the RESOLVED composite every card renders, so the previews must be rebuilt
	-- (not merely restated). Trails don't touch halo previews. (#4 / spec §6)
	local prev = equipped
	equipped = {
		halo_color = view.equipped and view.equipped.halo_color or nil,
		halo_style = view.equipped and view.equipped.halo_style or nil,
		trail = view.equipped and view.equipped.trail or nil,
	}
	local haloEquipChanged = prev.halo_color ~= equipped.halo_color or prev.halo_style ~= equipped.halo_style

	-- The handler is connected BEFORE build() (spec §5) so the one-shot join push can't be
	-- missed; until build finishes the UI refs don't exist, so only the state mirrors above
	-- run -- build() reflects the current state when it completes, and the sync fire re-pushes.
	if not built then
		return
	end

	hintBox.Visible = false
	-- Authoritative balance. While the panel is open, animate to it through the same
	-- token'd path as a buy -- if it lands mid buy-tween toward the same balance the
	-- tick continues smoothly (last-writer token, no snap). Hidden: snap and cancel.
	if panelOpen then
		animateCoinsTo(coins)
	else
		coinsAnimToken = nil
		setCoinText(coins)
	end

	if panelOpen then
		if haloEquipChanged then
			rebuildCards() -- composite changed -> previews must reflect the new halo
		else
			refreshCardStates() -- pure coin/ownership update -> cheap restate, previews kept
		end
	end
	updateToggleVisibility()
end

local function applyResult(res)
	if res.ok then
		if res.action == "buy" then
			local item = ShopCatalog.byId(res.itemId)
			if item then
				owned[res.itemId] = true
				equipped[item.kind] = res.itemId -- server auto-equips on buy
				-- optimistic coin tick-down (ProfileUpdated confirms authoritative)
				local price = ShopModel.priceOf(item, Config.SHOP_PRICES)
				coins = math.max(0, coins - price)
				animateCoinsTo(coins)
				collapseExpanded()
				refreshCardStates()
				local card = cardsById[res.itemId]
				if card then card.pop() end
			end
		elseif res.action == "equip" then
			-- optimistic: server confirms via ProfileUpdated
			if res.itemId == "default" then
				equipped[activeTab] = nil
			else
				local item = ShopCatalog.byId(res.itemId)
				if item then
					equipped[item.kind] = res.itemId
				end
			end
			refreshCardStates()
		end
		return
	end

	-- rejections
	if res.err == "insufficient_coins" then
		shakeCoinChip()
	elseif res.err == "profile_unavailable" then
		profileOk = false
		if panelOpen then
			hintBox.Visible = true
		end
		updateToggleVisibility()
	else
		-- already_owned / not_owned / unknown_item -> flash the offending card
		local card = res.itemId and cardsById[res.itemId]
		if card then card.flashError() end
	end
end

-- ===== viewport rebind (camera can be replaced; mirror HudTheme) =======
local viewportConn = nil
local function onViewportChange()
	if not panelOpen then
		-- keep the toggle sized AND clear of the (moved) jump rect even while closed
		placeToggle()
		return
	end
	applyLayout()
	rebuildCards() -- cards + fixed-px previews must resize; rebuild is the clean path
end
local function bindViewport()
	if viewportConn then viewportConn:Disconnect() end
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChange)
	end
end

-- Track the local player's RESOLVED soul color from SoulMap (spec §6): find our body by its
-- ControllerUserId attribute and mirror entry.color. That's the identity color the flat
-- previews use when no halo_color is equipped. A change while the panel is open (a lobby
-- swap) rebuilds only the identity-colored previews so they stay truthful.
local function onSoulMap(list)
	for _, entry in ipairs(list) do
		local body = entry.body
		if body and body:GetAttribute("ControllerUserId") == player.UserId then
			if entry.color and entry.color ~= localSoulColor then
				localSoulColor = entry.color
				if built and panelOpen and equipped.halo_color == nil then
					rebuildCards() -- only identity-colored previews depend on this color
				end
			end
			return
		end
	end
end

function ClientShopHud.start()
	-- (#4 / spec §5) Connect the profile handler FIRST -- BEFORE the heavy build -- so the
	-- one-shot join ProfileUpdated push can't slip past during a slow build. applyProfile
	-- only writes the state mirrors until `built` is true, so an early push is safe.
	ProfileUpdated.OnClientEvent:Connect(applyProfile)
	-- Track our resolved soul color for the identity-colored composite previews (spec §6).
	SoulMap.OnClientEvent:Connect(onSoulMap)

	SoulStyles.start() -- ensure the shared preview animator is running (idempotent)
	build()

	ShopResult.OnClientEvent:Connect(applyResult)

	RoundStateChanged.OnClientEvent:Connect(function(state)
		phase = state.phase
		if phase ~= "Active" then
			eliminated = false -- fresh round: alive again until an elimination says otherwise
		end
		if not eligible() and panelOpen then
			closePanel()
		end
		updateToggleVisibility()
	end)

	EliminationEvent.OnClientEvent:Connect(function(playerName)
		if playerName == player.Name then
			eliminated = true
			updateToggleVisibility()
		end
	end)

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewport()
		onViewportChange()
	end)
	bindViewport()
	updateToggleVisibility()

	-- (#4 / spec §5) Handler now live -- ask the server to re-push the profile in case the
	-- join push already fired before we connected (an idle lobby never re-pushes on its own).
	-- Net: the shop always obtains current coins + equipped shortly after start.
	ShopRequest:FireServer({ action = "sync" })
end

return ClientShopHud
