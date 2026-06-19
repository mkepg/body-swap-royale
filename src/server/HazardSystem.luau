--[[
	HazardSystem (server) -- the disappearing-tile floor (the MVP arena).
	Builds the tile grid once, then drives each tile's appearance + collision from
	the pure TileFieldModel during Active rounds.

	Death is NOT handled here. A body over a `gone` (CanCollide=false) tile falls
	past Config.VOID_Y and is eliminated by the existing void monitor in
	RoundManager -- grace-gated, no new death path.

	Lifecycle (called by RoundManager):
	  build()           -- once at startup: replace the baseplate, construct tiles
	  start(startTime)  -- beginRound: force solid + spin the apply loop
	  stop()            -- endRound: kill the loop + force solid

	Depends on: ReplicatedStorage.Shared.Config / TileFieldModel
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local TileFieldModel = require(ReplicatedStorage.Shared.TileFieldModel)

local HazardSystem = {}

local tiles = {} -- array of { part = Part, offset = number, phase = string }
local roundStart = 0

-- A unique token gates the apply loop; setting it to a new value (or nil) stops
-- any previously-running loop (same pattern as RoundManager's void monitor).
local loopToken = nil

local function durations()
	return {
		solid = Config.TILE_SOLID_SECONDS,
		warning = Config.TILE_WARNING_SECONDS,
		gone = Config.TILE_GONE_SECONDS,
	}
end

-- Map a phase to a tile part's properties. Caller applies only on change.
local function applyPhase(part, phase)
	if phase == "solid" then
		part.CanCollide = true
		part.Transparency = 0
		part.Color = Config.TILE_COLOR_SOLID
	elseif phase == "warning" then
		part.CanCollide = true
		part.Transparency = 0
		part.Color = Config.TILE_COLOR_WARNING
	else -- "gone"
		part.CanCollide = false
		part.Transparency = 1
		part.Color = Config.TILE_COLOR_SOLID -- pre-set so revival shows grey instantly
	end
end

local function forceAllSolid()
	for _, tile in ipairs(tiles) do
		tile.phase = "solid"
		applyPhase(tile.part, "solid")
	end
end

-- Build the tile grid once. The tile field IS the floor, so the baseplate is
-- removed. Singleton: a second call is a no-op (the tiles already exist).
function HazardSystem.build()
	if #tiles > 0 then
		return -- already built; build once at startup
	end

	local existing = workspace:FindFirstChild("Baseplate")
	if existing then
		existing:Destroy()
	end

	local folder = workspace:FindFirstChild("TileField")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "TileField"
		folder.Parent = workspace
	end

	local size = Config.TILE_GRID_SIZE
	local tileSize = Config.TILE_SIZE
	local span = size * tileSize
	-- Center the grid on the X/Z origin; first tile center is at -span/2 + half.
	local originOffset = -span / 2 + tileSize / 2
	-- Position so each tile's TOP face sits at TILE_SURFACE_Y.
	local centerY = Config.TILE_SURFACE_Y - Config.TILE_THICKNESS / 2

	for row = 0, size - 1 do
		for col = 0, size - 1 do
			local part = Instance.new("Part")
			part.Anchored = true
			part.Size = Vector3.new(tileSize, Config.TILE_THICKNESS, tileSize)
			part.Position = Vector3.new(
				originOffset + col * tileSize,
				centerY,
				originOffset + row * tileSize
			)
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Color = Config.TILE_COLOR_SOLID
			part.Name = string.format("Tile_%d_%d", row, col)
			part.Parent = folder
			tiles[#tiles + 1] = {
				part = part,
				offset = TileFieldModel.offsetFor(row, col, Config.TILE_SOLID_SECONDS),
				phase = "solid",
			}
		end
	end
end

-- Begin driving tiles for an Active round. startTime is the server clock value
-- captured by RoundManager at beginRound (os.clock()).
function HazardSystem.start(startTime)
	roundStart = startTime
	forceAllSolid()
	local token = {}
	loopToken = token
	task.spawn(function()
		local dur = durations()
		while loopToken == token do
			local now = os.clock()
			for _, tile in ipairs(tiles) do
				local phase = TileFieldModel.phaseAt(now, roundStart, tile.offset, dur)
				if phase ~= tile.phase then
					tile.phase = phase
					applyPhase(tile.part, phase)
				end
			end
			task.wait(0.1)
		end
	end)
end

-- Stop driving tiles and leave a clean, fully-solid floor (Lobby/Ended; parked
-- bodies rest on solid ground).
function HazardSystem.stop()
	loopToken = nil
	forceAllSolid()
end

return HazardSystem
