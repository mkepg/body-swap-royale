# Cross-Platform Controls Implementation Plan

**Goal:** Give touch, keyboard/mouse, and gamepad players working movement + jump for the server-assigned body, closing the mobile/gamepad zero-input gap that blocks the tester build.

**Architecture:** Reuse Roblox's `PlayerModule` control module for a device-agnostic move vector and `ContextActionService` for a cross-device jump (with an auto-generated mobile button), placed behind a thin `InputController` seam so a custom-thumbstick fallback can replace it without touching `ClientControl`. A new PURE, lune-tested `MoveDirection` module replaces the WASD-only `worldDir()` math.

**Tech Stack:** Luau, Rojo, lune (pure-module unit tests), Roblox `PlayerModule`/`ContextActionService`/`UserInputService`.

**Spec:** `docs/specs/2026-07-02-cross-platform-controls-design.md`

**Conventions:**
- Pure modules live in `src/shared/` (→ `ReplicatedStorage.Shared`), no Roblox APIs, number-in/number-out; tested with lune.
- Client glue lives in `src/client/` (→ `StarterPlayerScripts.Client`); not lune-testable — verified by Studio MCP + a manual smoke-test doc.
- Rojo folder-maps `src/shared` and `src/client`, so new files auto-sync — **no `default.project.json` change needed.**
- Run lune tests with: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`
---

## Task 1: `MoveDirection` pure module (TDD)

Resolve a camera-relative move vector into a normalized world XZ direction. This is the current
`worldDir()` math generalized from discrete WASD keys to a continuous `(moveX, moveZ)` vector.

**Files:**
- Create: `src/shared/MoveDirection.luau`
- Test: `tests/move_direction.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/move_direction.spec.luau`:

```luau
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/move_direction.spec.luau`
Expected: FAIL (module `../src/shared/MoveDirection` does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `src/shared/MoveDirection.luau`:

```luau
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/move_direction.spec.luau`
Expected: prints each `move: ... OK` line then `ALL MoveDirection TESTS PASSED`.

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: every spec prints its `ALL ... TESTS PASSED` line (18 specs now, including the new one).

- [ ] **Step 6: Commit**

```bash
git add src/shared/MoveDirection.luau tests/move_direction.spec.luau
git commit -m "feat(controls): add pure MoveDirection (camera-relative move vector -> world dir)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `InputController` client glue module

The swappable seam over Roblox input: device-agnostic move vector via `PlayerModule` controls, and
cross-device jump via `ContextActionService` (auto-creates the mobile jump button). Not
lune-testable (Roblox APIs); verified by code review here and the smoke test in Task 5.

**Files:**
- Create: `src/client/InputController.luau`

- [ ] **Step 1: Write the module**

Create `src/client/InputController.luau`:

```luau
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
```

- [ ] **Step 2: Syntax-check the module parses**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; stylua --check src/client/InputController.luau 2>/dev/null || echo "stylua not configured — skip"`
Expected: no formatting errors, or the skip message if stylua isn't set up. (This is a light
parse/format sanity check only; true verification is the Task 5 smoke test.)

- [ ] **Step 3: Commit**

```bash
git add src/client/InputController.luau
git commit -m "feat(controls): add InputController seam (PlayerModule move + CAS jump)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire `ClientControl` to `InputController` + `MoveDirection`

Replace the WASD-key table and direct Space handling with the device-agnostic seam and the pure
resolver. The control-assignment / swap-FOV logic is unchanged.

**Files:**
- Modify: `src/client/ClientControl.luau`

- [ ] **Step 1: Rewrite the input half of the module**

Replace the entire contents of `src/client/ClientControl.luau` with:

```luau
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
```

- [ ] **Step 2: Verify unchanged specs still pass (no pure logic changed, sanity only)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/move_direction.spec.luau`
Expected: `ALL MoveDirection TESTS PASSED` (ClientControl isn't lune-tested; this confirms the
shared resolver it now depends on is intact).

- [ ] **Step 3: Commit**

```bash
git add src/client/ClientControl.luau
git commit -m "feat(controls): drive body from device-agnostic InputController + MoveDirection

