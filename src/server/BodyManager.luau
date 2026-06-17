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

local BodyManager = {}
BodyManager.bodyByOwner = {} -- [player] = body wearing that player's avatar
BodyManager.folder = nil
BodyManager._index = 0

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
	local pos = Config.SPAWN_ORIGIN + Vector3.new((BodyManager._index - 1) * Config.SPAWN_SPACING, 0, 0)
	body:PivotTo(CFrame.new(pos))
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
end

return BodyManager
