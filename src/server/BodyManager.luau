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
local HexGrid = require(ReplicatedStorage.Shared.HexGrid)

local BodyManager = {}
BodyManager.bodyByOwner = {} -- [player] = body wearing that player's avatar
BodyManager.arenaSlotByOwner = {} -- [player] = arena spawn CFrame (round-start reposition)
BodyManager.lobbySlotByOwner = {} -- [player] = balcony slot CFrame (join + between-rounds)
BodyManager.folder = nil

-- Lobby grid row count, derived once from Config (read-only at runtime).
local LOBBY_ROWS = math.ceil(Config.LOBBY_CAPACITY / Config.LOBBY_PER_ROW)
-- Arena spawn slots: an outward spiral of hex centers (pure HexGrid), indexed by
-- the body's 1-based slot. 37 slots at HEX_RADIUS=3 cover the 16-body cap.
local ARENA_SLOTS = HexGrid.spawnSlots(Config.HEX_RADIUS)

-- Slot allocator: hand out a 1-based grid index in [1, LOBBY_CAPACITY] per body and
-- RECLAIM it when the body is removed, so join/leave churn never pushes a body past
-- the grid (the arena field / balcony pad). Both the arena and balcony slots use the
-- same index, so reclaiming it keeps both layouts bounded. Replaces the old
-- monotonic counter that grew forever and put the Nth-ever join off the grid.
local usedSlots = {}              -- [index] = true while occupied
BodyManager.slotByOwner = {}      -- [player] = index (released on removeBody)

local function allocateSlot()
	for i = 1, Config.LOBBY_CAPACITY do
		if not usedSlots[i] then
			usedSlots[i] = true
			return i
		end
	end
	-- Over capacity (more concurrent bodies than the cap): clamp to the last slot
	-- rather than compute an off-grid position. Not expected within the 16-player cap.
	return Config.LOBBY_CAPACITY
end

local function releaseSlot(player)
	local index = BodyManager.slotByOwner[player]
	if index then
		usedSlots[index] = nil
		BodyManager.slotByOwner[player] = nil
	end
end

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

-- Arena spawn CFrame for a 1-based body index: a hex center (pure HexGrid) offset
-- from the arena center, at the spawn height. Bodies drop onto the TOP hex floor.
-- Over-cap indices clamp to the last slot (matches the slot allocator's clamp).
local function arenaCFrame(index)
	local o = Config.SPAWN_ORIGIN
	local slot = ARENA_SLOTS[index] or ARENA_SLOTS[#ARENA_SLOTS]
	local dx, dz = HexGrid.toWorld(slot.q, slot.r, Config.HEX_SIZE)
	return CFrame.new(o.X + dx, o.Y, o.Z + dz)
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

	local index = allocateSlot()
	BodyManager.slotByOwner[player] = index
	-- A joining player starts in the waiting state, so spawn on the balcony.
	-- Both slots are stored so resetBody (arena) and returnToLobby (balcony) can
	-- reposition the body for the rest of its life without recomputing.
	local lobbyCF = lobbyCFrame(index)
	BodyManager.arenaSlotByOwner[player] = arenaCFrame(index)
	BodyManager.lobbySlotByOwner[player] = lobbyCF
	body:PivotTo(lobbyCF)
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
	releaseSlot(player) -- reclaim the grid index so a future join reuses it
end

-- Shared pivot primitive: unanchor root, zero both velocities, PivotTo cf.
-- Used by resetBody (arena slot) and placeOnLobbySlot (lobby slot) so the
-- physics-reset sequence only lives in one place.
local function pivotBodyTo(body, cf)
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then
		return false -- can't safely reposition without a root
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	body:PivotTo(cf)
	return true
end

-- Round start: reposition a player's OWN body to its spawn slot and re-enable
-- physics. The body was never killed (elimination is logical), so no revive is
-- needed -- just unanchor, zero velocity, and pivot back to the spawn CFrame.
function BodyManager.resetBody(player)
	local body = BodyManager.bodyByOwner[player]
	local cf = BodyManager.arenaSlotByOwner[player]
	if not body or not cf then return end
	pivotBodyTo(body, cf)
end

-- Reposition `body` onto `player`'s balcony slot, unanchored + zeroed. Shared by
-- returnToLobby (the player's OWN body, at round end) and sendToLobby (the body a
-- player was controlling when they died -- not necessarily their own avatar).
-- Unanchors so a later ControlManager.resetControl can SetNetworkOwner (errors on
-- an anchored part).
local function placeOnLobbySlot(player, body)
	local cf = BodyManager.lobbySlotByOwner[player]
	if not body or not cf then return end
	pivotBodyTo(body, cf)
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

-- Reposition `body` back onto its avatar-owner's ARENA spawn slot (unanchored +
-- zeroed) -- the arena mirror of sendToLobby. Used to rescue a still-alive survivor
-- whom a disconnect-absorb moved onto a body parked on the balcony (see the
-- disconnect-strand spec). Resolves the owner from the body's OwnerUserId attribute.
-- No-op if the owner or their arena slot can't be resolved.
function BodyManager.sendToArena(body)
	if not body then
		return
	end
	local userId = body:GetAttribute("OwnerUserId")
	local owner = userId and Players:GetPlayerByUserId(userId)
	local cf = owner and BodyManager.arenaSlotByOwner[owner]
	if not cf then
		return
	end
	pivotBodyTo(body, cf)
end

return BodyManager
