--[[
	SweeperModel -- PURE beam geometry for the Soul Sweeper arena (arena #2).
	Location (Roblox): ReplicatedStorage/Shared/SweeperModel (ModuleScript)

	No clock reads / RNG / Roblox globals (lune-tested, like HexErosionModel).
	The glue (SweeperHazard server-side, SweeperController client-side) feeds it
	elapsed seconds since round start + a body's polar position, and gets back
	beam angles and a yes/no strike decision. Angles in radians.
--]]

local SweeperModel = {}

local TAU = math.pi * 2

local function norm(a)
	a = a % TAU
	-- Belt-and-suspenders: Luau's `%` already yields [0, TAU) for a positive modulus,
	-- so this branch is effectively unreachable; kept as a guard against sign surprises.
	if a < 0 then a = a + TAU end
	return a
end

-- Minimal wrap-around angular distance in [0, π].
function SweeperModel.angularDistance(a, b)
	local d = norm(a - b)
	if d > math.pi then d = TAU - d end
	return d
end

-- (v2.1: the elapsed-based beamAngle was removed with the CFrame-stepped beams --
-- the physics engine owns beam poses now, and every consumer reads the MEASURED
-- angle off the bar's replicated root. rampedSpeed below still drives the motors.)

-- Monotonic angular speed-up over the round, clamped. opts = { rampPerSecond, maxSpeed }.
function SweeperModel.rampedSpeed(baseSpeed, elapsed, opts)
	local s = baseSpeed + (opts.rampPerSecond or 0) * math.max(0, elapsed)
	if opts.maxSpeed and s > opts.maxSpeed then
		s = opts.maxSpeed
	end
	return s
end

-- (v2.3: `overlaps` -- the angular-half-width test -- was removed with the retired
-- angular kill-zone model; isStruckSwept below derives a constant-width pad instead.)

-- Does a body's vertical state clear this beam class?
-- "low" is cleared by jumping (airborne); "high" is cleared by staying grounded.
-- Any other class value is a config error and fails loudly (never silently "high").
function SweeperModel.clears(class, airborne)
	assert(class == "low" or class == "high", "SweeperModel.clears: unknown beam class " .. tostring(class))
	if class == "low" then
		return airborne == true
	end
	return airborne == false
end

-- v2.4: the kill band half-width is DERIVED from the bar's visible thickness --
-- half the root-spine thickness (the visible bar edge) + the struck body's own
-- half-extent around its sampled root point (Config.SWEEP_BODY_CONTACT_PAD). One
-- constant sizes both the mesh and the hitbox, so they can never drift apart.
function SweeperModel.killHalfWidth(thickness, contactPad)
	return thickness / 2 + contactPad
end

-- v2.4 render-lag compensation (spec §2-2): pick the sweep window ending `lagTicks`
-- samples in the past from a measured-angle history (oldest first, newest last).
-- Returns the (angle, prevAngle) pair to feed isStruckSwept -- history[0] is nil,
-- so a window at the very start of history degrades to the model's instantaneous
-- first-tick fallback -- or nil when the history is still too short (round start /
-- post-re-park): the caller skips the strike test that tick rather than testing an
-- unlagged window.
function SweeperModel.delayedWindow(history, lagTicks)
	local i = #history - lagTicks
	if i < 1 then
		return nil, nil
	end
	return history[i], history[i - 1]
end

-- Swept-interval strike test on MEASURED angles: did any beam's arc cross the body
-- since the last tick? beams[i] = { angle, prevAngle?, direction (+1/-1), class,
-- innerRadius, outerRadius, killHalfWidth }. direction follows the system-wide
-- convention (+1 => measured angle increases; see SweeperHazard.motorTarget).
-- killHalfWidth is a constant STUD half-width (the bar's physical kill band), not an
-- angle -- converted per body to `halfAngle = asin(min(1, killHalfWidth / body.radius))`
-- so the same visible bar width kills identically at the hub and at the rim (an angular
-- pad would grow with radius and kill players long before the bar visually reaches them).
-- prevAngle == nil (first tick) or a sweep span > 1 rad (a re-park/teleport jump,
-- not real rotation) falls back to the instantaneous halfAngle check, so a parked
-- bar snapping home can never kill across the jumped arc.
function SweeperModel.isStruckSwept(body, beams)
	for _, beam in ipairs(beams) do
		if not SweeperModel.clears(beam.class, body.airborne)
			and body.radius >= beam.innerRadius and body.radius <= beam.outerRadius then
			local halfAngle = math.asin(math.min(1, beam.killHalfWidth / body.radius))
			local hit
			local span = beam.prevAngle
				and (((beam.angle - beam.prevAngle) * beam.direction) % TAU) or nil
			if span == nil or span > 1 then
				hit = SweeperModel.angularDistance(body.angle, beam.angle) < halfAngle
			else
				local o = ((body.angle - beam.prevAngle) * beam.direction) % TAU
				hit = o <= span + halfAngle or o >= TAU - halfAngle
			end
			if hit then
				return true
			end
		end
	end
	return false
end

return SweeperModel
