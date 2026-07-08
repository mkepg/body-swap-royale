local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)

local EMPTY = { sweeps = {} }
local SweeperHazard = {}

function SweeperHazard.build() end
function SweeperHazard.start(_now) end
function SweeperHazard.stop() end
function SweeperHazard.step(_now, _samples) return EMPTY end
function SweeperHazard.descriptor() return ArenaDescriptor.sweeper() end
function SweeperHazard.voidY() return Config.SWEEP_VOID_Y end

return SweeperHazard
