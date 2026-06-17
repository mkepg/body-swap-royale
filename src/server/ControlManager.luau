--[[
	ControlManager (server) -- thin glue over the pure ControlModel.

	Holds one ControlModel instance (the controllers<->bodies state) and turns its
	decisions into Roblox side effects: network ownership, the SetControlledBody
	notification, and avatar-body destruction on disconnect.

	Depends on:
	  ReplicatedStorage.Shared.Remotes      -> SetControlledBody  (RemoteEvent)
	  ReplicatedStorage.Shared.ControlModel -> pure state machine
	  ServerScriptService.Server.BodyManager -> destroys the leaving player's body
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ControlModel = require(ReplicatedStorage.Shared.ControlModel)
local BodyManager = require(script.Parent.BodyManager)
local SetControlledBody = Remotes.get("SetControlledBody")

local ControlManager = {}
local model = ControlModel.new()

-- Hand `player` network ownership of `body` and tell their client to retarget.
local function applyOwnership(player, body, isSwap)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root then
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
	SetControlledBody:FireClient(player, body, isSwap == true)
end

-- Player spawned: they own `body` and start by controlling it.
function ControlManager.addPlayer(player, body)
	ControlModel.addPlayer(model, player, body)
	applyOwnership(player, body, false)
end

-- Rotate control across `orderedPlayers` (a swap). Returns how many were swapped.
function ControlManager.swap(orderedPlayers)
	local result = ControlModel.swap(model, orderedPlayers, function(n)
		return math.random(1, n)
	end)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, true)
	end
	return #result
end

-- Player left: apply the model's absorb decision, then destroy their avatar body.
function ControlManager.removePlayer(player)
	local decision = ControlModel.removePlayer(model, player)
	if decision.reassign then
		applyOwnership(decision.reassign.player, decision.reassign.body, false)
	end
	if decision.destroyOwn then
		BodyManager.removeBody(player) -- destroys bodyByOwner[player] = the leaving player's avatar body
	end
end

function ControlManager.getControlledBody(player)
	return ControlModel.controlledBody(model, player)
end

return ControlManager
