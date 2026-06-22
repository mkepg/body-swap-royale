# Disconnect-Absorb Survivor Rescue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop an eliminated-but-connected player's disconnect from stranding a still-alive survivor on the balcony (which prevents the round from ending), by repositioning the survivor back into the arena.

**Architecture:** Pure `ControlModel` stays unchanged (connection-only; its absorb still yields a valid bijection). The fix is alive-aware server glue: `RoundManager.removePlayer` detects when an *eliminated* leaver's disconnect-absorb hands a parked body to an *alive* survivor and repositions that body to its avatar-owner's arena spawn slot, re-asserting ownership (reposition-then-re-own, mirroring `beginRound`).

**Tech Stack:** Luau, Rojo project. Pure modules are lune-tested; server glue (Roblox APIs) is verified by a manual multi-client Studio smoke test.

**Spec:** `docs/superpowers/specs/2026-06-22-disconnect-strand-survivor-design.md`

> **Testing note:** `ControlManager`/`BodyManager`/`RoundManager` use Roblox APIs (`game:GetService`, `workspace`, instances) and CANNOT be run by lune. After each code task, verifying "all lune specs still pass" is a *regression* check on the unchanged pure modules (and confirms shared modules still parse); it does not exercise the changed server files. The real behavioral verification is the Task 4 smoke test.

---

## File Structure

- **Modify** `src/server/ControlManager.luau` — `removePlayer` returns its absorb decision; add `regrantControl(player)`.
- **Modify** `src/server/BodyManager.luau` — add `sendToArena(body)` (arena mirror of `sendToLobby`).
- **Modify** `src/server/RoundManager.luau` — capture `leaverWasAlive`, consume the decision, apply the rescue.
- **Create** `docs/smoke-tests/2026-06-22-disconnect-strand-smoke-test.md` — 3-client runtime check.
- **Unchanged:** `src/shared/ControlModel.luau` (and all `tests/*.spec.luau`).

---

## Task 1: `ControlManager` — return the absorb decision + add `regrantControl`

**Files:**
- Modify: `src/server/ControlManager.luau` (`removePlayer`; new `regrantControl`)

- [ ] **Step 1: Make `removePlayer` return its decision**

In `src/server/ControlManager.luau`, the current function is:

```lua
-- Player left: apply the model's absorb decision, then destroy their avatar body.
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

Add `return decision` as the final line of the function body (immediately after
`ControlManager.broadcastSoulMap()`):

```lua
	soulColor[player] = nil
	ControlManager.broadcastSoulMap()
	return decision -- absorb decision {destroyOwn, reassign} -- consumed by RoundManager's rescue
