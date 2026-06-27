--[[
	LobbyArea (server) -- the beyblade lobby's LOAD-BEARING geometry: a round
	walkable DISC players stand on, raised and set back over the pit, ringed by an
	INVISIBLE BARRIER (gap-free, taller than a jump) that is the fall protection.
	Location: ServerScriptService/Server/LobbyArea (ModuleScript)

	Body POSITIONING on the disc is owned by BodyManager (SpawnLayout + Config); this
	module is geometry-only. The beyblade's cosmetic body (energy rings, taper, tip,
	spectator souls) is the client LobbyStage's job.

	Depends on: ReplicatedStorage.Shared.Config, ReplicatedStorage.Shared.WorldLayout
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldLayout = require(Shared.WorldLayout)

local LobbyArea = {}

local built = false

-- Build the lobby once. A second call is a no-op (singleton).
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

	local origin = Config.LOBBY_ORIGIN
	local r = Config.LOBBY_DISC_RADIUS
	local th = Config.LOBBY_DISC_THICKNESS

	-- Walkable disc: a CanCollide Cylinder, axis vertical, top face at origin.Y.
	-- A Cylinder's length is its local X; rotate X -> up, Size = (length, dia, dia).
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = true
	disc.Size = Vector3.new(th, r * 2, r * 2)
	disc.CFrame = CFrame.new(origin.X, origin.Y - th / 2, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = Config.LOBBY_DISC_COLOR
	disc.Material = Enum.Material.Metal
	disc.TopSurface = Enum.SurfaceType.Smooth
	disc.BottomSurface = Enum.SurfaceType.Smooth
	disc.Parent = folder

	-- Invisible rim barrier (LOAD-BEARING): a gap-free ring of tall, thin, transparent
	-- CanCollide segments at the disc rim, taller than a jump. Each segment's length is
	-- the chord between adjacent ring points x slack, so neighbours overlap (no gaps).
	local segs = Config.LOBBY_BARRIER_SEGMENTS
	local wallH = Config.LOBBY_WALL_HEIGHT
	local wallT = Config.LOBBY_WALL_THICKNESS
	local pts = WorldLayout.ring(origin.X, origin.Z, r, segs)
	local chord = 2 * r * math.sin(math.pi / segs)
	local segLen = chord * Config.LOBBY_BARRIER_SLACK
	local yMid = origin.Y + wallH / 2
	for i = 1, segs do
		local pt = pts[i]
		local nxt = pts[(i % segs) + 1]
		local seg = Instance.new("Part")
		seg.Name = "Barrier"
		seg.Anchored = true
		seg.CanCollide = true
		seg.Transparency = 1
		seg.Size = Vector3.new(wallT, wallH, segLen)
		seg.CFrame = CFrame.lookAt(Vector3.new(pt.x, yMid, pt.z), Vector3.new(nxt.x, yMid, nxt.z))
		seg.Parent = folder
	end
end

return LobbyArea
