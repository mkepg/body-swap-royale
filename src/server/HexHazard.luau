--[[
	HexHazard -- the Hex-A-Gone arena behind the ArenaHazard interface. A thin wrapper
	over the (unchanged) HazardSystem singleton so RoundManager can treat every arena
	uniformly. Hex never sweeps bodies (they fall through gone tiles by gravity), so
	step() returns empty effects.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaDescriptor = require(ReplicatedStorage.Shared.ArenaDescriptor)
local HexGrid = require(ReplicatedStorage.Shared.HexGrid)
local HazardSystem = require(script.Parent.HazardSystem)

local EMPTY = { sweeps = {}, reseeds = {} }

local HexHazard = {}
HexHazard.id = "hex"

function HexHazard.build() HazardSystem.build() end
function HexHazard.start(now) HazardSystem.start(now) end
function HexHazard.stop() HazardSystem.stop() end

-- HazardSystem.step reads only sample.position + sample.graceBlocked; the extra
-- Sweeper fields on each sample are ignored. Hex enqueues no sweeps or reseeds.
function HexHazard.step(now, samples)
	HazardSystem.step(now, samples)
	return EMPTY
end

function HexHazard.descriptor() return ArenaDescriptor.hex() end
function HexHazard.voidY() return Config.VOID_Y end

-- Round spawn slot: the existing hex spawn spiral (same math BodyManager uses for
-- its creation-time default), exposed through the interface for per-round assignment.
local HEX_SLOTS = HexGrid.spawnSlots(Config.HEX_RADIUS)

function HexHazard.spawnCFrame(index)
	local o = Config.SPAWN_ORIGIN
	local slot = HEX_SLOTS[index] or HEX_SLOTS[#HEX_SLOTS]
	local dx, dz = HexGrid.toWorld(slot.q, slot.r, Config.HEX_SIZE)
	return CFrame.new(o.X + dx, o.Y, o.Z + dz)
end

return HexHazard
