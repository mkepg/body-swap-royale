# Mobile Jump Button Smoke Test (2026-07-10)

Studio device emulation (or a real device). `SOLO_TEST_MODE = true` + `ARENA_OVERRIDE`
as needed for a quick round; `TOUCH_JUMP_FORCE = true` substitutes desktop Play Solo
(MouseButton1 = touch) for the layout-only cases.

- **MJ-1 (phone size/placement):** emulate a phone (min axis ≤ 500). PASS = jump button
  bottom-right with the default art, ~91 px (70 × 1.3), thumbstick bottom-left unaffected.
- **MJ-2 (tablet size/placement):** emulate an iPad (min axis > 500). PASS = same art,
  ~156 px (120 × 1.3), inset per the default large-screen formula.
- **MJ-3 (rotation/resize):** rotate the emulated device (or resize the window under
  TOUCH_JUMP_FORCE). PASS = button re-lays out immediately; crossing the 500 px min-axis
  boundary switches size class.
- **MJ-4 (hold + slide-off):** press and hold = body jumps repeatedly (bunny-hop is the
  established behavior); slide the finger OFF the button then release. PASS = jump stops on
  slide-off release (no stuck jump), pressed art shows only while held.
- **MJ-5 (visibility):** before controlling a body / after elimination (spectate). PASS =
  button hidden exactly when the thumbstick is; reappears on the next body in the NORMAL
  (unpressed) art even if eliminated mid-hold.
- **MJ-6 (desktop/gamepad regression):** normal desktop Play Solo (force flag OFF). PASS =
  no button, Space + gamepad A jump unchanged.
