--[[
	SweeperController (client) -- "Soul Turbine" cosmetics for the Soul Sweeper
	v2.2 "Touch Elimination" arena. 100% cosmetic; the server owns the physical
	beams and all gameplay geometry (SweeperHazard) -- this module only renders
	the machine: 12 permanent wedge seams (idle dim, flaring behind the low
	bar), a continuous rim ring, a faint moat line at the fall-gap, the static
	under-structure, and a seamless smooth annulus. Fully self-gating on the
	`LiveArena` workspace attribute, so it is safe to start unconditionally: an
	idle Soul Sweeper performs ZERO per-frame writes.

	Touch = elimination (spec 2026-07-09 v2.2 §2): a bar's strike is now a pure
	server-side kill via the grace-gated hazard chokepoint, not a physics shove.
	Beams are non-collidable server kill zones -- there is no client-visible
	contact response to render, so the cosmetic tumble watcher (which followed a
	server body-attribute stamp on strike) is gone.

	Angle source of truth: the seams' flare angle is read directly off the low
	beam's REPLICATED root pose (atan2 of its center offset from SWEEP_CENTER)
	-- the SAME measured-pose convention the server's strike math uses (spec
	2026-07-09 §2-5) -- so cosmetics can never drift from the physical bar. No
	client math derives an angle from elapsed time anymore; the floor telegraph
	arcs that used to do that are gone (v2 playtest: they read as two extra
	phantom beams -- spec 2026-07-09 §1-3).

	Location: StarterPlayerScripts/Client/SweeperController (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local AssetService = game:GetService("AssetService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local GlowDim = require(Shared:WaitForChild("GlowDim"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))

local SweeperController = {}

local TAU = math.pi * 2

-- Resting/base transparencies (live state); dormant always overrides to
-- Config.SWEEP_STANDBY_TRANSPARENCY. Kept as named constants so the build pass
-- and the live/dormancy sync pass never drift from each other.
-- T4 glow-up (spec 2026-07-13 §4.2): the dressing is ATMOSPHERE, not signal --
-- the kill tells are the server-built whole-bar Neon cores + end caps
-- (SweeperHazard), not anything rendered here. Each element below keeps its
-- own GlowDim knob so it can be tuned independently; idle/lit values stay
-- below SWEEP_STANDBY_TRANSPARENCY (0.85) so dormancy still visibly dims the
-- arena.
local SEAM_IDLE_TRANSPARENCY = GlowDim.apply(0.35, Config.GLOW_DIM_SWEEP_SEAM)
local SEAM_FLARE_TRANSPARENCY = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_SEAM)
local RIM_RING_TRANSPARENCY = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_RIM_RING)
local MOAT_TRANSPARENCY = GlowDim.apply(0.5, Config.GLOW_DIM_SWEEP_MOAT)
local DORMANT_TRANSPARENCY = GlowDim.apply(Config.SWEEP_STANDBY_TRANSPARENCY, Config.GLOW_DIM_SWEEP_DORMANT)

-- Seam flare fade-window width in RADIANS (fixed, not speed-scaled) -- the lit
-- trail behind the low bar's measured pose; same rationale as the old wake window.
local SEAM_FLARE_WINDOW = 0.9

--------------------------------------------------------------------------------
-- Build helpers.
--------------------------------------------------------------------------------

local function newPart(folder, name, size, cf, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	p.Parent = folder
	return p
end

-- Orients a part so its LOCAL X axis runs along the radial direction at `angle`,
-- centered at `radiusMid` studs from the arena center (the v1 beam-bar convention:
-- Size.X is the "length" axis; a box built this way spans [radiusMid - Size.X/2,
-- radiusMid + Size.X/2] outward from center along `angle`).
local function radialCFrame(center, angle, y, radiusMid)
	local dirX, dirZ = math.cos(angle), math.sin(angle)
	local mid = Vector3.new(center.X + dirX * radiusMid, y, center.Z + dirZ * radiusMid)
	return CFrame.lookAt(mid, mid + Vector3.new(dirX, 0, dirZ)) * CFrame.Angles(0, math.rad(90), 0)
end

-- A seamless TRUE-CIRCLE annulus (EditableMesh): inner/outer vertex rings top
-- and bottom, top & bottom quad strips + outer and inner skirts (the lobby's
-- `buildEditableCyl` pattern -- LobbyStage -- adapted to a ring). The caller
-- pcall-wraps this: on any client where EditableMesh is unavailable, the build
-- simply fails and the server's segmented floor stays visible (current look).
local function buildEditableAnnulus(innerR, outerR, thickness, sides)
	local em = AssetService:CreateEditableMesh()
	local ti, to, bi, bo = {}, {}, {}, {}
	for i = 0, sides - 1 do
		local a = (2 * math.pi * i) / sides
		local cx, sz = math.cos(a), math.sin(a)
		ti[i] = em:AddVertex(Vector3.new(innerR * cx, thickness / 2, innerR * sz))
		to[i] = em:AddVertex(Vector3.new(outerR * cx, thickness / 2, outerR * sz))
		bi[i] = em:AddVertex(Vector3.new(innerR * cx, -thickness / 2, innerR * sz))
		bo[i] = em:AddVertex(Vector3.new(outerR * cx, -thickness / 2, outerR * sz))
	end
	for i = 0, sides - 1 do
		local j = (i + 1) % sides
		em:AddTriangle(ti[i], to[j], to[i]); em:AddTriangle(ti[i], ti[j], to[j])   -- top
		em:AddTriangle(bi[i], bo[i], bo[j]); em:AddTriangle(bi[i], bo[j], bi[j])   -- bottom
		em:AddTriangle(to[i], bo[j], bo[i]); em:AddTriangle(to[i], to[j], bo[j])   -- outer skirt
		em:AddTriangle(ti[i], bi[i], bi[j]); em:AddTriangle(ti[i], bi[j], ti[j])   -- inner skirt
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em),
		{ CollisionFidelity = Enum.CollisionFidelity.Box }) -- cosmetic + non-colliding anyway
	mp.Size = Vector3.new(outerR * 2, thickness, outerR * 2)
	return mp
