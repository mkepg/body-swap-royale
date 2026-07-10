# Mobile Jump Button — Default-Replica, Comfort-Scaled, Responsive

**Date:** 2026-07-10
**Status:** 🟢 Approved (user feel-pass report; user approved the default-replica + 1.3× scale approach)
**Branch:** `feat/soul-sweeper-arena`

---

## 1. Report + root cause

**Report:** the mobile jump button is too small; it must grow and adapt across phones and tablets.
Preference: use the default Roblox jump button if possible.

**Root cause:** the button is a ContextActionService touch button (`InputController.setupJump`),
which renders at CAS's small fixed size inside `ContextButtonFrame` and ignores the TouchGui's
form-factor rules. The TRUE default button (PlayerModule `TouchJump`) cannot be used directly:
it is hard-gated on `LocalPlayer.Character`, which this game never sets (ownership-transfer
model, `CharacterAutoLoads = false`) — the documented root cause from the 2026-07 mobile
controls arc. Giving the player a Character to unlock it would ripple through camera/respawn/
control assumptions across the whole model — rejected.

**Engine facts (verified against the live PlayerModule TouchJump source, 2026-07-10, classic
path):** sprite sheet `rbxasset://textures/ui/Input/TouchControlsSheetV2.png`; normal state
rect offset (1, 146), pressed (146, 146), rect size (144, 144); breakpoint
`min(viewport axes) <= 500` → base size **70** px (phones) else **120** px (tablets/desktop
touch); position small: `(1, -(size*1.5 - 10), 1, -size - 20)`, large:
`(1, -(size*1.5 - 10), 1, -size * 1.75)`.

## 2. Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Default-replica button | Replace the CAS button with a self-owned touch-only ImageButton in `PlayerGui.BSRTouchJump` replicating the default exactly: same sprite-sheet art + pressed state, same breakpoint, same position formulas (§1 engine facts). Familiar look + placement; none of the CAS sizing quirks. |
| 2 | Comfort scale | `Config.TOUCH_JUMP_SCALE = 1.3` multiplies the base SIZE only (≈91 px phones / 156 px tablets); the default position FORMULAS take the scaled size, so margins grow with the button and it can never leave the screen. 1.0 = exact default. Feel-tunable. |
| 3 | Pure layout module | `TouchJumpLayout.compute(viewportX, viewportY, scale)` → `{ size, xOffset, yOffset, isSmallScreen }` (plain numbers, Roblox-free, lune-tested; asserts on non-positive scale). Glue converts to UDim2. |
| 4 | Responsive | Re-apply layout on every `Camera.ViewportSize` change (rotation, resize), rebinding through `workspace.CurrentCamera` replacement (`GetPropertyChangedSignal("CurrentCamera")`) so a recreated camera can't orphan the listener. |
| 5 | Input tracking | Track the initiating touch's `InputObject`: `button.InputBegan` (Touch, or MouseButton1 under the force flag) sets it + `jumpHeld = true` + pressed art; `UserInputService.InputEnded` on THAT object releases — sliding the finger off the button still releases the jump. The load-bearing `RenderPriority.Last` re-assert of `humanoid.Jump` is unchanged. |
| 6 | Visibility | Tied to the same humanoid binding as the default thumbstick: shown in `ensureControls` (on humanoid bind), hidden + `jumpHeld = false` in `releaseControls` (spectate/eliminated). Starts hidden. |
| 7 | Dev verifiability | `Config.TOUCH_JUMP_FORCE = false` (SOLO_TEST_MODE-style): when true the button renders on non-touch devices with MouseButton1 standing in for touch, so layout is verifiable in desktop Play Solo via MCP (screen capture can't see PlayerGui). Leave false. |
| 8 | Removed | The entire CAS path: `BindAction("BSR_Jump", ...)`, `SetImage`, `SetTitle`. Desktop Space / gamepad A jump stays with the ControlModule's own controllers (untouched). |

## 3. Verification

- **Lune:** `tests/touch_jump_layout.spec.luau` — phone/tablet sizes at scale 1 (70/120) and
  1.3 (91/156), exact offsets from the default formulas, the ≤500 boundary (500 small, 501
  large), portrait orientation, non-positive scale asserts.
- **Studio MCP (live):** with `TOUCH_JUMP_FORCE = true` in Play Solo — button exists under
  PlayerGui, AbsoluteSize/AbsolutePosition match `TouchJumpLayout.compute` for the current
  viewport; visible only while controlling a body (hidden pre-round if applicable); flip back.
- **User (final):** Studio device emulator (phone + iPad) and/or a real device — size feels
  comfortable, sits where the default sits, rotation re-layouts, slide-off releases the jump,
  desktop/gamepad unchanged.

## 4. Risks

1. Engine art/layout constants can drift with PlayerModule updates (the source shows a newer
   variant path: 72/120 with different insets behind what looks like a flag). We pin the
   classic-path values; a future engine flag flip changes only the DEFAULT button's look —
   ours keeps working, at worst slightly off the new fashion. Comment records the source +
   date.
2. Bottom-right HUD collisions (economy HUD etc.) — the default position is where mobile
   players expect the button; if anything overlaps on small screens the OTHER element should
   move. User feel pass owns the call.
