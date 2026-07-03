# Core Loop Correctness Bundle Implementation Plan

**Goal:** Make the swap handoff trustworthy — bodies hand off at rest, void-bound bodies are never handed to a victim, and the client grace shimmer follows the server's real grace gate.

**Architecture:** Three coupled server/client changes converging on `commitSwap` and the void monitor. Part A zeroes velocity server-authoritatively during the ownership transfer. Part B adds a current-state floor probe and excludes doomed bodies from the derangement via a new *pure* `ControlModel.filterSafe`. Part C mirrors the server's `canDieFromHazard` gate onto a `GraceProtected` body attribute the client shimmer follows.

**Tech Stack:** Luau, Roblox (server: `ServerScriptService`, shared: `ReplicatedStorage.Shared`, client: `StarterPlayerScripts`), Rojo, lune for pure unit tests.

**Spec:** `docs/specs/2026-07-03-core-loop-correctness-design.md`

**Testing note:** Only the pure `ControlModel.filterSafe` predicate (Task 2) is lune-testable. Parts A, B-glue, and C are server/client glue — per project convention they are validated by the Studio smoke-test doc (Task 6), and every task keeps the existing 18-suite lune set green.

**Run all lune tests** (used repeatedly below):
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done
```

---

## File Structure

- **Modify** `src/server/ControlManager.luau` — Part A: velocity-zero during swap handoff; `warn` on `SetNetworkOwner` failure.
- **Modify** `src/shared/ControlModel.luau` — Part B (pure): add `filterSafe`.
- **Create** `tests/control_model_filter_safe.spec.luau` — lune test for `filterSafe`.
- **Modify** `src/server/RoundManager.luau` — Part B (glue): `hasFloorBeneath` probe + safe-gated commit; Part C (server): write `GraceProtected` attribute.
- **Modify** `src/client/SoulController.luau` — Part C (client): shimmer follows `GraceProtected` attribute; delete local-input prediction.
- **Create** `docs/smoke-tests/2026-07-03-core-loop-correctness-smoke-test.md` — acceptance record for the glue.
- **Modify** `docs/body-swap-royale-gdd.md`, `docs/body-swap-royale-tdd.md` — note Bug #2 Layers 1–2 implemented.

---

## Task 1: Part A — velocity-zero at swap handoff (`ControlManager`)

**Files:**
- Modify: `src/server/ControlManager.luau:43-52` (`applyOwnership`)

Currently the swap path (`commitSwap` → `applyOwnership(pair.player, pair.body, true)`) hands a body to its new controller **without zeroing velocity**, so inherited launch/shove momentum carries across the swap and trips the grace `hasMoved` check. Because the body is client-owned, velocity must be zeroed while the **server** owns the assembly, as part of the ownership transfer.

- [ ] **Step 1: Rewrite `applyOwnership` to zero velocity on swap handoff and warn on failure**

Replace the existing function (lines 43-52):

```lua
-- Hand `player` network ownership of `body` and tell their client to retarget.
-- On a swap handoff (isSwap), zero the body's velocity server-authoritatively:
-- the body is client-owned, so a naive velocity write would be overwritten by the
-- owning client's physics. Taking ownership (nil) first, zeroing, then handing to
-- the new controller makes the inheritor start at rest -- no inherited launch/shove
-- momentum (which would otherwise cancel grace). Same own->mutate->re-own ordering
-- as BodyManager's reposition-then-re-own primitive.
local function applyOwnership(player, body, isSwap)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root then
		local ok, err = pcall(function()
			if isSwap then
				root:SetNetworkOwner(nil) -- server takes the body
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			root:SetNetworkOwner(player)
		end)
		if not ok then
			warn("[ControlManager] SetNetworkOwner failed for " .. tostring(player) .. ": " .. tostring(err))
		end
	end
	SetControlledBody:FireClient(player, body, isSwap == true)
end
```

- [ ] **Step 2: Run the full lune suite to confirm nothing regressed**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done
```
Expected: every suite prints its `ALL ... TESTS PASSED` line (this is glue; the pure suites must all still pass).

- [ ] **Step 3: Commit**

```bash
git add src/server/ControlManager.luau
git commit -m "feat(swap): zero body velocity server-authoritatively at swap handoff; warn on SetNetworkOwner failure"
```

---

## Task 2: Part B (pure) — `ControlModel.filterSafe` + lune test

**Files:**
- Modify: `src/shared/ControlModel.luau` (add function before `return ControlModel`)
- Test: `tests/control_model_filter_safe.spec.luau` (create)

