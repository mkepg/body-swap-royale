--[[
	InputController -- cross-platform movement + jump via Roblox's default controls.
	Location: StarterPlayerScripts/Client/InputController  (ModuleScript)

	This game has no player.Character (Players.CharacterAutoLoads = false); the
	server hands the client ownership of a body and ClientControl drives that body's
	MOVEMENT locally (Humanoid:Move from the move vector below). We lean on Roblox's
	PlayerModule ControlModule so the player gets the DEFAULT cross-platform controls:
	WASD, gamepad stick, and -- crucially -- the default on-screen touch HUD
	(thumbstick + jump button) on mobile.

	Root cause of the "no mobile thumbstick" bug: ControlModule only builds/shows its
	touch HUD when it has a humanoid to control -- `UpdateTouchGuiVisibility()` gates
	`doShow` on `self.humanoid`, normally set from CharacterAdded. With no Character
	that humanoid stays nil forever, so the thumbstick never renders (while
	GetMoveVector still returns a zero vector, which is why desktop looked fine).

	ensureControls() hands the ControlModule the assigned body's humanoid so its
	default touch HUD appears and it drives jump (`self.humanoid.Jump`) on ALL devices.
	It is SELF-HEALING: called every frame with the current body, it re-binds only on
	change, so it is robust to the humanoid replicating in late, to round-start
	repositions, and to swaps -- no fragile one-shot attach.

	No double-driving: ControlModule's own per-frame move is `LocalPlayer:Move(...)`,
	which with no Character both no-ops AND spams a warning; enable() replaces its
	`moveFunction` with a no-op so it stays silent. ClientControl's `Humanoid:Move`
	remains the sole mover; we consume `GetMoveVector()` (camera-relative) for it.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TouchJumpLayout = require(Shared:WaitForChild("TouchJumpLayout"))

local LocalPlayer = Players.LocalPlayer

local InputController = {}

local controls = nil          -- the PlayerModule ControlModule
local MOVE_EPSILON_SQ = 0.01  -- treat |move| below this as "not moving"
local jumpHeld = false         -- touch jump button held (see setupJump)
local jumpButton = nil         -- our default-replica ImageButton (touch / TOUCH_JUMP_FORCE)

-- The default TouchJump button's engine art (verified against the live
-- PlayerModule source 2026-07-10): one sprite sheet, normal + pressed rects.
local TOUCH_SHEET = "rbxasset://textures/ui/Input/TouchControlsSheetV2.png"
local RECT_NORMAL = Vector2.new(1, 146)
local RECT_PRESSED = Vector2.new(146, 146)
local RECT_SIZE = Vector2.new(144, 144)

-- Acquire and enable Roblox's control module. Idempotent.
function InputController.enable()
	if not controls then
		local playerModule = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		controls = playerModule:GetControls()
		-- We own movement (ClientControl's Humanoid:Move). Stop the ControlModule
		-- from also calling LocalPlayer:Move() every frame -- with no Character that
		-- is a no-op that spams "Player:Move called, but player currently has no
		-- character" once per frame. Jump (self.humanoid.Jump) is unaffected.
		controls.moveFunction = function() end
	end
	controls:Enable()
end

-- Current camera-relative move vector as (moveX, moveZ). +X = strafe right,
-- -Z = forward (matches MoveDirection.resolve's convention). Returns 0,0 until
-- enable() has run.
function InputController.getMoveVector()
	if not controls then
		return 0, 0
	end
	local mv = controls:GetMoveVector()
	return mv.X, mv.Z
end

-- True when the player is pushing the stick/keys enough to count as moving.
-- Device-agnostic replacement for watching raw WASD/Space.
function InputController.isMoving()
	local x, z = InputController.getMoveVector()
	return (x * x + z * z) > MOVE_EPSILON_SQ
end

-- Keep Roblox's ControlModule bound to the body we currently control, so its
-- default controls (the mobile touch HUD + jump) render and follow swaps. Call
-- every frame with the current body + its humanoid; re-binds only when the humanoid
-- changes, so it is cheap and self-heals against late replication / repositions.
function InputController.ensureControls(body, humanoid)
	if not controls then
		InputController.enable()
	end
	if humanoid and controls.humanoid ~= humanoid then
		controls:OnCharacterAdded(body)
		if jumpButton then
			jumpButton.Visible = true
		end
	end
end

-- No body to control (eliminated / round over / spectating): clear the
-- ControlModule's humanoid so it stops driving a stale one and hides the touch HUD.
function InputController.releaseControls()
	if controls and controls.humanoid ~= nil then
		controls:OnCharacterRemoving()
		if jumpButton then
			jumpButton.Visible = false
			jumpButton.ImageRectOffset = RECT_NORMAL
		end
		jumpHeld = false
	end
end

-- Jump. Desktop (Space) and gamepad (ButtonA) already jump via the ControlModule's
-- own controllers, which set `humanoid.Jump` in its Input-priority render step. TOUCH
-- is the gap: Roblox's default TouchJump button is hard-gated on LocalPlayer.Character
-- (via CharacterUtil), which this game never has, so it never renders. So we build a
-- REPLICA of the default button (spec 2026-07-10): same engine sprite-sheet art +
-- pressed state, and the default form-factor layout rules via the pure
-- TouchJumpLayout (size comfort-scaled by Config.TOUCH_JUMP_SCALE), re-applied on
-- every viewport change. (The old ContextActionService button was CAS-small and
-- ignored those rules -- the 2026-07-10 "too small on mobile" report.)
--
-- The catch (unchanged from the CAS era): because we feed the ControlModule our
-- body's humanoid (for the thumbstick), its render step writes `humanoid.Jump =
-- false` every frame on touch. A one-shot `Jump = true` would be stomped. So we
-- re-assert `Jump = true` while the button is held at Last render priority (2000),
-- which runs AFTER the ControlModule's Input step (100) -- our write wins.
--
-- Hold tracking follows the initiating touch's InputObject via UserInputService.
-- InputEnded: releasing OFF the button (finger slid away) still releases the jump,
-- which button-local InputEnded alone would miss.
function InputController.setupJump()
	if not (UserInputService.TouchEnabled or Config.TOUCH_JUMP_FORCE) then
		return -- keyboard/gamepad jump is the ControlModule's; no on-screen button
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "BSRTouchJump"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.Parent = playerGui

	local button = Instance.new("ImageButton")
	button.Name = "JumpButton"
	button.BackgroundTransparency = 1
	button.Image = TOUCH_SHEET
	button.ImageRectOffset = RECT_NORMAL
	button.ImageRectSize = RECT_SIZE
	button.Visible = false -- shown by ensureControls once a body is bound
	button.Parent = gui
	jumpButton = button

	-- Layout: the pure module's numbers -> UDim2, re-applied on every viewport
	-- change, re-bound if the Camera instance itself is ever replaced.
	local function applyLayout()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vps = cam.ViewportSize
		local l = TouchJumpLayout.compute(vps.X, vps.Y, Config.TOUCH_JUMP_SCALE)
		button.Size = UDim2.new(0, l.size, 0, l.size)
		button.Position = UDim2.new(1, l.xOffset, 1, l.yOffset)
	end
	local viewportConn = nil
	local function bindCamera()
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		local cam = workspace.CurrentCamera
		if cam then
			viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
		end
		applyLayout()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()

	-- Hold tracking (see doc comment above). MouseButton1 only matters under
	-- TOUCH_JUMP_FORCE (desktop layout verification).
	local activeInput = nil
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeInput = input
			jumpHeld = true
			button.ImageRectOffset = RECT_PRESSED
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == activeInput then
			activeInput = nil
			jumpHeld = false
			button.ImageRectOffset = RECT_NORMAL
		end
	end)

	RunService:BindToRenderStep("BSR_JumpReassert", Enum.RenderPriority.Last.Value, function()
		if jumpHeld and controls and controls.humanoid then
			controls.humanoid.Jump = true
		end
	end)
end

return InputController
