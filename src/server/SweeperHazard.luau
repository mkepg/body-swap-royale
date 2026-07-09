--[[
	SweeperHazard (server) -- the Soul Sweeper v2 "Soul Turbine" arena behind the
	ArenaHazard interface. One annulus platform (segmented tangent-box floor) around
	a non-walkable hub pillar, with a fall-gap ring between hub and hole. Two SOLID
	beam parts (low/high) are server Heartbeat-animated from the same pure
	SweeperModel.beamAngle/rampedSpeed math the strike backstop uses, so geometry,
	physics, and authority can never desync. The owning client's own physics
	resolves the shove locally (smooth); the server-side strike math is a backstop
	that force-sweeps a body that RESISTS the shove for SWEEP_RESIST_TICKS in a row.

	Lifecycle (called by RoundManager):
	  build()            -- once at startup: collision groups, annulus, hub, beams
	  start(now)         -- beginRound: reset clock, publish RoundStartServerT, animate
	  step(now, samples) -- per monitor tick: backstop sweeps + validator reseeds
	  stop()             -- endRound: freeze animation, park beams at baseAngle
	  descriptor()/voidY()/id/spawnCFrame -- ArenaHazard interface

	Depends on: Config / SweeperModel / ArenaDescriptor / WorldLayout.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Config = require(ReplicatedStorage.Shared.Config)
local SweeperModel = require(ReplicatedStorage.Shared.SweeperModel)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

local SweeperHazard = {}
SweeperHazard.id = "sweeper"

local built = false
local startClock = 0   -- os.clock() at round start; elapsed = now - startClock
local animConn = nil
local beamRecs = {}    -- { { beam = config, part = Part, y = height }, ... }
local activeBeams = {} -- beam configs + { innerRadius, outerRadius, angularHalfWidth } (v1 tierBeams pattern)

-- strikeTicks[body] = consecutive struck ticks (anti-cheat resist-backstop debounce).
-- Cleared explicitly whenever a body stops being struck / leaves the platform (the
-- practical cases); keyed weakly so a destroyed body's stray entry can never leak.
local strikeTicks = setmetatable({}, { __mode = "k" })

-- Collision groups: registered ONCE in build() (before any body can be flagged), so
-- solid beams never collide with a just-swapped grace body. pcall-guarded because
-- RegisterCollisionGroup errors if the group already exists (hot Studio reloads).
local function ensureCollisionGroups()
	pcall(function() PhysicsService:RegisterCollisionGroup("SweepBeam") end)
	pcall(function() PhysicsService:RegisterCollisionGroup("GraceBody") end)
	PhysicsService:CollisionGroupSetCollidable("SweepBeam", "GraceBody", false)
end

-- Beam world CFrame for a given angle + height offset above the surface. Shared by
-- the static park (build/stop) and the live Heartbeat animation (start), so the
-- rendered part and the strike math can never disagree on WHERE a given angle is.
--
-- NOTE the `-angle` yaw: Roblox yaw is counter-clockwise about +Y while the strike
-- math's atan2(z, x) angles increase clockwise when viewed from +Y (+Z toward the
-- viewer) -- the beam part and the strike math MUST agree on this. Task 9 verifies
-- it live with a stationary-probe test. If they disagree, flip the sign HERE, never
-- in the pure SweeperModel.
local function beamCFrame(beam, angle, y)
	local c = Config.SWEEP_CENTER
	local mid = Config.SWEEP_HUB_RADIUS + (Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS) / 2
	return CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, -angle, 0) * CFrame.new(mid, Config.SWEEP_SURFACE_Y + y, 0)
end

-- Segmented annulus floor: SWEEP_PLATFORM_SEGMENTS anchored tangent boxes on a ring
-- at the mid-radius, coplanar tops at SWEEP_SURFACE_Y, overlap slack so there is no
-- seam-catching. Orientation copies the proven LobbyArea barrier-segment convention
-- (CFrame.lookAt(pt, next) so the LOCAL Z axis is tangential -- Size.Z is the chord
-- length, Size.X is the radial width, Size.Y is the vertical thickness).
local function buildAnnulus(folder)
	local c = Config.SWEEP_CENTER
	local segments = Config.SWEEP_PLATFORM_SEGMENTS
	local midRadius = (Config.SWEEP_HOLE_RADIUS + Config.SWEEP_PLATFORM_RADIUS) / 2
	local radialWidth = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HOLE_RADIUS
	local chord = 2 * midRadius * math.sin(math.pi / segments)
	local segLen = chord * Config.SWEEP_SEGMENT_SLACK
	local floorY = Config.SWEEP_SURFACE_Y - Config.SWEEP_PLATFORM_THICKNESS / 2
	local pts = WorldLayout.ring(c.X, c.Z, midRadius, segments)
	for i = 1, segments do
		local pt = pts[i]
		local nxt = pts[(i % segments) + 1]
		local seg = Instance.new("Part")
		seg.Name = string.format("SweepFloor_%d", i)
		seg.Anchored = true
		seg.CanCollide = true
		seg.Size = Vector3.new(radialWidth, Config.SWEEP_PLATFORM_THICKNESS, segLen)
		seg.CFrame = CFrame.lookAt(Vector3.new(pt.x, floorY, pt.z), Vector3.new(nxt.x, floorY, nxt.z))
		seg.Color = Config.SWEEP_PLATFORM_COLOR
		seg.Material = Enum.Material.Glass
		-- Hybrid skin: swap the stock look for the sourced MaterialVariant when
		-- configured ("" keeps Glass). An unknown variant name renders the base.
		if Config.SWEEP_DISC_MATERIAL ~= "" then
			seg.Material = Enum.Material[Config.SWEEP_DISC_MATERIAL_BASE]
			seg.MaterialVariant = Config.SWEEP_DISC_MATERIAL
		end
		seg.Transparency = 0
		seg.TopSurface = Enum.SurfaceType.Smooth
		seg.BottomSurface = Enum.SurfaceType.Smooth
		seg.Parent = folder
	end
