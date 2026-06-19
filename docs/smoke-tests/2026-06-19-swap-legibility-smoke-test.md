# Smoke Test — Swap Legibility (2026-06-19)

Runtime behavior lune can't cover: the telegraph HUD, truthful preview, Soul
halos, the grace shimmer, and the plan/commit correctness under roster churn.
Run in Studio with **2 players** (Test → Clients and Server, 2 players).

Prereqs: builds via Rojo; `Config.SWAP_WARNING_SOUND_ID` may be `""` (silent is
OK). To reach RoundManager from the **server** command bar:

```lua
local RM = require(game.ServerScriptService.Server.RoundManager)
RM.forceSwap() -- force an immediate (no-preview) swap; safe to call repeatedly
```

Let the 30s cycle run normally to exercise the telegraph/preview; use
`forceSwap()` only where a step calls for it.

## 1. Live timer
- [ ] During Active, a countdown number is visible top-center on both clients.
- [ ] It decreases ~1/sec and reaches the low single digits right before a swap.
- [ ] It is blank in Lobby / Ended.

## 2. Telegraph (T-3s)
- [ ] In the last ~3s before a swap, a big 3 / 2 / 1 appears centered and an
      orange→red flash ramps up.
- [ ] If a sound id is set, the rumble plays once as the telegraph begins.
- [ ] The flash and big countdown clear at the swap.

## 3. Truthful preview
- [ ] During the telegraph, exactly one other body is outlined (the one you're
      about to inherit).
- [ ] After the swap, the body you now control IS the body that was outlined.
- [ ] The outline clears at the swap.

## 4. Soul halos + self-emphasis
- [ ] Each body has a colored halo; the two players' colors differ.
- [ ] Your OWN controlled body's halo is visibly emphasized (larger + outline
      ring) on your screen.
- [ ] After a swap, halos follow control: your color moves to your new body, and
      the emphasis stays on the body you now drive.
- [ ] At round start (reset), each halo is back on its owner's body.

## 5. Grace shimmer
- [ ] Right after a swap, a brief blue shimmer pulses on the body you inherited.
- [ ] It fades early once you start moving (after the ~0.5s floor); if you stay
      still it lasts ~1.5s.

## 6. Roster-changed-during-preview — DISCONNECT (correctness)
- [ ] With 3+ test players: during the 3s preview window, have one client
      disconnect (close that client window).
- [ ] Confirm: no Lua errors in Output; the surviving players still swap to
      valid, distinct bodies; control stays a clean bijection (no body with two
      controllers, nobody stuck uncontrolled).

## 7. Roster-changed-during-preview — DEATH (the bug fixed in code review)
This is the case `planStillValid` alone could not see (a hazard death updates the
alive set + parks the body but not the control map); `RoundManager.planIsCurrent`
adds the aliveness check. Verify it holds at runtime:
- [ ] With 3 alive players, during the 3s preview window kill one player — walk
      their body through a `gone` tile / off the edge so the void monitor
      eliminates them just as the telegraph is showing.
- [ ] Confirm: no Lua errors (esp. no `SetNetworkOwner`-on-anchored-part errors);
      the two survivors swap to **live** bodies (neither is stranded, frozen, on
      the dead/parked body); the dead player is spectating, not still "holding" a
      live body.
- [ ] 2-player variant: with 2 alive, kill one during preview → the round ends
      cleanly with the survivor crowned (no swap committed onto a dead body).

## 8. Whole loop still healthy
- [ ] Lobby → countdown → Active (swaps every ~30s) → elimination → winner →
      reset to Lobby all still work, with the new HUD/preview/halos present and
      no regressions to camera cut, control, or animation.

## Result
- [ ] All sections pass. Studio version: __________   Date run: __________
- Notes:
