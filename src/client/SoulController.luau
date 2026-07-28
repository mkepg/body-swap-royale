--[[
	SoulController -- the free Soul identity halo.
	Location: StarterPlayerScripts/Client/SoulController  (ModuleScript)

	Renders a colored halo above every controlled body from the SoulMap broadcast
	(color = whoever currently controls that body), so you can recognize players
	across swaps. THIS client's own controlled body (from SetControlledBody) gets
	an oversized halo (42px vs 24px) so "which one is me?" is unmistakable after
	the camera cut -- the size difference is the sole me-cue (the emphasis stroke
	was removed; it read as an artifact on some style x color combos).
	Also plays the brief post-swap grace shield shimmer on the body you inherit.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local TrailModel = require(Shared:WaitForChild("TrailModel"))
local SoulAnimModel = require(Shared:WaitForChild("SoulAnimModel"))
local SoulStyles = require(script.Parent:WaitForChild("SoulStyles"))
local SoulMap = Remotes.get("SoulMap")
local SetControlledBody = Remotes.get("SetControlledBody")

local SoulController = {}
local myBody = nil
local halos = {} -- [body] = { handle, gui, styleKey, colorId, isMine }
local trails = {} -- [body] = { trailKey, lumColor, trails, attachments, animHandle? }
local localPlayer = game:GetService("Players").LocalPlayer
local myUserId = localPlayer.UserId

local SIZE_MINE = 42
local SIZE_OTHER = 24

local function rgbFromColor3(c)
	return { r = c.R * 255, g = c.G * 255, b = c.B * 255 }
end

local function makeBillboard(head, sizePx)
	local halo = Instance.new("BillboardGui")
	halo.Name = "SoulHalo"
	halo.Size = UDim2.fromOffset(sizePx, sizePx)
	halo.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	halo.AlwaysOnTop = true
	halo.Adornee = head
	halo.Parent = head
	return halo
end

-- Resolve the style FRAME key from the equipped style item id (nil/unknown -> classic).
local function styleKeyFor(styleId)
	if not styleId then
		return "classic"
	end
	local item = ShopCatalog.byId(styleId)
	return (item and item.styleKey) or "classic"
end

-- Resolve the trail SHAPE key from the equipped trail item id (nil -> no trail).
local function trailKeyFor(trailId)
	if not trailId then
		return nil
	end
	local item = ShopCatalog.byId(trailId)
	return item and item.trailKey or nil
end

-- Build the pre-resolved color spec SoulStyles consumes: a premium color item drives
-- fill/luminous/anim; otherwise the server's resolved identity color is used flat.
local function colorSpecFor(entry)
	local colorItem = entry.colorId and ShopCatalog.byId(entry.colorId) or nil
	if colorItem and colorItem.kind ~= "halo_color" then
		colorItem = nil
	end
	if colorItem then
		local fillRgb = colorItem.fill
		local lumRgb = ShopCatalog.luminousOf(colorItem)
		return {
			fill = Color3.fromRGB(fillRgb.r, fillRgb.g, fillRgb.b),
			luminous = Color3.fromRGB(lumRgb.r, lumRgb.g, lumRgb.b),
			fillRgb = fillRgb,
			luminousRgb = lumRgb,
			anim = colorItem.anim,
		}
	end
	local fillRgb = rgbFromColor3(entry.color)
	return {
		fill = entry.color,
		luminous = entry.color,
		fillRgb = fillRgb,
		luminousRgb = fillRgb,
		anim = nil,
	}
end

-- A brief shield shimmer on the body you control, driven by the SERVER's authoritative
-- grace gate (the GraceProtected body attribute), not a local guess. It shows while the
-- attribute is true and ends the instant the server clears it, so the shield never
-- outlives real protection (no dying inside a visible shield). Cosmetic only.
local shimmerToken = nil
local graceConn = nil
local watchedBody = nil

local function stopShimmer(body)
	shimmerToken = nil
	if body then
		local hl = body:FindFirstChild("GraceShimmer")
		if hl then
			hl:Destroy()
		end
	end
end

local function startShimmer(body)
	if not (body and body.Parent) then
		return
	end
	if body:FindFirstChild("GraceShimmer") then
		return -- already shimmering
	end
	local token = {}
	shimmerToken = token

	local hl = Instance.new("Highlight")
	hl.Name = "GraceShimmer"
	hl.FillColor = Color3.fromRGB(120, 200, 255)
	hl.OutlineColor = Color3.fromRGB(200, 240, 255)
	hl.FillTransparency = 0.6
	hl.Adornee = body
	hl.Parent = body

	local start = os.clock()
	task.spawn(function()
		-- `hl.Parent` guard: if the body is destroyed mid-shimmer (owner disconnects),
		-- hl is destroyed with it; stop before writing to the locked instance.
		while shimmerToken == token and hl.Parent do
			hl.FillTransparency = 0.5 + 0.3 * math.sin((os.clock() - start) * 8) -- pulse
			task.wait()
		end
	end)
end

-- Bind the shimmer to `body`'s authoritative GraceProtected attribute: show while true,
-- hide when false/absent, and re-evaluate whenever it changes. Rebound on every swap.
local function watchGrace(body)
	if graceConn then
		graceConn:Disconnect()
		graceConn = nil
	end
	-- Clear the shimmer on the PREVIOUS body (client-local highlight nothing else
	-- removes) before rebinding, so a swap doesn't leave a stale shield on the body
	-- you no longer control.
	if watchedBody then
		stopShimmer(watchedBody)
	end
	watchedBody = body
	if not (body and body.Parent) then
		return
	end
	local function refresh()
		if body:GetAttribute("GraceProtected") then
			startShimmer(body)
		else
			stopShimmer(body)
		end
	end
	graceConn = body:GetAttributeChangedSignal("GraceProtected"):Connect(refresh)
	refresh() -- catch the case where the attribute is already true
end

-- Backstop for a missed/dropped SetControlledBody: if `myBody` is stale (nil,
-- destroyed, or no longer authoritatively ours), re-derive it from the SoulMap
-- broadcast's ControllerUserId attributes -- the same broadcast that drives the
-- halos below, so this fires on every control change with no extra plumbing.
local function reconcileMyBody(list)
	if myBody and myBody.Parent and myBody:GetAttribute("ControllerUserId") == myUserId then
		return
	end
	for _, entry in ipairs(list) do
		local body = entry.body
		if body and body.Parent and body:GetAttribute("ControllerUserId") == myUserId then
			myBody = body
			watchGrace(myBody)
			return
		end
	end
end

-- ===== Soul trails ======================================================
-- Trails ride the body's UpperTorso (fallback HumanoidRootPart) via attachment
-- pairs; each trail key is a different soul-wake shape. Color = wearer's luminous.
local function trailAttachRoot(body)
	return body:FindFirstChild("UpperTorso") or body:FindFirstChild("HumanoidRootPart")
end

local function destroyTrail(trec)
	if trec.animHandle then
		trec.animHandle._dead = true -- drop from the SoulStyles animator
	end
	for _, t in ipairs(trec.trails) do
		t:Destroy()
	end
	for _, a in ipairs(trec.attachments) do
		a:Destroy()
	end
end

-- A trail teleports with its body. Bodies are re-placed on round start (and swaps hand
-- control between distant bodies), which without a cap draws one enormous streak across
-- the arena for a full Lifetime. Cap the ribbon at a plausible sprint distance.
local TRAIL_MAX_LENGTH = 26
local WHITE = Color3.new(1, 1, 1)

-- The shared flow ring (TrailModel.FLOW_RING) resolved against a wearer colour, as the
-- {r,g,b} tables SoulAnimModel.scrollStops consumes. The shop card builds the identical
-- ring from the identical constant, so the light streaming down a card is the light
-- streaming down the equipped ribbon.
local function flowRing(base)
	local ring = {}
	for i, lift in ipairs(TrailModel.FLOW_RING) do
		local c = base:Lerp(WHITE, lift)
		ring[i] = { r = c.R * 255, g = c.G * 255, b = c.B * 255 }
	end
	return ring
end

-- Build every Roblox Trail for `trailKey` from the shared TrailModel description -- the
-- SAME description the shop card previews render, so the card and the body can no longer
-- drift apart (they did: the cards used to be static rarity-tinted bars).
local function buildTrail(body, trailKey, lumColor)
	local part = trailAttachRoot(body)
	if not part then
		return nil
	end
	local profile = TrailModel.profileOf(trailKey)
	if not profile then
		return nil -- unknown key (catalog/renderer drift) -> no trail, never an error
	end
	local trec = { trailKey = trailKey, lumColor = lumColor, trails = {}, attachments = {}, shimmer = {}, flow = {} }

	for _, s in ipairs(profile.world) do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(s.x or 0, s.spread / 2, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(s.x or 0, -s.spread / 2, 0)
		a1.Parent = part
		trec.attachments[#trec.attachments + 1] = a0
		trec.attachments[#trec.attachments + 1] = a1

		local base = lumColor:Lerp(Color3.new(1, 1, 1), s.tint or 0)
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.FaceCamera = true
		t.Lifetime = s.lifetime
		t.MinLength = 0 -- draw even on small movements, so idle drift still wisps
		t.MaxLength = TRAIL_MAX_LENGTH
		-- LightEmission is an ADDITIVE blend factor: pushed too high the ribbon blows out
		-- to pure white and the wearer's soul colour -- the whole point of a trail here --
		-- disappears. Verified in-game: 0.85 rendered every trail white on the dusk sky.
		-- 0.35 keeps the glow while the colour survives against both sky and shadow.
		t.LightEmission = 0.35
		t.LightInfluence = 0
		-- TAPER: the single biggest quality win. Untapered, every trail rendered as a
		-- blunt rectangle with a hard trailing edge. The bead humps ride this curve too.
		local kps = {}
		for i, k in ipairs(TrailModel.widthKeypoints(s)) do
			kps[i] = NumberSequenceKeypoint.new(k.at, k.scale)
		end
		t.WidthScale = NumberSequence.new(kps)
		local tk = {}
		for i, k in ipairs(TrailModel.transparencyKeypoints(s)) do
			tk[i] = NumberSequenceKeypoint.new(k.at, k.transparency)
		end
		t.Transparency = NumberSequence.new(tk)
		t.Color = ColorSequence.new(base) -- replaced every frame by the flow below
		t.Parent = part
		trec.trails[#trec.trails + 1] = t
		trec.flow[#trec.flow + 1] = { trail = t, ring = flowRing(base) }
		if s.shimmer then
			trec.shimmer[#trec.shimmer + 1] = { trail = t, phase = s.shimmer, headAlpha = s.headAlpha }
		end
	end

	-- ONE animator handle per wearer drives both effects:
	--  * FLOW -- light streaming down every ribbon, from the shared ring scrolled by the
	--    wrap-safe SoulAnimModel.scrollStops. This is what makes the equipped trail match
	--    its shop card: the card runs the same ring at the same rate. `Trail.Color` runs
	--    head(0) -> tail(1), the opposite of the card's gradient, so the phase is negated
	--    to keep the light travelling the same way (away from the body) on both.
	--  * SHIMMER -- Meteor's alternating twin-wake pulse, on a CONTINUOUS breathe rather
	--    than the old hard half-cycle swap, which flipped both wakes in a single frame.
	-- Cost: one ColorSequence per strand per frame per visible wearer (<= 3 each).
	local flowSeconds = TrailModel.flowSeconds(trailKey)
	if #trec.flow > 0 then
		trec.animHandle = SoulStyles.registerAnimated(trec.flow[1].trail, function(now)
			local p = (now % flowSeconds) / flowSeconds
			for _, fl in ipairs(trec.flow) do
				local kps = SoulAnimModel.scrollStops(fl.ring, -p)
				local out = table.create(#kps)
				for i = 1, #kps do
					out[i] = ColorSequenceKeypoint.new(kps[i].at, Color3.fromRGB(kps[i].r, kps[i].g, kps[i].b))
				end
				fl.trail.Color = ColorSequence.new(out)
			end
			for _, sh in ipairs(trec.shimmer) do
				local b = SoulAnimModel.breathe(now, 1.6, sh.phase)
				local head = math.min(1, sh.headAlpha + 0.45 * (1 - b))
				sh.trail.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, head),
					NumberSequenceKeypoint.new(0.55, math.min(1, head + (1 - head) * 0.45)),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		end)
	end
	return trec
end

-- ===== halo + trail reconcile ==========================================
local function updateHalo(body, entry, colorSpec, isMine)
	local head = body:FindFirstChild("Head") or body:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end
	local styleKey = styleKeyFor(entry.styleId)
	local rec = halos[body]
	-- Rebuild the billboard + handle only on a structural change (style/color item/
	-- mine/lost adornee); a mere resolved-color shift takes the cheap setColors path.
	local rebuild = (not rec)
		or rec.gui.Parent ~= head
		or rec.styleKey ~= styleKey
		or rec.colorId ~= entry.colorId
		or rec.isMine ~= isMine
	if rebuild then
		if rec then
			rec.handle.destroy()
			rec.gui:Destroy()
		end
		local sizePx = isMine and SIZE_MINE or SIZE_OTHER
		local gui = makeBillboard(head, sizePx)
		local handle = SoulStyles.build(gui, styleKey, colorSpec, sizePx, isMine)
		halos[body] = { handle = handle, gui = gui, styleKey = styleKey, colorId = entry.colorId, isMine = isMine }
	elseif entry.colorId == nil then
		-- Same item, but the server's assigned identity color may have changed.
		rec.handle.setColors(colorSpec.fill, colorSpec.luminous)
	end
end

local function updateTrail(body, entry, lumColor)
	local trailKey = trailKeyFor(entry.trailId)
	local trec = trails[body]
	if not trailKey then
		if trec then
			destroyTrail(trec)
			trails[body] = nil
		end
		return
	end
	-- Rebuild on shape OR color change (color changes are equip-only, so effectively rare).
	if not trec or trec.trailKey ~= trailKey or trec.lumColor ~= lumColor then
		if trec then
			destroyTrail(trec)
		end
		trails[body] = buildTrail(body, trailKey, lumColor)
	end
end

local function reconcile(list)
	reconcileMyBody(list)
	local seen = {}
	for _, entry in ipairs(list) do
		local body = entry.body
		if body and body.Parent then
			seen[body] = true
			local isMine = (body == myBody)
			local colorSpec = colorSpecFor(entry)
			updateHalo(body, entry, colorSpec, isMine)
			updateTrail(body, entry, colorSpec.luminous)
			-- Publish the local resolved soul color so other client UIs (the Soul Shop
			-- previews) can read it directly, without racing the one-shot SoulMap broadcast.
			if body:GetAttribute("ControllerUserId") == myUserId then
				if localPlayer:GetAttribute("SoulColor") ~= entry.color then
					localPlayer:SetAttribute("SoulColor", entry.color)
				end
			end
		end
	end
	-- Drop halos AND trails for bodies no longer in the map.
	for body, rec in pairs(halos) do
		if not seen[body] then
			rec.handle.destroy()
			rec.gui:Destroy()
			halos[body] = nil
		end
	end
	for body, trec in pairs(trails) do
		if not seen[body] then
			destroyTrail(trec)
			trails[body] = nil
		end
	end
end

function SoulController.start()
	SoulStyles.start() -- bind the shared halo animator (idempotent)
	if not Config.SOUL_HALO_ENABLED then
		return -- halos suppressed (e.g. clean marketing screenshots)
	end
	SoulMap.OnClientEvent:Connect(reconcile)

	SetControlledBody.OnClientEvent:Connect(function(body, _isSwap)
		myBody = body
		-- Resize immediately (don't wait for the next SoulMap broadcast): grow/shrink
		-- the billboard for the bodies whose mine-ness changed. The billboard SIZE is
		-- the sole "this is me" cue (mine 42px / others 24px) now that the emphasis ring
		-- is gone. `rec.isMine` is left STALE on purpose so the next SoulMap (always
		-- broadcast alongside SetControlledBody) does one authoritative rebuild that
		-- also re-sizes the style's px-based strokes.
		for b, rec in pairs(halos) do
			local desired = (b == myBody)
			if rec.isMine ~= desired then
				local px = desired and SIZE_MINE or SIZE_OTHER
				rec.gui.Size = UDim2.fromOffset(px, px)
			end
		end
		watchGrace(body)
	end)
end

return SoulController
