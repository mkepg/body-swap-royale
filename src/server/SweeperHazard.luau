--[[
	SweeperHazard (server) -- the Soul Sweeper arena behind the ArenaHazard interface.
	Builds SWEEP_TIER_COUNT stacked circular COLLISION discs, WIDENING downward so a body
	swept off an upper disc's rim lands on the wider tier below; only a fall off the bottom
	disc crosses SWEEP_VOID_Y. Beams are cosmetic (client SweeperController); strikes are
	pure server math (SweeperModel), applied as outward re-pivot "sweeps" returned to
	RoundManager. No beam part ever collides with a body.

	Depends on: Config / SweeperModel / ArenaDescriptor.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config)
local SweeperModel = require(ReplicatedStorage.Shared.SweeperModel)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)

local SweeperHazard = {}
SweeperHazard.id = "sweeper"

local tiers = {}      -- [k+1] = { surfaceY, radius, beams }  (0-based tier k)
local startClock = 0  -- os.clock() at round start; elapsed = now - startClock

local function tierRadius(k) return Config.SWEEP_TOP_RADIUS + k * Config.SWEEP_RADIUS_STEP end
local function tierSurfaceY(k) return Config.SWEEP_TOP_SURFACE_Y - k * Config.SWEEP_TIER_GAP end

-- Attach the radius band + arc half-width to each beam config (the pure model reads them).
local function tierBeams(k, radius)
	local out = {}
	for _, b in ipairs(Config.SWEEP_TIER_BEAMS[k + 1] or {}) do
		out[#out + 1] = {
			baseAngle = b.baseAngle, direction = b.direction, baseSpeed = b.baseSpeed,
			armCount = b.armCount, class = b.class,
			innerRadius = Config.SWEEP_HUB_RADIUS,
			outerRadius = radius,
			angularHalfWidth = Config.SWEEP_BEAM_HALF_WIDTH,
		}
	end
	return out
end

local function makeDisc(folder, k)
	local r = tierRadius(k)
	local surfaceY = tierSurfaceY(k)
	local disc = Instance.new("Part")
	disc.Name = string.format("SweepDisc_%d", k)
	disc.Anchored = true
	disc.Shape = Enum.PartType.Cylinder
	-- Cylinder length is along local X; rotate 90° about Z so the round faces point up/down
	-- (a flat horizontal disc). Size = (thickness, diameter, diameter).
	disc.Size = Vector3.new(Config.SWEEP_DISC_THICKNESS, r * 2, r * 2)
	disc.CFrame = CFrame.new(0, surfaceY - Config.SWEEP_DISC_THICKNESS / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = Config.SWEEP_TIER_COLORS[math.min(k + 1, #Config.SWEEP_TIER_COLORS)]
	disc.Material = Enum.Material.SmoothPlastic
	disc.TopSurface = Enum.SurfaceType.Smooth
	disc.BottomSurface = Enum.SurfaceType.Smooth
	disc.Parent = folder

	-- Central emitter hub (procedural cone fallback for the hero mesh; the mesh is wired
	-- in the MCP task). Cosmetic + non-colliding, but server-built so it exists in both.
	local hub = Instance.new("Part")
	hub.Name = string.format("SweepHub_%d", k)
	hub.Anchored = true
	hub.CanCollide = false
	hub.Shape = Enum.PartType.Cylinder
	hub.Size = Vector3.new(4, Config.SWEEP_HUB_RADIUS * 2, Config.SWEEP_HUB_RADIUS * 2)
	hub.CFrame = CFrame.new(0, surfaceY + 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	hub.Color = Config.SWEEP_TIER_COLORS[math.min(k + 1, #Config.SWEEP_TIER_COLORS)]
	hub.Material = Enum.Material.Neon
	hub.Parent = folder
end

function SweeperHazard.build()
	if #tiers > 0 then return end
	-- The sweeper field IS the floor: remove the place template's baseplate + spawns.
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
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		local r = tierRadius(k)
		makeDisc(folder, k)
		tiers[k + 1] = { surfaceY = tierSurfaceY(k), radius = r, beams = tierBeams(k, r) }
	end
end

function SweeperHazard.start(now)
	startClock = now
	-- Publish the round-start time on the SERVER clock -> client, so the cosmetic beams
	-- render at the same elapsed the server strike math uses (both measure real seconds).
	local folder = Workspace:FindFirstChild("SweeperField")
	if folder then
		folder:SetAttribute("RoundStartServerT", Workspace:GetServerTimeNow())
	end
end

function SweeperHazard.stop() end

function SweeperHazard.descriptor() return ArenaDescriptor.sweeper() end
function SweeperHazard.voidY() return Config.SWEEP_VOID_Y end

-- TEMPORARY stub (Task 5 replaces this with the real ring-spawn math per the v2
-- spec) -- exists only so ArenaHazard.validate passes on the v1 geometry that is
-- still in place here.
function SweeperHazard.spawnCFrame(_index)
	return CFrame.new(Config.SWEEP_CENTER + Vector3.new(0, 5, 0))
end

-- Which tier is this Y on? The tier whose surface is at/just above the body within
-- SWEEP_STAND_BAND. Returns the tier record + its 0-based index, or nil (mid-fall).
local function tierAt(y)
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		local surfaceY = tierSurfaceY(k)
		if y <= surfaceY + Config.SWEEP_STAND_BAND and y >= surfaceY - Config.SWEEP_STAND_BAND then
			return tiers[k + 1], k
		end
	end
	return nil, nil
end

function SweeperHazard.step(now, samples)
	local sweeps = {}
	if not Config.HAZARDS_ENABLED then
		return { sweeps = sweeps }
	end
	local elapsed = now - startClock
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }
	for _, s in ipairs(samples) do
		if not s.graceBlocked then -- grace-protected bodies are never swept (free immunity)
			local pos = s.position
			local tier = tierAt(pos.Y)
			if tier then
				local dx, dz = pos.X, pos.Z -- center is (0,0)
				local radius = math.sqrt(dx * dx + dz * dz)
				local angle = math.atan2(dz, dx)
				local airborne = (pos.Y - tier.surfaceY) > Config.SWEEP_AIRBORNE_BAND
					or (s.velocityY or 0) > Config.SWEEP_AIRBORNE_VY
				if SweeperModel.isStruck({ radius = radius, angle = angle, airborne = airborne },
					tier.beams, elapsed, speedOpts) then
					local tx, tz = SweeperModel.outwardTarget(dx, dz, 0, 0, tier.radius + Config.SWEEP_OFF_MARGIN)
					-- Horizontal shove to just past the rim at the body's current height;
					-- gravity then drops it onto the wider tier below (or the void at the bottom).
					local target = CFrame.new(tx, pos.Y, tz)
					sweeps[#sweeps + 1] = { player = s.player, body = s.body, target = target }
				end
			end
		end
	end
	return { sweeps = sweeps }
end

return SweeperHazard