`filterSafe` reduces an ordered roster to the subset whose bodies are currently safe (floor beneath before the void). It is pure — the safety decision is injected as a predicate, exactly like `randint` is injected into `derange`. The `< 2` guard already lives in callers (`SwapController.plan`, `commitSwap`), so `filterSafe` only filters.

- [ ] **Step 1: Write the failing test**

Create `tests/control_model_filter_safe.spec.luau`:

```lua
local ControlModel = require("../src/shared/ControlModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- All safe: order preserved, nothing dropped.
do
	local safe = { A = true, B = true, C = true }
	local out = ControlModel.filterSafe({ "A", "B", "C" }, function(p) return safe[p] end)
	expect(#out == 3, "all-safe keeps everyone")
	expect(out[1] == "A" and out[2] == "B" and out[3] == "C", "order preserved")
	print("filterSafe: all safe OK")
end

-- One doomed: excluded, order of the rest preserved.
do
	local safe = { A = true, B = false, C = true }
	local out = ControlModel.filterSafe({ "A", "B", "C" }, function(p) return safe[p] end)
	expect(#out == 2, "doomed player excluded")
	expect(out[1] == "A" and out[2] == "C", "remaining order preserved")
	print("filterSafe: one doomed excluded OK")
end

-- Only one safe: returns a size-1 roster (caller's < 2 guard suppresses the swap).
do
	local safe = { A = false, B = true, C = false }
	local out = ControlModel.filterSafe({ "A", "B", "C" }, function(p) return safe[p] end)
	expect(#out == 1 and out[1] == "B", "single safe survivor returned")
	print("filterSafe: single safe OK")
end

-- None safe: empty roster.
do
	local out = ControlModel.filterSafe({ "A", "B" }, function() return false end)
	expect(#out == 0, "none safe -> empty")
	print("filterSafe: none safe OK")
end

-- Does not mutate the input list.
do
	local input = { "A", "B", "C" }
	ControlModel.filterSafe(input, function(p) return p ~= "B" end)
	expect(#input == 3 and input[2] == "B", "input list untouched")
	print("filterSafe: input untouched OK")
end

print("ALL FILTERSAFE TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
lune run tests/control_model_filter_safe.spec.luau
```
Expected: FAIL — `attempt to call a nil value (field 'filterSafe')`.

- [ ] **Step 3: Implement `filterSafe`**

In `src/shared/ControlModel.luau`, immediately before the final `return ControlModel` line, add:

```lua
-- Reduce an ordered roster to the subset that is currently SAFE to swap, preserving
-- order. `isSafe(player) -> bool` is injected (in production: "has solid floor beneath
-- before VOID_Y"; in tests: a plain predicate), keeping this pure. Void-bound bodies
-- are excluded from the derangement so they are never handed to another player; the
-- caller's existing `< 2` guard then suppresses the swap if too few remain. Does not
-- mutate the input.
function ControlModel.filterSafe(orderedPlayers, isSafe)
	local out = {}
	for _, player in ipairs(orderedPlayers) do
		if isSafe(player) then
			out[#out + 1] = player
		end
	end
	return out
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
lune run tests/control_model_filter_safe.spec.luau
```
Expected: PASS — ends with `ALL FILTERSAFE TESTS PASSED`.

- [ ] **Step 5: Run the full suite (confirm no regression)**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done
```
Expected: all suites pass.

- [ ] **Step 6: Commit**

```bash
git add src/shared/ControlModel.luau tests/control_model_filter_safe.spec.luau
git commit -m "feat(swap): pure ControlModel.filterSafe to exclude doomed bodies from the derangement"
```

---

## Task 3: Part B (glue) — floor probe + safe-gated commit (`RoundManager`)

**Files:**
- Modify: `src/server/RoundManager.luau` — add `hasFloorBeneath`/`isBodySafe`/`planAllSafe` near `aliveRoster` (after line 138); rewrite `commitSwap` (lines 184-198).

The probe is a downward raycast from each alive body's root to `VOID_Y`, excluding **all player bodies** (`workspace.Bodies`) and respecting `CanCollide` (so a gone `CanCollide=false` tile is correctly not floor). Doomed = no hit before the void.

- [ ] **Step 1: Add the floor probe and safe-roster helpers**

In `src/server/RoundManager.luau`, add `local Workspace = game:GetService("Workspace")` to the services block near line 21 (after the `ReplicatedStorage` line) if not already present. Then insert this block immediately after `aliveRoster` (after line 138, before `firePreview`):

```lua
-- Current-state floor probe (doom-exclusion, spec 2026-07-03 §4). A body is SAFE iff
-- a downward ray from its root to the kill-plane (VOID_Y), excluding all player bodies,
-- hits solid floor. RespectCanCollide=true means a gone (CanCollide=false) hex tile is
-- correctly NOT floor. Arena-agnostic: any arena's floors are solid parts; VOID_Y is a
-- per-arena Config value. Bodies with no floor before the void are void-bound (doomed)
-- and must be excluded from the derangement so they are never handed to a victim.
local function hasFloorBeneath(body)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bodiesFolder = Workspace:FindFirstChild("Bodies")
	params.FilterDescendantsInstances = bodiesFolder and { bodiesFolder } or {}
	params.RespectCanCollide = true
	local origin = root.Position
	local downTo = Config.VOID_Y - origin.Y -- negative: from root down to the kill-plane
	local hit = Workspace:Raycast(origin, Vector3.new(0, downTo, 0), params)
	return hit ~= nil