end

function SweeperController.start()
	local folder = workspace:FindFirstChild("SweeperDressing")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "SweeperDressing"
	folder.Parent = Workspace

	local c = Config.SWEEP_CENTER
	local surfaceY = Config.SWEEP_SURFACE_Y
	local partCount = 0
	local function counted(p) partCount += 1; return p end

	-- The low beam config drives the wake channels; the high beam has no wake (the
	-- spec's "signature art beat" is scoped to the low/JUMP beam's trail).
	local lowBeam
	for _, beam in ipairs(Config.SWEEP_BEAMS) do
		if beam.class == "low" then lowBeam = beam end
	end
	assert(lowBeam, "SweeperController: Config.SWEEP_BEAMS has no 'low' class beam")
	-- Cached ref to the low bar's collidable root (workspace.SweeperField.SweepBeam_low);
	-- re-found in the Heartbeat loop whenever nil/destroyed (build order or a hot
	-- Studio reload can have the client running before SweeperField replicates).
	local lowBeamPart = nil

	----------------------------------------------------------------------------
	-- 1. Wedge seams: SWEEP_SEAM_COUNT radial Neon strips (hole -> rim) in dark
	--    grooves. Permanently visible (idle dim); the Heartbeat loop flares them
	--    behind the low bar -- the old wake beat fused into reference geometry.
	----------------------------------------------------------------------------
	local seamStrips = {}
	do
		local n = Config.SWEEP_SEAM_COUNT
		local len = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HOLE_RADIUS
		local mid = Config.SWEEP_HOLE_RADIUS + len / 2
		for i = 0, n - 1 do
			local angle = (i / n) * TAU
			counted(newPart(folder, "SeamGroove_" .. i, Vector3.new(len, 0.12, 1.6),
				radialCFrame(c, angle, surfaceY + 0.03, mid), Config.SWEEP_RAIL_COLOR,
				Enum.Material.SmoothPlastic, 0))
			local p = counted(newPart(folder, "Seam_" .. i, Vector3.new(len, 0.15, 0.9),
				radialCFrame(c, angle, surfaceY + 0.05, mid), Config.SWEEP_ACCENT,
				Enum.Material.Neon, SEAM_IDLE_TRANSPARENCY))
			seamStrips[#seamStrips + 1] = { part = p, angle = angle, lastTransparency = SEAM_IDLE_TRANSPARENCY }
		end
	end

	----------------------------------------------------------------------------
	-- 2. Rim ring: continuous bright band on the disc's outer edge face (48
	--    tangent segments, slack-overlapped like the floor). Replaces the chase
	--    studs, rim accent bars, and the generic ArenaDressing edge trim.
	----------------------------------------------------------------------------
	local rimRing = {}
	do
		local segs = 48
		local radius = Config.SWEEP_PLATFORM_RADIUS + 0.2
		local pts = WorldLayout.ring(c.X, c.Z, radius, segs)
		local chord = 2 * radius * math.sin(math.pi / segs) * 1.06
		local y = surfaceY - 0.55 -- band top flush with the deck (+0.05)
		for i, pt in ipairs(pts) do
			local nxt = pts[(i % segs) + 1]
			local p = counted(newPart(folder, "RimRing_" .. i, Vector3.new(0.4, 1.2, chord),
				CFrame.lookAt(Vector3.new(pt.x, y, pt.z), Vector3.new(nxt.x, y, nxt.z)),
				Config.SWEEP_ACCENT, Enum.Material.Neon, RIM_RING_TRANSPARENCY))
			rimRing[#rimRing + 1] = { part = p, liveTransparency = RIM_RING_TRANSPARENCY }
		end
	end

	----------------------------------------------------------------------------
	-- 3. Moat line: faint inner-rim band at the fall-gap's disc edge -- keeps
	--    the hole readable at play speed (fairness; the reference hides it).
	----------------------------------------------------------------------------
	local moatRing = {}
	do
		local segs = 24
		local radius = Config.SWEEP_HOLE_RADIUS - 0.2
		local pts = WorldLayout.ring(c.X, c.Z, radius, segs)
		local chord = 2 * radius * math.sin(math.pi / segs) * 1.06
		local y = surfaceY - 0.2 -- band top flush with the deck (+0.05)
		for i, pt in ipairs(pts) do
			local nxt = pts[(i % segs) + 1]
			local p = counted(newPart(folder, "MoatRing_" .. i, Vector3.new(0.3, 0.5, chord),
				CFrame.lookAt(Vector3.new(pt.x, y, pt.z), Vector3.new(nxt.x, y, nxt.z)),
				Config.SWEEP_ACCENT, Enum.Material.Neon, MOAT_TRANSPARENCY))
			moatRing[#moatRing + 1] = { part = p, liveTransparency = MOAT_TRANSPARENCY }
		end
	end

	----------------------------------------------------------------------------
	-- 4. Under-structure: 4 angled struts + 1 lower ring of tangent bars (static,
	--    dark SmoothPlastic -- reads as built, not floating).
	----------------------------------------------------------------------------
	local strutColor = Color3.fromRGB(14, 17, 30)
	do
		local hubBase = Vector3.new(c.X, surfaceY - 6, c.Z)
		local outerRadius = Config.SWEEP_PLATFORM_RADIUS * 0.7
		for i = 0, 3 do
			local angle = (i / 4) * TAU
			local from = Vector3.new(c.X + outerRadius * math.cos(angle), surfaceY - 12, c.Z + outerRadius * math.sin(angle))
			local mid = (from + hubBase) / 2
			local length = (hubBase - from).Magnitude
			counted(newPart(folder, "Strut_" .. i, Vector3.new(1, 1, length),
				CFrame.lookAt(mid, hubBase), strutColor, Enum.Material.SmoothPlastic, 0))
		end

		local lowerRing = WorldLayout.ring(c.X, c.Z, Config.SWEEP_HUB_RADIUS + 2, 12)
		local ly = surfaceY - 8
		local lchord = 2 * (Config.SWEEP_HUB_RADIUS + 2) * math.sin(math.pi / 12) * 1.1
		for i, pt in ipairs(lowerRing) do
			local nxt = lowerRing[(i % 12) + 1]
			local here = Vector3.new(pt.x, ly, pt.z)
			counted(newPart(folder, "LowerRing_" .. i, Vector3.new(0.8, 0.8, lchord),
				CFrame.lookAt(here, Vector3.new(nxt.x, ly, nxt.z)), strutColor, Enum.Material.SmoothPlastic, 0))
		end
	end

	----------------------------------------------------------------------------
	-- 5. Smooth annulus (the lobby technique): one seamless EditableMesh MeshPart
	--    laid directly over the server's segmented collision floor, carrying the
	--    SweeperStageFloor MaterialVariant. pcall-wrapped like LobbyStage.smoothCyl:
	--    on any client where EditableMesh is unavailable, the build simply fails
	--    and the server's segments (still fully visible + collidable) are the look
	--    -- nothing else breaks. On SUCCESS, the segments are hidden LOCALLY ONLY
	--    (LocalTransparencyModifier) so their collision stays exactly as-is for
	--    the server and every other client.
	----------------------------------------------------------------------------
	do
		local th = Config.SWEEP_PLATFORM_THICKNESS
		local topY = surfaceY + 0.02
		local ok, mp = pcall(buildEditableAnnulus,
			Config.SWEEP_HOLE_RADIUS, Config.SWEEP_PLATFORM_RADIUS, th, 96)
		if ok and mp then
			mp.Name = "SmoothAnnulus"
			mp.CFrame = CFrame.new(c.X, topY - th / 2, c.Z)
			mp.Anchored = true
			mp.CanCollide = false
			mp.CanQuery = false
			mp.CanTouch = false
			mp.CastShadow = false
			mp.Color = Config.SWEEP_PLATFORM_COLOR
			mp.Material = Enum.Material.Glass
			if Config.SWEEP_DISC_MATERIAL ~= "" then
				mp.Material = Enum.Material[Config.SWEEP_DISC_MATERIAL_BASE]
				mp.MaterialVariant = Config.SWEEP_DISC_MATERIAL
			end
			mp.Parent = folder
			counted(mp)

			-- SweeperField is server-built at startup (SweeperHazard.build), so it
			-- should already exist by the time a client runs this -- but wait a
			-- short beat and degrade gracefully (segments stay visible) rather than
			-- assume replication order.
			local field = Workspace:WaitForChild("SweeperField", 5)
			if field then
				for _, seg in ipairs(field:GetChildren()) do
					if seg:IsA("BasePart") and seg.Name:match("^SweepFloor_") then
						seg.LocalTransparencyModifier = 1
					end
				end
			end
		end
		-- pcall failure: skip both the smooth mesh and the segment hide, so the
		-- server's segmented floor stays fully visible (the pre-v2.1 look).
	end

	assert(partCount <= 180, "SweeperController: dressing part budget exceeded (" .. partCount .. " > 180)")

	----------------------------------------------------------------------------
	-- Dormancy sync: one pass over every Neon element. Static elements (rim
	-- ring, moat line) flip between a fixed live value and the standby dim.
	-- The animated element (seams) resets to idle dim on flip; the live loop
	-- repaints it once running.
	----------------------------------------------------------------------------
	local staticNeon = {}
	for _, b in ipairs(rimRing) do staticNeon[#staticNeon + 1] = b end
	for _, b in ipairs(moatRing) do staticNeon[#staticNeon + 1] = b end

	local function setLive(live)
		for _, e in ipairs(staticNeon) do
			e.part.Transparency = live and e.liveTransparency or DORMANT_TRANSPARENCY
		end
		local resetTo = (not live) and DORMANT_TRANSPARENCY or nil
		for _, s in ipairs(seamStrips) do
			s.part.Transparency = resetTo or SEAM_IDLE_TRANSPARENCY
			s.lastTransparency = nil -- force a resync on the next live tick
		end
	end

	setLive(false) -- server starts with no live arena
	workspace:GetAttributeChangedSignal("LiveArena"):Connect(function()
		setLive(workspace:GetAttribute("LiveArena") == "sweeper")
	end)

	----------------------------------------------------------------------------
	-- ONE shared Heartbeat loop -- zero writes when the sweeper isn't live.
	----------------------------------------------------------------------------
	-- Lag probe accumulators (Config.SWEEP_LAG_PROBE; spec v2.4 §2-3).
	local probeSum, probeMax, probeN, probeWindow = 0, 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		if workspace:GetAttribute("LiveArena") ~= "sweeper" then return end
		local field = Workspace:FindFirstChild("SweeperField")
		if not field then return end

		-- Seams flare behind the low beam's MEASURED pose (atan2 of its
		-- replicated root's offset from SWEEP_CENTER -- spec 2026-07-09 §2-5/§2-7),
		-- fading back to idle over a fixed SEAM_FLARE_WINDOW. Re-find the part if
		-- it's ever nil (not yet replicated, or a hot reload); tolerate its absence.
		if not lowBeamPart or not lowBeamPart.Parent then
			lowBeamPart = field:FindFirstChild("SweepBeam_low")
		end
		if lowBeamPart then
			local lowAngle = math.atan2(lowBeamPart.Position.Z - c.Z, lowBeamPart.Position.X - c.X)
			-- Dev lag probe: how far the RENDERED bar trails the server's authoritative
			-- angle (stamped as AuthAngle each monitor tick). Positive = rendered pose
			-- is behind. Accuracy is +-half a monitor tick (the stamp is 10 Hz).
			if Config.SWEEP_LAG_PROBE then
				local auth = lowBeamPart:GetAttribute("AuthAngle")
				if auth then
					local lag = ((auth - lowAngle) * lowBeam.direction) % TAU
					if lag > math.pi then lag -= TAU end
					probeSum += lag
					probeN += 1
					if lag > probeMax then probeMax = lag end
					probeWindow += dt
					if probeWindow >= 1 and probeN > 0 then
						local mean = probeSum / probeN
						print(string.format(
							"[BSR][lagprobe] mean %.4f rad / max %.4f rad (%.2f / %.2f studs at r=%d)",
							mean, probeMax, mean * Config.SWEEP_SPAWN_RADIUS,
							probeMax * Config.SWEEP_SPAWN_RADIUS, Config.SWEEP_SPAWN_RADIUS))
						probeSum, probeMax, probeN, probeWindow = 0, 0, 0, 0
					end
				end
			end
			for _, s in ipairs(seamStrips) do
				local behind = (lowBeam.direction * (lowAngle - s.angle)) % TAU
				local target
				if behind >= SEAM_FLARE_WINDOW then
					target = SEAM_IDLE_TRANSPARENCY
				else
					target = SEAM_FLARE_TRANSPARENCY
						+ (SEAM_IDLE_TRANSPARENCY - SEAM_FLARE_TRANSPARENCY) * (behind / SEAM_FLARE_WINDOW)
				end
				if s.lastTransparency == nil or math.abs(target - s.lastTransparency) > 0.02 then
					s.part.Transparency = target
					s.lastTransparency = target
				end
			end
		end
	end)
end

return SweeperController
