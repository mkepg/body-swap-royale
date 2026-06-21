--[[
	LobbyArea (server) -- the elevated balcony overlooking the arena.
	Location: ServerScriptService/Server/LobbyArea  (ModuleScript)

	Builds the balcony geometry ONCE (mirrors HazardSystem.build): an anchored
	platform raised above and set back from the arena, fully enclosed by perimeter
	barriers so a controlled body cannot walk off into the void between rounds.
	The arena-facing wall is a transparent-but-CanCollide glass railing so the
	downward view stays open.

	Body POSITIONING on the balcony is owned by BodyManager (via SpawnLayout +
	Config); this module is geometry-only.

	Depends on: ReplicatedStorage.Shared.Config
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LobbyArea = {}

local built = false

local function makePart(name, size, position, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Build the balcony once. A second call is a no-op (singleton).
function LobbyArea.build()
	if built then
		return
	end
	built = true

	local folder = workspace:FindFirstChild("LobbyArea")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LobbyArea"
		folder.Parent = workspace
	end

	local origin = Config.LOBBY_ORIGIN -- pad surface center
	local pad = Config.LOBBY_PAD_SIZE
	local wallH = Config.LOBBY_WALL_HEIGHT
	local wallT = Config.LOBBY_WALL_THICKNESS

	-- Platform: top face at origin.Y (body slots add LOBBY_SPAWN_DROP above it).
	makePart(
		"Platform",
		pad,
		origin - Vector3.new(0, pad.Y / 2, 0),
		Config.LOBBY_COLOR_PAD,
		folder
	)

	-- Perimeter barriers, centered on the wall midline (origin.Y + wallH/2).
	local wallY = origin.Y + wallH / 2
	local halfX = pad.X / 2
	local halfZ = pad.Z / 2

	-- Back wall (-Z, away from the arena) and the two side walls are solid.
	makePart(
		"Wall_Back",
		Vector3.new(pad.X, wallH, wallT),
		Vector3.new(origin.X, wallY, origin.Z - halfZ),
		Config.LOBBY_COLOR_WALL,
		folder
	)

	makePart(
		"Wall_Left",
		Vector3.new(wallT, wallH, pad.Z),
		Vector3.new(origin.X - halfX, wallY, origin.Z),
		Config.LOBBY_COLOR_WALL,
		folder
	)
	makePart(
		"Wall_Right",
		Vector3.new(wallT, wallH, pad.Z),
		Vector3.new(origin.X + halfX, wallY, origin.Z),
		Config.LOBBY_COLOR_WALL,
		folder
	)

	-- Front railing (+Z, faces the arena): CanCollide but transparent so the
	-- downward view is unobstructed. LOAD-BEARING fall protection.
	local rail = makePart(
		"Railing_Front",
		Vector3.new(pad.X, wallH, wallT),
		Vector3.new(origin.X, wallY, origin.Z + halfZ),
		Config.LOBBY_COLOR_WALL,
		folder
	)
	rail.Transparency = Config.LOBBY_RAILING_TRANSPARENCY
	rail.CanCollide = true
end

return LobbyArea