end
```

- [ ] **Step 2: Add `regrantControl`**

Immediately AFTER the `ControlManager.removePlayer` function (and before
`ControlManager.resetControl`), add:

```lua
-- Re-assert a player's network ownership of the body they CURRENTLY control, with a
-- clean (non-swap) retarget. Used after a server-side reposition so the teleport
-- replicates onto the now client-owned body (same reposition-then-re-own ordering as
-- beginRound's resetBody -> resetControl). No-op if the player controls no body.
function ControlManager.regrantControl(player)
	local body = ControlModel.controlledBody(model, player)
	if body then
		applyOwnership(player, body, false)
	end
end
```

- [ ] **Step 3: Verify the edits landed and specs still pass**

Run: `grep -n "return decision\|function ControlManager.regrantControl" src/server/ControlManager.luau`
Expected: both lines present.

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "${f%.luau}" 2>&1 | tail -1; done`
Expected: every line is an `ALL ... TESTS PASSED` (regression: pure modules unchanged; confirms shared modules still parse).

- [ ] **Step 4: Commit**

```bash
git add src/server/ControlManager.luau
git commit -m "feat(disconnect): ControlManager returns absorb decision + regrantControl

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `BodyManager` — add `sendToArena(body)`

**Files:**
- Modify: `src/server/BodyManager.luau` (new `sendToArena`, beside `sendToLobby`)

- [ ] **Step 1: Add `sendToArena`**

In `src/server/BodyManager.luau`, the existing `sendToLobby` is:

```lua
-- Elimination: send the body the player was controlling (now out of the round) to
-- their balcony slot, still under their control, so they watch the rest of the
-- round from the lobby instead of leaving a corpse in the arena. Teleporting it
-- up also catches the fall (no need to anchor against FallenPartsDestroyHeight).
function BodyManager.sendToLobby(player, body)
	placeOnLobbySlot(player, body)
end
```

Immediately AFTER it, add:

```lua
-- Reposition `body` back onto its avatar-owner's ARENA spawn slot (unanchored +
-- zeroed) -- the arena mirror of sendToLobby. Used to rescue a still-alive survivor
-- whom a disconnect-absorb moved onto a body parked on the balcony (see the
-- disconnect-strand spec). Resolves the owner from the body's OwnerUserId attribute.
-- No-op if the owner or their arena slot can't be resolved.
function BodyManager.sendToArena(body)
	if not body then
		return
	end
	local userId = body:GetAttribute("OwnerUserId")
	local owner = userId and Players:GetPlayerByUserId(userId)
	local cf = owner and BodyManager.arenaSlotByOwner[owner]
	if not cf then
		return
	end
	pivotBodyTo(body, cf)
end
```

(`Players` is already required at the top of the file; `pivotBodyTo` and
`BodyManager.arenaSlotByOwner` are both already defined above this point. The body's
`OwnerUserId` attribute is set in `createBody`.)

- [ ] **Step 2: Verify the edit landed and specs still pass**

Run: `grep -n "function BodyManager.sendToArena" src/server/BodyManager.luau`
Expected: present.

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "${f%.luau}" 2>&1 | tail -1; done`
Expected: every line is an `ALL ... TESTS PASSED`.

- [ ] **Step 3: Commit**

```bash
git add src/server/BodyManager.luau
git commit -m "feat(disconnect): BodyManager.sendToArena repositions a body to its arena slot

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `RoundManager` — apply the alive-aware rescue on disconnect

**Files:**
- Modify: `src/server/RoundManager.luau` (`RoundManager.removePlayer`)

- [ ] **Step 1: Rewrite `RoundManager.removePlayer` to capture aliveness and rescue**

In `src/server/RoundManager.luau`, the current function is:

```lua
function RoundManager.removePlayer(player)
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	ControlManager.removePlayer(player)    -- absorb + destroy the leaver's own body
	GraceModel.clear(grace, player)
	swapPos[player] = nil
	-- If the disconnect ended the round, the Active loop observes phase Ended and
	-- runs endRound; no special handling needed here.
end
```

Replace it with:

```lua
function RoundManager.removePlayer(player)
	-- Capture aliveness BEFORE RoundState drops the player. The rescue below applies
	-- only when an ELIMINATED leaver's disconnect-absorb would hand the parked body it
	-- was controlling to a still-ALIVE survivor -- which would otherwise strand that
	-- survivor on the balcony and stop the round from ever ending (disconnect-strand spec).
	local leaverWasAlive = RoundState.isAlive(model, player)
	RoundState.removePlayer(model, player) -- lifecycle (may auto-end the round)
	local decision = ControlManager.removePlayer(player) -- absorb + destroy the leaver's own body
	-- Alive-aware rescue: reposition the survivor's newly-absorbed body back into the
	-- arena and re-assert their ownership (reposition-then-re-own, like beginRound, so
	-- the teleport replicates onto the client-owned body). Their camera follows the
	-- body's humanoid, so no extra remote is needed.
	if not leaverWasAlive and decision and decision.reassign
		and RoundState.isAlive(model, decision.reassign.player) then
		BodyManager.sendToArena(decision.reassign.body)
		ControlManager.regrantControl(decision.reassign.player)
	end
	GraceModel.clear(grace, player)
	swapPos[player] = nil
	-- If the disconnect ended the round, the Active loop observes phase Ended and
	-- runs endRound; no special handling needed here.
