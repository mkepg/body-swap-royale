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
local InputController = require(script.Parent:WaitForChild("InputController"))

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

-- A brief shield shimmer on the body you just swapped into, mirroring the
-- post-swap grace window: it pulses for up to GRACE_SECONDS and fades early once
-- you've moved (after the GRACE_FLOOR_SECONDS hard floor). Cosmetic only -- the
-- server owns the real grace gate; this approximates its feel from local input.
local shimmerToken = nil

local function playGraceShimmer(body)
	if not (body and body.Parent) then
		return
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
	local moved = false

	task.spawn(function()
		-- `hl.Parent` guard: if the body is destroyed mid-grace (its owner
		-- disconnects -> BodyManager.removeBody), hl is destroyed with it; stop
		-- before writing to the locked instance so we still disconnect cleanly.
		while shimmerToken == token and hl.Parent do
			local elapsed = os.clock() - start
			hl.FillTransparency = 0.5 + 0.3 * math.sin(elapsed * 8) -- pulse
			-- Device-agnostic "moved": true once the player pushes the stick/keys,
			-- across keyboard, touch, and gamepad (was raw WASD/Space only).
			if not moved and InputController.isMoving() then
				moved = true
			end
			local floorDone = elapsed >= Config.GRACE_FLOOR_SECONDS
			if elapsed >= Config.GRACE_SECONDS or (floorDone and moved) then
				break
			end
			task.wait()
		end
		hl:Destroy()
		if shimmerToken == token then
			shimmerToken = nil
		end
	end)
end

function SoulController.start()
	SoulMap.OnClientEvent:Connect(reconcile)

	SetControlledBody.OnClientEvent:Connect(function(body, isSwap)
		myBody = body
		-- Re-emphasize immediately (don't wait for the next SoulMap broadcast).
		for b, halo in pairs(halos) do
			applyEmphasis(b, halo)
		end
		if isSwap and body then
			playGraceShimmer(body)
		end
	end)
end

return SoulController
