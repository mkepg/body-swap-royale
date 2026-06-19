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
7. **Post-swap grace window.** Use the one-shot script below — it's far more reliable
   than hand-timing the 1.5s window. Hand-timing fails two ways: walking a body into
   the void is *horizontal* movement that early-exits grace, and you can't manually
   raise `VOID_Y` within 1.5s of a swap. The script sidesteps both by raising the kill
   floor onto a **stationary** post-swap body (zero horizontal travel) and using a long
   test window. Verified PASS 2026-06-19 (`protected ~3.15s … then eliminated`).

> **Test floor (only if needed):** if bodies fall on their own in your test session,
> drop in a temporary floor so they have ground to rest on:
> `local f = Instance.new("Part"); f.Size = Vector3.new(400,1,400); f.Position = Vector3.new(0,0,0); f.Anchored = true; f.Parent = workspace`

Paste into the **server** command bar with a round Active and clients idle:

```lua
-- ===== ONE-SHOT POST-SWAP GRACE SMOKE TEST =====
local Players = game:GetService("Players")
local Config  = require(game.ReplicatedStorage.Shared.Config)
local RM      = require(game.ServerScriptService.Server.RoundManager)
local CM      = require(game.ServerScriptService.Server.ControlManager)
local TEST_GRACE = 3

local orig = { VOID_Y = Config.VOID_Y, GRACE = Config.GRACE_SECONDS, CYCLE = Config.CYCLE_SECONDS }
local function restore()
    Config.VOID_Y, Config.GRACE_SECONDS, Config.CYCLE_SECONDS = orig.VOID_Y, orig.GRACE, orig.CYCLE
end
local function roots()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local b = CM.getControlledBody(p); local r = b and b:FindFirstChild("HumanoidRootPart")
        if r then t[p] = r end
    end
    return t
end
local function anyAnchored()
    for _, r in pairs(roots()) do if r.Anchored then return true end end
    return false
end

local r0 = roots(); local n = 0; for _ in pairs(r0) do n += 1 end
if n < 2 then warn("[GRACE TEST] Need 2 players with bodies. Aborting."); return end
if anyAnchored() then warn("[GRACE TEST] A body is already eliminated — start a FRESH active round and retry."); return end

Config.CYCLE_SECONDS = 120
Config.GRACE_SECONDS = TEST_GRACE
Config.VOID_Y = orig.VOID_Y

local before = {}; for p in pairs(r0) do before[p] = CM.getControlledBody(p) end
RM.forceSwap()
local swapped = false
for p in pairs(r0) do if CM.getControlledBody(p) ~= before[p] then swapped = true end end
if not swapped then warn("[GRACE TEST] No swap occurred — round isn't Active. Retry in a running round."); restore(); return end

Config.VOID_Y = 50
local t0 = os.clock()
print(("[GRACE TEST] Swapped + bodies in-void. Watching a %ds grace window..."):format(TEST_GRACE))

task.wait(1.0)
if anyAnchored() then warn("[GRACE TEST] FAIL: eliminated within 1s, window is "..TEST_GRACE.."s — grace NOT protecting."); restore(); return end
print("[GRACE TEST] OK so far: alive 1.0s into the window (protected).")

while os.clock() < t0 + TEST_GRACE + 1.5 do
    if anyAnchored() then
        print(("[GRACE TEST] PASS: protected ~%.2fs (≈ the %ds window), then eliminated. Grace gate works."):format(os.clock() - t0, TEST_GRACE))
        restore(); return
    end
    task.wait(0.1)
end
warn(("[GRACE TEST] FAIL: never eliminated within %.1fs of the swap — window not expiring."):format(TEST_GRACE + 1.5))
restore()
```

PASS = `protected ~3s (≈ the window), then eliminated`; the script auto-restores Config.

Bodies are named `Body_<UserId>` under `workspace.Bodies`; players have no
`Character` (`CharacterAutoLoads = false`).