end

-- Is the body `player` currently controls safe to swap right now?
local function isBodySafe(player)
	return hasFloorBeneath(ControlManager.getControlledBody(player))
end

-- True iff every player in the plan currently has a safe (non-void-bound) body. Used
-- so the commit re-plans over the safe subset even when the plan is otherwise CURRENT:
-- the pre-swap rim-jump happens DURING the preview, so a still-alive planned player can
-- become doomed just before commit.
local function planAllSafe(plan)
	for _, pair in ipairs(plan.to) do
		if not isBodySafe(pair.player) then
			return false
		end
	end
	return true
end
```

- [ ] **Step 2: Rewrite `commitSwap` to gate on safety**

Replace `commitSwap` (lines 184-198) with:

```lua
-- Commit a planned swap. The commit is authoritative over the CURRENT roster: if the
-- plan went stale during the preview (someone died/left, an absorb moved a survivor),
-- OR any planned player became void-bound (doom-exclusion), recompute over the live,
-- currently-safe roster before applying. Doomed bodies are excluded from the
-- derangement (they keep their current controller and die for their own grief). Aborts
-- if fewer than 2 safe players remain (the round is ending).
local function commitSwap(plan)
	if not planIsCurrent(plan) or not planAllSafe(plan) then
		local roster = ControlModel.filterSafe(aliveRoster(), isBodySafe)
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
```

- [ ] **Step 3: Add the `ControlModel` require**

`commitSwap` now references `ControlModel.filterSafe`. Confirm `RoundManager` requires it; if not, add to the require block near line 25:

```lua
local ControlModel = require(ReplicatedStorage.Shared.ControlModel)
```
(Place it alongside the other `ReplicatedStorage.Shared.*` requires.)

- [ ] **Step 4: Run the full lune suite (confirm no regression)**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done
```
Expected: all suites pass (this task is glue; correctness is verified in the Task 6 smoke test).

- [ ] **Step 5: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(swap): exclude void-bound bodies from the derangement via current-state floor probe"
```

---

## Task 4: Part C (server) — mirror the grace gate to a `GraceProtected` attribute (`RoundManager`)

**Files:**
- Modify: `src/server/RoundManager.luau` — `stampGrace` (lines 151-159), the void monitor (around lines 279-283), and `RoundManager.eliminate` (around lines 224-231).

The monitor already computes `graceBlocked = not canDieFromHazard(...)` per body — the authoritative "am I protected right now" signal. Mirror it onto the body as `GraceProtected`, written on-change to avoid replication spam.

- [ ] **Step 1: Set `GraceProtected = true` when grace is stamped**

In `stampGrace` (lines 151-159), inside the loop, after `swapPos[player] = ...`, set the attribute on the body:

```lua
local function stampGrace(players)
	local t = now()
	for _, player in ipairs(players) do
		GraceModel.onSwap(grace, player, t, Config.GRACE_SECONDS, Config.GRACE_FLOOR_SECONDS)
		local body = ControlManager.getControlledBody(player)
		local root = body and body:FindFirstChild("HumanoidRootPart")
		swapPos[player] = root and root.Position or nil
		if body then
			body:SetAttribute("GraceProtected", true) -- client shimmer follows this
		end
	end
end
```

- [ ] **Step 2: Write the attribute on-change in the monitor**

In `startMonitor`, the sample block already computes `graceBlocked` (line 279). Immediately after that line, mirror it to the body on change (the body is `ControlManager.getControlledBody(player)` — reuse the `body` already fetched at line 259). Replace the `graceBlocked` assignment and the sample push region so it reads:

```lua
						local graceBlocked = not GraceModel.canDieFromHazard(grace, player, t)
						-- Mirror the authoritative grace gate onto the body so the client
						-- shimmer follows it instead of guessing from local input. On-change
						-- only (avoid per-tick replication spam). graceBlocked == protected.
						if body:GetAttribute("GraceProtected") ~= graceBlocked then
							body:SetAttribute("GraceProtected", graceBlocked)
						end
						samples[#samples + 1] = {
							position = root.Position,
							graceBlocked = graceBlocked,
						}
