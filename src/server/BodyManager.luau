--[[
	BodyManager (server)
	Location: ServerScriptService/Server/BodyManager  (ModuleScript)

	Creates one PERSISTENT body per player, baked once with that player's avatar
	appearance (their cosmetics live here -- the Soul rationale). These bodies are
	NEVER any player's Character, so reassigning control never destroys them.
	Control over a body is granted via network ownership (see ControlManager).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local SpawnLayout = require(ReplicatedStorage.Shared.SpawnLayout)

local BodyManager = {}
BodyManager.bodyByOwner = {} -- [player] = body wearing that player's avatar
BodyManager.arenaSlotByOwner = {} -- [player] = arena spawn CFrame (round-start reposition)
BodyManager.lobbySlotByOwner = {} -- [player] = balcony slot CFrame (join + between-rounds)
BodyManager.folder = nil
BodyManager._index = 0

-- Balcony grid row count, derived once from Config (read-only at runtime).
local LOBBY_ROWS = math.ceil(Config.LOBBY_CAPACITY / Config.LOBBY_PER_ROW)

local function ensureFolder()
	if not BodyManager.folder or not BodyManager.folder.Parent then
		local f = workspace:FindFirstChild("Bodies") or Instance.new("Folder")
		f.Name = "Bodies"
		f.Parent = workspace
		BodyManager.folder = f
	end
	return BodyManager.folder
end

local function buildAvatarBody(player)
	local body
	local ok = pcall(function()
		local desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
		for field, value in pairs(Config.NORMALIZED_SCALES) do
			desc[field] = value
		end
		body = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not body then
		-- Fallback for test players with no valid web avatar.
		body = Players:CreateHumanoidModelFromDescription(
			Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end
	return body
end

-- Arena spawn CFrame for a 1-based body index (today's single-row layout).
local function arenaCFrame(index)
	local o = Config.SPAWN_ORIGIN
	local x, y, z = SpawnLayout.arenaSlot(index, o.X, o.Y, o.Z, Config.SPAWN_SPACING)
	return CFrame.new(x, y, z)
end

-- Balcony slot CFrame for a 1-based body index. Grid offset (pure SpawnLayout)
-- + the balcony origin + a small drop, oriented (yaw only) to face the arena so
-- the avatar -- and its third-person camera -- point at the pit below.
local function lobbyCFrame(index)
	local dx, dz = SpawnLayout.lobbySlot(index, Config.LOBBY_PER_ROW, LOBBY_ROWS, Config.LOBBY_SPACING)
	local pos = Config.LOBBY_ORIGIN + Vector3.new(dx, Config.LOBBY_SPAWN_DROP, dz)
	-- Look at the arena center, kept level with `pos` so the body stands upright
	-- (yaw-only facing; the player tilts the camera to look down).
	local target = Vector3.new(Config.LOBBY_FACE_TARGET.X, pos.Y, Config.LOBBY_FACE_TARGET.Z)
	return CFrame.lookAt(pos, target)
end

function BodyManager.createBody(player)
	local body = buildAvatarBody(player)
	body.Name = "Body_" .. player.UserId

	local hum = body:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = Config.WALK_SPEED
		hum.UseJumpPower = false
		hum.JumpHeight = Config.JUMP_HEIGHT
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	BodyManager._index += 1
	local index = BodyManager._index
	-- A joining player starts in the waiting state, so spawn on the balcony.
	-- Both slots are stored so resetBody (arena) and returnToLobby (balcony) can
	-- reposition the body for the rest of its life without recomputing.
	BodyManager.arenaSlotByOwner[player] = arenaCFrame(index)
	BodyManager.lobbySlotByOwner[player] = lobbyCFrame(index)
	body:PivotTo(BodyManager.lobbySlotByOwner[player])
	body:SetAttribute("OwnerUserId", player.UserId)
	body.Parent = ensureFolder()

	BodyManager.bodyByOwner[player] = body
	return body
end

function BodyManager.getOwnBody(player)
	return BodyManager.bodyByOwner[player]
end

-- Returns an array of all current bodies (handy for the client animation driver
-- or any per-body server pass).
function BodyManager.getAllBodies()
	local list = {}
	for _, body in pairs(BodyManager.bodyByOwner) do
		table.insert(list, body)
	end
	return list
end

function BodyManager.removeBody(player)
	local body = BodyManager.bodyByOwner[player]
	if body then
		body:Destroy()
	end
	BodyManager.bodyByOwner[player] = nil
	BodyManager.arenaSlotByOwner[player] = nil
	BodyManager.lobbySlotByOwner[player] = nil
end

-- Round start: reposition a player's OWN body to its spawn slot and re-enable
-- physics. The body was never killed (elimination is logical), so no revive is
-- needed -- just unanchor, zero velocity, and pivot back to the spawn CFrame.
function BodyManager.resetBody(player)
	local body = BodyManager.bodyByOwner[player]
	local cf = BodyManager.arenaSlotByOwner[player]
	if not body or not cf then
		return
	end
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then
		return -- can't safely reset (and reposition) without a root
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	body:PivotTo(cf)
end

-- Reposition `body` onto `player`'s balcony slot, unanchored + zeroed. Shared by
-- returnToLobby (the player's OWN body, at round end) and sendToLobby (the body a
-- player was controlling when they died -- not necessarily their own avatar).
-- Unanchors so a later ControlManager.resetControl can SetNetworkOwner (errors on
-- an anchored part).
local function placeOnLobbySlot(player, body)
	local cf = BodyManager.lobbySlotByOwner[player]
	if not body or not cf then
		return
	end
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then
		return -- can't safely reposition without a root
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	body:PivotTo(cf)
end

-- Between rounds (and the Lobby phase): reposition a player's OWN body to its
-- balcony slot. The mirror of resetBody (which sends it to the arena slot).
function BodyManager.returnToLobby(player)
	placeOnLobbySlot(player, BodyManager.bodyByOwner[player])
end

-- Elimination: send the body the player was controlling (now out of the round) to
-- their balcony slot, still under their control, so they watch the rest of the
-- round from the lobby instead of leaving a corpse in the arena. Teleporting it
-- up also catches the fall (no need to anchor against FallenPartsDestroyHeight).
function BodyManager.sendToLobby(player, body)
	placeOnLobbySlot(player, body)
end

return BodyManager
