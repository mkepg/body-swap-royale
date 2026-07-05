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

local body, hum
local myUserId = game:GetService("Players").LocalPlayer.UserId

-- ALWAYS read the camera live, never cache the instance. The engine can replace
-- workspace.CurrentCamera around client boot (the cold-join startup camera); a
-- camera cached at require time then silently receives every retarget while the
-- player watches the NEW camera -- a permanent camera-only spawn with a perfectly
-- healthy server, immune to all the server-side re-embodiment layers. Can be nil
-- for a moment mid-replacement, so callers must guard.
local function currentCamera()
	return workspace.CurrentCamera
end

-- Backstop for a missed/dropped SetControlledBody: find the body whose authoritative
-- ControllerUserId attribute (set by ControlManager) is ours. Returns nil (gracefully,
-- retried next frame) if workspace.Bodies hasn't replicated in yet or nothing matches.
local function findMyBody()
	local bodies = workspace:FindFirstChild("Bodies")
	if not bodies then
		return nil
	end
	for _, candidate in ipairs(bodies:GetChildren()) do
		if candidate:GetAttribute("ControllerUserId") == myUserId then
			return candidate
		end
	end
	return nil
end

-- Camera-relative move vector (from any device) -> normalized world direction.
local function worldDir()
	local camera = currentCamera()
	if not camera then
		return Vector3.zero
	end
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
		-- A cold-join fire can outrun the body's replication, in which case the
		-- engine delivers nil here. Don't bind (or index) it -- the per-frame
		-- reconcile below attaches via the ControllerUserId attribute as soon as
		-- the body streams in.
		if not newBody then
			warn("[BSR] SetControlledBody carried no body (not replicated yet); reconcile will attach")
			return
		end
		body = newBody
		hum = newBody:FindFirstChildOfClass("Humanoid")
		local camera = currentCamera()
		if camera then
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
		end
		print("[BSR] controlling:", newBody.Name, isSwap and "(swap)" or "(spawn)")
	end)

	RunService.RenderStepped:Connect(function()
		-- Self-heal a missed/dropped SetControlledBody: if we have no valid body that's
		-- still authoritatively ours, look one up from the ControllerUserId attribute.
		-- This trusts applyOwnership's server-side ordering (it sets ControllerUserId
		-- BEFORE firing SetControlledBody), so after a swap exactly one body carries our
		-- id and we can't re-attach to a stale one. This RECONCILE BLOCK is dormant
		-- whenever `body` is already correct (including during Lobby/Ended, where our own
		-- body's ControllerUserId still equals us), so it adds no new interference with
		-- SpectateBody's victory/spectator camera. (The per-frame CameraSubject write
		-- below is pre-existing and separate from this backstop.)
		local camera = currentCamera()

		if not (body and body.Parent and body:GetAttribute("ControllerUserId") == myUserId) then
			local found = findMyBody()
			if found and found ~= body then
				body = found
				hum = body:FindFirstChildOfClass("Humanoid")
				if camera then
					camera.CameraType = Enum.CameraType.Custom
				end
				print("[BSR] controlling (reconciled):", body.Name)
			end
		end

		if body and body.Parent then
			-- Re-derive the humanoid each frame. The body (and its Humanoid) can
			-- replicate in AFTER the SetControlledBody handler runs, which would leave a
			-- once-captured `hum` nil forever (no movement, no control binding). This is
			-- robust to that late replication.
			hum = body:FindFirstChildOfClass("Humanoid")
			if hum then
				-- Idempotent per-frame re-assert onto the LIVE camera; also heals a
				-- mid-session camera replacement (a fresh Camera doesn't start Custom
				-- or pointed at us).
				if camera and camera.CameraSubject ~= hum then
					camera.CameraType = Enum.CameraType.Custom
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

	-- Bodiless-join watchdog: DIAGNOSTICS only (healing lives in the reconcile
	-- above and the server sweep). A player never legitimately sits bodiless for
	-- multiple reconcile periods -- eliminated players still control a body -- so
	-- if we do, say WHICH layer is failing instead of leaving an intermittent
	-- stranding to guesswork: no Bodies folder = replication/server-boot problem;
	-- candidates but no ControllerUserId match = server-side control/attribute
	-- problem (the client cannot self-heal either one).
	task.spawn(function()
		while true do
			task.wait(5)
			if not (body and body.Parent) then
				local bodies = workspace:FindFirstChild("Bodies")
				if not bodies then
					warn("[BSR][watchdog] bodiless: workspace.Bodies has not replicated")
				else
					local kids = bodies:GetChildren()
					local ids = {}
					for i = 1, math.min(#kids, 8) do
						ids[i] = tostring(kids[i]:GetAttribute("ControllerUserId"))
					end
					warn(string.format(
						"[BSR][watchdog] bodiless: %d bodies, none with ControllerUserId == %d (saw: %s)",
						#kids, myUserId, table.concat(ids, ", ")))
				end
			end
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
