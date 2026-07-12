--[[
	HazardSystem (server) -- the Hex-A-Gone arena floor (the MVP arena).
	Builds SEVEN stacked hexagonal floors once, then erodes them step-driven during
	Active rounds: a hex arms when a body stands on it, flashes the warning color,
	then vanishes for good (monotonic). Each tile is composed of 5 stock parts -- one
	central Block + four WedgeParts forming the two triangular end-caps -- meeting
	edge-to-edge with NO overlap, so neighbors never share geometry (no z-fighting on
	recolor) and the tile reads as a true hexagon. Each floor has a distinct solid
	color (depth read). Stock parts only: works without the EditableMesh API beta
	(which requires Experience Settings > Security > Allow Mesh/Image Access).

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

	Depends on: ReplicatedStorage.Shared.Config / HexGrid / HexErosionModel
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local HexGrid = require(ReplicatedStorage.Shared.HexGrid)
local HexErosionModel = require(ReplicatedStorage.Shared.HexErosionModel)

local HazardSystem = {}

local SQRT3 = math.sqrt(3)

local tiles = {}       -- array of { parts = {Part, WedgePart×4}, steppedAt, phase, floor, q, r }
local partToTile = {}  -- [BasePart] = tile record; populated in build() for fast contact lookup

-- groundParams is initialised in build() once the HexField folder exists.
-- Include-filter on the HexField only, RespectCanCollide=true so `gone`
-- tiles (CanCollide=false) are never returned -- a body can't stand on a vanished tile.
local groundParams = nil

-- Contact-probe sweep direction: straight down through the feet, HEX_STAND_BAND deep
-- (the height above a floor that counts as standing on it). Constant, so hoisted.
local PROBE_DOWN = Vector3.new(0, -Config.HEX_STAND_BAND, 0)

local function durations()
	return { gone = Config.HEX_GONE_DELAY_SECONDS }
end

-- Solid color for a 0-based floor (clamped to the palette length).
local function floorColor(floor)
	local palette = Config.HEX_FLOOR_COLORS
	return palette[math.min(floor + 1, #palette)]
end

-- Warning color, darkened toward black by GLOW_DIM_HEX_WARNING (0 = full red = original,
-- 1 = black). Precomputed once: the warning is an opaque floor color (not a glow), so
-- "dimming" it darkens the color rather than fading transparency.
local WARNING_COLOR = Config.TILE_COLOR_WARNING:Lerp(Color3.new(), Config.GLOW_DIM_HEX_WARNING)

-- Map a phase to all parts of a tile (caller applies only on change). Solid shows
-- the floor's own color; warning shows the universal red; gone hides + drops collision.
local function applyPhase(tile, phase)
	local canCollide, transparency, color
	if phase == "solid" then
		canCollide, transparency, color = true, 0, floorColor(tile.floor)
	elseif phase == "warning" then
		canCollide, transparency, color = true, 0, WARNING_COLOR
	else -- "gone"
		canCollide, transparency, color = false, 1, floorColor(tile.floor)
	end
	for _, part in ipairs(tile.parts) do
		part.CanCollide = canCollide
		part.Transparency = transparency
		part.Color = color
	end
end

-- Per-cap CFrame.Angles needed so the wedge's slanted triangular face lies flat on
-- TOP of the tile with the right-angle pointing INWARD (toward the hex center).
-- Derived experimentally in Studio; see docs/smoke-tests for the geometry probe.
--   { signX, signZ, yAng, zAng } -- signs pick the quadrant; yAng/zAng in degrees.
local CAP_ROTATIONS = {
	{  1,  1,   0,  -90 }, -- right-upper
	{  1, -1, 180,   90 }, -- right-lower
	{ -1,  1,   0,   90 }, -- left-upper
	{ -1, -1, 180,  -90 }, -- left-lower
}

-- Build one hex tile centered at world (cx, cz) with its TOP surface at surfaceY.
-- Geometry (flat-top, circumradius R, thickness T, inset HEX_GAP from the lattice):
--   1 central Block: x ∈ [-R/2, R/2], z ∈ [-R*sqrt(3)/2, R*sqrt(3)/2]
--   4 WedgeParts as 2 isosceles end-caps (right and left), each cap split into upper
--     and lower halves meeting at z=0. Each wedge is a right triangle with legs R/2
--     and R*sqrt(3)/2; the 4 caps tile the two end-triangles of the hexagon exactly.
-- All 5 parts are anchored, share the same Y and thickness, and DO NOT overlap --
-- they share edges only, so no z-fighting on recolor.
local function buildHexParts(folder, cx, cz, surfaceY, floor, q, r)
	local R = Config.HEX_SIZE - Config.HEX_GAP
	local T = Config.TILE_THICKNESS
	local centerY = surfaceY - T / 2
	local color = floorColor(floor)
	local parts = {}

	local function init(p, suffix)
		p.Anchored = true
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Name = string.format("Hex_%d_%d_%d_%s", floor, q, r, suffix)
		p.Parent = folder
		parts[#parts + 1] = p
	end

	local block = Instance.new("Part")
	block.Size = Vector3.new(R, T, R * SQRT3)
	block.CFrame = CFrame.new(cx, centerY, cz)
	init(block, "B")

	-- The 4 cap wedges. Each wedge bounding box is (T, R/2, R*sqrt(3)/2); after the
	-- per-cap rotation its triangular face lies on top with the right-angle pointing
	-- inward, so the 4 triangles + central block tile the hexagon edge-to-edge.
	local capNames = { "RU", "RL", "LU", "LL" }
	for i, rot in ipairs(CAP_ROTATIONS) do
		local signX, signZ, yAng, zAng = rot[1], rot[2], rot[3], rot[4]
		local wedge = Instance.new("WedgePart")
		wedge.Size = Vector3.new(T, R / 2, R * SQRT3 / 2)
		wedge.CFrame = CFrame.new(cx + signX * (R * 3 / 4), centerY, cz + signZ * (R * SQRT3 / 4))
			* CFrame.Angles(0, math.rad(yAng), math.rad(zAng))
		init(wedge, capNames[i])
	end

	return parts
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

	-- Contact probe: include ONLY the HexField, and respect CanCollide so `gone` tiles
	-- (CanCollide=false) are transparently skipped -- a body can't stand on a vanished tile.
	groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { folder }
	groundParams.RespectCanCollide = true

	-- The pit is a TRUE CIRCLE: clip the hex lattice to HEX_CIRCLE_RADIUS. Over-generate
	-- rings (genRings reaches well past the circle) so the circle is fully tiled.
	local genRings = math.ceil(Config.HEX_CIRCLE_RADIUS / Config.HEX_SIZE) + 1
	local coords = HexGrid.tilesInCircle(genRings, Config.HEX_SIZE, Config.HEX_CIRCLE_RADIUS)
	for floor = 0, Config.HEX_FLOOR_COUNT - 1 do
		local surfaceY = Config.TILE_SURFACE_Y - floor * Config.HEX_FLOOR_GAP
		for _, c in ipairs(coords) do
			local dx, dz = HexGrid.toWorld(c.q, c.r, Config.HEX_SIZE)
			local parts = buildHexParts(folder, dx, dz, surfaceY, floor, c.q, c.r)
			local tile = { parts = parts, steppedAt = nil, phase = "solid", floor = floor, q = c.q, r = c.r }
			tiles[#tiles + 1] = tile
			-- Register every part so the contact probe can map a hit back to its tile record.
			-- Each tile is 5 parts (1 Block + 4 WedgeParts); all must be registered.
			for _, part in ipairs(parts) do
				partToTile[part] = tile
			end
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
-- { position: Vector3, graceBlocked: boolean } (one per alive body; position is the
-- body root's world position). For each sample a small sphere is cast straight down
-- through the body's feet to find the collidable hex tile it is actually standing on
-- (contact-probe arming). This is robust to rim tiles whose lattice neighbor is outside
-- the circle (the old point-sample rounded to a nonexistent tile) and to bodies
-- perched on a tile's edge (where the root's XZ no longer rounds to the right hex).
-- Only collidable parts are returned (groundParams.RespectCanCollide=true), so `gone`
-- tiles are never re-armed. Arms each found tile (grace-gated), then applies the
-- current phase to every tile on change. `now` is os.clock().
function HazardSystem.step(now, samples)
	if Config.HAZARDS_ENABLED and groundParams then
		for _, s in ipairs(samples) do
			-- Find the tile ACTUALLY under this body: sweep a small sphere straight down
			-- from the root through the feet (PROBE_DOWN is HEX_STAND_BAND deep -- the
			-- height above a floor that counts as standing on it). The nearest collidable
			-- hex part is the bearing tile -- robust to rim tiles and edge/perched poses,
			-- unlike a point-sample. Spherecast (not raycast) so a body over the grout seam
			-- still arms a bearing tile (either adjacent tile when squarely over the seam --
			-- both are valid arm targets).
			local hit = workspace:Spherecast(
				s.position, Config.HEX_GROUND_PROBE_RADIUS, PROBE_DOWN, groundParams)
			if hit then
				local tile = partToTile[hit.Instance]
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
