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
	if a < 0 then a = a + TAU end
	return a
end

-- Minimal wrap-around angular distance in [0, π].
function SweeperModel.angularDistance(a, b)
	local d = norm(a - b)
	if d > math.pi then d = TAU - d end
	return d
end

-- Current angle of one arm of a beam. beam = { baseAngle, direction (+1/-1), armCount }.
-- speed is the (already ramped) angular speed; armIndex is 0-based.
function SweeperModel.beamAngle(beam, armIndex, speed, elapsed)
	local arm = armIndex * (TAU / beam.armCount)
	return norm(beam.baseAngle + beam.direction * speed * elapsed + arm)
end

-- Monotonic angular speed-up over the round, clamped. opts = { rampPerSecond, maxSpeed }.
function SweeperModel.rampedSpeed(baseSpeed, elapsed, opts)
	local s = baseSpeed + (opts.rampPerSecond or 0) * math.max(0, elapsed)
	if opts.maxSpeed and s > opts.maxSpeed then
		s = opts.maxSpeed
	end
	return s
end

-- Is a body at polar (radius, angle) under a beam arm currently at beamAngle?
-- opts = { innerRadius, outerRadius, angularHalfWidth }. The hub (< innerRadius) is safe.
function SweeperModel.overlaps(radius, angle, beamAngle, opts)
	if radius < opts.innerRadius or radius > opts.outerRadius then
		return false
	end
	return SweeperModel.angularDistance(angle, beamAngle) < opts.angularHalfWidth
end

-- Does a body's vertical state clear this beam class?
-- "low" is cleared by jumping (airborne); "high" is cleared by staying grounded.
function SweeperModel.clears(class, airborne)
	if class == "low" then
		return airborne == true
	end
	return airborne == false
end

return SweeperModel
