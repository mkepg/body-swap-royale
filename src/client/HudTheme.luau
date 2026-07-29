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
	-- The free Soul cyan -- the game's identity accent (equipped state, active tab, level
	-- badge, and the shop mark's spark). Named here so new work has one place to reach for
	-- it; the pre-existing literals in SoulStyles/ClientShopHud/ClientEconomyHud are the
	-- same value and can migrate to this token whenever they're next touched.
	soul = Color3.fromRGB(57, 214, 224),
	soulBright = Color3.fromRGB(186, 250, 255),
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

-- The gold coin "medallion" currency token -- ONE source so the balance readout,
-- the shop header, shop prices and the shop mark all render the identical coin. Returns
-- an unparented sizePx-square Frame; the caller parents + positions it. Facet/ring
-- scale with sizePx so it reads at 14px (a price) or 26px (the readout).
-- `zIndex` is optional: under Sibling ZIndexBehavior the facet must ride ABOVE the disc,
-- so the token owns that relationship (facet = disc + 1) rather than every caller
-- re-deriving it.
function HudTheme.makeCoinMedallion(sizePx, zIndex)
	local med = Instance.new("Frame")
	med.Name = "CoinMedallion"
	med.Size = UDim2.fromOffset(sizePx, sizePx)
	med.BackgroundColor3 = Color3.new(1, 1, 1)
	med.BorderSizePixel = 0
	if zIndex then
		med.ZIndex = zIndex
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = med
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 224, 138), Color3.fromRGB(201, 154, 46))
	grad.Rotation = 45
	grad.Parent = med
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.fromRGB(255, 255, 255)
	ring.Transparency = 0.6
	ring.Thickness = math.max(1, sizePx * 0.058)
	ring.Parent = med
	local facet = Instance.new("Frame")
	facet.Name = "Facet"
	facet.AnchorPoint = Vector2.new(0.5, 0.5)
	facet.Position = UDim2.fromScale(0.5, 0.5)
	facet.Size = UDim2.fromOffset(math.floor(sizePx * 0.35 + 0.5), math.floor(sizePx * 0.35 + 0.5))
	facet.Rotation = 45
	facet.BackgroundColor3 = Color3.fromRGB(150, 104, 40)
	facet.BorderSizePixel = 0
	facet.ZIndex = med.ZIndex + 1
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, math.max(1, math.floor(sizePx * 0.08 + 0.5)))
	fc.Parent = facet
	facet.Parent = med
	return med
end

-- The Soul Shop MARK -- the shop entry point's dedicated icon, drawn from the same gold
-- medallion token as the balance readout and every price, so the button finally speaks the
-- currency language (it used to be two flat gold circles that merged into one blob at
-- 47px -- the pre-token glyph). Composition, and why each piece is there:
--   * TWO coins, not one -- a single medallion IS the balance token; a stack reads "spend".
--   * the front coin sits in a dark cut so the pair can never merge into a blob again.
--   * a cyan soul spark lifting off the stack -- coins buy SOULS, and cyan is the game's
--     identity accent (equipped state, active tab, level badge).
-- Returns an unparented sizePx-square Frame; the caller parents + positions it.
function HudTheme.makeShopMark(sizePx, zIndex)
	local z = zIndex or 1
	local px = function(f) return math.max(4, math.floor(sizePx * f + 0.5)) end

	local root = Instance.new("Frame")
	root.Name = "ShopMark"
	root.Size = UDim2.fromOffset(sizePx, sizePx)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = z

	local function place(inst, sx, sy)
		inst.AnchorPoint = Vector2.new(0.5, 0.5)
		inst.Position = UDim2.fromScale(sx, sy)
		inst.Parent = root
	end

	-- Diagonal read, lower-left to upper-right: coins sit low and the soul lifts off them.
	-- back coin: smaller and set back, so the stack reads as depth not as two siblings
	local back = HudTheme.makeCoinMedallion(px(0.50), z + 1)
	back.Name = "CoinBack"
	place(back, 0.28, 0.46)

	-- dark cut behind the front coin: a disc ringed a hair larger than the coin, in the
	-- panel's own dark, so the front coin is punched cleanly out of the one behind it and
	-- the pair can never merge. The ring scales with the mark -- a fixed pixel offset reads
	-- as a chunky band at 32px and disappears at 128px.
	local frontPx = px(0.58)
	local ring = math.max(2, math.floor(sizePx * 0.045 + 0.5))
	local cut = Instance.new("Frame")
	cut.Name = "Cut"
	cut.Size = UDim2.fromOffset(frontPx + ring * 2, frontPx + ring * 2)
	cut.BackgroundColor3 = HudTheme.Color.panelDark
	cut.BorderSizePixel = 0
	cut.ZIndex = z + 2
	local cutCorner = Instance.new("UICorner")
	cutCorner.CornerRadius = UDim.new(1, 0)
	cutCorner.Parent = cut
	place(cut, 0.52, 0.60)

	local front = HudTheme.makeCoinMedallion(frontPx, z + 3)
	front.Name = "CoinFront"
	place(front, 0.52, 0.60)

	-- The soul: the game's own halo grammar in miniature -- concentric cyan discs falling
	-- off to a bright core, i.e. BUILDERS.classic at icon scale. Deliberately FEATURELESS
	-- (no rim, no facet): next to two detailed gold coins a smooth glowing orb reads as
	-- energy, where a rimmed disc with an inner shape just read as a third coin.
	-- Five layers rather than three: Roblox Frames have no blur, so a soft falloff has to
	-- be stepped, and three steps banded into visible concentric rings -- which is exactly
	-- the coin grammar we are avoiding.
	local SOUL = {
		{ f = 1.00, t = 0.82 }, { f = 0.80, t = 0.64 }, { f = 0.62, t = 0.44 },
		{ f = 0.46, t = 0.22 }, { f = 0.30, t = 0.00 },
	}
	for i, layer in ipairs(SOUL) do
		local d = px(0.42 * layer.f)
		local orb = Instance.new("Frame")
		orb.Name = "Soul" .. i
		orb.Size = UDim2.fromOffset(d, d)
		orb.BackgroundColor3 = i == #SOUL and HudTheme.Color.soulBright or HudTheme.Color.soul
		orb.BackgroundTransparency = layer.t
		orb.BorderSizePixel = 0
		orb.ZIndex = z + 4 + i
		local oc = Instance.new("UICorner")
		oc.CornerRadius = UDim.new(1, 0)
		oc.Parent = orb
		place(orb, 0.78, 0.24)
	end

	return root
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
