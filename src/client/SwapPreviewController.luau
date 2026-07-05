--[[
	SwapPreviewController -- the swap-preview DIRECTIONAL PING. Highlights the body
	THIS client will inherit AND guides the eye to it, because the target is frequently
	off-camera (a Highlight you can't see is not a preview):
	  - the shipped amber Highlight on the target body,
	  - an on-target chevron (BillboardGui) while the target is on-screen,
	  - an off-screen edge arrow (ScreenGui) that points toward the target otherwise.
	A per-frame update projects the target via the camera and feeds the pure
	PingDirectionModel (Roblox-free, lune-tested). Clears on the commit's
	SetControlledBody retarget or when the round leaves Active.
	Location: StarterPlayerScripts/Client/SwapPreviewController  (ModuleScript)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PingDirectionModel = require(Shared:WaitForChild("PingDirectionModel"))

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

local SwapPreview = Remotes.get("SwapPreview")
local SetControlledBody = Remotes.get("SetControlledBody")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local localPlayer = Players.LocalPlayer

local SwapPreviewController = {}
local target = nil          -- the Model this client will inherit
local highlight = nil
local chevron = nil         -- BillboardGui on the target head
local screenGui = nil
local arrow = nil           -- off-screen edge arrow (TextLabel)
local renderConn = nil

local function ensureGui()
	if screenGui then
		return
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SwapPingGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 20
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

	arrow = Instance.new("TextLabel")
	arrow.Name = "EdgeArrow"
	arrow.Size = UDim2.fromOffset(Config.PING_ARROW_SIZE, Config.PING_ARROW_SIZE)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.Text = "\u{25B2}" -- up triangle; rotationDeg rotates it to face the target
	arrow.TextScaled = true
	arrow.TextColor3 = Config.PING_COLOR
	arrow.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = HudTheme.Color.textStroke
	stroke.Parent = arrow
	arrow.Parent = screenGui
end

local function makeChevron(body)
	local head = body:FindFirstChild("Head") or body:FindFirstChild("HumanoidRootPart")
	if not head then
		return nil
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "SwapPingChevron"
	bb.Size = UDim2.fromOffset(Config.PING_CHEVRON_SIZE, Config.PING_CHEVRON_SIZE)
	bb.StudsOffsetWorldSpace = Vector3.new(0, Config.PING_CHEVRON_HEIGHT, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = "\u{25BC}" -- down triangle over the head
	lbl.TextScaled = true
	lbl.TextColor3 = Config.PING_COLOR
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = HudTheme.Color.textStroke
	stroke.Parent = lbl
	lbl.Parent = bb
	return bb
end

local function clear()
	target = nil
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	if chevron then
		chevron:Destroy()
		chevron = nil
	end
	if arrow then
		arrow.Visible = false
	end
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function update()
	if not (target and target.Parent) then
		clear()
		return
	end
	local root = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
	if not root then
		clear() -- target has no root parts (rig teardown) -> unusable; stop pinging
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return -- transient (camera swap); keep the preview alive
	end
	local vp = camera.ViewportSize
	local sp = camera:WorldToViewportPoint(root.Position)
	local r = PingDirectionModel.resolve(sp.X, sp.Y, sp.Z, vp.X, vp.Y, Config.PING_EDGE_MARGIN)
	if chevron then
		chevron.Enabled = r.onScreen
	end
	if arrow then
		if r.onScreen then
			arrow.Visible = false
		else
			arrow.Visible = true
			arrow.Position = UDim2.fromOffset(r.x, r.y)
			arrow.Rotation = r.rotationDeg
		end
	end
end

local function begin(body)
	clear()
	if not (body and body:IsA("Model")) then
		return
	end
	target = body
	highlight = Instance.new("Highlight")
	highlight.Name = "SwapTargetHighlight"
	highlight.FillColor = Config.PING_COLOR
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Config.PING_OUTLINE_COLOR
	highlight.Adornee = body
	highlight.Parent = body
	chevron = makeChevron(body)
	ensureGui()
	renderConn = RunService.RenderStepped:Connect(update)
end

function SwapPreviewController.start()
	SwapPreview.OnClientEvent:Connect(begin)
	-- The commit retargets control -> the preview is over.
	SetControlledBody.OnClientEvent:Connect(clear)
	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state.phase ~= "Active" then
			clear()
		end
	end)
end

return SwapPreviewController
