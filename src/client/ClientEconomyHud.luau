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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardScreenModel = require(Shared:WaitForChild("RewardScreenModel"))
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
local PANEL_VISIBLE_SECONDS = 4.5
local hideToken = nil

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
	rewardLevel.Text = d.levelText
	rewardCoins.Text = d.coinsText
	rewardXp.Text = d.xpText
	rewardBarFill.Size = UDim2.fromScale(math.clamp(d.levelBarProgress or 0, 0, 1), 1)
	HudTheme.setPanelAccent(rewardHandle, d.leveledUp and "win" or "neutral")
	rewardRoot.Visible = true
	HudTheme.popIn(rewardRoot)

	-- Auto-hide after a few seconds; a newer reward cancels the previous timer.
	local token = {}
	hideToken = token
	task.delay(PANEL_VISIBLE_SECONDS, function()
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
