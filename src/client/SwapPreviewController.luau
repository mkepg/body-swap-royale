--[[
	SwapPreviewController -- highlights the body THIS client is about to inherit.
	Location: StarterPlayerScripts/Client/SwapPreviewController  (ModuleScript)

	On SwapPreview(body) (fired during the T-3s window) it outlines that body with
	a local Highlight, so the preview is a readable challenge. The outline clears
	on the next control retarget (the commit's SetControlledBody) or when the round
	leaves Active.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local SwapPreview = Remotes.get("SwapPreview")
local SetControlledBody = Remotes.get("SetControlledBody")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local SwapPreviewController = {}
local highlight = nil

local function clear()
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

function SwapPreviewController.start()
	SwapPreview.OnClientEvent:Connect(function(body)
		clear()
		if body and body:IsA("Model") then
			highlight = Instance.new("Highlight")
			highlight.Name = "SwapTargetHighlight"
			highlight.FillColor = Color3.fromRGB(255, 200, 60)
			highlight.FillTransparency = 0.6
			highlight.OutlineColor = Color3.fromRGB(255, 220, 120)
			highlight.Adornee = body
			highlight.Parent = body
		end
	end)

	-- The commit retargets control -> the preview is over.
	SetControlledBody.OnClientEvent:Connect(clear)

	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state.phase ~= "Active" then
			clear()
		end
	end)
end

return SwapPreviewController