Replaces the WASD-only key table and Space handler; jump now binds keyboard,
gamepad ButtonA, and an auto-created touch button. Camera unchanged.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Generalize `SoulController` grace-shimmer "moved" detection

The cosmetic post-swap shimmer fades early once the player moves. It currently detects that from
raw WASD/Space via `UserInputService.InputBegan`, which never fires on touch/gamepad. Switch it to
the device-agnostic `InputController.isMoving()`.

**Files:**
- Modify: `src/client/SoulController.luau`

- [ ] **Step 1: Add the InputController require**

In `src/client/SoulController.luau`, the current requires block is:

```luau
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SoulMap = Remotes.get("SoulMap")
local SetControlledBody = Remotes.get("SetControlledBody")
```

Add the InputController require directly after it:

```luau
local InputController = require(script.Parent:WaitForChild("InputController"))
```

- [ ] **Step 2: Replace the raw-key "moved" detection with the device-agnostic poll**

In `playGraceShimmer`, remove the `UserInputService`-based `moved` tracking. The current code is:

```luau
	local start = os.clock()
	local moved = false
	local conn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then
			return
		end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.W or kc == Enum.KeyCode.A or kc == Enum.KeyCode.S
			or kc == Enum.KeyCode.D or kc == Enum.KeyCode.Space then
			moved = true
		end
	end)

	task.spawn(function()
		-- `hl.Parent` guard: if the body is destroyed mid-grace (its owner
		-- disconnects -> BodyManager.removeBody), hl is destroyed with it; stop
		-- before writing to the locked instance so we still disconnect cleanly.
		while shimmerToken == token and hl.Parent do
			local elapsed = os.clock() - start
			hl.FillTransparency = 0.5 + 0.3 * math.sin(elapsed * 8) -- pulse
			local floorDone = elapsed >= Config.GRACE_FLOOR_SECONDS
			if elapsed >= Config.GRACE_SECONDS or (floorDone and moved) then
				break
			end
			task.wait()
		end
		conn:Disconnect()
		hl:Destroy()
		if shimmerToken == token then
			shimmerToken = nil
		end
	end)
```

Replace it with (poll `InputController.isMoving()` each tick instead of connecting to InputBegan;
no connection to clean up):

```luau
	local start = os.clock()
	local moved = false

	task.spawn(function()
		-- `hl.Parent` guard: if the body is destroyed mid-grace (its owner
		-- disconnects -> BodyManager.removeBody), hl is destroyed with it; stop
		-- before writing to the locked instance so we still disconnect cleanly.
		while shimmerToken == token and hl.Parent do
			local elapsed = os.clock() - start
			hl.FillTransparency = 0.5 + 0.3 * math.sin(elapsed * 8) -- pulse
			-- Device-agnostic "moved": true once the player pushes the stick/keys,
			-- across keyboard, touch, and gamepad (was raw WASD/Space only).
			if not moved and InputController.isMoving() then
				moved = true
			end
			local floorDone = elapsed >= Config.GRACE_FLOOR_SECONDS
			if elapsed >= Config.GRACE_SECONDS or (floorDone and moved) then
				break
			end
			task.wait()
		end
		hl:Destroy()
		if shimmerToken == token then
			shimmerToken = nil
		end
	end)
```

- [ ] **Step 3: Remove the now-unused `UserInputService` service reference**

`UserInputService` was only used by the code removed in Step 2. Confirm no other reference remains
(`grep -n UserInputService src/client/SoulController.luau` returns nothing), then delete its
service line near the top of the file:

```luau
local UserInputService = game:GetService("UserInputService")
```

- [ ] **Step 4: Verify shared specs still pass (sanity)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/move_direction.spec.luau`
Expected: `ALL MoveDirection TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/client/SoulController.luau
git commit -m "fix(controls): grace shimmer 'moved' via device-agnostic InputController.isMoving

Was watching raw WASD/Space (never fired on touch/gamepad), so the shimmer
misbehaved off keyboard. Now polls the unified move vector.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Cross-platform controls smoke-test doc

