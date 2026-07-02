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

local LocalPlayer = Players.LocalPlayer

local InputController = {}

local controls = nil          -- the PlayerModule ControlModule
local MOVE_EPSILON_SQ = 0.01  -- treat |move| below this as "not moving"

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
	end
end

-- No body to control (eliminated / round over / spectating): clear the
-- ControlModule's humanoid so it stops driving a stale one and hides the touch HUD.
function InputController.releaseControls()
	if controls and controls.humanoid ~= nil then
		controls:OnCharacterRemoving()
	end
end

return InputController
