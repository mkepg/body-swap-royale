# RoundState Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `RoundState`, a pure Roblox-free round-lifecycle state machine (phase + alive set + winner), unit-tested with lune, as the first piece of the MVP win/lose gap.

**Architecture:** A single pure module mirroring `src/shared/ControlModel.luau`: opaque player keys compared with `==`, no Roblox APIs, no clocks. It owns only the round lifecycle (`Lobby → Active → Ended → reset`), tracks `present`/`alive` sets and a `winner`, and auto-ends when fewer than `minToContinue` players remain alive. Thresholds are injected (server passes `Config`, tests pass literals). The server glue (future RoundManager) keeps it in sync with `ControlModel`.

**Tech Stack:** Luau, lune (terminal test runner, pinned in `rokit.toml`), Rojo.

**Spec:** [docs/superpowers/specs/2026-06-18-round-state-design.md](../specs/2026-06-18-round-state-design.md)

**Test command (used in every task):**
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
lune runs the whole spec file at once; there is no per-test selection. "Verify it fails" means run the file and see the new assertion/`require` error; "verify it passes" means the file prints `ALL ROUNDSTATE TESTS PASSED`.

**Branch:** Work continues on `feat/round-state` (already created; the spec is committed there).

---

### Task 1: Config thresholds

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Add the two threshold constants**

In `src/shared/Config.luau`, immediately after the `Config.GRACE_FLOOR_SECONDS = 0.5` line (end of the "Round timing" block), add:

```lua

-- Round population thresholds (consumed by RoundState via the server glue).
-- Defaults of 2 keep the MVP playable with two friends; raise toward the GDD's
-- 4/6 numbers later with no logic change. "Continue = 2" => the round ends the
-- instant fewer than 2 players remain alive, so the last one standing wins.
Config.MIN_PLAYERS_TO_START = 2
Config.MIN_PLAYERS_TO_CONTINUE = 2
```

- [ ] **Step 2: Sanity-check the file parses**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/control_model.spec.luau
```
Expected: still prints `ALL CONTROLMODEL TESTS PASSED` (Config isn't imported there, but this confirms the toolchain and that nothing else broke).

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat: add round population thresholds to Config"
```

---

### Task 2: Module skeleton — new / addPlayer / canStart / getters

**Files:**
- Create: `src/shared/RoundState.luau`
- Create: `tests/round_state.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/round_state.spec.luau` with:

```lua
local RoundState = require("../src/shared/RoundState")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

-- new + addPlayer + getters: fresh model starts in Lobby, empty, no winner.
do
	local m = RoundState.new(2, 2)
	expect(RoundState.getPhase(m) == "Lobby", "fresh model is in Lobby")
	expect(RoundState.getWinner(m) == nil, "fresh model has no winner")
	expect(RoundState.aliveCount(m) == 0, "fresh model has nobody alive")
	expect(not RoundState.isAlive(m, "A"), "unknown player is not alive")
	print("new: empty Lobby model OK")
end

-- canStart: false below minToStart, true at/above it, false outside Lobby.
do
	local m = RoundState.new(2, 2)
	expect(not RoundState.canStart(m), "0 present < minToStart(2) -> cannot start")
	RoundState.addPlayer(m, "A")
	expect(not RoundState.canStart(m), "1 present < 2 -> cannot start")
	RoundState.addPlayer(m, "B")
	expect(RoundState.canStart(m), "2 present >= 2 -> can start")
	print("canStart: threshold gating OK")
end

print("ALL ROUNDSTATE TESTS PASSED")
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: FAIL — error requiring/indexing `RoundState` (module does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `src/shared/RoundState.luau` with:

```lua
--[[
	RoundState -- PURE round-lifecycle state machine.
	Location (Roblox): ReplicatedStorage/Shared/RoundState  (ModuleScript)

	No Roblox APIs and no clocks. Player keys are opaque, compared with ==;
	in production they are Player instances, in tests plain strings. Mirrors
	ControlModel.

	Tracks ONLY the round lifecycle: phase, who is present (the lobby roster),
	who is alive, and the winner. It knows nothing about bodies or ownership;
	the server glue coordinates it with ControlModel.

	Phases:  "Lobby" -> "Active" -> "Ended" -> (reset) "Lobby".
	Invariant: `alive` is always a subset of `present`.

	Thresholds are injected (the server passes Config values; tests pass
	literals), the same way ControlModel injects `randint`.
--]]

