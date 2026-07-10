--[[
	SweeperController (client) -- "Soul Turbine" cosmetics for the Soul Sweeper
	v2.2 "Touch Elimination" arena. 100% cosmetic; the server owns the physical
	beams and all gameplay geometry (SweeperHazard) -- this module only renders
	the machine: wake channels, rim marquee, rotor spin, a seamless smooth
	annulus, light shaft, and the static under-structure/spotlights that make
	the platform read as a built broadcast stage. Fully self-gating on the
	`LiveArena` workspace attribute, so it is safe to start unconditionally: an
	idle Soul Sweeper performs ZERO per-frame writes.

	Touch = elimination (spec 2026-07-09 v2.2 §2): a bar's strike is now a pure
	server-side kill via the grace-gated hazard chokepoint, not a physics shove.
	Beams are non-collidable server kill zones -- there is no client-visible
	contact response to render, so the cosmetic tumble watcher (which followed a
	server body-attribute stamp on strike) is gone. Everything else below --
	annulus, wake, chase, rotors, dormancy -- is unchanged from v2.1.

	Angle source of truth: the wake channel's ignition angle is read directly
	off the low beam's REPLICATED root pose (atan2 of its center offset from
	SWEEP_CENTER) -- the SAME measured-pose convention the server's strike math
	uses (spec 2026-07-09 §2-5) -- so cosmetics can never drift from the
	physical bar. No client math derives an angle from elapsed time anymore;
	the floor telegraph arcs that used to do that are gone (v2 playtest: they
	read as two extra phantom beams -- spec 2026-07-09 §1-3).

	Location: StarterPlayerScripts/Client/SweeperController (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local AssetService = game:GetService("AssetService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))

local SweeperController = {}

local TAU = math.pi * 2

-- Resting/base transparencies (live state); dormant always overrides to
-- Config.SWEEP_STANDBY_TRANSPARENCY. Kept as named constants so the build pass
-- and the live/dormancy sync pass never drift from each other.
-- v2.4 dim pass (spec §2-4): the dressing is ATMOSPHERE, not signal -- only the
-- bars' kill tells (amber blade / crimson underglow / end emitters, built server-
-- side in SweeperHazard) stay full-brightness Neon. Everything here sits at accent
-- level so the tells, the floor, and other players stay readable under Bloom 0.9.
-- Lit/static values stay below SWEEP_STANDBY_TRANSPARENCY (0.85) so dormancy still
-- visibly dims the arena.
local WAKE_BASE_TRANSPARENCY = 0.9
local WAKE_LIT_TRANSPARENCY = 0.5
local CHASE_BASE_TRANSPARENCY = 0.75
local CHASE_LIT_TRANSPARENCY = 0.4
local ROTOR_TRANSPARENCY = 0.6
local SHAFT_TRANSPARENCY = 0.8
local LENS_TRANSPARENCY = 0.5
local RIM_ACCENT_TRANSPARENCY = 0.55
local ROTOR_SPIN_SPEED = 0.4 -- rad/s, cosmetic only

-- Wake fade-window width in RADIANS (fixed, not speed-scaled): the lit trail
-- behind the low bar spans this angular arc regardless of the bar's current
-- speed. v2's window was speed-scaled (SWEEP_WAKE_FADE seconds * angular
-- speed) because it derived the low bar's angle from the elapsed round clock;
-- the v2.1 measured pose has no elapsed term to scale by, so a fixed width is
-- simpler and reads fine across the whole ramp (idle-look implementer's call).
local WAKE_WINDOW = 0.9

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

-- Orients a part so its LOCAL Z axis is TANGENT to the circle at `angle` (the
-- WORLD_TRIM / floor-trim convention) -- used for small individually-animated
-- bars (rotor rings) where we don't have a precomputed neighbor point.
local function tangentCFrame(pos, angle)
	local dir = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	return CFrame.lookAt(pos, pos + dir)
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
	-- 1. Wake channels: 36 radial Neon strips flush with the surface.
	----------------------------------------------------------------------------
	local wakeStrips = {}
	do
		local n = Config.SWEEP_WAKE_CHANNELS
		local len = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HOLE_RADIUS
		local mid = Config.SWEEP_HOLE_RADIUS + len / 2
		local y = surfaceY + 0.05
		for i = 0, n - 1 do
			local angle = (i / n) * TAU
			local cf = radialCFrame(c, angle, y, mid)
			local p = counted(newPart(folder, "Wake_" .. i, Vector3.new(len, 0.15, 0.6),
				cf, Config.SWEEP_ACCENT, Enum.Material.Neon, WAKE_BASE_TRANSPARENCY))
			wakeStrips[#wakeStrips + 1] = { part = p, angle = angle, lastTransparency = WAKE_BASE_TRANSPARENCY }
		end
	end

	----------------------------------------------------------------------------
	-- 2. Rim chase studs: 32 small Neon cubes on the rim ring.
	----------------------------------------------------------------------------
	local chaseStuds = {}
	do
		local n = Config.SWEEP_CHASE_STUDS
		local pts = WorldLayout.ring(c.X, c.Z, Config.SWEEP_PLATFORM_RADIUS + 1, n)
		local y = surfaceY + 0.4
		for i, pt in ipairs(pts) do
			local p = counted(newPart(folder, "Chase_" .. i, Vector3.new(0.6, 0.6, 0.6),
				CFrame.new(pt.x, y, pt.z), Config.SWEEP_ACCENT, Enum.Material.Neon, CHASE_BASE_TRANSPARENCY))
			chaseStuds[#chaseStuds + 1] = { part = p }
		end
	end

	----------------------------------------------------------------------------
	-- 3. Rotor rings: two assemblies of 8 tangent bars around the hub, at two
	--    heights on the pillar; these visually "drive" the beams.
	----------------------------------------------------------------------------
	local function buildRotorRing(namePrefix, y)
		local bars = {}
		local n = 8
		local radius = Config.SWEEP_HUB_RADIUS + 1.5
		local chord = 2 * radius * math.sin(math.pi / n) * 1.1
		for i = 0, n - 1 do
			local angle = (i / n) * TAU
			local pos = Vector3.new(c.X + radius * math.cos(angle), y, c.Z + radius * math.sin(angle))
			local p = counted(newPart(folder, namePrefix .. "_" .. i, Vector3.new(0.5, 0.5, chord),
				tangentCFrame(pos, angle), Config.SWEEP_ACCENT, Enum.Material.Neon, ROTOR_TRANSPARENCY))
			bars[#bars + 1] = { part = p, baseAngle = angle, radius = radius, y = y }
		end
		return bars
	end
	local rotor1Bars = buildRotorRing("Rotor1", surfaceY + 2)
	-- Ring 2 sits above the thick high bar now (bottom 5.5 + thickness 3 = top 8.5;
	-- v2.1 scale-up -- was +6 when the bar was a thin light beam).
	local rotor2Bars = buildRotorRing("Rotor2", surfaceY + 9.5)
	local rotor1Offset, rotor2Offset = 0, 0

	----------------------------------------------------------------------------
	-- 3b. Hub hero mesh (hybrid asset, PRESENCE-based): if the place carries
	--     ReplicatedStorage.SweeperAssets.HubMesh (sourced via Studio MCP; the
	--     folder lives outside Rojo's Shared mapping so syncs never delete it),
	--     clone it over the server's collision pillar as the turbine housing.
	--     Absent => the procedural pillar + rotors above stand alone.
	----------------------------------------------------------------------------
	do
		local assets = ReplicatedStorage:FindFirstChild("SweeperAssets")
		local hubMesh = assets and assets:FindFirstChild("HubMesh")
		if hubMesh then
			local m = hubMesh:Clone()
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true -- clone-time defense; the source is pre-normalized
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					counted(d)
				end
			end
			-- Seat the housing's bounding box on the hub base (pillar spans
			-- surface-6..+8), centered on the hub, whatever the model's own pivot.
			local bbox, size = m:GetBoundingBox()
			local target = CFrame.new(c.X, surfaceY - 6 + size.Y / 2, c.Z)
			m:PivotTo(target * (bbox:Inverse() * m:GetPivot()))
			m.Parent = folder
		end
	end

	----------------------------------------------------------------------------
	-- 4. Light shaft: translucent Neon cylinder through the hole.
	----------------------------------------------------------------------------
	local shaftPart
	do
		local topY = surfaceY + 20
		local bottomY = Config.SWEEP_VOID_Y
		local height = topY - bottomY
		local midY = (topY + bottomY) / 2
		shaftPart = counted(newPart(folder, "LightShaft", Vector3.new(height, 5, 5),
			CFrame.new(c.X, midY, c.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Config.SWEEP_ACCENT, Enum.Material.Neon, SHAFT_TRANSPARENCY))
		shaftPart.Shape = Enum.PartType.Cylinder
	end

	----------------------------------------------------------------------------
	-- 5. Under-structure: 4 angled struts + 1 lower ring of tangent bars (static,
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
	-- 6. Spotlight fixtures: housing + Neon lens, angled at the platform from
	--    above the rim (static).
	----------------------------------------------------------------------------
	do
		for i = 0, 2 do
			local angle = (i / 3) * TAU
			local hRadius = Config.SWEEP_PLATFORM_RADIUS * 0.55
			local hPos = Vector3.new(c.X + hRadius * math.cos(angle), surfaceY + 28, c.Z + hRadius * math.sin(angle))
			local targetRadius = Config.SWEEP_PLATFORM_RADIUS * 0.3
			local target = Vector3.new(c.X + targetRadius * math.cos(angle), surfaceY, c.Z + targetRadius * math.sin(angle))
			local aim = CFrame.lookAt(hPos, target)
			counted(newPart(folder, "SpotHousing_" .. i, Vector3.new(2, 2, 1.2),
				aim, strutColor, Enum.Material.SmoothPlastic, 0))
			counted(newPart(folder, "SpotLens_" .. i, Vector3.new(1.2, 1.2, 0.2),
				aim * CFrame.new(0, 0, -0.7), Config.SWEEP_ACCENT, Enum.Material.Neon, LENS_TRANSPARENCY))
		end
	end

	----------------------------------------------------------------------------
	-- 7. Rim accent ring: WORLD_TRIM-style tangent bars at the rim.
	----------------------------------------------------------------------------
	local rimAccentBars = {}
	do
		local segs = Config.SWEEP_PLATFORM_SEGMENTS
		local radius = Config.SWEEP_PLATFORM_RADIUS + 2.5
		local pts = WorldLayout.ring(c.X, c.Z, radius, segs)
		local chord = 2 * radius * math.sin(math.pi / segs) * 1.06
		local y = surfaceY + 0.8
		for i, pt in ipairs(pts) do
			local nxt = pts[(i % segs) + 1]
			local here = Vector3.new(pt.x, y, pt.z)
			local p = counted(newPart(folder, "RimAccent_" .. i, Vector3.new(0.5, 0.6, chord),
				CFrame.lookAt(here, Vector3.new(nxt.x, y, nxt.z)), Config.SWEEP_ACCENT, Enum.Material.Neon,
				RIM_ACCENT_TRANSPARENCY))
			rimAccentBars[#rimAccentBars + 1] = { part = p }
		end
	end

	----------------------------------------------------------------------------
	-- 8. Smooth annulus (the lobby technique): one seamless EditableMesh MeshPart
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

	-- Chase state declared here (before setLive, which reads it) so it persists
	-- across dormancy flips instead of resetting to index 0 each time.
	local chaseIndex = 0
	local chaseAccum = 0
	local chaseWindow = 3

	----------------------------------------------------------------------------
	-- Dormancy sync: one pass over every Neon element. Static elements (shaft,
	-- rim accent, spotlight lens) flip between a fixed live value and the
	-- standby dim. Animated elements (wake/chase/rotor) reset to a safe
	-- rest/synced state on flip; the live loop repaints them once running.
	----------------------------------------------------------------------------
	local staticNeon = { { part = shaftPart, liveTransparency = SHAFT_TRANSPARENCY } }
	for _, b in ipairs(rimAccentBars) do
		staticNeon[#staticNeon + 1] = { part = b.part, liveTransparency = RIM_ACCENT_TRANSPARENCY }
	end
	for i = 0, 2 do
		local lens = folder:FindFirstChild("SpotLens_" .. i)
		if lens then staticNeon[#staticNeon + 1] = { part = lens, liveTransparency = LENS_TRANSPARENCY } end
	end

	local function setLive(live)
		for _, e in ipairs(staticNeon) do
			e.part.Transparency = live and e.liveTransparency or Config.SWEEP_STANDBY_TRANSPARENCY
		end
		local resetTo = (not live) and Config.SWEEP_STANDBY_TRANSPARENCY or nil
		for _, w in ipairs(wakeStrips) do
			w.part.Transparency = resetTo or WAKE_BASE_TRANSPARENCY
			w.lastTransparency = nil -- force a resync on the next live tick
		end
		for i, cstud in ipairs(chaseStuds) do
			local lit = ((i - 1 - chaseIndex) % Config.SWEEP_CHASE_STUDS) < chaseWindow
			cstud.part.Transparency = resetTo or (lit and CHASE_LIT_TRANSPARENCY or CHASE_BASE_TRANSPARENCY)
		end
		for _, b in ipairs(rotor1Bars) do b.part.Transparency = resetTo or ROTOR_TRANSPARENCY end
		for _, b in ipairs(rotor2Bars) do b.part.Transparency = resetTo or ROTOR_TRANSPARENCY end
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

		-- Wake channels: ignite behind the low beam's MEASURED pose (atan2 of its
		-- replicated root's offset from SWEEP_CENTER -- spec 2026-07-09 §2-5/§2-7),
		-- fading back to base over a fixed WAKE_WINDOW. Re-find the part if it's
		-- ever nil (not yet replicated, or a hot reload); tolerate its absence.
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
			for _, w in ipairs(wakeStrips) do
				local behind = (lowBeam.direction * (lowAngle - w.angle)) % TAU
				local target
				if behind >= WAKE_WINDOW then
					target = WAKE_BASE_TRANSPARENCY
				else
					target = WAKE_LIT_TRANSPARENCY
						+ (WAKE_BASE_TRANSPARENCY - WAKE_LIT_TRANSPARENCY) * (behind / WAKE_WINDOW)
				end
				if w.lastTransparency == nil or math.abs(target - w.lastTransparency) > 0.02 then
					w.part.Transparency = target
					w.lastTransparency = target
				end
			end
		end

		-- Chase: advance the lit window (3 studs) roughly every 0.08s; only the
		-- studs that actually change state are written.
		chaseAccum += dt
		if chaseAccum >= 0.08 then
			chaseAccum -= 0.08
			local leaving = chaseIndex
			chaseIndex = (chaseIndex + 1) % Config.SWEEP_CHASE_STUDS
			local entering = (chaseIndex + chaseWindow - 1) % Config.SWEEP_CHASE_STUDS
			local leavingStud = chaseStuds[leaving + 1]
			local enteringStud = chaseStuds[entering + 1]
			if leavingStud then leavingStud.part.Transparency = CHASE_BASE_TRANSPARENCY end
			if enteringStud then enteringStud.part.Transparency = CHASE_LIT_TRANSPARENCY end
		end

		-- Rotors: counter-rotate the two ring assemblies.
		rotor1Offset += ROTOR_SPIN_SPEED * dt
		rotor2Offset -= ROTOR_SPIN_SPEED * dt
		for _, b in ipairs(rotor1Bars) do
			local angle = b.baseAngle + rotor1Offset
			local pos = Vector3.new(c.X + b.radius * math.cos(angle), b.y, c.Z + b.radius * math.sin(angle))
			b.part.CFrame = tangentCFrame(pos, angle)
		end
		for _, b in ipairs(rotor2Bars) do
			local angle = b.baseAngle + rotor2Offset
			local pos = Vector3.new(c.X + b.radius * math.cos(angle), b.y, c.Z + b.radius * math.sin(angle))
			b.part.CFrame = tangentCFrame(pos, angle)
		end
	end)
end

return SweeperController
