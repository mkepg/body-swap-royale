--[[
	ClientControl -- input + camera only.
	Location: StarterPlayerScripts/Client/ClientControl  (ModuleScript)

	The server hands this client ownership of a body and tells it which one (via
	the SetControlledBody RemoteEvent). The client drives that body locally
	(Humanoid:Move -> predicted, smooth) and points the camera at it. On a swap
	it plays a short FOV "punch."

	Movement input is device-agnostic: InputController supplies a move vector (WASD +
	default touch thumbstick + gamepad stick) and MoveDirection turns that
	camera-relative vector into a world direction we feed to Humanoid:Move. Jump and
	the mobile touch HUD are Roblox's DEFAULT controls: InputController.ensureControls
	keeps the ControlModule bound to the current body each frame, so it renders the
	touch thumbstick/jump button and drives jump on every device. Camera rotation is
	left to Roblox's default CameraModule (works on all devices).

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
	-- Connect the assignment handler FIRST, before enable() -- enable() yields on
	-- WaitForChild("PlayerModule"), and the initial SetControlledBody can fire during
	-- that yield. Connecting first guarantees we never miss the spawn assignment (and
	-- thus never miss attaching the body to the ControlModule for the touch HUD).
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

	RunService.RenderStepped:Connect(function()
		if body and body.Parent then
			-- Re-derive the humanoid each frame. The body (and its Humanoid) can
			-- replicate in AFTER the SetControlledBody handler runs, which would leave a
			-- once-captured `hum` nil forever (no movement, no control binding). This is
			-- robust to that late replication.
			hum = body:FindFirstChildOfClass("Humanoid")
			if hum then
				if camera.CameraSubject ~= hum then
					camera.CameraSubject = hum
				end
				-- Keep Roblox's ControlModule bound to this body so its default touch HUD
				-- (thumbstick + jump) renders and it drives jump. Self-healing/idempotent.
				InputController.ensureControls(body, hum)
				hum:Move(worldDir(), false) -- client owns this body, so this is predicted
			end
		else
			InputController.releaseControls()
		end
	end)

	-- enable() yields on WaitForChild("PlayerModule"); do it last so the handlers
	-- above are already live. ensureControls() self-heals by calling enable() if a
	-- body is assigned before this returns.
	InputController.enable()
	-- Touch-only jump button (default controls cover desktop/gamepad jump already).
	InputController.setupJump()
end

return ClientControl
