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
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudZoneModel = require(ReplicatedStorage.Shared.HudZoneModel)

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
	panelDark = Color3.fromRGB(17, 22, 31),
}

-- semantic accent -> panel gradient stops { top, bottom }
HudTheme.Accent = {
	neutral = { top = Color3.fromRGB(58, 160, 240), bottom = Color3.fromRGB(47, 127, 208) },
	win = { top = Color3.fromRGB(56, 210, 122), bottom = Color3.fromRGB(30, 167, 92) },
	lose = { top = Color3.fromRGB(240, 88, 78), bottom = Color3.fromRGB(200, 58, 50) },
}

-- pixel max sizes (static caps; the banner's cap is NOT here -- it is
-- viewport-derived via HudZoneModel.bannerCap and re-applied on viewport change)
HudTheme.Cap = {
	bottomLine = Vector2.new(210, 50),
	notice = Vector2.new(320, 80),
	timer = Vector2.new(120, 76),
}

HudTheme.Radius = UDim.new(0, 18)
HudTheme.PanelStrokeThickness = 4
HudTheme.TextStrokeThickness = 2
HudTheme.ShadowOffset = 6
HudTheme.PopInTime = 0.25
HudTheme.DisplayOrder = { swap = 5, bookend = 10 }

-- Zones are computed from viewport + Roblox top inset (HudZoneModel) and every
-- placed object is re-placed when either changes -- the safe-area layer (spec §6.3).
-- STRONG tables (not weak-keyed): Roblox Instances in a weak-keyed Lua table are
-- collected once no Lua ref remains even while still parented in the DataModel --
-- a consumer that discards applyMaxSize's return (as makePanel does) would silently
-- lose re-placement. This happened live: the banner's UISizeConstraint fell out of
-- a weak `placedCaps`, so replaceAll() re-capped nothing and the boot-time (0,0)
-- cap (see currentViewport's guard below) stuck forever. We purge dead entries
-- ourselves in replaceAll's sweep instead (Parent == nil), keyed off Destroy() --
-- the real lifecycle end. NOTE: an object temporarily unparented then reparented
-- will have been purged in the meantime and won't be tracked again automatically;
-- acceptable, since current consumers never unparent (only Destroy).
local placed = {} -- [guiObject] = zoneKey
local placedCaps = {} -- [UISizeConstraint] = true (banner caps)

local function currentViewport()
	local cam = workspace.CurrentCamera
	local size = cam and cam.ViewportSize or Vector2.new(1280, 720)
	-- Boot-time ViewportSize is (1,1) before the camera's first render; treat it
	-- as "not ready yet" and fall back, or bannerCap would floor to a 0-size cap.
	if size.X <= 1 or size.Y <= 1 then
		size = Vector2.new(1280, 720)
	end
	local inset = GuiService:GetGuiInset()
	return { w = size.X, h = size.Y, insetTop = inset.Y }
end

local function zoneData(zoneKey)
	return HudZoneModel.zones(currentViewport())[zoneKey]
end

-- Place a GUI object into a named zone (anchor + position).
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
		else
			placed[guiObject] = nil
		end
	end
	local cap = HudZoneModel.bannerCap(currentViewport())
	for constraint in pairs(placedCaps) do
		if constraint.Parent then
			constraint.MaxSize = Vector2.new(cap.w, cap.h)
		else
			placedCaps[constraint] = nil
		end
	end
end

-- Cap a GUI object's pixel size so it never balloons on desktop/ultrawide. The
-- banner cap is viewport-derived (shrinks on short screens) and re-applied on
-- viewport change; other caps stay static from HudTheme.Cap.
function HudTheme.applyMaxSize(guiObject, capKey)
	local c = Instance.new("UISizeConstraint")
	if capKey == "banner" then
		local cap = HudZoneModel.bannerCap(currentViewport())
		c.MaxSize = Vector2.new(cap.w, cap.h)
		placedCaps[c] = true
	else
		c.MaxSize = HudTheme.Cap[capKey]
	end
	c.Parent = guiObject
	return c
end

-- Consistent readable text: themed font, white fill, dark outline, scaled.
function HudTheme.styleText(label, fontKey)
	label.Font = HudTheme.Font[fontKey]
	label.TextColor3 = HudTheme.Color.textPrimary
	label.TextScaled = true
	label.TextStrokeTransparency = 1 -- the UIStroke below replaces the built-in stroke
	local s = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
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

	-- The gradient starts white-on-white; the caller MUST call setPanelAccent or
	-- setPanelFlat before making root visible, or the panel renders plain white.
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

-- Re-place on viewport change; the camera can be replaced, so rebind (no
-- listener stacking -- same pattern as InputController's viewport handling).
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

return HudTheme
