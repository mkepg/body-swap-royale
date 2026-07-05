--[[
	HintService (server) -- server-authoritative first-session hint firing. The client
	NEVER reports back (no client->server remote): the server owns the decision AND the
	seen-state. fireTrigger(player, trigger):
	  1. read the player's persisted seenHints via EconomyService (nil profile -> no-op);
	  2. HintModel.resolve against the registry;
	  3. on a hit: fire ShowHint to that client + append the id to seenHints (mutates the
	     cached profile; the existing autosave / leave-save path persists it).
	Location (Roblox): ServerScriptService/Server/HintService  (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HintModel = require(ReplicatedStorage.Shared.HintModel)
local HintRegistry = require(ReplicatedStorage.Shared.HintRegistry)
local EconomyService = require(script.Parent.EconomyService)

local ShowHint = Remotes.get("ShowHint")

local HintService = {}

function HintService.fireTrigger(player, trigger)
	local profile = EconomyService.getProfile(player)
	if not profile then
		return -- not loaded yet / already left: nothing to gate against
	end
	local hint = HintModel.resolve(HintRegistry, profile.seenHints, trigger)
	if not hint then
		return
	end
	ShowHint:FireClient(player, {
		id = hint.id,
		text = hint.text,
		duration = hint.duration,
		anchor = hint.anchor,
	})
	profile.seenHints = HintModel.withSeen(profile.seenHints, hint.id)
end

return HintService
