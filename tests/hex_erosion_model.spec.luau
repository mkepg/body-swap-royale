local HexErosionModel = require("../src/shared/HexErosionModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local DUR = { gone = 1.2 }

-- arm: stays nil unoccupied; sets `now` on first non-grace occupancy; suppressed
-- while graceBlocked; idempotent once armed.
do
	expect(HexErosionModel.arm(nil, false, false, 100) == nil, "unoccupied stays nil")
	expect(HexErosionModel.arm(nil, true, true, 100) == nil, "grace-blocked stays nil")
	expect(HexErosionModel.arm(nil, true, false, 100) == 100, "first non-grace occupancy arms at now")
	-- idempotent: an already-armed tile keeps its original steppedAt.
	expect(HexErosionModel.arm(100, true, false, 250) == 100, "re-arming keeps original steppedAt")
	expect(HexErosionModel.arm(100, false, false, 250) == 100, "armed tile stays armed when vacated")
	print("erosion: arm gating + idempotence OK")
end

-- phaseAt: solid when unarmed; warning before `gone`; gone at/after; monotonic.
do
	expect(HexErosionModel.phaseAt(nil, 999, DUR) == "solid", "unarmed -> solid")
	expect(HexErosionModel.phaseAt(100, 100, DUR) == "warning", "just armed -> warning")
	expect(HexErosionModel.phaseAt(100, 101.19, DUR) == "warning", "before delay -> warning")
	expect(HexErosionModel.phaseAt(100, 101.2, DUR) == "gone", "at delay -> gone")
	expect(HexErosionModel.phaseAt(100, 500, DUR) == "gone", "long after -> gone")
	-- monotonic: once gone, never returns to solid/warning for increasing now.
	local prevRank = 0
	local rank = { solid = 1, warning = 2, gone = 3 }
	for k = 0, 60 do
		local now = 100 + (k / 60) * 3
		local r = rank[HexErosionModel.phaseAt(100, now, DUR)]
		expect(r >= prevRank, "phase must not regress")
		prevRank = r
	end
	print("erosion: phaseAt thresholds + monotonicity OK")
end

print("ALL HexErosionModel TESTS PASSED")
