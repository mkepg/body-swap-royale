--[[
	ClientRoundHud -- round-flow bookend banner (Lobby + Results) renderer.
	Location: StarterPlayerScripts/Client/ClientRoundHud  (ModuleScript)

	Draws the keep-arena-visible banner from RoundStateChanged. WHAT to show is the
	pure RoundScreenModel's decision; this module only renders it (kid-friendly skin
	via HudTheme). Also keeps the spectator-camera retarget and a brief "you were
	eliminated" notice (Active-phase only -- the banner owns the screen during
	Lobby/Ended).

	Started once per client (LocalScript lifetime); all event connections live for
	the session, matching ClientSwapHud and SoulController.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoundScreenModel = require(Shared:WaitForChild("RoundScreenModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

local ClientRoundHud = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- A stacked text line inside a panel. scaleY is its share of the panel height.
local function panelLabel(parent, name, scaleY, order, fontKey)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.92, scaleY)
	l.LayoutOrder = order
	l.Text = ""
	l.Visible = false
	HudTheme.styleText(l, fontKey)
	l.Parent = parent
	return l
end

-- Built once in start(); held here so the update closure can reach them.
local bannerHandle, winnerTag, winnerName, title, subtitle
local bottomHandle, bottomText, elim

-- Set a panel's visibility and pop it in only on the hidden->visible edge.
-- (popIn sets UIScale.Scale=0 then we flip Visible in the same frame, so the
-- scale-up renders from 0.)
local function setVisible(root, visible)
	if visible and not root.Visible then
		HudTheme.popIn(root)
	end
	root.Visible = visible
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = HudTheme.DisplayOrder.bookend
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Banner: chunky state-colored panel in the TOP zone.
	bannerHandle = HudTheme.makePanel(gui, UDim2.fromScale(0.6, 0.16), "top", "banner")
	bannerHandle.root.Visible = false

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = bannerHandle.panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = bannerHandle.panel

	-- WINNER pill (yellow, dark text) -- shown only on Ended with a winner.
	winnerTag = Instance.new("TextLabel")
	winnerTag.Name = "WinnerTag"
	winnerTag.Size = UDim2.fromScale(0.42, 0.14)
	winnerTag.BackgroundColor3 = HudTheme.Color.pill
	winnerTag.TextColor3 = HudTheme.Color.pillText
	winnerTag.Font = HudTheme.Font.heading
	winnerTag.TextScaled = true
	winnerTag.Text = "WINNER" -- static text; visibility toggled in applyDisplay
	winnerTag.LayoutOrder = 1
	winnerTag.Visible = false
	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = HudTheme.PillRadius
	tagCorner.Parent = winnerTag
	-- White outline reads better on the dark-text/yellow pill (the dark text
	-- stroke from styleText is used on the white-text labels elsewhere).
	local tagStroke = Instance.new("UIStroke")
	tagStroke.Thickness = HudTheme.TextStrokeThickness
	tagStroke.Color = HudTheme.Color.panelStroke
	tagStroke.Parent = winnerTag
	winnerTag.Parent = bannerHandle.panel

	winnerName = panelLabel(bannerHandle.panel, "WinnerName", 0.26, 2, "title")
	title = panelLabel(bannerHandle.panel, "Title", 0.34, 3, "title")       -- Victory/Defeated/Round over/lobby lines
	subtitle = panelLabel(bannerHandle.panel, "Subtitle", 0.16, 4, "body")  -- "X / N players" in lobby

	-- Bottom line: fixed dark pill in the BOTTOM zone ("Next round in N").
	bottomHandle = HudTheme.makePanel(gui, UDim2.fromScale(0.34, 0.06), "bottom", "bottomLine")
	HudTheme.setPanelFlat(bottomHandle, HudTheme.Color.panelDark)
	bottomHandle.root.Visible = false

	bottomText = Instance.new("TextLabel")
	bottomText.Name = "BottomText"
	bottomText.Size = UDim2.fromScale(0.9, 0.7)
	bottomText.AnchorPoint = Vector2.new(0.5, 0.5)
	bottomText.Position = UDim2.fromScale(0.5, 0.5)
	bottomText.BackgroundTransparency = 1
	bottomText.Text = ""
	HudTheme.styleText(bottomText, "body")
	bottomText.Parent = bottomHandle.panel

	-- Active-only transient notice (red text, no panel) in the NOTICE zone.
	elim = Instance.new("TextLabel")
	elim.Name = "EliminatedNotice"
	elim.Size = UDim2.fromScale(0.6, 0.08)
	elim.BackgroundTransparency = 1
	elim.Text = ""
	elim.Visible = false
	HudTheme.placeInZone(elim, "notice")
	HudTheme.applyMaxSize(elim, "notice")
	HudTheme.styleText(elim, "heading")
	elim.TextColor3 = HudTheme.Accent.lose.top -- red callout
	elim.Parent = gui
end

local function applyDisplay(d)
	-- Banner + bottom pill: set visibility, pop in on the hidden->visible edge.
	setVisible(bannerHandle.root, d.visible)
	local bottomVisible = d.visible and d.bottomText ~= nil
	setVisible(bottomHandle.root, bottomVisible)
	bottomText.Text = d.bottomText or ""

	-- A visible banner (Lobby/Ended) owns the screen, so clear the Active-only
	-- eliminated notice here (keeps applyDisplay self-contained).
	if d.visible then
		elim.Visible = false
	end

	-- Panel fill color follows state (green win / red lose / blue neutral).
	HudTheme.setPanelAccent(bannerHandle, d.accent)

	winnerTag.Visible = d.winnerName ~= nil

	winnerName.Visible = d.winnerName ~= nil
	winnerName.Text = d.winnerName or ""

	title.Visible = d.titleText ~= nil
	title.Text = d.titleText or ""

	subtitle.Visible = d.subtitleText ~= nil
	subtitle.Text = d.subtitleText or ""
end

function ClientRoundHud.start()
	build()

	RoundStateChanged.OnClientEvent:Connect(function(state)
		local d = RoundScreenModel.display(state, {
			localPlayerName = player.Name,
			connectedCount = #Players:GetPlayers(),
			minPlayers = Config.MIN_PLAYERS_TO_START,
		})
		applyDisplay(d) -- clears the Active-only eliminated notice when a banner shows
	end)

	EliminationEvent.OnClientEvent:Connect(function(playerName)
		-- Only while the banner is hidden (Active). Guards a cross-remote race:
		-- if the Ended broadcast lands before this event, the banner is up and
		-- the notice must not cover it.
		if playerName == player.Name and not bannerHandle.root.Visible then
			elim.Text = "You were eliminated"
			elim.Visible = true
		end
	end)

	SpectateBody.OnClientEvent:Connect(function(body)
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = hum
		end
	end)
end

return ClientRoundHud
