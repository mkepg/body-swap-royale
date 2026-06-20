# Round-Flow Bookends (Lobby + Results) Implementation Plan

**Goal:** Frame the existing round loop with a Lobby banner and a Results banner, both driven by the existing `RoundStateChanged` remote.

**Architecture:** A pure, lune-tested `RoundScreenModel` decides *what* each bookend banner shows from a round-state snapshot + local-player context; `ClientRoundHud` evolves from a placeholder text label into the thin banner renderer that draws it (and keeps the spectate camera + elimination notice); `RoundManager.endRound` ticks the post-round countdown so "Next round in N" is server-truthful. Keep-arena-visible banner treatment; minimal lobby content.

**Tech Stack:** Luau, Rojo project, lune for pure-module unit tests. Established pattern: Roblox-free time-/clock-injected decision modules in `src/shared/`, server glue owns real clocks, client is a renderer.

**Spec:** `docs/specs/2026-06-20-round-flow-bookends-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/shared/RoundScreenModel.luau` | **new** — pure decision: round state + local ctx → what the banner shows |
| `tests/round_screen_model.spec.luau` | **new** — lune unit test for every decision-table row |
| `src/server/RoundManager.luau` | modify `endRound` — tick the Ended countdown via `broadcastState` |
| `src/client/ClientRoundHud.luau` | rewrite — placeholder text → banner renderer; keep spectate + elimination |
| `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md` | **new** — 2-client runtime check |

---

## Task 1: Pure `RoundScreenModel` (TDD)

**Files:**
- Create: `src/shared/RoundScreenModel.luau`
- Test: `tests/round_screen_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/round_screen_model.spec.luau`:

```lua
local RoundScreenModel = require("../src/shared/RoundScreenModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local CTX = { localPlayerName = "Mikhael", connectedCount = 2, minPlayers = 2 }

-- Lobby, not enough players yet (no countdown): "Waiting for players" + count.
do
	local d = RoundScreenModel.display({ phase = "Lobby", secondsRemaining = nil }, CTX)
	expect(d.visible == true, "lobby banner is visible")
	expect(d.titleText == "Waiting for players", "got title: " .. tostring(d.titleText))
	expect(d.subtitleText == "2 / 2 players", "got subtitle: " .. tostring(d.subtitleText))
	expect(d.bottomText == nil, "no bottom line in lobby")
	expect(d.winnerName == nil, "no winner in lobby")
	expect(d.accent == "neutral", "lobby accent is neutral")
	print("round-screen: lobby-waiting OK")
end

-- Lobby, counting down: title carries the seconds.
do
	local d = RoundScreenModel.display({ phase = "Lobby", secondsRemaining = 4 }, CTX)
	expect(d.titleText == "Round starting in 4", "got title: " .. tostring(d.titleText))
	expect(d.subtitleText == "2 / 2 players", "got subtitle: " .. tostring(d.subtitleText))
	print("round-screen: lobby-countdown OK")
end

-- Active: banner hidden, texts irrelevant.
do
	local d = RoundScreenModel.display({ phase = "Active", secondsRemaining = nil }, CTX)
	expect(d.visible == false, "banner hidden during Active")
	print("round-screen: active-hidden OK")
end

-- Ended, local player won: Victory + win accent + winner name + countdown.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = "Mikhael", secondsRemaining = 5 }, CTX)
	expect(d.visible == true, "results banner is visible")
	expect(d.titleText == "Victory", "got title: " .. tostring(d.titleText))
	expect(d.winnerName == "Mikhael", "winner name shown")
	expect(d.bottomText == "Next round in 5", "got bottom: " .. tostring(d.bottomText))
	expect(d.accent == "win", "win accent")
	print("round-screen: ended-victory OK")
end

-- Ended, someone else won: Defeated + lose accent, still shows the winner's name.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = "Vesper", secondsRemaining = 3 }, CTX)
	expect(d.titleText == "Defeated", "got title: " .. tostring(d.titleText))
	expect(d.winnerName == "Vesper", "winner name shown")
	expect(d.accent == "lose", "lose accent")
	print("round-screen: ended-defeated OK")
end

-- Ended, no winner (e.g. disconnect-decided with none alive): "Round over", neutral.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = nil, secondsRemaining = 2 }, CTX)
	expect(d.titleText == "Round over", "got title: " .. tostring(d.titleText))
	expect(d.winnerName == nil, "no winner name")
	expect(d.accent == "neutral", "neutral accent")
	expect(d.bottomText == "Next round in 2", "got bottom: " .. tostring(d.bottomText))
	print("round-screen: ended-no-winner OK")
end

-- Defensive: Ended without a countdown value shows no stale bottom line.
do
	local d = RoundScreenModel.display({ phase = "Ended", winnerName = "Mikhael", secondsRemaining = nil }, CTX)
	expect(d.bottomText == nil, "no bottom line when secondsRemaining is nil")
	print("round-screen: ended-no-countdown OK")
end

print("ALL RoundScreenModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec`
Expected: FAIL — the module does not exist yet (require error / nil).

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/RoundScreenModel.luau`:

```lua
--[[
	RoundScreenModel -- PURE round-flow bookend display decision (Lobby + Results).
	Location (Roblox): ReplicatedStorage/Shared/RoundScreenModel  (ModuleScript)

	No Roblox APIs, no clocks, no RNG: the caller injects the RoundStateChanged
	snapshot plus local-player context, and gets back what the banner should show.
	The renderer maps the semantic `accent` string to a Color3, keeping this module
	Roblox-free. Mirrors SwapTelegraphModel / TileFieldModel / GraceModel.

	state = { phase, winnerName, secondsRemaining }   (swap fields are ignored)
	ctx   = { localPlayerName, connectedCount, minPlayers }

	Returns:
	  visible       : false during Active (banner hidden); true for Lobby/Ended
	  titleText     : the big line (or nil)
	  subtitleText  : the small line under it (or nil)
	  bottomText    : the bottom line (or nil)
	  winnerName    : name for the fixed WINNER label slot (or nil)
	  accent        : "neutral" | "win" | "lose"  (renderer maps to a Color3)
--]]

