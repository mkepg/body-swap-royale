--[[
	LobbyStage (client) -- World Slice 2: redresses the between-round lobby balcony
	into a festival grandstand stage. 100% local cosmetic, ADD-ONLY: the load-bearing
	LobbyArea geometry (platform / walls / glass railing) is server-owned and untouched;
	every part built here is non-colliding/non-querying/shadow-less, so nothing can
	become a foothold over the railing.

	"Magic-Hour Fair": warm-gold festoon string-lights (bulbs on a hung wire) + bunting
	against the cool dusk/aurora sky. Two small soul-orb clusters at the pit-view edges
	cheer on eliminations/wins (reusing WorldShell's decaying-impulse pattern); the
	distant WorldShell crowd carries the rest. Hybrid assets fall back to code when the
	Config asset fields are blank.

	Location: StarterPlayerScripts/Client/LobbyStage (ModuleScript)
	Connections are session-lifetime (matches WorldShell/ArenaDressing).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local EliminationEvent = Remotes.get("EliminationEvent")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local LobbyStage = {}

local function newFolder()
	local f = workspace:FindFirstChild("LobbyStage")
	if f then f:Destroy() end
	f = Instance.new("Folder")
	f.Name = "LobbyStage"
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

-- platform top face (LOBBY_ORIGIN is the pad surface center, so top = its Y).
local function topY()
	return Config.LOBBY_ORIGIN.Y
end

-- Cosmetic deck skin over the platform + a lit pit-facing lip.
local function buildStageDeck(folder)
	local pad = Config.LOBBY_PAD_SIZE
	local inset = Config.LOBBY_STAGE_DECK_INSET
	local deck = rigPart(
		Vector3.new(pad.X - inset * 2, Config.LOBBY_STAGE_DECK_THICKNESS, pad.Z - inset * 2),
		Config.LOBBY_ORIGIN + Vector3.new(0, Config.LOBBY_STAGE_DECK_LIFT, 0),
		Config.LOBBY_STAGE_DECK_COLOR, Enum.Material.SmoothPlastic, folder)
	deck.Name = "StageDeck"
	if Config.LOBBY_STAGE_DECK_TEXTURE ~= "" then
		local tex = Instance.new("Texture")
		tex.Face = Enum.NormalId.Top
		tex.Texture = Config.LOBBY_STAGE_DECK_TEXTURE
		tex.StudsPerTileU = 8
		tex.StudsPerTileV = 8
		tex.Parent = deck
	end
	-- warm/lit lip along the +Z (pit-facing) edge
	local lip = rigPart(
		Vector3.new(pad.X - inset * 2, Config.LOBBY_STAGE_DECK_THICKNESS * 1.2, Config.LOBBY_STAGE_EDGE_THICKNESS),
		Config.LOBBY_ORIGIN + Vector3.new(0, Config.LOBBY_STAGE_DECK_LIFT + Config.LOBBY_STAGE_DECK_THICKNESS * 0.25,
			pad.Z / 2 - inset - Config.LOBBY_STAGE_EDGE_THICKNESS),
		Config.LOBBY_STAGE_EDGE_COLOR, Enum.Material.Neon, folder)
	lip.Name = "StageLip"
end

-- Two small soul clusters at the pit-view edges (front ±X) -- the distant WorldShell
-- crowd carries the rest. One Heartbeat drives idle wobble + decaying cheer pop.
local crowdOrbs = {}
local function buildCrowdClusters(folder)
	table.clear(crowdOrbs)
	local pad = Config.LOBBY_PAD_SIZE
	local palette = Config.SOUL_PALETTE
	local hx, hz = pad.X / 2, pad.Z / 2
	local baseY = topY() + Config.LOBBY_STAGE_CLUSTER_LIFT
	local clusterZ = Config.LOBBY_ORIGIN.Z + hz * Config.LOBBY_STAGE_CLUSTER_FRONT
	local n, sp = Config.LOBBY_STAGE_CLUSTER_PER_SIDE, Config.LOBBY_STAGE_CLUSTER_SPACING
	local inset = Config.LOBBY_STAGE_CLUSTER_INSET
	local centers = {
		Config.LOBBY_ORIGIN.X - (hx - inset), -- left wing
		Config.LOBBY_ORIGIN.X + (hx - inset), -- right wing
	}
	local idx = 0
	for _, cx in ipairs(centers) do
		for _, s in ipairs(WorldLayout.cluster(cx, clusterZ, baseY, n, sp)) do
			idx += 1
			local color = palette[WorldLayout.paletteIndex(idx, #palette)]
			local sz = Config.LOBBY_STAGE_ORB_SIZE
			local orb = rigPart(Vector3.new(sz, sz, sz), Vector3.new(s.x, s.y, s.z),
				color, Enum.Material.Neon, folder)
			orb.Shape = Enum.PartType.Ball
			orb.Name = "CrowdOrb"
			if Config.LOBBY_STAGE_ORB_MESH ~= "" then
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.FileMesh
				mesh.MeshId = Config.LOBBY_STAGE_ORB_MESH
				mesh.Parent = orb
			end
			crowdOrbs[#crowdOrbs + 1] = {
				part = orb, base = orb.Position, baseSize = sz,
				phase = (s.x + s.z), cheer = 0,
			}
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() * Config.LOBBY_STAGE_IDLE_SPEED * math.pi * 2
		for _, e in ipairs(crowdOrbs) do
			local p = e.part
			if p.Parent then
				local idle = math.sin(t + e.phase) * Config.LOBBY_STAGE_IDLE_AMP
				local pop = e.cheer * Config.LOBBY_STAGE_CHEER_BOB
				p.Position = e.base + Vector3.new(0, idle + pop, 0)
				local s = e.baseSize * (1 + e.cheer * Config.LOBBY_STAGE_CHEER_SCALE)
				p.Size = Vector3.new(s, s, s)
				if e.cheer > 0 then
					e.cheer = math.max(0, e.cheer - dt / Config.LOBBY_STAGE_CHEER_SECONDS)
				end
			end
		end
	end)
end

-- Festoon STRING-LIGHTS: small warm-gold bulbs in a catenary sag, hung on a thin
-- dark wire (the wire is what reads them as lights, not floating souls), along the
-- back + both wings. Real PointLights capped to LOBBY_STAGE_FESTOON_LIT total.
local litBudget = 0
local function buildStrand(folder, x1, z1, x2, z2)
	local y = topY() + Config.LOBBY_STAGE_FESTOON_HEIGHT
	local pts = WorldLayout.festoonStrand(x1, y, z1, x2, y, z2,
		Config.LOBBY_STAGE_FESTOON_BULBS, Config.LOBBY_STAGE_FESTOON_SAG)
	-- hang a thin dark wire between consecutive bulbs so the strand reads as a line
	local wt = Config.LOBBY_STAGE_FESTOON_WIRE_THICKNESS
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i].x, pts[i].y, pts[i].z)
		local b = Vector3.new(pts[i + 1].x, pts[i + 1].y, pts[i + 1].z)
		local mid = (a + b) / 2
		local seg = rigPart(Vector3.new(wt, wt, (b - a).Magnitude), mid,
			Config.LOBBY_STAGE_FESTOON_WIRE_COLOR, Enum.Material.SmoothPlastic, folder)
		seg.Name = "FestoonWire"
		seg.CFrame = CFrame.lookAt(mid, b)
	end
	local sz = Config.LOBBY_STAGE_FESTOON_BULB_SIZE
	for _, pt in ipairs(pts) do
		local bulb = rigPart(Vector3.new(sz, sz, sz), Vector3.new(pt.x, pt.y, pt.z),
			Config.LOBBY_STAGE_FESTOON_COLOR, Enum.Material.Neon, folder)
		bulb.Shape = Enum.PartType.Ball
		bulb.Name = "FestoonBulb"
		if Config.LOBBY_STAGE_FESTOON_MESH ~= "" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = Config.LOBBY_STAGE_FESTOON_MESH
			mesh.Parent = bulb
		end
		if litBudget < Config.LOBBY_STAGE_FESTOON_LIT then
			litBudget += 1
			local light = Instance.new("PointLight")
			light.Color = Config.LOBBY_STAGE_FESTOON_COLOR
			light.Range = Config.LOBBY_STAGE_LIGHT_RANGE
			light.Brightness = Config.LOBBY_STAGE_LIGHT_BRIGHTNESS
			light.Parent = bulb
		end
	end
end

local function buildFestoon(folder)
	litBudget = 0
	local pad = Config.LOBBY_PAD_SIZE
	local hx, hz = pad.X / 2, pad.Z / 2
	local ox, oz = Config.LOBBY_ORIGIN.X, Config.LOBBY_ORIGIN.Z
	buildStrand(folder, ox - hx, oz - hz, ox + hx, oz - hz) -- back (-Z)
	buildStrand(folder, ox - hx, oz - hz, ox - hx, oz + hz) -- left wing (-X)
	buildStrand(folder, ox + hx, oz - hz, ox + hx, oz + hz) -- right wing (+X)
end

-- Bunting pennants hanging along the back tier front (player-palette triangles).
local function buildBunting(folder)
	local pad = Config.LOBBY_PAD_SIZE
	local hx, hz = pad.X / 2, pad.Z / 2
	local ox, oz = Config.LOBBY_ORIGIN.X, Config.LOBBY_ORIGIN.Z
	local palette = Config.SOUL_PALETTE
	local y = topY() + Config.LOBBY_STAGE_BUNTING_HEIGHT
	local flags = WorldLayout.buntingFlags(ox - hx, oz - hz, ox + hx, oz - hz, y, Config.LOBBY_STAGE_BUNTING_COUNT)
	for i, fl in ipairs(flags) do
		local color = palette[WorldLayout.paletteIndex(i, #palette)]
		if Config.LOBBY_STAGE_BUNTING_TEXTURE ~= "" then
			local flag = rigPart(Config.LOBBY_STAGE_BUNTING_SIZE, Vector3.new(fl.x, fl.y, fl.z),
				color, Enum.Material.SmoothPlastic, folder)
			flag.Name = "BuntingFlag"
			local tex = Instance.new("Texture")
			tex.Face = Enum.NormalId.Front
			tex.Texture = Config.LOBBY_STAGE_BUNTING_TEXTURE
			tex.Parent = flag
		else
			local flag = Instance.new("WedgePart")
			flag.Anchored = true
			flag.CanCollide = false
			flag.CanQuery = false
			flag.CanTouch = false
			flag.CastShadow = false
			flag.Material = Enum.Material.SmoothPlastic
			flag.Size = Config.LOBBY_STAGE_BUNTING_SIZE
			flag.Color = color
			flag.CFrame = CFrame.new(fl.x, fl.y, fl.z) * CFrame.Angles(math.pi, 0, 0) -- point the flag down
			flag.Name = "BuntingFlag"
			flag.Parent = folder
		end
	end
end

-- Small festival crest crowning the back tier; faces into the stage (+Z / Back).
local function buildBackCrest(folder)
	local pad = Config.LOBBY_PAD_SIZE
	local pos = Config.LOBBY_ORIGIN + Vector3.new(0, Config.LOBBY_STAGE_CREST_HEIGHT, -pad.Z / 2)
	local panel = rigPart(Config.LOBBY_STAGE_CREST_SIZE, pos,
		Config.LOBBY_STAGE_CREST_BG, Enum.Material.SmoothPlastic, folder)
	panel.Name = "BackCrest"

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- NormalId.Back is the +Z face; the panel sits on the -Z back wall, so +Z faces inward toward the stage (note: ArenaDressing's front marquee instead uses Front = -Z to face out toward players)
	gui.CanvasSize = Vector2.new(400, 100)
	gui.LightInfluence = 0
	gui.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = Config.LOBBY_STAGE_CREST_TEXT
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Config.LOBBY_STAGE_CREST_TEXT_COLOR
	label.Parent = gui
end

local function cheer()
	for _, e in ipairs(crowdOrbs) do
		e.cheer = 0.6 + math.random() * 0.4
	end
end

function LobbyStage.start()
	local folder = newFolder()
	buildStageDeck(folder)
	buildCrowdClusters(folder)
	buildFestoon(folder)
	buildBunting(folder)
	buildBackCrest(folder)

	-- Reuse WorldShell's cheer triggers: the grandstand cheers on any elimination
	-- and on a winner being named (with a second pop), additive to the distant crowd.
	EliminationEvent.OnClientEvent:Connect(function() cheer() end)
	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state and state.phase == "Ended" and state.winnerName then
			cheer()
			task.delay(0.25, cheer)
		end
	end)
end

return LobbyStage
