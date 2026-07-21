--[[
	ClientEconomyHud -- renders the economy UI: a persistent top-left Coins/Level
	readout (from ProfileUpdated) and the end-of-round reward panel (from
	RewardGranted + the latest ProfileUpdated). WHAT to show in the panel is the pure
	RewardScreenModel's decision; this module only renders (HudTheme skin). The panel
	auto-hides shortly after it appears (the Ended window is brief).
	Location: StarterPlayerScripts/Client/ClientEconomyHud  (ModuleScript)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RewardScreenModel = require(Shared:WaitForChild("RewardScreenModel"))
local XpFillModel = require(Shared:WaitForChild("XpFillModel"))
local ProgressionModel = require(Shared:WaitForChild("ProgressionModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RewardGranted = Remotes.get("RewardGranted")
local ProfileUpdated = Remotes.get("ProfileUpdated")

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

local ClientEconomyHud = {}
local player = Players.LocalPlayer

-- Latest authoritative HUD view from ProfileUpdated; the reward panel reads level
-- + progress from it, the persistent readout reads coins + level.
local lastView = { coins = 0, level = 1, progress = 0 }

local balanceCoins, balanceLevel, balanceXpFill -- persistent readout: amount, level badge, XP fill
local rewardRoot, rewardCoins, rewardXp, rewardLevel, rewardBarFill -- reward panel
local rewardHandle                     -- makePanel handle; setPanelAccent needs the table, not a Frame
local hideToken = nil  -- generation token: a newer reward cancels the prior hide
local animToken = nil  -- same token gates the running fill coroutine (cancel-on-retrigger)

-- Pure thousands separator: 7426 -> "7,426". Integer-floored; sign preserved
-- (coins are non-negative, but the helper stays general).
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

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EconomyHud"
	gui.ResetOnSpawn = false
	-- IGNORE the topbar inset (matches ShopHud/RoundHud). The HudZoneModel zones are
	-- themselves inset-aware -- the `topLeft`/`top` zones offset children by
	-- `safeTop = insetTop + margin` -- so they place the balance panel below Roblox's
	-- menu/unibar button using the true screen origin. If the ScreenGui ALSO respected
	-- the inset, the panel would be pushed down by the inset twice (double-count); with
	-- IgnoreGuiInset = true the origin is the real screen top and the zone adds the
	-- inset exactly once. The centered reward panel is unaffected.
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = HudTheme.DisplayOrder.bookend -- same layer as the results banner
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ===== Persistent Coins/Level readout (top-left, below the topbar inset) =====
	-- Placed via the inset-aware `topLeft` zone (anchor 0,0; offset x=14, y=safeTop).
	-- makePanel registers the root in HudTheme's zone registry, so replaceAll() KEEPS
	-- it top-left on every viewport/camera change -- no manual AnchorPoint/Position
	-- override (that override was the center-clobber bug #6: the root was registered on
	-- the "top" center zone and re-placed to center over the banner). We deliberately
	-- avoid the other corners: top-right (default player list), top-center (round
	-- banner), and the bottom corners (mobile joystick/jump).
	--
	-- Sizing: a scale width (0.16) clamped to 176..192px and 60..66px tall via a
	-- UISizeConstraint. The scale grows the panel a touch on big screens but the max cap
	-- keeps it compact (~192x66 at desktop); the min cap keeps it legible on phones. Its
	-- top-left anchor + <=192px width means its right edge stays well left of the
	-- centered banner (whose left edge is w/2 - bannerWidth/2) on every realistic
	-- landscape viewport -- they can't overlap.
	local handle = HudTheme.makePanel(gui, UDim2.fromScale(0.16, 0.09), "topLeft", nil)
	do
		local sc = Instance.new("UISizeConstraint")
		sc.MinSize = Vector2.new(176, 60)
		sc.MaxSize = Vector2.new(192, 66)
		sc.Parent = handle.root
	end

	-- Dark gradient panel (top -> bottom) in HudTheme language, with a softer corner
	-- and a subtle hairline stroke (makePanel's chunky 4px white stroke is dialed down).
	handle.gradient.Color = ColorSequence.new(Color3.fromRGB(27, 33, 48), Color3.fromRGB(17, 22, 31))
	local panelCorner = handle.panel:FindFirstChildOfClass("UICorner")
	if panelCorner then
		panelCorner.CornerRadius = UDim.new(0, 14)
	end
	local panelStroke = handle.panel:FindFirstChildOfClass("UIStroke")
	if panelStroke then
		panelStroke.Thickness = 1.5
		panelStroke.Transparency = 0.85
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = handle.panel

	-- ---- Row 1: gold coin medallion + amount + COINS sublabel ----
	local medallion = Instance.new("Frame")
	medallion.Name = "CoinMedallion"
	medallion.AnchorPoint = Vector2.new(0, 0)
	medallion.Position = UDim2.new(0, 0, 0, 0)
	medallion.Size = UDim2.fromOffset(26, 26)
	medallion.BackgroundColor3 = Color3.new(1, 1, 1) -- gradient tints it
	medallion.BorderSizePixel = 0
	medallion.ZIndex = 3
	local medCorner = Instance.new("UICorner")
	medCorner.CornerRadius = UDim.new(1, 0) -- circle
	medCorner.Parent = medallion
	local medGrad = Instance.new("UIGradient")
	medGrad.Color = ColorSequence.new(Color3.fromRGB(255, 224, 138), Color3.fromRGB(201, 154, 46))
	medGrad.Rotation = 45 -- diagonal sheen fakes a radial gold
	medGrad.Parent = medallion
	local medRing = Instance.new("UIStroke")
	medRing.Color = Color3.fromRGB(255, 255, 255)
	medRing.Transparency = 0.6
	medRing.Thickness = 1.5
	medRing.Parent = medallion
	medallion.Parent = handle.panel

	-- Diamond facet mark. FredokaOne's glyph coverage for U+25C8 can't be verified
	-- without Studio, so we draw a font-independent rotated diamond Frame instead --
	-- guaranteed to render on every device/font fallback.
	local facet = Instance.new("Frame")
	facet.Name = "Facet"
	facet.AnchorPoint = Vector2.new(0.5, 0.5)
	facet.Position = UDim2.fromScale(0.5, 0.5)
	facet.Size = UDim2.fromOffset(9, 9)
	facet.Rotation = 45
	facet.BackgroundColor3 = Color3.fromRGB(150, 104, 40) -- dim gold-brown
	facet.BorderSizePixel = 0
	facet.ZIndex = 4
	local facetCorner = Instance.new("UICorner")
	facetCorner.CornerRadius = UDim.new(0, 2)
	facetCorner.Parent = facet
	facet.Parent = medallion

	balanceCoins = Instance.new("TextLabel")
	balanceCoins.Name = "Coins"
	balanceCoins.BackgroundTransparency = 1
	balanceCoins.AnchorPoint = Vector2.new(0, 0)
	balanceCoins.Position = UDim2.new(0, 34, 0, 0)
	balanceCoins.Size = UDim2.new(1, -34, 0, 16)
	balanceCoins.Font = HudTheme.Font.heading -- FredokaOne bold
	balanceCoins.Text = "0"
	balanceCoins.TextColor3 = HudTheme.Color.textPrimary
	balanceCoins.TextScaled = true
	balanceCoins.TextXAlignment = Enum.TextXAlignment.Left
	balanceCoins.TextYAlignment = Enum.TextYAlignment.Bottom
	balanceCoins.ZIndex = 3
	balanceCoins.Parent = handle.panel

	local coinsSub = Instance.new("TextLabel")
	coinsSub.Name = "CoinsSub"
	coinsSub.BackgroundTransparency = 1
	coinsSub.AnchorPoint = Vector2.new(0, 0)
	coinsSub.Position = UDim2.new(0, 34, 0, 17)
	coinsSub.Size = UDim2.new(1, -34, 0, 8)
	coinsSub.Font = HudTheme.Font.body
	coinsSub.Text = "COINS"
	coinsSub.TextColor3 = Color3.fromRGB(150, 160, 175) -- muted gray
	coinsSub.TextScaled = true
	coinsSub.TextXAlignment = Enum.TextXAlignment.Left
	coinsSub.ZIndex = 3
	coinsSub.Parent = handle.panel

	-- ---- Row 2: cyan level badge + XP progress track/fill ----
	local badge = Instance.new("Frame")
	badge.Name = "LevelBadge"
	badge.AnchorPoint = Vector2.new(0, 1)
	badge.Position = UDim2.new(0, 0, 1, 0)
	badge.Size = UDim2.fromOffset(42, 18)
	badge.BackgroundColor3 = Color3.fromRGB(57, 214, 224) -- cyan
	badge.BorderSizePixel = 0
	badge.ZIndex = 3
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 7)
	badgeCorner.Parent = badge
	badge.Parent = handle.panel

	balanceLevel = Instance.new("TextLabel")
	balanceLevel.Name = "Level"
	balanceLevel.BackgroundTransparency = 1
	balanceLevel.Size = UDim2.fromScale(1, 1)
	balanceLevel.Font = HudTheme.Font.heading
	balanceLevel.Text = "LV 1"
	balanceLevel.TextColor3 = Color3.fromRGB(8, 34, 42) -- dark on cyan
	balanceLevel.TextScaled = true
	balanceLevel.ZIndex = 4
	balanceLevel.Parent = badge
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingTop = UDim.new(0, 3)
	badgePad.PaddingBottom = UDim.new(0, 3)
	badgePad.PaddingLeft = UDim.new(0, 5)
	badgePad.PaddingRight = UDim.new(0, 5)
	badgePad.Parent = balanceLevel

	local xpTrack = Instance.new("Frame")
	xpTrack.Name = "XpTrack"
	xpTrack.AnchorPoint = Vector2.new(0, 1)
	xpTrack.Position = UDim2.new(0, 50, 1, -4) -- centers the 10px track on the 18px badge
	xpTrack.Size = UDim2.new(1, -50, 0, 10)
	xpTrack.BackgroundColor3 = Color3.fromRGB(12, 16, 23)
	xpTrack.BorderSizePixel = 0
	xpTrack.ZIndex = 3
	local xpTrackCorner = Instance.new("UICorner")
	xpTrackCorner.CornerRadius = UDim.new(1, 0)
	xpTrackCorner.Parent = xpTrack
	xpTrack.Parent = handle.panel

	balanceXpFill = Instance.new("Frame")
	balanceXpFill.Name = "Fill"
	balanceXpFill.AnchorPoint = Vector2.new(0, 0.5)
	balanceXpFill.Position = UDim2.fromScale(0, 0.5)
	balanceXpFill.Size = UDim2.fromScale(0, 1) -- width = clamped progress
	balanceXpFill.BackgroundColor3 = Color3.new(1, 1, 1) -- gradient tints it
	balanceXpFill.BorderSizePixel = 0
	balanceXpFill.ZIndex = 4
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = balanceXpFill
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new(Color3.fromRGB(57, 214, 224), Color3.fromRGB(127, 240, 247))
	fillGrad.Parent = balanceXpFill
	balanceXpFill.Parent = xpTrack

	-- ===== End-of-round reward panel (center) =====
	local panel = HudTheme.makePanel(gui, UDim2.fromScale(0.34, 0.22), "center", nil)
	HudTheme.setPanelAccent(panel, "neutral")
	rewardHandle = panel   -- capture the handle so showReward can call setPanelAccent correctly
	rewardRoot = panel.root
	rewardRoot.Visible = false

	local plist = Instance.new("UIListLayout")
	plist.FillDirection = Enum.FillDirection.Vertical
	plist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	plist.VerticalAlignment = Enum.VerticalAlignment.Center
	plist.SortOrder = Enum.SortOrder.LayoutOrder
	plist.Padding = UDim.new(0, 4)
	plist.Parent = panel.panel

	local function panelLine(name, scaleY, order, fontKey)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(0.92, scaleY)
		l.LayoutOrder = order
		l.Text = ""
		HudTheme.styleText(l, fontKey)
		l.Parent = panel.panel
		return l
	end

	rewardLevel = panelLine("RewardLevel", 0.26, 1, "title")
	rewardCoins = panelLine("RewardCoins", 0.22, 2, "heading")
	rewardXp = panelLine("RewardXp", 0.22, 3, "body")

	-- Thin level-bar track + fill at the bottom of the panel.
	local track = Instance.new("Frame")
	track.Name = "LevelBarTrack"
	track.Size = UDim2.fromScale(0.88, 0.12)
	track.LayoutOrder = 4
	track.BackgroundColor3 = HudTheme.Color.panelDark
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track
	track.Parent = panel.panel

	rewardBarFill = Instance.new("Frame")
	rewardBarFill.Name = "Fill"
	rewardBarFill.AnchorPoint = Vector2.new(0, 0.5)
	rewardBarFill.Position = UDim2.fromScale(0, 0.5)
	rewardBarFill.Size = UDim2.fromScale(0, 1)
	rewardBarFill.BackgroundColor3 = HudTheme.Accent.win.top
	rewardBarFill.BorderSizePixel = 0
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = rewardBarFill
	rewardBarFill.Parent = track
end

-- Progression tunables for XpFillModel's injected xpForLevel + the start fraction.
local function progressionOpts()
	return {
		coeff = Config.PROGRESSION_XP_COEFF,
		exp = Config.PROGRESSION_XP_EXP,
		maxLevel = Config.PROGRESSION_MAX_LEVEL,
	}
end

local function setBar(p)
	rewardBarFill.Size = UDim2.fromScale(math.clamp(p, 0, 1), 1)
end

-- The level-up "moment": tick the label, scale-punch the panel, surge the bar color.
local function playLevelUpMoment(newLevel)
	rewardLevel.Text = "Level " .. tostring(newLevel)
	local scale = rewardRoot:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = rewardRoot
	TweenService:Create(
		scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = Config.REWARD_LEVELUP_POP_SCALE }
	):Play()
	task.delay(0.12, function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	rewardBarFill.BackgroundColor3 = Config.REWARD_LEVELUP_FLASH_COLOR
	TweenService:Create(
		rewardBarFill,
		TweenInfo.new(Config.REWARD_LEVELUP_PAUSE_SECONDS),
		{ BackgroundColor3 = HudTheme.Accent.win.top }
	):Play()
end

-- Play the XpFillModel timeline: fill each segment proportionally to its xpSpan over
-- a fixed total time, count the +XP up, and run the level-up moment between segments.
-- `token` gates cancellation (a newer reward replaces animToken). Driven by Heartbeat
-- so the bar fill + number count-up + segment transitions stay in lockstep.
local function playTimeline(token, plan, delta)
	if #plan.segments == 0 or plan.totalSpan <= 0 then
		-- Nothing to animate: rest on the final state immediately.
		setBar(plan.finalProgress)
		rewardLevel.Text = "Level " .. tostring(plan.finalLevel)
		rewardXp.Text = "+" .. tostring(math.max(0, math.floor(delta))) .. " XP"
		return
	end

	local FILL = Config.REWARD_XP_FILL_SECONDS
	local PAUSE = Config.REWARD_LEVELUP_PAUSE_SECONDS
	local fillElapsed = 0 -- cumulative fill time (excludes pauses); drives the +XP count-up

	for i, seg in ipairs(plan.segments) do
		rewardLevel.Text = "Level " .. tostring(seg.level)
		local dur = FILL * (seg.xpSpan / plan.totalSpan)
		local t = 0
		while t < dur do
			if token ~= animToken then return end
			local dt = RunService.Heartbeat:Wait()
			t = math.min(dur, t + dt)
			local f = t / dur
			setBar(seg.fromProgress + (seg.toProgress - seg.fromProgress) * f)
			local xpShown = math.floor(delta * math.min(1, (fillElapsed + t) / FILL))
			rewardXp.Text = "+" .. tostring(xpShown) .. " XP"
		end
		fillElapsed += dur
		if seg.levelUpAfter then
			if token ~= animToken then return end
			playLevelUpMoment(seg.level + 1)
			-- Reposition for the next segment (fresh level at 0) or the final rest
			-- (full at max level, else the start of the next level).
			local nextSeg = plan.segments[i + 1]
			setBar(nextSeg and nextSeg.fromProgress or plan.finalProgress)
			local p = 0
			while p < PAUSE do
				if token ~= animToken then return end
				p += RunService.Heartbeat:Wait()
			end
		end
	end

	if token ~= animToken then return end
	-- Settle exactly on the authoritative final state.
	setBar(plan.finalProgress)
	rewardLevel.Text = "Level " .. tostring(plan.finalLevel)
	rewardXp.Text = "+" .. tostring(math.floor(delta)) .. " XP"
end

local function applyView(view)
	lastView = view
	balanceCoins.Text = withCommas(view.coins or 0)
	balanceLevel.Text = "LV " .. tostring(view.level or 1)
	balanceXpFill.Size = UDim2.fromScale(math.clamp(view.progress or 0, 0, 1), 1)
end

local function showReward(grant)
	local d = RewardScreenModel.display(grant, lastView)
	if not d.visible then
		return
	end

	-- Coins render instantly (XP is the animated focus).
	rewardCoins.Text = d.coinsText

	-- Build the fill timeline from the pre-award snapshot in the payload (self-contained;
	-- independent of ProfileUpdated arrival order). xpForLevel is injected so XpFillModel
	-- stays Roblox-free.
	local start = grant.before
	local opts = progressionOpts()
	local plan = XpFillModel.build(start, grant.xp, {
		maxLevel = opts.maxLevel,
		xpForLevel = function(level)
			return ProgressionModel.xpForLevel(level, opts)
		end,
	})

	-- Initial visual state: start level, start fraction, +0 XP.
	local startProgress
	if start.xpForNext and start.xpForNext > 0 then
		startProgress = start.xpIntoLevel / start.xpForNext
	elseif start.level >= opts.maxLevel then
		startProgress = 1
	else
		startProgress = 0
	end
	rewardLevel.Text = "Level " .. tostring(start.level)
	rewardXp.Text = "+0 XP"
	rewardBarFill.BackgroundColor3 = HudTheme.Accent.win.top
	setBar(startProgress)
	HudTheme.setPanelAccent(rewardHandle, grant.leveledUp and "win" or "neutral")

	rewardRoot.Visible = true
	HudTheme.popIn(rewardRoot)

	-- New reward cancels any running fill + the prior hide (shared token).
	local token = {}
	animToken = token
	hideToken = token
	task.spawn(playTimeline, token, plan, grant.xp)

	-- Keep the panel up for the whole sequence (fill + level-up pauses) plus a readable hold.
	local levelUps = 0
	for _, s in ipairs(plan.segments) do
		if s.levelUpAfter then
			levelUps += 1
		end
	end
	local visibleFor = Config.REWARD_XP_FILL_SECONDS
		+ Config.REWARD_LEVELUP_PAUSE_SECONDS * levelUps
		+ Config.REWARD_PANEL_HOLD_SECONDS
	task.delay(visibleFor, function()
		if hideToken == token then
			rewardRoot.Visible = false
		end
	end)
end

function ClientEconomyHud.start()
	build()
	ProfileUpdated.OnClientEvent:Connect(applyView)
	RewardGranted.OnClientEvent:Connect(showReward)
end

return ClientEconomyHud
