# Mobile Jump Button Implementation Plan

**Goal:** Replace the too-small ContextActionService touch jump button with a self-owned replica of Roblox's default TouchJump button — same art/placement/breakpoints, comfort-scaled 1.3×, responsive to viewport changes.

**Architecture:** A pure `TouchJumpLayout` module (Roblox-free, lune-tested) computes size/offsets from the default TouchJump's verified engine rules; `InputController` builds the ImageButton, re-applies layout on ViewportSize changes, tracks the initiating touch InputObject, and keeps the existing `RenderPriority.Last` jump re-assert. Visibility follows the humanoid binding like the default thumbstick.

**Tech Stack:** Luau (Rojo), lune tests, Studio MCP for live verification.

**Spec:** `docs/specs/2026-07-10-mobile-jump-button-design.md`

---

## ⚠️ Commit hygiene — dev flips (EVERY task that stages Config)

`src/shared/Config.luau` carries two UNCOMMITTED dev flips that must NEVER land in a commit:
`Config.SOLO_TEST_MODE = true` and `Config.ARENA_OVERRIDE = "sweeper"`.
When staging Config: (1) edit both to production values (`false`, `""`); (2) `git add` explicit
paths only; (3) restore the flips in the working tree; (4) verify
`git diff --cached src/shared/Config.luau | grep -E "^[+-]Config\.(SOLO_TEST_MODE|ARENA_OVERRIDE)"`
prints nothing; (5) commit.

Test command prefix (Git Bash): `export PATH="$HOME/.rokit/bin:$PATH"`

---

### Task 1: Pure `TouchJumpLayout` + Config knobs

**Files:**
- Create: `src/shared/TouchJumpLayout.luau`
- Create: `tests/touch_jump_layout.spec.luau`
- Modify: `src/shared/Config.luau` (insert before the `-- Movement, normalized so avatar choice never confers an advantage.` comment block)

- [ ] **Step 1: Write the failing test**

Create `tests/touch_jump_layout.spec.luau`:

```lua
local M = require("../src/shared/TouchJumpLayout")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- Default sizes at scale 1 reproduce the engine's TouchJump exactly
-- (verified against the live PlayerModule source 2026-07-10, classic path).
do
	local phone = M.compute(844, 390, 1) -- landscape phone: minAxis 390 <= 500
	expect(phone.isSmallScreen == true, "phone -> small screen")
	expect(phone.size == 70, "phone base size 70")
	expect(near(phone.xOffset, -(70 * 1.5 - 10)), "phone xOffset = -(size*1.5-10)")
	expect(near(phone.yOffset, -70 - 20), "phone yOffset = -size-20")

	local tablet = M.compute(1180, 820, 1) -- iPad-class: minAxis 820 > 500
	expect(tablet.isSmallScreen == false, "tablet -> large screen")
	expect(tablet.size == 120, "tablet base size 120")
	expect(near(tablet.xOffset, -(120 * 1.5 - 10)), "tablet xOffset formula")
	expect(near(tablet.yOffset, -120 * 1.75), "tablet yOffset = -size*1.75")
	print("touchjump: default sizes OK")
end

-- Comfort scale multiplies SIZE; the position formulas take the scaled size
-- (margins grow with the button -- it can never leave the screen).
do
	local phone = M.compute(844, 390, 1.3)
	expect(phone.size == 91, "70 * 1.3 rounds to 91")
	expect(near(phone.xOffset, -(91 * 1.5 - 10)), "scaled phone xOffset uses scaled size")
	expect(near(phone.yOffset, -91 - 20), "scaled phone yOffset uses scaled size")
	local tablet = M.compute(1180, 820, 1.3)
	expect(tablet.size == 156, "120 * 1.3 = 156")
	expect(near(tablet.yOffset, -156 * 1.75), "scaled tablet yOffset uses scaled size")
	print("touchjump: comfort scale OK")
end

-- Breakpoint boundary + orientation: min axis decides, exactly at <= 500.
do
	expect(M.compute(2000, 500, 1).isSmallScreen == true, "minAxis 500 -> small (inclusive)")
	expect(M.compute(2000, 501, 1).isSmallScreen == false, "minAxis 501 -> large")
	expect(M.compute(390, 844, 1).isSmallScreen == true, "portrait phone -> small (min of both axes)")
	print("touchjump: breakpoint OK")
end

-- Bad scale fails loudly (never a silently invisible/garbage button).
do
	expect(not pcall(M.compute, 844, 390, 0), "scale 0 -> errors")
	expect(not pcall(M.compute, 844, 390, -1), "negative scale -> errors")
	print("touchjump: scale guard OK")
end

print("ALL TouchJumpLayout TESTS PASSED")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/touch_jump_layout.spec.luau`
Expected: FAIL (module does not exist)

