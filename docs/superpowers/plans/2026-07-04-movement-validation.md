# MVP Movement Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the client-authoritative movement exploit surface (fly / teleport / speed / eliminated re-entry) with server-side rubber-band validation on the existing 10 Hz void monitor, without ever rubber-banding an honest laggy player.

**Architecture:** A new Roblox-free pure module `MovementValidator` decides — from scalar per-tick deltas (horizontal/vertical displacement, dt, floor-beneath) — whether a body's motion is physically impossible and has been so long enough to correct (debounce). Thin glue on `RoundManager.startMonitor` reduces every controlled body to those scalars each tick, reusing the existing `hasFloorBeneath` probe, and on a confirmed violation re-pivots the body to its last valid grounded pose using the existing reposition-then-re-own primitive. Folds in review Action #4 (uniform re-own after `sendToLobby`) and #5 (`ClientAnimator` registration retry).

**Tech Stack:** Luau, Rojo project; pure modules lune-tested via `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`; server glue verified via a Studio smoke-test doc.

**Spec:** `docs/superpowers/specs/2026-07-04-movement-validation-design.md`

---

## File Structure

- **Create** `src/shared/MovementValidator.luau` — pure per-body movement-legality decision (Task 1).
- **Create** `tests/movement_validator.spec.luau` — lune tests for the pure model (Task 1).
- **Modify** `src/shared/Config.luau` — `MOVE_*` tunables (Task 2).
- **Modify** `src/server/BodyManager.luau` — expose `pivotTo` (Task 3).
- **Modify** `src/server/RoundManager.luau` — Action #4 uniform re-own (Task 4) + validation glue (Task 5).
- **Modify** `src/client/ClientAnimator.luau` — Action #5 registration retry (Task 6).
- **Create** `docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md` + **Modify** `CHANGELOG.md` (Task 7).

---

## Task 1: Pure `MovementValidator` module (TDD)

**Files:**
- Create: `tests/movement_validator.spec.luau`
- Create: `src/shared/MovementValidator.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/movement_validator.spec.luau`:

