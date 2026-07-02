# Smoke Test — Cross-Platform Controls (2026-07-02)

**Status:** RUNTIME-UNVERIFIED until run in Studio + on a real phone.
**Covers:** the client glue lune can't test — `InputController` (PlayerModule move
vector + ContextActionService jump) and `ClientControl` driving the assigned body
across Touch, Keyboard/Mouse, and Gamepad. Pure `MoveDirection` math is lune-covered.

**Spec:** `docs/superpowers/specs/2026-07-02-cross-platform-controls-design.md`

**Note on `screen_capture`:** the MCP `screen_capture` tool renders only the edit
viewport, not the running Play client. All checks below require the human to drive
the actual Play session (and a real phone for touch).

## Load-bearing pre-check (spec §6.1) — ControlModule without a Character

**Live result (2026-07-02, desktop, via MCP execute_luau in a Play session):** PASS.
With `LocalPlayer.Character == nil`, `require(PlayerScripts.PlayerModule):GetControls()`
returned a controls object, `controls:Enable()` ran without error, and
`controls:GetMoveVector()` returned a `Vector3` (0,0,0 with no key held). The
ControlModule is usable without a Character, so the primary approach stands (the
custom-thumbstick contingency is NOT needed). Still to confirm by a human: a NONZERO
move vector while input is held, and the touch thumbstick rendering under emulation /
on a real phone.

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
