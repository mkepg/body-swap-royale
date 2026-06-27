--[[
	ArenaDressing (client) -- Layer 2 of the broadcast world: local framing built
	parametrically from an ArenaDescriptor (never from arena internals), so any
	future arena gets dressed by publishing its own descriptor. 100% local cosmetic.

	Per-floor dressing: a floor-colored glowing EDGE TRIM hugging each floor's rim
	(WORLD_TRIM_SEGMENTS Neon tangent bars on a footprint-derived ring; every floor
	glows by Neon alone, uniformly -- no real PointLights), and a framed
	"BODY SWAP ROYALE" marquee header at the balcony's arena-facing edge.

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

-- Per-floor EDGE TRIM: a floor-colored glowing rim hugging each floor's edge,
-- built as WORLD_TRIM_SEGMENTS thin Neon tangent bars around a ring derived from
-- the descriptor footprint (radius = footprint.X/2 + margin) -- one coherent rim
-- per floor (replaces the old corner torches + soul-orb rings). The ring sits
-- OUTSIDE the outermost tiles, so eroding tiles never reveal a glowing plate.
-- Every floor glows by Neon alone -- uniform across all floors, no real
-- PointLights (matches the deeper floors' style; mobile-friendly).
local function buildFloorTrim(folder, desc)
	local segs = Config.WORLD_TRIM_SEGMENTS
	local radius = desc.footprint.X / 2 + Config.WORLD_TRIM_MARGIN
	local pts = WorldLayout.ring(desc.center.X, desc.center.Z, radius, segs)
	-- bar length from the chord between adjacent ring points (slack closes the rim)
	local chord = 2 * radius * math.sin(math.pi / segs)
	local barLen = chord * Config.WORLD_TRIM_LENGTH_SLACK
	for _, lv in ipairs(desc.levels) do
		local y = lv.y + Config.WORLD_TRIM_Y
		for i, pt in ipairs(pts) do
			local nxt = pts[(i % segs) + 1]
			local here = Vector3.new(pt.x, y, pt.z)
			local bar = rigPart(
				Vector3.new(Config.WORLD_TRIM_DEPTH, Config.WORLD_TRIM_HEIGHT, barLen),
				here, lv.color, Enum.Material.Neon, folder)
			bar.Name = "FloorTrim"
			-- point the bar's long (Z) axis along the tangent toward the next point
			bar.CFrame = CFrame.lookAt(here, Vector3.new(nxt.x, y, nxt.z))
		end
	end
end

-- Framed marquee header floating clear above the lobby disc's arena-facing edge,
-- facing the waiting players (-Z Front face). Raised above the rim barrier and nudged
-- toward the arena so it doesn't touch the lobby structure. Built from lobby Config.
local function buildBanner(folder)
	local mountZ = Config.LOBBY_ORIGIN.Z + Config.LOBBY_DISC_RADIUS + Config.WORLD_BANNER_FORWARD
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
	buildFloorTrim(folder, desc)
	buildBanner(folder)
end

return ArenaDressing
