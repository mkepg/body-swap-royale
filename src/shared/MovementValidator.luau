--[[
	MovementValidator -- PURE per-body movement legality.
	Location (Roblox): ReplicatedStorage/Shared/MovementValidator  (ModuleScript)

	Roblox-free + clock-free, like GraceModel / HexErosionModel. The glue reduces a
	body to scalars (horizontal/vertical displacement since the last tick, dt, and
	whether solid floor sits between it and the kill-plane) and asks: is this tick a
	physically-impossible move, and has it been impossible long enough to correct?

	Keys are opaque (body Instances in production, strings in tests).

	A tick VIOLATES if any of:
	  horizDelta > walkSpeed * dt * horizontalSlack     -- speed / horizontal teleport
	  vertDelta  > jumpSpeed * dt * verticalSlack       -- upward teleport / launch / fly-up
	  not hasFloor and vertDelta > -minFallEpsilon        -- over the void and not falling (hover)

	Debounce: correct=true only once `violationTicks` CONSECUTIVE violating ticks
	accumulate; any clean tick resets the run (so a one-tick lag spike is forgiven,
	and a legal gap-jump's bounded ascent over the void never reaches the threshold).
	The counter resets when a correction fires.
--]]

local MovementValidator = {}

function MovementValidator.new()
	return {
		byBody = {}, -- [bodyId] = { violations = int }
	}
end

local function entry(model, bodyId)
	local e = model.byBody[bodyId]
	if not e then
		e = { violations = 0 }
		model.byBody[bodyId] = e
	end
	return e
end

-- Is this single tick physically impossible? Returns (bool, reason?).
local function isViolation(sample, opts)
	if sample.horizDelta > opts.walkSpeed * sample.dt * opts.horizontalSlack then
		return true, "horizontal"
	end
	if sample.vertDelta > opts.jumpSpeed * sample.dt * opts.verticalSlack then
		return true, "rise"
	end
	if not sample.hasFloor and sample.vertDelta > -opts.minFallEpsilon then
		return true, "hover"
	end
	return false, nil
end

-- Judge one tick. Returns { correct, reason } -- correct=true only after the
-- debounce threshold is crossed, at which point the counter is reset.
function MovementValidator.step(model, bodyId, sample, opts)
	local e = entry(model, bodyId)
	local violated, reason = isViolation(sample, opts)
	if not violated then
		e.violations = 0
		return { correct = false, reason = nil }
	end
	e.violations += 1
	if e.violations >= opts.violationTicks then
		e.violations = 0
		return { correct = true, reason = reason }
	end
	return { correct = false, reason = reason }
end

-- Clear the debounce counter (server reposition / first sight of a body).
function MovementValidator.reseed(model, bodyId)
	local e = model.byBody[bodyId]
	if e then
		e.violations = 0
	end
end

-- Drop all state for a body (destroyed / player left).
function MovementValidator.forget(model, bodyId)
	model.byBody[bodyId] = nil
end

return MovementValidator
