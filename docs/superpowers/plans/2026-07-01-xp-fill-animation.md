# Animated XP Fill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animate the end-of-round reward panel's XP bar — smooth fill, a pop/flash/level-tick moment on level-up, and a counting-up `+XP` number.

**Architecture:** A new pure, lune-tested `XpFillModel` computes the fill *geometry* (ordered segments across level boundaries, final level/progress) from the pre-award state + XP delta. `ClientEconomyHud` plays that geometry with TweenService/RunService using Config timing. `EconomyService.awardRound` adds a pre-award `before` snapshot to the `RewardGranted` payload so the client animation is self-contained.

**Tech Stack:** Luau, Rojo, lune (`export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`), Roblox TweenService/RunService, runtime `RemoteEvent`s.

**Conventions:** Pure modules are Roblox-free and take dependencies via injected `opts` (no `require` of Config or sibling modules — lune has no `script`). `XpFillModel` therefore takes an injected `opts.xpForLevel` function rather than requiring `ProgressionModel`. Test harness mirrors `tests/reward_model.spec.luau` (`require("../src/shared/<Module>")`, multi-line `expect`/`fail`, `do ... end` blocks, final `ALL ... PASSED`). A `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer on commits is fine.

---

### Task 1: Config XP-fill timing block

**Files:**
- Modify: `src/shared/Config.luau` (append before `return Config`)

- [ ] **Step 1: Add the timing block**

Insert immediately before the final `return Config` line:

```lua
-- ===== Animated XP fill (reward panel) =====
-- Timing only; the fill GEOMETRY (segments across level boundaries) is pure
-- (XpFillModel). Consumed by ClientEconomyHud's timeline player.
Config.REWARD_XP_FILL_SECONDS = 1.2        -- total bar-fill time, any XP amount
Config.REWARD_LEVELUP_PAUSE_SECONDS = 0.3  -- hold at each level-up (pop/flash)
Config.REWARD_PANEL_HOLD_SECONDS = 2.5     -- readable beat after the animation completes
Config.REWARD_LEVELUP_POP_SCALE = 1.08     -- panel scale-punch peak on level-up
Config.REWARD_LEVELUP_FLASH_COLOR = Color3.fromRGB(255, 246, 200) -- bright surge tint
```

- [ ] **Step 2: Sanity-check the repo still runs**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/reward_model.spec.luau`
Expected: `ALL RewardModel TESTS PASSED`

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(economy): add animated XP-fill timing tunables to Config"
```

---

### Task 2: XpFillModel (pure) + tests

**Files:**
- Create: `src/shared/XpFillModel.luau`
- Test: `tests/xp_fill_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/xp_fill_model.spec.luau`:

```lua
local XpFillModel = require("../src/shared/XpFillModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local function approx(a, b)
	return math.abs(a - b) < 1e-6
end

-- Flat curve: every level costs 100. maxLevel high so no clamping.
local FLAT = { maxLevel = 100, xpForLevel = function() return 100 end }

-- No level-up: fills within the current level.
do
	local r = XpFillModel.build({ level = 3, xpIntoLevel = 20, xpForNext = 100 }, 30, FLAT)
	expect(#r.segments == 1, "one segment, got " .. tostring(#r.segments))
	local s = r.segments[1]
	expect(s.level == 3, "segment level 3")
	expect(approx(s.fromProgress, 0.2), "from 0.2, got " .. tostring(s.fromProgress))
	expect(approx(s.toProgress, 0.5), "to 0.5, got " .. tostring(s.toProgress))
	expect(s.xpSpan == 30, "span 30, got " .. tostring(s.xpSpan))
	expect(s.levelUpAfter == false, "no level-up")
	expect(r.totalSpan == 30, "totalSpan 30")
	expect(r.finalLevel == 3, "final level 3")
	expect(approx(r.finalProgress, 0.5), "final progress 0.5")
	print("xp-fill: no-levelup OK")
end

-- Exactly one level-up.
do
	local r = XpFillModel.build({ level = 3, xpIntoLevel = 80, xpForNext = 100 }, 50, FLAT)
	expect(#r.segments == 2, "two segments, got " .. tostring(#r.segments))
	expect(approx(r.segments[1].fromProgress, 0.8), "seg1 from 0.8")
	expect(approx(r.segments[1].toProgress, 1), "seg1 to 1.0")
	expect(r.segments[1].xpSpan == 20, "seg1 span 20")
	expect(r.segments[1].levelUpAfter == true, "seg1 levels up")
	expect(r.segments[2].level == 4, "seg2 level 4")
	expect(approx(r.segments[2].fromProgress, 0), "seg2 from 0")
	expect(approx(r.segments[2].toProgress, 0.3), "seg2 to 0.3")
	expect(r.segments[2].xpSpan == 30, "seg2 span 30")
	expect(r.segments[2].levelUpAfter == false, "seg2 no level-up")
	expect(r.totalSpan == 50, "totalSpan 50")
	expect(r.finalLevel == 4, "final level 4")
	expect(approx(r.finalProgress, 0.3), "final progress 0.3")
	print("xp-fill: one-levelup OK")
end

-- Lands exactly on a level boundary: one full segment, ends at the new level / 0 progress.
do
	local r = XpFillModel.build({ level = 3, xpIntoLevel = 80, xpForNext = 100 }, 20, FLAT)
	expect(#r.segments == 1, "one segment")
	expect(approx(r.segments[1].toProgress, 1), "fills to full")
	expect(r.segments[1].levelUpAfter == true, "levels up")
	expect(r.finalLevel == 4, "final level 4")
	expect(approx(r.finalProgress, 0), "final progress 0 (fresh level)")
	print("xp-fill: exact-boundary OK")
end

-- Multiple level-ups in one award.
do
	local r = XpFillModel.build({ level = 1, xpIntoLevel = 0, xpForNext = 100 }, 250, FLAT)
	expect(#r.segments == 3, "three segments, got " .. tostring(#r.segments))
	expect(r.segments[1].levelUpAfter == true and r.segments[2].levelUpAfter == true, "first two level up")
	expect(r.segments[3].levelUpAfter == false, "last does not")
	expect(r.segments[3].level == 3, "ends on level 3")
	expect(approx(r.segments[3].toProgress, 0.5), "ends at 0.5")
	expect(r.totalSpan == 250, "totalSpan 250")
	expect(r.finalLevel == 3 and approx(r.finalProgress, 0.5), "final 3 @ 0.5")
	print("xp-fill: multi-levelup OK")
end

-- Max-level clamp: the fill stops at maxLevel, bar rests full, excess discarded.
do
	local opts = { maxLevel = 100, xpForLevel = function() return 100 end }
	local r = XpFillModel.build({ level = 99, xpIntoLevel = 0, xpForNext = 100 }, 500, opts)
	expect(#r.segments == 1, "one segment (then clamps)")
	expect(r.segments[1].level == 99, "segment level 99")
	expect(r.segments[1].levelUpAfter == true, "levels up into max")
	expect(r.totalSpan == 100, "only 100 of the 500 fills the bar")
	expect(r.finalLevel == 100, "final level 100 (max)")
	expect(approx(r.finalProgress, 1), "rests full at max")
	print("xp-fill: max-clamp OK")
end

-- Already at max: nothing animates, rests full.
do
	local r = XpFillModel.build({ level = 100, xpIntoLevel = 0, xpForNext = 0 }, 50, FLAT)
	expect(#r.segments == 0, "no segments")
	expect(r.totalSpan == 0, "no span")
	expect(r.finalLevel == 100, "stays max")
	expect(approx(r.finalProgress, 1), "rests full")
	print("xp-fill: already-max OK")
end

-- Zero / negative delta: nothing animates, rests at the start fraction.
do
	local r = XpFillModel.build({ level = 2, xpIntoLevel = 30, xpForNext = 100 }, 0, FLAT)
	expect(#r.segments == 0, "no segments for 0 delta")
	expect(r.finalLevel == 2 and approx(r.finalProgress, 0.3), "rests at start 0.3")
	local n = XpFillModel.build({ level = 2, xpIntoLevel = 30, xpForNext = 100 }, -10, FLAT)
	expect(#n.segments == 0, "no segments for negative delta")
	print("xp-fill: zero-negative OK")
end

-- Invariant: sum of xpSpan equals totalSpan, on a varied curve.
do
	local opts = { maxLevel = 100, xpForLevel = function(l) return 100 + l end }
	local r = XpFillModel.build({ level = 5, xpIntoLevel = 10, xpForNext = 105 }, 400, opts)
	local sum = 0
	for _, s in ipairs(r.segments) do sum += s.xpSpan end
	expect(sum == r.totalSpan, "sum(xpSpan) == totalSpan")
	print("xp-fill: span-invariant OK")
end

print("ALL XpFillModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/xp_fill_model.spec.luau`
Expected: FAIL (cannot require `XpFillModel`).

- [ ] **Step 3: Write the implementation**

Create `src/shared/XpFillModel.luau`:

```lua
--[[
	XpFillModel -- PURE animated-XP-fill timeline. Roblox-free, no clocks/RNG.
	Given the pre-award level state + the XP delta + progression opts, returns the
	ordered fill SEGMENTS the renderer tweens (one per level touched) plus the final
	level/progress. Geometry only -- TIMING lives in the client (Config). The level
	costs are INJECTED (opts.xpForLevel) so this module needs no Roblox `script`
	require, keeping it lune-testable (mirrors how the repo injects dependencies).
	Location (Roblox): ReplicatedStorage/Shared/XpFillModel  (ModuleScript)

	start = { level, xpIntoLevel, xpForNext }   -- xpForNext = 0 at max level
	opts  = { maxLevel, xpForLevel = function(level) -> number }  -- cost to finish `level`
	Returns { segments, totalSpan, finalLevel, finalProgress }.
	segment = { level, fromProgress, toProgress, xpSpan, levelUpAfter }
--]]

local XpFillModel = {}

local function fractionOf(intoLevel, forNext)
	if forNext and forNext > 0 then
		return intoLevel / forNext
	end
	return 0
end

function XpFillModel.build(start, deltaXp, opts)
	local level = start.level
	local intoLevel = start.xpIntoLevel
	local forNext = start.xpForNext
	local remaining = math.max(0, math.floor(deltaXp))

	-- Nothing animates: no XP, already at/over max, or no "next" to fill toward.
	if remaining <= 0 or level >= opts.maxLevel or forNext <= 0 then
		local finalProgress = (level >= opts.maxLevel) and 1 or fractionOf(intoLevel, forNext)
		return {
			segments = {},
			totalSpan = 0,
			finalLevel = math.min(level, opts.maxLevel),
			finalProgress = finalProgress,
		}
	end

	local segments = {}
	local totalSpan = 0
	while remaining > 0 do
		local need = forNext - intoLevel -- XP to finish THIS level
		if remaining < need then
			-- Ends within this level (no level-up).
			local toInto = intoLevel + remaining
			segments[#segments + 1] = {
				level = level,
				fromProgress = fractionOf(intoLevel, forNext),
				toProgress = fractionOf(toInto, forNext),
				xpSpan = remaining,
				levelUpAfter = false,
			}
			totalSpan += remaining
			intoLevel = toInto
			remaining = 0
		else
			-- Fills the rest of this level -> level-up.
			segments[#segments + 1] = {
				level = level,
				fromProgress = fractionOf(intoLevel, forNext),
				toProgress = 1,
				xpSpan = need,
				levelUpAfter = true,
			}
			totalSpan += need
			remaining -= need
			level += 1
			intoLevel = 0
			if level >= opts.maxLevel then
				break -- reached max: stop; bar rests full on the final level
			end
			forNext = opts.xpForLevel(level)
		end
	end

	local finalProgress = (level >= opts.maxLevel) and 1 or fractionOf(intoLevel, forNext)
	return {
		segments = segments,
		totalSpan = totalSpan,
		finalLevel = level,
		finalProgress = finalProgress,
	}
end

return XpFillModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/xp_fill_model.spec.luau`
Expected: `ALL XpFillModel TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add src/shared/XpFillModel.luau tests/xp_fill_model.spec.luau
git commit -m "feat(economy): pure XpFillModel (XP-fill timeline geometry), lune-tested"
```

---

### Task 3: EconomyService sends a pre-award `before` snapshot

**Files:**
- Modify: `src/server/EconomyService.luau` (the `awardRound` function)

- [ ] **Step 1: Replace `awardRound`**

Find the current `awardRound` function:

```lua
function EconomyService.awardRound(player, ctx)
	local profile = profiles[player]
	if not profile then
		return -- player left mid-round (profile already saved + dropped)
	end
	local before = ProgressionModel.levelFor(profile.totalXp, progressionOpts()).level
	local reward = RewardModel.rewardFor(ctx, rewardOpts())
	profile.coins += reward.coins
	profile.totalXp += reward.xp
	local after = ProgressionModel.levelFor(profile.totalXp, progressionOpts()).level
	RewardGranted:FireClient(player, {
		coins = reward.coins,
		xp = reward.xp,
		leveledUp = after > before,
	})
	pushProfile(player)
end
```

Replace it with (capture the full pre-award view and include it as `before`):

```lua
function EconomyService.awardRound(player, ctx)
	local profile = profiles[player]
	if not profile then
		return -- player left mid-round (profile already saved + dropped)
	end
	-- Pre-award snapshot drives the client's XP-fill animation (XpFillModel start state).
	local beforeLv = ProgressionModel.levelFor(profile.totalXp, progressionOpts())
	local reward = RewardModel.rewardFor(ctx, rewardOpts())
	profile.coins += reward.coins
	profile.totalXp += reward.xp
	local afterLevel = ProgressionModel.levelFor(profile.totalXp, progressionOpts()).level
	RewardGranted:FireClient(player, {
		coins = reward.coins,
		xp = reward.xp,
		leveledUp = afterLevel > beforeLv.level,
		before = {
			level = beforeLv.level,
			xpIntoLevel = beforeLv.xpIntoLevel,
			xpForNext = beforeLv.xpForNext,
		},
	})
	pushProfile(player)
end
```

- [ ] **Step 2: Sanity-check the pure suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/progression_model.spec.luau`
Expected: `ALL ProgressionModel TESTS PASSED` (EconomyService isn't lune-tested; this confirms its pure dependency is intact).

- [ ] **Step 3: Commit**

```bash
git add src/server/EconomyService.luau
git commit -m "feat(economy): include pre-award 'before' snapshot in RewardGranted"
```

---

### Task 4: ClientEconomyHud plays the animated fill

**Files:**
- Modify: `src/client/ClientEconomyHud.luau`

GUI is not lune-testable; verified via Studio MCP + the smoke doc (Task 5). Make the edits below in order.

- [ ] **Step 1: Add requires for Config, the two pure modules, and the Roblox services**

Find:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardScreenModel = require(Shared:WaitForChild("RewardScreenModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))
```

Replace with:

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RewardScreenModel = require(Shared:WaitForChild("RewardScreenModel"))
local XpFillModel = require(Shared:WaitForChild("XpFillModel"))
local ProgressionModel = require(Shared:WaitForChild("ProgressionModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))
```

- [ ] **Step 2: Replace the upvalue block (add `animToken`, drop the fixed visible constant)**

Find:

```lua
local balanceCoins, balanceLevel       -- persistent readout labels
local rewardRoot, rewardCoins, rewardXp, rewardLevel, rewardBarFill -- reward panel
local rewardHandle                     -- makePanel handle; setPanelAccent needs the table, not a Frame
local PANEL_VISIBLE_SECONDS = 4.5
local hideToken = nil
```

Replace with:

```lua
local balanceCoins, balanceLevel       -- persistent readout labels
local rewardRoot, rewardCoins, rewardXp, rewardLevel, rewardBarFill -- reward panel
local rewardHandle                     -- makePanel handle; setPanelAccent needs the table, not a Frame
local hideToken = nil  -- generation token: a newer reward cancels the prior hide
local animToken = nil  -- same token gates the running fill coroutine (cancel-on-retrigger)
```

- [ ] **Step 3: Add the progression-opts helper + the timeline player above `applyView`**

Find the line `local function applyView(view)` and insert the following ABOVE it:

```lua
-- Progression tunables for XpFillModel's injected xpForLevel + the start fraction.
local function progressionOpts()
	return {
		coeff = Config.PROGRESSION_XP_COEFF,
		exp = Config.PROGRESSION_XP_EXP,
		maxLevel = Config.PROGRESSION_MAX_LEVEL,
	}
end

local function setBar(p)
	rewardBarFill.Size = UDim2.fromScale(math.clamp(p, 0, 1), 1)
end

-- The level-up "moment": tick the label, scale-punch the panel, surge the bar color.
local function playLevelUpMoment(newLevel)
	rewardLevel.Text = "Level " .. tostring(newLevel)
	local scale = rewardRoot:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = rewardRoot
	TweenService:Create(
		scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = Config.REWARD_LEVELUP_POP_SCALE }
	):Play()
	task.delay(0.12, function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	rewardBarFill.BackgroundColor3 = Config.REWARD_LEVELUP_FLASH_COLOR
	TweenService:Create(
		rewardBarFill,
		TweenInfo.new(Config.REWARD_LEVELUP_PAUSE_SECONDS),
		{ BackgroundColor3 = HudTheme.Accent.win.top }
	):Play()
end

-- Play the XpFillModel timeline: fill each segment proportionally to its xpSpan over
-- a fixed total time, count the +XP up, and run the level-up moment between segments.
-- `token` gates cancellation (a newer reward replaces animToken). Driven by Heartbeat
-- so the bar fill + number count-up + segment transitions stay in lockstep.
local function playTimeline(token, plan, delta)
	if #plan.segments == 0 or plan.totalSpan <= 0 then
		-- Nothing to animate: rest on the final state immediately.
		setBar(plan.finalProgress)
		rewardLevel.Text = "Level " .. tostring(plan.finalLevel)
		rewardXp.Text = "+" .. tostring(math.max(0, math.floor(delta))) .. " XP"
		return
	end

	local FILL = Config.REWARD_XP_FILL_SECONDS
	local PAUSE = Config.REWARD_LEVELUP_PAUSE_SECONDS
	local fillElapsed = 0 -- cumulative fill time (excludes pauses); drives the +XP count-up

	for i, seg in ipairs(plan.segments) do
		rewardLevel.Text = "Level " .. tostring(seg.level)
		local dur = FILL * (seg.xpSpan / plan.totalSpan)
		local t = 0
		while t < dur do
			if token ~= animToken then return end
			local dt = RunService.Heartbeat:Wait()
			t = math.min(dur, t + dt)
			local f = t / dur
			setBar(seg.fromProgress + (seg.toProgress - seg.fromProgress) * f)
			local xpShown = math.floor(delta * math.min(1, (fillElapsed + t) / FILL))
			rewardXp.Text = "+" .. tostring(xpShown) .. " XP"
		end
		fillElapsed += dur
		if seg.levelUpAfter then
			if token ~= animToken then return end
			playLevelUpMoment(seg.level + 1)
			-- Reposition for the next segment (fresh level at 0) or the final rest
			-- (full at max level, else the start of the next level).
			local nextSeg = plan.segments[i + 1]
			setBar(nextSeg and nextSeg.fromProgress or plan.finalProgress)
			local p = 0
			while p < PAUSE do
				if token ~= animToken then return end
				p += RunService.Heartbeat:Wait()
			end
		end
	end

	if token ~= animToken then return end
	-- Settle exactly on the authoritative final state.
	setBar(plan.finalProgress)
	rewardLevel.Text = "Level " .. tostring(plan.finalLevel)
	rewardXp.Text = "+" .. tostring(math.floor(delta)) .. " XP"
end
```

- [ ] **Step 4: Replace `showReward` with the animated orchestrator**

Find the current `showReward` function (from `local function showReward(grant)` through its closing `end` before `function ClientEconomyHud.start()`):

```lua
local function showReward(grant)
	local d = RewardScreenModel.display(grant, lastView)
	if not d.visible then
		return
	end
	rewardLevel.Text = d.levelText
	rewardCoins.Text = d.coinsText
	rewardXp.Text = d.xpText
	rewardBarFill.Size = UDim2.fromScale(math.clamp(d.levelBarProgress or 0, 0, 1), 1)
	HudTheme.setPanelAccent(rewardHandle, d.leveledUp and "win" or "neutral")
	rewardRoot.Visible = true
	HudTheme.popIn(rewardRoot)

	-- Auto-hide after a few seconds; a newer reward cancels the previous timer.
	local token = {}
	hideToken = token
	task.delay(PANEL_VISIBLE_SECONDS, function()
		if hideToken == token then
			rewardRoot.Visible = false
		end
	end)
end
```

Replace it with:

```lua
local function showReward(grant)
	local d = RewardScreenModel.display(grant, lastView)
	if not d.visible then
		return
	end

	-- Coins render instantly (XP is the animated focus).
	rewardCoins.Text = d.coinsText

	-- Build the fill timeline from the pre-award snapshot in the payload (self-contained;
	-- independent of ProfileUpdated arrival order). xpForLevel is injected so XpFillModel
	-- stays Roblox-free.
	local start = grant.before
	local opts = progressionOpts()
	local plan = XpFillModel.build(start, grant.xp, {
		maxLevel = opts.maxLevel,
		xpForLevel = function(level)
			return ProgressionModel.xpForLevel(level, opts)
		end,
	})

	-- Initial visual state: start level, start fraction, +0 XP.
	local startProgress
	if start.xpForNext and start.xpForNext > 0 then
		startProgress = start.xpIntoLevel / start.xpForNext
	elseif start.level >= opts.maxLevel then
		startProgress = 1
	else
		startProgress = 0
	end
	rewardLevel.Text = "Level " .. tostring(start.level)
	rewardXp.Text = "+0 XP"
	rewardBarFill.BackgroundColor3 = HudTheme.Accent.win.top
	setBar(startProgress)
	HudTheme.setPanelAccent(rewardHandle, grant.leveledUp and "win" or "neutral")

	rewardRoot.Visible = true
	HudTheme.popIn(rewardRoot)

	-- New reward cancels any running fill + the prior hide (shared token).
	local token = {}
	animToken = token
	hideToken = token
	task.spawn(playTimeline, token, plan, grant.xp)

	-- Keep the panel up for the whole sequence (fill + level-up pauses) plus a readable hold.
	local levelUps = 0
	for _, s in ipairs(plan.segments) do
		if s.levelUpAfter then
			levelUps += 1
		end
	end
	local visibleFor = Config.REWARD_XP_FILL_SECONDS
		+ Config.REWARD_LEVELUP_PAUSE_SECONDS * levelUps
		+ Config.REWARD_PANEL_HOLD_SECONDS
	task.delay(visibleFor, function()
		if hideToken == token then
			rewardRoot.Visible = false
		end
	end)
end
```

- [ ] **Step 5: Sanity-check the pure suite still passes (no client lune test)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/xp_fill_model.spec.luau`
Expected: `ALL XpFillModel TESTS PASSED` (confirms the model the client drives is intact; the client GUI itself is verified in Studio).

- [ ] **Step 6: Commit**

```bash
git add src/client/ClientEconomyHud.luau
git commit -m "feat(economy): animate the reward XP bar (fill + level-up pop + count-up)"
```

---

### Task 5: Update the economy smoke-test doc

**Files:**
- Modify: `docs/smoke-tests/2026-06-30-economy-persistence-smoke-test.md`

- [ ] **Step 1: Append the XP-animation checks**

Add this section immediately before the final `## Notes` heading:

```markdown
## XP-fill animation checks (2026-07-01)

8. **Smooth fill.** On the reward panel, the XP bar fills smoothly from its prior
   fraction to the new one (not an instant snap), finishing in ~1.2s, and the `+XP`
   number counts up from `+0` to the full amount in step with the bar.
9. **Level-up moment.** Award enough XP to cross a level (lower `Config.PROGRESSION_XP_COEFF`
   temporarily, or use the direct-trigger below with a big XP value): the bar fills to
   full, the panel pops/flashes, the `Level N` label ticks up, the bar resets to empty and
   continues toward the next level. Multiple level-ups chain.
10. **Panel stays long enough.** The panel remains visible through the entire animation
    plus a readable hold (it does not vanish mid-fill).
11. **Re-trigger.** Triggering a second reward while the first is animating cancels the
    first and restarts cleanly (no stuck/garbled bar).

Direct trigger for a big multi-level award (server command bar):
`require(game.ServerScriptService.Server.EconomyService).awardRound(game.Players:GetPlayers()[1], { survivedSwaps = 40, isWinner = true, participated = true })`
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-30-economy-persistence-smoke-test.md
git commit -m "docs(smoke): add XP-fill animation checks"
```

---

## Self-Review

**Spec coverage:**
- Pure timeline geometry (`XpFillModel`) + tests → Task 2. ✔
- Fixed-duration proportional fill + level-up pop/flash/tick + XP count-up → Task 4. ✔
- `RewardGranted.before` pre-award snapshot → Task 3. ✔
- Config timing tunables → Task 1. ✔
- Edge cases (no level-up, zero/negative delta, max-level clamp, multi level-up, re-trigger) → Task 2 tests + Task 4 player. ✔
- Smoke checks → Task 5. ✔

**Type/name consistency:** `XpFillModel.build(start, deltaXp, opts) -> { segments, totalSpan, finalLevel, finalProgress }`; segment fields `{ level, fromProgress, toProgress, xpSpan, levelUpAfter }`; `opts = { maxLevel, xpForLevel }`; `start = { level, xpIntoLevel, xpForNext }`. `RewardGranted` adds `before = { level, xpIntoLevel, xpForNext }`. Client `progressionOpts()` returns `{ coeff, exp, maxLevel }` (matches `ProgressionModel.xpForLevel` opts). Config keys `REWARD_XP_FILL_SECONDS` / `REWARD_LEVELUP_PAUSE_SECONDS` / `REWARD_PANEL_HOLD_SECONDS` / `REWARD_LEVELUP_POP_SCALE` / `REWARD_LEVELUP_FLASH_COLOR` are used consistently across Tasks 1 and 4. ✔

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✔
