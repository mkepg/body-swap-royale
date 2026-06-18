--[[
	GraceModel -- PURE post-swap grace state.
	Location (Roblox): ReplicatedStorage/Shared/GraceModel  (ModuleScript)

	Time-agnostic, like RoundState (takes thresholds) and ControlModel (takes
	randint): it never reads a clock. The glue passes `now` and the grace
	durations in. Holds per-player { graceUntil, graceMinFloor, hasMoved } and
	answers the single question a hazard asks before eliminating a player:
	canDieFromHazard. Keys are opaque (Player instances in production, strings in
	tests).

	Decision (TDD §2 Grace Window Logic):
	  no entry                          -> can die (no grace; e.g. round-start spawn)
	  now < graceMinFloor               -> protected (hard floor, checked first)
	  now < graceUntil and not hasMoved -> protected (still orienting)
	  otherwise                         -> can die
--]]

local GraceModel = {}

function GraceModel.new()
	return {
		byPlayer = {}, -- [player] = { graceUntil, graceMinFloor, hasMoved }
	}
end

-- Stamp a fresh grace window for `player` at time `now`. Called on each swap.
function GraceModel.onSwap(model, player, now, graceSeconds, floorSeconds)
	model.byPlayer[player] = {
		graceUntil = now + graceSeconds,
		graceMinFloor = now + floorSeconds,
		hasMoved = false,
	}
end

-- The player has oriented (started moving). No-op if no grace entry exists.
function GraceModel.markMoved(model, player)
	local g = model.byPlayer[player]
	if g then
		g.hasMoved = true
	end
end

-- May this player's body be eliminated by a hazard right now?
function GraceModel.canDieFromHazard(model, player, now)
	local g = model.byPlayer[player]
	if not g then
		return true
	end
	if now < g.graceMinFloor then
		return false -- hard floor: always protected briefly, even if moved
	end
	if now < g.graceUntil and not g.hasMoved then
		return false -- still in grace, hasn't oriented yet
	end
	return true
end

-- Drop a player's grace entry (on elimination / disconnect).
function GraceModel.clear(model, player)
	model.byPlayer[player] = nil
end

return GraceModel
