--[[
	ArenaHazard -- the contract between RoundManager and a specific arena's hazard.
	RoundManager is arena-agnostic: it calls this interface, never a concrete arena.

	An ArenaHazard implements:
	  build()                 -- once at startup: construct geometry (replaces baseplate)
	  start(now)              -- beginRound: reset to the round-start state (now = os.clock())
	  step(now, samples)      -- per monitor tick: returns an `effects` table (see below)
	  stop()                  -- endRound: freeze to a safe resting state
	  descriptor()            -- returns the ArenaDescriptor for Layer-2 dressing
	  voidY()                 -- this arena's kill-plane Y

	`samples` = array of { position: Vector3, graceBlocked: boolean, player: Player,
	                       body: Model, velocityY: number } (one per alive body).
	`effects` = { sweeps = { { player, body, target: CFrame }, ... } }
	            -- RoundManager applies each sweep with reposition-then-re-own.
--]]

local ArenaHazard = {}

-- Cheap shape guard so a hazard implementation fails loudly if it's missing a method.
function ArenaHazard.validate(h)
	for _, name in ipairs({ "build", "start", "step", "stop", "descriptor", "voidY" }) do
		assert(type(h[name]) == "function", "ArenaHazard missing method: " .. name)
	end
	return h
end

return ArenaHazard