```lua
local MovementValidator = require("../src/shared/MovementValidator")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local DT = 0.1
-- horizontal budget = 16 * 0.1 * 2.0 = 3.2 ; rise budget = 53 * 0.1 * 1.5 = 7.95
local OPTS = {
	walkSpeed = 16,
	horizontalSlack = 2.0,
	jumpSpeed = 53,
	verticalSlack = 1.5,
	minFallEpsilon = 0.5,
	violationTicks = 5,
}

local function grounded(h, v)
	return { horizDelta = h, vertDelta = v or 0, dt = DT, hasFloor = true }
end

-- legal walk: never corrects, even sustained.
do
	local m = MovementValidator.new()
	for _ = 1, 12 do
		expect(MovementValidator.step(m, "A", grounded(1.5), OPTS).correct == false,
			"legal walk must never correct")
	end
	print("mv: legal walk -> never corrects OK")
end

-- legal jump rise (within budget, over floor): never corrects.
do
	local m = MovementValidator.new()
	for _ = 1, 12 do
		expect(MovementValidator.step(m, "A", grounded(1.5, 5), OPTS).correct == false,
			"legal jump rise must never correct")
	end
	print("mv: legal jump rise OK")
end

-- horizontal teleport: corrects after exactly violationTicks, not before.
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for i = 1, OPTS.violationTicks - 1 do
		expect(MovementValidator.step(m, "A", tp, OPTS).correct == false,
			"tick " .. i .. " must not correct yet")
	end
	local d = MovementValidator.step(m, "A", tp, OPTS)
	expect(d.correct == true, "must correct on the violationTicks-th tick")
	expect(d.reason == "horizontal", "reason must be horizontal")
	print("mv: horizontal teleport debounce OK")
end

-- counter resets after a correction (next illegal run must re-accumulate).
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for _ = 1, OPTS.violationTicks do MovementValidator.step(m, "A", tp, OPTS) end -- fires once, resets
	expect(MovementValidator.step(m, "A", tp, OPTS).correct == false,
		"counter must reset after a correction")
	print("mv: counter resets after correction OK")
end

-- upward launch (rise beyond jump budget): corrects.
do
	local m = MovementValidator.new()
	local up = { horizDelta = 0, vertDelta = 50, dt = DT, hasFloor = true }
	local fired = false
	for _ = 1, OPTS.violationTicks do
		if MovementValidator.step(m, "A", up, OPTS).correct then fired = true end
	end
	expect(fired, "sustained rise beyond budget must correct")
	print("mv: upward launch OK")
end

-- hover over void: no floor + not descending -> corrects after debounce.
do
	local m = MovementValidator.new()
	local hover = { horizDelta = 0, vertDelta = 0, dt = DT, hasFloor = false }
	local d
	for _ = 1, OPTS.violationTicks do d = MovementValidator.step(m, "A", hover, OPTS) end
	expect(d.correct == true and d.reason == "hover", "hovering over void must correct")
	print("mv: hover over void OK")
end

-- legit fall over a hole: no floor but strongly descending -> never corrects.
do
	local m = MovementValidator.new()
	local falling = { horizDelta = 0, vertDelta = -5, dt = DT, hasFloor = false }
	for _ = 1, 12 do
		expect(MovementValidator.step(m, "A", falling, OPTS).correct == false,
			"legit fall must never correct")
	end
	print("mv: legit fall over hole OK")
end

-- legal gap-jump: a bounded ascent over the void (fewer than violationTicks) then descent -> forgiven.
do
	local m = MovementValidator.new()
	local ascend = { horizDelta = 1, vertDelta = 3, dt = DT, hasFloor = false } -- over a hole, rising (hover-predicate true)
	local fallover = { horizDelta = 1, vertDelta = -4, dt = DT, hasFloor = false } -- now descending -> resets run
	for _ = 1, OPTS.violationTicks - 1 do -- one short of firing
		expect(MovementValidator.step(m, "A", ascend, OPTS).correct == false, "ascent under threshold")
	end
	expect(MovementValidator.step(m, "A", fallover, OPTS).correct == false, "descent resets the run")
	-- run reset: another (violationTicks-1) ascents still must not fire
	for _ = 1, OPTS.violationTicks - 1 do
		expect(MovementValidator.step(m, "A", ascend, OPTS).correct == false, "post-reset ascent under threshold")
	end
	print("mv: legal gap-jump forgiven OK")
end

-- one-tick lag spike then normal: forgiven (clean tick resets the run).
do
	local m = MovementValidator.new()
	local spike = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for _ = 1, 8 do
		MovementValidator.step(m, "A", spike, OPTS)    -- one spike
		expect(MovementValidator.step(m, "A", grounded(1.5), OPTS).correct == false,
			"clean tick after a spike resets the run")
	end
	print("mv: single-tick lag spike forgiven OK")
end

-- reseed clears the counter mid-run (server reposition path).
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	for _ = 1, OPTS.violationTicks - 1 do MovementValidator.step(m, "A", tp, OPTS) end
	MovementValidator.reseed(m, "A")
	expect(MovementValidator.step(m, "A", tp, OPTS).correct == false, "reseed must clear the run")
	print("mv: reseed clears counter OK")
end

-- forget drops all state (independent bodies do not interfere).
do
	local m = MovementValidator.new()
	local tp = { horizDelta = 100, vertDelta = 0, dt = DT, hasFloor = true }
	MovementValidator.step(m, "A", tp, OPTS)
	MovementValidator.forget(m, "A")
	expect(m.byBody["A"] == nil, "forget must drop the body entry")
	-- an unrelated body is unaffected
	expect(MovementValidator.step(m, "B", grounded(1.5), OPTS).correct == false, "B independent of A")
	print("mv: forget OK")
end

print("ALL MOVEMENTVALIDATOR TESTS PASSED")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/movement_validator.spec.luau`
Expected: FAIL — module `../src/shared/MovementValidator` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `src/shared/MovementValidator.luau`:

```lua
--[[
	MovementValidator -- PURE per-body movement legality.
	Location (Roblox): ReplicatedStorage/Shared/MovementValidator  (ModuleScript)

	Roblox-free + clock-free, like GraceModel / HexErosionModel. The glue reduces a
	body to scalars (horizontal/vertical displacement since the last tick, dt, and
	whether solid floor sits between it and the kill-plane) and asks: is this tick a
	physically-impossible move, and has it been impossible long enough to correct?

	Keys are opaque (body Instances in production, strings in tests).

	A tick VIOLATES if any of:
	  horizDelta > walkSpeed * dt * horizontalSlack     -- speed / horizontal teleport
	  vertDelta  > jumpSpeed * dt * verticalSlack       -- upward teleport / launch / fly-up
	  not hasFloor and vertDelta > -minFallEpsilon        -- over the void and not falling (hover)

	Debounce: correct=true only once `violationTicks` CONSECUTIVE violating ticks
	accumulate; any clean tick resets the run (so a one-tick lag spike is forgiven,
	and a legal gap-jump's bounded ascent over the void never reaches the threshold).
	The counter resets when a correction fires.
--]]

local MovementValidator = {}

function MovementValidator.new()
	return {
		byBody = {}, -- [bodyId] = { violations = int }
	}
end

local function entry(model, bodyId)
	local e = model.byBody[bodyId]
	if not e then
		e = { violations = 0 }
		model.byBody[bodyId] = e
	end
	return e
end

-- Is this single tick physically impossible? Returns (bool, reason?).
local function isViolation(sample, opts)
	if sample.horizDelta > opts.walkSpeed * sample.dt * opts.horizontalSlack then
		return true, "horizontal"
	end
	if sample.vertDelta > opts.jumpSpeed * sample.dt * opts.verticalSlack then
		return true, "rise"
	end
	if not sample.hasFloor and sample.vertDelta > -opts.minFallEpsilon then
		return true, "hover"
	end
	return false, nil
end

-- Judge one tick. Returns { correct, reason } -- correct=true only after the
-- debounce threshold is crossed, at which point the counter is reset.
function MovementValidator.step(model, bodyId, sample, opts)
	local e = entry(model, bodyId)
	local violated, reason = isViolation(sample, opts)
	if not violated then
		e.violations = 0
		return { correct = false, reason = nil }
	end
	e.violations += 1
	if e.violations >= opts.violationTicks then
		e.violations = 0
		return { correct = true, reason = reason }
	end
	return { correct = false, reason = reason }
end

-- Clear the debounce counter (server reposition / first sight of a body).
function MovementValidator.reseed(model, bodyId)
	local e = model.byBody[bodyId]
	if e then
		e.violations = 0
	end
end

-- Drop all state for a body (destroyed / player left).
function MovementValidator.forget(model, bodyId)
	model.byBody[bodyId] = nil
end

return MovementValidator
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/movement_validator.spec.luau`
Expected: PASS — ends with `ALL MOVEMENTVALIDATOR TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add tests/movement_validator.spec.luau src/shared/MovementValidator.luau
git commit -m "feat(anti-cheat): pure MovementValidator (displacement clamp + anti-hover + debounce)"
```

---

## Task 2: Config tunables

**Files:**
- Modify: `src/shared/Config.luau` (insert after the `Config.JUMP_HEIGHT = 7.2` line, ~line 98)

- [ ] **Step 1: Add the config block**

In `src/shared/Config.luau`, immediately after:

```lua
Config.WALK_SPEED = 16
Config.JUMP_HEIGHT = 7.2
```

insert:

```lua

-- ===== Movement validation (server-authoritative anti-cheat) =====
-- The void monitor rubber-bands any owned body whose motion is physically impossible
-- (fly / teleport / speed), snapping it to its last valid grounded pose. Pure decision
-- lives in MovementValidator; the glue is in RoundManager.startMonitor. Lenient + debounced
-- so honest laggy players are never corrected (see the 2026-07-04 spec).
Config.MOVE_VALIDATION_ENABLED = true  -- dev/test switch (like HAZARDS_ENABLED), NOT a gameplay tunable
Config.MOVE_HORIZONTAL_SLACK = 2.0     -- x (WALK_SPEED * dt) per-tick budget = the permitted speed-hack
                                       -- ceiling; debounce (not slack) forgives lag, so keep this tight.
Config.MOVE_VERTICAL_SLACK = 1.5       -- x (jumpSpeed * dt) rise budget; a whole legal jump rises < this
                                       -- in a single 0.1s tick, so only a fly-up launch exceeds it.
Config.MOVE_MIN_FALL_EPSILON = 0.5     -- studs/tick; a floorless body descending slower than this counts
                                       -- as hovering (a real fall accelerates well past it).
Config.MOVE_VIOLATION_TICKS = 5        -- consecutive violating ticks (~0.5s at 10Hz) before a correction.
                                       -- MUST exceed the longest legal non-descending run -- a gap-jump's
                                       -- ascent, ceil(sqrt(2*JUMP_HEIGHT/gravity)/0.1) ~= 3 ticks at default
                                       -- gravity; 5 leaves margin. Re-check if gravity/JUMP_HEIGHT change.
```

