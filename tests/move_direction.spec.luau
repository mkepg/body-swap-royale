local MoveDirection = require("../src/shared/MoveDirection")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local function approx(a, b)
	return math.abs(a - b) < 1e-9
end

-- Default camera: look = (0,0,-1), right = (1,0,0). GetMoveVector convention:
-- +X = strafe right, -Z = forward.
local LOOKX, LOOKZ = 0, -1
local RIGHTX, RIGHTZ = 1, 0

-- Forward (moveZ = -1) -> world -Z (forward when camera faces -Z).
do
	local dx, dz = MoveDirection.resolve(0, -1, LOOKX, LOOKZ, RIGHTX, RIGHTZ)
	expect(approx(dx, 0) and approx(dz, -1), "forward should map to world -Z")
	print("move: forward OK")
end

-- Back (moveZ = 1) -> world +Z.
do
	local dx, dz = MoveDirection.resolve(0, 1, LOOKX, LOOKZ, RIGHTX, RIGHTZ)
	expect(approx(dx, 0) and approx(dz, 1), "back should map to world +Z")
	print("move: back OK")
end

-- Strafe right (moveX = 1) -> world +X.
do
	local dx, dz = MoveDirection.resolve(1, 0, LOOKX, LOOKZ, RIGHTX, RIGHTZ)
	expect(approx(dx, 1) and approx(dz, 0), "strafe right should map to world +X")
	print("move: strafe-right OK")
end

-- Strafe left (moveX = -1) -> world -X.
do
	local dx, dz = MoveDirection.resolve(-1, 0, LOOKX, LOOKZ, RIGHTX, RIGHTZ)
	expect(approx(dx, -1) and approx(dz, 0), "strafe left should map to world -X")
	print("move: strafe-left OK")
end

-- Diagonal (forward + right): normalized magnitude ~1.
do
	local dx, dz = MoveDirection.resolve(1, -1, LOOKX, LOOKZ, RIGHTX, RIGHTZ)
	local mag = math.sqrt(dx * dx + dz * dz)
	expect(approx(mag, 1), "diagonal output must be normalized to magnitude 1")
	expect(dx > 0 and dz < 0, "forward+right diagonal should point +X/-Z")
	print("move: diagonal normalized OK")
end

-- Rotated camera facing +X: look = (1,0,0), right = (0,0,1).
-- Forward input should now map to world +X.
do
	local dx, dz = MoveDirection.resolve(0, -1, 1, 0, 0, 1)
	expect(approx(dx, 1) and approx(dz, 0), "forward with camera facing +X should map to world +X")
	print("move: rotated-camera OK")
end

-- Zero input -> (0,0).
do
	local dx, dz = MoveDirection.resolve(0, 0, LOOKX, LOOKZ, RIGHTX, RIGHTZ)
	expect(dx == 0 and dz == 0, "zero input must return (0,0)")
	print("move: zero OK")
end

-- Sub-epsilon input -> (0,0) (no divide-by-near-zero, no jitter).
do
	local dx, dz = MoveDirection.resolve(1e-6, -1e-6, LOOKX, LOOKZ, RIGHTX, RIGHTZ)
	expect(dx == 0 and dz == 0, "sub-epsilon input must return (0,0)")
	print("move: sub-epsilon OK")
end

print("ALL MoveDirection TESTS PASSED")
