# HUD Theme & Coherence (kid-friendly skin) Implementation Plan

**Goal:** Introduce one shared `HudTheme` source of truth for HUD zones/caps/fonts/colors/panel-styling, migrate every HUD element onto it, and apply a kid-friendly (Natural Disaster Survival vibe) skin.

**Architecture:** A new client-only `HudTheme` module holds presentation constants + small helpers (`placeInZone`, `applyMaxSize`, `styleText`, `makePanel`, `setPanelAccent`, `setPanelFlat`, `popIn`). `ClientSwapHud` and `ClientRoundHud` are migrated to render through it. `HudTheme` maps the semantic accent strings the pure `RoundScreenModel` already returns to concrete colors, so the pure models stay Roblox-free.

**Tech Stack:** Luau, Rojo, Roblox GUI (`UICorner`/`UIStroke`/`UIGradient`/`UISizeConstraint`/`UIScale`/`TweenService`). Client modules are children of the `Client` LocalScript (require siblings via `script.Parent:WaitForChild(...)`).

**Spec:** `docs/specs/2026-06-21-hud-theme-coherence-design.md`

> **Testing note:** `HudTheme` and the two client modules use Roblox types (`Color3`/`Enum`/`Instance`/`TweenService`) and therefore **cannot run under lune** — only the Roblox-free decision modules do. So their "verify" steps run the existing pure lune suite as a tooling sanity check, and the real runtime validation is the Studio smoke test in Task 4 (manual, run by the human). This mirrors how the bookends plan handled the Roblox-only client/server files.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/client/HudTheme.luau` | **new** — single source of truth: fonts, colors, caps, zones, panel styling + helpers |
| `src/client/ClientSwapHud.luau` | migrate timer + big countdown onto `HudTheme`; set `DisplayOrder` |
| `src/client/ClientRoundHud.luau` | migrate banner / dark bottom pill / eliminated notice onto `HudTheme`; remove inline `ACCENT`; state-colored panel; pop-in |
| `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md` | extend with HUD-consistency + kid-friendly checks (desktop + mobile) |

---

## Task 1: Create `HudTheme` (the source of truth)

**Files:**
- Create: `src/client/HudTheme.luau`

- [ ] **Step 1: Write the module**

Create `src/client/HudTheme.luau` with EXACTLY this content:

```lua
--[[
	HudTheme -- the single source of truth for the on-screen HUD look.
	Location: StarterPlayerScripts/Client/HudTheme  (ModuleScript; child of Client)

	Client-only presentation constants + small helpers shared by ClientRoundHud
	and ClientSwapHud, so HUD zones / size caps / fonts / colors / panel styling
	live in ONE place and can't drift element-by-element. Holds Roblox types
	(Color3/Enum/UDim/Instance), so it is NOT lune-tested -- the pure decision
	modules (RoundScreenModel/SwapTelegraphModel) stay Roblox-free and own the
	logic; this module only styles. Kid-friendly skin: chunky, bright, rounded.

	Maps the semantic accent strings RoundScreenModel returns
	("neutral" | "win" | "lose") to concrete panel colors.
--]]

local TweenService = game:GetService("TweenService")

local HudTheme = {}

HudTheme.Font = {
	title = Enum.Font.FredokaOne,
	heading = Enum.Font.FredokaOne,
	body = Enum.Font.GothamMedium,
}

HudTheme.Color = {
	textPrimary = Color3.fromRGB(255, 255, 255),
	textStroke = Color3.fromRGB(20, 24, 31),
	panelStroke = Color3.fromRGB(255, 255, 255),
	shadow = Color3.fromRGB(0, 0, 0),
	pill = Color3.fromRGB(255, 210, 63),
	pillText = Color3.fromRGB(90, 61, 0),
	panelDark = Color3.fromRGB(17, 22, 31),
}

-- semantic accent -> panel gradient stops { top, bottom }
HudTheme.Accent = {
	neutral = { top = Color3.fromRGB(58, 160, 240), bottom = Color3.fromRGB(47, 127, 208) },
	win = { top = Color3.fromRGB(56, 210, 122), bottom = Color3.fromRGB(30, 167, 92) },
	lose = { top = Color3.fromRGB(240, 88, 78), bottom = Color3.fromRGB(200, 58, 50) },
}

