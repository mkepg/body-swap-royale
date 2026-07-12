--[[
	WorldShell (client) -- Layer 1 of the broadcast world: the arena-agnostic
	"Soul Festival Sky". 100% local cosmetic (no replication): dusk atmosphere,
	drifting soul-wisps, an aurora that flares on each swap, and a distant
	soul-orb crowd that cheers on eliminations/wins. Built once on start.

	Location: StarterPlayerScripts/Client/WorldShell (ModuleScript)
	Connections are session-lifetime (matches SoulController/ClientRoundHud).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GlowDim = require(Shared:WaitForChild("GlowDim"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SetControlledBody = Remotes.get("SetControlledBody")
local EliminationEvent = Remotes.get("EliminationEvent")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local WorldShell = {}

local function newFolder()
	local f = workspace:FindFirstChild("WorldShell")
	if f then f:Destroy() end
	f = Instance.new("Folder")
	f.Name = "WorldShell"
	f.Parent = workspace
	return f
end

local function glowOrb(size, color, parent, dimFactor)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Transparency = GlowDim.apply(0, dimFactor)
	p.Size = Vector3.new(size, size, size)
	p.Color = color
	p.Parent = parent
	return p
end

-- Dusk grade + optional skybox (fallback: no Sky, gradient via atmosphere only).
local function buildAtmosphere()
	-- Lighting effects must live in Lighting (not the workspace folder) to take effect.
	Lighting.ClockTime = Config.WORLD_CLOCK_TIME
	Lighting.Ambient = Config.WORLD_AMBIENT
	Lighting.OutdoorAmbient = Config.WORLD_OUTDOOR_AMBIENT
	Lighting.FogColor = Config.WORLD_FOG_COLOR

	local atmo = Instance.new("Atmosphere")
	atmo.Density = Config.WORLD_ATMOSPHERE_DENSITY
	atmo.Haze = Config.WORLD_ATMOSPHERE_HAZE
	atmo.Color = Config.WORLD_FOG_COLOR
	atmo.Decay = Config.WORLD_ATMOSPHERE_DECAY
	atmo.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = Config.WORLD_BLOOM_INTENSITY
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Config.WORLD_COLORCORRECTION_TINT
	cc.Saturation = Config.WORLD_COLORCORRECTION_SATURATION
	cc.Parent = Lighting

	local sb = Config.WORLD_SKYBOX
	if sb.Up ~= "" then
		local sky = Instance.new("Sky")
		sky.SkyboxUp, sky.SkyboxDn = sb.Up, sb.Down
		sky.SkyboxLf, sky.SkyboxRt = sb.Left, sb.Right
		sky.SkyboxFt, sky.SkyboxBk = sb.Front, sb.Back
		sky.Parent = Lighting
	end
end

local function buildWisps(folder)
	local palette = Config.SOUL_PALETTE
	local field = WorldLayout.wispField(
		0, Config.WORLD_WISP_CENTER_Y, 0,
		Config.WORLD_WISP_SPREAD, Config.WORLD_WISP_HEIGHT,
		Config.WORLD_WISP_COUNT, #palette, Config.WORLD_WISP_SEED)
	local wisps = {}
	for _, w in ipairs(field) do
		local orb = glowOrb(Config.WORLD_WISP_SIZE, palette[w.colorIndex], folder, Config.GLOW_DIM_WISPS)
		orb.Position = Vector3.new(w.x, w.y, w.z)
		wisps[#wisps + 1] = { part = orb, baseX = w.x, baseY = w.y, baseZ = w.z, phase = (w.x + w.z) }
	end
	-- One Heartbeat bob for the whole field (cheap; session-lifetime).
	RunService.Heartbeat:Connect(function()
		local t = os.clock() * Config.WORLD_WISP_DRIFT_SPEED * math.pi * 2
		for _, wp in ipairs(wisps) do
			local p = wp.part
			if p.Parent then
				p.Position = Vector3.new(
					wp.baseX,
					wp.baseY + math.sin(t + wp.phase) * Config.WORLD_WISP_DRIFT_AMP,
					wp.baseZ)
			end
		end
	end)
end

local auroraPart = nil
local function buildAurora(folder)
	auroraPart = Instance.new("Part")
	auroraPart.Name = "Aurora"
	auroraPart.Anchored = true
	auroraPart.CanCollide = false
	auroraPart.CanQuery = false
	auroraPart.CanTouch = false
	auroraPart.CastShadow = false
	auroraPart.Material = Enum.Material.Neon
	auroraPart.Size = Config.WORLD_AURORA_SIZE
	auroraPart.Position = Vector3.new(0, Config.WORLD_AURORA_Y, 0)
	auroraPart.Color = Config.WORLD_AURORA_BASE_COLOR
	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.GLOW_DIM_AURORA)
	auroraPart.Parent = folder
end

local flareToken = nil
local function flareAurora()
	if not (auroraPart and auroraPart.Parent) then return end
	local token = {}
	flareToken = token
	auroraPart.Color = Config.SOUL_PALETTE[math.random(1, #Config.SOUL_PALETTE)]
	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_FLARE_TRANSPARENCY, Config.GLOW_DIM_AURORA)
	local tw = TweenService:Create(auroraPart,
		TweenInfo.new(Config.WORLD_AURORA_FLARE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.GLOW_DIM_AURORA) })
	tw:Play()
	task.delay(Config.WORLD_AURORA_FLARE_SECONDS, function()
		if flareToken == token then flareToken = nil end
	end)
end

local crowd = {}
local function buildCrowd(folder)
	local palette = Config.SOUL_PALETTE
	local pts = WorldLayout.ring(0, 0, Config.WORLD_CROWD_RADIUS, Config.WORLD_CROWD_COUNT)
	for i, pt in ipairs(pts) do
		local color = palette[WorldLayout.paletteIndex(i, #palette)]
		local orb = glowOrb(Config.WORLD_CROWD_ORB_SIZE, color, folder, Config.GLOW_DIM_CROWD)
		orb.Position = Vector3.new(pt.x, Config.WORLD_CROWD_Y, pt.z)
		crowd[#crowd + 1] = {
			part = orb,
			base = orb.Position,
			baseSize = Config.WORLD_CROWD_ORB_SIZE,
			phase = (pt.x + pt.z),
			cheer = 0,
		}
	end
	-- One Heartbeat drives a gentle idle wobble plus a decaying cheer pop (bob +
	-- size = brighter neon glow) for the whole crowd. A per-orb decaying impulse
	-- (not TweenService) keeps the idle Position write from fighting a tween.
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() * Config.WORLD_CROWD_IDLE_SPEED * math.pi * 2
		for _, e in ipairs(crowd) do
			local p = e.part
			if p.Parent then
				local idle = math.sin(t + e.phase) * Config.WORLD_CROWD_IDLE_AMP
				local pop = e.cheer * Config.WORLD_CROWD_CHEER_BOB
				p.Position = e.base + Vector3.new(0, idle + pop, 0)
				local s = e.baseSize * (1 + e.cheer * Config.WORLD_CROWD_CHEER_SCALE)
				p.Size = Vector3.new(s, s, s)
				if e.cheer > 0 then
					e.cheer = math.max(0, e.cheer - dt / Config.WORLD_CROWD_CHEER_SECONDS)
				end
			end
		end
	end)
end

local function cheer()
	for _, e in ipairs(crowd) do
		e.cheer = 0.6 + math.random() * 0.4
	end
end

function WorldShell.start()
	local folder = newFolder()
	buildAtmosphere()
	buildWisps(folder)
	buildAurora(folder)
	buildCrowd(folder)

	-- Aurora flares when this client is told it swapped (fired to everyone at T0).
	SetControlledBody.OnClientEvent:Connect(function(_, isSwap)
		if isSwap then flareAurora() end
	end)
	-- Crowd cheers on any elimination, and a bigger cheer when a winner is named.
	EliminationEvent.OnClientEvent:Connect(function() cheer() end)
	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state and state.phase == "Ended" and state.winnerName then
			cheer()
			task.delay(0.25, cheer)
		end
	end)
end

return WorldShell
