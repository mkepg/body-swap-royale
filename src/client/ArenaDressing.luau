--[[
	ArenaDressing (client) -- Layer 2 of the broadcast world: local framing built
	parametrically from an ArenaDescriptor (never from arena internals), so any
	future arena gets dressed by publishing its own descriptor. 100% local cosmetic.

	Per-floor dressing: short torches at every level's footprint corners (Neon head
	tinted to the floor color; a real PointLight + flame only on the top
	WORLD_TORCH_LIT_FLOORS floors), a soul-orb ring per floor, and a framed
	"BODY SWAP ROYALE" marquee header on posts at the balcony's arena-facing edge.

	Location: StarterPlayerScripts/Client/ArenaDressing (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local ArenaDescriptor = require(Shared:WaitForChild("ArenaDescriptor"))

local ArenaDressing = {}

local function newFolder()
	local f = workspace:FindFirstChild("ArenaDressing")
	if f then f:Destroy() end
	f = Instance.new("Folder")
	f.Name = "ArenaDressing"
	f.Parent = workspace
	return f
end

local function rigPart(size, pos, color, material, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Parent = parent
	return p
end

-- One short torch: dark post + Neon head tinted to the floor color (all floors).
-- `lit` floors additionally get a real floor-colored PointLight + a low-rate flame.
local function buildTorch(folder, x, z, baseY, color, lit)
	local postH = Config.WORLD_TORCH_POST_HEIGHT
	local post = rigPart(Vector3.new(1.5, postH, 1.5),
		Vector3.new(x, baseY + postH / 2, z),
		Color3.fromRGB(40, 40, 50), Enum.Material.Metal, folder)
	post.Name = "TorchPost"

	local hs = Config.WORLD_TORCH_HEAD_SIZE
	local head = rigPart(Vector3.new(hs, hs, hs),
		Vector3.new(x, baseY + postH + hs / 2, z),
		color, Enum.Material.Neon, folder)
	head.Name = "TorchHead"

	if lit then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = Config.WORLD_TORCH_LIGHT_RANGE
		light.Brightness = Config.WORLD_TORCH_LIGHT_BRIGHTNESS
		light.Parent = head

		local flame = Instance.new("ParticleEmitter")
		flame.Color = ColorSequence.new(color)
		flame.Rate = Config.WORLD_TORCH_FLAME_RATE
		flame.Lifetime = NumberRange.new(0.5, 0.9)
		flame.Speed = NumberRange.new(2, 4)
		flame.Size = NumberSequence.new(1.2, 0)
		flame.Transparency = NumberSequence.new(0.2, 1)
		flame.LightEmission = 1
		flame.Parent = head
	end
end

-- 4 torches at the footprint corners of every level; only the top
-- WORLD_TORCH_LIT_FLOORS levels get a real light + flame.
local function buildTorches(folder, desc)
	-- Corners are level-invariant (depend only on center/footprint/margin); compute once.
	local corners = WorldLayout.footprintCorners(
		desc.center.X, desc.center.Z, desc.footprint.X, desc.footprint.Y,
		Config.WORLD_TORCH_MARGIN)
	for i, lv in ipairs(desc.levels) do
		local lit = i <= Config.WORLD_TORCH_LIT_FLOORS
		for _, c in ipairs(corners) do
			buildTorch(folder, c.x, c.z, lv.y, lv.color, lit)
		end
	end
end

-- A soul-palette orb ring around every level (distinct from the floor-colored torches).
local function buildOrbRings(folder, desc)
	local palette = Config.SOUL_PALETTE
	for _, lv in ipairs(desc.levels) do
		local pts = WorldLayout.ring(desc.center.X, desc.center.Z,
			Config.WORLD_NEAR_ORB_RADIUS, Config.WORLD_NEAR_ORB_COUNT)
		for i, pt in ipairs(pts) do
			local orb = rigPart(
				Vector3.new(Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE),
				Vector3.new(pt.x, lv.y + Config.WORLD_NEAR_ORB_Y, pt.z),
				palette[WorldLayout.paletteIndex(i, #palette)], Enum.Material.Neon, folder)
			orb.Shape = Enum.PartType.Ball
			orb.Name = "NearOrb"
		end
	end
end

-- Framed marquee header floating clear above the balcony's arena-facing edge,
-- facing the waiting players (-Z Front face). Raised above the railing and nudged
-- toward the arena so it doesn't touch the lobby structure. Built from lobby Config.
local function buildBanner(folder)
	local mountZ = Config.LOBBY_ORIGIN.Z + Config.LOBBY_PAD_SIZE.Z / 2 + Config.WORLD_BANNER_FORWARD
	local y = Config.LOBBY_ORIGIN.Y + Config.WORLD_BANNER_HEIGHT
	local panel = rigPart(Config.WORLD_BANNER_SIZE,
		Vector3.new(0, y, mountZ),
		Config.WORLD_BANNER_BG_BOTTOM, Enum.Material.SmoothPlastic, folder)
	panel.Name = "Banner"
	-- Hide the square part itself: only the rounded SurfaceGui frame should show, so
	-- the part's sharp dark corners don't protrude past the rounded amber border.
	panel.Transparency = 1

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- -Z, toward the balcony players
	gui.CanvasSize = Vector2.new(640, 160) -- 4:1 matches the 64x16 panel
	gui.LightInfluence = 0 -- render at full brightness regardless of the dusk grade
	gui.Parent = panel

	-- Inset + centered so the rounded frame and its stroke sit fully inside the
	-- canvas (no edge clipping); with the part transparent, the margin shows sky.
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.96, 0.9)
	frame.BackgroundColor3 = Config.WORLD_BANNER_BG_TOP
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.14, 0)
	corner.Parent = frame
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Config.WORLD_BANNER_BG_TOP, Config.WORLD_BANNER_BG_BOTTOM)
	grad.Rotation = 90
	grad.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.WORLD_BANNER_FRAME_COLOR
	stroke.Thickness = 6
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.9, 0.52)
	title.Position = UDim2.fromScale(0.05, 0.34)
	title.BackgroundTransparency = 1
	title.Text = Config.WORLD_BANNER_TEXT
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Config.WORLD_BANNER_TEXT_COLOR
	title.Parent = frame
	local tstroke = Instance.new("UIStroke")
	tstroke.Color = Color3.fromRGB(60, 20, 10)
	tstroke.Thickness = 2
	tstroke.Parent = title

	local pill = Instance.new("TextLabel")
	pill.Size = UDim2.fromScale(0.3, 0.16)
	pill.Position = UDim2.fromScale(0.35, 0.08)
	pill.BackgroundColor3 = Color3.fromRGB(255, 61, 139)
	pill.Text = "★ ON AIR ★"
	pill.Font = Enum.Font.GothamBold
	pill.TextScaled = true
	pill.TextColor3 = Color3.new(1, 1, 1)
	pill.Parent = frame
	local pcorner = Instance.new("UICorner")
	pcorner.CornerRadius = UDim.new(0.5, 0)
	pcorner.Parent = pill
end

function ArenaDressing.start()
	local folder = newFolder()
	local desc = ArenaDescriptor.validate(ArenaDescriptor.hex())
	buildTorches(folder, desc)
	buildOrbRings(folder, desc)
	buildBanner(folder)
end

return ArenaDressing