- [ ] **Step 3: Implement the module**

Create `src/shared/TouchJumpLayout.luau`:

```lua
--[[
	TouchJumpLayout -- PURE layout math for the mobile jump button.
	Location (Roblox): ReplicatedStorage/Shared/TouchJumpLayout (ModuleScript)

	No Roblox globals (lune-tested). Reproduces the DEFAULT TouchJump button's
	form-factor rules -- verified against the live PlayerModule TouchJump source
	2026-07-10 (classic path): breakpoint min(viewport axes) <= 500; base size
	70 px (small screens / phones) else 120 px (tablets+); position offsets
	small: (-(size*1.5 - 10), -size - 20), large: (-(size*1.5 - 10), -size*1.75)
	from the bottom-right corner. `scale` multiplies SIZE only; the position
	formulas take the scaled size, so margins grow with the button and it can
	never leave the screen. The glue (InputController) converts to UDim2.
--]]

local TouchJumpLayout = {}

function TouchJumpLayout.compute(viewportX, viewportY, scale)
	assert(type(scale) == "number" and scale > 0,
		"TouchJumpLayout.compute: scale must be a positive number")
	local minAxis = math.min(viewportX, viewportY)
	local isSmallScreen = minAxis <= 500
	local size = math.floor((isSmallScreen and 70 or 120) * scale + 0.5)
	return {
		size = size,
		xOffset = -(size * 1.5 - 10),
		yOffset = isSmallScreen and (-size - 20) or (-size * 1.75),
		isSmallScreen = isSmallScreen,
	}
end

return TouchJumpLayout
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/touch_jump_layout.spec.luau`
Expected: PASS — `ALL TouchJumpLayout TESTS PASSED`

- [ ] **Step 5: Add the two Config knobs**

In `src/shared/Config.luau`, insert directly ABOVE the line
`-- Movement, normalized so avatar choice never confers an advantage.`:

```lua
-- ===== Mobile touch jump button (2026-07-10) =====
-- The DEFAULT TouchJump button never renders in this game (it is hard-gated on
-- LocalPlayer.Character, which the ownership-transfer model never sets), so
-- InputController builds a replica: the same engine sprite-sheet art + the
-- default form-factor layout rules (pure TouchJumpLayout, lune-tested), with
-- the SIZE scaled by TOUCH_JUMP_SCALE for comfort. 1.0 = exact default
-- (70 px phones / 120 px tablets -- too small per the 2026-07-10 mobile feel
-- pass); 1.3 => ~91 px phones / 156 px tablets. Feel-tunable.
Config.TOUCH_JUMP_SCALE = 1.3
-- Dev/test switch (like SOLO_TEST_MODE, NOT a gameplay tunable): when true the
-- touch jump button also renders on non-touch devices, with MouseButton1
-- standing in for touch, so layout is verifiable in desktop Play Solo (Studio
-- MCP cannot see PlayerGui via screen capture). Leave false.
Config.TOUCH_JUMP_FORCE = false

```

- [ ] **Step 6: Full lune suite**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: all 25 suites pass, exit 0

- [ ] **Step 7: Commit (dev-flip hygiene — Config is staged)**

```bash
git add src/shared/TouchJumpLayout.luau tests/touch_jump_layout.spec.luau src/shared/Config.luau docs/specs/2026-07-10-mobile-jump-button-design.md docs/plans/2026-07-10-mobile-jump-button.md
git commit -m "feat(mobile): pure TouchJumpLayout (default TouchJump rules, comfort scale)"
```

---

### Task 2: InputController — default-replica button, CAS removed

**Files:**
- Modify: `src/client/InputController.luau`

- [ ] **Step 1: Replace the module's requires/locals header**

Replace:

```lua
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local InputController = {}

local controls = nil          -- the PlayerModule ControlModule
local MOVE_EPSILON_SQ = 0.01  -- treat |move| below this as "not moving"
local jumpHeld = false         -- touch jump button held (see setupJump)
```

with:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TouchJumpLayout = require(Shared:WaitForChild("TouchJumpLayout"))

local LocalPlayer = Players.LocalPlayer

local InputController = {}

local controls = nil          -- the PlayerModule ControlModule
local MOVE_EPSILON_SQ = 0.01  -- treat |move| below this as "not moving"
local jumpHeld = false         -- touch jump button held (see setupJump)
local jumpButton = nil         -- our default-replica ImageButton (touch / TOUCH_JUMP_FORCE)