```

- [ ] **Step 3: Clear the attribute on elimination**

In `RoundManager.eliminate` (lines 224-231), where the eliminated body is fetched and sent to lobby, set `GraceProtected = false` so a body that leaves the round while still inside its window doesn't keep a stale shimmer. Update that block:

```lua
	local body = ControlManager.getControlledBody(player)
	if body then
		body:SetAttribute("GraceProtected", false)
		BodyManager.sendToLobby(player, body)
	end
```

- [ ] **Step 4: Run the full lune suite (confirm no regression)**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done
```
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(grace): mirror authoritative grace gate onto GraceProtected body attribute"
```

---

## Task 5: Part C (client) — shimmer follows `GraceProtected` (`SoulController`)

**Files:**
- Modify: `src/client/SoulController.luau:97-158` — replace `playGraceShimmer` and its call site.

Delete the `os.clock()` timer + `InputController.isMoving()` prediction. The shimmer's *lifetime* becomes server-driven: it shows while the local controlled body's `GraceProtected` attribute is true. The pulse animation is unchanged.

- [ ] **Step 1: Replace `playGraceShimmer` (lines 97-144) with an attribute-driven watcher**

```lua
-- A brief shield shimmer on the body you control, driven by the SERVER's authoritative
-- grace gate (the GraceProtected body attribute), not a local guess. It shows while the
-- attribute is true and ends the instant the server clears it, so the shield never
-- outlives real protection (no dying inside a visible shield). Cosmetic only.
local shimmerToken = nil
local graceConn = nil
local watchedBody = nil

local function stopShimmer(body)
	shimmerToken = nil
	if body then
		local hl = body:FindFirstChild("GraceShimmer")
		if hl then
			hl:Destroy()
		end
	end
end

local function startShimmer(body)
	if not (body and body.Parent) then
		return
	end
	if body:FindFirstChild("GraceShimmer") then
		return -- already shimmering
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
	task.spawn(function()
		-- `hl.Parent` guard: if the body is destroyed mid-shimmer (owner disconnects),
		-- hl is destroyed with it; stop before writing to the locked instance.
		while shimmerToken == token and hl.Parent do
			hl.FillTransparency = 0.5 + 0.3 * math.sin((os.clock() - start) * 8) -- pulse
			task.wait()
		end
	end)
end

-- Bind the shimmer to `body`'s authoritative GraceProtected attribute: show while true,
-- hide when false/absent, and re-evaluate whenever it changes. Rebound on every swap.
local function watchGrace(body)
	if graceConn then
		graceConn:Disconnect()
		graceConn = nil
	end
	-- Clear the shimmer on the PREVIOUS body (client-local highlight nothing else
	-- removes) before rebinding, so a swap doesn't leave a stale shield on the body
	-- you no longer control.
	if watchedBody then
		stopShimmer(watchedBody)
	end
	watchedBody = body
	if not (body and body.Parent) then
		return
	end
	local function refresh()
		if body:GetAttribute("GraceProtected") then
			startShimmer(body)
		else
			stopShimmer(body)
		end
	end
	graceConn = body:GetAttributeChangedSignal("GraceProtected"):Connect(refresh)
	refresh() -- catch the case where the attribute is already true
