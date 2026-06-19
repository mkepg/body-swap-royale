# Swap Legibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the swap readable end-to-end — a live countdown + T−3s telegraph, a truthful swap preview (plan/commit), free Soul halos with self-emphasis, and the post-swap grace shimmer.

**Architecture:** Pure, value-injected decision modules (`SwapTelegraphModel`, `SoulPalette`, extended `ControlModel`) hold the testable logic; thin server/client glue owns Roblox APIs and real clocks. The swap splits into a `plan` (T−3s, drives the preview) and an authoritative `commit` (T0). The ownership-transfer and animation cores are untouched.

**Tech Stack:** Roblox / Luau, Rojo project (`src/` → game tree), pure modules unit-tested with **lune** (standalone assertion scripts, no TestEZ). Spec: [docs/superpowers/specs/2026-06-19-swap-legibility-design.md](../specs/2026-06-19-swap-legibility-design.md).

## Conventions for this plan

- **Run lune tests:** `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`
  Each test file is a standalone script that `print`s progress and `error`s on the first failed assertion. "Pass" = it prints its final `ALL ... TESTS PASSED` line and exits 0. "Fail" = it errors.
- **Pure modules** (in `src/shared/`) must use **no Roblox APIs and no clocks** — all time/RNG/palette values are injected — so lune can run them. Keys/values are opaque (`==`-compared); tests pass plain strings where production passes `Player`/`Model`/`Color3`.
- **Glue modules** (server systems, client controllers) use Roblox APIs and **cannot** be lune-tested. They are verified by (a) running the full lune suite to prove pure logic + no-regression, and (b) the Studio 2-client smoke test in Task 15. This matches the project's established pattern.
- **Commit** after each task with the message shown. Work happens on the existing `feat/swap-legibility` branch.

---

## File structure

**New pure modules (lune-tested):**
- `src/shared/SwapTelegraphModel.luau` — time-remaining → HUD display decision.
- `src/shared/SoulPalette.luau` — index → distinct color (palette injected).

**Modified pure module:**
- `src/shared/ControlModel.luau` — add `planSwap` / `applySwap` / `planStillValid`; reimplement `swap` on top of them (behavior unchanged).

**Modified shared:**
- `src/shared/Config.luau` — telegraph sound id, flash color, soul palette.
- `src/shared/Remotes.luau` — add `SwapPreview`, `SoulMap`.

**Modified server glue:**
- `src/server/SwapController.luau` — `plan` / `commit` / `planStillValid` / immediate `swap`.
- `src/server/ControlManager.luau` — plan/commit wrappers, soul-color assignment, `SoulMap` broadcast.
- `src/server/RoundManager.luau` — `swapAtServerTime` broadcast, then free-play/preview/commit restructure.

**New client controllers:**
- `src/client/ClientSwapHud.luau` — timer + telegraph flash/countdown/audio.
- `src/client/SwapPreviewController.luau` — highlight the target body.
- `src/client/SoulController.luau` — halos + self-emphasis + grace shimmer.
- `src/client/init.client.luau` — start the three new controllers.

**New test files:**
- `tests/swap_telegraph_model.spec.luau`
- `tests/soul_palette.spec.luau`
- `tests/control_model.spec.luau` — extended.

**New doc:**
- `docs/smoke-tests/2026-06-19-swap-legibility-smoke-test.md`

---

## Task 1: Config additions

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Add the new tunables**

Add these lines just before the final `return Config` (keep the existing comment style):

```lua
-- Swap telegraph + Soul (the swap-legibility piece).
-- SWAP_WARNING_SOUND_ID: the "incoming" rumble played once when the 3s telegraph
-- begins. Leave "" to keep the telegraph silent (it is fully communicative
-- visually -- accessibility). Set to an "rbxassetid://..." string to enable.
Config.SWAP_WARNING_SOUND_ID = ""
-- TELEGRAPH_FLASH_COLOR: the warm base color of the full-screen flash that ramps
-- up over the 3s preview window.
Config.TELEGRAPH_FLASH_COLOR = Color3.fromRGB(255, 110, 40)
-- SOUL_PALETTE: distinct, mobile-legible colors auto-assigned one per player (by
-- join order, wrapping) as their persistent identity halo. The free "which body
-- am I?" anchor (GDD §5). Index->color mapping is the pure SoulPalette module.
Config.SOUL_PALETTE = {
	Color3.fromRGB(255, 80, 80),    -- red
	Color3.fromRGB(80, 160, 255),   -- blue
	Color3.fromRGB(90, 220, 120),   -- green
	Color3.fromRGB(255, 210, 70),   -- yellow
	Color3.fromRGB(200, 110, 255),  -- purple
	Color3.fromRGB(255, 150, 60),   -- orange
	Color3.fromRGB(80, 230, 230),   -- cyan
	Color3.fromRGB(255, 130, 200),  -- pink
}
```

- [ ] **Step 2: Sanity-check it loads (no syntax error)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau`
Expected: still prints `ALL CONTROLMODEL TESTS PASSED` (Config isn't required by tests, but this confirms the workspace lune setup is intact before we start).

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(config): add swap telegraph + soul palette tunables"
```

---

## Task 2: SwapTelegraphModel (pure) + test

**Files:**
- Create: `src/shared/SwapTelegraphModel.luau`
- Test: `tests/swap_telegraph_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/swap_telegraph_model.spec.luau`:

```lua
local SwapTelegraphModel = require("../src/shared/SwapTelegraphModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local PREVIEW = 3

-- Outside the preview window: always-on timer text, no flash, no big countdown.
do
	local d = SwapTelegraphModel.display(27, PREVIEW)
	expect(d.timerText == "27", "timerText at 27s should be '27', got " .. tostring(d.timerText))
	expect(d.inPreview == false, "27s is not in preview")
	expect(d.bigCountdownInt == nil, "no big countdown outside preview")
	expect(d.flashAlpha == 0, "no flash outside preview")
	print("telegraph: outside-preview OK")
end

-- ceil behavior: 26.4s still reads as 27 (counts down to 1 then 0).
do
	local d = SwapTelegraphModel.display(26.4, PREVIEW)
	expect(d.timerText == "27", "26.4s should ceil to '27', got " .. tostring(d.timerText))
	print("telegraph: ceil timerText OK")
end

-- At the preview boundary (s == previewSeconds): in preview, big = 3, flash just starting.
do
	local d = SwapTelegraphModel.display(3, PREVIEW)
	expect(d.inPreview == true, "3s == previewSeconds must be in preview")
	expect(d.bigCountdownInt == 3, "big countdown at 3s should be 3")
	expect(d.flashAlpha == 0, "flash should start at 0 at the boundary")
	print("telegraph: preview boundary OK")
end

-- Mid preview: big counts down, flash ramps 0..1 as s -> 0.
do
	local d2 = SwapTelegraphModel.display(2, PREVIEW)
	expect(d2.bigCountdownInt == 2, "big at 2s should be 2")
	expect(math.abs(d2.flashAlpha - (1 / 3)) < 1e-6, "flashAlpha at 2s should be 1/3")
	local d1 = SwapTelegraphModel.display(1, PREVIEW)
	expect(d1.bigCountdownInt == 1, "big at 1s should be 1")
	expect(d1.flashAlpha > d2.flashAlpha, "flash should intensify as the swap nears")
	print("telegraph: mid-preview ramp OK")
end

-- At/after the swap moment: clamp to 0, no negative text, no big countdown.
do
	local d0 = SwapTelegraphModel.display(0, PREVIEW)
	expect(d0.timerText == "0", "timerText at 0 should be '0'")
	expect(d0.bigCountdownInt == nil, "no big countdown at the swap moment (s <= 0)")
	local dn = SwapTelegraphModel.display(-1.5, PREVIEW)
	expect(dn.timerText == "0", "negative seconds clamp to '0'")
	expect(dn.flashAlpha == 0, "no flash past the swap")
	print("telegraph: swap-moment clamp OK")
end

print("ALL SwapTelegraphModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/swap_telegraph_model.spec.luau`
Expected: FAIL — error loading/requiring `../src/shared/SwapTelegraphModel` (module does not exist yet).

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/SwapTelegraphModel.luau`:

```lua
--[[
	SwapTelegraphModel -- PURE swap-HUD display decision.
	Location (Roblox): ReplicatedStorage/Shared/SwapTelegraphModel  (ModuleScript)

	No Roblox APIs and no clocks: the caller injects `secondsUntilSwap` (and the
	preview length). Returns what the HUD should show, so the client renders and
	lune tests the same logic. Mirrors TileFieldModel / GraceModel.
--]]

local SwapTelegraphModel = {}

-- Given seconds until the next swap and the preview-window length, decide:
--   timerText       : always-on countdown, ceil(secondsUntilSwap) clamped >= 0
--   inPreview       : secondsUntilSwap <= previewSeconds
--   bigCountdownInt : 3 / 2 / 1 during preview (nil at/after the swap or outside)
--   flashAlpha      : 0..1 telegraph intensity, ramping as the swap nears
function SwapTelegraphModel.display(secondsUntilSwap, previewSeconds)
	local s = secondsUntilSwap
	if s < 0 then
		s = 0
	end

	local timerText = tostring(math.ceil(s))
	local inPreview = secondsUntilSwap <= previewSeconds
	local bigCountdownInt = nil
	local flashAlpha = 0

	if inPreview and s > 0 then
		bigCountdownInt = math.ceil(s)
		flashAlpha = (previewSeconds - s) / previewSeconds
		if flashAlpha < 0 then flashAlpha = 0 end
		if flashAlpha > 1 then flashAlpha = 1 end
	end

	return {
		timerText = timerText,
		inPreview = inPreview,
		bigCountdownInt = bigCountdownInt,
		flashAlpha = flashAlpha,
	}
end

return SwapTelegraphModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/swap_telegraph_model.spec.luau`
Expected: PASS — prints `ALL SwapTelegraphModel TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/SwapTelegraphModel.luau tests/swap_telegraph_model.spec.luau
git commit -m "feat(swap): pure SwapTelegraphModel for timer + telegraph display"
```

---

## Task 3: SoulPalette (pure) + test

**Files:**
- Create: `src/shared/SoulPalette.luau`
- Test: `tests/soul_palette.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/soul_palette.spec.luau` (palette entries are opaque values — plain strings here, `Color3`s in production):

```lua
local SoulPalette = require("../src/shared/SoulPalette")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local P = { "red", "green", "blue" } -- 3-entry palette

-- 1-based index maps straight through within palette size.
do
	expect(SoulPalette.colorForIndex(1, P) == "red", "index 1 -> red")
	expect(SoulPalette.colorForIndex(2, P) == "green", "index 2 -> green")
	expect(SoulPalette.colorForIndex(3, P) == "blue", "index 3 -> blue")
	print("soul: in-range mapping OK")
end

-- distinct indices within the palette give distinct colors.
do
	local a = SoulPalette.colorForIndex(1, P)
	local b = SoulPalette.colorForIndex(2, P)
	local c = SoulPalette.colorForIndex(3, P)
	expect(a ~= b and b ~= c and a ~= c, "first N indices must be distinct")
	print("soul: distinctness OK")
end

-- wraps modulo palette size past the end.
do
	expect(SoulPalette.colorForIndex(4, P) == "red", "index 4 wraps to red")
	expect(SoulPalette.colorForIndex(6, P) == "blue", "index 6 wraps to blue")
	expect(SoulPalette.colorForIndex(7, P) == "red", "index 7 wraps to red")
	print("soul: wrap OK")
end

-- deterministic: same inputs, same output.
do
	expect(SoulPalette.colorForIndex(5, P) == SoulPalette.colorForIndex(5, P), "deterministic")
	print("soul: determinism OK")
end

