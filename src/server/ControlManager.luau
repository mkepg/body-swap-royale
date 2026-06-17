--[[
	ControlManager (server)
	Location: ServerScriptService/Server/ControlManager  (ModuleScript)

	Grants a player control of a body by handing them its network ownership.
	The client then drives that body locally (predicted -> smooth) and points its
	camera at it. Because control is ownership (not Character), it can be rotated
	freely with no destruction -- which is the entire reason this model exists.

	This is the piece SwapController calls to actually perform the swap.

	Depends on:
	  ReplicatedStorage.Shared.Remotes -> SetControlledBody  (RemoteEvent)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SetControlledBody = Remotes.get("SetControlledBody")

local ControlManager = {}
ControlManager.bodyOf = {}       -- [player] = body they currently control
ControlManager.controllerOf = {} -- [body]   = player

-- Assign one player to one body. Used for both initial spawn and swaps.
-- For a full-bijection swap every entry is overwritten, so no stale links.
function ControlManager.assignOne(player, body, isSwap)
	local root = body:FindFirstChild("HumanoidRootPart")
	if root then
		pcall(function() root:SetNetworkOwner(player) end)
	end
	ControlManager.bodyOf[player] = body
	ControlManager.controllerOf[body] = player
	SetControlledBody:FireClient(player, body, isSwap == true)
end

function ControlManager.getControlledBody(player)
	return ControlManager.bodyOf[player]
end

function ControlManager.release(player)
	local body = ControlManager.bodyOf[player]
	if body and ControlManager.controllerOf[body] == player then
		ControlManager.controllerOf[body] = nil
		local root = body:FindFirstChild("HumanoidRootPart")
		if root then
			pcall(function() root:SetNetworkOwner(nil) end) -- back to server
		end
	end
	ControlManager.bodyOf[player] = nil
end

return ControlManager
