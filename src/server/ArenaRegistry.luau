--[[
	ArenaRegistry -- resolves Config.ACTIVE_ARENA to the concrete ArenaHazard singleton.
	RoundManager calls forActive() once at startup and talks to the returned interface.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaHazard = require(script.Parent.ArenaHazard)
local HexHazard = require(script.Parent.HexHazard)
local SweeperHazard = require(script.Parent.SweeperHazard)

local ArenaRegistry = {}

function ArenaRegistry.forActive()
	local hazard
	if Config.ACTIVE_ARENA == "sweeper" then
		hazard = SweeperHazard
	else
		hazard = HexHazard
	end
	return ArenaHazard.validate(hazard)
end

return ArenaRegistry
