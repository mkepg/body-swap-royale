--[[
	SweeperController (client) -- "Soul Turbine" cosmetics for the Soul Sweeper v2
	arena. 100% cosmetic; the server owns the physical beams and all gameplay
	geometry now (SweeperHazard v2) -- this module only renders the machine: wake
	channels, rim marquee, rotor spin, floor telegraph, light shaft, and the static
	under-structure/spotlights that make the platform read as a built broadcast
	stage. Fully self-gating on the `LiveArena` workspace attribute, so it is safe
	to start unconditionally: an idle Soul Sweeper performs ZERO per-frame writes.

	Angles come from the SAME pure SweeperModel math the server's strike backstop
	uses (round-start server time read off SweeperField.RoundStartServerT), so
	cosmetics can never drift from the authoritative beam positions.

	Location: StarterPlayerScripts/Client/SweeperController (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SweeperModel = require(Shared:WaitForChild("SweeperModel"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))

local SweeperController = {}

local TAU = math.pi * 2

-- Resting/base transparencies (live state); dormant always overrides to
-- Config.SWEEP_STANDBY_TRANSPARENCY. Kept as named constants so the build pass
-- and the live/dormancy sync pass never drift from each other.
local WAKE_BASE_TRANSPARENCY = 0.9
local WAKE_LIT_TRANSPARENCY = 0.15
local CHASE_BASE_TRANSPARENCY = 0.6
local CHASE_LIT_TRANSPARENCY = 0.1
local TELEGRAPH_TRANSPARENCY = 0.5
local ROTOR_TRANSPARENCY = 0.35
local SHAFT_TRANSPARENCY = 0.7
local LENS_TRANSPARENCY = 0.2
local RIM_ACCENT_TRANSPARENCY = 0
local ROTOR_SPIN_SPEED = 0.4 -- rad/s, cosmetic only

--------------------------------------------------------------------------------
-- Tumble watcher (verbatim from v1 -- dedupe + disconnect version).
--------------------------------------------------------------------------------

-- Watch the local player's controlled body for a server sweep stamp and play a brief
-- cosmetic tumble (a decaying spin on the body's root). Debounced: ignores stamps that
-- arrive while a tumble is already playing. Fed by authoritative state; never drives it.
local function watchTumble(getOwnBody)
	local tumbling = false
	local currentBody = nil -- the body we're currently watching (or nil between spawns)
	local conn = nil
	local function attach(body)
		if body == currentBody then return end -- unchanged: keep the existing connection
		-- Body changed (a swap, or dropped to nil between spawns): tear down the prior
		-- connection FIRST, so a stale SweptAt stamp on a body we no longer control can't
		-- win the shared `tumbling` flag, and so we never leak a fresh connection each poll.
		if conn then conn:Disconnect(); conn = nil end
		currentBody = body
		local root = body and body:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local last = 0
		conn = body:GetAttributeChangedSignal("SweptAt"):Connect(function()
			local t = body:GetAttribute("SweptAt")
			if not t or t == last or tumbling then return end
			last = t
			tumbling = true
			task.spawn(function()
				local dur = Config.SWEEP_TUMBLE_SECONDS
				local t0 = os.clock()
				while os.clock() - t0 < dur do
					local f = 1 - (os.clock() - t0) / dur -- decay
					root.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(18 * f))
					RunService.RenderStepped:Wait()
				end
				tumbling = false
			end)
		end)
	end
	-- Re-poll the controlled body; attach() only rewires when it actually changes.
	task.spawn(function()
		while true do
			attach(getOwnBody())
			task.wait(1)
		end
	end)
end

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

function SweeperController.start(getOwnBody)
	if getOwnBody then watchTumble(getOwnBody) end

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
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }

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
	local rotor2Bars = buildRotorRing("Rotor2", surfaceY + 6)
	local rotor1Offset, rotor2Offset = 0, 0

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
	-- 8. Telegraph arcs: one per beam, repositioned per frame ahead of the beam.
	----------------------------------------------------------------------------
	local telegraphs = {}
	local telegraphLen = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS
	local telegraphMid = Config.SWEEP_HUB_RADIUS + telegraphLen / 2
	local telegraphY = surfaceY + 0.15
	do
		for _, beam in ipairs(Config.SWEEP_BEAMS) do
			local color = beam.class == "low" and Config.SWEEP_BEAM_LOW_COLOR or Config.SWEEP_BEAM_HIGH_COLOR
			local cf = radialCFrame(c, beam.baseAngle, telegraphY, telegraphMid)
			local p = counted(newPart(folder, "Telegraph_" .. beam.class, Vector3.new(telegraphLen, 0.2, 1.2),
				cf, color, Enum.Material.Neon, TELEGRAPH_TRANSPARENCY))
			telegraphs[#telegraphs + 1] = { part = p, beam = beam }
		end
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
	-- standby dim. Animated elements (wake/chase/rotor/telegraph) reset to a
	-- safe rest/synced state on flip; the live loop repaints them once running.
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
		for _, t in ipairs(telegraphs) do
			t.part.Transparency = resetTo or TELEGRAPH_TRANSPARENCY
			if not live then
				t.part.CFrame = radialCFrame(c, t.beam.baseAngle, telegraphY, telegraphMid) -- park
			end
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
	RunService.Heartbeat:Connect(function(dt)
		if workspace:GetAttribute("LiveArena") ~= "sweeper" then return end
		local field = Workspace:FindFirstChild("SweeperField")
		local startT = field and field:GetAttribute("RoundStartServerT")
		if not startT then return end
		local elapsed = Workspace:GetServerTimeNow() - startT

		-- Telegraph: leading arc ahead of each beam.
		for _, t in ipairs(telegraphs) do
			local speed = SweeperModel.rampedSpeed(t.beam.baseSpeed, elapsed, speedOpts)
			local angle = SweeperModel.beamAngle(t.beam, 0, speed, elapsed)
			local lead = angle + t.beam.direction * Config.SWEEP_TELEGRAPH_LEAD
			t.part.CFrame = radialCFrame(c, lead, telegraphY, telegraphMid)
		end

		-- Wake channels: ignite behind the low beam, fade back to base over the window.
		local lowSpeed = SweeperModel.rampedSpeed(lowBeam.baseSpeed, elapsed, speedOpts)
		local lowAngle = SweeperModel.beamAngle(lowBeam, 0, lowSpeed, elapsed)
		local window = math.max(Config.SWEEP_WAKE_FADE * lowSpeed, 1e-3)
		for _, w in ipairs(wakeStrips) do
			local behind = (lowBeam.direction * (lowAngle - w.angle)) % TAU
			local target
			if behind >= window then
				target = WAKE_BASE_TRANSPARENCY
			else
				target = WAKE_LIT_TRANSPARENCY + (WAKE_BASE_TRANSPARENCY - WAKE_LIT_TRANSPARENCY) * (behind / window)
			end
			if w.lastTransparency == nil or math.abs(target - w.lastTransparency) > 0.02 then
				w.part.Transparency = target
				w.lastTransparency = target
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
