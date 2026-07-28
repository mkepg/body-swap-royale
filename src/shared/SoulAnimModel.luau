--[[
	SoulAnimModel -- PURE animated-halo-color math (spec §4.1 anim kinds). Given an
	anim spec, the fill, and a time, returns the {r,g,b} to show. Deterministic in t
	(no state, no RNG) so every client renders the same wearer identically and lune
	can pin behavior. Kinds handled HERE: osc, flicker, steps, hue. Kinds handled
	STRUCTURALLY by the renderer (they animate sub-elements, not the flat color):
	sweep/gradient (a seamless cyclic keypoint scroll via SoulAnimModel.scrollStops) and
	flash (rim pulse via SoulAnimModel.flashOn). Structural ripples (pulse/seraph) get
	their wrap-continuous opacity from SoulAnimModel.rippleFade.

	WRAP CONTINUITY IS THE CONTRACT. Everything here is driven by the sawtooth phase
	(t % period)/period, so any value mapped from it MUST agree at p=0 and p=1 or the
	renderer faithfully draws a one-frame pop -- which reads as "choppy". osc/flicker/hue
	satisfy this by construction (whole numbers of sine/hue cycles); steps and flash are
	the two DELIBERATE exceptions (broadcast-glitch cuts and lightning). If you add a
	kind, prove f(0) == f(1) in a test.
	Location (Roblox): ReplicatedStorage/Shared/SoulAnimModel  (ModuleScript)
--]]

local SoulAnimModel = {}

local function lerp(a, b, k)
	return {
		r = a.r + (b.r - a.r) * k,
		g = a.g + (b.g - a.g) * k,
		b = a.b + (b.b - a.b) * k,
	}
end

-- 0..1 phase within the period (shared by renderer for sweep/gradient offsets).
function SoulAnimModel.phase(anim, t)
	return (t % anim.period) / anim.period
end

-- flash: two quick rim pulses early in the period (Stormcloud lightning). The
-- catalog's flash spec only carries `period` ({ kind = "flash", period = 4 }) --
-- the "two pulses" RHYTHM lives HERE, not in catalog data; change the feel by
-- editing these windows, not the shop data.
function SoulAnimModel.flashOn(anim, t)
	local p = SoulAnimModel.phase(anim, t)
	return (p >= 0.00 and p < 0.05) or (p >= 0.10 and p < 0.14)
end

local function hsvToRgb(h, s, v) -- h 0..1
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, r2 = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local map = {
		[0] = { v, r2, p }, [1] = { q, v, p }, [2] = { p, v, r2 },
		[3] = { p, q, v }, [4] = { r2, p, v }, [5] = { v, p, q },
	}
	local c = map[i]
	return { r = c[1] * 255, g = c[2] * 255, b = c[3] * 255 }
end

function SoulAnimModel.colorAt(anim, fill, t)
	if not anim then
		return fill
	end
	local p = SoulAnimModel.phase(anim, t)
	if anim.kind == "osc" then
		local k = 0.5 - 0.5 * math.cos(p * 2 * math.pi) -- fill -> to -> fill
		return lerp(fill, anim.to, k)
	elseif anim.kind == "steps" then
		local current = anim.frames[1].c
		for _, frame in ipairs(anim.frames) do
			if p >= frame.at then current = frame.c end
		end
		return current
	elseif anim.kind == "flicker" then
		-- Two incommensurate sines -> irregular but deterministic 0..1 mix.
		local k = 0.5 + 0.25 * math.sin(p * 2 * math.pi * 3)
			+ 0.25 * math.sin(p * 2 * math.pi * 7 + 1.3)
		return lerp(fill, anim.to, math.clamp(k, 0, 1))
	elseif anim.kind == "hue" then
		return hsvToRgb(p, anim.s, anim.v)
	end
	return fill -- sweep/gradient/flash: flat color stays fill; renderer animates
end

-- Interior positions closer than this to an endpoint are dropped: ColorSequence
-- keypoint times must be STRICTLY increasing, and a ring stop crossing the seam
-- carries the same color the endpoints already do, so dropping it changes nothing.
local EPS = 1e-4