end
```

- [ ] **Step 2: Verify the edit landed and specs still pass**

Run: `grep -n "leaverWasAlive\|sendToArena\|regrantControl" src/server/RoundManager.luau`
Expected: `leaverWasAlive` (twice), one `sendToArena`, one `regrantControl`.

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "${f%.luau}" 2>&1 | tail -1; done`
Expected: every line is an `ALL ... TESTS PASSED`.

- [ ] **Step 3: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "fix(disconnect): rescue an alive survivor stranded by an eliminated leaver's absorb

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Smoke-test documentation

**Files:**
- Create: `docs/smoke-tests/2026-06-22-disconnect-strand-smoke-test.md`

- [ ] **Step 1: Create the smoke test**

Create `docs/smoke-tests/2026-06-22-disconnect-strand-smoke-test.md` with EXACTLY this content:

```markdown
# Disconnect-strand survivor rescue smoke test (manual, 3-client Studio)

Validates the fix for: an eliminated-but-connected player disconnecting used to strand a
still-alive survivor on the balcony (round never ended; the survivor became a "spectator"
of their old body after a swap). The fix is server glue (RoundManager/ControlManager/
BodyManager), which lune can't reach -- hence this manual test. Run a **3-player local
server** (Test -> Clients and Servers -> 3 -> Start).

**Setup** (Server view, command bar) -- keep the floor safe so deaths are deliberate:
`local C = require(game.ReplicatedStorage.Shared.Config); C.HAZARDS_ENABLED = false; C.VOID_Y = 0`

**Procedure & PASS criteria:**
1. **Start a round** with all 3 players. From the Server command bar, force swaps until an
   alive player is controlling another player's AVATAR body:
   `require(game.ServerScriptService.Server.RoundManager).forceSwap()` (repeat as needed).
   You can inspect the control map by checking which `Body_<UserId>` each client's camera
   follows.
2. **Eliminate one player B** by walking B's controlled body below `Config.VOID_Y` (or
   raise `VOID_Y` momentarily). B is sent to the balcony, still connected, still able to
   walk around up there. Two players remain alive.
3. **Identify the alive survivor Q** who is controlling B's avatar body (`Body_<B.UserId>`)
   down in the arena.
4. **Disconnect B** from the Server command bar:
   `game.Players:GetPlayers()` then `:Kick("test")` the eliminated player's client (match by
   `.UserId`/`.Name`).
5. **PASS:**
   - Survivor Q is **teleported back into the arena** (onto an arena spawn tile), NOT left
     standing on the balcony. Q remains controllable.
   - The round continues as a normal **2-alive** race and **ends with a declared winner**
     once one of them falls.
   - After any subsequent swap, neither survivor is stuck "spectating" a body from up on the
     balcony.

**FAIL (the old bug):** Q stays on the balcony, the round never ends with 2 players showing
alive while only 1 is in the arena, and a swap leaves a survivor looking down at their former
body.

Bodies are named `Body_<UserId>` under `workspace.Bodies`; players have no `Character`
(`CharacterAutoLoads = false`).
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-22-disconnect-strand-smoke-test.md
git commit -m "docs(disconnect): smoke test for the survivor-rescue fix

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "${f%.luau}" 2>&1 | tail -1; done` → every line `ALL ... TESTS PASSED` (pure modules, incl. unchanged `control_model.spec`, still green).
- [ ] `grep -rn "leaverWasAlive\|sendToArena\|regrantControl" src/server/` → the rescue wiring is present across `RoundManager` (trigger) and its helpers in `ControlManager`/`BodyManager`.
- [ ] Manual Studio run per `docs/smoke-tests/2026-06-22-disconnect-strand-smoke-test.md`: an eliminated player's disconnect no longer strands an alive survivor; the round resolves to a winner.
```
