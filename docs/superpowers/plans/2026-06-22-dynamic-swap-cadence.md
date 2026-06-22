# Dynamic Swap Cadence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed `Config.CYCLE_SECONDS = 30` with a dynamic swap interval that compresses from a calm round-start (20s) to a frantic endgame (8s), driven by alive-count + round progress.

**Architecture:** A new pure, lune-tested `CadenceModel` maps `(startCount, aliveCount, swapsSoFar)` to the next interval in seconds. `RoundManager` calls it each Active cycle and broadcasts the resulting deadline over the existing `RoundStateChanged` remote (the client HUD already counts down to that deadline, so there is no client change). `Config` loses `CYCLE_SECONDS` and gains the cadence tunables.

**Tech Stack:** Luau, Rojo project; pure logic modules unit-tested with lune (`tests/*.spec.luau`); runtime behaviour validated with a manual 2-client Studio smoke test.

**Spec:** `docs/superpowers/specs/2026-06-22-dynamic-swap-cadence-design.md`

---

## File Structure

- **Create** `src/shared/CadenceModel.luau` — pure cadence decision (the only logic).
- **Create** `tests/cadence_model.spec.luau` — lune unit spec for `CadenceModel`.
- **Modify** `src/shared/Config.luau` — remove `CYCLE_SECONDS`; add the cadence block.
- **Modify** `src/server/RoundManager.luau` — require `CadenceModel`, hold round-scoped `cadenceStartCount` / `swapsSoFar`, compute the interval each cycle.
- **Create** `docs/smoke-tests/2026-06-22-dynamic-cadence-smoke-test.md` — runtime check.
- **Modify** `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md` — drop the now-removed `CYCLE_SECONDS` references.

---

## Task 1: `CadenceModel` pure module (TDD)

**Files:**
- Test: `tests/cadence_model.spec.luau`
- Create: `src/shared/CadenceModel.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/cadence_model.spec.luau`:

```lua
local CadenceModel = require("../src/shared/CadenceModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local function approx(a, b)
	return math.abs(a - b) < 1e-9
end

-- Mirrors the Config defaults (max 20, min 8, floor at 8 swaps, full-weight progress).
local OPTS = { maxInterval = 20, minInterval = 8, swapsToFloor = 8, stallWeight = 1.0 }

-- round start: full lobby, no swaps -> exactly maxInterval.
do
	expect(approx(CadenceModel.interval(8, 8, 0, OPTS), 20), "round start must be maxInterval")
	print("cadence: round start -> max OK")
end

-- final duel in a big lobby (countT == 1) -> exactly minInterval.
do
	expect(approx(CadenceModel.interval(8, 2, 0, OPTS), 8), "final duel (countT=1) -> min")
	print("cadence: final duel -> min OK")
end

-- always within [min, max] for arbitrary / absurd inputs (incl. alive>start, negative swaps).
do
	local cases = {
		{ 8, 8, 0 }, { 8, 2, 100 }, { 16, 1, 0 }, { 2, 2, 0 }, { 2, 2, 1000 }, { 8, 9, 0 }, { 8, 8, -5 },
	}
	for _, c in ipairs(cases) do
		local v = CadenceModel.interval(c[1], c[2], c[3], OPTS)
		expect(v >= OPTS.minInterval - 1e-9 and v <= OPTS.maxInterval + 1e-9,
			"interval out of range for " .. c[1] .. "," .. c[2] .. "," .. c[3])
	end
	print("cadence: always within [min,max] OK")
end

-- non-increasing as aliveCount drops (more eliminations -> faster).
do
	local prev = math.huge
	for alive = 8, 2, -1 do
		local v = CadenceModel.interval(8, alive, 0, OPTS)
		expect(v <= prev + 1e-9, "interval must not increase as aliveCount drops")
		prev = v
	end
	print("cadence: monotonic in aliveCount OK")
end

-- non-increasing as swapsSoFar rises (round drags -> faster).
do
	local prev = math.huge
	for swaps = 0, 12 do
		local v = CadenceModel.interval(8, 8, swaps, OPTS)
		expect(v <= prev + 1e-9, "interval must not increase as swapsSoFar rises")
		prev = v
	end
	print("cadence: monotonic in swapsSoFar OK")
end

-- N=2: countT pinned at 0 (both alive the whole round); progress alone ramps from
-- max down to exactly min by swapsToFloor swaps.
do
	expect(approx(CadenceModel.interval(2, 2, 0, OPTS), 20), "N=2 start -> max")
	expect(approx(CadenceModel.interval(2, 2, 4, OPTS), 14), "N=2 halfway -> 14")
	expect(approx(CadenceModel.interval(2, 2, 8, OPTS), 8), "N=2 at swapsToFloor -> min")
	print("cadence: N=2 progress-only ramp OK")
end

-- divide-by-zero safety at startCount == 2 (denom clamps to 1; no NaN/error).
do
	local v = CadenceModel.interval(2, 2, 0, OPTS)
	expect(v == v, "must not be NaN at startCount==2") -- NaN ~= NaN
	print("cadence: startCount==2 no divide-by-zero OK")
end

print("ALL CADENCEMODEL TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/cadence_model.spec`
Expected: FAIL — the require fails because `src/shared/CadenceModel.luau` does not exist yet.

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/CadenceModel.luau`:

```lua
--[[
	CadenceModel -- PURE dynamic swap-cadence decision.
	Location (Roblox): ReplicatedStorage/Shared/CadenceModel  (ModuleScript)

	Stateless and Roblox-free, like SoulPalette: a pure function of the round's
	current shape. Maps (startCount, aliveCount, swapsSoFar) -> the next swap
	interval in seconds, compressing a calm round-start toward a frantic endgame.

	Two drivers, combined additively then clamped (dynamic-cadence design, Approach A):
	  countT    -- elimination progress: 0 at round start, 1 at the final duel.
	  progressT -- swapsSoFar / swapsToFloor, capped at 1 (the stall-breaker so a
	               round where nobody dies still escalates; it also carries the N=2
	               case, where countT is pinned at 0 because the round ends at 1
	               survivor and nobody is eliminated mid-round).
	  t        = clamp(countT + stallWeight * progressT, 0, 1)
	  interval = lerp(maxInterval, minInterval, t)

	opts = { maxInterval, minInterval, swapsToFloor, stallWeight }. Passed in (not
	read from Config) so tests inject their own values.
--]]

