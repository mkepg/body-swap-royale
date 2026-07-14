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
-- Rim + moat belts are ONE mesh (editable-memory budget), so they share this
-- knob; the retired GLOW_DIM_SWEEP_MOAT went with the separate segmented moat.
local RIM_RING_TRANSPARENCY = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_RIM_RING)
local LANTERN_TRANSPARENCY = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_LANTERN)
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

-- A seamless TRUE-CIRCLE multi-band ring mesh (EditableMesh): each band is an
-- annulus (inner/outer vertex rings top and bottom, top/bottom quad strips +
-- outer and inner skirts -- the lobby's `buildEditableCyl` pattern adapted to
-- rings); several bands share ONE mesh/part. Bands give y0/y1 in SURFACE-
-- relative studs; vertices are authored around the combined vertical center so
-- the part pivot is the bbox center. The caller pcall-wraps this: on any client
-- where EditableMesh is unavailable, the build simply fails and the caller
-- falls back to the segmented look.
--
-- BUDGET WARNING: the returned MeshPart renders the LIVE EditableMesh --
-- destroying the editable blanks the part (verified in Studio) -- and every
-- live editable holds a slab of a small device-wide memory budget that
-- LobbyStage's smooth deck/rings already draw from. That is exactly why the
-- arena consolidates ALL its circle geometry into just TWO of these meshes
-- (dark shell + edge neon); do not add more without retesting the budget.
local function buildEditableBands(bands, sides)
	local yMin, yMax = math.huge, -math.huge
	for _, b in ipairs(bands) do
		if b.y0 < yMin then yMin = b.y0 end
		if b.y1 > yMax then yMax = b.y1 end
	end
	local mid = (yMin + yMax) / 2
	local em = AssetService:CreateEditableMesh()
	for _, b in ipairs(bands) do
		local ti, to, bi, bo = {}, {}, {}, {}
		for i = 0, sides - 1 do
			local a = (2 * math.pi * i) / sides
			local cx, sz = math.cos(a), math.sin(a)
			ti[i] = em:AddVertex(Vector3.new(b.inner * cx, b.y1 - mid, b.inner * sz))
			to[i] = em:AddVertex(Vector3.new(b.outer * cx, b.y1 - mid, b.outer * sz))
			bi[i] = em:AddVertex(Vector3.new(b.inner * cx, b.y0 - mid, b.inner * sz))
			bo[i] = em:AddVertex(Vector3.new(b.outer * cx, b.y0 - mid, b.outer * sz))
		end
		for i = 0, sides - 1 do
			local j = (i + 1) % sides
			em:AddTriangle(ti[i], to[j], to[i]); em:AddTriangle(ti[i], ti[j], to[j])   -- top
			em:AddTriangle(bi[i], bo[i], bo[j]); em:AddTriangle(bi[i], bo[j], bi[j])   -- bottom
			em:AddTriangle(to[i], bo[j], bo[i]); em:AddTriangle(to[i], to[j], bo[j])   -- outer skirt
			em:AddTriangle(ti[i], bi[i], bi[j]); em:AddTriangle(ti[i], bi[j], ti[j])   -- inner skirt
		end
	end
	local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em),
		{ CollisionFidelity = Enum.CollisionFidelity.Box }) -- cosmetic + non-colliding anyway
	return mp, mid
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

	-- The low beam config drives the seam flare; the high beam has no trail (the
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

	-- Bake one multi-band TRUE-CIRCLE mesh (96 sides) as a configured cosmetic
	-- part. Returns nil where EditableMesh is unavailable (or the editable-memory
	-- budget is exhausted); callers fall back to the segmented look.
	local function bandMesh(name, bands, color, material, transparency)
		-- 180 sides (vs the old annulus' 96): on the reflective metal shell, each
		-- silhouette facet catches the sun separately -- at 96 the edge glints
		-- read as a dashed line; at 180 they merge into one continuous catchlight.
		local ok, mp, mid = pcall(buildEditableBands, bands, 180)
		if not ok or not mp then return nil end
		mp.Name = name
		mp.CFrame = CFrame.new(c.X, surfaceY + mid, c.Z)
		mp.Anchored = true
		mp.CanCollide = false
		mp.CanQuery = false
		mp.CanTouch = false
		mp.CastShadow = false
		mp.Color = color
		mp.Material = material
		mp.Transparency = transparency
		mp.Parent = folder
		return counted(mp)
	end

	-- Segmented tangent-ring fallback (pre-mesh look) for clients without
	-- EditableMesh; also keeps the dormancy wiring identical either way.
	local function segmentedRing(list, namePrefix, segs, radius, size, y, transparency)
		local pts = WorldLayout.ring(c.X, c.Z, radius, segs)
		local chord = 2 * radius * math.sin(math.pi / segs) * 1.06
		for i, pt in ipairs(pts) do
			local nxt = pts[(i % segs) + 1]
			local p = counted(newPart(folder, namePrefix .. i, Vector3.new(size.X, size.Y, chord),
				CFrame.lookAt(Vector3.new(pt.x, y, pt.z), Vector3.new(nxt.x, y, nxt.z)),
				Config.SWEEP_ACCENT, Enum.Material.Neon, transparency))
			list[#list + 1] = { part = p, liveTransparency = transparency }
		end
	end

	----------------------------------------------------------------------------
	-- 1. Wedge seams: SWEEP_SEAM_COUNT radial Neon strips (hole -> rim), each
	--    RECESSED in a dark metal channel -- groove plate below, flank rails
	--    either side rising past the strip's top -- so the light reads embedded
	--    in the platform, not laid on it (same shell language as the bars).
	--    Permanently visible (idle dim); the Heartbeat loop flares them behind
	--    the low bar -- the old wake beat fused into reference geometry.
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
			-- Flank rails on the groove plate's edges: tops at +0.20 vs the strip's
			-- +0.125, so the neon sits below the metal -- a lit channel, not a bump.
			for _, side in ipairs({ -0.625, 0.625 }) do
				counted(newPart(folder, "SeamFlank_" .. i, Vector3.new(len, 0.28, 0.35),
					radialCFrame(c, angle, surfaceY + 0.06, mid) * CFrame.new(0, 0, side),
					Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0))
			end
			seamStrips[#seamStrips + 1] = { part = p, angle = angle, lastTransparency = SEAM_IDLE_TRANSPARENCY }
		end
	end

	----------------------------------------------------------------------------
	-- 2. Disc shell + edge neon: the whole circular look is exactly TWO true-
	--    circle meshes (see the budget warning on buildEditableBands):
	--    SHELL = the smooth disc annulus + rim fascia lips + moat lips, one dark
	--    metal mesh; NEON = the rim belt + moat belt, one Neon mesh whose faces
	--    sit 0.18 (rim) / 0.14 (moat) BEHIND the lips -- the glow reads embedded
	--    in the platform's metal, per the reference, on a perfectly smooth
	--    circle. The rim assembly replaces the chase studs, rim accent bars, and
	--    the generic ArenaDressing edge trim; the moat belt keeps the fall-gap
	--    readable at play speed (fairness; the reference hides it).
	--    Fallback without EditableMesh: the server's segmented floor stays
	--    visible and both rings build as segmented tangent bars (pre-mesh look).
	----------------------------------------------------------------------------
	local edgeNeon = {} -- dormancy entries; single mesh OR fallback segments
	local discShell = nil
	do
		local th = Config.SWEEP_PLATFORM_THICKNESS
		local holeR = Config.SWEEP_HOLE_RADIUS
		local platR = Config.SWEEP_PLATFORM_RADIUS
		-- Vertical stacks (rel. surface): rim lips -0.25..+0.02 and -1.85..-1.55
		-- (tops flush with the deck top +0.02 -- a proud lip corner reads as a
		-- separate glint line); moat lips -0.08..+0.02 and -0.45..-0.32. Disc
		-- bottom -1.98 (the fascia stays within the disc's depth). The rim neon
		-- carries ~70% of the fascia height (reference read: a BOLD glow band
		-- framed by slim metal lips, not a thin slit).
		discShell = bandMesh("DiscShell", {
			{ inner = holeR, outer = platR, y0 = 0.02 - th, y1 = 0.02 },          -- the disc
			{ inner = platR - 0.5, outer = platR + 0.5, y0 = -0.25, y1 = 0.02 },  -- rim lip top (flush with deck)
			{ inner = platR - 0.5, outer = platR + 0.5, y0 = -1.85, y1 = -1.55 }, -- rim lip bottom
			{ inner = holeR - 0.5, outer = holeR + 0.1, y0 = -0.08, y1 = 0.02 },  -- moat lip top (flush with deck)
			{ inner = holeR - 0.5, outer = holeR + 0.1, y0 = -0.45, y1 = -0.32 }, -- moat lip bottom
		}, Config.SWEEP_PLATFORM_COLOR, Enum.Material.Metal, 0)
		if discShell then
			-- Premium dark-metal finish (reference read: painted/brushed metal with
			-- subtle reflections -- NOT the rocky variant look).
			discShell.Reflectance = Config.SWEEP_DISC_REFLECTANCE
			if Config.SWEEP_DISC_MATERIAL ~= "" then
				discShell.Material = Enum.Material[Config.SWEEP_DISC_MATERIAL_BASE]
				discShell.MaterialVariant = Config.SWEEP_DISC_MATERIAL
			end
			-- Belt edges sit 0.10 INSIDE the lip openings (vertical setback, not
			-- flush): a flush edge leaves a sub-pixel neon sliver visible past the
			-- lip corner at grazing angles, which rasterizes as a dashed line along
			-- the deck edge. With the setback, grazing rays land on dark channel
			-- shadow (the disc's own skirt) instead of glow.
			local neon = bandMesh("EdgeNeon", {
				{ inner = platR - 0.5, outer = platR + 0.35, y0 = -1.45, y1 = -0.35 }, -- rim belt (recess 0.15)
				{ inner = holeR - 0.36, outer = holeR + 0.1, y0 = -0.29, y1 = -0.12 }, -- moat belt (recess 0.14)
			}, Config.SWEEP_ACCENT, Enum.Material.Neon, RIM_RING_TRANSPARENCY)
			if neon then
				edgeNeon[#edgeNeon + 1] = { part = neon, liveTransparency = RIM_RING_TRANSPARENCY }
			end
		else
			segmentedRing(edgeNeon, "RimRing_", 48, Config.SWEEP_PLATFORM_RADIUS + 0.2,
				Vector3.new(0.4, 1.2, 0), surfaceY - 0.55, RIM_RING_TRANSPARENCY)
			segmentedRing(edgeNeon, "MoatRing_", 24, Config.SWEEP_HOLE_RADIUS - 0.2,
				Vector3.new(0.3, 0.5, 0), surfaceY - 0.2, RIM_RING_TRANSPARENCY)
		end
	end

	----------------------------------------------------------------------------
	-- 4. Hub stack (spec §4.2): flared skirt into the moat, stacked drums with
	--    a shadow groove, high-bar ledge, GLASS-encased amber lantern core with
	--    a PointLight, bezel rings, rounded cap. Replaces the visual role of the
	--    retired rotor rings / light shaft / spotlight fixtures. All
	--    non-collidable anchored cosmetics; the server's collidable r=6 pillar
	--    and the beam motor axle are untouched.
	----------------------------------------------------------------------------
	local lanternCore, lanternLight
	do
		local function cyl(name, radius, yBottom, yTop, cylColor, material, transparency)
			local p = newPart(folder, name, Vector3.new(yTop - yBottom, radius * 2, radius * 2),
				CFrame.new(c.X, surfaceY + (yBottom + yTop) / 2, c.Z) * CFrame.Angles(0, 0, math.rad(90)),
				cylColor, material, transparency)
			p.Shape = Enum.PartType.Cylinder
			return counted(p)
		end
		local grooveColor = Color3.fromRGB(10, 13, 30)
		-- Skirt: flares down into the fall-gap; max radius 8.5 < HOLE_RADIUS 12,
		-- so the moat stays open (and lethal). Non-collidable like everything here.
		cyl("HubSkirt1", 8.5, -2.5, -0.8, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubSkirt2", 7.6, -0.8, 0.2, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		-- Drums hug the collidable pillar (visual overhang 0.3, cosmetic-only).
		cyl("HubDrum1", 6.3, 0.2, 3.3, Config.SWEEP_PLATFORM_COLOR, Enum.Material.Metal, 0)
		cyl("HubGroove", 5.95, 3.3, 3.5, grooveColor, Enum.Material.SmoothPlastic, 0)
		cyl("HubDrum2", 6.15, 3.5, 6.8, Config.SWEEP_PLATFORM_COLOR, Enum.Material.Metal, 0)
		-- Ledge sits ABOVE the high-bar collar's sweep. Collar top ~ y 9.0 is
		-- DERIVED from the server collar build (SweeperHazard): collar top =
		-- SWEEP_BEAM_HIGH_BOTTOM + SWEEP_BEAM_HIGH_THICKNESS/2 + (thick + 1)/2
		-- = 5.5 + 1.5 + 2.0. Re-derive the 9.3 below if either knob changes
		-- (the Config.SWEEP_AIRBORNE_BAND re-derive-note precedent).
		cyl("HubLedge", 7.2, 9.3, 9.7, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubBezelLow", 3.4, 9.9, 10.3, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		-- Lantern: outer GLASS wall (visible transparency), inner Neon core with
		-- an air gap, per the reference read (glow embedded in glass). Taller than
		-- wide (visual-pass iter 1): the reference lantern is a slim upright
		-- capsule, not a squat drum.
		cyl("HubLanternGlass", 3.0, 10.2, 15.0,
			Color3.fromRGB(205, 222, 255), Enum.Material.Glass, 0.45)
		lanternCore = cyl("HubLanternCore", 2.0, 10.5, 14.7,
			Config.SWEEP_ACCENT, Enum.Material.Neon, LANTERN_TRANSPARENCY)
		lanternLight = Instance.new("PointLight")
		lanternLight.Color = Config.SWEEP_ACCENT
		lanternLight.Brightness = 2
		lanternLight.Range = 26
		-- Dormancy-safe initial state: the instance default is Enabled = true, and
		-- setLive(false) only runs at the END of start() -- past section 6's
		-- WaitForChild yield -- so a slow-replicating client would otherwise show
		-- the lantern lit for seconds while dormant. setLive syncs it from here on.
		lanternLight.Enabled = false
		lanternLight.Parent = lanternCore
		cyl("HubBezelHigh", 3.4, 14.9, 15.3, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubCap", 2.8, 15.3, 16.3, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
		cyl("HubCapTop", 2.2, 16.3, 16.7, Config.SWEEP_RAIL_COLOR, Enum.Material.Metal, 0)
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
	-- 6. With the DiscShell mesh up (section 2), hide the server's segmented
	--    collision floor LOCALLY ONLY (LocalTransparencyModifier), so its
	--    collision stays exactly as-is for the server and every other client.
	--    Done here (end of the build) because WaitForChild can yield up to 5s.
	----------------------------------------------------------------------------
	if discShell then
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
	-- No shell mesh: the server's segmented floor stays fully visible.

	assert(partCount <= 180, "SweeperController: dressing part budget exceeded (" .. partCount .. " > 180)")

	----------------------------------------------------------------------------
	-- Dormancy sync: one pass over every Neon element. Static elements (the
	-- edge-neon mesh -- or its segmented fallback rings -- and the hub lantern
	-- core) flip between a fixed live value and the standby dim; the lantern's
	-- PointLight switches off entirely when dormant (it has no dim analog). The
	-- animated element (seams) resets to idle dim on flip; the live loop
	-- repaints it once running.
	----------------------------------------------------------------------------
	local staticNeon = {}
	for _, b in ipairs(edgeNeon) do staticNeon[#staticNeon + 1] = b end
	staticNeon[#staticNeon + 1] = { part = lanternCore, liveTransparency = LANTERN_TRANSPARENCY }

	local function setLive(live)
		lanternLight.Enabled = live
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