-- pixel max sizes (the bottom pill never exceeds the banner)
HudTheme.Cap = {
	banner = Vector2.new(340, 150),
	bottomLine = Vector2.new(240, 66),
	notice = Vector2.new(320, 80),
	timer = Vector2.new(120, 76),
}

-- named screen zones: { anchor, position }
HudTheme.Zone = {
	top = { anchor = Vector2.new(0.5, 0), position = UDim2.new(0.5, 0, 0, 14) },
	topTimer = { anchor = Vector2.new(0.5, 0), position = UDim2.fromScale(0.5, 0.04) },
	center = { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.40) },
	notice = { anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.62) },
	bottom = { anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 0.97, 0) },
}

HudTheme.Radius = UDim.new(0, 18)
HudTheme.PanelStrokeThickness = 4
HudTheme.TextStrokeThickness = 2
HudTheme.ShadowOffset = 6
HudTheme.PopInTime = 0.25
HudTheme.DisplayOrder = { swap = 5, bookend = 10 }

-- Place a GUI object into a named zone (anchor + position).
function HudTheme.placeInZone(guiObject, zoneKey)
	local z = HudTheme.Zone[zoneKey]
	guiObject.AnchorPoint = z.anchor
	guiObject.Position = z.position
end

-- Cap a GUI object's pixel size so it never balloons on desktop/ultrawide.
function HudTheme.applyMaxSize(guiObject, capKey)
	local c = Instance.new("UISizeConstraint")
	c.MaxSize = HudTheme.Cap[capKey]
	c.Parent = guiObject
	return c
end

-- Consistent readable text: themed font, white fill, dark outline, scaled.
function HudTheme.styleText(label, fontKey)
	label.Font = HudTheme.Font[fontKey]
	label.TextColor3 = HudTheme.Color.textPrimary
	label.TextScaled = true
	label.TextStrokeTransparency = 1 -- the UIStroke below replaces the built-in stroke
	local s = Instance.new("UIStroke")
	s.Thickness = HudTheme.TextStrokeThickness
	s.Color = HudTheme.Color.textStroke
	s.Parent = label
	return s
end

-- Build a chunky themed panel (root > shadow + panel) in `parent`, sized `size`,
-- placed in `zoneKey` and capped by `capKey`. Parent your content into `.panel`;
-- recolor via setPanelAccent/setPanelFlat; pop it in via popIn(handle.root).
-- The shadow is an offset dark sibling BEHIND the panel (Sibling ZIndexBehavior).
function HudTheme.makePanel(parent, size, zoneKey, capKey)
	local root = Instance.new("Frame")
	root.Name = "PanelRoot"
	root.BackgroundTransparency = 1
	root.Size = size
	HudTheme.placeInZone(root, zoneKey)
	if capKey then
		HudTheme.applyMaxSize(root, capKey)
	end
	root.Parent = parent

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.new(0, 0, 0, HudTheme.ShadowOffset)
	shadow.BackgroundColor3 = HudTheme.Color.shadow
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	local sc = Instance.new("UICorner")
	sc.CornerRadius = HudTheme.Radius
	sc.Parent = shadow
	shadow.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = HudTheme.Color.textPrimary -- white; the gradient tints it
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	local pc = Instance.new("UICorner")
	pc.CornerRadius = HudTheme.Radius
	pc.Parent = panel
	local ps = Instance.new("UIStroke")
	ps.Thickness = HudTheme.PanelStrokeThickness
	ps.Color = HudTheme.Color.panelStroke
	ps.Parent = panel
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = panel
	panel.Parent = root

	return { root = root, panel = panel, gradient = gradient }
end

-- Color the panel from a semantic accent (top->bottom gradient).
function HudTheme.setPanelAccent(handle, accentKey)
	local a = HudTheme.Accent[accentKey] or HudTheme.Accent.neutral
	handle.gradient.Color = ColorSequence.new(a.top, a.bottom)
end

-- Color the panel a single flat color (used for the neutral dark bottom pill).
function HudTheme.setPanelFlat(handle, color)
	handle.gradient.Color = ColorSequence.new(color)
