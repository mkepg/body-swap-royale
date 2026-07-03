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
local SoulMap = Remotes.get("SoulMap")
local SetControlledBody = Remotes.get("SetControlledBody")

local SoulController = {}
local myBody = nil
local halos = {} -- [body] = BillboardGui

local SIZE_MINE = UDim2.fromOffset(42, 42)
local SIZE_OTHER = UDim2.fromOffset(24, 24)

local function makeHalo(head)
	local halo = Instance.new("BillboardGui")
	halo.Name = "SoulHalo"
	halo.Size = SIZE_OTHER
	halo.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	halo.AlwaysOnTop = true
	halo.Adornee = head
	halo.Parent = head

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromScale(1, 1)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.Parent = halo

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Emphasis"
	stroke.Thickness = 0
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Parent = dot

	return halo
end

local function applyEmphasis(body, halo)
	local isMine = (body == myBody)
	halo.Size = isMine and SIZE_MINE or SIZE_OTHER
	local stroke = halo:FindFirstChild("Dot") and halo.Dot:FindFirstChild("Emphasis")
	if stroke then
		stroke.Thickness = isMine and 3 or 0
	end
end

local function reconcile(list)
	local seen = {}
	for _, entry in ipairs(list) do
		local body, color = entry.body, entry.color
		if body and body.Parent then
			local head = body:FindFirstChild("Head") or body:FindFirstChild("HumanoidRootPart")
			if head then
				seen[body] = true
				local halo = halos[body]
				if not halo or halo.Parent ~= head then
					if halo then halo:Destroy() end
					halo = makeHalo(head)
					halos[body] = halo
				end
				local dot = halo:FindFirstChild("Dot")
				if dot then
					dot.BackgroundColor3 = color
				end
				applyEmphasis(body, halo)
			end
		end
	end
	-- Drop halos for bodies no longer in the map.
	for body, halo in pairs(halos) do
		if not seen[body] then
			halo:Destroy()
			halos[body] = nil
		end
	end
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

function SoulController.start()
	SoulMap.OnClientEvent:Connect(reconcile)

	SetControlledBody.OnClientEvent:Connect(function(body, _isSwap)
		myBody = body
		-- Re-emphasize immediately (don't wait for the next SoulMap broadcast).
		for b, halo in pairs(halos) do
			applyEmphasis(b, halo)
		end
		watchGrace(body)
	end)
end

return SoulController
