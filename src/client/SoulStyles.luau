--[[
	SoulStyles -- ONE construction + animation pipeline for every Soul halo, free
	Classic included (spec §6.1). Builders return handles parented into the halo
	BillboardGui; a single shared Heartbeat animator drives every animated element
	(rotation, ripple, color anims via SoulAnimModel). Per-frame budget: <= 16
	color writes + <= 3 property writes per visible halo (review §2.7 budget line).

	SoulStyles.build(parent, styleKey, colorSpec, sizePx, isMine) -> handle
	  parent: the BillboardGui to fill
	  styleKey: "classic"|"ring"|"pulse"|"orbit"|"eclipse"|"seraph" (unknown -> classic)
	  colorSpec: { fill = Color3, luminous = Color3, anim = table? } -- PRE-RESOLVED
	  handle: { setColors(fill, luminous), destroy() }
	SoulStyles.buildPreview(item, px) -> Frame  (same constructions for shop cards; Task 9 consumes)
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
	local under = circle(root, 1.20, state.luminous, 1)
	under.BackgroundTransparency = 0.72
	local annulus = circle(root, 1.0, state.fill, 2)
	annulus.BackgroundTransparency = 1
	local ann = makeStroke(annulus, px * 0.18, state.fill) -- 18% of billboard px
	local rim, rimStroke = makeFlashRim(root, state) -- flash colors (Stormcloud) pulse here

	ctx.fillTargets = { strokeTarget(ann) }
	ctx.gradientTarget = annulus -- a UIGradient here tints the annulus stroke
	ctx.rimStroke = rimStroke
	ctx.applyColors = function()
		under.BackgroundColor3 = state.luminous
		ann.Color = state.fill
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

	ticks[#ticks + 1] = function(now)
		local p = (now % 1.6) / 1.6 -- 1.6s loop
		local s = 0.80 + 0.72 * p -- 0.80 -> 1.52
		ripple.Size = UDim2.fromScale(s, s)
		rip.Transparency = 0.2 + 0.8 * p
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

	ticks[#ticks + 1] = function(now)
		carrier.Rotation = (now / 3 * 360) % 360 -- 360deg / 3s
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
	local glow = circle(root, 1.34, state.luminous, 0)
	glow.BackgroundTransparency = 0.82
	local disc = circle(root, 1.0, ECLIPSE_DISC, 1)
	local corona = makeStroke(disc, px * 0.14, state.luminous) -- 14% of billboard px

	-- The corona (luminous) is eclipse's only colored element, so the flat color
	-- anim rides it -- base = luminous so Void-type keeps its bright ring.
	ctx.fillTargets = { strokeTarget(corona) }
	ctx.baseKey = "luminousRgb"
	ctx.gradientTarget = disc -- gradient here tints the corona stroke
	ctx.rimStroke = corona
	ctx.applyColors = function()
		glow.BackgroundColor3 = state.luminous
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

	ticks[#ticks + 1] = function(now)
		local p = (now % 2.4) / 2.4 -- 2.4s ripple loop
		local s = 0.34 + 0.56 * p -- 0.34 -> 0.90 (subtle; stays within the ring)
		ripple.Size = UDim2.fromScale(s, s)
		rip.Transparency = 0.2 + 0.8 * p
		carrier.Rotation = (now / 6 * 360) % 360 -- 360deg / 6s
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

local function stopsToSequence(stops)
	local n = #stops
	local kps = {}
	for i, s in ipairs(stops) do
		local at = n > 1 and (i - 1) / (n - 1) or 0
		kps[i] = ColorSequenceKeypoint.new(at, Color3.fromRGB(s.r, s.g, s.b))
	end
	return ColorSequence.new(kps)
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

	elseif kind == "sweep" and ctx.gradientTarget then
		-- Whiten the fill element so the gradient shows true colors, not fill*grad.
		for i = 1, #ctx.fillTargets do
			ctx.fillTargets[i](WHITE)
		end
		local grad = Instance.new("UIGradient")
		grad.Rotation = 25
		local to = anim.to
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, state.fill),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(to.r, to.g, to.b)),
			ColorSequenceKeypoint.new(1, state.fill),
		})
		grad.Parent = ctx.gradientTarget
		ticks[#ticks + 1] = function(now)
			grad.Offset = Vector2.new(SoulAnimModel.phase(anim, now) * 2 - 1, 0)
		end

	elseif kind == "gradient" and ctx.gradientTarget then
		for i = 1, #ctx.fillTargets do
			ctx.fillTargets[i](WHITE)
		end
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90 -- vertical stops
		grad.Color = stopsToSequence(anim.stops)
		grad.Parent = ctx.gradientTarget
		ticks[#ticks + 1] = function(now)
			grad.Offset = Vector2.new(0, SoulAnimModel.phase(anim, now) * 2 - 1)
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

-- Shop-card preview: same constructions, no billboard. halo_color renders Classic
-- in that color; halo_style renders its frame in free identity cyan; anything else
-- (trails handled elsewhere) falls back to an identity Classic dot so this never errors.
function SoulStyles.buildPreview(item, px)
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
		styleKey = "classic"
	elseif item.kind == "halo_style" then
		styleKey = item.styleKey
		colorSpec = { fill = IDENTITY, luminous = IDENTITY }
	else
		styleKey = "classic"
		colorSpec = { fill = IDENTITY, luminous = IDENTITY }
	end

	local state = makeState(colorSpec, px)
	local root = makeRoot(nil, UDim2.fromOffset(px, px))
	local ctx = construct(root, styleKey, state)

	if #ctx.ticks > 0 then
		local handle = { gui = root, _dead = false, _seen = false }
		handle._animate = function(now)
			for i = 1, #ctx.ticks do
				ctx.ticks[i](now)
			end
		end
		registerHandle(handle)
	end
	return root
end

return SoulStyles
