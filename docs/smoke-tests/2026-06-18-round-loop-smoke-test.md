# Round-loop smoke test (manual, 2-client Studio)

Validates the RoundManager win/lose loop, which lune can't reach. Run a **2-player
local server** in Studio (Test → Clients and Servers → 2 → Start).

**Setup for a fast test** (Server view, command bar): temporarily shorten the clocks
so you don't wait out the full timers, e.g.
`local C = require(game.ReplicatedStorage.Shared.Config); C.CYCLE_SECONDS = 8; C.LOBBY_COUNTDOWN_SECONDS = 2; C.ROUND_END_SECONDS = 2`.
Raise `VOID_Y` (e.g. `C.VOID_Y = 0`) if you want bodies to die from a small drop.

**Procedure & PASS criteria:**
1. **Round start.** After both clients join, the lobby countdown text appears and
   counts down (`LOBBY_COUNTDOWN_SECONDS`), then a round begins: both clients
   control their own body, repositioned to spawn, and the countdown text clears.
2. **Force a swap (optional).** From the Server command bar:
   `require(game.ServerScriptService.Server.RoundManager).forceSwap()` — both
   clients hard-cut to a new body with the FOV punch.
3. **Void death.** Walk one client's body off the arena / below `Config.VOID_Y`
   (default −50). That player sees "You were eliminated" and their camera retargets
   to the surviving body (spectating, not a corpse). `workspace.Bodies` is unchanged
   (the dead body is parked/anchored, **not** destroyed).
4. **Winner.** Both clients see "Winner: <name>" for the surviving player.
5. **Round 2.** After `ROUND_END_SECONDS`, the loop returns to Lobby and a second
   round begins — all bodies repositioned to spawn and everyone back on their own
   body (proves revive-free reset + `resetControl`).
6. **Disconnect win.** In a fresh round, kick one player from the Server command bar:
   `game.Players:GetPlayers()[1]:Kick("test")`. The round ends with the remaining
   player as winner; their controlled body is never yanked (absorb rule still holds).

Bodies are named `Body_<UserId>` under `workspace.Bodies`; players have no
`Character` (`CharacterAutoLoads = false`).
