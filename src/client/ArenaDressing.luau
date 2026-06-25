--[[
	ArenaDressing (client) -- Layer 2 of the broadcast world: local framing built
	parametrically from an ArenaDescriptor (never from arena internals), so any
	future arena gets dressed by publishing its own descriptor. 100% local cosmetic.

	Slice 1 dressing: spotlight rigs at the footprint corners, a "BODY SWAP ROYALE"
	marquee on the balcony side, and a near ring of soul-orb spectators.

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

local function buildSpotlights(folder, desc)
	local corners = WorldLayout.footprintCorners(
		desc.center.X, desc.center.Z,
		desc.footprint.X, desc.footprint.Y, -- Vector2.Y holds the Z extent
		Config.WORLD_SPOTLIGHT_MARGIN)
	local topY = desc.center.Y + Config.WORLD_SPOTLIGHT_HEIGHT
	for _, c in ipairs(corners) do
		local pole = rigPart(Vector3.new(2, Config.WORLD_SPOTLIGHT_HEIGHT, 2),
			Vector3.new(c.x, desc.center.Y + Config.WORLD_SPOTLIGHT_HEIGHT / 2, c.z),
			Color3.fromRGB(40, 40, 50), Enum.Material.Metal, folder)
		local head = rigPart(Vector3.new(5, 3, 5), Vector3.new(c.x, topY, c.z),
			desc.accent, Enum.Material.Neon, folder)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 75
		light.Range = Config.WORLD_SPOTLIGHT_RANGE
		light.Brightness = Config.WORLD_SPOTLIGHT_BRIGHTNESS
		light.Color = desc.accent
		light.Parent = head
		pole.Name, head.Name = "SpotlightPole", "SpotlightHead"
	end
end

local function buildMarquee(folder, desc)
	-- Place on the balcony side (-Z), facing the arena (+Z). Balcony is at
	-- Config.LOBBY_ORIGIN; sit the marquee just in front of its edge, high up.
	local z = Config.LOBBY_ORIGIN.Z + 6
	local part = rigPart(Config.WORLD_MARQUEE_SIZE,
		Vector3.new(0, desc.center.Y + Config.WORLD_MARQUEE_HEIGHT, z),
		Color3.fromRGB(20, 16, 36), Enum.Material.SmoothPlastic, folder)
	part.Name = "Marquee"

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- +Z face, toward the arena
	gui.CanvasSize = Vector2.new(600, 120)
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = Config.WORLD_MARQUEE_TEXT
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 216, 77)
	label.Parent = gui
end

local function buildNearOrbs(folder, desc)
	local palette = Config.SOUL_PALETTE
	local pts = WorldLayout.ring(desc.center.X, desc.center.Z,
		Config.WORLD_NEAR_ORB_RADIUS, Config.WORLD_NEAR_ORB_COUNT)
	for i, pt in ipairs(pts) do
		local orb = rigPart(
			Vector3.new(Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE),
			Vector3.new(pt.x, desc.center.Y + Config.WORLD_NEAR_ORB_Y, pt.z),
			palette[WorldLayout.paletteIndex(i, #palette)], Enum.Material.Neon, folder)
		orb.Shape = Enum.PartType.Ball
		orb.Name = "NearOrb"
	end
end

function ArenaDressing.start()
	local folder = newFolder()
	local desc = ArenaDescriptor.hex()
	buildSpotlights(folder, desc)
	buildMarquee(folder, desc)
	buildNearOrbs(folder, desc)
end

return ArenaDressing
