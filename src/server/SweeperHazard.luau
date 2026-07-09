--[[
	SweeperHazard (server) -- the Soul Sweeper v2.1 "Jump Club" arena behind the
	ArenaHazard interface. One annulus platform (segmented tangent-box floor) around
	a non-walkable hub pillar, with a fall-gap ring between hub and hole. Two SOLID
	striped machine-bar beams (low/high) are unanchored welded assemblies driven by
	HingeConstraint motors on the anchored hub axle (spec 2026-07-09 §2-4): the
	PHYSICS ENGINE rotates them, so contact impulses (flings, stalls) are real --
	there is no Heartbeat CFrame stepping to desync from what a body actually feels.
	The strike backstop and the reseed scan both read each beam's MEASURED angle off
	its replicated root pose (spec §2-5), so geometry, physics, authority, and (via
	replication) client cosmetics all observe one physical object; there is no
	computed-vs-physical mapping left that could disagree. The backstop remains as a
	force-sweep for a body that RESISTS the shove for SWEEP_RESIST_TICKS in a row.

	Lifecycle (called by RoundManager):
	  build()            -- once at startup: collision groups, annulus, hub, beam assemblies
	  start(now)         -- beginRound: reset clock, publish RoundStartServerT, spin up motors
	  step(now, samples) -- per monitor tick: refresh motor targets + backstop sweeps + reseeds
	  stop()             -- endRound: brake motors, re-park assemblies at baseAngle
	  descriptor()/voidY()/id/spawnCFrame -- ArenaHazard interface

	Depends on: Config / SweeperModel / ArenaDescriptor / WorldLayout.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local Config = require(ReplicatedStorage.Shared.Config)
local SweeperModel = require(ReplicatedStorage.Shared.SweeperModel)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)

local SweeperHazard = {}
SweeperHazard.id = "sweeper"

local built = false
local startClock = 0   -- os.clock() at round start; elapsed = now - startClock
-- { { beam = config, part = Part (the assembly's collidable root spine),
--     hinge = HingeConstraint (the motor), y = centerY }, ... }
local beamRecs = {}

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

-- World pose of a beam assembly's ROOT at a given angle + height: a radial bar
-- spanning hub-to-rim, centered on that span. Shared by the initial build placement
-- and the stop() re-park, so the two can never disagree on where "baseAngle" is.
-- (Unlike v2, nothing else reads this: while live, the physics engine owns the
-- pose and SweeperHazard.step reads it back via measuredAngle -- see spec §2-5.)
local function beamPose(angle, centerY)
	local c = Config.SWEEP_CENTER
	local span = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS
	return CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, -angle, 0)
		* CFrame.new(Config.SWEEP_HUB_RADIUS + span / 2, centerY, 0)
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

-- Turbine hub pillar: a sheer vertical cylinder inside the center hole (the
-- HUB_RADIUS..HOLE_RADIUS band around it is the open fall-gap ring). CanCollide so
-- a body can't walk through it, but it offers no standing surface of its own. Also
-- the anchored axle every beam assembly's motor hinges off of, so its top must clear
-- the thick bar (SWEEP_HUB_TOP is sized to reach past HIGH_BOTTOM + HIGH_THICKNESS).
local function buildHub(folder)
	local c = Config.SWEEP_CENTER
	local below, above = 6, Config.SWEEP_HUB_TOP
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
	return hub
end

local function beamColor(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_COLOR end
	return Config.SWEEP_BEAM_HIGH_COLOR
end

local function beamThickness(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_THICKNESS end
	return Config.SWEEP_BEAM_HIGH_THICKNESS
end

local function beamBottom(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_BOTTOM end
	return Config.SWEEP_BEAM_HIGH_BOTTOM
end

-- One solid striped machine bar: a collidable root spine + alternating welded
-- stripe shells + a rounded end cap + a hub collar, all rigidly welded (so they
-- move as one body), hinged to the anchored hub axle by a torque-capped motor.
-- Everything here is group "SweepBeam" so grace pass-through covers the whole bar,
-- not just the spine.
local function buildBeamAssembly(folder, hubPart, beam)
	local span = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS
	local thick = beamThickness(beam.class)
	local bottom = beamBottom(beam.class)
	local centerY = Config.SWEEP_SURFACE_Y + bottom + thick / 2
	local color = beamColor(beam.class)
	local props = PhysicalProperties.new(Config.SWEEP_BEAM_DENSITY, 0.3, 0.5)
	local c = Config.SWEEP_CENTER

	-- Root spine: the full-span collidable bar (the physics contact surface). Built
	-- and welded while still part of a rigid structure that has NOTHING anchored yet
	-- (default Anchored = false) -- that's safe because no physics step runs between
	-- Instance.new/Parent here and the hinge attachment below (all synchronous Luau,
	-- no yields), so the engine never gets a chance to drop it before the hinge exists.
	local root = Instance.new("Part")
	root.Name = "SweepBeam_" .. beam.class
	root.Size = Vector3.new(span, thick, thick)
	root.CFrame = beamPose(beam.baseAngle, centerY)
	root.Color = color
	root.Material = Enum.Material.SmoothPlastic
	root.CanCollide = true
	root.CollisionGroup = "SweepBeam"
	root.CustomPhysicalProperties = props
	root.Parent = folder

	-- Stripes: alternating cream shells welded onto the spine (slightly proud so the
	-- stripe reads over the base color; non-colliding + massless so the contact
	-- surface and the mass distribution both stay exactly the root spine's box).
	local stripeLen = span / Config.SWEEP_BEAM_STRIPES
	for i = 0, Config.SWEEP_BEAM_STRIPES - 1 do
		if i % 2 == 1 then
			local stripe = Instance.new("Part")
			stripe.Name = root.Name .. "_Stripe" .. i
			stripe.Size = Vector3.new(stripeLen, thick + 0.1, thick + 0.1)
			stripe.CFrame = root.CFrame * CFrame.new(-span / 2 + stripeLen * (i + 0.5), 0, 0)
			stripe.Color = Config.SWEEP_BEAM_STRIPE_COLOR
			stripe.Material = Enum.Material.SmoothPlastic
			stripe.CanCollide = false
			stripe.CollisionGroup = "SweepBeam"
			stripe.Massless = true
			stripe.Parent = folder
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = stripe
			weld.Parent = stripe
		end
	end

	-- End cap (rounded outer tip).
	local cap = Instance.new("Part")
	cap.Name = root.Name .. "_Cap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(thick + 0.4, thick + 0.4, thick + 0.4)
	cap.CFrame = root.CFrame * CFrame.new(span / 2, 0, 0)
	cap.Color = color
	cap.Material = Enum.Material.SmoothPlastic
	cap.CanCollide = false
	cap.CollisionGroup = "SweepBeam"
	cap.Massless = true
	cap.Parent = folder
	local capWeld = Instance.new("WeldConstraint")
	capWeld.Part0 = root
	capWeld.Part1 = cap
	capWeld.Parent = cap

	-- Hub collar (mounts the bar on the axle visually): a short disc, same up/down
	-- cylinder convention as buildHub, radius just past the hub so it never covers
	-- the fall-gap ring (HUB_RADIUS + 1 < SWEEP_HOLE_RADIUS by construction).
	local collar = Instance.new("Part")
	collar.Name = root.Name .. "_Collar"
	collar.Shape = Enum.PartType.Cylinder
	collar.Size = Vector3.new(thick + 1, (Config.SWEEP_HUB_RADIUS + 1) * 2, (Config.SWEEP_HUB_RADIUS + 1) * 2)
	collar.CFrame = CFrame.new(c.X, centerY, c.Z) * CFrame.Angles(0, 0, math.rad(90))
	collar.Color = Config.SWEEP_BEAM_STRIPE_COLOR
	collar.Material = Enum.Material.SmoothPlastic
	collar.CanCollide = false
	collar.CollisionGroup = "SweepBeam"
	collar.Massless = true
	collar.Parent = folder
	local collarWeld = Instance.new("WeldConstraint")
	collarWeld.Part0 = root
	collarWeld.Part1 = collar
	collarWeld.Parent = collar

	-- Motor: anchored hub -> bar assembly, a vertical hinge axis at the hub center.
	--
	-- THE FIDDLY SPOT: Attachment.Axis is expressed in the attachment's OWN local
	-- space, which (since neither attachment below sets a rotation on its own
	-- CFrame) collapses to its PARENT PART's local space. The hub is a Z-rolled
	-- cylinder (buildHub rotates it 90 deg about Z to stand it up), so the hub's
	-- local Y axis does NOT point world-up -- feeding it a bare Vector3.yAxis would
	-- hinge on the wrong axis. `hubPart.CFrame:VectorToObjectSpace(Vector3.yAxis)`
	-- converts world-up INTO the hub's rotated local frame, so a0's WorldAxis comes
	-- back out as true world-up. The bar's root, by contrast, is only ever yawed
	-- about Y (beamPose's CFrame.Angles(0, -angle, 0)), and a pure yaw about Y never
	-- moves the Y basis vector -- so a1's local Y already IS world-up, and
	-- `Vector3.yAxis` needs no conversion. Both attachments must agree on world-up
	-- (not just "an axis"), or the hinge solves against mismatched frames and either
	-- locks up or drifts. Same reasoning for Position: a0 is placed at the hub
	-- center via PointToObjectSpace (the hub's local coordinates of that world
	-- point); a1 is placed at `-(HUB_RADIUS + span/2)` along the bar's local X,
	-- which is exactly the hub center regardless of the bar's current angle (the
	-- root's local origin is its span midpoint, so walking back HUB_RADIUS + span/2
	-- always lands on the pivot) -- so the two attachment points coincide at every
	-- angle, which is what lets the hinge spin freely with zero constraint error.
	local hubCenterWorld = Vector3.new(c.X, centerY, c.Z)
	local a0 = Instance.new("Attachment")
	a0.Position = hubPart.CFrame:PointToObjectSpace(hubCenterWorld)
	a0.Axis = hubPart.CFrame:VectorToObjectSpace(Vector3.yAxis)
	a0.Parent = hubPart

	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-(Config.SWEEP_HUB_RADIUS + span / 2), 0, 0)
	a1.Axis = Vector3.yAxis
	a1.Parent = root

	local hinge = Instance.new("HingeConstraint")
	hinge.Name = root.Name .. "_Motor"
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = Config.SWEEP_BEAM_MOTOR_TORQUE
	hinge.MotorMaxAcceleration = math.huge
	hinge.AngularVelocity = 0
	hinge.Parent = root

	-- Only now does the assembly go live: unanchored + server-owned, so the physics
	-- engine (not a Heartbeat loop) rotates it, and no client's local sim can
	-- override where a big solid bar actually is.
	root.Anchored = false
	root:SetNetworkOwner(nil)

	return { beam = beam, part = root, hinge = hinge, y = centerY }
end

-- Two beam assemblies, one per Config.SWEEP_BEAMS entry, spanning hub-to-rim.
local function buildBeams(folder, hubPart)
	beamRecs = {}
	for _, beam in ipairs(Config.SWEEP_BEAMS) do
		beamRecs[#beamRecs + 1] = buildBeamAssembly(folder, hubPart, beam)
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
	local hub = buildHub(folder)
	buildBeams(folder, hub)
end

-- The bar's CURRENT physical angle: atan2 of its root center's offset from the hub.
-- This is the single angle source of truth (spec 2026-07-09 §2-5) -- the strike
-- backstop, the reseed scan, and (via the replicated CFrame, independently on the
-- client) cosmetics all read this SAME physical pose, so there is no
-- computed-vs-physical mapping left that geometry and authority could disagree on.
local function measuredAngle(rec)
	local c = Config.SWEEP_CENTER
	local pos = rec.part.Position
	return math.atan2(pos.Z - c.Z, pos.X - c.X)
end

function SweeperHazard.start(now)
	startClock = now
	-- Publish the round-start time on the SERVER clock -> client. Beams themselves no
	-- longer need this (their pose is measured, not computed from elapsed) -- kept
	-- because it's harmless and other client cosmetics (chase, rotors) still key off
	-- it (spec 2026-07-09 §2-7).
	local folder = Workspace:FindFirstChild("SweeperField")
	if folder then
		folder:SetAttribute("RoundStartServerT", Workspace:GetServerTimeNow())
	end
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	for _, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = rec.beam.direction * SweeperModel.rampedSpeed(rec.beam.baseSpeed, 0, speedOpts)
	end
end

function SweeperHazard.stop()
	-- Brake the motors, then re-park each (still unanchored, server-owned) assembly
	-- at rest via PivotTo -- welded parts follow rigidly, so one call re-seats the
	-- whole bar (spine + stripes + cap + collar) in one atomic move. Dormant cost is
	-- ~zero: a braked motor holding a resting bar against gravity does no per-frame
	-- Luau work (no Heartbeat connection exists to stop, unlike v2).
	for _, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = 0
		rec.part:PivotTo(beamPose(rec.beam.baseAngle, rec.y))
	end
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

-- Per monitor tick: refresh each motor's ramped target speed, read back each bar's
-- MEASURED angle once (shared by the reseed scan and the strike test below, so both
-- see the identical physical snapshot), then run the on-platform check, validator
-- reseeds near any beam arc, and the resist backstop (a body that stays inside an
-- arc -- resisting the physics shove -- for SWEEP_RESIST_TICKS consecutive ticks is
-- force-swept + SweptAt-stamped by RoundManager). Grace-blocked bodies are skipped
-- entirely (physical pass-through + backstop immunity both apply).
function SweeperHazard.step(now, samples)
	local sweeps, reseeds = {}, {}
	if not Config.HAZARDS_ENABLED then
		return { sweeps = sweeps, reseeds = reseeds }
	end
	local elapsed = now - startClock
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	local c = Config.SWEEP_CENTER

	local beamsNow = {}
	for i, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = rec.beam.direction * SweeperModel.rampedSpeed(rec.beam.baseSpeed, elapsed, speedOpts)
		beamsNow[i] = {
			angle = measuredAngle(rec),
			class = rec.beam.class,
			innerRadius = Config.SWEEP_HUB_RADIUS,
			outerRadius = Config.SWEEP_PLATFORM_RADIUS,
			angularHalfWidth = Config.SWEEP_BEAM_HALF_WIDTH,
		}
	end

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
			for _, b in ipairs(beamsNow) do
				if SweeperModel.angularDistance(angle, b.angle) < Config.SWEEP_BEAM_HALF_WIDTH + Config.SWEEP_RESEED_MARGIN then
					nearArc = true
					break
				end
			end
			if nearArc then reseeds[#reseeds + 1] = s.body end
			-- Backstop: only a body that STAYS in the arc (resisting the physics shove)
			-- for SWEEP_RESIST_TICKS consecutive ticks is force-swept.
			if SweeperModel.isStruckAt({ radius = radius, angle = angle, airborne = airborne }, beamsNow) then
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