-- Color of the cyclic ring at ring-position `u` (period 1). The n stops sit at i/n and
-- the last segment wraps back to the first -- that wrap is what makes the scroll seamless.
local function ringColorAt(stops, u)
	local n = #stops
	u = u % 1
	local f = u * n
	local i = math.floor(f)
	local a = stops[i % n + 1]
	local b = stops[(i + 1) % n + 1]
	return lerp(a, b, f - i)
end

-- Seamless CYCLIC gradient scroll -- the fix for the sweep/gradient "pop" (2026-07-25).
--
-- The old binding scrolled a UIGradient by sawtoothing Offset from -1 to +1. A UIGradient
-- CLAMPS outside [0,1] to its edge keypoints, so that range spends most of the period
-- showing a flat clamped edge (motion stalls -- Gilded read "laggy") and then jumps the
-- full width in one frame. With a non-cyclic ColorSequence the two clamped edges are
-- DIFFERENT colors, so the jump is a hard visible pop (Duskfall snapped orange->purple
-- every 7s; measured in-game as a 1.995 one-frame Offset delta).
--
-- Instead we leave Offset at 0 and rebuild the sequence itself: treat `stops` as a RING
-- of colors and emit the keypoints for C(x + p), x in [0,1]. Both endpoints are C(p), so
-- the sequence is continuous across its own seam AND across the period wrap -- the band
-- travels forever with no stall and no jump. `stops` = array of {r,g,b} (n >= 2);
-- returns { { at, r, g, b }, ... } with `at` strictly increasing from 0 to 1.
function SoulAnimModel.scrollStops(stops, p)
	local n = #stops
	assert(n >= 2, "scrollStops needs at least 2 stops")
	p = p % 1
	local seam = ringColorAt(stops, p)
	local interior = {}
	for i = 0, n - 1 do
		local x = (i / n - p) % 1
		if x > EPS and x < 1 - EPS then
			interior[#interior + 1] = { at = x, c = stops[i + 1] }
		end
	end
	table.sort(interior, function(a, b) return a.at < b.at end)

	local kps = { { at = 0, r = seam.r, g = seam.g, b = seam.b } }
	for _, e in ipairs(interior) do
		kps[#kps + 1] = { at = e.at, r = e.c.r, g = e.c.g, b = e.c.b }
	end
	kps[#kps + 1] = { at = 1, r = seam.r, g = seam.g, b = seam.b }
	return kps
end

-- Ripple opacity for the pulse/seraph expanding rings. The ring must be INVISIBLE at
-- both ends of the period: the old linear ramp (minT -> 1) snapped straight back to minT
-- at the wrap, so the ring materialised at 80% opacity out of nowhere every cycle (a
-- measured 0.79 one-frame transparency jump). sin(pi*p) is 0 at p=0 AND p=1, so the
-- size reset now happens while the ring is fully transparent -- it emits and dissolves.
function SoulAnimModel.rippleFade(p, minT)
	return 1 - (1 - minT) * math.sin(math.pi * (p % 1))
end

-- Continuous 0..1 "breathe" over `period` seconds, optionally phase-shifted by `phase`
-- (in turns). Cosine, so it is smooth everywhere AND equal at both ends of the period.
--
-- This is the halo's primary aliveness channel (2026-07-26). Halo billboards are only
-- 24 px (others) / 42 px (mine), and at that scale every GEOMETRIC animation is sub-pixel
-- per frame -- measured: the Eclipse aura advanced 0.033 px/frame, i.e. one pixel every
-- 30 frames, so the rasteriser held it still and then ticked. That reads as stutter no
-- matter how exact the maths is. Transparency and colour are blend factors, not spatial
-- quantities: they are smooth at ANY pixel size. So every style now carries its life on a
-- breathe, and the geometric motion is amplitude-boosted rather than relied upon alone.
function SoulAnimModel.breathe(t, period, phase)
	local p = (t / period + (phase or 0)) % 1
	return 0.5 - 0.5 * math.cos(p * 2 * math.pi)
end

return SoulAnimModel