print("ALL SoulPalette TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/soul_palette.spec.luau`
Expected: FAIL — module `../src/shared/SoulPalette` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/SoulPalette.luau`:

```lua
--[[
	SoulPalette -- PURE index -> color mapping for the free Soul halo.
	Location (Roblox): ReplicatedStorage/Shared/SoulPalette  (ModuleScript)

	No Roblox APIs: the palette is INJECTED (Config.SOUL_PALETTE in production,
	plain strings in tests), so this stays a pure, lune-testable index map.
	Each connected player gets a stable index (join order); this returns their
	color, wrapping if there are more players than palette entries.
--]]

local SoulPalette = {}

-- 1-based `index` -> palette color, wrapping modulo palette size.
function SoulPalette.colorForIndex(index, palette)
	local n = #palette
	assert(n > 0, "palette must be non-empty")
	local i = ((index - 1) % n) + 1
	return palette[i]
end

return SoulPalette
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/soul_palette.spec.luau`
Expected: PASS — prints `ALL SoulPalette TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/SoulPalette.luau tests/soul_palette.spec.luau
git commit -m "feat(soul): pure SoulPalette index->color mapping"
```

---

## Task 4: ControlModel plan/commit + tests

**Files:**
- Modify: `src/shared/ControlModel.luau`
- Test: `tests/control_model.spec.luau` (extend)

- [ ] **Step 1: Write the failing tests**

Append these blocks to `tests/control_model.spec.luau` immediately BEFORE the final `print("ALL CONTROLMODEL TESTS PASSED")` line:

```lua
-- planSwap: does NOT mutate the model (it only computes the future assignment).
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.addPlayer(m, "C", "c")

	local plan = ControlModel.planSwap(m, { "A", "B", "C" }, function(_n) return 1 end)

	-- model is untouched: everyone still controls their own body.
	expect(ControlModel.controlledBody(m, "A") == "a", "planSwap must not move A")
	expect(ControlModel.controlledBody(m, "B") == "b", "planSwap must not move B")
	expect(ControlModel.controlledBody(m, "C") == "c", "planSwap must not move C")
	expect(ControlModel.bijectionHolds(m), "planSwap must not break the bijection")

	-- plan captures the source snapshot and the future map.
	expect(plan.from["A"] == "a" and plan.from["B"] == "b" and plan.from["C"] == "c",
		"plan.from is the source snapshot")
	expect(#plan.to == 3, "plan.to has one entry per player")
	print("planSwap: non-mutating + captures from/to OK")
end

-- applySwap(planSwap(...)) matches the old swap behavior (n=2 deterministic).
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")

	local plan = ControlModel.planSwap(m, { "A", "B" }, function(_n) return 1 end)
	ControlModel.applySwap(m, plan)

	expect(ControlModel.controlledBody(m, "A") == "b", "apply: A -> b")
	expect(ControlModel.controlledBody(m, "B") == "a", "apply: B -> a")
	expect(ControlModel.bijectionHolds(m), "apply keeps the bijection")
	print("applySwap: matches swap behavior OK")
end

-- planStillValid: true while nothing changes; false when a player leaves.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.addPlayer(m, "C", "c")

	local plan = ControlModel.planSwap(m, { "A", "B", "C" }, function(_n) return 1 end)
	expect(ControlModel.planStillValid(m, plan) == true, "plan valid before any change")

	ControlModel.removePlayer(m, "A") -- A leaves: plan.from references A's old body
	expect(ControlModel.planStillValid(m, plan) == false, "plan invalid after a player leaves")
	print("planStillValid: leave invalidates OK")
end

-- planStillValid: false when a disconnect-absorb changes a SURVIVOR's body.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.addPlayer(m, "C", "c")
	ControlModel.swap(m, { "A", "B", "C" }, function(_n) return 1 end) -- A->b, B->c, C->a

	-- plan over the current (post-swap) state.
	local plan = ControlModel.planSwap(m, { "A", "B", "C" }, function(_n) return 1 end)
	expect(ControlModel.planStillValid(m, plan) == true, "fresh plan valid")

	ControlModel.removePlayer(m, "A") -- absorbs C (controller of a) onto b -> C's body changes
	expect(ControlModel.planStillValid(m, plan) == false, "absorb changes a survivor's body -> stale")
	print("planStillValid: absorb invalidates OK")
end

-- commit after a roster change still yields a valid bijection (re-plan path).
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.addPlayer(m, "C", "c")

	local plan = ControlModel.planSwap(m, { "A", "B", "C" }, function(_n) return 1 end)
	ControlModel.removePlayer(m, "A") -- roster now {B, C}
	expect(ControlModel.planStillValid(m, plan) == false, "old plan is stale")

	-- glue would re-plan over the current roster and apply that instead.
	local fresh = ControlModel.planSwap(m, { "B", "C" }, function(_n) return 1 end)
	ControlModel.applySwap(m, fresh)
	expect(ControlModel.bijectionHolds(m), "commit over current roster keeps the bijection")
	print("commit-after-change: bijection preserved OK")
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau`
Expected: FAIL — `attempt to call a nil value (field 'planSwap')` (new functions not defined yet).

- [ ] **Step 3: Add planSwap / applySwap / planStillValid and reimplement swap**

In `src/shared/ControlModel.luau`, REPLACE the existing `ControlModel.swap` function (the block from `function ControlModel.swap(model, orderedPlayers, randint)` through its closing `end`) with the following four functions:

```lua
-- Compute (but DO NOT apply) the next swap. Deranges a COPY of the players'
-- current bodies so the model is untouched; returns:
--   { from = {[player] = sourceBody}, to = { {player, body}, ... } }
-- `from` is the snapshot the plan was derived from (used by planStillValid);
-- `to` is the future control map. Lets the swap be previewed at T-3s and the
-- SAME permutation committed at T0 (a truthful preview).
function ControlModel.planSwap(model, orderedPlayers, randint)
	assert(#orderedPlayers >= 2, "planSwap needs >= 2 players")

	local from = {}
	local bodies = {}
	for i, player in ipairs(orderedPlayers) do
		local body = model.bodyOf[player]
		from[player] = body
		bodies[i] = body
	end

	ControlModel.derange(bodies, randint) -- `bodies` is a fresh copy; model untouched

	local to = {}
	for i, player in ipairs(orderedPlayers) do
		to[i] = { player = player, body = bodies[i] }
	end
	return { from = from, to = to }
end

-- Apply a plan produced by planSwap: rewrite bodyOf/controllerOf from plan.to.
-- Because plan.to permutes the exact set of bodies those players held, the
-- overwrite leaves no stale entries. Returns the array of { player, body }.
function ControlModel.applySwap(model, plan)
	local result = {}
	for i, pair in ipairs(plan.to) do
		model.bodyOf[pair.player] = pair.body
		model.controllerOf[pair.body] = pair.player
		result[i] = { player = pair.player, body = pair.body }
	end
	return result
end

-- True iff, for every player in the plan, the model's CURRENT controlled body
-- still equals the source body the plan was derived from. Goes false if a
-- planned player left, or a disconnect-absorb moved a survivor onto another body
-- -- i.e. whenever the committed swap would no longer match the previewed one.
function ControlModel.planStillValid(model, plan)
	for player, sourceBody in pairs(plan.from) do
		if model.bodyOf[player] ~= sourceBody then
			return false
		end
	end
	return true
end

-- Rotate control among the given connected players (plan + apply in one call).
-- Unchanged external behavior: deranges their CURRENT bodies and returns the new
-- { player, body } map. Used by the immediate (no-preview) forceSwap path.
function ControlModel.swap(model, orderedPlayers, randint)
	assert(#orderedPlayers >= 2, "swap needs >= 2 players")
	local plan = ControlModel.planSwap(model, orderedPlayers, randint)
	return ControlModel.applySwap(model, plan)
end
```

- [ ] **Step 4: Run the test to verify it passes (including the pre-existing cases)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau`
Expected: PASS — prints all the pre-existing `swap:` / `removePlayer:` lines AND the new `planSwap:` / `applySwap:` / `planStillValid:` / `commit-after-change:` lines, then `ALL CONTROLMODEL TESTS PASSED`.

- [ ] **Step 5: Run the whole suite (no regression)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done`
Expected: every spec prints its `ALL ... TESTS PASSED` line; no errors.

- [ ] **Step 6: Commit**

```bash
git add src/shared/ControlModel.luau tests/control_model.spec.luau
git commit -m "feat(control): add planSwap/applySwap/planStillValid; swap built on them"
```

---

## Task 5: Add remotes

**Files:**
- Modify: `src/shared/Remotes.luau`

- [ ] **Step 1: Register the two new RemoteEvents**

In `src/shared/Remotes.luau`, replace the `REMOTE_EVENTS` line:

```lua
local REMOTE_EVENTS = { "SetControlledBody", "RoundStateChanged", "EliminationEvent", "SpectateBody" }
```

with:

```lua
local REMOTE_EVENTS =
	{ "SetControlledBody", "RoundStateChanged", "EliminationEvent", "SpectateBody", "SwapPreview", "SoulMap" }
```

- [ ] **Step 2: Verify the suite still loads**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau`
Expected: PASS (Remotes isn't required by lune tests; this just confirms nothing broke). The remotes themselves are verified live in the Task 15 smoke test.

- [ ] **Step 3: Commit**

```bash
git add src/shared/Remotes.luau
git commit -m "feat(remotes): add SwapPreview and SoulMap events"
```

---

## Task 6: RoundManager — broadcast swap deadline (enables the live timer)

This is the minimal RoundManager change so the client timer works in isolation; the full preview/commit restructure comes in Task 9.

**Files:**
- Modify: `src/server/RoundManager.luau`

- [ ] **Step 1: Extend broadcastState with a swap deadline field**

In `src/server/RoundManager.luau`, replace the `broadcastState` function:

```lua
local function broadcastState(secondsRemaining)
	local winner = RoundState.getWinner(model)
	RoundStateChanged:FireAllClients({
		phase = RoundState.getPhase(model),
		aliveCount = RoundState.aliveCount(model),
		winnerName = winner and winner.Name or nil,
		secondsRemaining = secondsRemaining,
	})
end
```

with (adds an optional `swapAtServerTime`):

```lua
local function broadcastState(secondsRemaining, swapAtServerTime)
	local winner = RoundState.getWinner(model)
	RoundStateChanged:FireAllClients({
		phase = RoundState.getPhase(model),
		aliveCount = RoundState.aliveCount(model),
		winnerName = winner and winner.Name or nil,
		secondsRemaining = secondsRemaining,
		swapAtServerTime = swapAtServerTime,
	})
end
```

- [ ] **Step 2: Broadcast the deadline at the start of each cycle**

In `src/server/RoundManager.luau`, replace the `runActivePhase` function:

```lua
local function runActivePhase()
	while RoundState.getPhase(model) == "Active" do
		local elapsed = 0
		while elapsed < Config.CYCLE_SECONDS and RoundState.getPhase(model) == "Active" do
			task.wait(0.25)
			elapsed += 0.25
		end
		if RoundState.getPhase(model) ~= "Active" then
			break
		end
		doSwap()
	end
end
```

with (broadcasts the next-swap clock time each cycle):

```lua
local function runActivePhase()
	while RoundState.getPhase(model) == "Active" do
		broadcastState(nil, workspace:GetServerTimeNow() + Config.CYCLE_SECONDS)
		local elapsed = 0
		while elapsed < Config.CYCLE_SECONDS and RoundState.getPhase(model) == "Active" do
			task.wait(0.25)
			elapsed += 0.25
		end
		if RoundState.getPhase(model) ~= "Active" then
			break
		end
		doSwap()
	end
end
```

- [ ] **Step 3: Verify no lune regression**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau`
Expected: PASS — `ALL ... TESTS PASSED` (RoundManager glue isn't lune-tested; this confirms the round-state logic it drives is intact).

- [ ] **Step 4: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(round): broadcast swapAtServerTime each cycle for the client timer"
```

---

## Task 7: ClientSwapHud — timer + telegraph + audio

**Files:**
- Create: `src/client/ClientSwapHud.luau`
- Modify: `src/client/init.client.luau`

- [ ] **Step 1: Create the controller**

Create `src/client/ClientSwapHud.luau`:

```lua
--[[
	ClientSwapHud -- the always-visible swap countdown + the T-3s telegraph.
	Location: StarterPlayerScripts/Client/ClientSwapHud  (ModuleScript)

	Reads `swapAtServerTime` off RoundStateChanged and renders via the pure
	SwapTelegraphModel: a small top-center timer always during Active, and during
	the last PREVIEW_SECONDS a ramping orange->red flash + a big centered 3/2/1 +
	a one-shot audio cue (Config.SWAP_WARNING_SOUND_ID; silent if "").
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
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.fromScale(0.5, 0.03)
	timer.Size = UDim2.fromScale(0.16, 0.08)
	timer.BackgroundTransparency = 1
	timer.TextScaled = true
	timer.Font = Enum.Font.GothamBold
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.TextStrokeTransparency = 0.4
	timer.Text = ""
	timer.ZIndex = 2
	timer.Parent = gui

	local big = Instance.new("TextLabel")
	big.Name = "BigCountdown"
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.fromScale(0.5, 0.4)
	big.Size = UDim2.fromScale(0.3, 0.3)
	big.BackgroundTransparency = 1
	big.TextScaled = true
	big.Font = Enum.Font.GothamBlack
	big.TextColor3 = Color3.new(1, 1, 1)
	big.TextStrokeTransparency = 0.2
	big.Text = ""
	big.ZIndex = 2
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
		if d.inPreview and d.bigCountdownInt then
			big.Text = tostring(d.bigCountdownInt)
			flash.BackgroundTransparency = 1 - (d.flashAlpha * 0.5) -- up to 50% opaque
			if d.bigCountdownInt ~= lastBigInt then
				lastBigInt = d.bigCountdownInt
				if warningSound and d.bigCountdownInt == Config.PREVIEW_SECONDS then
					warningSound:Play() -- one shot at telegraph entry
				end
			end
		else
			big.Text = ""
			flash.BackgroundTransparency = 1
		end
	end)
end

return ClientSwapHud
```

- [ ] **Step 2: Start it from the client bootstrap**

In `src/client/init.client.luau`, replace:

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
```

with (adds ClientSwapHud):

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)
local ClientSwapHud = require(script.ClientSwapHud)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
ClientSwapHud.start()
```

- [ ] **Step 3: Verify lune suite still green (no pure-logic regression)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/swap_telegraph_model.spec.luau`
Expected: PASS. (The HUD itself is verified live in Task 15.)

- [ ] **Step 4: Commit**

```bash
git add src/client/ClientSwapHud.luau src/client/init.client.luau
git commit -m "feat(client): ClientSwapHud live timer + T-3s telegraph"
```

---

## Task 8: SwapController + ControlManager — plan/commit + soul-color + SoulMap

**Files:**
- Modify: `src/server/SwapController.luau`
- Modify: `src/server/ControlManager.luau`

- [ ] **Step 1: Rewrite SwapController to expose plan/commit/validity**

Replace the body of `src/server/SwapController.luau` (everything from `local SwapController = {}` through `return SwapController`) with:

```lua
local ControlManager = require(script.Parent.ControlManager)

local SwapController = {}

-- Compute the next swap over `orderedAlive` WITHOUT applying it (drives the
-- T-3s preview). Returns a plan, or nil + message if too few players.
function SwapController.plan(orderedAlive)
	if #orderedAlive < 2 then
		return nil, "need >=2 alive players"
	end
	return ControlManager.planSwap(orderedAlive)
end

-- Apply a previously computed plan (the authoritative T0 commit). Returns how
-- many players were swapped.
function SwapController.commit(plan)
	return ControlManager.commitSwap(plan)
end

-- True iff `plan` still matches the current control map (re-plan decision).
function SwapController.planStillValid(plan)
	return ControlManager.planStillValid(plan)
end

-- Immediate plan+commit over `orderedAlive` (the no-preview forceSwap path).
function SwapController.swap(orderedAlive)
	if #orderedAlive < 2 then
		return false, "need >=2 alive players"
	end
	local plan = ControlManager.planSwap(orderedAlive)
	ControlManager.commitSwap(plan)
	return true, string.format("swapped %d players", #orderedAlive)
end

return SwapController
```

- [ ] **Step 2: Add plan/commit wrappers, soul colors, and the SoulMap broadcast to ControlManager**

In `src/server/ControlManager.luau`:

(a) Replace the require/remote header block:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ControlModel = require(ReplicatedStorage.Shared.ControlModel)
local BodyManager = require(script.Parent.BodyManager)
local SetControlledBody = Remotes.get("SetControlledBody")

local ControlManager = {}
local model = ControlModel.new()
```

with (adds Config, SoulPalette, the SoulMap remote, and soul-color state):

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ControlModel = require(ReplicatedStorage.Shared.ControlModel)
local SoulPalette = require(ReplicatedStorage.Shared.SoulPalette)
local Config = require(ReplicatedStorage.Shared.Config)
local BodyManager = require(script.Parent.BodyManager)
local SetControlledBody = Remotes.get("SetControlledBody")
local SoulMap = Remotes.get("SoulMap")

local ControlManager = {}
local model = ControlModel.new()

-- Per-player Soul colors, auto-assigned by join order (stable for the session).
local soulColor = {} -- [player] = Color3
local soulIndex = 0

-- Broadcast every controlled body's current Soul color so each client can place
-- a halo on it (and follow it across swaps). Built from the live control map.
function ControlManager.broadcastSoulMap()
	local list = {}
	for body, player in pairs(model.controllerOf) do
		local color = soulColor[player]
		if color then
			list[#list + 1] = { body = body, color = color }
		end
	end
	SoulMap:FireAllClients(list)
end
```

(b) Replace `ControlManager.addPlayer`:

```lua
function ControlManager.addPlayer(player, body)
	ControlModel.addPlayer(model, player, body)
	applyOwnership(player, body, false)
end
```

with (assigns a soul color, then broadcasts the map):

```lua
function ControlManager.addPlayer(player, body)
	soulIndex += 1
	soulColor[player] = SoulPalette.colorForIndex(soulIndex, Config.SOUL_PALETTE)
	ControlModel.addPlayer(model, player, body)
	applyOwnership(player, body, false)
	ControlManager.broadcastSoulMap()
end
```

(c) Replace the existing `ControlManager.swap` function:

```lua
function ControlManager.swap(orderedPlayers)
	local result = ControlModel.swap(model, orderedPlayers, function(n)
		return math.random(1, n)
	end)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, true)
	end
	return #result
end
```

with three functions (`planSwap`, `commitSwap`, `planStillValid`) — `swap` is no longer needed because RoundManager/SwapController now use plan+commit:

```lua
-- Compute the next swap without applying it (no ownership change, no notify).
function ControlManager.planSwap(orderedPlayers)
	return ControlModel.planSwap(model, orderedPlayers, function(n)
		return math.random(1, n)
	end)
end

-- Apply a plan: rotate network ownership + notify each client (isSwap = true),
-- then rebroadcast the Soul map (halos follow control). Returns how many moved.
function ControlManager.commitSwap(plan)
	local result = ControlModel.applySwap(model, plan)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, true)
	end
	ControlManager.broadcastSoulMap()
	return #result
end

-- True iff `plan` still matches the current control map (re-plan decision).
function ControlManager.planStillValid(plan)
	return ControlModel.planStillValid(model, plan)
end
```

(d) Replace `ControlManager.removePlayer`:

```lua
function ControlManager.removePlayer(player)
	local decision = ControlModel.removePlayer(model, player)
	if decision.reassign then
		applyOwnership(decision.reassign.player, decision.reassign.body, false)
	end
	if decision.destroyOwn then
		BodyManager.removeBody(player) -- destroys bodyByOwner[player] = the leaving player's avatar body
	end
end
```

with (clears the soul color and rebroadcasts):

```lua
function ControlManager.removePlayer(player)
	local decision = ControlModel.removePlayer(model, player)
	if decision.reassign then
		applyOwnership(decision.reassign.player, decision.reassign.body, false)
	end
	if decision.destroyOwn then
		BodyManager.removeBody(player) -- destroys bodyByOwner[player] = the leaving player's avatar body
	end
	soulColor[player] = nil
	ControlManager.broadcastSoulMap()
end
```

(e) Replace `ControlManager.resetControl`:

```lua
function ControlManager.resetControl()
	local result = ControlModel.resetControl(model)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, false)
	end
	return result
end
```

with (rebroadcasts so halos reset to owners at round start):

```lua
function ControlManager.resetControl()
	local result = ControlModel.resetControl(model)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, false)
	end
	ControlManager.broadcastSoulMap()
	return result
end
```

- [ ] **Step 3: Verify lune suite (control logic intact)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau`
Expected: PASS — `ALL CONTROLMODEL TESTS PASSED`. (The pure model is unchanged from Task 4; this confirms the glue rewrite didn't require touching it.)

- [ ] **Step 4: Commit**

```bash
git add src/server/SwapController.luau src/server/ControlManager.luau
git commit -m "feat(swap): plan/commit control flow + soul-color assignment + SoulMap broadcast"
```

---

## Task 9: RoundManager — free-play / preview / commit restructure

**Files:**
- Modify: `src/server/RoundManager.luau`

- [ ] **Step 1: Add the SwapPreview remote handle**

In `src/server/RoundManager.luau`, find the remotes block:

```lua
local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")
```

and add a `SwapPreview` line:

```lua
local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")
local SwapPreview = Remotes.get("SwapPreview")
```

- [ ] **Step 2: Replace doSwap with plan-aware commit helpers**

In `src/server/RoundManager.luau`, replace the entire `doSwap` function:

```lua
local function doSwap()
	local roster = aliveRoster()
	if #roster >= 2 then
		local ok, msg = SwapController.swap(roster)
		print("[BSR] swap:", ok, msg)
		if ok then
			-- Open a grace window for everyone who just swapped, and record the
			-- starting position of the body they now control so the monitor can
			-- tell when they have moved (oriented).
			local t = now()
			for _, player in ipairs(roster) do
				GraceModel.onSwap(grace, player, t, Config.GRACE_SECONDS, Config.GRACE_FLOOR_SECONDS)
				local body = ControlManager.getControlledBody(player)
				local root = body and body:FindFirstChild("HumanoidRootPart")
				swapPos[player] = root and root.Position or nil
			end
		end
	end
end
```

with these three functions (fire-preview, grace-stamp, and commit):

```lua
-- Tell each player in the plan which body they will inherit (drives the
-- client-side preview highlight). Fired at preview start and on any re-plan.
local function firePreview(plan)
	for _, pair in ipairs(plan.to) do
		SwapPreview:FireClient(pair.player, pair.body)
	end
end

-- After control has been committed, open the post-swap grace window for `players`
-- and record each one's new controlled-body position so the void monitor can
-- derive "has moved" (horizontal travel since the swap).
local function stampGrace(players)
	local t = now()
	for _, player in ipairs(players) do
		GraceModel.onSwap(grace, player, t, Config.GRACE_SECONDS, Config.GRACE_FLOOR_SECONDS)
		local body = ControlManager.getControlledBody(player)
		local root = body and body:FindFirstChild("HumanoidRootPart")
		swapPos[player] = root and root.Position or nil
	end
end

-- Commit a planned swap. The commit is authoritative over the CURRENT roster: if
-- the plan went stale during the preview window (someone died/left, or an absorb
-- moved a survivor), recompute over the live roster before applying. Aborts if
-- fewer than 2 remain (the round is ending).
local function commitSwap(plan)
	if not SwapController.planStillValid(plan) then
		local roster = aliveRoster()
		if #roster < 2 then
			return
		end
		plan = SwapController.plan(roster)
	end
	SwapController.commit(plan)
	local players = {}
	for _, pair in ipairs(plan.to) do
		players[#players + 1] = pair.player
	end
	stampGrace(players)
end

-- Immediate plan+commit (no preview) -- used by forceSwap for the smoke test.
local function doSwap()
	local roster = aliveRoster()
	if #roster >= 2 then
		local plan = SwapController.plan(roster)
		commitSwap(plan)
	end
end
```

- [ ] **Step 3: Restructure runActivePhase into free-play / preview / commit**

In `src/server/RoundManager.luau`, replace the `runActivePhase` function (the Task 6 version) with:

```lua
-- Wait up to `seconds`, breaking early if the round leaves Active. Polls at the
-- same 0.25s cadence used elsewhere.
local function waitActive(seconds)
	local elapsed = 0
	while elapsed < seconds and RoundState.getPhase(model) == "Active" do
		task.wait(0.25)
		elapsed += 0.25
	end
end

-- Spin during Active. Each cycle: broadcast the swap deadline, free-play for
-- (CYCLE - PREVIEW), then run the PREVIEW window (plan + per-client preview,
-- re-planning if the roster churns), then commit the swap at T0.
local function runActivePhase()
	while RoundState.getPhase(model) == "Active" do
		broadcastState(nil, workspace:GetServerTimeNow() + Config.CYCLE_SECONDS)

		-- Free play.
		waitActive(Config.CYCLE_SECONDS - Config.PREVIEW_SECONDS)
		if RoundState.getPhase(model) ~= "Active" then
			break
		end

		-- Preview window: plan now and tell each client their target body.
		local plan = nil
		local roster = aliveRoster()
		if #roster >= 2 then
			plan = SwapController.plan(roster)
			firePreview(plan)
		end

		local elapsed = 0
		while elapsed < Config.PREVIEW_SECONDS and RoundState.getPhase(model) == "Active" do
			task.wait(0.25)
			elapsed += 0.25
			-- Re-plan if the roster changed mid-preview (death / disconnect / absorb).
			if plan and not SwapController.planStillValid(plan) then
				roster = aliveRoster()
				if #roster >= 2 then
					plan = SwapController.plan(roster)
					firePreview(plan)
				else
					plan = nil
				end
			end
		end
		if RoundState.getPhase(model) ~= "Active" then
			break
		end

		-- Commit at T0.
		if plan then
			commitSwap(plan)
		end
	end
end
```

- [ ] **Step 4: Verify round-state logic still green**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done`
Expected: every spec prints `ALL ... TESTS PASSED`. (RoundManager glue is verified live in Task 15.)

- [ ] **Step 5: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(round): free-play/preview/commit cycle with re-plan on roster change"
```

---

## Task 10: SwapPreviewController — highlight the target body

**Files:**
- Create: `src/client/SwapPreviewController.luau`
- Modify: `src/client/init.client.luau`

- [ ] **Step 1: Create the controller**

Create `src/client/SwapPreviewController.luau`:

```lua
--[[
	SwapPreviewController -- highlights the body THIS client is about to inherit.
	Location: StarterPlayerScripts/Client/SwapPreviewController  (ModuleScript)

	On SwapPreview(body) (fired during the T-3s window) it outlines that body with
	a local Highlight, so the preview is a readable challenge. The outline clears
	on the next control retarget (the commit's SetControlledBody) or when the round
	leaves Active.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local SwapPreview = Remotes.get("SwapPreview")
local SetControlledBody = Remotes.get("SetControlledBody")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local SwapPreviewController = {}
local highlight = nil

local function clear()
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

function SwapPreviewController.start()
	SwapPreview.OnClientEvent:Connect(function(body)
		clear()
		if body and body:IsA("Model") then
			highlight = Instance.new("Highlight")
			highlight.Name = "SwapTargetHighlight"
			highlight.FillColor = Color3.fromRGB(255, 200, 60)
			highlight.FillTransparency = 0.6
			highlight.OutlineColor = Color3.fromRGB(255, 220, 120)
			highlight.Adornee = body
			highlight.Parent = body
		end
	end)

	-- The commit retargets control -> the preview is over.
	SetControlledBody.OnClientEvent:Connect(clear)

	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state.phase ~= "Active" then
			clear()
		end
	end)
end

return SwapPreviewController
```

- [ ] **Step 2: Start it from the client bootstrap**

In `src/client/init.client.luau`, replace:

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)
local ClientSwapHud = require(script.ClientSwapHud)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
ClientSwapHud.start()
```

with:

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)
local ClientSwapHud = require(script.ClientSwapHud)
local SwapPreviewController = require(script.SwapPreviewController)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
ClientSwapHud.start()
SwapPreviewController.start()
```

- [ ] **Step 3: Commit**

```bash
git add src/client/SwapPreviewController.luau src/client/init.client.luau
git commit -m "feat(client): SwapPreviewController highlights the inherited body"
```

---

## Task 11: SoulController — halos + self-emphasis

**Files:**
- Create: `src/client/SoulController.luau`
- Modify: `src/client/init.client.luau`

- [ ] **Step 1: Create the controller**

Create `src/client/SoulController.luau`:

```lua
--[[
	SoulController -- the free Soul identity halo.
	Location: StarterPlayerScripts/Client/SoulController  (ModuleScript)

	Renders a colored halo above every controlled body from the SoulMap broadcast
	(color = whoever currently controls that body), so you can recognize players
	across swaps. THIS client's own controlled body (from SetControlledBody) gets
	an emphasized halo so "which one is me?" is unmistakable after the camera cut.
	(Grace shimmer is added in Task 12.)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local SoulMap = Remotes.get("SoulMap")
local SetControlledBody = Remotes.get("SetControlledBody")

local SoulController = {}
local myBody = nil
local halos = {} -- [body] = BillboardGui

local SIZE_MINE = UDim2.fromOffset(42, 42)
local SIZE_OTHER = UDim2.fromOffset(24, 24)

local function makeHalo(head)
	local halo = Instance.new("BillboardGui")
	halo.Name = "SoulHalo"
	halo.Size = SIZE_OTHER
	halo.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	halo.AlwaysOnTop = true
	halo.Adornee = head
	halo.Parent = head

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromScale(1, 1)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.Parent = halo

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Emphasis"
	stroke.Thickness = 0
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Parent = dot

	return halo
end

local function applyEmphasis(body, halo)
	local isMine = (body == myBody)
	halo.Size = isMine and SIZE_MINE or SIZE_OTHER
	local stroke = halo:FindFirstChild("Dot") and halo.Dot:FindFirstChild("Emphasis")
	if stroke then
		stroke.Thickness = isMine and 3 or 0
	end
end

local function reconcile(list)
	local seen = {}
	for _, entry in ipairs(list) do
		local body, color = entry.body, entry.color
		if body and body.Parent then
			local head = body:FindFirstChild("Head") or body:FindFirstChild("HumanoidRootPart")
			if head then
				seen[body] = true
				local halo = halos[body]
				if not halo or halo.Parent ~= head then
					if halo then halo:Destroy() end
					halo = makeHalo(head)
					halos[body] = halo
				end
				local dot = halo:FindFirstChild("Dot")
				if dot then
					dot.BackgroundColor3 = color
				end
				applyEmphasis(body, halo)
			end
		end
	end
	-- Drop halos for bodies no longer in the map.
	for body, halo in pairs(halos) do
		if not seen[body] then
			halo:Destroy()
			halos[body] = nil
		end
	end
end

function SoulController.start()
	SoulMap.OnClientEvent:Connect(reconcile)

	SetControlledBody.OnClientEvent:Connect(function(body)
		myBody = body
		-- Re-emphasize immediately (don't wait for the next SoulMap broadcast).
		for b, halo in pairs(halos) do
			applyEmphasis(b, halo)
		end
	end)
end

return SoulController
```

- [ ] **Step 2: Start it from the client bootstrap**

In `src/client/init.client.luau`, replace:

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)
local ClientSwapHud = require(script.ClientSwapHud)
local SwapPreviewController = require(script.SwapPreviewController)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
ClientSwapHud.start()
SwapPreviewController.start()
```

with:

```lua
local ClientControl = require(script.ClientControl)
local ClientAnimator = require(script.ClientAnimator)
local ClientRoundHud = require(script.ClientRoundHud)
local ClientSwapHud = require(script.ClientSwapHud)
local SwapPreviewController = require(script.SwapPreviewController)
local SoulController = require(script.SoulController)

ClientControl.start()
ClientAnimator.start()
ClientRoundHud.start()
ClientSwapHud.start()
SwapPreviewController.start()
SoulController.start()
```

- [ ] **Step 3: Commit**

```bash
git add src/client/SoulController.luau src/client/init.client.luau
git commit -m "feat(client): SoulController halos with self-emphasis"
```

---

## Task 12: SoulController — grace shield shimmer

**Files:**
- Modify: `src/client/SoulController.luau`

- [ ] **Step 1: Add the shimmer (triggered by a swap retarget)**

In `src/client/SoulController.luau`:

(a) Add the services + Config require at the top. Replace:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local SoulMap = Remotes.get("SoulMap")
local SetControlledBody = Remotes.get("SetControlledBody")
```

with:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SoulMap = Remotes.get("SoulMap")
local SetControlledBody = Remotes.get("SetControlledBody")
```

(b) Add the shimmer function just above `function SoulController.start()`:

```lua
-- A brief shield shimmer on the body you just swapped into, mirroring the
-- post-swap grace window: it pulses for up to GRACE_SECONDS and fades early once
-- you've moved (after the GRACE_FLOOR_SECONDS hard floor). Cosmetic only -- the
-- server owns the real grace gate; this approximates its feel from local input.
local shimmerToken = nil

local function playGraceShimmer(body)
	if not (body and body.Parent) then
		return
	end
	local token = {}
	shimmerToken = token

	local hl = Instance.new("Highlight")
	hl.Name = "GraceShimmer"
	hl.FillColor = Color3.fromRGB(120, 200, 255)
	hl.OutlineColor = Color3.fromRGB(200, 240, 255)
	hl.FillTransparency = 0.6
	hl.Adornee = body
	hl.Parent = body

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
		while shimmerToken == token do
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
end
```

(c) Trigger it on a swap retarget. Replace the `SetControlledBody.OnClientEvent` handler inside `SoulController.start()`:

```lua
	SetControlledBody.OnClientEvent:Connect(function(body)
		myBody = body
		-- Re-emphasize immediately (don't wait for the next SoulMap broadcast).
		for b, halo in pairs(halos) do
			applyEmphasis(b, halo)
		end
	end)
```

with (adds the `isSwap` param + shimmer):

```lua
	SetControlledBody.OnClientEvent:Connect(function(body, isSwap)
		myBody = body
		-- Re-emphasize immediately (don't wait for the next SoulMap broadcast).
		for b, halo in pairs(halos) do
			applyEmphasis(b, halo)
		end
		if isSwap and body then
			playGraceShimmer(body)
		end
	end)
```

- [ ] **Step 2: Commit**

```bash
git add src/client/SoulController.luau
git commit -m "feat(client): post-swap grace shield shimmer on the Soul body"
```

---

## Task 13: Full lune suite green

**Files:** none (verification only)

- [ ] **Step 1: Run every spec**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done`
Expected: each of `control_model`, `grace_model`, `round_state`, `tile_field_model`, `swap_telegraph_model`, `soul_palette` prints its `ALL ... TESTS PASSED` line; the loop exits 0.

- [ ] **Step 2: (No commit — verification gate.)** If anything failed, stop and fix before the smoke test.

---

## Task 14: Studio smoke-test doc

**Files:**
- Create: `docs/smoke-tests/2026-06-19-swap-legibility-smoke-test.md`

- [ ] **Step 1: Write the smoke-test procedure**

Create `docs/smoke-tests/2026-06-19-swap-legibility-smoke-test.md`:

```markdown
# Smoke Test — Swap Legibility (2026-06-19)

Runtime behavior lune can't cover: the telegraph HUD, truthful preview,
Soul halos, and the grace shimmer. Run in Studio with **2 players**
(Test → Clients and Server, 2 players).

Prereqs: builds via Rojo; `Config.SWAP_WARNING_SOUND_ID` may be "" (silent is OK).
Force a swap from the server command bar with `require(...).forceSwap()` only if a
test calls for it (otherwise let the 30s cycle run). To reach RoundManager from the
command bar: `local RM = require(game.ServerScriptService.Server.RoundManager)`.

## 1. Live timer
- [ ] During Active, a countdown number is visible top-center on both clients.
- [ ] It decreases ~1/sec and reaches the low single digits right before a swap.
- [ ] It is blank in Lobby / Ended.

## 2. Telegraph (T-3s)
- [ ] In the last ~3s before a swap, a big 3 / 2 / 1 appears centered and an
      orange→red flash ramps up.
- [ ] If a sound id is set, the rumble plays once as the telegraph begins.
- [ ] The flash/countdown clear at the swap.

## 3. Truthful preview
- [ ] During the telegraph, exactly one other body is outlined (the one you're
      about to inherit).
- [ ] After the swap, the body you now control IS the body that was outlined.
- [ ] The outline clears at the swap.

## 4. Soul halos + self-emphasis
- [ ] Each body has a colored halo; the two players' colors differ.
- [ ] Your OWN controlled body's halo is visibly emphasized (larger + outlined)
      on your screen.
- [ ] After a swap, the halos follow control: your color moves to your new body,
      and emphasis stays on the body you now drive.

## 5. Grace shimmer
- [ ] Right after a swap, a brief blue shimmer pulses on the body you inherited.
- [ ] It fades early once you start moving (after the ~0.5s floor); if you stay
      still it lasts ~1.5s.

## 6. Roster-changed-during-preview (the correctness edge)
- [ ] With 2 players alive, during the 3s preview window force the round toward a
      change: e.g. walk one body off into the void just as the telegraph starts,
      or call `RM.forceSwap()` repeatedly to churn. 
- [ ] Confirm: no Lua errors in the Output; control stays a clean bijection (no
      body with two controllers, nobody stuck uncontrolled); if one player dies
      the round ends cleanly with the survivor as winner.
- [ ] With 3+ test players (optional): eliminate one mid-preview and confirm the
      surviving two still swap to valid, distinct bodies.

## Result
- [ ] All sections pass. Note Studio version + date below.
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-19-swap-legibility-smoke-test.md
git commit -m "docs: swap-legibility 2-client Studio smoke test"
```

- [ ] **Step 3: Run the smoke test in Studio**

Open the place in Studio, run the 2-client test, and walk the checklist. This is
manual and cannot be automated here; record the outcome (and check the boxes) in
the doc. Fix any runtime issues found and re-commit before considering the feature
done.

---

## Self-review notes (for the executor)

- **Spec coverage:** timer (T6/T7), telegraph+audio (T7), preview plan/commit
  (T4/T8/T9/T10), Soul halo + self-emphasis (T3/T8/T11), grace shimmer (T12),
  pure tests (T2/T3/T4), smoke test (T14) — all spec §2 deliverables mapped.
- **Type consistency:** `plan = { from, to }`; `plan.to[i] = { player, body }`;
  `SoulMap` payload `= { { body, color }, ... }`; `SwapPreview` carries a single
  `body`. `ControlManager.commitSwap` returns a count; `SwapController.plan`
  returns the plan (or nil+msg). These names are used identically across T4/T8/T9.
- **Glue is not lune-tested** by design (Roblox APIs); its verification is the
  full suite staying green + the Task 14 Studio smoke test.
```
