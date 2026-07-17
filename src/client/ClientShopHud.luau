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

local ClientShopHud = {}
local player = Players.LocalPlayer

-- ===== style constants (spec §6.2 / §7) ================================
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local CYAN = rgb(57, 214, 224)         -- active tab / equipped accent (free Soul cyan)
local GOLD = rgb(255, 201, 77)         -- coins + price + BUY
local DARK_TEXT = rgb(20, 24, 31)
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

-- built once
local gui, toggleBtn, panel, closeBtn, titleLabel, coinChip, coinChipCount, coinChipBase
local tabsRow, headerRow, scroll, grid, hintLabel
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

-- ===== coin chip =======================================================
-- The single entry point that writes the chip: records what's on screen so the
-- tween always animates FROM the displayed value, not from the (already-decremented)
-- balance mirror.
local function setCoinText(n)
	displayedCoins = math.max(0, math.floor(n + 0.5))
	coinChipCount.Text = tostring(displayedCoins)
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

-- Returns the preview Frame (SoulStyles handle for color/style; ribbon for trails;
-- identity Classic for the free Default card). Cleanup contract: SoulStyles.buildPreview
-- returns the animator root Frame -- destroying it (via destroying the card subtree on
-- rebuild) makes the shared animator drop the handle next Heartbeat, so simply
-- :Destroy()-ing the card is the full teardown; no explicit handle bookkeeping needed.
local function buildPreview(item, px)
	if item.kind == "trail" then
		return buildTrailRibbon(item, px)
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

	-- rarity chip top-left
	if not isDefault then
		local chip = Instance.new("Frame")
		chip.AnchorPoint = Vector2.new(0, 0)
		chip.Position = UDim2.fromScale(0.06, 0.06)
		chip.Size = UDim2.fromScale(0.22, 0.1)
		chip.BackgroundColor3 = RARITY_COLOR[item.rarity] or TAB_OFF_TEXT
		chip.BorderSizePixel = 0
		chip.ZIndex = 4
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(1, 0)
		cc.Parent = chip
		chip.Parent = root
	end

	-- preview (centered)
	local previewPx = math.max(20, math.floor(L.cardH * 0.4))
	local preview = buildPreview(isDefault and { kind = "default" } or item, previewPx)
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

	local actionBtn = Instance.new("TextButton")
	actionBtn.AutoButtonColor = false
	actionBtn.AnchorPoint = Vector2.new(0.5, 1)
	actionBtn.Position = UDim2.fromScale(0.5, 0.97)
	actionBtn.Size = UDim2.fromScale(0.86, 0.24)
	actionBtn.Text = ""
	actionBtn.ZIndex = 5
	actionBtn.Visible = false
	actionBtn.BorderSizePixel = 0
	local abc = Instance.new("UICorner")
	abc.CornerRadius = UDim.new(0, 8)
	abc.Parent = actionBtn
	HudTheme.styleText(actionBtn, "heading")
	capText(actionBtn, CAP_BODY)
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

		if st == "equipped" then
			stateText.Visible = true
			stateText.Text = "EQUIPPED"
			stateText.TextColor3 = CYAN
			actionBtn.Visible = false
		elseif st == "owned" then
			stateText.Visible = false
			actionBtn.Visible = true
			actionBtn.Text = "EQUIP"
			actionBtn.TextColor3 = Color3.new(1, 1, 1)
			actionBtn.BackgroundColor3 = TAB_OFF_BG
			actionBtn.BackgroundTransparency = 0
		elseif isExpanded then
			stateText.Visible = false
			actionBtn.Visible = true
			actionBtn.Text = "BUY"
			actionBtn.TextColor3 = DARK_TEXT
			actionBtn.BackgroundColor3 = GOLD
			actionBtn.BackgroundTransparency = 0
		else -- buyable, collapsed
			stateText.Visible = true
			stateText.Text = "\u{25C8} " .. tostring(ShopModel.priceOf(item, Config.SHOP_PRICES))
			stateText.TextColor3 = GOLD
			actionBtn.Visible = false
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
end

-- ===== tabs ============================================================
local function paintTabs()
	for _, tab in ipairs(TABS) do
		local entry = tabPills[tab.kind]
		local isActive = tab.kind == activeTab
		entry.pill.BackgroundColor3 = isActive and CYAN or TAB_OFF_BG
		entry.label.TextColor3 = isActive and DARK_TEXT or TAB_OFF_TEXT
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

