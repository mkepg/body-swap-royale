local TrailModel = require("../src/shared/TrailModel")
local ShopCatalog = require("../src/shared/ShopCatalog")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

-- Every catalog trail has a profile, and every profile is reachable from the catalog.
do
	local catalogKeys, n = {}, 0
	for _, it in ipairs(ShopCatalog.items) do
		if it.kind == "trail" then
			n += 1
			expect(it.trailKey ~= nil, it.id .. " declares a trailKey")
			catalogKeys[it.trailKey] = true
			expect(TrailModel.profileOf(it.trailKey) ~= nil, "TrailModel covers " .. it.trailKey)
		end
	end
	expect(n == 5, "catalog still has 5 trails (got " .. n .. ")")
	for _, key in ipairs(TrailModel.keys) do
		expect(catalogKeys[key], "TrailModel key " .. key .. " is reachable from the catalog")
		expect(TrailModel.profileOf(key) ~= nil, "TrailModel.keys entry " .. key .. " has a profile")
	end
	expect(#TrailModel.keys == 5, "TrailModel.keys lists all 5")
	print("trail: catalog coverage OK")
end

-- World strands: sane, renderable, and tapered (an untapered trail draws as a blunt
-- rectangle -- the "bland" this redesign exists to fix).
do
	for _, key in ipairs(TrailModel.keys) do
		local p = TrailModel.profileOf(key)
		expect(#p.world >= 1, key .. " has at least one world strand")
		expect(type(p.behaviour) == "string" and #p.behaviour > 0, key .. " has a behaviour descriptor")
		for i, s in ipairs(p.world) do
			local where = key .. " strand " .. i
			expect(s.spread > 0, where .. " has positive spread")
			expect(s.lifetime > 0 and s.lifetime <= 2, where .. " lifetime in (0, 2]")
			expect(s.headAlpha >= 0 and s.headAlpha < 1, where .. " headAlpha in [0,1)")
			expect((s.widthTail or 0) <= 0.25, where .. " tapers (widthTail <= 0.25)")
			expect((s.tint or 0) >= 0 and (s.tint or 0) <= 1, where .. " tint in [0,1]")
		end
	end
	-- descriptors are the belt-and-braces disambiguation on the card; they must be unique
	local seen = {}
	for _, key in ipairs(TrailModel.keys) do
		local b = TrailModel.profileOf(key).behaviour
		expect(not seen[b], "behaviour descriptor '" .. b .. "' is reused")
		seen[b] = true
	end
	print("trail: world strand contract OK")
end

-- WidthScale keypoints must satisfy Roblox's NumberSequence contract.
do
	for _, key in ipairs(TrailModel.keys) do
		for i, s in ipairs(TrailModel.profileOf(key).world) do
			local kps = TrailModel.widthKeypoints(s)
			local where = key .. " strand " .. i
			expect(#kps >= 2 and #kps <= 20, where .. " keypoint count in [2,20] (got " .. #kps .. ")")
			expect(kps[1].at == 0, where .. " starts at 0")
			expect(kps[#kps].at == 1, where .. " ends at 1")
			for j = 2, #kps do
				expect(kps[j].at > kps[j - 1].at, where .. " times strictly increase")
			end
			for _, k in ipairs(kps) do
				expect(k.scale >= 0 and k.scale <= 1, where .. " scale in [0,1]")
			end
		end
	end
	print("trail: widthKeypoints contract OK")
end

-- Beads actually bead, in the world ribbon AND on the card. The shipped pinch was far too
-- subtle to read, which is half of why Sparkline was mistaken for Soul Stream.
do
	local spark = TrailModel.profileOf("sparkline").world[1]
	expect(spark.beads and spark.beads > 0, "sparkline declares beads")
	local lo = 1
	for _, k in ipairs(TrailModel.widthKeypoints(spark)) do lo = math.min(lo, k.scale) end
	expect(lo < 0.2, "sparkline width dips below 0.2 somewhere (got " .. lo .. ")")

	local stream = TrailModel.profileOf("stream").world[1]
	expect(not stream.beads, "stream is smooth, not beaded")

	-- On the card the beads live in the fade gradient: it must swing back and forth, where
	-- a smooth strand's fade only ever rises from head to tail.
	local function reversals(key)
		local f = TrailModel.previewStrands(key)[1].fade
		local n, rising = 0, nil
		for i = 2, #f do
			local up = f[i].transparency > f[i - 1].transparency + 1e-6
			local down = f[i].transparency < f[i - 1].transparency - 1e-6
			if up or down then
				if rising ~= nil and up ~= rising then n += 1 end
				rising = up
			end
		end
		return n
	end
	expect(reversals("sparkline") >= 4, "sparkline's beads read on the card (reversals=" .. reversals("sparkline") .. ")")
	expect(reversals("stream") == 0, "stream fades monotonically on the card")
	print("trail: bead signature OK")
end

-- Preview strands: renderable bar stack + a legal, strictly-increasing fade gradient.
do
	for _, key in ipairs(TrailModel.keys) do
		local strands = TrailModel.previewStrands(key)
		expect(#strands >= 1, key .. " previews at least one strand")
		for si, st in ipairs(strands) do
			local where = key .. " strand " .. si
			expect(#st.bars >= 2 and #st.bars <= 6, where .. " has a small bar stack")
			expect(st.thick > 0 and st.thick < 1, where .. " thickness in (0,1)")
			expect(st.len > 0 and st.len <= 1, where .. " length fraction in (0,1]")
			expect(st.tint >= 0 and st.tint <= 1, where .. " tint in [0,1]")
			-- the stack must taper: longer bars are thinner, the shortest is the fat head
			for bi = 2, #st.bars do
				expect(st.bars[bi].len < st.bars[bi - 1].len, where .. " bar lengths decrease")
				expect(st.bars[bi].thick > st.bars[bi - 1].thick, where .. " bar thickness increases")
			end
			expect(st.bars[1].len == 1, where .. " the longest bar spans the whole wake")
			expect(st.bars[#st.bars].thick == 1, where .. " the fattest bar is full thickness")
			-- Roblox NumberSequence contract on the fade gradient
			expect(#st.fade >= 2 and #st.fade <= 20, where .. " fade keypoints in [2,20] (got " .. #st.fade .. ")")
			expect(st.fade[1].at == 0, where .. " fade starts at gradient 0 (tail)")
			expect(st.fade[#st.fade].at == 1, where .. " fade ends at gradient 1 (head)")
			for i = 2, #st.fade do
				expect(st.fade[i].at > st.fade[i - 1].at, where .. " fade times strictly increase")
			end
			for _, f in ipairs(st.fade) do
				expect(f.transparency >= 0 and f.transparency <= 1, where .. " fade in [0,1]")
			end
			expect(st.fade[1].transparency > 0.99, where .. " tail fully dissolves")
			expect(st.fade[#st.fade].transparency < 0.9, where .. " head is visible")
		end
	end
	print("trail: preview strand contract OK")
end

-- The wake must fit inside its preview box vertically. On an earlier pass it spilled out
-- and ran under the card's tier chip, so this is machine-guarded rather than eyeballed.
do
	for _, key in ipairs(TrailModel.keys) do
		local e = TrailModel.previewExtent(key)
		expect(e > 0.08, key .. " preview wake is thick enough to read (extent=" .. e .. ")")
		expect(e < 0.5, key .. " preview wake stays inside its box (extent=" .. e .. ")")
	end
	print("trail: preview fits its box OK")
end

-- PARITY: the card must be derived from the body, not tuned alongside it. A strand that
-- is wider / longer / further out in the world must be wider / longer / further out on
-- the card, and the card's fade must be the ribbon's own WidthScale x its own
-- transparency ramp. This is what makes "what you see is what you get" structural.
do
	for _, key in ipairs(TrailModel.keys) do
		local world = TrailModel.profileOf(key).world
		local card = TrailModel.previewStrands(key)
		expect(#card == #world, key .. " previews exactly one strand per world ribbon")
		for i = 1, #world do
			local w, c = world[i], card[i]
			local where = key .. " strand " .. i
			expect(c.tint == (w.tint or 0), where .. " carries the ribbon's tint")
			-- shoulder direction must survive (meteor's left wake stays on the left)
			local wx, cx = w.x or 0, c.offset
			expect((wx > 0) == (cx > 0) and (wx < 0) == (cx < 0), where .. " keeps its shoulder side")
			-- the card fade must start fully gone and end visible, mirroring the ribbon
			expect(math.abs(c.fade[#c.fade].transparency - w.headAlpha) < 1e-9,
				where .. " head opacity equals the ribbon's headAlpha")
		end
		-- ordering: a wider world ribbon is a thicker card ribbon
		for i = 2, #world do
			if world[i].spread > world[i - 1].spread then
				expect(card[i].thick > card[i - 1].thick, key .. " thicker ribbon -> thicker card strand")
			elseif world[i].spread < world[i - 1].spread then
				expect(card[i].thick < card[i - 1].thick, key .. " thinner ribbon -> thinner card strand")
			end
		end
	end
	-- across trails: the longest-lived wake owns the longest card wake
	local longest, longestKey = 0, nil
	for _, key in ipairs(TrailModel.keys) do
		for _, w in ipairs(TrailModel.profileOf(key).world) do
			if w.lifetime > longest then longest, longestKey = w.lifetime, key end
		end
	end
	for _, key in ipairs(TrailModel.keys) do
		expect(TrailModel.previewWakeLen(key) <= TrailModel.previewWakeLen(longestKey) + 1e-9,
			longestKey .. " should own the longest card wake, not " .. key)
	end
	print("trail: card is derived from the body OK")
end

-- Both sides scroll ONE shared flow ring at ONE derived rate, so the light on the card is
-- the light on the equipped ribbon.
do
	expect(#TrailModel.FLOW_RING >= 2, "flow ring has enough stops to scroll")
	local bright, dim = 0, 0
	for _, lift in ipairs(TrailModel.FLOW_RING) do
		expect(lift >= 0 and lift <= 1, "flow ring lifts are in [0,1]")
		if lift > 0 then bright += 1 else dim += 1 end
	end
	expect(bright >= 1 and dim >= 2, "the ring is a NARROW band, not a two-tone wipe")
	for _, key in ipairs(TrailModel.keys) do
		local f = TrailModel.flowSeconds(key)
		expect(f > 0.3 and f < 4, key .. " flow rate is legible (got " .. f .. "s)")
	end
	-- a shorter-lived wake flickers faster than a long one
	expect(TrailModel.flowSeconds("wisp") < TrailModel.flowSeconds("meteor"),
		"wisp flows faster than meteor")
	print("trail: shared flow ring OK")
end

-- THE REGRESSION THIS MODULE EXISTS FOR: Soul Stream and Sparkline are both Rare and both
-- 900 coins, and their old cards were pixel-identical rarity-tinted bars. No two trails
-- may ever produce the same preview again.
do
	local function signature(key)
		local parts = {}
		for si, st in ipairs(TrailModel.previewStrands(key)) do
			parts[#parts + 1] = ("s%d:%.3f:%.3f:%.3f:%.3f"):format(si, st.thick, st.offset, st.tint, st.len)
			for _, f in ipairs(st.fade) do
				parts[#parts + 1] = ("%.3f=%.3f"):format(f.at, f.transparency)
			end
		end
		parts[#parts + 1] = ("len%.3f/flow%.3f"):format(TrailModel.previewWakeLen(key), TrailModel.flowSeconds(key))
		return table.concat(parts, "|")
	end
	local seen = {}
	for _, key in ipairs(TrailModel.keys) do
		local sig = signature(key)
		for other, otherSig in pairs(seen) do
			expect(sig ~= otherSig, key .. " previews IDENTICALLY to " .. other .. " -- ambiguous card")
		end
		seen[key] = sig
	end
	-- and specifically the pair that shipped broken
	expect(signature("stream") ~= signature("sparkline"), "stream and sparkline preview differently")
	-- strand COUNT alone must separate the top two tiers from the rest
	expect(#TrailModel.previewStrands("comet") == 2, "comet previews 2 strands")
	expect(#TrailModel.previewStrands("meteor") == 3, "meteor previews 3 strands")
	expect(#TrailModel.previewStrands("wisp") == 1, "wisp previews 1 strand")
	print("trail: previews are pairwise distinct OK")
end

-- Rarity should read as escalation: the wake gets longer and gains strands.
do
	local function len(key) return TrailModel.previewWakeLen(key) end
	local function strands(key) return #TrailModel.previewStrands(key) end
	expect(len("wisp") < len("stream"), "wisp is shorter than stream")
	expect(strands("comet") > strands("wisp"), "comet out-reads wisp")
	expect(strands("meteor") > strands("comet"), "meteor out-reads comet")
	expect(len("meteor") >= len("comet"), "meteor's wake is at least as long as comet's")
	print("trail: rarity escalation OK")
end

print("ALL trail_model tests passed")
