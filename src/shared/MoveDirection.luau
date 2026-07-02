--[[
	MoveDirection -- PURE camera-relative move-vector -> world XZ direction.
	Location (Roblox): ReplicatedStorage/Shared/MoveDirection  (ModuleScript)

	No Roblox APIs (no Vector3/CFrame), no clocks, no RNG. Number-in / number-out;
	the client glue (ClientControl) supplies GetMoveVector()'s X/Z and the camera's
	flattened look/right, and turns the returned (dx, dz) into a Vector3 for
	Humanoid:Move. Mirrors the project's other pure modules (HexGrid, SpawnLayout).

	This is the old WASD-only worldDir() math generalized to a continuous vector:
	the same `right * moveX + look * (-moveZ)`, normalized, so it is device-agnostic
	(keyboard, touch thumbstick, and gamepad stick all arrive as a move vector).

	Convention (matches Roblox ControlModule:GetMoveVector): moveX is strafe with
	+X = right; moveZ is forward/back with -Z = forward.
--]]

local MoveDirection = {}

local EPSILON = 1e-3

-- Returns a normalized world-space (dx, dz) direction, or (0, 0) if the input is
-- negligible. look/right are the camera's flattened (Y-zeroed), unit look and right
-- component pairs.
function MoveDirection.resolve(moveX, moveZ, lookX, lookZ, rightX, rightZ)
	local x = rightX * moveX + lookX * (-moveZ)
	local z = rightZ * moveX + lookZ * (-moveZ)
	local mag = math.sqrt(x * x + z * z)
	if mag < EPSILON then
		return 0, 0
	end
	return x / mag, z / mag
end

return MoveDirection