end
```

- [ ] **Step 2: Update the `SetControlledBody` handler to watch grace instead of playing the timer**

Replace the handler body (lines 149-158) so it always rebinds the grace watcher to the new body (on swap and clean retarget alike — a non-swap retarget simply finds no `GraceProtected` and shows nothing):

```lua
	SetControlledBody.OnClientEvent:Connect(function(body, _isSwap)
		myBody = body
		-- Re-emphasize immediately (don't wait for the next SoulMap broadcast).
		for b, halo in pairs(halos) do
			applyEmphasis(b, halo)
		end
		watchGrace(body)
	end)
```

- [ ] **Step 3: Remove the now-unused `InputController` require if nothing else uses it**

Check `src/client/SoulController.luau` for any remaining `InputController` reference. The grep must return no *other* use:
```bash
grep -n "InputController" src/client/SoulController.luau
```
If line 19 (`local InputController = require(...)`) is the only remaining hit, delete that line. If `InputController` is used elsewhere in the file, leave the require.

- [ ] **Step 4: Run the full lune suite (confirm no regression — this is client glue, so just ensure nothing shared broke)**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done
```
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git add src/client/SoulController.luau
git commit -m "feat(grace): client shimmer follows authoritative GraceProtected attribute; drop local-input guess"
```

---

## Task 6: Smoke-test doc + design-doc updates + full verification

**Files:**
- Create: `docs/smoke-tests/2026-07-03-core-loop-correctness-smoke-test.md`
- Modify: `docs/body-swap-royale-gdd.md`, `docs/body-swap-royale-tdd.md`

- [ ] **Step 1: Write the smoke-test doc**

Create `docs/smoke-tests/2026-07-03-core-loop-correctness-smoke-test.md` with this content:

```markdown
# Smoke Test — Core Loop Correctness Bundle (2026-07-03)

**Spec:** docs/specs/2026-07-03-core-loop-correctness-design.md
**Needs:** 2 Studio clients (Play Solo cannot exercise a real swap between two players).
**Force a swap:** `RoundManager.forceSwap()` from the server command bar (see
docs/smoke-tests/2026-06-18-round-loop-smoke-test.md).

## Part A — velocity-zero at handoff
1. Start a 2-player round. Have Player 1 sprint/leap so their body carries horizontal
   velocity, then trigger a swap at that instant.
   - **Expect:** the inheritor's new body starts at REST (no slide), and grace is NOT
     immediately cancelled by inherited momentum (shimmer persists ~its full window).

## Part B — doom-exclusion
2. **Rim jump (lowest floor / off the rim):** P1 jumps off the arena into the void just
   before a swap commits.
   - **Expect:** P1 KEEPS their own void-bound body and dies; P2 is NOT handed it and
     stays safe. No unfair inherited death.
3. **Upper-floor tile vanish at T0:** P1 stands on an upper floor, times a tile to erode
   at the swap moment, hops off.
   - **Expect:** the inheritor receives a body that finds the next floor down, falls one
     level, and survives (fresh grace). No void death.
4. **No false positive:** a normal jump over solid floor at the swap instant.
   - **Expect:** the player is NOT excluded; the swap proceeds normally.
5. **Both doomed / only one safe:** both players jump off before a swap.
   - **Expect:** safe set < 2 → no swap this cycle; griefers die; round resolves.

## Part C — authoritative grace shimmer
6. After a swap, watch the inheritor's shield shimmer while moving immediately.
   - **Expect:** the shimmer ends exactly when server protection ends (moving after the
     0.5s hard floor clears it); it NEVER pulses after the player can already die.
7. Inherit a body carrying momentum (Part A fixed) then stand still.
   - **Expect:** shimmer runs its full window; no premature end, no die-inside-shield.

## Regression
8. Normal multi-swap round with legit movement: swaps feel unchanged; halos and
   emphasis still follow control; no console errors.
```

- [ ] **Step 2: Update the GDD**

In `docs/body-swap-royale-gdd.md`, find the §12 No-Doom Assignment / pre-swap-suicide discussion and add a note that Bug #2 Layers 1–2 are now implemented via the 2026-07-03 Core Loop Correctness bundle (velocity-zero handoff + doom-exclusion floor probe). Reference the spec path. (Search for "No-Doom" or "doom" or "pre-swap"; if no such section exists, add a one-line note under the fairness/grace section pointing to the spec.)

- [ ] **Step 3: Update the TDD**

In `docs/body-swap-royale-tdd.md` §2 (Grace Window Logic / No-Doom Assignment Resolution), note that inherited momentum no longer cancels grace (velocity-zero at handoff) and that void-bound bodies are excluded from the derangement (current-state floor probe). Reference the spec path.

- [ ] **Step 4: Run the full lune suite one final time**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"
for f in tests/*.spec.luau; do echo "== $f =="; lune run "$f" || exit 1; done
```
Expected: all 19 suites pass (18 original + the new `control_model_filter_safe`).

- [ ] **Step 5: Commit**

```bash
git add docs/smoke-tests/2026-07-03-core-loop-correctness-smoke-test.md docs/body-swap-royale-gdd.md docs/body-swap-royale-tdd.md
git commit -m "docs(swap): smoke test + GDD/TDD notes for core loop correctness bundle"
```

---

## Done when

- All 19 lune suites pass (18 original + `control_model_filter_safe`).
- Parts A/B/C committed; smoke-test doc written and (manually) executed at 2 clients.
- GDD §12 / TDD §2 reflect that Bug #2 Layers 1–2 are implemented.
- Branch `feat/core-loop-correctness` ready to finish (merge/PR via `finishing-a-development-branch`).
```