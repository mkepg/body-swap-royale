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
local SoulPalette = require(ReplicatedStorage.Shared.SoulPalette)
local Config = require(ReplicatedStorage.Shared.Config)
local BodyManager = require(script.Parent.BodyManager)
local SetControlledBody = Remotes.get("SetControlledBody")
local SoulMap = Remotes.get("SoulMap")

local ControlManager = {}
local model = ControlModel.new()

-- Per-player Soul colors, auto-assigned by join order (stable for the session).
local soulColor = {} -- [player] = Color3
local soulIndex = 0

-- Broadcast every controlled body's current Soul color so each client can place
-- a halo on it (and follow it across swaps). Built from the live control map.
function ControlManager.broadcastSoulMap()
	local list = {}
	for body, player in pairs(model.controllerOf) do
		local color = soulColor[player]
		if color then
			list[#list + 1] = { body = body, color = color }
		end
	end
	SoulMap:FireAllClients(list)
end

-- Hand `player` network ownership of `body` and tell their client to retarget.
-- On a swap handoff (isSwap), zero the body's velocity server-authoritatively:
-- the body is client-owned, so a naive velocity write would be overwritten by the
-- owning client's physics. Taking ownership (nil) first, zeroing, then handing to
-- the new controller makes the inheritor start at rest -- no inherited launch/shove
-- momentum (which would otherwise cancel grace). Same own->mutate->re-own ordering
-- as BodyManager's reposition-then-re-own primitive.
local function applyOwnership(player, body, isSwap)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root then
		local ok, err = pcall(function()
			if isSwap then
				root:SetNetworkOwner(nil) -- server takes the body
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			root:SetNetworkOwner(player)
		end)
		if not ok then
			warn("[ControlManager] SetNetworkOwner failed for " .. tostring(player) .. ": " .. tostring(err))
		end
	end
	-- Authoritative "who controls this body RIGHT NOW" -- attributes replicate
	-- reliably and in-order per instance, unlike the fire-and-forget SetControlledBody
	-- remote below. The client self-heals its camera/control from this if that remote
	-- is ever missed (e.g. fired before the client's LocalScripts finish loading on a
	-- cold first join). Distinct from BodyManager's OwnerUserId (stable avatar identity
	-- for this body); ControllerUserId changes on every swap/regrant/reset.
	if body then
		body:SetAttribute("ControllerUserId", player.UserId)
	end
	SetControlledBody:FireClient(player, body, isSwap == true)
end

-- Player spawned: they own `body` and start by controlling it.
function ControlManager.addPlayer(player, body)
	soulIndex += 1
	soulColor[player] = SoulPalette.colorForIndex(soulIndex, Config.SOUL_PALETTE)
	ControlModel.addPlayer(model, player, body)
	applyOwnership(player, body, false)
	ControlManager.broadcastSoulMap()
end

-- Compute the next swap without applying it (no ownership change, no notify).
function ControlManager.planSwap(orderedPlayers)
	return ControlModel.planSwap(model, orderedPlayers, function(n)
		return math.random(1, n)
	end)
end

-- Apply a plan: rotate network ownership + notify each client (isSwap = true),
-- then rebroadcast the Soul map (halos follow control). Returns how many moved.
function ControlManager.commitSwap(plan)
	local result = ControlModel.applySwap(model, plan)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, true)
	end
	ControlManager.broadcastSoulMap()
	return #result
end

-- True iff `plan` still matches the current control map (re-plan decision).
function ControlManager.planStillValid(plan)
	return ControlModel.planStillValid(model, plan)
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
	soulColor[player] = nil
	ControlManager.broadcastSoulMap()
	return decision -- absorb decision {destroyOwn, reassign} -- consumed by RoundManager's rescue
end

-- Re-assert a player's network ownership of the body they CURRENTLY control, with a
-- clean (non-swap) retarget. Used after a server-side reposition so the teleport
-- replicates onto the now client-owned body (same reposition-then-re-own ordering as
-- beginRound's resetBody -> resetControl). No-op if the player controls no body.
function ControlManager.regrantControl(player)
	local body = ControlModel.controlledBody(model, player)
	if body then
		applyOwnership(player, body, false)
	end
end

-- Reset every player to their own avatar body (round start). Applies the pure
-- ControlModel.resetControl, then re-grants network ownership and notifies each
-- client (isSwap = false: a clean spawn-style retarget, no FOV punch).
function ControlManager.resetControl()
	local result = ControlModel.resetControl(model)
	for _, pair in ipairs(result) do
		if pair.body then
			pair.body:SetAttribute("GraceProtected", false)
		end
		applyOwnership(pair.player, pair.body, false)
	end
	ControlManager.broadcastSoulMap()
	return result
end

function ControlManager.getControlledBody(player)
	return ControlModel.controlledBody(model, player)
end

-- Inverse lookup: the player currently controlling `body` (nil if none). Used by
-- the broken-body heal to find who is riding a torn-down body.
function ControlManager.getController(body)
	return model.controllerOf[body]
end

return ControlManager