-- The default TouchJump button's engine art (verified against the live
-- PlayerModule source 2026-07-10): one sprite sheet, normal + pressed rects.
local TOUCH_SHEET = "rbxasset://textures/ui/Input/TouchControlsSheetV2.png"
local RECT_NORMAL = Vector2.new(1, 146)
local RECT_PRESSED = Vector2.new(146, 146)
local RECT_SIZE = Vector2.new(144, 144)
```

- [ ] **Step 2: Wire visibility into the existing bind/release points**

In `ensureControls`, replace:

```lua
	if humanoid and controls.humanoid ~= humanoid then
		controls:OnCharacterAdded(body)
	end
```

with:

```lua
	if humanoid and controls.humanoid ~= humanoid then
		controls:OnCharacterAdded(body)
		if jumpButton then
			jumpButton.Visible = true
		end
	end
```

In `releaseControls`, replace:

```lua
	if controls and controls.humanoid ~= nil then
		controls:OnCharacterRemoving()
	end
```

with:

```lua
	if controls and controls.humanoid ~= nil then
		controls:OnCharacterRemoving()
		if jumpButton then
			jumpButton.Visible = false
		end
		jumpHeld = false
	end
```

- [ ] **Step 3: Replace `setupJump` (and its doc comment) entirely**

Replace everything from the comment line
`-- Jump. Desktop (Space) and gamepad (ButtonA) already jump via the ControlModule's`
down to the end of the current `setupJump` function (its closing `end`) with:

```lua
-- Jump. Desktop (Space) and gamepad (ButtonA) already jump via the ControlModule's
-- own controllers, which set `humanoid.Jump` in its Input-priority render step. TOUCH
-- is the gap: Roblox's default TouchJump button is hard-gated on LocalPlayer.Character
-- (via CharacterUtil), which this game never has, so it never renders. So we build a
-- REPLICA of the default button (spec 2026-07-10): same engine sprite-sheet art +
-- pressed state, and the default form-factor layout rules via the pure
-- TouchJumpLayout (size comfort-scaled by Config.TOUCH_JUMP_SCALE), re-applied on
-- every viewport change. (The old ContextActionService button was CAS-small and
-- ignored those rules -- the 2026-07-10 "too small on mobile" report.)
--
-- The catch (unchanged from the CAS era): because we feed the ControlModule our
-- body's humanoid (for the thumbstick), its render step writes `humanoid.Jump =
-- false` every frame on touch. A one-shot `Jump = true` would be stomped. So we
-- re-assert `Jump = true` while the button is held at Last render priority (2000),
-- which runs AFTER the ControlModule's Input step (100) -- our write wins.
--
-- Hold tracking follows the initiating touch's InputObject via UserInputService.
-- InputEnded: releasing OFF the button (finger slid away) still releases the jump,
-- which button-local InputEnded alone would miss.
function InputController.setupJump()
	if not (UserInputService.TouchEnabled or Config.TOUCH_JUMP_FORCE) then
		return -- keyboard/gamepad jump is the ControlModule's; no on-screen button
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "BSRTouchJump"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.Parent = playerGui

	local button = Instance.new("ImageButton")
	button.Name = "JumpButton"
	button.BackgroundTransparency = 1
	button.Image = TOUCH_SHEET
	button.ImageRectOffset = RECT_NORMAL
	button.ImageRectSize = RECT_SIZE
	button.Visible = false -- shown by ensureControls once a body is bound
	button.Parent = gui
	jumpButton = button

	-- Layout: the pure module's numbers -> UDim2, re-applied on every viewport
	-- change, re-bound if the Camera instance itself is ever replaced.
	local function applyLayout()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vps = cam.ViewportSize
		local l = TouchJumpLayout.compute(vps.X, vps.Y, Config.TOUCH_JUMP_SCALE)
		button.Size = UDim2.new(0, l.size, 0, l.size)
		button.Position = UDim2.new(1, l.xOffset, 1, l.yOffset)
	end
	local function bindCamera()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
		end
		applyLayout()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()

	-- Hold tracking (see doc comment above). MouseButton1 only matters under
	-- TOUCH_JUMP_FORCE (desktop layout verification).
	local activeInput = nil
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeInput = input
			jumpHeld = true
			button.ImageRectOffset = RECT_PRESSED
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == activeInput then
			activeInput = nil
			jumpHeld = false
			button.ImageRectOffset = RECT_NORMAL
		end
	end)

	RunService:BindToRenderStep("BSR_JumpReassert", Enum.RenderPriority.Last.Value, function()
		if jumpHeld and controls and controls.humanoid then
			controls.humanoid.Jump = true
		end
	end)
end
```