local RoundScreenModel = {}

function RoundScreenModel.display(state, ctx)
	local phase = state.phase

	if phase == "Lobby" then
		local count = string.format("%d / %d players", ctx.connectedCount, ctx.minPlayers)
		local title
		if state.secondsRemaining == nil then
			title = "Waiting for players"
		else
			title = "Round starting in " .. tostring(state.secondsRemaining)
		end
		return {
			visible = true,
			titleText = title,
			subtitleText = count,
			bottomText = nil,
			winnerName = nil,
			accent = "neutral",
		}
	elseif phase == "Ended" then
		local bottom = nil
		if state.secondsRemaining ~= nil then
			bottom = "Next round in " .. tostring(state.secondsRemaining)
		end
		local winner = state.winnerName
		local title, accent
		if winner == nil then
			title, accent = "Round over", "neutral"
		elseif winner == ctx.localPlayerName then
			title, accent = "Victory", "win"
		else
			title, accent = "Defeated", "lose"
		end
		return {
			visible = true,
			titleText = title,
			subtitleText = nil,
			bottomText = bottom,
			winnerName = winner,
			accent = accent,
		}
	end

	-- Active (or any non-bookend phase): banner hidden.
	return {
		visible = false,
		titleText = nil,
		subtitleText = nil,
		bottomText = nil,
		winnerName = nil,
		accent = "neutral",
	}
end

return RoundScreenModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec`
Expected: PASS — ends with `ALL RoundScreenModel TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/RoundScreenModel.luau tests/round_screen_model.spec.luau
git commit -m "feat(ui): pure RoundScreenModel for Lobby/Results bookends

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Server — tick the Ended countdown in `RoundManager.endRound`

**Files:**
- Modify: `src/server/RoundManager.luau` (the `endRound` function, currently ~lines 340-349)

This is server glue (no lune unit test; validated by the Task 4 smoke test). `broadcastState` already sends `winnerName` during Ended and accepts `secondsRemaining` as its first arg.

- [ ] **Step 1: Replace the single wait with a per-second tick**

Find the current `endRound`:

```lua
local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	broadcastState() -- phase Ended (+ winnerName)
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
	task.wait(Config.ROUND_END_SECONDS)
	RoundState.reset(model) -- Ended -> Lobby
	broadcastState() -- phase Lobby
end
```

Replace it with:

```lua
local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
	-- Tick the post-round countdown so the Results banner shows a truthful
	-- "Next round in N" -- reusing the same secondsRemaining channel the Lobby
	-- countdown uses, so the client stays clock-free (server owns clocks).
	-- broadcastState already carries winnerName during Ended.
	local remaining = Config.ROUND_END_SECONDS
	while remaining > 0 do
		broadcastState(remaining) -- phase Ended (+ winnerName) + secondsRemaining
		task.wait(1)
		remaining -= 1
	end
	RoundState.reset(model) -- Ended -> Lobby
	broadcastState() -- phase Lobby
end
```