local RoundState = {}

local function count(set)
	local n = 0
	for _ in pairs(set) do
		n += 1
	end
	return n
end

function RoundState.new(minToStart, minToContinue)
	return {
		phase = "Lobby",   -- "Lobby" | "Active" | "Ended"
		present = {},       -- [player] = true : connected, in the lobby roster
		alive = {},         -- [player] = true : alive in the current Active round
		winner = nil,       -- player; set only on a win
		minToStart = minToStart,
		minToContinue = minToContinue,
	}
end

function RoundState.getPhase(model)
	return model.phase
end

function RoundState.getWinner(model)
	return model.winner
end

function RoundState.aliveCount(model)
	return count(model.alive)
end

function RoundState.isAlive(model, player)
	return model.alive[player] == true
end

function RoundState.addPlayer(model, player)
	model.present[player] = true
end

function RoundState.canStart(model)
	return model.phase == "Lobby" and count(model.present) >= model.minToStart
end

return RoundState
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: PASS — prints `new: empty Lobby model OK`, `canStart: threshold gating OK`, `ALL ROUNDSTATE TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/RoundState.luau tests/round_state.spec.luau
git commit -m "feat: RoundState skeleton (new/addPlayer/canStart/getters)"
```

---

### Task 3: beginRound — snapshot present into alive

**Files:**
- Modify: `src/shared/RoundState.luau`
- Modify: `tests/round_state.spec.luau`

- [ ] **Step 1: Write the failing test**

In `tests/round_state.spec.luau`, insert this block immediately **before** the final `print("ALL ROUNDSTATE TESTS PASSED")` line:

```lua
-- beginRound: Lobby -> Active; snapshots present into alive; returns the roster.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")

	local roster = RoundState.beginRound(m)

	expect(RoundState.getPhase(m) == "Active", "beginRound enters Active")
	expect(RoundState.aliveCount(m) == 3, "all 3 present are alive at start")
	expect(RoundState.isAlive(m, "A") and RoundState.isAlive(m, "B") and RoundState.isAlive(m, "C"),
		"each present player is alive")
	expect(#roster == 3, "roster lists all starting players")

	-- roster contents equal the present set (order unspecified).
	local seen = {}
	for _, p in ipairs(roster) do
		seen[p] = true
	end
	expect(seen["A"] and seen["B"] and seen["C"], "roster contains exactly the present players")

	expect(not RoundState.canStart(m), "cannot start again while Active")
	print("beginRound: snapshot present->alive + roster OK")
end

-- beginRound: refuses to start below threshold.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	local ok = pcall(RoundState.beginRound, m)
	expect(not ok, "beginRound errors when canStart is false")
	print("beginRound: refuses below threshold OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: FAIL — `attempt to call a nil value (field 'beginRound')`.

- [ ] **Step 3: Write minimal implementation**

In `src/shared/RoundState.luau`, add this function immediately **before** the final `return RoundState`:

```lua
-- Lobby -> Active. Snapshots the current `present` set into `alive` and returns
-- the starting roster as an array so the caller can spawn / assign control.
function RoundState.beginRound(model)
	assert(RoundState.canStart(model), "beginRound requires canStart")
	model.phase = "Active"
	model.winner = nil
	model.alive = {}
	local roster = {}
	for player in pairs(model.present) do
		model.alive[player] = true
		roster[#roster + 1] = player
	end
	return roster
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: PASS — includes `beginRound: snapshot present->alive + roster OK` and `beginRound: refuses below threshold OK`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/RoundState.luau tests/round_state.spec.luau
git commit -m "feat: RoundState.beginRound snapshots roster into alive"
```

---

### Task 4: eliminate — auto-end and winner

**Files:**
- Modify: `src/shared/RoundState.luau`
- Modify: `tests/round_state.spec.luau`

- [ ] **Step 1: Write the failing test**

In `tests/round_state.spec.luau`, insert this block immediately **before** the final `print("ALL ROUNDSTATE TESTS PASSED")` line:

```lua
-- eliminate: down to one survivor -> Ended with the correct winner.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")
	RoundState.beginRound(m)

	local r1 = RoundState.eliminate(m, "A")
	expect(r1.ended == false, "round continues with 2 alive")
	expect(r1.winner == nil, "no winner while 2 alive")
	expect(RoundState.getPhase(m) == "Active", "still Active after first elimination")

	local r2 = RoundState.eliminate(m, "B")
	expect(r2.ended == true, "round ends when 1 remains")
	expect(r2.winner == "C", "C is the last one standing")
	expect(RoundState.getPhase(m) == "Ended", "phase is Ended")
	expect(RoundState.getWinner(m) == "C", "winner recorded on the model")
	print("eliminate: auto-end + winner OK")
end

-- eliminate: no-op on a non-alive player and outside Active.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")

	-- Before the round starts (Lobby), eliminate does nothing.
	local rLobby = RoundState.eliminate(m, "A")
	expect(rLobby.ended == false and rLobby.winner == nil, "eliminate is a no-op in Lobby")

	RoundState.beginRound(m)
	RoundState.eliminate(m, "A") -- A now dead, B wins -> Ended

	-- Eliminating an already-dead player changes nothing.
	local rDead = RoundState.eliminate(m, "A")
	expect(rDead.ended == false and rDead.winner == nil, "eliminate on dead player is a no-op")
	expect(RoundState.getWinner(m) == "B", "winner unchanged")
	print("eliminate: no-op cases OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: FAIL — `attempt to call a nil value (field 'eliminate')`.

- [ ] **Step 3: Write minimal implementation**

In `src/shared/RoundState.luau`, add this local helper and function immediately **before** the final `return RoundState`:

```lua
-- After `alive` shrinks during an Active round, end it if fewer than
-- minToContinue remain. Winner = the sole survivor, or nil if none remain.
-- Returns { ended, winner }.
local function maybeEnd(model)
	if model.phase ~= "Active" then
		return { ended = false, winner = nil }
	end
	if count(model.alive) < model.minToContinue then
		model.phase = "Ended"
		local sole = nil
		for player in pairs(model.alive) do
			sole = player
			break
		end
		model.winner = sole
		return { ended = true, winner = sole }
	end
	return { ended = false, winner = nil }
end

-- Remove a player from the alive set due to death. No-op unless the round is
-- Active and the player is currently alive. May auto-end the round.
function RoundState.eliminate(model, player)
	if model.phase ~= "Active" or not model.alive[player] then
		return { ended = false, winner = nil }
	end
	model.alive[player] = nil
	return maybeEnd(model)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: PASS — includes `eliminate: auto-end + winner OK` and `eliminate: no-op cases OK`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/RoundState.luau tests/round_state.spec.luau
git commit -m "feat: RoundState.eliminate with auto-end and winner"
```

---

### Task 5: removePlayer — disconnect win and drop-to-zero

**Files:**
- Modify: `src/shared/RoundState.luau`
- Modify: `tests/round_state.spec.luau`

- [ ] **Step 1: Write the failing test**

In `tests/round_state.spec.luau`, insert this block immediately **before** the final `print("ALL ROUNDSTATE TESTS PASSED")` line:

```lua
-- removePlayer: a disconnect that drops alive to 1 declares the remaining winner.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.beginRound(m)

	local r = RoundState.removePlayer(m, "A")
	expect(r.ended == true, "disconnect to 1 alive ends the round")
	expect(r.winner == "B", "B wins when A disconnects")
	expect(RoundState.getPhase(m) == "Ended", "phase Ended after disconnect win")
	expect(m.present["A"] == nil, "A removed from present")
	print("removePlayer: disconnect win OK")
end

-- removePlayer: dropping the alive set to 0 ends with no winner (round aborted).
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.beginRound(m)

	-- minToContinue is 2, so removing ONE alive player already ends the round
	-- (1 < 2) with the other as winner. To reach 0 we construct the boundary
	-- case directly: a model whose continue threshold is 1, so it only ends at 0.
	local m0 = RoundState.new(2, 1)
	RoundState.addPlayer(m0, "A")
	RoundState.addPlayer(m0, "B")
	RoundState.beginRound(m0)

	local r1 = RoundState.removePlayer(m0, "A")
	expect(r1.ended == false, "with continue=1, 1 alive keeps going")
	local r2 = RoundState.removePlayer(m0, "B")
	expect(r2.ended == true, "0 alive ends the round")
	expect(r2.winner == nil, "0 alive -> no winner")
	expect(RoundState.getPhase(m0) == "Ended", "phase Ended on abort")
	expect(RoundState.getWinner(m0) == nil, "winner stays nil on abort")
	print("removePlayer: drop-to-zero abort OK")
end

-- removePlayer: removing a non-present player is a no-op; removing a present but
-- non-alive (spectating) player does not affect the round outcome.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.beginRound(m)

	local rGhost = RoundState.removePlayer(m, "ghost")
	expect(rGhost.ended == false and rGhost.winner == nil, "removing unknown player is a no-op")

	RoundState.addPlayer(m, "C") -- joins mid-round: present, not alive
	local rSpec = RoundState.removePlayer(m, "C")
	expect(rSpec.ended == false and rSpec.winner == nil, "removing a spectator does not end the round")
	expect(RoundState.getPhase(m) == "Active", "round still Active")
	print("removePlayer: no-op cases OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: FAIL — `attempt to call a nil value (field 'removePlayer')`.

- [ ] **Step 3: Write minimal implementation**

In `src/shared/RoundState.luau`, add this function immediately **before** the final `return RoundState`:

```lua
-- Handle a disconnect: drop the player from `present` and (if alive) from
-- `alive`. If removing an alive player during an Active round pushes the
-- survivor count below threshold, auto-end. No-op if the player is not present.
function RoundState.removePlayer(model, player)
	if not model.present[player] then
		return { ended = false, winner = nil }
	end
	model.present[player] = nil
	local wasAlive = model.alive[player] == true
	model.alive[player] = nil
	if wasAlive then
		return maybeEnd(model)
	end
	return { ended = false, winner = nil }
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: PASS — includes `removePlayer: disconnect win OK`, `removePlayer: drop-to-zero abort OK`, `removePlayer: no-op cases OK`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/RoundState.luau tests/round_state.spec.luau
git commit -m "feat: RoundState.removePlayer (disconnect win + abort)"
```

---

### Task 6: reset, terminal-Ended no-ops, and the full-cycle invariant

**Files:**
- Modify: `src/shared/RoundState.luau`
- Modify: `tests/round_state.spec.luau`

- [ ] **Step 1: Write the failing test**

In `tests/round_state.spec.luau`, insert this block immediately **before** the final `print("ALL ROUNDSTATE TESTS PASSED")` line:

```lua
-- Post-Ended: eliminate / removePlayer are no-ops for phase and winner.
do
	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	RoundState.addPlayer(m, "C")
	RoundState.beginRound(m)
	RoundState.eliminate(m, "A") -- B, C alive
	RoundState.eliminate(m, "B") -- C wins -> Ended

	local rElim = RoundState.eliminate(m, "C")
	expect(rElim.ended == false and rElim.winner == nil, "eliminate after Ended is a no-op")
	expect(RoundState.getPhase(m) == "Ended", "phase stays Ended")
	expect(RoundState.getWinner(m) == "C", "winner stays C")

	-- removePlayer after Ended may still drop from present, but never re-ends.
	local rRem = RoundState.removePlayer(m, "C")
	expect(rRem.ended == false and rRem.winner == nil, "removePlayer after Ended does not re-end")
	expect(RoundState.getWinner(m) == "C", "winner still C")
	expect(m.present["C"] == nil, "C still dropped from present")
	print("terminal Ended: no-op OK")
end

-- reset + full cycle: Ended -> Lobby keeps still-connected players; alive subset
-- of present holds throughout.
do
	local function aliveSubsetOfPresent(m)
		for p in pairs(m.alive) do
			if not m.present[p] then
				return false
			end
		end
		return true
	end

	local m = RoundState.new(2, 2)
	RoundState.addPlayer(m, "A")
	RoundState.addPlayer(m, "B")
	expect(aliveSubsetOfPresent(m), "invariant holds in Lobby")

	RoundState.beginRound(m)
	expect(aliveSubsetOfPresent(m), "invariant holds in Active")

	RoundState.eliminate(m, "A") -- B wins -> Ended
	expect(aliveSubsetOfPresent(m), "invariant holds in Ended")

	RoundState.reset(m)
	expect(RoundState.getPhase(m) == "Lobby", "reset returns to Lobby")
	expect(RoundState.getWinner(m) == nil, "reset clears winner")
	expect(RoundState.aliveCount(m) == 0, "reset clears alive")
	expect(m.present["A"] and m.present["B"], "still-connected players carry to next round")
	expect(RoundState.canStart(m), "can start the next round with carried players")
	expect(aliveSubsetOfPresent(m), "invariant holds after reset")
	print("reset: full-cycle + invariant OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: FAIL — `attempt to call a nil value (field 'reset')`.

- [ ] **Step 3: Write minimal implementation**

In `src/shared/RoundState.luau`, add this function immediately **before** the final `return RoundState`:

```lua
-- Ended -> Lobby for the next round. Clears `alive` and `winner`; keeps
-- `present` so still-connected players carry over.
function RoundState.reset(model)
	model.phase = "Lobby"
	model.alive = {}
	model.winner = nil
end
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau
```
Expected: PASS — includes `terminal Ended: no-op OK` and `reset: full-cycle + invariant OK`, ending with `ALL ROUNDSTATE TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/RoundState.luau tests/round_state.spec.luau
git commit -m "feat: RoundState.reset + terminal-Ended no-ops + invariant test"
```

---

### Task 7: Changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Record the addition**

In `CHANGELOG.md`, under `## [Unreleased]` → `### Added`, add as the first bullet:

```markdown
- `src/shared/RoundState.luau` — pure, Roblox-free round-lifecycle state
  machine (phase `Lobby`/`Active`/`Ended`, present/alive sets, winner). Auto-ends
  when fewer than `Config.MIN_PLAYERS_TO_CONTINUE` remain alive; last one standing
  wins, 0 alive aborts to lobby. Time-agnostic and event-driven like
  `ControlModel`; unit tested with lune (`tests/round_state.spec.luau`).
- `Config.MIN_PLAYERS_TO_START` / `Config.MIN_PLAYERS_TO_CONTINUE` (both default 2).
```

- [ ] **Step 2: Final full test run**

Run:
```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau && lune run tests/control_model.spec.luau
```
Expected: both suites print their `ALL ... TESTS PASSED` lines.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: record RoundState in changelog"
```

---

## Self-Review

**Spec coverage:**
- Module boundary / pure / time-agnostic → Task 2 module header + structure. ✓
- State shape (phase/present/alive/winner/thresholds) → Task 2 `new`. ✓
- Config thresholds → Task 1. ✓
- State machine `Lobby→Active→Ended→reset` → Tasks 2,3,4,6. ✓
- API: `new/addPlayer/canStart/getPhase/getWinner/aliveCount/isAlive` (T2), `beginRound` (T3), `eliminate` (T4), `removePlayer` (T5), `reset` (T6). ✓ All API rows covered.
- Win/edge rules: auto-end at threshold (T4), drop-to-0 winner nil (T5), terminal Ended no-ops (T6), mid-round join not alive (T5 spectator), `alive ⊆ present` invariant (T6). ✓
- Simultaneous-death ordering is caller responsibility — no module behavior to test; noted in spec only. ✓
- Testing list items 1–10 from spec all map to Tasks 2–6 test blocks. ✓
- Files touched: `RoundState.luau`, `round_state.spec.luau`, `Config.luau`, `CHANGELOG.md` — all have tasks. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. ✓

**Type consistency:** `count` helper defined in T2, reused by `canStart` (T2), `aliveCount` (T2), `maybeEnd` (T4). `maybeEnd` defined in T4 before its first use by `eliminate` (T4) and `removePlayer` (T5) — both add functions after T4, so ordering in the file is valid (helpers/functions all sit before the single `return RoundState`). Result table shape `{ ended, winner }` consistent across `eliminate`/`removePlayer`/`maybeEnd`. Method names match the spec API table exactly. ✓