local CadenceModel = {}

local function clamp(x, lo, hi)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

function CadenceModel.interval(startCount, aliveCount, swapsSoFar, opts)
	-- max(startCount - 2, 1) avoids divide-by-zero when startCount == 2 (the MVP
	-- duel): countT then stays 0 and the progress term carries the whole ramp.
	local denom = math.max(startCount - 2, 1)
	local countT = clamp((startCount - aliveCount) / denom, 0, 1)
	local progressT = math.min(swapsSoFar / opts.swapsToFloor, 1)
	local t = clamp(countT + opts.stallWeight * progressT, 0, 1)
	return lerp(opts.maxInterval, opts.minInterval, t)
end

return CadenceModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/cadence_model.spec`
Expected: PASS — ends with `ALL CADENCEMODEL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add tests/cadence_model.spec.luau src/shared/CadenceModel.luau
git commit -m "feat(cadence): pure CadenceModel for dynamic swap interval

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Wire cadence into `Config` + `RoundManager`

These two files must change together: removing `CYCLE_SECONDS` would break `RoundManager` unless the cadence call replaces it in the same commit.

**Files:**
- Modify: `src/shared/Config.luau:9-10`
- Modify: `src/server/RoundManager.luau` (requires block; module state; `beginRound`; `runActivePhase`)

- [ ] **Step 1: Edit `Config.luau` — remove `CYCLE_SECONDS`, add the cadence block**

In `src/shared/Config.luau`, replace these two lines (9-10):

```lua
-- Round timing (used from step 5/6 onward)
Config.CYCLE_SECONDS = 30
Config.PREVIEW_SECONDS = 3
```

with:

```lua
-- Round timing (used from step 5/6 onward)
Config.PREVIEW_SECONDS = 3

-- Dynamic swap cadence. The swap interval is no longer fixed: the pure CadenceModel
-- compresses it from CADENCE_MAX_INTERVAL (calm round-start) toward
-- CADENCE_MIN_INTERVAL (frantic endgame), driven by alive-count + round progress.
-- INVARIANT: CADENCE_MIN_INTERVAL MUST stay > PREVIEW_SECONDS so the 3s preview
-- window always fits inside the shortest cycle.
Config.CADENCE_MAX_INTERVAL = 20   -- round-start ceiling (seconds)
Config.CADENCE_MIN_INTERVAL = 8    -- endgame floor (seconds)
Config.CADENCE_SWAPS_TO_FLOOR = 8  -- swaps for the stall-breaker (progress term) to reach the floor
Config.CADENCE_STALL_WEIGHT = 1.0  -- progress-term weight; 1.0 so the ramp still works at N=2
```

- [ ] **Step 2: Edit `RoundManager.luau` — require `CadenceModel`**

In `src/server/RoundManager.luau`, after the existing line:

```lua
local SwapController = require(script.Parent.SwapController)
```

add (keep the existing `require` lines around it untouched):