- [ ] **Step 2: Sanity-check the whole test suite still loads Config**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/cadence_model.spec.luau`
Expected: PASS (any suite that requires Config; confirms no syntax error in Config).

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(anti-cheat): movement-validation Config tunables"
```

---

## Task 3: Expose `BodyManager.pivotTo`

**Files:**
- Modify: `src/server/BodyManager.luau` (after the private `pivotBodyTo`, ~line 256)

- [ ] **Step 1: Add the public wrapper**

In `src/server/BodyManager.luau`, immediately after the `pivotBodyTo` function ends (the line `end` closing it, ~line 256), add:

```lua

-- Public reposition primitive: unanchor, zero velocity, PivotTo an arbitrary CFrame.
-- Used by the movement-validation glue to snap a violating body back to its last valid
-- pose (the caller then re-owns via ControlManager.regrantControl). Returns pivotBodyTo's
-- success bool (false if the body has no HumanoidRootPart).
function BodyManager.pivotTo(body, cf)
	return pivotBodyTo(body, cf)
end
```

- [ ] **Step 2: Verify no syntax error**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec.luau`
Expected: PASS (BodyManager is server-only and not lune-required, so this just confirms the repo still parses in adjacent suites; a manual read of the diff confirms the wrapper is well-formed).

- [ ] **Step 3: Commit**

```bash
git add src/server/BodyManager.luau
git commit -m "feat(anti-cheat): expose BodyManager.pivotTo reposition primitive"
```

---

## Task 4: Action #4 — uniform re-own after `sendToLobby`

**Files:**
- Modify: `src/server/RoundManager.luau` — `RoundManager.eliminate` (~lines 274-278)

- [ ] **Step 1: Add the re-own to the elimination path**

In `src/server/RoundManager.luau`, in `RoundManager.eliminate`, change:

```lua
	local body = ControlManager.getControlledBody(player)
	if body then
		body:SetAttribute("GraceProtected", false)
		BodyManager.sendToLobby(player, body)
	end
