# Disconnect / Control-Body Model Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make player disconnects safe under the network-ownership swap model, so a leaving player can never yank a body another player is controlling or orphan a body owned by a gone player.

**Architecture:** Extract all controllers↔bodies state and decision logic into a pure, Roblox-free module `ControlModel` (testable from the terminal with lune). The existing Roblox-coupled managers (`ControlManager`, `BodyManager`, `SwapController`, `init.server`) become thin glue that asks `ControlModel` what to do and then performs the side effects (`SetNetworkOwner`, `FireClient`, `Destroy`). The model maintains one invariant — **every body in play is controlled by exactly one connected player, and every connected player controls exactly one body (a bijection)** — and preserves it across spawn, swap, and disconnect. On disconnect it uses an *absorb* rule: the controller of the leaving player's avatar-body is moved onto the body the leaving player vacated, after which the leaving player's avatar-body is free to destroy.

**Tech Stack:** Luau, Rojo (build), [lune](https://lune-org.github.io/docs) (standalone Luau runtime for terminal unit tests), [rokit](https://github.com/rojo-rbx/rokit) (toolchain manager). The pure module is tested under lune; the Roblox glue is verified by re-running the pure tests plus a scripted 2-client Studio smoke test (it cannot be unit-tested outside the Roblox runtime, and this plan does not introduce a Roblox-runtime test harness).

---

## Background: the bug being fixed

Today, [src/server/init.server.luau:31-34](../../../src/server/init.server.luau#L31-L34) does this on `PlayerRemoving`:

```lua
ControlManager.release(player)
BodyManager.removeBody(player)   -- destroys the player's AVATAR body unconditionally
```

In the ownership model a player's **avatar-body** (the body wearing their appearance, keyed in `BodyManager.bodyByOwner`) is not the same as the body they currently **control** after a swap. So destroying the leaving player's avatar-body can destroy a body that *another* player is actively controlling (yank), and the body the leaver was controlling is left network-owned by a player who no longer exists (orphan). See the TDD "Known Open Issue" in [docs/body-swap-royale-tdd.md](../../body-swap-royale-tdd.md#4-multiplayer-design).

**Worked example (the regression test):** Players A and B own avatar-bodies `a` and `b`. After one swap, A controls `b` and B controls `a`. A disconnects. The buggy code destroys `a` (A's avatar-body) — but B is controlling `a`, so B is yanked. The fix instead *absorbs*: B (controller of A's avatar-body `a`) is moved onto `b` (the body A vacated), then `a` is destroyed. Result: B keeps controlling a live body (`b`), nothing is orphaned, and the bijection holds with one fewer player and body.

---

## File Structure

- **Create** `src/shared/ControlModel.luau` — pure controllers↔bodies state machine. No `game`, no services, no Instances-as-API (keys are opaque, compared with `==`). Exports `new`, `addPlayer`, `swap`, `removePlayer`, `controlledBody`, `derange`, `bijectionHolds`.
- **Create** `tests/control_model.spec.luau` — lune unit tests for `ControlModel`.
- **Create** `rokit.toml` — pins `lune` and `rojo`.
- **Modify** `src/server/ControlManager.luau` — delegate state to a `ControlModel` instance; expose `addPlayer`, `swap`, `removePlayer`, `getControlledBody`; perform `SetNetworkOwner` + `FireClient` + body destroy.
- **Modify** `src/server/SwapController.luau` — drop its private Sattolo copy; build the active-player list and call `ControlManager.swap`.
- **Modify** `src/server/init.server.luau` — use `ControlManager.addPlayer` on join and `ControlManager.removePlayer` on leave (removing the unconditional `BodyManager.removeBody` call).
- **Unchanged** `src/server/BodyManager.luau` — `createBody`/`removeBody(player)` already do exactly the avatar-body lifecycle the glue needs; `removeBody(player)` destroys `bodyByOwner[player]`, which is always the leaving player's avatar-body.

`ControlModel` is built by Rojo into `ReplicatedStorage.Shared.ControlModel` (via the existing `src/shared` mapping) and required by the server glue as `require(ReplicatedStorage.Shared.ControlModel)`. The same file is required by the lune tests as a relative path. It must therefore contain **no** `require` of its own and no Roblox API calls.

---

## Task 1: Toolchain — add rokit + lune, verify it runs

**Files:**
- Create: `rokit.toml`
- Create: `tests/.gitkeep`

- [ ] **Step 1: Install rokit (one-time, machine-level)**

If `rokit` is not already installed, follow https://github.com/rojo-rbx/rokit (e.g. on Windows download the installer from the latest release, or `cargo install rokit` then `rokit self-install`). Verify:

Run: `rokit --version`
Expected: prints a version like `rokit 1.x.x`

- [ ] **Step 2: Initialize the project toolchain and add tools**

Run these from the repo root:

```bash
rokit init
rokit add lune-org/lune
rokit add rojo-rbx/rojo
rokit install
```

`rokit add` resolves the latest published version of each tool and writes it into `rokit.toml`; `rokit install` downloads them. After this, `rokit.toml` should contain a `[tools]` section with `lune` and `rojo` entries (exact versions are whatever was latest).

- [ ] **Step 3: Verify lune is available**

Run: `lune --version`
Expected: prints a version like `lune 0.8.x` (any installed version is fine)

> If your shell can't find `lune`, prefix tool commands with `rokit run`, e.g. `rokit run lune --version`. Use that same prefix for every `lune ...` command later in this plan if needed.

- [ ] **Step 4: Create the tests directory placeholder**

Create `tests/.gitkeep` as an empty file so the directory is tracked before any spec exists.

- [ ] **Step 5: Smoke-test that lune can run a Luau script**

Create a throwaway file `tests/_smoke.luau` with:

```lua
print("lune ok")
```

Run: `lune run tests/_smoke.luau`
Expected: prints `lune ok` and exits 0

Then delete it:

```bash
rm tests/_smoke.luau
```

- [ ] **Step 6: Commit**

```bash
git add rokit.toml tests/.gitkeep
git commit -m "chore: add rokit toolchain with lune + rojo for terminal tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `ControlModel.derange` — Sattolo single-cycle derangement (pure)

This moves the swap permutation out of `SwapController` into the pure, testable module, with an injectable RNG.

**Files:**
- Create: `src/shared/ControlModel.luau`
- Test: `tests/control_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/control_model.spec.luau`:

```lua
local ControlModel = require("../src/shared/ControlModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- derange: with a deterministic rng that always returns 1, the result is a fixed,
-- known single-cycle permutation; and no element keeps its original index.
do
	local list = { "a", "b", "c", "d" }
	local rng = function(_n) return 1 end -- always pick j = 1
	ControlModel.derange(list, rng)

	-- Sattolo with j=1 each pass on {a,b,c,d}:
	--   i=4: swap(4,1) -> {d,b,c,a}
	--   i=3: swap(3,1) -> {c,b,d,a}
	--   i=2: swap(2,1) -> {b,c,d,a}
	expect(list[1] == "b", "derange[1] expected b, got " .. tostring(list[1]))
	expect(list[2] == "c", "derange[2] expected c, got " .. tostring(list[2]))
	expect(list[3] == "d", "derange[3] expected d, got " .. tostring(list[3]))
	expect(list[4] == "a", "derange[4] expected a, got " .. tostring(list[4]))
	print("derange: deterministic single-cycle OK")
end

-- derange: n = 2 always swaps (only valid derangement of 2 elements).
do
	local list = { "x", "y" }
	ControlModel.derange(list, function(_n) return 1 end)
	expect(list[1] == "y" and list[2] == "x", "derange n=2 must swap")
	print("derange: n=2 swaps OK")
end

print("ALL CONTROLMODEL TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lune run tests/control_model.spec.luau`
Expected: FAIL — error like `module not found` or `attempt to call a nil value (field 'derange')`

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/ControlModel.luau`:

```lua
--[[
	ControlModel -- PURE controllers<->bodies state machine.
	Location (Roblox): ReplicatedStorage/Shared/ControlModel  (ModuleScript)

	No Roblox APIs and no requires of its own, so it can be unit-tested from the
	terminal with lune and shipped unchanged via Rojo. Keys ("players" and
	"bodies") are opaque values compared with ==; in production they are Player
	and body-Model instances, in tests they are plain strings.

	Invariant it maintains: every body in play is controlled by exactly one
	connected player, and every connected player controls exactly one body
	(a bijection). Spawn, swap, and disconnect all preserve it.
--]]

local ControlModel = {}

-- Sattolo's algorithm: one pass, single-cycle permutation = always a derangement
-- (no element keeps its index). `randint(m)` must return an integer in [1, m].
function ControlModel.derange(list, randint)
	for i = #list, 2, -1 do
		local j = randint(i - 1) -- draw from 1..i-1 (never i): guarantees no fixed point
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return ControlModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `lune run tests/control_model.spec.luau`
Expected: PASS — prints `derange: deterministic single-cycle OK`, `derange: n=2 swaps OK`, `ALL CONTROLMODEL TESTS PASSED`, exits 0

- [ ] **Step 5: Commit**

```bash
git add src/shared/ControlModel.luau tests/control_model.spec.luau
git commit -m "feat: add pure ControlModel.derange (Sattolo) with lune tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `ControlModel.new` + `addPlayer` + `controlledBody` + `bijectionHolds`

**Files:**
- Modify: `src/shared/ControlModel.luau`
- Test: `tests/control_model.spec.luau`

- [ ] **Step 1: Add the failing tests**

Append this block to `tests/control_model.spec.luau` **immediately before** the final `print("ALL CONTROLMODEL TESTS PASSED")` line:

```lua
-- new + addPlayer: each player spawns controlling their own avatar body.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")

	expect(ControlModel.controlledBody(m, "A") == "a", "A should control a")
	expect(ControlModel.controlledBody(m, "B") == "b", "B should control b")
	expect(ControlModel.bijectionHolds(m), "bijection should hold after spawns")
	print("addPlayer: self-control + bijection OK")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `lune run tests/control_model.spec.luau`
Expected: FAIL — `attempt to call a nil value (field 'new')`

- [ ] **Step 3: Implement**

In `src/shared/ControlModel.luau`, add these functions **above** the final `return ControlModel` line:

```lua
function ControlModel.new()
	return {
		players = {},      -- [player] = true   (connected set)
		bodyOf = {},       -- [player] = body    (body the player currently controls)
		controllerOf = {}, -- [body]   = player  (inverse of bodyOf)
		ownerBody = {},    -- [player] = body    (the body wearing this player's avatar; stable)
	}
end

-- A player joins/spawns: they own a fresh body and start by controlling it.
function ControlModel.addPlayer(model, player, body)
	model.players[player] = true
	model.ownerBody[player] = body
	model.bodyOf[player] = body
	model.controllerOf[body] = player
end

function ControlModel.controlledBody(model, player)
	return model.bodyOf[player]
end

-- True iff every connected player controls exactly one body and vice versa.
function ControlModel.bijectionHolds(model)
	local nPlayers, nBodies = 0, 0
	for player in pairs(model.players) do
		nPlayers += 1
		local body = model.bodyOf[player]
		if body == nil or model.controllerOf[body] ~= player then
			return false
		end
	end
	for _body, player in pairs(model.controllerOf) do
		nBodies += 1
		if model.players[player] == nil then
			return false
		end
	end
	return nPlayers == nBodies
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `lune run tests/control_model.spec.luau`
Expected: PASS — includes `addPlayer: self-control + bijection OK`

- [ ] **Step 5: Commit**

```bash
git add src/shared/ControlModel.luau tests/control_model.spec.luau
git commit -m "feat: ControlModel state, addPlayer, controlledBody, bijectionHolds

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `ControlModel.swap` — derange current bodies, no fixed point, bijection preserved

**Files:**
- Modify: `src/shared/ControlModel.luau`
- Test: `tests/control_model.spec.luau`

- [ ] **Step 1: Add the failing tests**

Append this block to `tests/control_model.spec.luau` **immediately before** the final `print("ALL CONTROLMODEL TESTS PASSED")` line:

```lua
-- swap: 3 players, deterministic rng -> single-cycle derangement of current bodies.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.addPlayer(m, "C", "c")

	local pairs_ = ControlModel.swap(m, { "A", "B", "C" }, function(_n) return 1 end)

	-- No player keeps their previous body.
	expect(ControlModel.controlledBody(m, "A") ~= "a", "A must not keep a")
	expect(ControlModel.controlledBody(m, "B") ~= "b", "B must not keep b")
	expect(ControlModel.controlledBody(m, "C") ~= "c", "C must not keep c")

	-- Still a bijection (every body controlled once, every player controls once).
	expect(ControlModel.bijectionHolds(m), "bijection must survive swap")

	-- Returned pairs describe exactly who now controls what.
	expect(#pairs_ == 3, "swap should return 3 pairs")
	for _, pr in ipairs(pairs_) do
		expect(ControlModel.controlledBody(m, pr.player) == pr.body, "pair must match model")
	end
	print("swap: derangement + bijection + pairs OK")
end

-- swap: 2 players always exchange.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.swap(m, { "A", "B" }, function(_n) return 1 end)
	expect(ControlModel.controlledBody(m, "A") == "b", "A should now control b")
	expect(ControlModel.controlledBody(m, "B") == "a", "B should now control a")
	print("swap: n=2 exchange OK")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `lune run tests/control_model.spec.luau`
Expected: FAIL — `attempt to call a nil value (field 'swap')`

- [ ] **Step 3: Implement**

In `src/shared/ControlModel.luau`, add **above** the final `return ControlModel` line:

```lua
-- Rotate control among the given connected players. Deranges their CURRENT bodies
-- (Sattolo), so nobody keeps the body they were just in. Because it permutes the
-- exact same set of bodies the players already hold, it stays a bijection.
-- Returns an array of { player = <player>, body = <body> } describing the new map.
function ControlModel.swap(model, orderedPlayers, randint)
	assert(#orderedPlayers >= 2, "swap needs >= 2 players")

	local bodies = {}
	for i, player in ipairs(orderedPlayers) do
		bodies[i] = model.bodyOf[player]
	end

	ControlModel.derange(bodies, randint)

	-- Every body in `bodies` gets exactly one new controller, so overwriting
	-- controllerOf/bodyOf fully reassigns with no stale entries.
	local result = {}
	for i, player in ipairs(orderedPlayers) do
		local newBody = bodies[i]
		model.bodyOf[player] = newBody
		model.controllerOf[newBody] = player
		result[i] = { player = player, body = newBody }
	end
	return result
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `lune run tests/control_model.spec.luau`
Expected: PASS — includes `swap: derangement + bijection + pairs OK` and `swap: n=2 exchange OK`

- [ ] **Step 5: Commit**

```bash
git add src/shared/ControlModel.luau tests/control_model.spec.luau
git commit -m "feat: ControlModel.swap (derange current bodies, preserve bijection)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `ControlModel.removePlayer` — the disconnect fix (absorb rule)

This is the core of the plan: the rule that prevents the yank/orphan bug.

**Files:**
- Modify: `src/shared/ControlModel.luau`
- Test: `tests/control_model.spec.luau`

- [ ] **Step 1: Add the failing tests**

Append this block to `tests/control_model.spec.luau` **immediately before** the final `print("ALL CONTROLMODEL TESTS PASSED")` line:

```lua
-- removePlayer CASE 1: player controls their OWN avatar body (no swap happened).
-- Their body is destroyed; no reassignment; remaining players keep a valid bijection.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")

	local r = ControlModel.removePlayer(m, "A")

	expect(r.destroyOwn == true, "A's own body must be destroyed")
	expect(r.reassign == nil, "no reassignment needed when controlling own body")
	expect(m.players["A"] == nil, "A must be removed from players")
	expect(ControlModel.controlledBody(m, "B") == "b", "B unaffected")
	expect(ControlModel.bijectionHolds(m), "bijection holds for remaining players")
	print("removePlayer: case 1 (own body) OK")
end

-- removePlayer CASE 2 (THE REGRESSION): after a swap A controls b, B controls a.
-- A disconnects. B (controller of A's avatar body `a`) must be ABSORBED onto the
-- body A vacated (`b`), then `a` is destroyed. B must NOT be yanked.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	ControlModel.addPlayer(m, "B", "b")
	ControlModel.swap(m, { "A", "B" }, function(_n) return 1 end) -- A->b, B->a

	expect(ControlModel.controlledBody(m, "A") == "b", "precondition: A controls b")
	expect(ControlModel.controlledBody(m, "B") == "a", "precondition: B controls a")

	local r = ControlModel.removePlayer(m, "A")

	expect(r.destroyOwn == true, "A's avatar body (a) must be destroyed")
	expect(r.reassign ~= nil, "B must be reassigned (absorbed)")
	expect(r.reassign.player == "B", "the absorbed player is B")
	expect(r.reassign.body == "b", "B is moved onto the vacated body b")
	expect(ControlModel.controlledBody(m, "B") == "b", "B now controls a LIVE body (not yanked)")
	expect(m.controllerOf["a"] == nil, "destroyed body a has no controller")
	expect(m.players["A"] == nil, "A removed")
	expect(ControlModel.bijectionHolds(m), "bijection holds after absorb")
	print("removePlayer: case 2 (absorb / regression) OK")
end

-- removePlayer: unknown player is a no-op.
do
	local m = ControlModel.new()
	ControlModel.addPlayer(m, "A", "a")
	local r = ControlModel.removePlayer(m, "ghost")
	expect(r.destroyOwn == false and r.reassign == nil, "removing unknown player is a no-op")
	expect(ControlModel.bijectionHolds(m), "bijection unaffected")
	print("removePlayer: unknown player no-op OK")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `lune run tests/control_model.spec.luau`
Expected: FAIL — `attempt to call a nil value (field 'removePlayer')`

- [ ] **Step 3: Implement**

In `src/shared/ControlModel.luau`, add **above** the final `return ControlModel` line:

```lua
-- Handle a player disconnecting while preserving the bijection.
--
-- `freed` = the body the player currently controls (it loses its controller).
-- `own`   = the body wearing the leaving player's avatar (it must be destroyed,
--           since its owner is gone).
--
-- If another connected player Q controls `own`, ABSORB: move Q onto `freed`
-- (the just-vacated body), so `own` becomes controllerless and can be destroyed
-- without yanking Q. If the player controlled their own avatar body
-- (freed == own), there is nobody to absorb and we simply destroy it.
--
-- Returns: {
--   destroyOwn = boolean,                       -- caller destroys the player's avatar body
--   reassign   = { player = Q, body = freed } | nil,  -- caller hands Q ownership of `freed`
-- }
function ControlModel.removePlayer(model, player)
	if not model.players[player] then
		return { destroyOwn = false, reassign = nil }
	end

	local freed = model.bodyOf[player]
	local own = model.ownerBody[player]

	-- Drop the leaving player's control first.
	if freed ~= nil then
		model.controllerOf[freed] = nil
	end
	model.bodyOf[player] = nil

	local reassign = nil
	if own ~= nil then
		-- If freed == own this is already nil (we just cleared it): nobody to absorb.
		local otherController = model.controllerOf[own]
		if otherController ~= nil and freed ~= nil and freed ~= own then
			-- Absorb: move the other controller onto the vacated body.
			model.controllerOf[own] = nil
			model.bodyOf[otherController] = freed
			model.controllerOf[freed] = otherController
			reassign = { player = otherController, body = freed }
		end
		model.ownerBody[player] = nil
	end

	model.players[player] = nil
	return { destroyOwn = (own ~= nil), reassign = reassign }
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `lune run tests/control_model.spec.luau`
Expected: PASS — includes `removePlayer: case 1 (own body) OK`, `removePlayer: case 2 (absorb / regression) OK`, `removePlayer: unknown player no-op OK`, `ALL CONTROLMODEL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add src/shared/ControlModel.luau tests/control_model.spec.luau
git commit -m "feat: ControlModel.removePlayer absorb rule (fixes disconnect yank/orphan)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Wire `ControlManager` to `ControlModel` (Roblox glue)

`ControlManager` stops holding its own maps and instead owns a `ControlModel` instance, translating model intents into `SetNetworkOwner` / `FireClient` / body destruction. There is no terminal unit test for this file (it needs the Roblox runtime); correctness rests on the pure tests plus the Studio smoke test in Task 7.

**Files:**
- Modify: `src/server/ControlManager.luau` (full rewrite)

- [ ] **Step 1: Rewrite the file**

Replace the entire contents of `src/server/ControlManager.luau` with:

```lua
--[[
	ControlManager (server) -- thin glue over the pure ControlModel.

	Holds one ControlModel instance (the controllers<->bodies state) and turns its
	decisions into Roblox side effects: network ownership, the SetControlledBody
	notification, and avatar-body destruction on disconnect.

	Depends on:
	  ReplicatedStorage.Shared.Remotes      -> SetControlledBody  (RemoteEvent)
	  ReplicatedStorage.Shared.ControlModel -> pure state machine
	  ServerScriptService.Server.BodyManager -> destroys the leaving player's body
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ControlModel = require(ReplicatedStorage.Shared.ControlModel)
local BodyManager = require(script.Parent.BodyManager)
local SetControlledBody = Remotes.get("SetControlledBody")

local ControlManager = {}
local model = ControlModel.new()

-- Hand `player` network ownership of `body` and tell their client to retarget.
local function applyOwnership(player, body, isSwap)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root then
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
	SetControlledBody:FireClient(player, body, isSwap == true)
end

-- Player spawned: they own `body` and start by controlling it.
function ControlManager.addPlayer(player, body)
	ControlModel.addPlayer(model, player, body)
	applyOwnership(player, body, false)
end

-- Rotate control across `orderedPlayers` (a swap). Returns how many were swapped.
function ControlManager.swap(orderedPlayers)
	local result = ControlModel.swap(model, orderedPlayers, function(n)
		return math.random(1, n)
	end)
	for _, pair in ipairs(result) do
		applyOwnership(pair.player, pair.body, true)
	end
	return #result
end

-- Player left: apply the model's absorb decision, then destroy their avatar body.
function ControlManager.removePlayer(player)
	local decision = ControlModel.removePlayer(model, player)
	if decision.reassign then
		applyOwnership(decision.reassign.player, decision.reassign.body, false)
	end
	if decision.destroyOwn then
		BodyManager.removeBody(player) -- destroys bodyByOwner[player] = the leaving player's avatar body
	end
end

function ControlManager.getControlledBody(player)
	return ControlModel.controlledBody(model, player)
end

return ControlManager
```

- [ ] **Step 2: Re-run the pure tests (still the regression guard)**

Run: `lune run tests/control_model.spec.luau`
Expected: PASS — `ALL CONTROLMODEL TESTS PASSED` (this confirms the model the glue depends on is intact)

- [ ] **Step 3: Static check that no caller references removed methods**

Run: `git grep -n "ControlManager.assignOne\|ControlManager.release\|controllerOf\|bodyOf" -- src/server`
Expected: **no matches in `ControlManager.luau` or `SwapController.luau` consumers** for `assignOne`/`release`. (Matches inside `init.server.luau` will be fixed in Task 7; if `assignOne`/`release` appear anywhere else, update those call sites to `addPlayer`/`swap`/`removePlayer`.)

- [ ] **Step 4: Commit**

```bash
git add src/server/ControlManager.luau
git commit -m "refactor: ControlManager delegates state to ControlModel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Wire `SwapController` + `init.server`, remove the buggy destroy

**Files:**
- Modify: `src/server/SwapController.luau` (full rewrite)
- Modify: `src/server/init.server.luau` (full rewrite)

- [ ] **Step 1: Rewrite `SwapController.luau`**

Replace the entire contents of `src/server/SwapController.luau` with:

```lua
--[[
	SwapController (server) -- drives the periodic swap.

	Every CYCLE_SECONDS it gathers the connected players who currently control a
	living body and asks ControlManager to rotate their control. The derangement
	itself now lives in the pure ControlModel (ControlManager.swap), so this file
	only decides WHO is eligible and WHEN.

	Depends on:
	  ReplicatedStorage.Shared.Config        (CYCLE_SECONDS)
	  ServerScriptService.Server.ControlManager
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ControlManager = require(script.Parent.ControlManager)

local SwapController = {}

-- Connected players who currently control a living body.
local function getActivePlayers()
	local players = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local body = ControlManager.getControlledBody(player)
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		if body and body.Parent and hum and hum.Health > 0 then
			table.insert(players, player)
		end
	end
	return players
end

function SwapController.swap()
	local players = getActivePlayers()
	if #players < 2 then
		return false, "need >=2 active players"
	end
	local n = ControlManager.swap(players)
	return true, string.format("swapped %d players", n)
end

function SwapController.start()
	task.spawn(function()
		while true do
			task.wait(Config.CYCLE_SECONDS)
			local ok, msg = SwapController.swap()
			print("[BSR] swap:", ok, msg)
		end
	end)
end

return SwapController
```

- [ ] **Step 2: Rewrite `init.server.luau`**

Replace the entire contents of `src/server/init.server.luau` with:

```lua
--[[
	Server bootstrap (Init) -- ownership-transfer model.
	Location: ServerScriptService/Server  (Script; siblings are its child modules)

	Players have NO Character; they're disembodied controllers. Each gets a
	persistent body wearing their avatar, and starts by controlling their own.
	Every CYCLE_SECONDS the SwapController rotates control so nobody keeps it.

	On disconnect, ControlManager.removePlayer applies the absorb rule so a leaving
	player never yanks a body someone else controls, then destroys the leaver's
	avatar body. (It is NOT safe to destroy the avatar body directly here.)
--]]

local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local BodyManager = require(script.BodyManager)
local ControlManager = require(script.ControlManager)
local SwapController = require(script.SwapController)

local function onPlayerAdded(player)
	local body = BodyManager.createBody(player) -- persistent avatar body
	ControlManager.addPlayer(player, body)      -- start in your own body
	print(string.format("[BSR] %s -> own body (%s)", player.Name, body.Name))
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	ControlManager.removePlayer(player) -- absorb + destroy; never a bare removeBody
end)

SwapController.start()
print("[BSR] Server ready (ownership-transfer model). Swap loop active.")
```

- [ ] **Step 3: Confirm no stale references remain**

Run: `git grep -n "assignOne\|ControlManager.release\|sattolo" -- src`
Expected: no matches (the old `assignOne`/`release` API and the in-`SwapController` `sattolo` copy are gone; derangement now lives in `ControlModel.derange`).

- [ ] **Step 4: Build the place to confirm it compiles via Rojo**

Run: `rojo build -o build-check.rbxlx`
Expected: builds with no errors and writes `build-check.rbxlx`. Then remove it:

```bash
rm build-check.rbxlx
```

> `.gitignore` only ignores the specific name `body-swap-royale.rbxlx`, so `build-check.rbxlx` is *not* ignored — delete it explicitly (above) so it is never committed.

- [ ] **Step 5: Manual Studio smoke test (records the runtime behavior the pure tests model)**

1. In Roblox Studio, open this Rojo project (`rojo serve`, connect the plugin) or `rojo build` and open the place.
2. Test → start a **Local Server with 2 players**.
3. Confirm each player controls their own avatar body and can move (WASD) — the swap/control path still works.
4. Wait ~30s for one swap; confirm both players' controlled bodies change and movement still works after the FOV punch.
5. In the server view, run in the command bar: `game.Players:GetPlayers()[1]:Kick("disconnect test")` to drop player 1 **after** a swap has occurred.
6. **Expected:** the remaining player keeps controlling a living body without interruption (no freeze, no nil camera subject), and exactly one body is removed from `workspace.Bodies` (the kicked player's avatar body). The server output shows no errors.

Record the result (pass/fail + any output) when reporting task completion.

- [ ] **Step 6: Commit**

```bash
git add src/server/SwapController.luau src/server/init.server.luau
git commit -m "fix: safe disconnect handling via ControlManager.removePlayer

PlayerRemoving no longer destroys a player's avatar body unconditionally
(which could yank a body another player controlled or orphan one). Control
rotation now uses the pure ControlModel derangement.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Update the CHANGELOG and TDD open-issue note

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/body-swap-royale-tdd.md`

- [ ] **Step 1: Add CHANGELOG entries**

In `CHANGELOG.md`, under `## [Unreleased]`, add a new `### Added` bullet and a `### Fixed` section (create `### Fixed` if absent), keeping the existing entries:

```markdown
### Added
- `src/shared/ControlModel.luau` — pure, Roblox-free controllers↔bodies state
  machine (spawn / swap / disconnect) maintaining a player↔body bijection. Unit
  tested from the terminal with lune (`tests/control_model.spec.luau`).
- `rokit.toml` — toolchain pinning `lune` (terminal Luau tests) and `rojo`.

### Fixed
- Disconnect handling no longer destroys a leaving player's avatar body
  unconditionally. After a swap that body may be controlled by another player;
  the old code yanked them and orphaned the leaver's controlled body.
  `ControlManager.removePlayer` now applies an "absorb" rule (move the other
  controller onto the vacated body, then destroy the leaver's body), preserving
  the controllers↔bodies bijection. Derangement moved from `SwapController` into
  `ControlModel.derange`.
```

- [ ] **Step 2: Resolve the TDD "Known Open Issue"**

In `docs/body-swap-royale-tdd.md`, find the `### ⚠️ Known Open Issue — disconnect cleanup vs. the ownership model` heading (in §4). Change the status line:

```markdown
**Status: unresolved; must be fixed before MVP.**
```

to:

```markdown
**Status: RESOLVED (2026-06-18).** Implemented via the pure `ControlModel` absorb rule and `ControlManager.removePlayer`; see `docs/superpowers/plans/2026-06-18-disconnect-control-model-fix.md`. Regression covered by `tests/control_model.spec.luau` (case 2). The notes below are retained as the rationale.
```

Then in §9 Technical Risks, change the row:

```markdown
| **Disconnect cleanup corrupts the controllers↔bodies bijection** | **High** | See §4 Known Open Issue — decouple body lifecycle from control map before MVP |
```

to:

```markdown
| **Disconnect cleanup corrupts the controllers↔bodies bijection** | **Resolved** | Fixed via the ControlModel absorb rule + `ControlManager.removePlayer`; bijection asserted by lune tests. See §4. |
```

- [ ] **Step 3: Final full test run**

Run: `lune run tests/control_model.spec.luau`
Expected: PASS — `ALL CONTROLMODEL TESTS PASSED`

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md docs/body-swap-royale-tdd.md
git commit -m "docs: record disconnect fix in CHANGELOG and resolve TDD open issue

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the next plans (out of scope here)

These remain MVP-core and each warrants its own spec→plan cycle, building on the clean bijection this plan establishes:

- **RoundManager** — phase state machine (lobby / pre-round / active / preview / swap / grace / end), gating the currently-unconditional swap loop and providing round-boundary body cleanup.
- **Grace window + hazards + elimination + win condition** — consumes `Config.GRACE_SECONDS`; needs a `CanDieFromHazard` path and a death/elimination signal (which then makes `getActivePlayers`' `Health > 0` filter meaningful).
- **Swap preview** — `PREVIEW_SECONDS`, `SwapPreview`/`SwapEvent` remotes, target-body telegraph.
- **Server-side movement validation** — load-bearing under client-owned physics.
- **Free Soul halo** — identity anchor.
