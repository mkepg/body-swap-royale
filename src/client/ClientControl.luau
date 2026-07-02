--[[
	ClientControl -- input + camera only.
	Location: StarterPlayerScripts/Client/ClientControl  (ModuleScript)

	The server hands this client ownership of a body and tells it which one (via
	the SetControlledBody RemoteEvent). The client drives that body locally
	(Humanoid:Move -> predicted, smooth) and points the camera at it. On a swap
	it plays a short FOV "punch."

	Movement/jump input is device-agnostic: InputController supplies a move vector
	(WASD + touch thumbstick + gamepad stick) and a cross-device jump binding;
	MoveDirection turns the camera-relative vector into a world direction. Camera
	rotation is left to Roblox's default CameraModule (works on all devices).

	Animation is handled separately by ClientAnimator (local, per-body, from
	replicated velocity) -- intentionally NOT here.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local MoveDirection = require(Shared:WaitForChild("MoveDirection"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local SetControlledBody = Remotes.get("SetControlledBody")

local ClientControl = {}

local camera = workspace.CurrentCamera
local body, hum

-- Camera-relative move vector (from any device) -> normalized world direction.
local function worldDir()
	local moveX, moveZ = InputController.getMoveVector()
	local cf = camera.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	look, right = look.Unit, right.Unit
	local dx, dz = MoveDirection.resolve(moveX, moveZ, look.X, look.Z, right.X, right.Z)
	if dx == 0 and dz == 0 then
		return Vector3.zero
	end
	return Vector3.new(dx, 0, dz)
end

function ClientControl.start()
	InputController.enable()
	InputController.bindJump(function()
		if hum then
			hum.Jump = true
		end
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
