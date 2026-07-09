--[[
	ArenaHazard -- the contract between RoundManager and a specific arena's hazard.
	RoundManager is arena-agnostic: it calls this interface, never a concrete arena.

	An ArenaHazard implements:
	  id                       -- string: this arena's identifier (e.g. "hex", "sweeper")
	  build()                  -- once at startup: construct geometry (replaces baseplate)
	  start(now)               -- beginRound: reset to the round-start state (now = os.clock())
	  step(now, samples)       -- per monitor tick: returns an `effects` table (see below)
	  stop()                   -- endRound: freeze to a safe resting state
	  descriptor()             -- returns the ArenaDescriptor for Layer-2 dressing
	  voidY()                  -- this arena's kill-plane Y
	  spawnCFrame(index)       -- 1-based round spawn slot -> CFrame

	`samples` = array of { position: Vector3, graceBlocked: boolean, player: Player,
	                       body: Model, velocityY: number } (one per alive body).
	`effects` (v3, spec 2026-07-09 v2.2) = { eliminations = { player, ... } }
	            -- RoundManager routes each struck player through the SAME
	            -- grace-gated chokepoint as void death (RoundManager.eliminateFromHazard),
	            -- which double-checks the grace gate. Deterministic server math on
	            -- server-owned physics state -- no shove, no knockback, nothing to desync.
--]]

local ArenaHazard = {}

-- Cheap shape guard so a hazard implementation fails loudly if it's missing a method.
function ArenaHazard.validate(h)
	for _, name in ipairs({ "build", "start", "step", "stop", "descriptor", "voidY", "spawnCFrame" }) do
		assert(type(h[name]) == "function", "ArenaHazard missing method: " .. name)
	end
	assert(type(h.id) == "string" and h.id ~= "", "ArenaHazard.id must be a non-empty string")
	return h
end

return ArenaHazard
