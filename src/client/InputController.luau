--[[
	InputController -- cross-platform movement + jump input (the swappable seam).
	Location: StarterPlayerScripts/Client/InputController  (ModuleScript)

	This game has no player.Character (Players.CharacterAutoLoads = false); the
	server hands the client ownership of a body and ClientControl drives it. So we
	consume Roblox's PlayerModule control module ONLY for its device-agnostic move
	vector (WASD + touch thumbstick + gamepad left stick), and bind jump through
	ContextActionService (which also auto-draws the mobile jump button and binds
	gamepad ButtonA).

	Enable() must be called explicitly: the PlayerModule normally enables controls
	on CharacterAdded, which never fires here.

	It is a thin seam on purpose: if GetControls() proves unusable without a
	Character, this module can be reimplemented with a custom on-screen thumbstick
	WITHOUT any change to ClientControl.
--]]

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local LocalPlayer = Players.LocalPlayer

local InputController = {}

local controls = nil          -- the PlayerModule ControlModule
local jumpBound = false
local MOVE_EPSILON_SQ = 0.01  -- treat |move| below this as "not moving"

-- Acquire and enable Roblox's control module. Idempotent.
function InputController.enable()
	if not controls then
		local playerModule = require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		controls = playerModule:GetControls()
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

-- Bind jump across keyboard (Space), gamepad (ButtonA), and touch (auto button).
-- `onJump` is called once per press (on Begin). Idempotent.
function InputController.bindJump(onJump)
	if jumpBound then
		return
	end
	jumpBound = true
	ContextActionService:BindAction(
		"BSR_Jump",
		function(_actionName, inputState, _inputObject)
			if inputState == Enum.UserInputState.Begin then
				onJump()
			end
			return Enum.ContextActionResult.Pass
		end,
		true, -- createTouchButton: draws the mobile jump button
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)
end

return InputController
