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

local balanceCoins, balanceLevel       -- persistent readout labels
local rewardRoot, rewardCoins, rewardXp, rewardLevel, rewardBarFill -- reward panel
local rewardHandle                     -- makePanel handle; setPanelAccent needs the table, not a Frame
local hideToken = nil  -- generation token: a newer reward cancels the prior hide
local animToken = nil  -- same token gates the running fill coroutine (cancel-on-retrigger)

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EconomyHud"
	gui.ResetOnSpawn = false
	-- Respect the topbar inset so the top-left balance panel below sits BELOW
	-- Roblox's menu/unibar button on every device. The engine computes the inset
	-- per-device (topbar height + notch/safe-area), which a fixed or scale offset
	-- can't do reliably. The centered reward panel is unaffected (it just centers
	-- within the inset-reduced area).
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = HudTheme.DisplayOrder.bookend -- same layer as the results banner
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ===== Persistent Coins/Level readout (top-left, below the topbar inset) =====
	-- Pinned top-left with a small fixed margin. Because the ScreenGui RESPECTS the
	-- GUI inset (IgnoreGuiInset = false above), (0,14)/(0,14) is measured from just
	-- below Roblox's topbar -- clearing the top-left menu/unibar button on phone,
	-- tablet, and desktop alike. We deliberately avoid the other corners: top-right
	-- (default CoreGui player list), top-center (the round banner), and the bottom
	-- corners (mobile joystick/jump).
	local handle = HudTheme.makePanel(gui, UDim2.fromScale(0.16, 0.07), "top", nil)
	HudTheme.setPanelFlat(handle, HudTheme.Color.panelDark)
	handle.root.AnchorPoint = Vector2.new(0, 0)
	handle.root.Position = UDim2.new(0, 14, 0, 14)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = handle.panel

	balanceCoins = Instance.new("TextLabel")
	balanceCoins.Name = "Coins"
	balanceCoins.BackgroundTransparency = 1
	balanceCoins.Size = UDim2.fromScale(0.92, 0.55)
	balanceCoins.LayoutOrder = 1
	balanceCoins.Text = "0 Coins"
	HudTheme.styleText(balanceCoins, "heading")
	balanceCoins.Parent = handle.panel

	balanceLevel = Instance.new("TextLabel")
	balanceLevel.Name = "Level"
	balanceLevel.BackgroundTransparency = 1
	balanceLevel.Size = UDim2.fromScale(0.92, 0.40)
	balanceLevel.LayoutOrder = 2
	balanceLevel.Text = "Level 1"
	HudTheme.styleText(balanceLevel, "body")
	balanceLevel.Parent = handle.panel

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
	balanceCoins.Text = string.format("%d Coins", view.coins)
	balanceLevel.Text = "Level " .. tostring(view.level)
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
