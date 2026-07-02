# Cross-Platform Controls — Touch + Keyboard/Mouse + Gamepad

**Date:** 2026-07-02
**Status:** APPROVED — ready for implementation plan.
**Priority:** Blocks the tester build. Testers cannot play on mobile (or gamepad) today.
**Related:** [ClientControl.luau](../../src/client/ClientControl.luau) (input + camera glue),
[SoulController.luau](../../src/client/SoulController.luau) (grace-shimmer "moved" detection),
`init.server.luau` (`Players.CharacterAutoLoads = false`), pure-module convention in
[HexGrid.luau](../../src/shared/HexGrid.luau) / [SpawnLayout.luau](../../src/shared/SpawnLayout.luau).

---

## 1. The gap

The game uses a **custom control model**: the server hands each client network ownership of a
separate body rig and tells it which body via the `SetControlledBody` RemoteEvent. There is **no
`player.Character`** (`Players.CharacterAutoLoads = false`), so Roblox's default control scripts
have nothing to drive. [ClientControl.luau](../../src/client/ClientControl.luau) drives the
assigned body manually with `hum:Move(worldDir(), false)` each `RenderStepped`, where `worldDir()`
is built from **WASD keys only**, and jump is **Space only**.

Consequence: **touch and gamepad players have zero movement input.** Only keyboard works. Testers
on phones/tablets or controllers cannot play. This blocks the tester build.

Camera is `CameraType.Custom` following the controlled body's Humanoid. PC play works today, which
means Roblox's default `CameraModule` is already running and handling rotation — so touch-drag and
gamepad right-stick rotation are *expected* to work through the same module (must be verified, not
assumed — see §6).

## 2. Scope

- **In scope:** cross-platform **movement** and **jump** for Touch, Keyboard/Mouse, and Gamepad.
  These are the only two player-driven actions in the game (swaps are server-driven; there is no
  swap button).
- **Out of scope (unless verification fails):** camera rotation input — it is expected to work via
  the existing default CameraModule on all devices. If §6.2 verification fails, camera input
  becomes a separate follow-up, not part of this change.
- **Arena-agnostic:** input handling is independent of arena geometry; nothing here hardcodes
  hex/arena data.

## 3. Approach (C — reuse Roblox controls behind a swappable seam)

Reuse Roblox's battle-tested input for the move vector and jump, but place move-vector acquisition
behind a thin interface so a custom fallback can be swapped in without touching `ClientControl`.

### 3.1 Components

- **`MoveDirection` — new PURE module (`src/shared/`, ReplicatedStorage/Shared).**
  Replaces the inlined `worldDir()` math. Pure, no Roblox APIs (no `Vector3`/`CFrame`), number-in /
  number-out — mirrors [HexGrid.luau](../../src/shared/HexGrid.luau) and
  [SpawnLayout.luau](../../src/shared/SpawnLayout.luau), so it is lune-testable and shipped
  unchanged via Rojo. Named distinctly from the existing `ControlModel` (which is the unrelated
  player↔body bijection/swap logic).

  ```
  MoveDirection.resolve(moveX, moveZ, lookX, lookZ, rightX, rightZ) -> (dx, dz)
  ```

  Semantics (preserves the current mapping): given a camera-relative move vector `(moveX, moveZ)`
  as returned by `GetMoveVector()` (X = strafe, +X right; Z = forward/back, −Z forward) and the
  camera's flattened look/right components, compute:

  ```
  x = rightX * moveX + lookX * (-moveZ)
  z = rightZ * moveX + lookZ * (-moveZ)
  ```

  then normalize `(x, z)`; if magnitude < epsilon (`1e-3`) return `(0, 0)`. This is exactly the
  existing `worldDir()` math generalized from discrete keys to a continuous vector.

- **`InputController` — new client glue module (`src/client/`).** The swappable seam. Interface:
  - `InputController.enable()` — acquire and enable Roblox controls.
  - `InputController.getMoveVector() -> (moveX, moveZ)` — current camera-relative move vector.
  - `InputController.bindJump(onJump: () -> ()) ` — bind a jump action across devices.
  - `InputController.isMoving() -> boolean` — true when the move vector is non-negligible
    (used by the grace-shimmer touch-point in §5).

  Primary implementation:
  - **Move:** `local controls = require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule")):GetControls()`,
    then `controls:Enable()`. `getMoveVector()` returns `controls:GetMoveVector()`'s X and Z.
    `Enable()` is **required** because it is normally called on `CharacterAdded`, which never fires
    here.
  - **Jump:** `ContextActionService:BindAction("BSR_Jump", handler, true, Enum.KeyCode.Space,
    Enum.KeyCode.ButtonA)` — `true` auto-creates the mobile touch button and binds keyboard Space
    and gamepad ButtonA in one call. The handler calls `onJump()` on `Enum.UserInputState.Begin`.

  The interface is what lets a **custom-thumbstick fallback** (§6.1 contingency) replace the
  primary impl without any change to `ClientControl`.