end

-- Turbine hub pillar: a sheer vertical cylinder inside the center hole (the r
-- HUB_RADIUS..HOLE_RADIUS band around it is the open fall-gap ring). CanCollide so
-- a body can't walk through it, but it offers no standing surface of its own.
local function buildHub(folder)
	local c = Config.SWEEP_CENTER
	local below, above = 6, 8
	local hub = Instance.new("Part")
	hub.Name = "SweepHub"
	hub.Anchored = true
	hub.CanCollide = true
	hub.Shape = Enum.PartType.Cylinder
	-- Cylinder length is along local X; rotate 90 deg about Z so the round faces
	-- point up/down (a vertical pillar). Size = (height, diameter, diameter).
	hub.Size = Vector3.new(below + above, Config.SWEEP_HUB_RADIUS * 2, Config.SWEEP_HUB_RADIUS * 2)
	hub.CFrame = CFrame.new(c.X, Config.SWEEP_SURFACE_Y + (above - below) / 2, c.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	hub.Color = Config.SWEEP_PLATFORM_COLOR
	hub.Material = Enum.Material.Metal
	hub.Parent = folder
end

local function beamColor(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_COLOR end
	return Config.SWEEP_BEAM_HIGH_COLOR
end

local function beamHeight(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_Y end
	return Config.SWEEP_BEAM_HIGH_Y
end

-- Two solid collidable beam parts, one per Config.SWEEP_BEAMS entry, spanning
-- hub-to-rim. Also builds `activeBeams` (v1 tierBeams pattern): the same beam
-- config plus the radius band + arc half-width the pure strike math reads.
local function buildBeams(folder)
	local span = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS
	beamRecs = {}
	activeBeams = {}
	for _, beam in ipairs(Config.SWEEP_BEAMS) do
		local y = beamHeight(beam.class)
		local part = Instance.new("Part")
		part.Name = "SweepBeam_" .. beam.class
		part.Anchored = true
		part.CanCollide = true
		part.CollisionGroup = "SweepBeam"
		part.Size = Vector3.new(span, Config.SWEEP_BEAM_SIZE.Y, Config.SWEEP_BEAM_SIZE.Z)
		part.CFrame = beamCFrame(beam, beam.baseAngle, y)
		part.Material = Enum.Material.Neon
		-- Hybrid skin: deliberately Neon by default (Config.SWEEP_BEAM_MATERIAL = "");
		-- the slot swaps in a textured variant if one is ever sourced.
		if Config.SWEEP_BEAM_MATERIAL ~= "" then
			part.Material = Enum.Material[Config.SWEEP_BEAM_MATERIAL_BASE]
			part.MaterialVariant = Config.SWEEP_BEAM_MATERIAL
		end
		part.Color = beamColor(beam.class)
		part.Parent = folder

		beamRecs[#beamRecs + 1] = { beam = beam, part = part, y = y }
		activeBeams[#activeBeams + 1] = {
			baseAngle = beam.baseAngle,
			direction = beam.direction,
			baseSpeed = beam.baseSpeed,
			armCount = beam.armCount,
			class = beam.class,
			innerRadius = Config.SWEEP_HUB_RADIUS,
			outerRadius = Config.SWEEP_PLATFORM_RADIUS,
			angularHalfWidth = Config.SWEEP_BEAM_HALF_WIDTH,
		}
	end
end

function SweeperHazard.build()
	if built then return end
	built = true

	ensureCollisionGroups()

	-- The sweeper field IS the floor: remove the place template's baseplate + spawns
	-- (idempotent alongside HexHazard.build -- whichever arena builds first destroys
	-- them; the second no-ops since the children are already gone).
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then baseplate:Destroy() end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then child:Destroy() end
	end

	local folder = Workspace:FindFirstChild("SweeperField")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "SweeperField"
		folder.Parent = Workspace
	end

	buildAnnulus(folder)
	buildHub(folder)
	buildBeams(folder)
end

-- Beam angular speed factoring in the ramp (shared by animation + step's near-arc scan).
local function angleOf(beam, elapsed)
	local speed = SweeperModel.rampedSpeed(beam.baseSpeed, elapsed,
		{ rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX })
	return SweeperModel.beamAngle(beam, 0, speed, elapsed)
end

-- Heartbeat animation: connected ONLY while this arena is the live one (start/stop
-- gate the connection), so a dormant sweeper performs zero per-frame work.
local function startAnimation()
	if animConn then return end
	animConn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startClock
		for _, rec in ipairs(beamRecs) do
			rec.part.CFrame = beamCFrame(rec.beam, angleOf(rec.beam, elapsed), rec.y)
		end
	end)
end

local function stopAnimation()
	if animConn then
		animConn:Disconnect()
		animConn = nil
	end
	for _, rec in ipairs(beamRecs) do
		rec.part.CFrame = beamCFrame(rec.beam, rec.beam.baseAngle, rec.y) -- park at rest
	end
end

function SweeperHazard.start(now)
	startClock = now
	-- Publish the round-start time on the SERVER clock -> client, so cosmetic beams
	-- render at the same elapsed the server strike math uses (both real seconds).
	local folder = Workspace:FindFirstChild("SweeperField")
	if folder then
		folder:SetAttribute("RoundStartServerT", Workspace:GetServerTimeNow())
	end
	startAnimation()
end

function SweeperHazard.stop()
	stopAnimation()
end

function SweeperHazard.descriptor() return ArenaDescriptor.sweeper() end
function SweeperHazard.voidY() return Config.SWEEP_VOID_Y end

-- Round spawn slot: an evenly-spaced ring at mid-annulus radius, facing the hub.
function SweeperHazard.spawnCFrame(index)
	local c = Config.SWEEP_CENTER
	local pts = WorldLayout.ring(c.X, c.Z, Config.SWEEP_SPAWN_RADIUS, Config.LOBBY_CAPACITY)
	local pt = pts[math.min(index, #pts)]
	local pos = Vector3.new(pt.x, Config.SWEEP_SURFACE_Y + 5, pt.z)
	return CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
end

-- Per monitor tick: on-platform check, validator reseeds near any beam arc, and the
-- resist backstop (a body that stays inside an arc -- resisting the physics shove --
-- for SWEEP_RESIST_TICKS consecutive ticks is force-swept + SweptAt-stamped by
-- RoundManager). Grace-blocked bodies are skipped entirely (physical pass-through +
-- backstop immunity both apply).
function SweeperHazard.step(now, samples)
	local sweeps, reseeds = {}, {}
	if not Config.HAZARDS_ENABLED then
		return { sweeps = sweeps, reseeds = reseeds }
	end
	local elapsed = now - startClock
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	local c = Config.SWEEP_CENTER
	for _, s in ipairs(samples) do
		local dx, dz = s.position.X - c.X, s.position.Z - c.Z
		local radius = math.sqrt(dx * dx + dz * dz)
		local dy = s.position.Y - Config.SWEEP_SURFACE_Y
		local onPlatform = radius >= Config.SWEEP_HUB_RADIUS and radius <= Config.SWEEP_PLATFORM_RADIUS
			and math.abs(dy) <= Config.SWEEP_STAND_BAND
		if onPlatform and not s.graceBlocked then
			local angle = math.atan2(dz, dx)
			local airborne = dy > Config.SWEEP_AIRBORNE_BAND or (s.velocityY or 0) > Config.SWEEP_AIRBORNE_VY
			-- Reseed movement validation for any body in/near an arc (beam shoves are
			-- huge input-less displacements the validator must not score).
			local nearArc = false
			for _, beam in ipairs(activeBeams) do
				local a = angleOf(beam, elapsed)
				if SweeperModel.angularDistance(angle, a) < Config.SWEEP_BEAM_HALF_WIDTH + Config.SWEEP_RESEED_MARGIN then
					nearArc = true
					break
				end
			end
			if nearArc then reseeds[#reseeds + 1] = s.body end
			-- Backstop: only a body that STAYS in the arc (resisting the physics shove)
			-- for SWEEP_RESIST_TICKS consecutive ticks is force-swept.
			if SweeperModel.isStruck({ radius = radius, angle = angle, airborne = airborne },
				activeBeams, elapsed, speedOpts) then
				strikeTicks[s.body] = (strikeTicks[s.body] or 0) + 1
				if strikeTicks[s.body] >= Config.SWEEP_RESIST_TICKS then
					strikeTicks[s.body] = nil
					local tx, tz = SweeperModel.outwardTarget(dx, dz, 0, 0,
						Config.SWEEP_PLATFORM_RADIUS + Config.SWEEP_OFF_MARGIN)
					sweeps[#sweeps + 1] = { player = s.player, body = s.body,
						target = CFrame.new(c.X + tx, s.position.Y, c.Z + tz) }
				end
			else
				strikeTicks[s.body] = nil
			end
		else
			strikeTicks[s.body] = nil
		end
	end
	return { sweeps = sweeps, reseeds = reseeds }
end

return SweeperHazard
