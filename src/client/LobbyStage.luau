--[[
	LobbyStage (client) -- the beyblade lobby's cosmetic dressing. 100% local
	cosmetic, ADD-ONLY: the load-bearing LobbyArea geometry (the walkable disc + the
	invisible rim barrier) is server-owned and untouched; every part built here is
	non-colliding/non-querying/shadow-less.

	The lobby is shaped like a beyblade (spinning top): glowing rim ENERGY RINGS
	around the server disc (the old festival "lights", reinterpreted; the topmost is
	the visible half of the hybrid fall ring), a STEPPED TAPER body down to a TIP, and
	two cheer-reactive SOUL-ORB clusters ("spectator souls") at the rim that pulse on
	eliminations/wins (reusing WorldShell's decaying-impulse pattern).

	Location: StarterPlayerScripts/Client/LobbyStage (ModuleScript)
	Connections are session-lifetime (matches WorldShell/ArenaDressing).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")

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

-- A vertical-axis Cylinder centered on the lobby, with its CENTER at world height
-- `centerY`. `length` is the vertical extent; `diameter` the round cross-section.
local function rigCyl(name, diameter, length, centerY, color, material, parent)
	local o = Config.LOBBY_ORIGIN
	local p = rigPart(Vector3.new(length, diameter, diameter),
		Vector3.new(o.X, centerY, o.Z), color, material, parent)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(o.X, centerY, o.Z) * CFrame.Angles(0, 0, math.rad(90))
	p.Name = name
	return p
end

-- A PERFECTLY SMOOTH vertical-axis cylinder: a high-N EditableMesh disc built on the
-- client (primitive Part Cylinders facet visibly at this scale). The mesh lies flat
-- with Y as the thickness axis, so no rotation is needed. Falls back to the primitive
-- rigCyl if EditableMesh is unavailable on this client.
local SMOOTH_SIDES = Config.LOBBY_BEY_SMOOTH_SIDES

local function buildEditableCyl(diameter, length)
	local em = AssetService:CreateEditableMesh()
	local R, H, N = diameter / 2, length, SMOOTH_SIDES
	local topC = em:AddVertex(Vector3.new(0, H / 2, 0))
	local botC = em:AddVertex(Vector3.new(0, -H / 2, 0))
	local top, bot = {}, {}
	for i = 0, N - 1 do
		local ang = (2 * math.pi * i) / N
		local x, z = R * math.cos(ang), R * math.sin(ang)
		top[i] = em:AddVertex(Vector3.new(x, H / 2, z))
		bot[i] = em:AddVertex(Vector3.new(x, -H / 2, z))
	end
	for i = 0, N - 1 do
		local j = (i + 1) % N
		em:AddTriangle(topC, top[j], top[i])   -- top face (+Y)
		em:AddTriangle(botC, bot[i], bot[j])   -- bottom face (-Y)
		em:AddTriangle(top[i], top[j], bot[i]) -- side
		em:AddTriangle(top[j], bot[j], bot[i]) -- side
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em),
		{ CollisionFidelity = Enum.CollisionFidelity.Box })
	mp.Size = Vector3.new(diameter, length, diameter)
	return mp
end

local function smoothCyl(name, diameter, length, centerY, color, material, parent)
	local o = Config.LOBBY_ORIGIN
	local ok, mp = pcall(buildEditableCyl, diameter, length)
	if ok and mp then
		mp.CFrame = CFrame.new(o.X, centerY, o.Z) -- mesh already lies flat (Y = thickness)
		mp.Anchored = true
		mp.CanCollide = false
		mp.CanQuery = false
		mp.CanTouch = false
		mp.CastShadow = false
		mp.Material = material
		mp.Color = color
		mp.Name = name
		mp.Parent = parent
		return mp
	end
	return rigCyl(name, diameter, length, centerY, color, material, parent) -- primitive fallback
end

-- top face of the server disc (= LOBBY_ORIGIN.Y).
local function topY()
	return Config.LOBBY_ORIGIN.Y
end

-- The smooth visual disc players see (the server LobbyArea disc is invisible
-- collision). Top face at LOBBY_ORIGIN.Y, matching the collision disc exactly.
local function buildDeck(folder)
	local th = Config.LOBBY_DISC_THICKNESS
	smoothCyl("Deck", Config.LOBBY_DISC_RADIUS * 2, th, topY() - th / 2,
		Config.LOBBY_DISC_COLOR, Enum.Material.Metal, folder)
end

-- Glowing energy rings around the disc rim. Each is a Neon disc WIDER than the disc,
-- centered at its mid-height; the opaque deck occludes the centre, so only the
-- protruding rim glows.
local function buildEnergyRings(folder)
	local r = Config.LOBBY_DISC_RADIUS
	local midY = topY() - Config.LOBBY_DISC_THICKNESS / 2
	local t = Config.LOBBY_BEY_RING_THICKNESS
	local a = smoothCyl("EnergyRing", (r + Config.LOBBY_BEY_RING_OVERHANG_A) * 2, t, midY,
		Config.LOBBY_BEY_RING_COLOR_A, Enum.Material.Neon, folder)
	local b = smoothCyl("EnergyRing", (r + Config.LOBBY_BEY_RING_OVERHANG_B) * 2, t,
		midY - Config.LOBBY_BEY_RING_DROP_B, Config.LOBBY_BEY_RING_COLOR_B, Enum.Material.Neon, folder)
	-- soften the rim glow
	a.Transparency = Config.LOBBY_BEY_GLOW_TRANSPARENCY
	b.Transparency = Config.LOBBY_BEY_GLOW_TRANSPARENCY
end

-- Stepped taper body below the disc (down to a small base; no tip spike).
local function buildBody(folder)
	local r = Config.LOBBY_DISC_RADIUS
	for _, step in ipairs(Config.LOBBY_BEY_STEPS) do
		local radiusFrac, depth, thickness = step[1], step[2], step[3]
		smoothCyl("BeyStep", r * 2 * radiusFrac, thickness, topY() - depth,
			Config.LOBBY_BEY_STEP_COLOR, Enum.Material.Metal, folder)
	end
end

-- Two cheer-reactive soul-orb clusters at the rim (±X); one Heartbeat drives idle
-- wobble + a decaying cheer pop (same pattern as WorldShell's crowd).
local crowdOrbs = {}
local function buildSpectatorSouls(folder)
	table.clear(crowdOrbs)
	local palette = Config.SOUL_PALETTE
	local o = Config.LOBBY_ORIGIN
	local rimX = Config.LOBBY_DISC_RADIUS * Config.LOBBY_BEY_CLUSTER_RADIUS
	local baseY = topY() + Config.LOBBY_BEY_CLUSTER_LIFT
	local n, sp = Config.LOBBY_STAGE_CLUSTER_PER_SIDE, Config.LOBBY_STAGE_CLUSTER_SPACING
	local centers = { o.X - rimX, o.X + rimX }
	local idx = 0
	for _, cx in ipairs(centers) do
		for _, s in ipairs(WorldLayout.cluster(cx, o.Z, baseY, n, sp)) do
			idx += 1
			local color = palette[WorldLayout.paletteIndex(idx, #palette)]
			local sz = Config.LOBBY_STAGE_ORB_SIZE
			local orb = rigPart(Vector3.new(sz, sz, sz), Vector3.new(s.x, s.y, s.z),
				color, Enum.Material.Neon, folder)
			orb.Shape = Enum.PartType.Ball
			orb.Transparency = Config.LOBBY_BEY_GLOW_TRANSPARENCY -- soften the soul glow
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

local function cheer()
	for _, e in ipairs(crowdOrbs) do
		e.cheer = 0.6 + math.random() * 0.4
	end
end

function LobbyStage.start()
	local folder = newFolder()
	buildBody(folder)
	buildEnergyRings(folder)
	buildDeck(folder)
	buildSpectatorSouls(folder)

	-- Reuse WorldShell's cheer triggers: the spectator souls pulse on any elimination
	-- and on a winner being named (second pop), additive to the distant crowd.
	EliminationEvent.OnClientEvent:Connect(function() cheer() end)
	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state and state.phase == "Ended" and state.winnerName then
			cheer()
			task.delay(0.25, cheer)
		end
	end)
end

return LobbyStage
