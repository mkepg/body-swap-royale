--[[
	HazardSystem (server) -- the Hex-A-Gone arena floor (the MVP arena).
	Builds SEVEN stacked hexagonal floors once, then erodes them step-driven during
	Active rounds: a hex arms when a body stands on it, flashes the warning color,
	then vanishes for good (monotonic). Each tile is ONE true hexagonal MeshPart
	(built once via EditableMesh from the pure HexPrism geometry, then cloned per
	tile) -- a single surface, so no gaps between neighbors and no z-fighting when a
	stepped tile recolors. Each floor has a distinct solid color (depth read).

	Death is NOT handled here. A body over a `gone` hex falls to the floor below
	(intermediate floors are CanCollide); only a fall off the LOWEST floor crosses
	Config.VOID_Y and is eliminated by the grace-gated void monitor in RoundManager.

	Driven by RoundManager's void monitor (one server loop): each tick it gathers
	body samples and calls HazardSystem.step(now, samples).

	Lifecycle (called by RoundManager):
	  build()          -- once at startup: replace the baseplate, construct 7 hex floors
	  start(startTime) -- beginRound: reset all hexes to solid
	  step(now, samples) -- per tick: arm stepped hexes, apply phases
	  stop()           -- endRound: reset all hexes to solid

	Depends on: ReplicatedStorage.Shared.Config / HexGrid / HexErosionModel / HexPrism
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")
local Config = require(ReplicatedStorage.Shared.Config)
local HexGrid = require(ReplicatedStorage.Shared.HexGrid)
local HexErosionModel = require(ReplicatedStorage.Shared.HexErosionModel)
local HexPrism = require(ReplicatedStorage.Shared.HexPrism)

local HazardSystem = {}

local tiles = {}      -- array of { part = MeshPart, steppedAt, phase, floor, q, r }
local tileByKey = {}  -- ["floor:q:r"] = tile record

local function keyOf(floor, q, r)
	return floor .. ":" .. q .. ":" .. r
end

local function durations()
	return { gone = Config.HEX_GONE_DELAY_SECONDS }
end

-- Solid color for a 0-based floor (clamped to the palette length).
local function floorColor(floor)
	local palette = Config.HEX_FLOOR_COLORS
	return palette[math.min(floor + 1, #palette)]
end

-- Map a phase to a tile's single part (caller applies only on change). Solid shows
-- the floor's own color; warning shows the universal red; gone hides + drops collision.
local function applyPhase(tile, phase)
	local part = tile.part
	if phase == "solid" then
		part.CanCollide = true
		part.Transparency = 0
		part.Color = floorColor(tile.floor)
	elseif phase == "warning" then
		part.CanCollide = true
		part.Transparency = 0
		part.Color = Config.TILE_COLOR_WARNING
	else -- "gone"
		part.CanCollide = false
		part.Transparency = 1
	end
end

-- Build ONE hexagonal-prism MeshPart (the template that every tile clones) from the
-- pure HexPrism geometry via EditableMesh. Hull collision matches the hex exactly
-- (no box-overlap holding bodies up across seams). Falls back to a bounding block
-- if the mesh API fails, so the arena still builds.
local function buildHexTemplate()
	-- Render/collide each tile INSET from the lattice radius (HexGrid still spaces
	-- centers by the full HEX_SIZE), so neighbors leave a grout seam and never share
	-- geometry -- distinct tiles, and no z-fighting when a stepped tile recolors.
	local renderSize = Config.HEX_SIZE - Config.HEX_GAP
	local geom = HexPrism.build(renderSize, Config.TILE_THICKNESS)
	local ok, result = pcall(function()
		local em = AssetService:CreateEditableMesh()
		local ids = {}
		for _, v in ipairs(geom.vertices) do
			ids[#ids + 1] = em:AddVertex(Vector3.new(v[1], v[2], v[3]))
		end
		for _, t in ipairs(geom.triangles) do
			em:AddTriangle(ids[t[1]], ids[t[2]], ids[t[3]])
		end
		return AssetService:CreateMeshPartAsync(Content.fromObject(em), {
			CollisionFidelity = Enum.CollisionFidelity.Hull,
		})
	end)

	local part
	if ok and result then
		part = result
		part.Material = Enum.Material.SmoothPlastic
	else
		warn("[BSR] HexField EditableMesh build failed; using block tiles: " .. tostring(result))
		part = Instance.new("Part")
		part.Size = Vector3.new(renderSize * 2, Config.TILE_THICKNESS, renderSize * math.sqrt(3))
	end
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Build the 7 stacked hex floors once. The hex field IS the floor, so any leftover
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

	local template = buildHexTemplate()
	local coords = HexGrid.tiles(Config.HEX_RADIUS)
	for floor = 0, Config.HEX_FLOOR_COUNT - 1 do
		local surfaceY = Config.TILE_SURFACE_Y - floor * Config.HEX_FLOOR_GAP
		local centerY = surfaceY - Config.TILE_THICKNESS / 2
		for _, c in ipairs(coords) do
			local dx, dz = HexGrid.toWorld(c.q, c.r, Config.HEX_SIZE)
			local part = template:Clone()
			part.CFrame = CFrame.new(dx, centerY, dz)
			part.Name = string.format("Hex_%d_%d_%d", floor, c.q, c.r)
			part.Color = floorColor(floor)
			part.Parent = folder
			local tile = { part = part, steppedAt = nil, phase = "solid", floor = floor, q = c.q, r = c.r }
			tiles[#tiles + 1] = tile
			tileByKey[keyOf(floor, c.q, c.r)] = tile
		end
	end
	template:Destroy()
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