```lua
local CadenceModel = require(ReplicatedStorage.Shared.CadenceModel)
```

- [ ] **Step 3: Edit `RoundManager.luau` — add round-scoped cadence state**

In `src/server/RoundManager.luau`, immediately after this existing line:

```lua
local swapPos = {} -- [player] = Vector3
```

add:

```lua

-- Round-scoped dynamic-cadence state (reset in beginRound). cadenceStartCount is the
-- alive count at round start; swapsSoFar counts swaps committed this round. CadenceModel
-- maps these -> the next swap interval (20s calm round-start -> 8s frantic endgame).
local cadenceStartCount = 0
local swapsSoFar = 0
local cadenceOpts = {
	maxInterval = Config.CADENCE_MAX_INTERVAL,
	minInterval = Config.CADENCE_MIN_INTERVAL,
	swapsToFloor = Config.CADENCE_SWAPS_TO_FLOOR,
	stallWeight = Config.CADENCE_STALL_WEIGHT,
}
```

- [ ] **Step 4: Edit `RoundManager.luau` — reset cadence state in `beginRound`**

In `beginRound`, immediately after this existing line:

```lua
	RoundState.beginRound(model) -- Lobby -> Active; present snapshot into alive
```

add:

```lua
	cadenceStartCount = RoundState.aliveCount(model)
	swapsSoFar = 0
```

- [ ] **Step 5: Edit `RoundManager.luau` — compute the interval each cycle**

In `runActivePhase`, replace this existing block:

```lua
	while RoundState.getPhase(model) == "Active" do
		broadcastState(nil, workspace:GetServerTimeNow() + Config.CYCLE_SECONDS)

		-- Free play.
		waitActive(Config.CYCLE_SECONDS - Config.PREVIEW_SECONDS)
```

with:

```lua
	while RoundState.getPhase(model) == "Active" do
		-- Dynamic cadence: the interval shrinks as players are eliminated and as the
		-- round drags on (CadenceModel). The HUD counts down to this broadcast deadline.
		local interval = CadenceModel.interval(
			cadenceStartCount, RoundState.aliveCount(model), swapsSoFar, cadenceOpts)
		broadcastState(nil, workspace:GetServerTimeNow() + interval)

		-- Free play.
		waitActive(interval - Config.PREVIEW_SECONDS)
```

- [ ] **Step 6: Edit `RoundManager.luau` — count committed swaps**

Still in `runActivePhase`, replace this existing block (the commit at T0):

```lua
		-- Commit at T0.
		if plan then
			commitSwap(plan)
		end
	end
end
```

with:

```lua
		-- Commit at T0.
		if plan then
			commitSwap(plan)
			swapsSoFar += 1 -- advances the cadence progress term for the next cycle
		end
	end
end
```

(Note: `forceSwap` deliberately does not touch `swapsSoFar` — it is a debug-only immediate swap that exists outside the cadence loop.)

- [ ] **Step 7: Verify no runtime reference to `CYCLE_SECONDS` remains and tests still pass**

Run: `grep -rn "CYCLE_SECONDS" src/`
Expected: no matches (empty output).

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/cadence_model.spec`
Expected: PASS — `ALL CADENCEMODEL TESTS PASSED` (confirms `Config` still loads cleanly for the shared modules).

> Runtime behaviour in `RoundManager` (Roblox-only APIs: `game:GetService`, `workspace`) cannot be exercised by lune — it is validated by the Studio smoke test added in Task 3.

- [ ] **Step 8: Commit**

```bash
git add src/shared/Config.luau src/server/RoundManager.luau
git commit -m "feat(cadence): drive RoundManager swap interval from CadenceModel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Smoke-test documentation

**Files:**
- Create: `docs/smoke-tests/2026-06-22-dynamic-cadence-smoke-test.md`
- Modify: `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md` (lines referencing `CYCLE_SECONDS`)

- [ ] **Step 1: Create the dynamic-cadence smoke test**

Create `docs/smoke-tests/2026-06-22-dynamic-cadence-smoke-test.md`:

```markdown
# Dynamic swap cadence smoke test (manual, 2-client Studio)

Validates that the swap interval is dynamic — it shrinks cycle-over-cycle — and that
the HUD countdown matches the actual swap timing. lune covers the pure `CadenceModel`
math (`tests/cadence_model.spec.luau`); this covers the `RoundManager` runtime wiring,
which lune can't reach. Run a **2-player local server** (Test → Clients and Servers →
2 → Start).

> **N=2 note:** with two players nobody is eliminated until the round ends, so the
> alive-count driver is inert and the ramp is carried entirely by the progress term
> (this is the case `CADENCE_STALL_WEIGHT = 1.0` exists to cover). The interval should
> still march 20s → 8s over successive swaps.

**Optional fast setup** (Server view, command bar) — keep the floor safe so a body
doesn't die before you've watched a few cycles:
`local C = require(game.ReplicatedStorage.Shared.Config); C.HAZARDS_ENABLED = false; C.LOBBY_COUNTDOWN_SECONDS = 2`

**Procedure & PASS criteria:**
1. **Round start.** After both clients join and the round begins, note the swap
   countdown shown on the HUD at the top of the first cycle — it should start near
   `CADENCE_MAX_INTERVAL` (20s).
2. **Interval shrinks.** Let several swaps fire without anyone dying. Each successive
   cycle's starting countdown should be **shorter** than the previous one (e.g. ~20 →
   ~18.5 → ~17 …), trending toward `CADENCE_MIN_INTERVAL` (8s). PASS = the countdown is
   visibly and monotonically decreasing across cycles.
3. **Floor holds.** After enough swaps (≈`CADENCE_SWAPS_TO_FLOOR` = 8), the starting
   countdown should sit at ~8s and not drop below it. PASS = it bottoms out at the
   floor, never lower.
4. **HUD matches the swap.** On any cycle, the swap (hard cut + FOV punch) fires when
   the countdown reaches 0 — the dynamic deadline and the HUD agree. PASS = no drift
   between the displayed countdown and the moment the swap happens.

To shorten the wait while testing, lower the envelope instead of the (now removed)
`CYCLE_SECONDS`, e.g.
`local C = require(game.ReplicatedStorage.Shared.Config); C.CADENCE_MAX_INTERVAL = 8; C.CADENCE_MIN_INTERVAL = 4`.
```

- [ ] **Step 2: Update the round-loop smoke test's `CYCLE_SECONDS` references**

In `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md`:

Replace this line (the fast-setup line 8):

```
`local C = require(game.ReplicatedStorage.Shared.Config); C.CYCLE_SECONDS = 8; C.LOBBY_COUNTDOWN_SECONDS = 2; C.ROUND_END_SECONDS = 2`.
```

with:

```
`local C = require(game.ReplicatedStorage.Shared.Config); C.CADENCE_MAX_INTERVAL = 8; C.CADENCE_MIN_INTERVAL = 8; C.LOBBY_COUNTDOWN_SECONDS = 2; C.ROUND_END_SECONDS = 2`.
```

In the one-shot grace script, replace this line:

```lua
local orig = { VOID_Y = Config.VOID_Y, GRACE = Config.GRACE_SECONDS, CYCLE = Config.CYCLE_SECONDS }
```

with:

```lua
local orig = { VOID_Y = Config.VOID_Y, GRACE = Config.GRACE_SECONDS, CMAX = Config.CADENCE_MAX_INTERVAL, CMIN = Config.CADENCE_MIN_INTERVAL }
```

Replace this line:

```lua
    Config.VOID_Y, Config.GRACE_SECONDS, Config.CYCLE_SECONDS = orig.VOID_Y, orig.GRACE, orig.CYCLE
```

with:

```lua
    Config.VOID_Y, Config.GRACE_SECONDS = orig.VOID_Y, orig.GRACE
    Config.CADENCE_MAX_INTERVAL, Config.CADENCE_MIN_INTERVAL = orig.CMAX, orig.CMIN
```

Replace this line (it pins the interval long so no automatic swap interrupts the grace observation):

```lua
Config.CYCLE_SECONDS = 120
```

with:

```lua
Config.CADENCE_MAX_INTERVAL, Config.CADENCE_MIN_INTERVAL = 120, 120 -- pin the interval so no auto-swap interrupts the grace window
```

- [ ] **Step 3: Verify no runtime reference to `CYCLE_SECONDS` remains anywhere in code**

Run: `grep -rn "CYCLE_SECONDS" src/`
Expected: no matches (docs may still mention it historically; `src/` must be clean).

- [ ] **Step 4: Commit**

```bash
git add docs/smoke-tests/2026-06-22-dynamic-cadence-smoke-test.md docs/smoke-tests/2026-06-18-round-loop-smoke-test.md
git commit -m "docs(cadence): smoke test for dynamic cadence; drop CYCLE_SECONDS refs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/cadence_model.spec` → `ALL CADENCEMODEL TESTS PASSED`.
- [ ] `grep -rn "CYCLE_SECONDS" src/` → no matches.
- [ ] Manual Studio run per `docs/smoke-tests/2026-06-22-dynamic-cadence-smoke-test.md`: the swap countdown opens near 20s and shrinks cycle-over-cycle toward an 8s floor, with the HUD matching the actual swap moment.
```