- [ ] **Step 2: Sanity-check it loads (syntax)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec`
Expected: still PASS (this confirms the repo's tooling runs; `RoundManager` itself is Roblox-only and is exercised in the smoke test). Visually re-read the diff to confirm the loop broadcasts `remaining` from `Config.ROUND_END_SECONDS` down to 1 before reset.

- [ ] **Step 3: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(server): tick post-round countdown for the Results banner

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Client — rewrite `ClientRoundHud` into the banner renderer

**Files:**
- Modify (full rewrite): `src/client/ClientRoundHud.luau`

This is client render code (no lune test; validated by the Task 4 smoke test). It keeps the existing `SpectateBody` camera retarget and adds an Active-only "You were eliminated" notice. Pixel sizing is approximate — fine-tune during the smoke test.

- [ ] **Step 1: Replace the file contents**

Overwrite `src/client/ClientRoundHud.luau` with:

```lua
--[[
	ClientRoundHud -- round-flow bookend banner (Lobby + Results) renderer.
	Location: StarterPlayerScripts/Client/ClientRoundHud  (ModuleScript)

	Draws the keep-arena-visible banner from RoundStateChanged. WHAT to show is the
	pure RoundScreenModel's decision; this module only renders it and maps the
	semantic accent to a Color3. Also keeps the spectator-camera retarget and a
	brief "you were eliminated" notice (Active-phase only -- the banner owns the
	screen during Lobby/Ended).
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

local ClientRoundHud = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- accent -> Color3 (lives in the renderer; the pure model stays Roblox-free).
local ACCENT = {
	neutral = Color3.fromRGB(180, 200, 220),
	win = Color3.fromRGB(45, 212, 191),
	lose = Color3.fromRGB(220, 90, 90),
}

-- A stacked text line inside the banner. scaleY is its share of the banner height.
local function bannerLabel(parent, name, scaleY, order)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(0.96, scaleY)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.LayoutOrder = order
	l.Text = ""
	l.Visible = false
	l.Parent = parent
	return l
end

-- Built once in start(); held here so the update closure can reach them.
local banner, winnerTag, winnerName, title, subtitle, stroke, bottomLabel, elim

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Top banner (keep-arena-visible): semi-transparent dark panel + accent stroke.
	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 12)
	banner.Size = UDim2.fromScale(0.94, 0.2)
	banner.BackgroundColor3 = Color3.fromRGB(17, 22, 31)
	banner.BackgroundTransparency = 0.25
	banner.Visible = false
	banner.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner

	stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = ACCENT.neutral
	stroke.Parent = banner

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = banner

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = banner

	-- WINNER mini-label + the winner's name (shown only on Ended with a winner).
	winnerTag = bannerLabel(banner, "WinnerTag", 0.16, 1)
	winnerTag.Text = "WINNER"
	winnerTag.TextColor3 = Color3.fromRGB(150, 170, 190)

	winnerName = bannerLabel(banner, "WinnerName", 0.30, 2)
	title = bannerLabel(banner, "Title", 0.36, 3)       -- Waiting.../Round starting.../Victory/Defeated
	subtitle = bannerLabel(banner, "Subtitle", 0.18, 4) -- "X / N players" in lobby

	-- Bottom line: "Next round in N" on the Results screen.
	bottomLabel = Instance.new("TextLabel")
	bottomLabel.Name = "BottomLine"
	bottomLabel.AnchorPoint = Vector2.new(0.5, 1)
	bottomLabel.Position = UDim2.fromScale(0.5, 0.97)
	bottomLabel.Size = UDim2.fromScale(0.5, 0.05)
	bottomLabel.BackgroundColor3 = Color3.fromRGB(17, 22, 31)
	bottomLabel.BackgroundTransparency = 0.4
	bottomLabel.Font = Enum.Font.GothamMedium
	bottomLabel.TextScaled = true
	bottomLabel.TextColor3 = Color3.fromRGB(223, 238, 238)
	bottomLabel.TextStrokeTransparency = 0.5
	bottomLabel.Text = ""
	bottomLabel.Visible = false
	bottomLabel.Parent = gui

	-- Active-only transient notice when THIS client is eliminated.
	elim = Instance.new("TextLabel")
	elim.Name = "EliminatedNotice"
	elim.AnchorPoint = Vector2.new(0.5, 0.5)
	elim.Position = UDim2.fromScale(0.5, 0.5)
	elim.Size = UDim2.fromScale(0.6, 0.08)
	elim.BackgroundTransparency = 1
	elim.Font = Enum.Font.GothamBold
	elim.TextScaled = true
	elim.TextColor3 = Color3.fromRGB(220, 90, 90)
	elim.TextStrokeTransparency = 0.3
	elim.Text = ""
	elim.Visible = false
	elim.Parent = gui
end

local function applyDisplay(d)
	banner.Visible = d.visible
	bottomLabel.Visible = d.visible and d.bottomText ~= nil
	bottomLabel.Text = d.bottomText or ""

	-- When a banner takes the screen (Lobby/Ended), clear the Active-only notice.
	if d.visible then
		elim.Visible = false
	end

	local accent = ACCENT[d.accent] or ACCENT.neutral
	stroke.Color = accent

	winnerTag.Visible = d.winnerName ~= nil
	winnerName.Visible = d.winnerName ~= nil
	winnerName.Text = d.winnerName or ""
	winnerName.TextColor3 = accent

	title.Visible = d.titleText ~= nil
	title.Text = d.titleText or ""
	title.TextColor3 = (d.accent == "neutral") and Color3.new(1, 1, 1) or accent

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
		applyDisplay(d)
	end)

	EliminationEvent.OnClientEvent:Connect(function(playerName)
		if playerName == player.Name then
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

- [ ] **Step 2: Confirm the model require path is valid**

The renderer requires `ReplicatedStorage.Shared.RoundScreenModel` (created in Task 1) — confirm that file exists. `init.client.luau` already requires and starts `ClientRoundHud`, so no bootstrap change is needed (the public `ClientRoundHud.start()` signature is unchanged).

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec`
Expected: still PASS (model unchanged; this just reconfirms tooling).

- [ ] **Step 3: Commit**

```bash
git add src/client/ClientRoundHud.luau
git commit -m "feat(client): render Lobby/Results bookend banner via RoundScreenModel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Studio smoke test doc + manual run

**Files:**
- Create: `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md`

- [ ] **Step 1: Write the smoke-test procedure**

Create `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md`:

```markdown
# Smoke Test — Round-Flow Bookends (Lobby + Results)

**Date:** 2026-06-20
**Spec:** docs/specs/2026-06-20-round-flow-bookends-design.md
**Why manual:** the banner is runtime client render + server round-loop timing,
which lune can't cover. The pure decision is unit-tested in
`tests/round_screen_model.spec.luau`.

## Setup
- Studio → Test → Clients and Servers → **2 players**, Start.
- Set `Config.HAZARDS_ENABLED = false` (keep the floor solid so nobody falls and
  the round won't end on its own while you inspect the Lobby/Active banners).

## Checks

1. **Lobby banner.** Before the round starts, both clients show the top banner:
   "Waiting for players" with "2 / 2 players" underneath, then it switches to
   "Round starting in N" counting down. Accent stroke is neutral (grey-blue). The
   arena bodies remain visible behind the banner.

2. **Active hides the banner.** When the round begins (phase Active), the banner
   disappears; only the in-round swap HUD (timer/telegraph) is visible.

3. **Eliminated notice (Active-only).** Temporarily set `HAZARDS_ENABLED = true`
   (or in the command bar eliminate one body via the existing harness, e.g.
   `RoundManager.forceSwap()` then let a body fall). On the client that loses a
   body: a centered "You were eliminated" notice appears during Active, and its
   camera retargets to a living body (spectate).

4. **Results banner — winner's client.** When one player remains, the winner's
   client shows the banner with the small "WINNER" label, the winner's **name**,
   the big word **Victory** (teal/win accent), and a bottom line "Next round in N"
   ticking down from `Config.ROUND_END_SECONDS`.

5. **Results banner — loser's client.** The other client shows the same banner with
   the winner's name but the big word **Defeated** (red/lose accent) and the same
   ticking "Next round in N".

6. **Return to Lobby.** After the countdown, both clients revert to the Lobby
   banner ("Waiting for players" / "Round starting in N").

## Pass criteria
All six checks behave as described; text is readable (TextScaled) and the banner
clears the top inset. Note any pixel/spacing tweaks and adjust sizes in
`ClientRoundHud.build()`.
```

- [ ] **Step 2: Run the smoke test in Studio**

Perform the 6 checks above with a 2-client Studio session. Record results. If any check fails, fix `ClientRoundHud.luau` (render) or `RoundManager.luau` (timing) and re-run. Do **not** mark this step done on unverified assertions — only after observing the behavior.

- [ ] **Step 3: Commit**

```bash
git add docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md
git commit -m "docs: 2-client smoke test for round-flow bookends

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Done criteria

- `lune run tests/round_screen_model.spec` passes (Task 1).
- Lobby and Results banners render correctly in a 2-client Studio session, with
  Victory/Defeated personalized per client and a ticking "Next round in N" (Task 4).
- No regression to the spectate camera or elimination notice.
- The in-round HUD is untouched (banner is hidden during Active).
```
