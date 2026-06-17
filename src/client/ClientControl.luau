--[[
	ClientControl -- input + camera only.
	Location: StarterPlayerScripts/Client/ClientControl  (ModuleScript)

	The server hands this client ownership of a body and tells it which one (via
	the SetControlledBody RemoteEvent). The client drives that body locally
	(Humanoid:Move -> predicted, smooth) and points the camera at it. On a swap
	it plays a short FOV "punch."

	Animation is handled separately by ClientAnimator (local, per-body, from
	replicated velocity) -- intentionally NOT here.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local SetControlledBody = Remotes.get("SetControlledBody")

local ClientControl = {}

local camera = workspace.CurrentCamera
local body, hum

-- ===== input =====
local keys = { W = false, A = false, S = false, D = false }

local function worldDir()
	local x, z = 0, 0
	if keys.W then z -= 1 end
	if keys.S then z += 1 end
	if keys.A then x -= 1 end
	if keys.D then x += 1 end
	if x == 0 and z == 0 then return Vector3.zero end
	local cf = camera.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	if look.Magnitude < 1e-3 then look = Vector3.new(0, 0, -1) end
	look, right = look.Unit, right.Unit
	local d = right * x + look * (-z)
	return d.Magnitude > 0 and d.Unit or Vector3.zero
end

function ClientControl.start()
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.W then keys.W = true
		elseif kc == Enum.KeyCode.A then keys.A = true
		elseif kc == Enum.KeyCode.S then keys.S = true
		elseif kc == Enum.KeyCode.D then keys.D = true
		elseif kc == Enum.KeyCode.Space then
			if hum then hum.Jump = true end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local kc = input.KeyCode
		if kc == Enum.KeyCode.W then keys.W = false
		elseif kc == Enum.KeyCode.A then keys.A = false
		elseif kc == Enum.KeyCode.S then keys.S = false
		elseif kc == Enum.KeyCode.D then keys.D = false end
	end)

	RunService.RenderStepped:Connect(function()
		if hum and body and body.Parent then
			hum:Move(worldDir(), false) -- client owns this body, so this is predicted
		end
	end)

	-- ===== control assignment + swap transition =====
	SetControlledBody.OnClientEvent:Connect(function(newBody, isSwap)
		body = newBody
		hum = newBody:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = hum
		if isSwap then
			camera.FieldOfView = 88
			TweenService:Create(
				camera,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ FieldOfView = 70 }
			):Play()
		end
		print("[BSR] controlling:", newBody.Name, isSwap and "(swap)" or "(spawn)")
	end)
end

return ClientControl
