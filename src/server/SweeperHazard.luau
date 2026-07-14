--[[
	SweeperHazard (server) -- the Soul Sweeper v2.3 touch-elimination arena behind
	the ArenaHazard interface. One annulus platform (segmented tangent-box floor)
	around a non-walkable hub pillar, with a fall-gap ring between hub and hole. Two
	NON-COLLIDABLE layered bars (low/high) -- each spine IS the emissive
	class-colored Neon core, framed by dark structural rails top and bottom with a
	rounded Neon tip cap (T4 glow-up, 2026-07-13 spec §4.1) -- are unanchored
	welded assemblies driven by HingeConstraint motors on the anchored hub axle (spec
	2026-07-09 v2.2 §2-4): the PHYSICS ENGINE still rotates them for a smooth,
	desync-proof visual, but CanCollide = false means bodies pass through them
	physically -- a beam TOUCH is not a contact, it is read off the same measured
	pose and turned into an instant elimination (spec §2-1/§2-5): the strike test
	reads each beam's MEASURED angle off its replicated root pose, so geometry,
	physics, authority, and (via replication) client cosmetics all observe one
	physical object; there is no computed-vs-physical mapping left that could
	disagree. No shove, no re-pivot, no knockback, no collision groups: a struck
	non-grace body is routed through RoundManager.eliminateFromHazard, the SAME
	grace-gated chokepoint as void death.

	Lifecycle (called by RoundManager):
	  build()            -- once at startup: annulus, hub, beam assemblies
	  start(now)         -- beginRound: reset clock, publish RoundStartServerT, spin up motors
	  step(now, samples) -- per monitor tick: refresh motor targets + touch-elimination scan
	  stop()             -- endRound: brake motors, re-park assemblies at baseAngle, clear angle history
	  descriptor()/voidY()/id/spawnCFrame -- ArenaHazard interface

	Depends on: Config / SweeperModel / ArenaDescriptor / WorldLayout.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config)
local SweeperModel = require(ReplicatedStorage.Shared.SweeperModel)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local GlowDim = require(ReplicatedStorage.Shared.GlowDim)

local SweeperHazard = {}
SweeperHazard.id = "sweeper"

local built = false
local startClock = 0   -- os.clock() at round start; elapsed = now - startClock
-- { { beam = config, part = Part (the assembly's non-collidable root spine),
--     hinge = HingeConstraint (the motor), y = centerY,
--     angleHist = { measured angles, oldest first } }, ... }
local beamRecs = {}

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

-- Kill band half-width DERIVED from the same thickness that sizes the root spine
-- (spec v2.4 §2-1): hitbox and mesh cannot drift.
local function killHalf(class)
	return SweeperModel.killHalfWidth(beamThickness(class), Config.SWEEP_BODY_CONTACT_PAD)
end

local function beamBottom(class)
	if class == "low" then return Config.SWEEP_BEAM_LOW_BOTTOM end
	return Config.SWEEP_BEAM_HIGH_BOTTOM
end

-- One layered bar (spec §4.1): a non-collidable root spine that IS the emissive
-- class-colored Neon core, plus welded dressing -- dark structural rails framing
-- the glow top and bottom, a rounded Neon tip cap, and a hub collar -- all rigidly
-- welded (so they move as one body), hinged to the anchored hub axle by a
-- torque-capped motor. Every
-- part is CanCollide = false (spec v2.2 §2-4): the bar physically touches nothing,
-- so no collision group is needed either -- a touch is read off the measured pose
-- (SweeperHazard.step), not felt as a physics contact.
local function buildBeamAssembly(folder, hubPart, beam)
	local span = Config.SWEEP_PLATFORM_RADIUS - Config.SWEEP_HUB_RADIUS
	local thick = beamThickness(beam.class)
	local bottom = beamBottom(beam.class)
	local centerY = Config.SWEEP_SURFACE_Y + bottom + thick / 2
	local color = beamColor(beam.class)
	local c = Config.SWEEP_CENTER

	-- Root spine: the full-span bar (drives the assembly's pose + is the strike
	-- test's measured-angle source). Built and welded while still part of a rigid
	-- structure that has NOTHING anchored yet (default Anchored = false) -- that's
	-- safe because no physics step runs between Instance.new/Parent here and the
	-- hinge attachment below (all synchronous Luau, no yields), so the engine never
	-- gets a chance to drop it before the hinge exists.
	local root = Instance.new("Part")
	root.Name = "SweepBeam_" .. beam.class
	root.Size = Vector3.new(span, thick, thick)
	root.CFrame = beamPose(beam.baseAngle, centerY)
	-- T4 glow-up: the spine IS the emissive core (spec §4.1). Because the kill
	-- band derives from this same part's thickness, hitbox<->visual alignment is
	-- exact by construction (v2.4 invariant strengthened).
	root.Color = color
	root.Material = Enum.Material.Neon
	root.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
	root.CanCollide = false
	root.Parent = folder

	-- Dressing only (spec §4.1): the root's SIZE/POSE above stays the strike-math
	-- + wake reference -- everything below is welded, massless, non-colliding cosmetic.
	-- The gameplay tell is now the whole class-colored Neon core (spine + cap)
	-- reading as one emissive capsule; the rails are neutral dark structural shell
	-- framing that glow top and bottom, not a tell of their own.
	local function weldOn(part)
		part.CanCollide = false
		part.Massless = true
		part.Parent = folder
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	-- Layered shell (spec §4.1): dark structural rails frame the glowing core
	-- along its top and bottom edges; a rounded Neon cap closes the rim tip.
	-- Envelope invariant: rails extend 0.25 past the spine's faces (< the 0.3
	-- precedent), so perceived clearance/jump heights are unchanged in practice.
	local RAIL_THICK = 0.25
	local underRail = beam.class == "low" and Config.SWEEP_BEAM_LOW_UNDERRAIL_COLOR
		or Config.SWEEP_BEAM_HIGH_UNDERRAIL_COLOR
	local railLen = span - thick -- stop short of the rounded tip cap
	for _, side in ipairs({
		{ suffix = "_TopRail", yOff = thick / 2 + RAIL_THICK / 2, railColor = Config.SWEEP_RAIL_COLOR },
		{ suffix = "_UnderRail", yOff = -(thick / 2 + RAIL_THICK / 2), railColor = underRail },
	}) do
		local rail = Instance.new("Part")
		rail.Name = root.Name .. side.suffix
		-- Z is 0.3 wider than the core so the rails overhang it laterally and the
		-- shell reads as framing the glow from the side, not just capping it.
		rail.Size = Vector3.new(railLen, RAIL_THICK, thick + 0.3)
		rail.CFrame = root.CFrame * CFrame.new(-thick / 2, side.yOff, 0)
		rail.Color = side.railColor
		rail.Material = Enum.Material.SmoothPlastic
		weldOn(rail)
	end

	local cap = Instance.new("Part")
	cap.Name = root.Name .. "_Cap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = Vector3.new(thick, thick, thick)
	cap.CFrame = root.CFrame * CFrame.new(span / 2, 0, 0)
	cap.Color = color
	cap.Material = Enum.Material.Neon
	cap.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
	weldOn(cap)

	-- Hub collar (mounts the bar on the axle visually): a short disc, same up/down
	-- cylinder convention as buildHub, radius just past the hub so it never covers
	-- the fall-gap ring (HUB_RADIUS + 1 < SWEEP_HOLE_RADIUS by construction).
	local collar = Instance.new("Part")
	collar.Name = root.Name .. "_Collar"
	collar.Shape = Enum.PartType.Cylinder
	collar.Size = Vector3.new(thick + 1, (Config.SWEEP_HUB_RADIUS + 1) * 2, (Config.SWEEP_HUB_RADIUS + 1) * 2)
	collar.CFrame = CFrame.new(c.X, centerY, c.Z) * CFrame.Angles(0, 0, math.rad(90))
	collar.Color = Config.SWEEP_PLATFORM_COLOR
	collar.Material = Enum.Material.Metal
	weldOn(collar)

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

	return { beam = beam, part = root, hinge = hinge, y = centerY, angleHist = {} }
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
-- test and (via the replicated CFrame, independently on the client) cosmetics all
-- read this SAME physical pose, so there is no computed-vs-physical mapping left
-- that geometry and authority could disagree on.
local function measuredAngle(rec)
	local c = Config.SWEEP_CENTER
	local pos = rec.part.Position
	return math.atan2(pos.Z - c.Z, pos.X - c.X)
end

-- Motor target for a beam. NEGATED on purpose: the hinge's +AngularVelocity spins
-- by the right-hand rule about the world-up axis (+X toward -Z), which DECREASES
-- our measured atan2(Z, X) angle -- verified live via the Task 6 spin probe. The
-- negation restores the system-wide convention every consumer assumes (Config
-- comments, the client wake's "behind" math): direction = +1 means the bar's
-- MEASURED angle increases over time.
local function motorTarget(beam, elapsed, speedOpts)
	return -beam.direction * SweeperModel.rampedSpeed(beam.baseSpeed, elapsed, speedOpts)
end

function SweeperHazard.start(now)
	startClock = now
	-- Publish the round-start time on the SERVER clock -> client. Beams themselves no
	-- longer need this (their pose is measured, not computed from elapsed), and the
	-- T4 glow-up retired its last cosmetic consumers (chase/rotors) -- kept anyway as
	-- a cheap, harmless round-start stamp for future consumers/diagnostics.
	local folder = Workspace:FindFirstChild("SweeperField")
	if folder then
		folder:SetAttribute("RoundStartServerT", Workspace:GetServerTimeNow())
	end
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	for _, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = motorTarget(rec.beam, 0, speedOpts)
	end
end

function SweeperHazard.stop()
	-- Brake the motors, then re-park each (still unanchored, server-owned) assembly
	-- at rest via PivotTo -- welded parts follow rigidly, so one call re-seats the
	-- whole bar (spine + dressing + collar) in one atomic move.
	--
	-- The hinge MUST be disabled around the pivot (verified live 2026-07-09): an
	-- ACTIVE HingeConstraint maintains its own accumulated-angle state, and the
	-- solver snaps a pivoted assembly straight back to that angle on the next
	-- physics step -- bars were starting rounds at arbitrary leftover angles
	-- (~41 deg) instead of baseAngle, breaking the same-side formation. Disabling
	-- the hinge, zeroing the assembly's residual velocities, pivoting, and
	-- re-enabling makes the constraint re-derive its angle from the new attachment
	-- poses, so the park sticks.
	--
	-- Dormant cost stays ~zero (a braked motor holding a resting bar does no
	-- per-frame Luau work). Clearing angleHist means the NEXT round's first ticks
	-- have no lagged window yet (SweeperModel.delayedWindow returns nil -> strike
	-- test skipped, covered by round-start grace), so this re-park jump can never
	-- be read as a (potentially kill-wide) swept arc.
	for _, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = 0
		rec.hinge.Enabled = false
		rec.part.AssemblyLinearVelocity = Vector3.zero
		rec.part.AssemblyAngularVelocity = Vector3.zero
		rec.part:PivotTo(beamPose(rec.beam.baseAngle, rec.y))
		rec.hinge.Enabled = true
		rec.angleHist = {}
	end
end

function SweeperHazard.descriptor() return ArenaDescriptor.sweeper() end
function SweeperHazard.voidY() return Config.SWEEP_VOID_Y end

-- Round spawn slot: an evenly-spaced ARC at mid-annulus radius, centered on the far
-- side from where both beams park (spec v2.3 §2-4), facing the hub.
-- Slots are assigned MIDDLE-OUT (player 1 takes the arc center, later players
-- alternate outward), so small rosters cluster at the point farthest from the
-- parked bars instead of stacking up at one arc edge nearest the incoming sweep
-- (found live 2026-07-09: a solo tester spawned at the 110-degree edge and met
-- the low bar ~1.5 s early).
function SweeperHazard.spawnCFrame(index)
	local c = Config.SWEEP_CENTER
	local pts = WorldLayout.arc(c.X, c.Z, Config.SWEEP_SPAWN_RADIUS, Config.LOBBY_CAPACITY,
		Config.SWEEP_SPAWN_CENTER_ANGLE, Config.SWEEP_SPAWN_ARC)
	local n = #pts
	local k = math.min(index, n)
	local center = math.ceil(n / 2)
	local mag = math.floor(k / 2)
	local pt = pts[math.clamp(center + ((k % 2 == 0) and mag or -mag), 1, n)]
	-- Spawn AT standing root height (measured 3.0; see SWEEP_AIRBORNE_BAND): a
	-- taller drop's landing bounce read as horizontal movement and ended the
	-- round-start grace at the 0.5 s floor instead of the full window.
	local pos = Vector3.new(pt.x, Config.SWEEP_SURFACE_Y + 3, pt.z)
	return CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
end

-- Per monitor tick: refresh each motor's ramped target speed, push each bar's
-- MEASURED angle onto its history, then strike-test the sweep window ending
-- SWEEP_STRIKE_LAG_TICKS ticks ago (SweeperModel.delayedWindow -> isStruckSwept):
-- the swept interval covers the arc's full motion between samples (no rotation
-- speed can tunnel past a player between 10 Hz ticks), and the LAG makes the kill
-- land on the pose clients actually SEE (replication interpolation trails the
-- authoritative pose -- spec v2.4 §2-2). A struck non-grace on-platform body is
-- queued for elimination via the SAME grace-gated chokepoint as void death
-- (RoundManager.eliminateFromHazard). Grace-blocked / off-platform bodies are
-- skipped entirely (no strike test run).
function SweeperHazard.step(now, samples)
	local eliminations = {}
	if not Config.HAZARDS_ENABLED then
		return { eliminations = eliminations }
	end
	local elapsed = now - startClock
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	local c = Config.SWEEP_CENTER

	local beamsNow = {}
	for _, rec in ipairs(beamRecs) do
		rec.hinge.AngularVelocity = motorTarget(rec.beam, elapsed, speedOpts)
		local hist = rec.angleHist
		hist[#hist + 1] = measuredAngle(rec)
		-- Cap the history at what delayedWindow can ever read (lag + window pair).
		if #hist > Config.SWEEP_STRIKE_LAG_TICKS + 2 then
			table.remove(hist, 1)
		end
		if Config.SWEEP_LAG_PROBE and rec.beam.class == "low" then
			rec.part:SetAttribute("AuthAngle", hist[#hist])
		end
		local angle, prevAngle = SweeperModel.delayedWindow(hist, Config.SWEEP_STRIKE_LAG_TICKS)
		if angle then
			beamsNow[#beamsNow + 1] = {
				angle = angle,
				prevAngle = prevAngle,
				direction = rec.beam.direction,
				class = rec.beam.class,
				innerRadius = Config.SWEEP_HUB_RADIUS,
				outerRadius = Config.SWEEP_PLATFORM_RADIUS,
				killHalfWidth = killHalf(rec.beam.class),
			}
		end
	end

	for _, s in ipairs(samples) do
		local dx, dz = s.position.X - c.X, s.position.Z - c.Z
		local radius = math.sqrt(dx * dx + dz * dz)
		local dy = s.position.Y - Config.SWEEP_SURFACE_Y
		-- Asymmetric vertical band (spec v2.3 §2-2): a jump-apex root reaches 10.2
		-- studs, so the old symmetric +/-6 made a jumper unhittable near apex. Below
		-- -SWEEP_STAND_BAND still skips a body fallen into the gap.
		local onPlatform = radius >= Config.SWEEP_HUB_RADIUS and radius <= Config.SWEEP_PLATFORM_RADIUS
			and dy >= -Config.SWEEP_STAND_BAND and dy <= Config.SWEEP_STAND_BAND_UP
		if onPlatform and not s.graceBlocked then
			local angle = math.atan2(dz, dx)
			local airborne = dy > Config.SWEEP_AIRBORNE_BAND or (s.velocityY or 0) > Config.SWEEP_AIRBORNE_VY
			if SweeperModel.isStruckSwept({ radius = radius, angle = angle, airborne = airborne }, beamsNow) then
				eliminations[#eliminations + 1] = s.player
			end
		end
	end
	return { eliminations = eliminations }
end

return SweeperHazard
