--[[
	HexHazard -- the Hex-A-Gone arena behind the ArenaHazard interface. A thin wrapper
	over the (unchanged) HazardSystem singleton so RoundManager can treat every arena
	uniformly. Hex never sweeps bodies (they fall through gone tiles by gravity), so
	step() returns empty effects.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)
local HazardSystem = require(script.Parent.HazardSystem)

local EMPTY = { sweeps = {} }

local HexHazard = {}

function HexHazard.build() HazardSystem.build() end
function HexHazard.start(now) HazardSystem.start(now) end
function HexHazard.stop() HazardSystem.stop() end

-- HazardSystem.step reads only sample.position + sample.graceBlocked; the extra
-- Sweeper fields on each sample are ignored. Hex enqueues no sweeps.
function HexHazard.step(now, samples)
	HazardSystem.step(now, samples)
	return EMPTY
end

function HexHazard.descriptor() return ArenaDescriptor.hex() end
function HexHazard.voidY() return Config.VOID_Y end

return HexHazard
