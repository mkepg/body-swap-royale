local SoulAnimModel = require("../src/shared/SoulAnimModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b) return math.abs(a - b) < 0.5 end

local FILL = { r = 100, g = 200, b = 0 }

-- nil anim -> fill, always.
do
	local c = SoulAnimModel.colorAt(nil, FILL, 12.34)
	expect(c == FILL, "no anim returns fill identity")
	print("anim: none OK")
end

-- osc: t=0 -> fill, t=period/2 -> to, t=period -> fill (cosine ease).
do
	local anim = { kind = "osc", to = { r = 0, g = 0, b = 100 }, period = 4 }
	local c0 = SoulAnimModel.colorAt(anim, FILL, 0)
	expect(near(c0.r, 100) and near(c0.b, 0), "osc t=0 at fill")
	local ch = SoulAnimModel.colorAt(anim, FILL, 2)
	expect(near(ch.r, 0) and near(ch.b, 100), "osc t=period/2 at to")
	local cf = SoulAnimModel.colorAt(anim, FILL, 4)
	expect(near(cf.r, 100), "osc wraps at period")
	print("anim: osc OK")
end

-- steps: hard snaps, last frame holds to period end.
do
	local anim = { kind = "steps", period = 2, frames = {
		{ at = 0.0, c = { r = 10, g = 0, b = 0 } },
		{ at = 0.5, c = { r = 20, g = 0, b = 0 } },
	} }
	expect(SoulAnimModel.colorAt(anim, FILL, 0.2).r == 10, "steps frame 1")
	expect(SoulAnimModel.colorAt(anim, FILL, 1.2).r == 20, "steps frame 2")
	expect(SoulAnimModel.colorAt(anim, FILL, 1.99).r == 20, "steps holds last")
	expect(SoulAnimModel.colorAt(anim, FILL, 2.2).r == 10, "steps wraps")
	print("anim: steps OK")
end

-- flicker: deterministic for same t; stays within fill..to channel bounds.
do
	local anim = { kind = "flicker", to = { r = 255, g = 150, b = 54 }, period = 1.3 }
	local a = SoulAnimModel.colorAt(anim, { r = 200, g = 30, b = 20 }, 0.7)
	local b = SoulAnimModel.colorAt(anim, { r = 200, g = 30, b = 20 }, 0.7)
	expect(a.r == b.r and a.g == b.g, "flicker deterministic")
	expect(a.r >= 200 - 0.5 and a.r <= 255.5, "flicker r in range")
	print("anim: flicker OK")
end

-- hue: rotates; quarter period apart differ; period apart equal.
do
	local anim = { kind = "hue", period = 8, s = 0.72, v = 1.0 }
	local a = SoulAnimModel.colorAt(anim, FILL, 0)
	local b = SoulAnimModel.colorAt(anim, FILL, 2)
	local c = SoulAnimModel.colorAt(anim, FILL, 8)
	expect(a.r ~= b.r or a.g ~= b.g or a.b ~= b.b, "hue moves")
	expect(near(a.r, c.r) and near(a.g, c.g) and near(a.b, c.b), "hue wraps")
	print("anim: hue OK")
end

-- phase + flashOn: rim pulses land in the first 20% of the period only.
do
	local anim = { kind = "flash", period = 4 }
	expect(near(SoulAnimModel.phase(anim, 2), 0.5), "phase midpoint")
	expect(SoulAnimModel.flashOn(anim, 0.1) == true, "first pulse on")
	expect(SoulAnimModel.flashOn(anim, 0.3) == false, "between pulses off")
	expect(SoulAnimModel.flashOn(anim, 0.45) == true, "second pulse on")
	expect(SoulAnimModel.flashOn(anim, 2.0) == false, "rest of period off")
	print("anim: flash OK")
end

print("ALL soul_anim_model tests passed")
