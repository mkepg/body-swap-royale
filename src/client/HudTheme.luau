--[[
	HudTheme -- the single source of truth for the on-screen HUD look.
	Location: StarterPlayerScripts/Client/HudTheme  (ModuleScript; child of Client)

	Client-only presentation constants + small helpers shared by ClientRoundHud
	and ClientSwapHud, so HUD zones / size caps / fonts / colors / panel styling
	live in ONE place and can't drift element-by-element. Holds Roblox types
	(Color3/Enum/UDim/Instance), so it is NOT lune-tested -- the pure decision
	modules (RoundScreenModel/SwapTelegraphModel) stay Roblox-free and own the
	logic; this module only styles. Kid-friendly skin: chunky, bright, rounded.

	Maps the semantic accent strings RoundScreenModel returns
	("neutral" | "win" | "lose") to concrete panel colors.
--]]

local TweenService = game:GetService("TweenService")

local HudTheme = {}

HudTheme.Font = {
	title = Enum.Font.FredokaOne,
	heading = Enum.Font.FredokaOne,
	body = Enum.Font.GothamMedium,
}

HudTheme.Color = {
	textPrimary = Color3.fromRGB(255, 255, 255),
	textStroke = Color3.fromRGB(20, 24, 31),
	panelStroke = Color3.fromRGB(255, 255, 255),
	shadow = Color3.fromRGB(0, 0, 0),
	pill = Color3.fromRGB(255, 210, 63),
	pillText = Color3.fromRGB(90, 61, 0),
	panelDark = Color3.fromRGB(17, 22, 31),
}

-- semantic accent -> panel gradient stops { top, bottom }
HudTheme.Accent = {
	neutral = { top = Color3.fromRGB(58, 160, 240), bottom = Color3.fromRGB(47, 127, 208) },
	win = { top = Color3.fromRGB(56, 210, 122), bottom = Color3.fromRGB(30, 167, 92) },
	lose = { top = Color3.fromRGB(240, 88, 78), bottom = Color3.fromRGB(200, 58, 50) },
}

-- pixel max sizes (the bottom pill never exceeds the banner)
HudTheme.Cap = {
	banner = Vector2.new(340, 150),
	bottomLine = Vector2.new(240, 66),
	notice = Vector2.new(320, 80),
	timer = Vector2.new(120, 76),
}

-- named screen zones: { anchor, position }
HudTheme.Zone = {
	top = { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 14) },
	topTimer = { anchor = Vector2.new(0.5, 0), position = UDim2.fromScale(0.5, 0.04) },
	center = { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.40) },
	notice = { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.62) },
	bottom = { anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 0.97, 0) },
}

HudTheme.Radius = UDim.new(0, 18)
HudTheme.PanelStrokeThickness = 4
HudTheme.TextStrokeThickness = 2
HudTheme.ShadowOffset = 6
HudTheme.PopInTime = 0.25
HudTheme.DisplayOrder = { swap = 5, bookend = 10 }

-- Place a GUI object into a named zone (anchor + position).
function HudTheme.placeInZone(guiObject, zoneKey)
	local z = HudTheme.Zone[zoneKey]
	guiObject.AnchorPoint = z.anchor
	guiObject.Position = z.position
end

-- Cap a GUI object's pixel size so it never balloons on desktop/ultrawide.
function HudTheme.applyMaxSize(guiObject, capKey)
	local c = Instance.new("UISizeConstraint")
	c.MaxSize = HudTheme.Cap[capKey]
	c.Parent = guiObject
	return c
end

-- Consistent readable text: themed font, white fill, dark outline, scaled.
function HudTheme.styleText(label, fontKey)
	label.Font = HudTheme.Font[fontKey]
	label.TextColor3 = HudTheme.Color.textPrimary
	label.TextScaled = true
	label.TextStrokeTransparency = 1 -- the UIStroke below replaces the built-in stroke
	local s = Instance.new("UIStroke")
	s.Thickness = HudTheme.TextStrokeThickness
	s.Color = HudTheme.Color.textStroke
	s.Parent = label
	return s
end

-- Build a chunky themed panel (root > shadow + panel) in `parent`, sized `size`,
-- placed in `zoneKey` and capped by `capKey`. Parent your content into `.panel`;
-- recolor via setPanelAccent/setPanelFlat; pop it in via popIn(handle.root).
-- The shadow is an offset dark sibling BEHIND the panel (Sibling ZIndexBehavior).
function HudTheme.makePanel(parent, size, zoneKey, capKey)
	local root = Instance.new("Frame")
	root.Name = "PanelRoot"
	root.BackgroundTransparency = 1
	root.Size = size
	HudTheme.placeInZone(root, zoneKey)
	if capKey then
		HudTheme.applyMaxSize(root, capKey)
	end
	root.Parent = parent

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.new(0, 0, 0, HudTheme.ShadowOffset)
	shadow.BackgroundColor3 = HudTheme.Color.shadow
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	local sc = Instance.new("UICorner")
	sc.CornerRadius = HudTheme.Radius
	sc.Parent = shadow
	shadow.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.new(1, 1, 1) -- white base; the UIGradient tints it
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	local pc = Instance.new("UICorner")
	pc.CornerRadius = HudTheme.Radius
	pc.Parent = panel
	local ps = Instance.new("UIStroke")
	ps.Thickness = HudTheme.PanelStrokeThickness
	ps.Color = HudTheme.Color.panelStroke
	ps.Parent = panel
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = panel
	panel.Parent = root

	return { root = root, panel = panel, gradient = gradient }
end

-- Color the panel from a semantic accent (top->bottom gradient).
function HudTheme.setPanelAccent(handle, accentKey)
	local a = HudTheme.Accent[accentKey] or HudTheme.Accent.neutral
	handle.gradient.Color = ColorSequence.new(a.top, a.bottom)
end

-- Color the panel a single flat color (used for the neutral dark bottom pill).
function HudTheme.setPanelFlat(handle, color)
	handle.gradient.Color = ColorSequence.new(color)
end

-- Bouncy entrance: scale the whole panel 0 -> 1 with Back/Out.
function HudTheme.popIn(root)
	local scale = root:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = root
	end
	scale.Scale = 0
	TweenService:Create(
		scale,
		TweenInfo.new(HudTheme.PopInTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

return HudTheme