local function applyLayout()
	L = ShopLayoutModel.layout(currentViewport())
	placeToggle()

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
	gui.DisplayOrder = HudTheme.DisplayOrder.bookend - 1
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ===== toggle button (bottom-right; clear of ClientEconomyHud's top-left/center) =====
	-- Size + position are set by placeToggle() (called via applyLayout at build end).
	toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "ShopToggle"
	toggleBtn.Text = ""
	toggleBtn.AutoButtonColor = false
	toggleBtn.BackgroundColor3 = HudTheme.Color.panelDark
	toggleBtn.BackgroundTransparency = 0.06
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Visible = false
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0.5, 0)
	tc.Parent = toggleBtn
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2.5
	ts.Color = HudTheme.Color.panelStroke
	ts.Parent = toggleBtn
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
	toggleBtn.Activated:Connect(openPanel)

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

	-- close X (top-right corner, 44px touch floor)
	closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -6, 0, 6)
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.Text = "\u{2715}"
	closeBtn.AutoButtonColor = false
	closeBtn.BackgroundColor3 = TAB_OFF_BG
	closeBtn.BackgroundTransparency = 0.15
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 6
	local clc = Instance.new("UICorner")
	clc.CornerRadius = UDim.new(0.5, 0)
	clc.Parent = closeBtn
	HudTheme.styleText(closeBtn, "heading")
	capText(closeBtn, CAP_BODY)
	closeBtn.Parent = panel
	closeBtn.Activated:Connect(closePanel)

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

	local coinDot = Instance.new("Frame")
	coinDot.AnchorPoint = Vector2.new(0, 0.5)
	coinDot.Position = UDim2.fromScale(0.06, 0.5)
	coinDot.Size = UDim2.fromScale(0.5, 0.62)
	coinDot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	coinDot.BackgroundColor3 = GOLD
	coinDot.BorderSizePixel = 0
	coinDot.ZIndex = 4
	local cdc = Instance.new("UICorner")
	cdc.CornerRadius = UDim.new(0.5, 0)
	cdc.Parent = coinDot
	coinDot.Parent = coinChip

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
		pcc.CornerRadius = UDim.new(0, 8)
		pcc.Parent = pill
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
		tabPills[tab.kind] = { pill = pill, label = plabel }
	end
	paintTabs()

	-- scrolling card grid
	scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
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

	-- profile-loading hint overlay (shown on profile_unavailable)
	hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.BackgroundTransparency = 1
	hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hintLabel.Position = UDim2.fromScale(0.5, 0.5)
	hintLabel.Size = UDim2.fromScale(0.8, 0.1)
	hintLabel.Text = "Profile loading\u{2026}"
	hintLabel.Visible = false
	hintLabel.ZIndex = 7
	HudTheme.styleText(hintLabel, "heading")
	capText(hintLabel, CAP_BODY)
	hintLabel.Parent = panel

	applyLayout()
end

-- ===== remote handling =================================================
local function applyProfile(view)
	profileOk = true
	hintLabel.Visible = false
	coins = view.coins or 0
	-- Authoritative balance. While the panel is open, animate to it through the same
	-- token'd path as a buy -- if it lands mid buy-tween toward the same balance the
	-- tick continues smoothly (last-writer token, no snap). Hidden: snap and cancel.
	if panelOpen then
		animateCoinsTo(coins)
	else
		coinsAnimToken = nil
		setCoinText(coins)
	end

	owned = {}
	for _, id in ipairs(view.ownedItems or {}) do
		owned[id] = true
	end
	equipped = {
		halo_color = view.equipped and view.equipped.halo_color or nil,
		halo_style = view.equipped and view.equipped.halo_style or nil,
		trail = view.equipped and view.equipped.trail or nil,
	}

	if panelOpen then
		refreshCardStates()
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
			hintLabel.Visible = true
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

function ClientShopHud.start()
	SoulStyles.start() -- ensure the shared preview animator is running (idempotent)
	build()

	ProfileUpdated.OnClientEvent:Connect(applyProfile)
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
end

return ClientShopHud