- [ ] **Step 4: Update the file-header comment**

In the header block comment, replace the sentence fragment
`So we add a` / `TOUCH-ONLY jump button (default jump art) via ContextActionService.`
(end of the third paragraph, lines ~97-99 reference this in the old setupJump comment — in the
HEADER it is the paragraph mentioning the touch HUD; only edit if the header mentions
ContextActionService) — check with `grep -n "ContextActionService" src/client/InputController.luau`;
after Steps 1-3 the ONLY remaining match must be inside the setupJump doc comment's
parenthetical about the old CAS button. If the header has no CAS mention, skip this step.

- [ ] **Step 5: Verify no stale references**

Run: `grep -n "ContextActionService\|BSR_Jump\"" src/client/InputController.luau`
Expected: no `GetService("ContextActionService")`, no `BindAction`, no `SetImage`/`SetTitle`;
the string `BSR_JumpReassert` remains (render-step name), and prose mentions of the old CAS
button in comments are fine.

- [ ] **Step 6: Full lune suite (regression guard — client glue has no lune coverage)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: all 25 pass

- [ ] **Step 7: Commit (Config NOT staged — no flip dance)**

```bash
git add src/client/InputController.luau
git commit -m "feat(mobile): default-replica touch jump button (responsive, comfort-scaled; CAS button removed)"
```

---

### Task 3: Docs — CHANGELOG + smoke doc

**Files:**
- Modify: `CHANGELOG.md` (new `## [2026-07-10]` section at the top, above `## [2026-07-09]`)
- Create: `docs/smoke-tests/2026-07-10-mobile-jump-button-smoke-test.md`

- [ ] **Step 1: CHANGELOG**

Insert directly below the `The format is based on...` line and its trailing blank line (i.e., as
the new FIRST version section):

```markdown
## [2026-07-10]

### Added
- **Mobile jump button — default-replica, comfort-scaled, responsive.** Feel-pass report: the
  touch jump button was too small. Root cause: it was a ContextActionService button (CAS-small,
  ignores the TouchGui form-factor rules); the TRUE default TouchJump can't render here (hard-
  gated on `LocalPlayer.Character`, which the ownership-transfer model never sets). Fixed:
  `InputController` now builds a replica of the default button — same engine sprite-sheet art
  (normal + pressed), same ≤500 px min-axis breakpoint and position formulas (verified against
  the live PlayerModule source) — sized by pure `TouchJumpLayout` (lune-tested) ×
  `Config.TOUCH_JUMP_SCALE = 1.3` (≈91 px phones / 156 px tablets; 1.0 = exact default), re-laid
  out on every viewport change (rotation/resize, camera-replacement safe). Hold tracking follows
  the initiating touch's InputObject (slide-off releases); the `RenderPriority.Last`
  `humanoid.Jump` re-assert is unchanged; visibility follows the humanoid binding like the
  default thumbstick (hides when spectating). `TOUCH_JUMP_FORCE` dev flag renders it on desktop
  for Studio verification. CAS jump button fully removed. See
  [spec](../specs/2026-07-10-mobile-jump-button-design.md) and
  [plan](../plans/2026-07-10-mobile-jump-button.md).
```

- [ ] **Step 2: Smoke doc**

Create `docs/smoke-tests/2026-07-10-mobile-jump-button-smoke-test.md`:

```markdown
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
  button hidden exactly when the thumbstick is; reappears on the next body.
- **MJ-6 (desktop/gamepad regression):** normal desktop Play Solo (force flag OFF). PASS =
  no button, Space + gamepad A jump unchanged.
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md docs/smoke-tests/2026-07-10-mobile-jump-button-smoke-test.md
git commit -m "docs(mobile): jump button CHANGELOG + smoke test"
```

---

## Live verification (MAIN SESSION — not a subagent task)

1. Confirm Rojo synced (`TouchJumpLayout` present in ReplicatedStorage.Shared, InputController
   Source contains `BSRTouchJump`).
2. Flip `TOUCH_JUMP_FORCE = true` (working tree only), Play Solo; via Client `execute_luau`:
   button exists, `Visible` true while controlling a body, `AbsoluteSize`/`AbsolutePosition`
   match `TouchJumpLayout.compute(viewport)`; optionally `user_mouse_input` click-hold on the
   button center and confirm the body jumps. Stop, flip back to false.
3. MJ-1..3 + MJ-4/5 as far as emulation allows; the user owns the real-device feel pass and
   the final TOUCH_JUMP_SCALE verdict.
