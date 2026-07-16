--[[
	SoulAnimModel -- PURE animated-halo-color math (spec §4.1 anim kinds). Given an
	anim spec, the fill, and a time, returns the {r,g,b} to show. Deterministic in t
	(no state, no RNG) so every client renders the same wearer identically and lune
	can pin behavior. Kinds handled HERE: osc, flicker, steps, hue. Kinds handled
	STRUCTURALLY by the renderer (they animate sub-elements, not the flat color):
	sweep/gradient (UIGradient offset via SoulAnimModel.phase) and flash (rim pulse
	via SoulAnimModel.flashOn).
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

return SoulAnimModel
