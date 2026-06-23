--[[
	HazardSystem (server) -- the Hex-A-Gone arena floor (the MVP arena).
	Builds THREE stacked hexagonal floors once, then erodes them step-driven during
	Active rounds: a hex arms when a body stands on it, flashes the warning color,
	then vanishes for good (monotonic). Each hex is a cluster of 3 rotated Block
	parts (reads as a hexagon, erodes as a unit) -- no mesh asset, consistent with
	the build-in-code pattern (LobbyArea.build).

	Death is NOT handled here. A body over a `gone` hex falls to the floor below
	(intermediate floors are CanCollide); only a fall off the LOWEST floor crosses
	Config.VOID_Y and is eliminated by the grace-gated void monitor in RoundManager.

	Driven by RoundManager's void monitor (one server loop): each tick it gathers
	body samples and calls HazardSystem.step(now, samples).

	Lifecycle (called by RoundManager):
	  build()          -- once at startup: replace the baseplate, construct 3 hex floors
	  start(startTime) -- beginRound: reset all hexes to solid
	  step(now, samples) -- per tick: arm stepped hexes, apply phases
	  stop()           -- endRound: reset all hexes to solid

	Depends on: ReplicatedStorage.Shared.Config / HexGrid / HexErosionModel
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local HexGrid = require(ReplicatedStorage.Shared.HexGrid)
local HexErosionModel = require(ReplicatedStorage.Shared.HexErosionModel)

local HazardSystem = {}

local SQRT3 = math.sqrt(3)

local tiles = {}      -- array of { parts = {Part,Part,Part}, steppedAt, phase, floor, q, r }
local tileByKey = {}  -- ["floor:q:r"] = tile record

local function keyOf(floor, q, r)
	return floor .. ":" .. q .. ":" .. r
end

local function durations()
	return { gone = Config.HEX_GONE_DELAY_SECONDS }
end

-- Map a phase to a hex tile's 3 parts (caller applies only on change).
local function applyPhase(tile, phase)
	local canCollide, transparency, color
	if phase == "solid" then
		canCollide, transparency, color = true, 0, Config.TILE_COLOR_SOLID
	elseif phase == "warning" then
		canCollide, transparency, color = true, 0, Config.TILE_COLOR_WARNING
	else -- "gone"
		canCollide, transparency, color = false, 1, Config.TILE_COLOR_SOLID
	end
	for _, part in ipairs(tile.parts) do
		part.CanCollide = canCollide
		part.Transparency = transparency
		part.Color = color
	end
end

-- Three Block parts rotated 0/60/120 deg about Y, centered at (cx, *, cz), reading
-- as one flat-top hexagon (a regular hexagon = union of 3 rectangles of size
-- size*sqrt(3) x size). Top faces sit at surfaceY.
local function buildHexParts(folder, cx, cz, surfaceY, floor, q, r)
	local size = Config.HEX_SIZE
	local thickness = Config.TILE_THICKNESS
	local centerY = surfaceY - thickness / 2
	local parts = {}
	for i = 0, 2 do
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(size * SQRT3, thickness, size)
		part.CFrame = CFrame.new(cx, centerY, cz) * CFrame.Angles(0, math.rad(60 * i), 0)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Color = Config.TILE_COLOR_SOLID
		part.Name = string.format("Hex_%d_%d_%d_%d", floor, q, r, i)
		part.Parent = folder
		parts[#parts + 1] = part
	end
	return parts
end

-- Build the 3 stacked hex floors once. The hex field IS the floor, so any leftover
-- floor from the place template is removed: the Baseplate, plus any SpawnLocation
-- (this game never spawns player Characters). Singleton: a second call is a no-op.
function HazardSystem.build()
	if #tiles > 0 then
		return
	end

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local folder = workspace:FindFirstChild("HexField")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "HexField"
		folder.Parent = workspace
	end

	local coords = HexGrid.tiles(Config.HEX_RADIUS)
	for floor = 0, Config.HEX_FLOOR_COUNT - 1 do
		local surfaceY = Config.TILE_SURFACE_Y - floor * Config.HEX_FLOOR_GAP
		for _, c in ipairs(coords) do
			local dx, dz = HexGrid.toWorld(c.q, c.r, Config.HEX_SIZE)
			local parts = buildHexParts(folder, dx, dz, surfaceY, floor, c.q, c.r)
			local tile = { parts = parts, steppedAt = nil, phase = "solid", floor = floor, q = c.q, r = c.r }
			tiles[#tiles + 1] = tile
			tileByKey[keyOf(floor, c.q, c.r)] = tile
		end
	end
end

local function forceAllSolid()
	for _, tile in ipairs(tiles) do
		tile.steppedAt = nil
		tile.phase = "solid"
		applyPhase(tile, "solid")
	end
end

-- Begin an Active round: all hexes solid + un-armed. startTime is accepted for
-- symmetry with the old API but erosion is now driven by step()'s `now`.
function HazardSystem.start(_startTime)
	forceAllSolid()
end

-- Driven each tick by RoundManager's void monitor. samples = array of
-- { dx, dz, y, graceBlocked } (one per alive body, offsets from the field center
-- at origin). Arms the hex each body stands on (grace-gated), then applies the
-- current phase to every tile on change. `now` is os.clock().
function HazardSystem.step(now, samples)
	if Config.HAZARDS_ENABLED then
		for _, s in ipairs(samples) do
			local floor = HexGrid.floorAt(
				s.y, Config.TILE_SURFACE_Y, Config.HEX_FLOOR_GAP, Config.HEX_STAND_BAND, Config.HEX_FLOOR_COUNT)
			if floor then
				local q, r = HexGrid.fromWorld(s.dx, s.dz, Config.HEX_SIZE)
				local tile = tileByKey[keyOf(floor, q, r)]
				if tile then
					tile.steppedAt = HexErosionModel.arm(tile.steppedAt, true, s.graceBlocked, now)
				end
			end
		end
	end
	local dur = durations()
	for _, tile in ipairs(tiles) do
		local phase = HexErosionModel.phaseAt(tile.steppedAt, now, dur)
		if phase ~= tile.phase then
			tile.phase = phase
			applyPhase(tile, phase)
		end
	end
end

-- Stop driving the floor and leave it fully solid + un-armed (Lobby/Ended; parked
-- bodies rest on solid ground next round).
function HazardSystem.stop()
	forceAllSolid()
end

return HazardSystem
