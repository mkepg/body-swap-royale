--[[
	SoulStyles -- ONE construction + animation pipeline for every Soul halo, free
	Classic included (spec §6.1). Builders return handles parented into the halo
	BillboardGui; a single shared Heartbeat animator drives every animated element
	(rotation, ripple, breathe, color anims via SoulAnimModel).

	Per-frame budget: <= 16 color writes + <= 8 property writes per visible halo. The
	property line was raised from 3 on 2026-07-26: EVERY style now carries a breathe (and
	Seraph a per-shard twinkle), because at 24/42px billboard scale the geometric motion is
	sub-pixel per frame -- measured 0.033 to 0.42 px/frame -- and cannot be perceptually
	smooth on its own; transparency is the only channel that is size-independent. Worst
	case is Seraph at 6 writes; frame time was indistinguishable from an
	all-cards-destroyed control with all 16 shop previews live.

	SoulStyles.build(parent, styleKey, colorSpec, sizePx, isMine) -> handle
	  parent: the BillboardGui to fill
	  styleKey: "classic"|"ring"|"pulse"|"orbit"|"eclipse"|"seraph" (unknown -> classic)
	  colorSpec: { fill = Color3, luminous = Color3, anim = table? } -- PRE-RESOLVED
	  handle: { setColors(fill, luminous), destroy() }
	SoulStyles.buildPreview(item, px, ctx?) -> Frame  (shop cards; renders the RESOLVED
	  composite: color card = this color x equipped style; style card = this style x equipped
	  color. ctx = { colorSpec = <resolved colorSpec or nil>, styleKey = <equipped styleKey or nil> })
	SoulStyles.start() -- binds the shared animator (idempotent)

	NOTE: the identity/style-preview color below is the free Soul cyan. Aurora's
	catalog fill (200,110,255) deliberately equals Config.WORLD_AURORA_BASE_COLOR;
	that pairing is maintained BY HAND because ShopCatalog is Roblox-free and cannot
	require Config. If you retune one, retune the other.
--]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoulAnimModel = require(Shared:WaitForChild("SoulAnimModel"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))

local SoulStyles = {}

-- Free Soul cyan: style previews (colorless frames) and any unresolved fallback.
local IDENTITY = Color3.fromRGB(57, 214, 224)
-- Eclipse's signature dark disc -- fixed regardless of the wearer's color.
local ECLIPSE_DISC = Color3.fromRGB(25, 16, 38)
local WHITE = Color3.new(1, 1, 1)

-- ===== shared animator ==================================================
-- ONE Heartbeat over a registry of live handles. Only ANIMATED handles are
-- registered (static halos are torn down by their owner). A handle is dropped
-- once its gui has been seen parented and later loses its Parent (body/card
-- destroyed) -- this bounds registry growth without a weak table.
local registry = {}
local animConn = nil

local NEVER_PARENTED_GRACE = 600 -- ~10s @60fps: drop handles never mounted (leak guard)

local function stepAnimator()
	local now = os.clock()
	local n = #registry
	local w = 0
	for i = 1, n do
		local h = registry[i]
		if h and not h._dead then
			if h.gui.Parent then
				-- running: parented (again) -> animate
				h._seen = true
				h._graceFrames = nil
				w += 1
				registry[w] = h
				h._animate(now)
			elseif not h._seen then
				-- not-yet-parented (preview between build and mount): keep briefly,
				-- but bound the wait so an orphaned preview can't linger forever.
				h._graceFrames = (h._graceFrames or 0) + 1
				if h._graceFrames < NEVER_PARENTED_GRACE then
					w += 1
					registry[w] = h
				end
			end
			-- else: was seen parented, now unparented (destroyed) -> drop
		end
	end
	for i = w + 1, n do
		registry[i] = nil
	end
end

function SoulStyles.start()
	if animConn then
		return
	end
	animConn = RunService.Heartbeat:Connect(stepAnimator)
end

local function registerHandle(h)
	registry[#registry + 1] = h
end

-- Expose the animator to sibling systems (Soul trails' meteor cycle).
function SoulStyles.registerAnimated(guiRef, animateFn)
	local h = { gui = guiRef, _dead = false, _seen = false, _animate = animateFn }
	registerHandle(h)
	return h
end

-- ===== motion tempo =====================================================
-- ONE tempo family so the six styles read as one set instead of six arbitrary loops
-- (they used to be 1.6 / 2.4 / 3 / 6 / 2.4s, picked independently). Rates were also
-- raised across the board: at 24 px every geometric animation here was moving well under
-- one pixel per frame -- measured 0.033 px/frame (Eclipse aura) to 0.419 (Orbit) -- so
-- continuous maths rasterised into visible steps. See SoulAnimModel.breathe.
local TEMPO = {
	breathe = 2.6, -- the slow glow every style carries (size-independent, always smooth)
	ripple = 1.25, -- pulse's emitted ring (was 1.6)
	spin = 1.8, -- orbit's revolution (was 3.0)
	ringSpin = 3.6, -- seraph's shard ring (was 6.0)
	twinkle = 2.2, -- seraph's staggered shard sparkle
	aura = 2.0, -- eclipse's aura (was 2.4, and far too shallow)
}

-- ===== element helpers ==================================================
local function clamp255(x)
	return x < 0 and 0 or (x > 255 and 255 or x)
end

local function rgbToColor3(t)
	return Color3.new(clamp255(t.r) / 255, clamp255(t.g) / 255, clamp255(t.b) / 255)
end

local function rgbFromColor3(c)
	return { r = c.R * 255, g = c.G * 255, b = c.B * 255 }
end

local function colorsDiffer(a, b)
	return a.R ~= b.R or a.G ~= b.G or a.B ~= b.B
end

-- Centered circle in SCALE units of its parent (billboard-relative).
local function circle(parent, scale, color, zindex)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(scale, scale)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zindex
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	f.Parent = parent
	return f
end

local function makeStroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.Parent = parent
	return s
end

local function bgTarget(frame)
	return function(c)
		frame.BackgroundColor3 = c
	end
end

local function strokeTarget(s)
	return function(c)
		s.Color = c
	end
end

-- Full-scale invisible rim + luminous UIStroke that a flash color (Stormcloud)
-- pulses on/off. Returns nil,nil for non-flash colors so it costs nothing on the
-- styles that add it defensively. Stroke starts at 0.65 (subtle) until flashOn -> 0.
local function makeFlashRim(root, state)
	if not (state.anim and state.anim.kind == "flash") then
		return nil, nil
	end
	local rim = circle(root, 1.0, state.luminous, 2)
	rim.BackgroundTransparency = 1
	local rimStroke = makeStroke(rim, state.sizePx * 0.12, state.luminous) -- 12% of billboard px
	rimStroke.Transparency = 0.65
	return rim, rimStroke
end

-- ===== style builders ===================================================
-- Each builder fills `root` and populates `ctx`:
--   ctx.applyColors()   -- write all STATIC/flat colors
--   ctx.fillTargets     -- apply-fns for the animated color (bg / stroke)
--   ctx.baseKey         -- "fillRgb" (default) or "luminousRgb" -- animation base
--   ctx.gradientTarget  -- instance to host a sweep/gradient UIGradient (optional)
--   ctx.rimStroke       -- stroke a flash anim pulses (optional)
-- and may push structural ticks (rotation/ripple) into `ticks`.
local BUILDERS = {}

function BUILDERS.classic(root, state, ticks, ctx)
	local px = state.sizePx
	local under = circle(root, 1.30, state.luminous, 1)
	under.BackgroundTransparency = 0.72
	local core = circle(root, 0.92, state.fill, 2)

	-- Classic used to have NO motion whatsoever: with a non-animated colour the halo was a
	-- completely frozen dot. It now breathes its underglow, so every soul reads as alive.
	ticks[#ticks + 1] = function(now)
		local b = SoulAnimModel.breathe(now, TEMPO.breathe)
		under.BackgroundTransparency = 0.82 - 0.20 * b -- 0.82 -> 0.62
		local s = 1.24 + 0.16 * b
		under.Size = UDim2.fromScale(s, s)
	end

	-- Rim ring only where it reads: Void-type (luminous != fill, no anim) for the
	-- glow halo, or a flash color which pulses the rim on/off.
	local isFlash = state.anim ~= nil and state.anim.kind == "flash"
	local voidType = state.anim == nil and colorsDiffer(state.fill, state.luminous)
	local rim, rimStroke
	if voidType or isFlash then
		rim = circle(root, 1.0, state.luminous, 2)
		rim.BackgroundTransparency = 1
		rimStroke = makeStroke(rim, px * 0.12, state.luminous) -- 12% of billboard px
		if isFlash then
			rimStroke.Transparency = 0.65 -- dim between pulses; flashOn -> 0
		end
	end

	ctx.fillTargets = { bgTarget(core) }
	ctx.gradientTarget = core
	ctx.rimStroke = isFlash and rimStroke or nil
	ctx.applyColors = function()
		under.BackgroundColor3 = state.luminous
		core.BackgroundColor3 = state.fill
		if rim then
			rimStroke.Color = state.luminous
		end
	end
end

function BUILDERS.ring(root, state, ticks, ctx)
	local px = state.sizePx
	-- Softened underglow (0.80) so the middle reads EMPTY, not a dark orb.
	local under = circle(root, 1.20, state.luminous, 1)
	under.BackgroundTransparency = 0.80
	-- Hollow annulus (transparent center) + a thin fill-colored stroke, thinner than before.
	local annulus = circle(root, 1.0, state.fill, 2)
	annulus.BackgroundTransparency = 1
	local ann = makeStroke(annulus, px * 0.15, state.fill) -- 15% of billboard px
	-- Crisp BRIGHT inner accent: a slightly-smaller ring in lightened fill (55% -> white),
	-- giving the halo a clean double edge around its empty middle.
	local accent = circle(root, 0.84, state.fill, 3)
	accent.BackgroundTransparency = 1
	local accentStroke = makeStroke(accent, 1.5, state.fill:Lerp(WHITE, 0.55))
	local rim, rimStroke = makeFlashRim(root, state) -- flash colors (Stormcloud) pulse here

	-- Ring was the other completely static style. A ring is rotationally symmetric, so
	-- spinning it would be invisible -- its life is an energy breathe instead: the
	-- underglow swells while the bright inner accent pulses against it (counter-phased,
	-- so the halo always has something moving).
	ticks[#ticks + 1] = function(now)
		local b = SoulAnimModel.breathe(now, TEMPO.breathe)
		under.BackgroundTransparency = 0.88 - 0.20 * b
		local s = 1.14 + 0.14 * b
		under.Size = UDim2.fromScale(s, s)
		accentStroke.Transparency = 0.55 - 0.55 * (1 - b) -- 0 -> 0.55, opposite the glow
	end

	ctx.fillTargets = { strokeTarget(ann) }
	ctx.gradientTarget = annulus -- a UIGradient here tints the annulus stroke
	ctx.rimStroke = rimStroke
	ctx.applyColors = function()
		under.BackgroundColor3 = state.luminous
		ann.Color = state.fill
		accentStroke.Color = state.fill:Lerp(WHITE, 0.55)
		if rim then
			rimStroke.Color = state.luminous
		end
	end
end

function BUILDERS.pulse(root, state, ticks, ctx)
	local under = circle(root, 1.30, state.luminous, 1)
	under.BackgroundTransparency = 0.72
	local core = circle(root, 0.80, state.fill, 2)
	local ripple = circle(root, 0.80, state.luminous, 1)
	ripple.BackgroundTransparency = 1
	local rip = makeStroke(ripple, 3, state.luminous)
	rip.Transparency = 0.2
	local rim, rimStroke = makeFlashRim(root, state) -- flash colors (Stormcloud) pulse here

	-- The ring EXPANDS linearly but fades in AND out (rippleFade), so it is invisible at
	-- both ends of the loop -- the size reset at the wrap happens unseen. The old linear
	-- fade snapped back to 0.2, popping the ring into view at 80% opacity every 1.6s.
	-- Faster and wider than before (1.6s/0.72 span): at 24px the old ripple crept at
	-- 0.18 px/frame, which reads as a stalled ring rather than an emitted one.
	rip.Transparency = 1
	ticks[#ticks + 1] = function(now)
		local p = (now % TEMPO.ripple) / TEMPO.ripple
		local s = 0.78 + 0.94 * p -- 0.78 -> 1.72
		ripple.Size = UDim2.fromScale(s, s)
		rip.Transparency = SoulAnimModel.rippleFade(p, 0.15)
		-- the core breathes underneath, so the halo lives between ripples too
		local b = SoulAnimModel.breathe(now, TEMPO.breathe)
		under.BackgroundTransparency = 0.80 - 0.16 * b
	end

	ctx.fillTargets = { bgTarget(core) }
	ctx.gradientTarget = core
	ctx.rimStroke = rimStroke
	ctx.applyColors = function()
		under.BackgroundColor3 = state.luminous
		core.BackgroundColor3 = state.fill
		rip.Color = state.luminous
		if rim then
			rimStroke.Color = state.luminous
		end
	end
end

function BUILDERS.orbit(root, state, ticks, ctx)
	local under = circle(root, 1.20, state.luminous, 1)
	under.BackgroundTransparency = 0.72
	local core = circle(root, 0.70, state.fill, 2)

	local carrier = Instance.new("Frame")
	carrier.AnchorPoint = Vector2.new(0.5, 0.5)
	carrier.Position = UDim2.fromScale(0.5, 0.5)
	carrier.Size = UDim2.fromScale(1, 1)
	carrier.BackgroundTransparency = 1
	carrier.BorderSizePixel = 0
	carrier.ZIndex = 3
	carrier.Parent = root
	local satL = circle(carrier, 0.25, state.luminous, 3)
	satL.Position = UDim2.fromScale(0, 0.5)
	local satR = circle(carrier, 0.25, state.luminous, 3)
	satR.Position = UDim2.fromScale(1, 0.5)
	local rim, rimStroke = makeFlashRim(root, state) -- flash colors (Stormcloud) pulse here

	-- Spin raised from 3.0s to 1.8s per revolution: at 24px the satellites travelled
	-- 0.419 px/frame, below the threshold where rotation reads as motion rather than
	-- stepping. The satellites also breathe out of phase with each other, which is smooth
	-- at any pixel size and keeps the halo alive even when the spin is edge-on small.
	ticks[#ticks + 1] = function(now)
		carrier.Rotation = (now / TEMPO.spin * 360) % 360
		local a = SoulAnimModel.breathe(now, TEMPO.breathe)
		local b = SoulAnimModel.breathe(now, TEMPO.breathe, 0.5)
		satL.BackgroundTransparency = 0.35 - 0.35 * a
		satR.BackgroundTransparency = 0.35 - 0.35 * b
		under.BackgroundTransparency = 0.80 - 0.16 * a
	end

	ctx.fillTargets = { bgTarget(core) }
	ctx.gradientTarget = core
	ctx.rimStroke = rimStroke
	ctx.applyColors = function()
		under.BackgroundColor3 = state.luminous
		core.BackgroundColor3 = state.fill
		satL.BackgroundColor3 = state.luminous
		satR.BackgroundColor3 = state.luminous
		if rim then
			rimStroke.Color = state.luminous
		end
	end
end

function BUILDERS.eclipse(root, state, ticks, ctx)
	local px = state.sizePx
	-- Breathing outer aura (ZIndex 0, behind everything): a luminous halo the animator
	-- gently pulses -- Eclipse's living glow, which Ring lacks entirely.
	local aura = circle(root, 1.50, state.luminous, 0)
	aura.BackgroundTransparency = 0.55
	-- Solid, OPAQUE dark orb (t=0) + a faint lighter core for a subtle radial 3D read.
	local disc = circle(root, 1.0, ECLIPSE_DISC, 1)
	local core = circle(root, 0.40, Color3.fromRGB(60, 42, 96), 2)
	core.BackgroundTransparency = 0.90
	-- Blazing luminous corona, thicker than before so the orb reads as eclipsed.
	local corona = makeStroke(disc, px * 0.17, state.luminous) -- 17% of billboard px

	-- Aura breathe, ALWAYS on (independent of the colour anim), so every Eclipse lives even
	-- with a static colour. Amplitude roughly doubled and the period shortened: the old
	-- 1.40->1.60 swing over 2.4s advanced the aura edge at 0.033 px/frame at 24px -- ONE
	-- PIXEL EVERY 30 FRAMES -- and only 0.15 of transparency, so it looked frozen and then
	-- ticked. This was the worst offender of the six styles.
	-- A `flash` colour (Stormcloud) drives this same corona as its lightning rim, so we
	-- leave the rim alone in that pairing rather than writing it twice per frame.
	local coronaIsFlashRim = state.anim ~= nil and state.anim.kind == "flash"
	ticks[#ticks + 1] = function(now)
		local b = SoulAnimModel.breathe(now, TEMPO.aura)
		local s = 1.30 + 0.44 * b -- 1.30 -> 1.74
		aura.Size = UDim2.fromScale(s, s)
		aura.BackgroundTransparency = 0.78 - 0.36 * b -- 0.78 -> 0.42
		if not coronaIsFlashRim then
			corona.Transparency = 0.20 - 0.20 * b -- the eclipse rim flares with the aura
		end
	end

	-- The corona (luminous) is eclipse's only wearer-colored element, so the flat color
	-- anim rides it -- base = luminous so Void-type keeps its bright ring.
	ctx.fillTargets = { strokeTarget(corona) }
	ctx.baseKey = "luminousRgb"
	ctx.gradientTarget = disc -- gradient here tints the corona stroke
	ctx.rimStroke = corona
	ctx.applyColors = function()
		aura.BackgroundColor3 = state.luminous
		disc.BackgroundColor3 = ECLIPSE_DISC
		corona.Color = state.luminous
	end
end

-- V1 concept (2026-07-16-soul-shop-v1-concepts.html §seraph): a bright 22px core
-- with a subtle ripple, wrapped by a thin 6s-spinning ring that carries 3 small
-- rounded-diamond shards on its edge. Airy halo-wrap, not a filled blob.
function BUILDERS.seraph(root, state, ticks, ctx)
	-- soft glow only (V1 had box-shadow, not a filled disc); subtle for 24px legibility
	local under = circle(root, 0.95, state.luminous, 1)
	under.BackgroundTransparency = 0.82
	local core = circle(root, 0.34, state.fill, 2)

	local ripple = circle(root, 0.34, state.luminous, 1)
	ripple.BackgroundTransparency = 1
	local rip = makeStroke(ripple, 3, state.luminous)
	rip.Transparency = 0.2

	-- shard-ring: a thin luminous ring on a 0.875-scale circular carrier (V1 inset:4px
	-- on a 64px wrap) that spins 6s, carrying the shards around with it.
	local carrier = Instance.new("Frame")
	carrier.AnchorPoint = Vector2.new(0.5, 0.5)
	carrier.Position = UDim2.fromScale(0.5, 0.5)
	carrier.Size = UDim2.fromScale(0.875, 0.875)
	carrier.BackgroundTransparency = 1
	carrier.BorderSizePixel = 0
	carrier.ZIndex = 3
	carrier.Parent = root
	local carrierCorner = Instance.new("UICorner")
	carrierCorner.CornerRadius = UDim.new(0.5, 0) -- V1 border-radius:50% -> a true ring
	carrierCorner.Parent = carrier
	local ringStroke = makeStroke(carrier, 2.5, state.luminous)
	ringStroke.Transparency = 0.25

	-- 3 rounded-diamond shards ON the ring edge: top / bottom-left / bottom-right.
	local shardPos = { { 0.5, 0 }, { 0.09, 0.80 }, { 0.91, 0.80 } }
	local shards = {}
	for i, pos in ipairs(shardPos) do
		local sh = Instance.new("Frame")
		sh.AnchorPoint = Vector2.new(0.5, 0.5)
		sh.Position = UDim2.fromScale(pos[1], pos[2])
		sh.Size = UDim2.fromScale(0.16, 0.16)
		sh.Rotation = 45
		sh.BackgroundColor3 = state.luminous
		sh.BorderSizePixel = 0
		sh.ZIndex = 3
		local shardCorner = Instance.new("UICorner")
		shardCorner.CornerRadius = UDim.new(0.3, 0) -- V1 border-radius:2px -> rounded diamond
		shardCorner.Parent = sh
		sh.Parent = carrier
		shards[i] = sh
	end

	local rim, rimStroke = makeFlashRim(root, state) -- flash colors (Stormcloud) pulse here

	-- Same emit-and-dissolve ripple as pulse (see rippleFade): invisible at both ends of
	-- the loop, so the size reset never blinks. Ring spin raised 6.0s -> 3.6s/rev (the
	-- shards crawled at 0.183 px/frame at 24px), and each shard now twinkles on its OWN
	-- phase -- a staggered sparkle that stays perfectly smooth at any pixel size, which is
	-- what actually sells the legendary at billboard scale where the spin cannot.
	rip.Transparency = 1
	local shardPhase = {}
	for i = 1, #shards do
		shardPhase[i] = (i - 1) / #shards
	end
	ticks[#ticks + 1] = function(now)
		local p = (now % TEMPO.ripple) / TEMPO.ripple
		local s = 0.34 + 0.62 * p -- 0.34 -> 0.96
		ripple.Size = UDim2.fromScale(s, s)
		rip.Transparency = SoulAnimModel.rippleFade(p, 0.2)
		carrier.Rotation = (now / TEMPO.ringSpin * 360) % 360
		for i = 1, #shards do
			shards[i].BackgroundTransparency = 0.55 - 0.55 * SoulAnimModel.breathe(now, TEMPO.twinkle, shardPhase[i])
		end
	end

	ctx.fillTargets = { bgTarget(core) }
	ctx.gradientTarget = core
	ctx.rimStroke = rimStroke
	ctx.applyColors = function()
		under.BackgroundColor3 = state.luminous
		core.BackgroundColor3 = state.fill
		rip.Color = state.luminous
		ringStroke.Color = state.luminous
		for _, sh in ipairs(shards) do
			sh.BackgroundColor3 = state.luminous
		end
		if rim then
			rimStroke.Color = state.luminous
		end
	end
end

-- ===== color-animation binding ==========================================
local FLAT_KINDS = { osc = true, flicker = true, steps = true, hue = true }

-- The cyclic ring of `stops`, scrolled to phase `p`, as a ColorSequence. The pure
-- SoulAnimModel.scrollStops owns the wrap math (and is lune-tested); this only converts.
local function ringToSequence(ring, p)
	local kps = SoulAnimModel.scrollStops(ring, p)
	local out = table.create(#kps)
	for i = 1, #kps do
		out[i] = ColorSequenceKeypoint.new(kps[i].at, rgbToColor3(kps[i]))
	end
	return ColorSequence.new(out)
end

-- Bind the color anim to already-built elements. MUST run after ctx.applyColors()
-- so a sweep/gradient can legitimately whiten the fill target underneath its gradient.
local function bindColorAnim(state, ctx, ticks)
	local anim = state.anim
	if not anim then
		return
	end
	local kind = anim.kind

	if FLAT_KINDS[kind] then
		local baseKey = ctx.baseKey or "fillRgb"
		local targets = ctx.fillTargets
		ticks[#ticks + 1] = function(now)
			local c = rgbToColor3(SoulAnimModel.colorAt(anim, state[baseKey], now))
			for i = 1, #targets do
				targets[i](c)
			end
		end

	elseif (kind == "sweep" or kind == "gradient") and ctx.gradientTarget then
		-- Both kinds are the same thing: a CYCLIC ring of colors scrolling under the
		-- element. We hold Offset at 0 and rebuild the ColorSequence each frame from the
		-- pure scroll math, because scrolling via Offset clamps at the gradient's edges --
		-- it stalls for most of the period and then jumps the full width in one frame
		-- (Gilded read "laggy", Duskfall popped orange->purple every 7s). Rebuilding is
		-- ONE property write per frame, the same budget the old Offset write cost.
		--   sweep    -> a 2-stop ring (fill -> to -> fill): a highlight band on a diagonal
		--   gradient -> the catalog's multi-stop ring, drifting vertically
		-- Whiten the fill element first so the gradient shows true colors, not fill*grad.
		for i = 1, #ctx.fillTargets do
			ctx.fillTargets[i](WHITE)
		end
		local ring = kind == "sweep" and { state.fillRgb, anim.to } or anim.stops
		local grad = Instance.new("UIGradient")
		grad.Rotation = kind == "sweep" and 25 or 90
		grad.Color = ringToSequence(ring, 0)
		grad.Parent = ctx.gradientTarget
		-- Negated phase so the pattern still travels in the direction the old Offset ramp
		-- moved it (scrollStops emits C(x + p), which drifts the other way). scrollStops
		-- takes p modulo 1, so a negative phase is fine.
		ticks[#ticks + 1] = function(now)
			grad.Color = ringToSequence(ring, -SoulAnimModel.phase(anim, now))
		end

	elseif kind == "flash" and ctx.rimStroke then
		local rim = ctx.rimStroke
		ticks[#ticks + 1] = function(now)
			rim.Transparency = SoulAnimModel.flashOn(anim, now) and 0 or 0.65
		end
	end
	-- sweep/gradient without a gradient target, or flash without a rim (rare
	-- style x color combos): degrade to the static fill -- never error.
end

-- ===== assembly =========================================================
local function makeState(colorSpec, sizePx)
	return {
		fill = colorSpec.fill,
		luminous = colorSpec.luminous,
		fillRgb = colorSpec.fillRgb or rgbFromColor3(colorSpec.fill),
		luminousRgb = colorSpec.luminousRgb or rgbFromColor3(colorSpec.luminous),
		anim = colorSpec.anim,
		sizePx = sizePx,
	}
end

local function makeRoot(parent, size)
	local root = Instance.new("Frame")
	root.Name = "SoulStyle"
	root.Size = size
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = parent
	return root
end

local function construct(root, styleKey, state)
	local ctx = {}
	local ticks = {}
	local builder = BUILDERS[styleKey] or BUILDERS.classic
	builder(root, state, ticks, ctx)
	ctx.applyColors() -- initial static colors
	bindColorAnim(state, ctx, ticks)
	ctx.ticks = ticks
	return ctx
end

-- `isMine` is accepted for call-site compatibility but no longer affects the halo:
-- the "this is me" cue is the billboard SIZE (SoulController sizes mine 42px / others
-- 24px). The emphasis stroke was removed (luminance-flipped + inconsistent per style).
function SoulStyles.build(parent, styleKey, colorSpec, sizePx, isMine)
	local _ = isMine
	local state = makeState(colorSpec, sizePx)
	local root = makeRoot(parent, UDim2.fromScale(1, 1))
	local ctx = construct(root, styleKey, state)

	local handle = { gui = root, _dead = false, _seen = false }
	handle.setColors = function(fill, luminous)
		state.fill = fill
		state.luminous = luminous
		state.fillRgb = rgbFromColor3(fill)
		state.luminousRgb = rgbFromColor3(luminous)
		ctx.applyColors()
	end
	handle.destroy = function()
		handle._dead = true
		root:Destroy()
	end

	if #ctx.ticks > 0 then
		handle._animate = function(now)
			for i = 1, #ctx.ticks do
				ctx.ticks[i](now)
			end
		end
		registerHandle(handle)
	end
	return handle
end

-- Shop-card preview: same constructions, no billboard. Renders the RESOLVED COMPOSITE
-- so a card matches what the avatar wears. `ctx` (optional) = { colorSpec?, styleKey? }:
--   halo_color -> this color composed with the equipped STYLE (ctx.styleKey or classic)
--   halo_style -> this style composed with the equipped COLOR (ctx.colorSpec or identity cyan)
--   else (Default card / trails handled elsewhere / unknown) -> identity Classic dot; never errors.
-- ctx.colorSpec shape = { fill, luminous, fillRgb, luminousRgb, anim? } -- what build consumes.
-- Backwards-compatible: ctx nil -> style previews in identity cyan, color previews as Classic.
function SoulStyles.buildPreview(item, px, ctx)
	ctx = ctx or {}
	local styleKey, colorSpec
	if item.kind == "halo_color" then
		local fillRgb = item.fill
		local lumRgb = ShopCatalog.luminousOf(item)
		colorSpec = {
			fill = Color3.fromRGB(fillRgb.r, fillRgb.g, fillRgb.b),
			luminous = Color3.fromRGB(lumRgb.r, lumRgb.g, lumRgb.b),
			fillRgb = fillRgb,
			luminousRgb = lumRgb,
			anim = item.anim,
		}
		styleKey = ctx.styleKey or "classic"
	elseif item.kind == "halo_style" then
		styleKey = item.styleKey
		colorSpec = ctx.colorSpec or { fill = IDENTITY, luminous = IDENTITY }
	else
		styleKey = "classic"
		colorSpec = { fill = IDENTITY, luminous = IDENTITY }
	end

	local state = makeState(colorSpec, px)
	local root = makeRoot(nil, UDim2.fromOffset(px, px))
	local built = construct(root, styleKey, state)

	if #built.ticks > 0 then
		local handle = { gui = root, _dead = false, _seen = false }
		handle._animate = function(now)
			for i = 1, #built.ticks do
				built.ticks[i](now)
			end
		end
		registerHandle(handle)
	end
	return root
end

return SoulStyles
