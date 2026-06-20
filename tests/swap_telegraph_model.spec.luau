local SwapTelegraphModel = require("../src/shared/SwapTelegraphModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local PREVIEW = 3

-- Outside the preview window: always-on timer text, no flash, no big countdown.
do
	local d = SwapTelegraphModel.display(27, PREVIEW)
	expect(d.timerText == "27", "timerText at 27s should be '27', got " .. tostring(d.timerText))
	expect(d.inPreview == false, "27s is not in preview")
	expect(d.bigCountdownInt == nil, "no big countdown outside preview")
	expect(d.flashAlpha == 0, "no flash outside preview")
	print("telegraph: outside-preview OK")
end

-- ceil behavior: 26.4s still reads as 27 (counts down to 1 then 0).
do
	local d = SwapTelegraphModel.display(26.4, PREVIEW)
	expect(d.timerText == "27", "26.4s should ceil to '27', got " .. tostring(d.timerText))
	print("telegraph: ceil timerText OK")
end

-- At the preview boundary (s == previewSeconds): in preview, big = 3, flash just starting.
do
	local d = SwapTelegraphModel.display(3, PREVIEW)
	expect(d.inPreview == true, "3s == previewSeconds must be in preview")
	expect(d.bigCountdownInt == 3, "big countdown at 3s should be 3")
	expect(d.flashAlpha == 0, "flash should start at 0 at the boundary")
	print("telegraph: preview boundary OK")
end

-- Mid preview: big counts down, flash ramps 0..1 as s -> 0.
do
	local d2 = SwapTelegraphModel.display(2, PREVIEW)
	expect(d2.bigCountdownInt == 2, "big at 2s should be 2")
	expect(math.abs(d2.flashAlpha - (1 / 3)) < 1e-6, "flashAlpha at 2s should be 1/3")
	local d1 = SwapTelegraphModel.display(1, PREVIEW)
	expect(d1.bigCountdownInt == 1, "big at 1s should be 1")
	expect(d1.flashAlpha > d2.flashAlpha, "flash should intensify as the swap nears")
	print("telegraph: mid-preview ramp OK")
end

-- At/after the swap moment: clamp text to 0, no big countdown, but HOLD the flash
-- at peak. The actual swap (SetControlledBody) and the next cycle's deadline land
-- a beat after the predicted T0 (server task.wait overshoot + replication), so the
-- flash must stay up through that gap instead of blinking out before the swap.
do
	local d0 = SwapTelegraphModel.display(0, PREVIEW)
	expect(d0.timerText == "0", "timerText at 0 should be '0'")
	expect(d0.bigCountdownInt == nil, "no big countdown at the swap moment (s <= 0)")
	expect(d0.inPreview == true, "still in preview at the swap moment")
	expect(d0.flashAlpha == 1, "flash holds at peak at the swap moment")
	local dn = SwapTelegraphModel.display(-1.5, PREVIEW)
	expect(dn.timerText == "0", "negative seconds clamp to '0'")
	expect(dn.bigCountdownInt == nil, "no big countdown past the swap")
	expect(dn.flashAlpha == 1, "flash stays held just past the swap until the next cycle")
	print("telegraph: swap-moment hold OK")
end

print("ALL SwapTelegraphModel TESTS PASSED")
