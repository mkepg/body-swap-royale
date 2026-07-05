--[[
	HintController -- renders server-authoritative first-session hints as labels
	ANCHORED to the thing they explain: the swap-preview target ("you become this") or
	the local controlled body / Soul-halo body ("this is you"). The "which hint /
	once-ever" decision already happened server-side (HintService); this only renders.
	A sequential queue guarantees one hint at a time (future rows may fire close
	together). Non-blocking: never pauses input; auto-dismisses.
	Location: StarterPlayerScripts/Client/HintController  (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

local ShowHint = Remotes.get("ShowHint")
local SwapPreview = Remotes.get("SwapPreview")
local SetControlledBody = Remotes.get("SetControlledBody")

local HintController = {}
local previewTarget = nil     -- last SwapPreview body
local controlledBody = nil    -- last SetControlledBody body
local queue = {}
local showing = false

-- Anchored hints assume the server fires the anchor's remote (SwapPreview for
-- "target", SetControlledBody for "controlledBody") BEFORE ShowHint -- true today
-- (RoundManager fires the remote, then HintService). A future trigger fired before
-- its anchor remote would find no body and no-op via present()'s drop path.
local function anchorBody(anchor)
	if anchor == "controlledBody" then
		return controlledBody
	end
	return previewTarget
end

-- Returns true iff a label was actually created; false on any drop path (anchor
-- body/head missing) so the queue can release the slot immediately instead of
-- holding it for the label's full lifetime.
local function present(hint)
	local body = anchorBody(hint.anchor)
	if not (body and body.Parent) then
		return false -- anchor gone; drop this hint silently
	end
	local head = body:FindFirstChild("Head") or body:FindFirstChild("HumanoidRootPart")
	if not head then
		return false
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "HintLabel"
	bb.Size = UDim2.fromOffset(Config.HINT_LABEL_SIZE.X, Config.HINT_LABEL_SIZE.Y)
	bb.StudsOffsetWorldSpace = Vector3.new(0, Config.HINT_LABEL_HEIGHT, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = HudTheme.Color.panelDark
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Config.PING_OUTLINE_COLOR
	stroke.Transparency = 1
	stroke.Parent = panel
	panel.Parent = bb

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(0.9, 0.78)
	lbl.Position = UDim2.fromScale(0.05, 0.11)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = hint.text
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 235, 190)
	lbl.TextTransparency = 1
	local ls = Instance.new("UIStroke")
	ls.Thickness = 1
	ls.Color = HudTheme.Color.textStroke
	ls.Transparency = 1
	ls.Parent = lbl
	lbl.Parent = panel

	local inInfo = TweenInfo.new(Config.HINT_FADE_IN)
	TweenService:Create(panel, inInfo, { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(stroke, inInfo, { Transparency = 0 }):Play()
	TweenService:Create(lbl, inInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(ls, inInfo, { Transparency = 0 }):Play()

	task.delay(Config.HINT_FADE_IN + (hint.duration or 3), function()
		local outInfo = TweenInfo.new(Config.HINT_FADE_OUT)
		TweenService:Create(panel, outInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, outInfo, { Transparency = 1 }):Play()
		TweenService:Create(ls, outInfo, { Transparency = 1 }):Play()
		local fade = TweenService:Create(lbl, outInfo, { TextTransparency = 1 })
		fade.Completed:Connect(function()
			if bb then
				bb:Destroy()
			end
		end)
		fade:Play()
	end)
	return true
end

local function pump()
	if showing then
		return
	end
	local hint = table.remove(queue, 1)
	if not hint then
		return
	end
	showing = true
	if not present(hint) then
		-- The anchor was gone: nothing was shown, so don't hold the slot for the
		-- full lifetime -- release it and drive the next queued hint right away.
		showing = false
		task.spawn(pump)
		return
	end
	-- Hold the slot for the label's full lifetime so two never overlap.
	local life = Config.HINT_FADE_IN + (hint.duration or 3) + Config.HINT_FADE_OUT
	task.delay(life, function()
		showing = false
		pump()
	end)
end

function HintController.start()
	SwapPreview.OnClientEvent:Connect(function(body)
		previewTarget = body
	end)
	SetControlledBody.OnClientEvent:Connect(function(body)
		controlledBody = body
	end)
	ShowHint.OnClientEvent:Connect(function(hint)
		if type(hint) ~= "table" or type(hint.text) ~= "string" then
			return
		end
		if type(hint.duration) ~= "number" then
			hint.duration = 3 -- defend the hold/fade timing against a malformed row
		end
		queue[#queue + 1] = hint
		pump()
	end)
end

return HintController
