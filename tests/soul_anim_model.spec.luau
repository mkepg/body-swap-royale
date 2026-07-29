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

-- ===== scrollStops: the seamless cyclic gradient scroll (2026-07-25 pop fix) =====
-- Evaluate an emitted keypoint list the way a UIGradient does: piecewise-linear in `at`.
local function evalKps(kps, x)
	for i = 2, #kps do
		local a, b = kps[i - 1], kps[i]
		if x <= b.at then
			local span = b.at - a.at
			local k = span > 0 and (x - a.at) / span or 0
			return {
				r = a.r + (b.r - a.r) * k,
				g = a.g + (b.g - a.g) * k,
				b = a.b + (b.b - a.b) * k,
			}
		end
	end
	local last = kps[#kps]
	return { r = last.r, g = last.g, b = last.b }
end
local function maxChannelDiff(a, b)
	return math.max(math.abs(a.r - b.r), math.abs(a.g - b.g), math.abs(a.b - b.b))
end

local DUSK = { -- Duskfall's catalog stops: deliberately NON-cyclic (purple/pink/orange)
	{ r = 122, g = 75, b = 214 },
	{ r = 232, g = 106, b = 154 },
	{ r = 255, g = 179, b = 92 },
}

-- Shape contract: first at=0, last at=1, strictly increasing, within Roblox's 20-key cap.
do
	for _, p in ipairs({ 0, 0.13, 1 / 3, 0.5, 0.9999 }) do
		local kps = SoulAnimModel.scrollStops(DUSK, p)
		expect(kps[1].at == 0, "scrollStops starts at 0 (p=" .. p .. ")")
		expect(kps[#kps].at == 1, "scrollStops ends at 1 (p=" .. p .. ")")
		expect(#kps <= 20, "scrollStops within the 20-keypoint cap")
		for i = 2, #kps do
			expect(kps[i].at > kps[i - 1].at, "scrollStops times strictly increase (p=" .. p .. ")")
		end
	end
	print("anim: scrollStops shape OK")
end

-- Seam contract: both ends carry the SAME color, so the sequence tiles against itself.
do
	for _, p in ipairs({ 0, 0.2, 0.5, 0.77 }) do
		local kps = SoulAnimModel.scrollStops(DUSK, p)
		expect(maxChannelDiff(kps[1], kps[#kps]) < 1e-9, "scrollStops endpoints match (p=" .. p .. ")")
	end
	print("anim: scrollStops seam OK")
end

-- THE REGRESSION THIS FIXES: the old binding sawtoothed UIGradient.Offset from -1 to +1
-- over a non-cyclic sequence, so the wrap swapped one clamped edge color for the other --
-- Duskfall popped orange -> purple every 7s. Continuity across the wrap means sampling
-- the whole gradient at p=1-eps and at p=0 must agree everywhere.
do
	local before = SoulAnimModel.scrollStops(DUSK, 1 - 1e-6)
	local after = SoulAnimModel.scrollStops(DUSK, 0)
	local worst = 0
	for i = 0, 40 do
		local x = i / 40
		worst = math.max(worst, maxChannelDiff(evalKps(before, x), evalKps(after, x)))
	end
	expect(worst < 0.5, "scrollStops is continuous across the period wrap (worst=" .. worst .. ")")
	print("anim: scrollStops wrap continuity OK")
end

-- No stall: consecutive phases must actually differ (the old Offset range spent most of
-- the period clamped flat, which is what made Gilded's sweep read "laggy").
do
	local moved = 0
	for i = 0, 19 do
		local a = SoulAnimModel.scrollStops(DUSK, i / 20)
		local b = SoulAnimModel.scrollStops(DUSK, (i + 1) / 20)
		if maxChannelDiff(evalKps(a, 0.5), evalKps(b, 0.5)) > 0.5 then
			moved += 1
		end
	end
	expect(moved == 20, "scrollStops advances every step, no dead zone (moved=" .. moved .. ")")
	print("anim: scrollStops no-stall OK")
end

-- 2-stop ring = the sweep band (fill -> to -> fill); still seamless and still moving.
do
	local ring = { { r = 201, g = 154, b = 46 }, { r = 255, g = 224, b = 138 } }
	local kps = SoulAnimModel.scrollStops(ring, 0.25)
	expect(maxChannelDiff(kps[1], kps[#kps]) < 1e-9, "2-stop ring endpoints match")
	local before = SoulAnimModel.scrollStops(ring, 1 - 1e-6)
	local after = SoulAnimModel.scrollStops(ring, 0)
	expect(maxChannelDiff(evalKps(before, 0.3), evalKps(after, 0.3)) < 0.5, "2-stop ring wraps continuously")
	print("anim: scrollStops sweep ring OK")
end

-- ===== rippleFade: pulse/seraph rings emit and dissolve, never blink in =====
do
	-- tight tolerance: these are 0..1 transparencies, not 0..255 channels
	local function tight(a, b) return math.abs(a - b) < 1e-9 end
	expect(tight(SoulAnimModel.rippleFade(0, 0.2), 1), "ripple invisible at p=0")
	expect(tight(SoulAnimModel.rippleFade(1, 0.2), 1), "ripple invisible at p=1")
	expect(tight(SoulAnimModel.rippleFade(0.5, 0.2), 0.2), "ripple peaks mid-cycle at minT")
	-- Wrap continuity (the old `0.2 + 0.8p` ramp jumped 1.0 -> 0.2 in a single frame).
	local jump = math.abs(SoulAnimModel.rippleFade(1 - 1e-6, 0.2) - SoulAnimModel.rippleFade(0, 0.2))
	expect(jump < 1e-4, "rippleFade is continuous across the wrap (jump=" .. jump .. ")")
	-- Never brighter than minT, never darker than fully transparent.
	for i = 0, 50 do
		local v = SoulAnimModel.rippleFade(i / 50, 0.2)
		expect(v >= 0.2 - 1e-9 and v <= 1 + 1e-9, "rippleFade stays in [minT, 1]")
	end
	print("anim: rippleFade OK")
end

-- ===== breathe: the halo's size-independent aliveness channel =====
do
	local function tight(a, b) return math.abs(a - b) < 1e-9 end
	expect(tight(SoulAnimModel.breathe(0, 2), 0), "breathe starts at 0")
	expect(tight(SoulAnimModel.breathe(1, 2), 1), "breathe peaks at half period")
	expect(tight(SoulAnimModel.breathe(2, 2), 0), "breathe returns at full period")
	-- wrap continuity: the whole point (a sawtooth here would pop, like the old ripple)
	local jump = math.abs(SoulAnimModel.breathe(2 - 1e-6, 2) - SoulAnimModel.breathe(0, 2))
	expect(jump < 1e-6, "breathe is continuous across the wrap (jump=" .. jump .. ")")
	-- bounded, and phase actually shifts
	for i = 0, 60 do
		local v = SoulAnimModel.breathe(i / 10, 2.4)
		expect(v >= 0 and v <= 1, "breathe stays in [0,1]")
	end
	expect(math.abs(SoulAnimModel.breathe(0, 2, 0.5) - 1) < 1e-9, "phase 0.5 inverts")
	-- staggered phases (seraph's 3-shard twinkle) must not coincide
	local a = SoulAnimModel.breathe(0.7, 2.2, 0)
	local b = SoulAnimModel.breathe(0.7, 2.2, 1 / 3)
	local c = SoulAnimModel.breathe(0.7, 2.2, 2 / 3)
	expect(math.abs(a - b) > 1e-3 and math.abs(b - c) > 1e-3, "staggered phases differ")
	print("anim: breathe OK")
end

print("ALL soul_anim_model tests passed")