end

-- Bouncy entrance: scale the whole panel 0 -> 1 with Back/Out.
function HudTheme.popIn(root)
	local scale = root:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = root
	end
	scale.Scale = 0
	TweenService:Create(
		scale,
		TweenInfo.new(HudTheme.PopInTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

return HudTheme
```

- [ ] **Step 2: Tooling sanity check**

`HudTheme` is Roblox-only (cannot run under lune). Confirm the pure suite still runs:
Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec`
Expected: PASS (`ALL RoundScreenModel TESTS PASSED`). Then re-read the module and confirm: every `HudTheme.Cap`/`Zone`/`Accent` key referenced by later tasks exists (`banner`, `bottomLine`, `notice`, `timer`; `top`, `topTimer`, `center`, `notice`, `bottom`; `neutral`, `win`, `lose`), and helper names are exactly `placeInZone`, `applyMaxSize`, `styleText`, `makePanel`, `setPanelAccent`, `setPanelFlat`, `popIn`.

- [ ] **Step 3: Commit**

```bash
git add src/client/HudTheme.luau
git commit -m "feat(ui): HudTheme single source of truth for HUD zones/caps/skin"
```

---

## Task 2: Migrate `ClientSwapHud` onto `HudTheme`

**Files:**
- Modify (full overwrite): `src/client/ClientSwapHud.luau`

This keeps ALL behavior (flash, RenderStepped intensity, one-shot sound, telegraph timing) identical — only the timer and big-countdown styling/placement move to `HudTheme`, plus a `DisplayOrder`.

- [ ] **Step 1: Overwrite the file**

Overwrite `src/client/ClientSwapHud.luau` with EXACTLY this content:

```lua
--[[
	ClientSwapHud -- the always-visible swap countdown + the T-3s telegraph.
	Location: StarterPlayerScripts/Client/ClientSwapHud  (ModuleScript)

	Reads `swapAtServerTime` off RoundStateChanged and renders via the pure
	SwapTelegraphModel: a small top-center timer always during Active, and during
	the last PREVIEW_SECONDS a ramping orange->red flash + a big centered 3/2/1 +
	a one-shot audio cue (Config.SWAP_WARNING_SOUND_ID; silent if "").

	Look (zones/caps/fonts) comes from the shared HudTheme; behavior is unchanged.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SwapTelegraphModel = require(Shared:WaitForChild("SwapTelegraphModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RoundStateChanged = Remotes.get("RoundStateChanged")

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

local ClientSwapHud = {}
local player = Players.LocalPlayer

local phase = "Lobby"
local swapAtServerTime = nil
local lastBigInt = nil
local warningSound = nil

function ClientSwapHud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SwapHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = HudTheme.DisplayOrder.swap
	gui.Parent = player:WaitForChild("PlayerGui")

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Config.TELEGRAPH_FLASH_COLOR
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = gui

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.Size = UDim2.fromScale(0.16, 0.08)
	timer.BackgroundTransparency = 1
	timer.Text = ""
	timer.ZIndex = 2
	HudTheme.placeInZone(timer, "topTimer")
	HudTheme.applyMaxSize(timer, "timer")
	HudTheme.styleText(timer, "heading")
	timer.Parent = gui

	local big = Instance.new("TextLabel")
	big.Name = "BigCountdown"
	big.Size = UDim2.fromScale(0.3, 0.3)
	big.BackgroundTransparency = 1
	big.Text = ""
	big.ZIndex = 2
	HudTheme.placeInZone(big, "center")
	HudTheme.styleText(big, "title")
	big.Parent = gui

	if Config.SWAP_WARNING_SOUND_ID ~= "" then
		warningSound = Instance.new("Sound")
		warningSound.Name = "SwapWarning"
		warningSound.SoundId = Config.SWAP_WARNING_SOUND_ID
		warningSound.Parent = SoundService
	end

	RoundStateChanged.OnClientEvent:Connect(function(state)
		phase = state.phase
		if state.swapAtServerTime then
			swapAtServerTime = state.swapAtServerTime
		end
		if phase ~= "Active" then
			swapAtServerTime = nil
			lastBigInt = nil
		end
	end)

	RunService.RenderStepped:Connect(function()
		if phase ~= "Active" or not swapAtServerTime then
			flash.BackgroundTransparency = 1
			timer.Text = ""
			big.Text = ""
			return
		end

		local secondsUntilSwap = swapAtServerTime - workspace:GetServerTimeNow()
		local d = SwapTelegraphModel.display(secondsUntilSwap, Config.PREVIEW_SECONDS)

		timer.Text = d.timerText

		-- Flash follows telegraph intensity, independent of the number, so it stays
		-- visible through the swap moment (bigCountdownInt is already nil by then and
		-- flashAlpha is held at peak until the next cycle's deadline arrives).
		if d.inPreview then
			flash.BackgroundTransparency = 1 - (d.flashAlpha * 0.5) -- up to 50% opaque
		else
			flash.BackgroundTransparency = 1
		end

		if d.bigCountdownInt then
			big.Text = tostring(d.bigCountdownInt)
			if d.bigCountdownInt ~= lastBigInt then
				lastBigInt = d.bigCountdownInt
				if warningSound and d.bigCountdownInt == Config.PREVIEW_SECONDS then
					warningSound:Play() -- one shot at telegraph entry
				end
			end
		else
			big.Text = ""
		end
	end)
end

return ClientSwapHud
```

- [ ] **Step 2: Tooling sanity check**

Roblox-only file; confirm tooling + the `HudTheme` require path:
Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/swap_telegraph_model.spec`
Expected: PASS (`ALL SwapTelegraphModel TESTS PASSED`). Then confirm `src/client/HudTheme.luau` exists (sibling) so `script.Parent:WaitForChild("HudTheme")` resolves, and re-read the diff to confirm only timer/big styling + `DisplayOrder` changed and the flash/RenderStepped/sound logic is byte-for-byte the same as before.

- [ ] **Step 3: Commit**

```bash
git add src/client/ClientSwapHud.luau
git commit -m "feat(ui): migrate swap HUD timer + big countdown onto HudTheme"
```

---

## Task 3: Migrate `ClientRoundHud` onto `HudTheme` (kid-friendly bookend)

**Files:**
- Modify (full overwrite): `src/client/ClientRoundHud.luau`

Behavior (what shows when, spectate retarget, Active-only notice + cross-remote guard, phase-based clear) is preserved. Rendering becomes: a state-colored chunky banner panel, a yellow WINNER pill, a dark bottom pill, a red eliminated notice in its own zone, and pop-in on show.

- [ ] **Step 1: Overwrite the file**

Overwrite `src/client/ClientRoundHud.luau` with EXACTLY this content:

```lua
--[[
	ClientRoundHud -- round-flow bookend banner (Lobby + Results) renderer.
	Location: StarterPlayerScripts/Client/ClientRoundHud  (ModuleScript)

	Draws the keep-arena-visible banner from RoundStateChanged. WHAT to show is the
	pure RoundScreenModel's decision; this module only renders it (kid-friendly skin
	via HudTheme). Also keeps the spectator-camera retarget and a brief "you were
	eliminated" notice (Active-phase only -- the banner owns the screen during
	Lobby/Ended).

	Started once per client (LocalScript lifetime); all event connections live for
	the session, matching ClientSwapHud and SoulController.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RoundScreenModel = require(Shared:WaitForChild("RoundScreenModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

local ClientRoundHud = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- A stacked text line inside a panel. scaleY is its share of the panel height.
local function panelLabel(parent, name, scaleY, order)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.92, scaleY)
	l.LayoutOrder = order
	l.Text = ""
	l.Visible = false
	HudTheme.styleText(l, "title")
	l.Parent = parent
	return l
end

-- Built once in start(); held here so the update closure can reach them.
local bannerHandle, winnerTag, winnerName, title, subtitle
local bottomHandle, bottomText, elim
local bannerShown, bottomShown = false, false

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = HudTheme.DisplayOrder.bookend
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Banner: chunky state-colored panel in the TOP zone.
	bannerHandle = HudTheme.makePanel(gui, UDim2.fromScale(0.6, 0.16), "top", "banner")
	bannerHandle.root.Visible = false

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = bannerHandle.panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = bannerHandle.panel

	-- WINNER pill (yellow, dark text) -- shown only on Ended with a winner.
	winnerTag = Instance.new("TextLabel")
	winnerTag.Name = "WinnerTag"
	winnerTag.Size = UDim2.fromScale(0.42, 0.16)
	winnerTag.BackgroundColor3 = HudTheme.Color.pill
	winnerTag.TextColor3 = HudTheme.Color.pillText
	winnerTag.Font = HudTheme.Font.heading
	winnerTag.TextScaled = true
	winnerTag.Text = "WINNER" -- static text; visibility toggled in applyDisplay
	winnerTag.LayoutOrder = 1
	winnerTag.Visible = false
	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(1, 0)
	tagCorner.Parent = winnerTag
	local tagStroke = Instance.new("UIStroke")
	tagStroke.Thickness = 2
	tagStroke.Color = HudTheme.Color.panelStroke
	tagStroke.Parent = winnerTag
	winnerTag.Parent = bannerHandle.panel

	winnerName = panelLabel(bannerHandle.panel, "WinnerName", 0.30, 2)
	title = panelLabel(bannerHandle.panel, "Title", 0.40, 3)       -- Victory/Defeated/Round over/lobby lines
	subtitle = panelLabel(bannerHandle.panel, "Subtitle", 0.18, 4) -- "X / N players" in lobby
	subtitle.Font = HudTheme.Font.body

	-- Bottom line: fixed dark pill in the BOTTOM zone ("Next round in N").
	bottomHandle = HudTheme.makePanel(gui, UDim2.fromScale(0.34, 0.06), "bottom", "bottomLine")
	HudTheme.setPanelFlat(bottomHandle, HudTheme.Color.panelDark)
	bottomHandle.root.Visible = false

	bottomText = Instance.new("TextLabel")
	bottomText.Name = "BottomText"
	bottomText.Size = UDim2.fromScale(0.9, 0.7)
	bottomText.AnchorPoint = Vector2.new(0.5, 0.5)
	bottomText.Position = UDim2.fromScale(0.5, 0.5)
	bottomText.BackgroundTransparency = 1
	bottomText.Text = ""
	HudTheme.styleText(bottomText, "body")
	bottomText.Parent = bottomHandle.panel

	-- Active-only transient notice (red text, no panel) in the NOTICE zone.
	elim = Instance.new("TextLabel")
	elim.Name = "EliminatedNotice"
	elim.Size = UDim2.fromScale(0.6, 0.08)
	elim.BackgroundTransparency = 1
	elim.Text = ""
	elim.Visible = false
	HudTheme.placeInZone(elim, "notice")
	HudTheme.applyMaxSize(elim, "notice")
	HudTheme.styleText(elim, "heading")
	elim.TextColor3 = HudTheme.Accent.lose.top -- red callout
	elim.Parent = gui
end

local function applyDisplay(d)
	-- Banner visibility + pop-in on the rising edge (hidden -> visible).
	if d.visible and not bannerShown then
		HudTheme.popIn(bannerHandle.root)
	end
	bannerShown = d.visible
	bannerHandle.root.Visible = d.visible

	-- Bottom pill visibility + pop-in on its rising edge.
	local bottomVisible = d.visible and d.bottomText ~= nil
	if bottomVisible and not bottomShown then
		HudTheme.popIn(bottomHandle.root)
	end
	bottomShown = bottomVisible
	bottomHandle.root.Visible = bottomVisible
	bottomText.Text = d.bottomText or ""

	-- When a banner takes the screen (Lobby/Ended), the notice is hidden via the
	-- phase check in the RoundStateChanged handler; nothing to do here.

	-- Panel fill color follows state (green win / red lose / blue neutral).
	HudTheme.setPanelAccent(bannerHandle, d.accent)

	winnerTag.Visible = d.winnerName ~= nil

	winnerName.Visible = d.winnerName ~= nil
	winnerName.Text = d.winnerName or ""

	title.Visible = d.titleText ~= nil
	title.Text = d.titleText or ""

	subtitle.Visible = d.subtitleText ~= nil
	subtitle.Text = d.subtitleText or ""
end

function ClientRoundHud.start()
	build()

	RoundStateChanged.OnClientEvent:Connect(function(state)
		local d = RoundScreenModel.display(state, {
			localPlayerName = player.Name,
			connectedCount = #Players:GetPlayers(),
			minPlayers = Config.MIN_PLAYERS_TO_START,
		})
		if state.phase ~= "Active" then
			elim.Visible = false -- the eliminated notice is Active-phase only
		end
		applyDisplay(d)
	end)

	EliminationEvent.OnClientEvent:Connect(function(playerName)
		-- Only while the banner is hidden (Active). Guards a cross-remote race:
		-- if the Ended broadcast lands before this event, the banner is up and
		-- the notice must not cover it.
		if playerName == player.Name and not bannerHandle.root.Visible then
			elim.Text = "You were eliminated"
			elim.Visible = true
		end
	end)

	SpectateBody.OnClientEvent:Connect(function(body)
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = hum
		end
	end)
end

return ClientRoundHud
```

- [ ] **Step 2: Tooling sanity check**

Roblox-only file; confirm tooling + dependencies:
Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec`
Expected: PASS (`ALL RoundScreenModel TESTS PASSED`). Then confirm: `src/client/HudTheme.luau` exists; `src/client/init.client.luau` still requires `script.ClientRoundHud` (unchanged public `start()` so no bootstrap edit); and re-read the diff to confirm the inline `ACCENT` table is gone, the banner/bottom use `makePanel`, the notice is at `Zone.notice`, and the spectate + elimination + phase-clear behavior matches the previous committed version.

- [ ] **Step 3: Commit**

```bash
git add src/client/ClientRoundHud.luau
git commit -m "feat(ui): kid-friendly bookend banner via HudTheme (state-colored, pop-in)"
```

---

## Task 4: Extend the smoke test (desktop + mobile consistency)

**Files:**
- Modify: `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md`

- [ ] **Step 1: Append the HUD-consistency section**

Append the following to the END of `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md`:

```markdown

## HUD consistency & kid-friendly skin (added 2026-06-21)

Run these on TWO window shapes: a wide desktop window AND a narrow phone-sized
window (Studio device emulator or just drag the client window narrow).

7. **Nothing balloons.** Banner, bottom "Next round in N" pill, and the swap timer
   number are all capped and centered on desktop (no full-width slab). The bottom
   pill is no wider than the banner.

8. **Kid-friendly skin.** Banner is a chunky rounded panel with a thick white
   outline and an offset drop shadow; the panel FILL color matches state -- blue in
   Lobby, green on Victory, red on Defeated. Title text (VICTORY/DEFEATED) is white
   with a dark outline in the rounded FredokaOne font. The WINNER pill is yellow.

9. **Pop-in.** The banner and bottom pill bounce in (scale up) when they appear,
   rather than snapping.

10. **No zone collisions.** The "You were eliminated" notice appears BELOW the big
    swap countdown (never overlapping it), as red text. The swap timer (top) and the
    bookend banner (top) never show at the same time.

11. **Mobile pass.** On the narrow window everything stays readable and on-screen:
    panels shrink via scale but text remains legible; nothing clips off the edges.

## Pass criteria (HUD)
All five checks hold on both window shapes. Note any spacing/size tweaks -- adjust the
values in `src/client/HudTheme.luau` (`Cap`, `Zone`, `Radius`, etc.), NOT in the
individual HUD modules (that is the whole point of the shared theme).
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md
git commit -m "docs: extend bookend smoke test with HUD consistency + skin checks"
```

---

## Done criteria

- `HudTheme` is the only place HUD zones/caps/fonts/colors/panel-styling are defined; both `ClientSwapHud` and `ClientRoundHud` render through it.
- The bookend banner, bottom pill, and eliminated notice are capped, state-colored, kid-friendly, and pop in; no element balloons on desktop and the bottom pill is no wider than the banner.
- The eliminated notice no longer shares a zone with the big swap countdown.
- The pure `RoundScreenModel` / `SwapTelegraphModel` and their lune suites are untouched and still pass.
- The Studio smoke test (Task 4) passes on desktop and a narrow window.
```
