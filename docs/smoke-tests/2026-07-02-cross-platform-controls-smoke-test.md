# Smoke Test — Cross-Platform Controls (2026-07-02)

**Status:** RUNTIME-UNVERIFIED on-device until run on a real phone / Studio device emulation.
**Covers:** the client glue lune can't test — `InputController` (Roblox ControlModule as the
DEFAULT cross-platform input) + `DeviceOrientation` (landscape) + `ClientControl` driving the
assigned body. Pure `MoveDirection` math is lune-covered.

**Spec:** `docs/specs/2026-07-02-cross-platform-controls-design.md`

## Approach (as shipped) & root cause

The game has no `LocalPlayer.Character` (`Players.CharacterAutoLoads = false`). Roblox's
`ControlModule` only builds/shows its **default touch HUD** (thumbstick + jump button) when it
has a humanoid to control — `ControlModule:UpdateTouchGuiVisibility()` gates `doShow` on
`self.humanoid`, normally set from `CharacterAdded`, which never fires here. **That is why the
mobile thumbstick was missing while a jump button still showed.**

Fix (uses Roblox's DEFAULT controls, per request):
- `InputController.ensureControls(body, humanoid)` calls `controls:OnCharacterAdded(body)` each
  frame from `ClientControl` RenderStepped, binding the assigned body's humanoid so the default
  touch HUD renders and the ControlModule drives jump on all devices. Self-healing (re-binds only
  on change; robust to the body/humanoid replicating in late — `hum` is re-derived each frame).
- `enable()` sets `controls.moveFunction = function() end` so the ControlModule stops calling
  `LocalPlayer:Move()` each frame (with no Character it is a no-op that otherwise spams
  "Player:Move called, but player currently has no character"). We own movement via `Humanoid:Move`.
- `releaseControls()` clears the humanoid when there is no body (eliminated / round over).
- `DeviceOrientation` sets `PlayerGui.ScreenOrientation = LandscapeSensor` on join.

**Notes for whoever verifies:**
- The MCP `screen_capture` shows only the edit viewport, not the Play client — drive the real session.
- **MCP `execute_luau` runs in a SEPARATE `require` cache** from the game scripts. Reading
  `require(PlayerModule):GetControls().humanoid` in an MCP probe returns a *different* ControlModule
  instance (always nil) — it does NOT reflect the game's. To observe game state, use instance
  **Attributes** the game code sets, not `require(module).state`.

## Desktop-verified via MCP (2026-07-02)

- [x] Client boots clean: no errors, **no `Player:Move` spam** (moveFunction no-op working).
- [x] In-game ControlModule humanoid **is bound** to the controlled body (proven via a temporary
      Attribute written from inside `ensureControls`: `dbg_cmHumBefore=true`, `dbg_boundAfter=true`).
- [x] `PlayerGui.ScreenOrientation == LandscapeSensor`.
- Not observable on desktop: the touch HUD itself only renders when `PreferredInput == Touch`.

## 1. Touch — the primary check (real phone / Studio device emulation)

- [ ] A **movement thumbstick** appears (Roblox default, bottom-left / dynamic) and moves the body
      in all directions relative to the camera. (This is the reported bug — must now work.)
- [ ] A **jump button** appears (Roblox default, bottom-right) and jumps the body.
- [ ] Dragging elsewhere rotates the camera; the body follows.
- [ ] The screen is **landscape** on join and stays landscape (auto left/right by the sensor).

## 2. Keyboard/Mouse (regression)

- [ ] WASD moves the body relative to the camera; Space jumps; mouse rotates the camera.

## 3. Gamepad

- [ ] Left stick moves the body relative to the camera; Button A jumps; right stick rotates camera.

## 4. Swaps & grace shimmer × devices

- [ ] Force a swap: `require(game.ServerScriptService.Server.RoundManager).forceSwap()` (or wait for
      a cadence swap). Control + the touch HUD follow to the new body; the FOV "punch" plays.
- [ ] On each device, after a swap the blue grace shimmer fades early once you push movement (and
      pulses the full window if you never move).

## 5. Elimination / round end

- [ ] When your body is removed (eliminated / round over), no errors spam from a stale humanoid
      (releaseControls clears it); the touch HUD hides until the next round assigns a body.

## Result

Record pass/fail per check and any tuning notes (thumbstick style, jump-button placement, orientation
feel). The touch thumbstick appearing and moving the body is the load-bearing pass.
