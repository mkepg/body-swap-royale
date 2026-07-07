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

return SweeperModel
