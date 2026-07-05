local MovementValidator = require("../src/shared/MovementValidator")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local DT = 0.1
-- horizontal budget = 16 * 0.1 * 2.0 = 3.2 ; rise budget = 53 * 0.1 * 1.5 = 7.95
local OPTS = {
	walkSpeed = 16,
	horizontalSlack = 2.0,
	jumpSpeed = 53,
	verticalSlack = 1.5,
	minFallEpsilon = 0.5,
	violationTicks = 5,
}

local function grounded(h, v)
	return { horizDelta = h, vertDelta = v or 0, dt = DT, hasFloor = true }
end

-- legal walk: never corrects, even sustained.
do
	local m = MovementValidator.new()
	for _ = 1, 12 do
		expect(MovementValidator.step(m, "A", grounded(1.5), OPTS).correct == false,
			"legal walk must never correct")
	end
	print("mv: legal walk -> never corrects OK")
end

-- legal jump rise (within budget, over floor): never corrects.
do
	local m = MovementValidator.new()
	for _ = 1, 12 do
		expect(MovementValidator.step(m, "A", grounded(1.5, 5), OPTS).correct == false,
			"legal jump rise must never correct")
	end
	print("mv: legal jump rise OK")
end

-- horizontal teleport: corrects after exactly violationTicks, not before.
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for i = 1, OPTS.violationTicks - 1 do
		expect(MovementValidator.step(m, "A", tp, OPTS).correct == false,
			"tick " .. i .. " must not correct yet")
	end
	local d = MovementValidator.step(m, "A", tp, OPTS)
	expect(d.correct == true, "must correct on the violationTicks-th tick")
	expect(d.reason == "horizontal", "reason must be horizontal")
	print("mv: horizontal teleport debounce OK")
end

-- counter resets after a correction (next illegal run must re-accumulate).
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for _ = 1, OPTS.violationTicks do MovementValidator.step(m, "A", tp, OPTS) end -- fires once, resets
	expect(MovementValidator.step(m, "A", tp, OPTS).correct == false,
		"counter must reset after a correction")
	print("mv: counter resets after correction OK")
end

-- upward launch (rise beyond jump budget): corrects.
do
	local m = MovementValidator.new()
	local up = { horizDelta = 0, vertDelta = 50, dt = DT, hasFloor = true }
	local fired = false
	for _ = 1, OPTS.violationTicks do
		if MovementValidator.step(m, "A", up, OPTS).correct then fired = true end
	end
	expect(fired, "sustained rise beyond budget must correct")
	print("mv: upward launch OK")
end

-- hover over void: no floor + not descending -> corrects after debounce.
do
	local m = MovementValidator.new()
	local hover = { horizDelta = 0, vertDelta = 0, dt = DT, hasFloor = false }
	local d
	for _ = 1, OPTS.violationTicks do d = MovementValidator.step(m, "A", hover, OPTS) end
	expect(d.correct == true and d.reason == "hover", "hovering over void must correct")
	print("mv: hover over void OK")
end

-- legit fall over a hole: no floor but strongly descending -> never corrects.
do
	local m = MovementValidator.new()
	local falling = { horizDelta = 0, vertDelta = -5, dt = DT, hasFloor = false }
	for _ = 1, 12 do
		expect(MovementValidator.step(m, "A", falling, OPTS).correct == false,
			"legit fall must never correct")
	end
	print("mv: legit fall over hole OK")
end

-- legal gap-jump: a bounded ascent over the void (fewer than violationTicks) then descent -> forgiven.
do
	local m = MovementValidator.new()
	local ascend = { horizDelta = 1, vertDelta = 3, dt = DT, hasFloor = false } -- over a hole, rising (hover-predicate true)
	local fallover = { horizDelta = 1, vertDelta = -4, dt = DT, hasFloor = false } -- now descending -> resets run
	for _ = 1, OPTS.violationTicks - 1 do -- one short of firing
		expect(MovementValidator.step(m, "A", ascend, OPTS).correct == false, "ascent under threshold")
	end
	expect(MovementValidator.step(m, "A", fallover, OPTS).correct == false, "descent resets the run")
	-- run reset: another (violationTicks-1) ascents still must not fire
	for _ = 1, OPTS.violationTicks - 1 do
		expect(MovementValidator.step(m, "A", ascend, OPTS).correct == false, "post-reset ascent under threshold")
	end
	print("mv: legal gap-jump forgiven OK")
end

-- one-tick lag spike then normal: forgiven (clean tick resets the run).
do
	local m = MovementValidator.new()
	local spike = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for _ = 1, 8 do
		MovementValidator.step(m, "A", spike, OPTS)    -- one spike
		expect(MovementValidator.step(m, "A", grounded(1.5), OPTS).correct == false,
			"clean tick after a spike resets the run")
	end
	print("mv: single-tick lag spike forgiven OK")
end

-- reseed clears the counter mid-run (server reposition path).
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for _ = 1, OPTS.violationTicks - 1 do MovementValidator.step(m, "A", tp, OPTS) end
	MovementValidator.reseed(m, "A")
	expect(MovementValidator.step(m, "A", tp, OPTS).correct == false, "reseed must clear the run")
	print("mv: reseed clears counter OK")
end

-- forget drops all state (independent bodies do not interfere).
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	MovementValidator.step(m, "A", tp, OPTS)
	MovementValidator.forget(m, "A")
	expect(m.byBody["A"] == nil, "forget must drop the body entry")
	-- an unrelated body is unaffected
	expect(MovementValidator.step(m, "B", grounded(1.5), OPTS).correct == false, "B independent of A")
	print("mv: forget OK")
end

print("ALL MOVEMENTVALIDATOR TESTS PASSED")
