--[[
	SoulController -- the free Soul identity halo.
	Location: StarterPlayerScripts/Client/SoulController  (ModuleScript)

	Renders a colored halo above every controlled body from the SoulMap broadcast
	(color = whoever currently controls that body), so you can recognize players
	across swaps. THIS client's own controlled body (from SetControlledBody) gets
	an emphasized halo so "which one is me?" is unmistakable after the camera cut.
	Also plays the brief post-swap grace shield shimmer on the body you inherit.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local SoulStyles = require(script.Parent:WaitForChild("SoulStyles"))
local SoulMap = Remotes.get("SoulMap")
local SetControlledBody = Remotes.get("SetControlledBody")

local SoulController = {}
local myBody = nil
local halos = {} -- [body] = { handle, gui, styleKey, colorId, isMine }
local trails = {} -- [body] = { trailKey, lumColor, trails, attachments, animHandle? }
local myUserId = game:GetService("Players").LocalPlayer.UserId

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

local function buildTrail(body, trailKey, lumColor)
	local part = trailAttachRoot(body)
	if not part then
		return nil
	end
	local trec = { trailKey = trailKey, lumColor = lumColor, trails = {}, attachments = {} }

	-- One trail on a fresh attachment pair (vertical spread; optional X shoulder offset).
	local function addTrail(spread, xOffset)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(xOffset or 0, spread / 2, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(xOffset or 0, -spread / 2, 0)
		a1.Parent = part
		trec.attachments[#trec.attachments + 1] = a0
		trec.attachments[#trec.attachments + 1] = a1
		local t = Instance.new("Trail")
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.FaceCamera = true
		t.LightEmission = 0.6
		t.Color = ColorSequence.new(lumColor)
		t.Parent = part
		trec.trails[#trec.trails + 1] = t
		return t
	end

	if trailKey == "wisp" then
		local t = addTrail(0.35)
		t.Lifetime = 0.45
		t.Transparency = NumberSequence.new(0.35, 1)
	elseif trailKey == "stream" then
		local t = addTrail(1.4)
		t.Lifetime = 0.8
		t.Transparency = NumberSequence.new(0.25, 1)
	elseif trailKey == "sparkline" then
		local t = addTrail(0.9)
		t.Lifetime = 0.6
		t.Transparency = NumberSequence.new(0.3, 1)
		t.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.15),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(0.75, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
	elseif trailKey == "comet" then
		local core = addTrail(0.35)
		core.Lifetime = 1.0
		core.Color = ColorSequence.new(lumColor:Lerp(Color3.new(1, 1, 1), 0.75)) -- hot white-ish core
		local sheath = addTrail(1.8)
		sheath.Lifetime = 1.0
		sheath.Transparency = NumberSequence.new(0.55, 1)
	elseif trailKey == "meteor" then
		local tA = addTrail(0.55, -0.8) -- twin wakes offset to the shoulders
		local tB = addTrail(0.55, 0.8)
		tA.Lifetime = 1.2
		tB.Lifetime = 1.2
		tA.Transparency = NumberSequence.new(0.25, 1)
		tB.Transparency = NumberSequence.new(0.7, 1)
		-- Alternate the two wakes' base transparency on a 1.1s cycle. NumberSequence
		-- swaps only at the half-cycle crossing (not per frame) to keep it cheap.
		local swapped = false
		trec.animHandle = SoulStyles.registerAnimated(tA, function(now)
			local firstHalf = (now % 1.1) < 0.55
			if firstHalf ~= swapped then
				swapped = firstHalf
				tA.Transparency = NumberSequence.new(firstHalf and 0.25 or 0.7, 1)
				tB.Transparency = NumberSequence.new(firstHalf and 0.7 or 0.25, 1)
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
		-- Re-emphasize immediately (don't wait for the next SoulMap broadcast): resize
		-- the billboard and flip the emphasis ring for the bodies whose mine-ness
		-- changed. `rec.isMine` is left STALE on purpose so the next SoulMap (always
		-- broadcast alongside SetControlledBody) does one authoritative rebuild that
		-- also re-sizes the style's px-based strokes.
		for b, rec in pairs(halos) do
			local desired = (b == myBody)
			if rec.isMine ~= desired then
				local px = desired and SIZE_MINE or SIZE_OTHER
				rec.gui.Size = UDim2.fromOffset(px, px)
				rec.handle.setEmphasis(desired)
			end
		end
		watchGrace(body)
	end)
end

return SoulController