- **`ClientControl` — modified.** Remove the `keys` table and the direct
  `UserInputService.InputBegan/InputEnded` WASD/Space handling. On `start()`:
  `InputController.enable()` and `InputController.bindJump(function() if hum then hum.Jump = true end end)`.
  Each `RenderStepped`: read `InputController.getMoveVector()`, feed it plus the camera's flattened
  look/right into `MoveDirection.resolve`, and call `hum:Move(Vector3.new(dx, 0, dz), false)`.
  Control-assignment / swap-FOV-punch logic (the `SetControlledBody` handler) is unchanged.

### 3.2 Data flow (per RenderStepped)

```
InputController.getMoveVector()  ->  (moveX, moveZ)
        |                                   camera.CFrame look/right (flattened, unit)
        v                                   |
MoveDirection.resolve(moveX, moveZ, lookX, lookZ, rightX, rightZ)  ->  (dx, dz)
        v
hum:Move(Vector3.new(dx, 0, dz), false)   -- client owns the body: predicted
```

Jump is event-driven via the CAS binding (`hum.Jump = true` on Begin) — same effect as today.

## 4. Per-device coverage summary

| Device | Move | Jump | Camera |
|---|---|---|---|
| Keyboard/Mouse | WASD via `GetMoveVector` | Space via CAS | mouse (default CameraModule) |
| Touch | Roblox thumbstick via `GetMoveVector` | auto touch button (CAS) | drag (default CameraModule) — verify §6.2 |
| Gamepad | left stick via `GetMoveVector` | ButtonA via CAS | right stick (default CameraModule) — verify §6.2 |

## 5. Extra touch-point — grace-shimmer "moved" detection

[SoulController.luau](../../src/client/SoulController.luau) (`playGraceShimmer`) currently decides
the cosmetic post-swap shimmer should fade early by watching raw **WASD/Space** via
`UserInputService.InputBegan`. That silently never fires on touch/gamepad, so the shimmer would
misbehave on those devices. Generalize it to detect movement from the unified move vector — e.g.
poll `InputController.isMoving()` (or subscribe to a movement signal) instead of raw key codes.
Cosmetic only; the server still owns the real grace gate.

## 6. Risks & verification (load-bearing)

1. **ControlModule without a Character.** The primary unknown: with `CharacterAutoLoads = false`,
   does `GetControls()` + `Enable()` render the touch thumbstick and return a nonzero move vector?
   Reading only the move vector should be Character-independent, but this **must be verified in
   Studio** (device emulation + a real phone). **Contingency:** the `InputController` seam lets us
   drop in a custom on-screen thumbstick (the touch slice of a fully-custom router) without
   touching `ClientControl`. This is the reason for the seam.

2. **Camera rotation on touch/gamepad.** Verify drag and right-stick rotate the camera through the
   existing default CameraModule. If they do not, camera input is a separate follow-up (out of
   scope here) — call it out in the smoke-test result rather than expanding this change.

## 7. Testing plan

- **Pure (lune):** `tests/move_direction.spec.luau` covering `MoveDirection.resolve`:
  forward / back / strafe-left / strafe-right, diagonals (normalized magnitude ~1), a rotated
  camera (e.g. camera facing +X so "forward" maps to world +X), zero input → `(0, 0)`, and
  sub-epsilon input → `(0, 0)`. All existing specs (17) stay green.
- **Studio MCP checks:** use `execute_luau` to confirm `GetControls()`/`Enable()` return a controls
  object and a live move vector, and that the CAS jump action is bound, before the human run.
- **Smoke-test doc** (`docs/smoke-tests/2026-07-02-cross-platform-controls-smoke-test.md`),
  runtime-unverified until driven by a human, with a per-device checklist:
  - **Touch** (Studio device emulation + a real phone): thumbstick appears and moves the body in
    all directions relative to the camera; jump button appears and jumps; camera drag rotates.
  - **Keyboard** (regression): WASD moves, Space jumps, mouse rotates — unchanged from today.
  - **Gamepad**: left stick moves, ButtonA jumps, right stick rotates.
  - **Grace shimmer**: after a swap, the shimmer fades once you move on each device (§5).
  - `screen_capture` shows only the edit viewport, so the human drives all runtime-UI checks.

## 8. Non-goals / YAGNI

- No custom-themed touch UI for the tester build — Roblox's default thumbstick + auto jump button
  are acceptable and fastest. (The seam keeps a custom UI open as a later option.)
- No sprint/crouch/interact or other new actions — the game has none.
- No camera-input rewrite unless §6.2 verification fails.
