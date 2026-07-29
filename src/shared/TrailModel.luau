--[[
	TrailModel -- the PURE, single description of every Soul trail, consumed by BOTH the
	world renderer (SoulController.buildTrail) and the shop card preview (ClientShopHud).

	WHY THIS EXISTS. The two were previously written independently and drifted badly: the
	world drew Roblox `Trail` ribbons per an if-chain, while the shop drew three static
	rarity-tinted bars. Soul Stream and Sparkline came out PIXEL-IDENTICAL on their cards
	-- two different 900-coin items a player could not tell apart -- and every card was
	tinted by rarity rather than by the soul colour the trail actually wears.

	THE CARD IS NOW DERIVED FROM THE BODY. `world` is the ONLY hand-authored description;
	the preview's thickness, shoulder offsets, length, taper, bead pattern and fade are all
	computed from it (see `previewStrands`). There are no parallel preview numbers left to
	drift out of sync -- if you retune a ribbon, its card follows automatically. Both sides
	also share one flow ring and one transparency ramp, so "what you see is what you get"
	is structural rather than a matter of keeping two tables in agreement.

	Plain data + pure functions, no Roblox types (lune-testable). Colours are expressed as
	a `tint` in 0..1 = how far to lerp the wearer's luminous colour toward white; the
	renderers own the Color3 maths.

	SHAPE: `world` is one entry per Roblox `Trail` instance on the body.
	  spread     -- attachment separation in studs (the ribbon's width at the body)
	  x          -- lateral attachment offset in studs (shoulder wakes)
	  lifetime   -- seconds a segment persists (the wake's LENGTH)
	  headAlpha  -- transparency at the body; the far end is always 1 (gone)
	  widthTail  -- WidthScale at the tail; 0 tapers the ribbon to a POINT (the single
	                biggest quality win -- untapered trails render as blunt rectangles)
	  beads      -- >0 adds that many WidthScale humps, the "beaded dash" signature
	  shimmer    -- phase offset in 0..1 for the alternating twin-wake pulse (meteor)
	Location (Roblox): ReplicatedStorage/Shared/TrailModel  (ModuleScript)
--]]

local TrailModel = {}

-- Ordered so callers (and tests) iterate deterministically; matches ShopCatalog rarity order.
TrailModel.keys = { "wisp", "stream", "sparkline", "comet", "meteor" }

TrailModel.profiles = {
	-- Uncommon -- "thin whisper, quick fade" (spec §7). One narrow ribbon, short life.
	wisp = {
		behaviour = "Thin whisper",
		world = {
			{ spread = 0.38, x = 0, lifetime = 0.55, headAlpha = 0.26, widthTail = 0, tint = 0.12 },
		},
	},

	-- Rare -- "wide silk ribbon". The long, smooth, generous one; reads as a banner.
	stream = {
		behaviour = "Wide silk ribbon",
		world = {
			{ spread = 1.55, x = 0, lifetime = 0.90, headAlpha = 0.14, widthTail = 0.05, tint = 0 },
		},
	},

	-- Rare -- "beaded dashes (WidthScale humps)". MUST be unmistakable against `stream`:
	-- same price, same tier, so the bead pattern is the whole read. Humped hard enough to
	-- break the ribbon into visible beads rather than the old barely-visible pinch.
	sparkline = {
		behaviour = "Beaded dashes",
		world = {
			-- Wider and with FEWER, longer beads than the first pass: at 0.85 spread with 4
			-- humps each bead was too small to register at world scale.
			{ spread = 1.15, x = 0, lifetime = 0.65, headAlpha = 0.20, widthTail = 0, beads = 3, tint = 0.30 },
		},
	},

	-- Epic -- "white-hot core + soft colour sheath (2 trails)". Two concentric ribbons;
	-- the sheath is listed first so the hot core renders on top of it on both sides.
	comet = {
		behaviour = "White-hot core",
		world = {
			{ spread = 1.95, x = 0, lifetime = 1.05, headAlpha = 0.50, widthTail = 0, tint = 0 },
			{ spread = 0.32, x = 0, lifetime = 1.05, headAlpha = 0.00, widthTail = 0, tint = 0.60 },
		},
	},

	-- Legendary -- "twin shoulder streams, alternating pulse". Twin wakes plus a hot
	-- centre core (the third strand is new: the legendary needs to out-read Comet, which
	-- already has two). `shimmer` phases the two shoulders against each other.
	meteor = {
		behaviour = "Twin shoulder streams",
		world = {
			{ spread = 0.55, x = -0.78, lifetime = 1.25, headAlpha = 0.22, widthTail = 0, tint = 0.05, shimmer = 0.0 },
			{ spread = 0.55, x = 0.78, lifetime = 1.25, headAlpha = 0.22, widthTail = 0, tint = 0.05, shimmer = 0.5 },
			{ spread = 0.30, x = 0, lifetime = 1.00, headAlpha = 0.05, widthTail = 0, tint = 0.50 },
		},
	},
}

function TrailModel.profileOf(trailKey)
	return TrailModel.profiles[trailKey]
end

-- Catalog-wide maxima, computed once, so the card can express a ribbon's size RELATIVE to
-- the widest/longest trail in the shop rather than via a second set of tuned numbers.
local MAX_SPREAD, MAX_LIFETIME, MAX_X = 0, 0, 0
for _, key in ipairs(TrailModel.keys) do
	for _, s in ipairs(TrailModel.profiles[key].world) do
		MAX_SPREAD = math.max(MAX_SPREAD, s.spread)
		MAX_LIFETIME = math.max(MAX_LIFETIME, s.lifetime)
		MAX_X = math.max(MAX_X, math.abs(s.x or 0))
	end
end
TrailModel.MAX_SPREAD, TrailModel.MAX_LIFETIME = MAX_SPREAD, MAX_LIFETIME

-- How the world's studs map into the card's box. Chosen once, here, so a retuned ribbon
-- moves its card automatically. THICK_SPAN + OFFSET_SPAN are bounded so the widest strand
-- and the furthest shoulder both still fit inside the box (asserted by previewExtent).
local THICK_SPAN = 0.86  -- widest ribbon -> 86% of the preview box HEIGHT
local OFFSET_SPAN = 0.21 -- furthest shoulder -> 21% of the box height off the centreline
local LEN_SPAN = 0.80    -- longest-lived wake -> 80% of the preview box WIDTH
local FLOW_PER_LIFETIME = 1.4 -- one light pulse crosses the wake in lifetime * this

-- The flow ring: a narrow bright band on an otherwise soul-coloured ribbon, expressed as
-- how far to lerp the wearer's colour toward WHITE at each of four evenly-spaced stops.
-- BOTH renderers scroll this same ring (via SoulAnimModel.scrollStops), so the light that
-- streams down a card is the light that streams down the equipped ribbon.
TrailModel.FLOW_RING = { 0, 0, 0.5, 0 }

-- Seconds for one pulse to travel the wake. Derived, so a short-lived wisp flickers
-- quickly and a long meteor wake rolls slowly -- matching how each reads in the world.
function TrailModel.flowSeconds(trailKey)
	local profile = TrailModel.profiles[trailKey]
	if not profile then
		return 1
	end
	local longest = 0
	for _, s in ipairs(profile.world) do
		longest = math.max(longest, s.lifetime)
	end
	return longest * FLOW_PER_LIFETIME
end

-- Bead envelope: `n` humps across the wake, dipping to 0.14 between them so the ribbon
-- visibly breaks instead of merely narrowing. Continuous in u (no popping).
local function beadFactor(u, n)
	if not n or n <= 0 then
		return 1
	end
	return 0.14 + 0.86 * (0.5 + 0.5 * math.cos(u * 2 * math.pi * n))
end

-- The WidthScale keypoints for a strand: head at full width, tapering to `widthTail`,
-- with bead humps applied when the strand declares them. `at` strictly increases 0 -> 1
-- (Roblox NumberSequence contract). Drives the world ribbon's WidthScale AND, sampled
-- below, the card's fade -- so the card's silhouette IS the ribbon's silhouette.
function TrailModel.widthKeypoints(strand)
	local tail = strand.widthTail or 0
	local n = strand.beads
	local steps = (n and n > 0) and 12 or 2
	local kps = {}
	for i = 0, steps do
		local u = i / steps
		local base = 1 + (tail - 1) * u
		kps[#kps + 1] = { at = u, scale = math.max(0, math.min(1, base * beadFactor(u, n))) }
	end
	return kps
end

-- The ribbon's transparency ramp along its length: `headAlpha` at the body, easing to
-- fully gone at the tail with a knee at 0.55 so the wake holds its body before dissolving.
-- ONE definition, used by the world Trail directly and sampled by the card.
local KNEE = 0.55
local function alphaAt(strand, u)
	local head = strand.headAlpha
	local mid = math.min(1, head + (1 - head) * 0.45)
	if u <= KNEE then
		return head + (mid - head) * (u / KNEE)
	end
	return mid + (1 - mid) * ((u - KNEE) / (1 - KNEE))
end

function TrailModel.transparencyKeypoints(strand)
	return {
		{ at = 0, transparency = strand.headAlpha },
		{ at = KNEE, transparency = alphaAt(strand, KNEE) },
		{ at = 1, transparency = 1 },
	}
end

-- How far a strand sits from the wake's CENTRELINE (its shoulder offset plus its own
-- half-thickness), in fractions of the preview box HEIGHT. Must stay under 0.5 or the
-- wake spills out of its box and collides with the card's tier chip.
function TrailModel.previewExtent(trailKey)
	local worst = 0
	for _, st in ipairs(TrailModel.previewStrands(trailKey)) do
		worst = math.max(worst, math.abs(st.offset) + st.thick * 0.5)
	end
	return worst
end

-- Wake length as a fraction of the preview box WIDTH, from the longest-lived strand.
function TrailModel.previewWakeLen(trailKey)
	local profile = TrailModel.profiles[trailKey]
	if not profile then
		return 0
	end
	local longest = 0
	for _, s in ipairs(profile.world) do
		longest = math.max(longest, s.lifetime)
	end
	return longest / MAX_LIFETIME * LEN_SPAN
end

-- Each strand is drawn as a few LONGITUDINAL bars stacked head-aligned, rather than as
-- transverse slices: slicing a thick wake across its length ribs it into a corrugated
-- block, because neighbouring semi-transparent slices stack unevenly (tried, rejected in
-- an in-game pass). Bars of decreasing length and increasing thickness, all anchored at
-- the head, give the taper; one gradient per bar gives the fade.
local PREVIEW_BARS = {
	{ len = 1.00, thick = 0.32 },
	{ len = 0.62, thick = 0.68 },
	{ len = 0.30, thick = 1.00 },
}

-- The card wake, DERIVED from the world ribbon -- one strand in, one strand out:
--   bars   -- { { len, thick } }: fractions of the wake length and of this strand's thickness
--   thick  -- thickness as a fraction of the preview box HEIGHT, from the ribbon's `spread`
--   offset -- perpendicular offset in box-height units, from the ribbon's shoulder `x`
--   len    -- this strand's own length fraction, from its `lifetime`
--   tint   -- 0..1 lerp of the wearer's luminous colour toward white
--   fade   -- { { at, transparency } }, `at` in GRADIENT space (0 = tail, 1 = head) and
--             strictly increasing. It is the ribbon's OWN WidthScale x its OWN transparency
--             ramp, so the taper and the bead humps on the card are the ones on the body.
function TrailModel.previewStrands(trailKey)
	local profile = TrailModel.profiles[trailKey]
	if not profile then
		return {}
	end
	local wakeLen = TrailModel.previewWakeLen(trailKey)
	local out = {}
	for _, s in ipairs(profile.world) do
		local width = TrailModel.widthKeypoints(s)
		local fade = {}
		for i = #width, 1, -1 do -- descending u so `at` (= 1 - u) ascends
			local u = width[i].at
			local t = 1 - width[i].scale * (1 - alphaAt(s, u))
			fade[#fade + 1] = { at = 1 - u, transparency = math.max(0, math.min(1, t)) }
		end
		out[#out + 1] = {
			bars = PREVIEW_BARS,
			thick = s.spread / MAX_SPREAD * THICK_SPAN,
			offset = (MAX_X > 0 and (s.x or 0) / MAX_X or 0) * OFFSET_SPAN,
			len = (s.lifetime / MAX_LIFETIME * LEN_SPAN) / math.max(1e-6, wakeLen),
			tint = s.tint or 0,
			fade = fade,
		}
	end
	return out
end

return TrailModel