Client glue isn't lune-testable; this is the runtime verification the human drives (per project
convention). It also records the two load-bearing verifications from spec §6.

**Files:**
- Create: `docs/smoke-tests/2026-07-02-cross-platform-controls-smoke-test.md`

- [ ] **Step 1: Write the smoke-test doc**

Create `docs/smoke-tests/2026-07-02-cross-platform-controls-smoke-test.md`:

```markdown
# Smoke Test — Cross-Platform Controls (2026-07-02)

**Status:** RUNTIME-UNVERIFIED until run in Studio + on a real phone.
**Covers:** the client glue lune can't test — `InputController` (PlayerModule move
vector + ContextActionService jump) and `ClientControl` driving the assigned body
across Touch, Keyboard/Mouse, and Gamepad. Pure `MoveDirection` math is lune-covered.

**Spec:** `docs/specs/2026-07-02-cross-platform-controls-design.md`

**Note on `screen_capture`:** the MCP `screen_capture` tool renders only the edit
viewport, not the running Play client. All checks below require the human to drive
the actual Play session (and a real phone for touch).

## Load-bearing pre-check (spec §6.1) — ControlModule without a Character

- [ ] In a running Play session, open the command bar and run:
      `print(require(game.Players.LocalPlayer.PlayerScripts.PlayerModule):GetControls())`
      Expected: a controls object (not an error).
- [ ] While pushing WASD (or the thumbstick), print the move vector once per second
      and confirm it is nonzero while pushing, zero when released. If the vector is
      always zero, the ControlModule is not usable without a Character → invoke the
      spec's contingency (custom-thumbstick impl behind the same InputController seam).

## 1. Keyboard/Mouse (regression)

- [ ] WASD moves the controlled body relative to the camera (W = away from camera,
      etc.); movement matches pre-change behavior.
- [ ] Space makes the body jump.
- [ ] Mouse rotates the camera; the body follows.

## 2. Touch (Studio device emulation + a real phone)

- [ ] A movement thumbstick appears (bottom-left by default) and moves the body in
      all directions relative to the camera.
- [ ] A jump button appears (auto-created by ContextActionService) and jumps the body.
- [ ] Dragging elsewhere on screen rotates the camera (spec §6.2). If it does NOT,
      record it here — camera input becomes a separate follow-up.

## 3. Gamepad

- [ ] Left stick moves the body relative to the camera.
- [ ] Button A jumps the body.
- [ ] Right stick rotates the camera (spec §6.2). If it does NOT, record it here.

## 4. Grace shimmer × devices (Task 4)

- [ ] Force a swap: `require(game.ServerScriptService.Server.RoundManager).forceSwap()`
      (or wait for a cadence swap).
- [ ] The inherited body shows the blue grace shimmer. On EACH device (keyboard,
      touch, gamepad), once you push movement the shimmer fades early (after the
      hard-floor window); if you never move it pulses for the full grace window.

## 5. Swap still feels right (regression)

- [ ] After a swap, the FOV "punch" still plays and the camera snaps to the new body.
- [ ] Control of the new body is immediate on all devices.

## Result

Record pass/fail per check and any tuning notes (thumbstick/jump-button placement,
move-vector dead zone). If the §6.1 pre-check fails, note it prominently — the
contingency (custom thumbstick) is the follow-up.
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-07-02-cross-platform-controls-smoke-test.md
git commit -m "docs(controls): add cross-platform controls smoke-test doc

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Run the full lune suite once more: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done` — every spec passes.
- [ ] `grep -rn "keys\." src/client/ClientControl.luau` returns nothing (old WASD table gone).
- [ ] `grep -rn UserInputService src/client/ClientControl.luau src/client/SoulController.luau` returns nothing (both switched off raw key input).
- [ ] Confirm the branch is `feat/cross-platform-controls` and all five tasks are committed.
- [ ] Hand off to the human for the Studio + real-phone smoke test (Task 5 doc) — this is load-bearing and cannot be automated.
```
