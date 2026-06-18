local GraceModel = require("../src/shared/GraceModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local GRACE = 1.5
local FLOOR = 0.5

-- no entry: a player who never swapped can always die from a hazard.
do
	local m = GraceModel.new()
	expect(GraceModel.canDieFromHazard(m, "A", 100) == true, "no entry must allow death")
	print("grace: no entry -> can die OK")
end

-- within the floor: protected, and protected EVEN IF moved (floor is unconditional).
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 0) == false, "t=0 within floor must protect")
	expect(GraceModel.canDieFromHazard(m, "A", 0.4) == false, "t<floor must protect")
	GraceModel.markMoved(m, "A")
	expect(GraceModel.canDieFromHazard(m, "A", 0.4) == false, "floor protects even after moving")
	print("grace: hard floor (unconditional) OK")
end

-- after floor, before graceUntil, not moved: still protected.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 1.0) == false, "in grace, not moved -> protected")
	print("grace: in-window, not moved -> protected OK")
end

-- after floor, before graceUntil, moved: early exit -> can die.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	GraceModel.markMoved(m, "A")
	expect(GraceModel.canDieFromHazard(m, "A", 1.0) == true, "moved past floor -> can die (early exit)")
	print("grace: early exit on movement OK")
end

-- at/after graceUntil, not moved: window expired -> can die.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 1.5) == true, "at graceUntil -> can die")
	expect(GraceModel.canDieFromHazard(m, "A", 2.0) == true, "after graceUntil -> can die")
	print("grace: window expiry -> can die OK")
end

-- markMoved on an unknown player is a harmless no-op.
do
	local m = GraceModel.new()
	GraceModel.markMoved(m, "ghost") -- must not error
	expect(GraceModel.canDieFromHazard(m, "ghost", 0) == true, "unknown player has no grace")
	print("grace: markMoved no-op on unknown OK")
end

-- clear: removes the entry, so canDieFromHazard returns true again.
do
	local m = GraceModel.new()
	GraceModel.onSwap(m, "A", 0, GRACE, FLOOR)
	expect(GraceModel.canDieFromHazard(m, "A", 0) == false, "precondition: protected")
	GraceModel.clear(m, "A")
	expect(GraceModel.canDieFromHazard(m, "A", 0) == true, "cleared -> can die")
	print("grace: clear OK")
end

print("ALL GRACEMODEL TESTS PASSED")
