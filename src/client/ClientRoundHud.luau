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
local bannerHandle, title, subtitle
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
	-- Sibling so nested labels draw in front of the opaque Panel they live in
	-- (Global would render them behind it by ZIndex, hiding the text).
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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
	layout.Padding = UDim.new(0, 6) -- breathing room between the two lines
	layout.Parent = bannerHandle.panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = bannerHandle.panel

	-- Two stacked lines only -> roomy and consistent with the lobby look.
	-- Results: outcome word (hero) over a name line. Lobby: status over count.
	-- Title is the hero. FredokaOne sits small inside its box, so give it a big
	-- share of the panel height (and keep the bottom pill smaller) so the outcome
	-- word clearly dominates "Next round in N".
	title = panelLabel(bannerHandle.panel, "Title", 0.54, 1, "title")      -- VICTORY/DEFEATED/Round over, or lobby status
	title.RichText = true -- lets the dot animation reserve invisible trailing dots
	subtitle = panelLabel(bannerHandle.panel, "Subtitle", 0.20, 2, "body") -- winner/loser name line, or "X / N players"

	-- Bottom line: fixed dark pill in the BOTTOM zone ("Next round in N").
	bottomHandle = HudTheme.makePanel(gui, UDim2.fromScale(0.3, 0.055), "bottom", "bottomLine")
	HudTheme.setPanelFlat(bottomHandle, HudTheme.Color.panelDark)
	bottomHandle.root.Visible = false

	bottomText = Instance.new("TextLabel")
	bottomText.Name = "BottomText"
	bottomText.Size = UDim2.fromScale(0.84, 0.58)
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

-- Animated trailing "..." for the lobby wait line. The unlit dots are kept in the
-- string (so the title's width never changes) but rendered fully transparent --
-- fill AND stroke, since the title carries a UIStroke -- via RichText. Because the
-- centered title is TextScaled, reserving the full "..." width every frame is what
-- keeps it from resizing, shifting, or jittering as the dots cycle.
local DOT_STEP = 0.45 -- seconds between dot frames (0 -> . -> .. -> ... -> loop)
local INVIS_OPEN = '<font transparency="1"><stroke transparency="1">'
local INVIS_CLOSE = "</stroke></font>"

local dotThread -- running animation coroutine, or nil
local dotBase -- the base text currently being animated, or nil (de-dupes restarts)

local function stopDotAnim()
	if dotThread then
		task.cancel(dotThread)
		dotThread = nil
	end
	dotBase = nil
end

local function startDotAnim(baseText)
	if dotBase == baseText then
		return -- already animating this exact line; don't reset the cycle
	end
	stopDotAnim()
	dotBase = baseText
	dotThread = task.spawn(function()
		local shown = 0
		while true do
			local lit = string.rep(".", shown)
			local reserved = string.rep(".", 3 - shown)
			title.Text = baseText .. lit .. INVIS_OPEN .. reserved .. INVIS_CLOSE
			shown = (shown + 1) % 4
			task.wait(DOT_STEP)
		end
	end)
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

	-- Hero line: the outcome word (Victory/Defeated/Round over) or lobby status.
	-- The below-minimum lobby wait animates a trailing "..."; every other line is
	-- static, so stop any running animation before setting plain text.
	title.Visible = d.titleText ~= nil
	if d.titleAnimateDots and d.titleText ~= nil then
		startDotAnim(d.titleText)
	else
		stopDotAnim()
		title.Text = d.titleText or ""
	end

	-- Sub line: on a results banner, the name -- your own name on a win,
	-- "Winner: X" on a loss; otherwise the lobby's player count.
	local subText = d.subtitleText
	if d.winnerName then
		subText = (d.accent == "win") and d.winnerName or ("Winner: " .. d.winnerName)
	end
	subtitle.Visible = subText ~= nil
	subtitle.Text = subText or ""
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