```

to:

```lua
	local body = ControlManager.getControlledBody(player)
	if body then
		body:SetAttribute("GraceProtected", false)
		BodyManager.sendToLobby(player, body)
		-- Re-assert ownership after the server pivot (reposition-then-re-own), so the
		-- teleport replicates onto the client-owned body -- uniform with beginRound's
		-- resetBody->resetControl and the disconnect rescue's sendToArena->regrantControl
		-- (review Action #4; matters for the fast-falling elimination case under latency).
		ControlManager.regrantControl(player)
	end
```

- [ ] **Step 2: Verify the full suite still passes (no pure regression)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: every suite prints its `ALL ... PASSED` line; no failures. (RoundManager glue isn't lune-tested; this guards the pure layer.)

- [ ] **Step 3: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "fix(control): re-own after sendToLobby (uniform reposition-then-re-own, review #4)"
```

---

## Task 5: Validation glue in the void monitor

**Files:**
- Modify: `src/server/RoundManager.luau` — requires/module state (~lines 24-49), a new `validateBody` helper + reposition/forget bookkeeping, `startMonitor` (~lines 298-352), `beginRound` (~line 392), `endRound` (~line 518), `eliminate` (~line 277), `removePlayer` (~lines 566-588).

- [ ] **Step 1: Add the require + module-level validation state**

In `src/server/RoundManager.luau`, after the line:

```lua
local CadenceModel = require(ReplicatedStorage.Shared.CadenceModel)
```

add:

```lua
local MovementValidator = require(ReplicatedStorage.Shared.MovementValidator)
```

Then, after the `swapPos` declaration block (~line 49):

```lua
local grace = GraceModel.new()
local swapPos = {} -- [player] = Vector3
```

add:

```lua

-- Movement validation (server-authoritative anti-cheat). The pure MovementValidator
-- judges each owned body's per-tick motion; the glue below holds the only Roblox-typed
-- state. `lastPos` is the previous tick's root position (to derive deltas); `validAnchor`
-- is the most recent CLEAN + GROUNDED pose (the rubber-band target). Jump launch speed is
-- derived from gravity + JUMP_HEIGHT (kept out of the pure model, which only multiplies).
local validator = MovementValidator.new()
local lastPos = {}       -- [body] = Vector3
local validAnchor = {}   -- [body] = CFrame
local lastMonitorT = nil -- previous monitor-tick timestamp (measured dt)
local jumpSpeed = math.sqrt(2 * Workspace.Gravity * Config.JUMP_HEIGHT)
```

- [ ] **Step 2: Add the reposition/forget bookkeeping + `validateBody` helper**

In `src/server/RoundManager.luau`, immediately AFTER the `hasFloorBeneath` function (it ends ~line 165, before `isBodySafe`), add:

```lua

-- Movement-validation bookkeeping ------------------------------------------------

-- A server-initiated PivotTo (round start / end / elimination / rescue) moves a body far
-- in one tick; clearing its tracking makes the next monitor tick re-seed cleanly instead
-- of reading the teleport as a violation.
local function noteServerReposition(body)
	if not body then return end
	lastPos[body] = nil
	validAnchor[body] = nil
	MovementValidator.reseed(validator, body)
end

-- Drop all validation state for a destroyed body (disconnect), so the tables never leak.
local function forgetBodyValidation(body)
	if not body then return end
	lastPos[body] = nil
	validAnchor[body] = nil
	MovementValidator.forget(validator, body)
end

-- Validate one owned body for one monitor tick. Reduces the body to scalar deltas, asks the
-- pure MovementValidator, and on a confirmed violation snaps it back to its last valid grounded
-- pose (reposition-then-re-own). `player` is the current controller (for the re-own). `dt` is the
-- measured seconds since the last tick.
local function validateBody(player, body, dt)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pos = root.Position
	local prev = lastPos[body]
	if not prev then
		-- First sight (or just after a server reposition): seed and skip; no delta yet.
		lastPos[body] = pos
		validAnchor[body] = body:GetPivot()
		MovementValidator.reseed(validator, body)
		return
	end
	local delta = pos - prev
	local hasFloor = hasFloorBeneath(body) -- the ONE ray per body per tick (reused below)
	local decision = MovementValidator.step(validator, body, {
		horizDelta = Vector3.new(delta.X, 0, delta.Z).Magnitude,
		vertDelta = delta.Y,
		dt = dt,
		hasFloor = hasFloor,
	}, {
		walkSpeed = Config.WALK_SPEED,
		horizontalSlack = Config.MOVE_HORIZONTAL_SLACK,
		jumpSpeed = jumpSpeed,
		verticalSlack = Config.MOVE_VERTICAL_SLACK,
		minFallEpsilon = Config.MOVE_MIN_FALL_EPSILON,
		violationTicks = Config.MOVE_VIOLATION_TICKS,
	})
	if decision.correct then
		local anchor = validAnchor[body]
		if anchor then
			-- Reposition-then-re-own: pivot (zeroes velocity) then re-assert ownership so the
			-- snap replicates onto the client-owned body. Same primitive as the disconnect rescue.
			BodyManager.pivotTo(body, anchor)
			ControlManager.regrantControl(player)
			lastPos[body] = anchor.Position -- next delta is measured from where we put it
		end
	else
		lastPos[body] = pos
		if hasFloor then
			validAnchor[body] = body:GetPivot() -- only anchor on a clean, grounded pose
		end
	end
end
```

> Note: `hasFloorBeneath(body)` is called exactly once per validated body per tick (the value is reused for both the decision and the anchor update), matching spec §6.

- [ ] **Step 3: Wire `validateBody` into the monitor loop**

In `src/server/RoundManager.luau`, replace the whole `startMonitor` body. Find:

```lua
local function startMonitor()
	local token = {}
	monitorToken = token
	task.spawn(function()
		while monitorToken == token do
			local t = now()
			-- One server loop now drives BOTH void death and hex erosion: gather a
			-- body sample per alive player (position + whether grace still shields it)
			-- and hand them to HazardSystem.step after the per-player death check.
			local samples = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if RoundState.isAlive(model, player) then
```

and replace the loop header region so the tick also validates EVERY owned body. Change the opening of the `task.spawn` loop to:

```lua
local function startMonitor()
	local token = {}
	monitorToken = token
	lastMonitorT = nil
	task.spawn(function()
		while monitorToken == token do
			local t = now()
			local dt = lastMonitorT and (t - lastMonitorT) or 0.1
			if dt <= 0 then dt = 0.1 end
			lastMonitorT = t
			-- Movement validation runs for EVERY owned body (alive or eliminated) -- one
			-- invariant: all owned bodies are validated. This also contains an eliminated
			-- player's balcony body (a teleport back toward the arena is snapped away).
			if Config.MOVE_VALIDATION_ENABLED then
				for _, player in ipairs(Players:GetPlayers()) do
					local body = ControlManager.getControlledBody(player)
					if body then
						validateBody(player, body, dt)
					end
				end
			end
			-- One server loop now drives BOTH void death and hex erosion: gather a
			-- body sample per alive player (position + whether grace still shields it)
			-- and hand them to HazardSystem.step after the per-player death check.
			local samples = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if RoundState.isAlive(model, player) then
```

Leave the rest of the loop (the alive-player void/grace/erosion body, `samples`, `HazardSystem.step(t, samples)`, `task.wait(0.1)`) UNCHANGED.

- [ ] **Step 4: Reseed on every server reposition; forget on disconnect**

In `src/server/RoundManager.luau`:

(a) In `beginRound`, change the reset loop:

```lua
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.resetBody(p) -- reposition own body to spawn + unanchor
	end
```

to:

```lua
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.resetBody(p) -- reposition own body to spawn + unanchor
		noteServerReposition(BodyManager.getOwnBody(p)) -- don't read the spawn teleport as a violation
	end
```

(b) In `endRound`, change the return-to-lobby loop:

```lua
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.returnToLobby(p)
	end
```

to:

```lua
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.returnToLobby(p)
		noteServerReposition(BodyManager.getOwnBody(p))
	end
```

(c) In `RoundManager.eliminate`, in the `if body then` block edited in Task 4, add a reseed after the re-own so the balcony teleport isn't flagged. It becomes:

```lua
	local body = ControlManager.getControlledBody(player)
	if body then
		body:SetAttribute("GraceProtected", false)
		BodyManager.sendToLobby(player, body)
		ControlManager.regrantControl(player)
		noteServerReposition(body) -- the send-to-lobby pivot is server-initiated, not a cheat
	end
```

(d) In `RoundManager.removePlayer`, reseed the rescued body and forget the destroyed body. Capture the leaver's own body at the top, and add the calls. Change:

```lua
function RoundManager.removePlayer(player)
	local leaverWasAlive = RoundState.isAlive(model, player)
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	local decision = ControlManager.removePlayer(player) -- absorb + destroy the leaver's own body
	if not leaverWasAlive and decision and decision.reassign
		and RoundState.isAlive(model, decision.reassign.player) then
		BodyManager.sendToArena(decision.reassign.body)
		ControlManager.regrantControl(decision.reassign.player)
	end
```

to:

```lua
function RoundManager.removePlayer(player)
	local leaverWasAlive = RoundState.isAlive(model, player)
	local leaverBody = BodyManager.getOwnBody(player) -- captured before ControlManager destroys it
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	local decision = ControlManager.removePlayer(player) -- absorb + destroy the leaver's own body
	forgetBodyValidation(leaverBody) -- the leaver's body is destroyed; drop its tracking
	if not leaverWasAlive and decision and decision.reassign
		and RoundState.isAlive(model, decision.reassign.player) then
		BodyManager.sendToArena(decision.reassign.body)
		ControlManager.regrantControl(decision.reassign.player)
		noteServerReposition(decision.reassign.body) -- rescued survivor's body was server-pivoted
	end
```

- [ ] **Step 5: Verify the full pure suite still passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: every suite passes (the glue can't be lune-run; this confirms nothing in the shared layer broke). Manually re-read the `startMonitor` diff to confirm the alive-player void/grace/erosion block and `task.wait(0.1)` are intact.

- [ ] **Step 6: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(anti-cheat): rubber-band movement validation on the void monitor (review #6)"
```

---

## Task 6: Action #5 — `ClientAnimator` registration retry

**Files:**
- Modify: `src/client/ClientAnimator.luau` — constants (~line 29) + `register` (~lines 65-71)

- [ ] **Step 1: Add retry constants**

In `src/client/ClientAnimator.luau`, after:

```lua
local WALK_THRESHOLD = 0.5 -- studs/s of horizontal speed before "walk" kicks in
local RISING_THRESHOLD = 1 -- upward studs/s that reads as "jump" rather than "fall"
```

add:

```lua
-- A body's Humanoid can lag one or more frames behind its ChildAdded on a cold join, so
-- loadTracks returns nil and the body would never animate for the session. Retry until the
-- rig replicates (same late-replication class ClientControl already guards against).
local REGISTER_MAX_ATTEMPTS = 10
local REGISTER_RETRY_SECONDS = 0.2
```

- [ ] **Step 2: Make `register` retry**

In `src/client/ClientAnimator.luau`, replace:

```lua
local function register(body)
	if rigs[body] then return end
	local tracks = loadTracks(body)
	if tracks then
		rigs[body] = { tracks = tracks, current = nil }
	end
end
```

with:

```lua
local function register(body)
	if rigs[body] then return end
	-- Retry off the caller's thread: loadTracks needs the Humanoid, which may not have
	-- replicated yet. Give up after REGISTER_MAX_ATTEMPTS (body is likely gone).
	task.spawn(function()
		for _ = 1, REGISTER_MAX_ATTEMPTS do
			if not body.Parent or rigs[body] then return end -- removed, or registered elsewhere
			local tracks = loadTracks(body)
			if tracks then
				if body.Parent and not rigs[body] then
					rigs[body] = { tracks = tracks, current = nil }
				end
				return
			end
			task.wait(REGISTER_RETRY_SECONDS)
		end
	end)
end
```

- [ ] **Step 3: Verify no syntax error**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/move_direction.spec.luau`
Expected: PASS (ClientAnimator is client-only, not lune-required; this confirms adjacent client-shared code still parses). Manually confirm the diff is well-formed — the ChildAdded handler (`task.defer(register, child)`) and the initial `register` loop are unchanged and still valid with the now-async `register`.

- [ ] **Step 4: Commit**

```bash
git add src/client/ClientAnimator.luau
git commit -m "fix(client): ClientAnimator registration retry for late-replicating rigs (review #5)"
```

---

## Task 7: Smoke-test doc + CHANGELOG

**Files:**
- Create: `docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md`
- Modify: `CHANGELOG.md` (top of the `### Fixed` / `### Added` section under `[Unreleased]`)

- [ ] **Step 1: Write the smoke-test doc**

Create `docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md`:

```markdown
# Smoke test — MVP Movement Validation (2026-07-04)

Validates the server rubber-band clamp (spec `docs/superpowers/specs/2026-07-04-movement-validation-design.md`).
The pure model is lune-covered; this exercises the glue in a running server. Requires a 2-client Studio
session (one client to exploit, one honest) unless noted. Read live state via Attributes/instances — the
command-bar `require` cache is separate from the game scripts.

## Setup
- Play Solo (2 players via Test > Clients and Servers where a case needs an honest observer).
- `Config.MOVE_VALIDATION_ENABLED` must be `true`.

## Cases (server command bar unless stated)

1. **Horizontal teleport (client-owned body).** With a round Active, on a client set the controlled
   body's `HumanoidRootPart.Position` +200 studs on X. EXPECT: within ~0.5 s the body snaps back to its
   last grounded pose; it does not stay displaced; the round continues.

2. **Straight-up teleport / fly.** On a client, repeatedly set the body's Y up (or anchor+raise). EXPECT:
   the body is snapped back down within ~0.5 s; it never camps above the arena.

3. **Hover over an eroded hole.** Let the tile under a body erode (or force it), then hold the body's Y
   so it does not fall. EXPECT: snapped back to its last grounded pose within ~0.5 s (does NOT win by
   floating over the void).

4. **Honest play is untouched (critical).** With validation on, walk, sprint-turn, jump, jump ACROSS an
   eroded gap, and ride a swap normally on the honest client. EXPECT: zero rubber-banding — no snap-backs,
   no stutter — across a full round. Repeat with artificial latency (Studio > Network > incoming/outgoing
   lag, e.g. 200-400 ms) and confirm still no false corrections.

5. **Legit fall is untouched.** Walk off a floor edge over a hole. EXPECT: the body falls normally and
   either lands on the floor below or dies at VOID_Y via the existing grace-gated void monitor — never
   snapped back mid-fall.

6. **Eliminated-body containment.** After a player is eliminated (body on the balcony, still owned), on
   that client teleport the body toward/into the arena. EXPECT: snapped back; it cannot re-enter as a
   physics actor.

7. **Server repositions never self-correct.** Observe round start (spawn drop), an elimination
   (send-to-lobby), and round end (return-to-lobby). EXPECT: none of these server PivotTos trigger a
   rubber-band the following tick (bodies settle where the server placed them).

8. **Disconnect rescue still works.** Reproduce the disconnect-strand case (an eliminated player leaves,
   handing a body to a live survivor). EXPECT: the survivor's rescued body lands in the arena and is not
   rubber-banded; the round can still end.

## Pass criteria
All 8 cases behave as EXPECTED. Case 4 (honest play, incl. latency) is the gate: any false positive fails
the test and blocks the stranger playtest.
```

- [ ] **Step 2: Add a CHANGELOG entry**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add near the top:

```markdown
- **MVP movement validation (server-authoritative anti-cheat).** The 10 Hz void monitor now
  rubber-bands any owned body whose motion is physically impossible — horizontal/vertical
  displacement beyond walk/jump physics (speed, teleport, fly-up) or hovering over the void with no
  floor beneath — snapping it to its last valid grounded pose via reposition-then-re-own. Pure decision
  in `src/shared/MovementValidator.luau` (displacement clamp + anti-hover + a 5-tick debounce so honest
  laggy players are never corrected; lune-tested `tests/movement_validator.spec.luau`); glue in
  `RoundManager.startMonitor` reuses the doom-exclusion `hasFloorBeneath` probe. Validates EVERY owned
  body (alive + eliminated), so an eliminated player can no longer teleport their balcony body back into
  the arena. Closes the "an exploiter literally cannot lose" gap (review 2026-07-03 §3.2 / Action #6).
  Tunables in `Config.MOVE_*`; smoke test `docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md`.
```

Then, under `### Fixed` (create it under `[Unreleased]` if absent), add:

```markdown
- Elimination now re-asserts network ownership after `sendToLobby` (uniform reposition-then-re-own,
  review Action #4) so the balcony teleport replicates reliably onto a fast-falling client-owned body.
- `ClientAnimator.register` retries until a body's Humanoid replicates (review Action #5), fixing bodies
  that could go permanently un-animated on a cold join when the rig lagged a frame behind `ChildAdded`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md CHANGELOG.md
git commit -m "docs(anti-cheat): movement-validation smoke test + CHANGELOG"
```

---

## Final verification (after all tasks)

- [ ] Run the entire pure suite: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done` — all suites pass, including the new `movement_validator.spec.luau`.
- [ ] Re-read the `RoundManager.startMonitor` diff: the new validation pass precedes the alive-only void/grace/erosion pass, `dt` is measured, and `task.wait(0.1)` + `HazardSystem.step` are intact.
- [ ] Confirm no hardcoded arena geometry entered the glue (all thresholds via `Config`; floor test via `hasFloorBeneath`).
- [ ] The Studio smoke test (`docs/smoke-tests/2026-07-04-movement-validation-smoke-test.md`) is left for the user's 2-client session; case 4 (honest + latency) is the release gate.
```
