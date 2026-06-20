--[[
	ClientRoundHud -- round-flow bookend banner (Lobby + Results) renderer.
	Location: StarterPlayerScripts/Client/ClientRoundHud  (ModuleScript)

	Draws the keep-arena-visible banner from RoundStateChanged. WHAT to show is the
	pure RoundScreenModel's decision; this module only renders it and maps the
	semantic accent to a Color3. Also keeps the spectator-camera retarget and a
	brief "you were eliminated" notice (Active-phase only -- the banner owns the
	screen during Lobby/Ended).

	Started once per client (LocalScript lifetime); all event connections live for
	the session, matching the pattern used by ClientSwapHud and SoulController.
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

local ClientRoundHud = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- accent -> Color3 (lives in the renderer; the pure model stays Roblox-free).
local ACCENT = {
	neutral = Color3.fromRGB(180, 200, 220),
	win = Color3.fromRGB(45, 212, 191),
	lose = Color3.fromRGB(220, 90, 90),
}

-- A stacked text line inside the banner. scaleY is its share of the banner height.
local function bannerLabel(parent, name, scaleY, order)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.96, scaleY)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.LayoutOrder = order
	l.Text = ""
	l.Visible = false
	l.Parent = parent
	return l
end

-- Built once in start(); held here so the update closure can reach them.
local banner, winnerTag, winnerName, title, subtitle, stroke, bottomLabel, elim

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Top banner (keep-arena-visible): semi-transparent dark panel + accent stroke.
	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 12)
	banner.Size = UDim2.fromScale(0.94, 0.2)
	banner.BackgroundColor3 = Color3.fromRGB(17, 22, 31)
	banner.BackgroundTransparency = 0.25
	banner.Visible = false
	banner.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner

	stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = ACCENT.neutral
	stroke.Parent = banner

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = banner

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = banner

	-- WINNER mini-label + the winner's name (shown only on Ended with a winner).
	winnerTag = bannerLabel(banner, "WinnerTag", 0.16, 1)
	winnerTag.Text = "WINNER" -- static label text; only its visibility is toggled in applyDisplay
	winnerTag.TextColor3 = Color3.fromRGB(150, 170, 190)

	winnerName = bannerLabel(banner, "WinnerName", 0.30, 2)
	title = bannerLabel(banner, "Title", 0.36, 3)       -- Waiting.../Round starting.../Victory/Defeated
	subtitle = bannerLabel(banner, "Subtitle", 0.18, 4) -- "X / N players" in lobby

	-- Bottom line: "Next round in N" on the Results screen.
	bottomLabel = Instance.new("TextLabel")
	bottomLabel.Name = "BottomLine"
	bottomLabel.AnchorPoint = Vector2.new(0.5, 1)
	bottomLabel.Position = UDim2.fromScale(0.5, 0.97)
	bottomLabel.Size = UDim2.fromScale(0.5, 0.05)
	bottomLabel.BackgroundColor3 = Color3.fromRGB(17, 22, 31)
	bottomLabel.BackgroundTransparency = 0.4
	bottomLabel.Font = Enum.Font.GothamMedium
	bottomLabel.TextScaled = true
	bottomLabel.TextColor3 = Color3.fromRGB(223, 238, 238)
	bottomLabel.TextStrokeTransparency = 0.5
	bottomLabel.Text = ""
	bottomLabel.Visible = false
	bottomLabel.Parent = gui

	-- Active-only transient notice when THIS client is eliminated.
	elim = Instance.new("TextLabel")
	elim.Name = "EliminatedNotice"
	elim.AnchorPoint = Vector2.new(0.5, 0.5)
	elim.Position = UDim2.fromScale(0.5, 0.5)
	elim.Size = UDim2.fromScale(0.6, 0.08)
	elim.BackgroundTransparency = 1
	elim.Font = Enum.Font.GothamBold
	elim.TextScaled = true
	elim.TextColor3 = Color3.fromRGB(220, 90, 90)
	elim.TextStrokeTransparency = 0.3
	elim.Text = ""
	elim.Visible = false
	elim.Parent = gui
end

local function applyDisplay(d)
	banner.Visible = d.visible
	bottomLabel.Visible = d.visible and d.bottomText ~= nil
	bottomLabel.Text = d.bottomText or ""

	local accent = ACCENT[d.accent] or ACCENT.neutral
	stroke.Color = accent

	winnerTag.Visible = d.winnerName ~= nil
	winnerName.Visible = d.winnerName ~= nil
	winnerName.Text = d.winnerName or ""
	winnerName.TextColor3 = accent

	title.Visible = d.titleText ~= nil
	title.Text = d.titleText or ""
	title.TextColor3 = (d.accent == "neutral") and Color3.new(1, 1, 1) or accent

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
		if state.phase ~= "Active" then
			elim.Visible = false -- the eliminated notice is Active-phase only
		end
		applyDisplay(d)
	end)

	EliminationEvent.OnClientEvent:Connect(function(playerName)
		if playerName == player.Name then
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
