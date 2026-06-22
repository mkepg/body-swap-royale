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
