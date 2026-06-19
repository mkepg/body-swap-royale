--[[
	Remotes
	Location: ReplicatedStorage/Shared/Remotes  (ModuleScript)

	The old project shipped a hand-placed RemoteEvent at
	ReplicatedStorage/BSR/Remotes/SetControlledBody. This project is built by
	Rojo from source with no instance model files, so the remotes are created at
	runtime instead: the server ensures they exist, the client waits for them.

	Returns a small accessor; require it from both sides and call Remotes.get(name).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"
local REMOTE_EVENTS =
	{ "SetControlledBody", "RoundStateChanged", "EliminationEvent", "SpectateBody", "SwapPreview", "SoulMap" }

local function getFolder()
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		for _, name in ipairs(REMOTE_EVENTS) do
			if not folder:FindFirstChild(name) then
				local ev = Instance.new("RemoteEvent")
				ev.Name = name
				ev.Parent = folder
			end
		end
		return folder
	else
		return ReplicatedStorage:WaitForChild(FOLDER_NAME)
	end
end

local Remotes = {}
local folder = getFolder()

-- Returns the RemoteEvent/RemoteFunction by name (waits on the client).
function Remotes.get(name)
	return folder:WaitForChild(name)
end

return Remotes
