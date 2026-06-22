# Lobby Staging Area — 2-Client Studio Smoke Test (2026-06-21)

Runtime checks the lune tests can't cover: balcony geometry, body relocation
across the round lifecycle, and the victory cam. Pairs with the unit test
`tests/spawn_layout.spec.luau` (slot math) and the spec
`docs/specs/2026-06-21-lobby-staging-area-design.md`.

## Setup
- Roblox Studio, **2 players** (Test > Clients and Servers > 2 players, Start).
- Set `Config.HAZARDS_ENABLED = false` so the arena floor stays solid while you
  observe the loop (no body falls mid-test). Restore to `true` afterward.

## Procedure

1. **Join → balcony.** Both clients spawn on the **elevated balcony** (not in the
   arena). Each can walk their body around the platform; looking forward/down they
   see the arena below. Walking into any edge is blocked — the perimeter walls and
   the (semi-transparent) front railing stop the body; nobody falls into the void.
   **Also try jumping repeatedly against each wall (especially the front railing):**
   the body must not clear it (walls are taller than a jump).

2. **Round start → arena.** Once both are present, the lobby countdown runs and at
   round start both bodies **teleport down into the arena** spawn row; each client's
   camera retargets to its own body in the arena. (With hazards enabled, tiles begin
   their cycle here.)

3. **Mid-round elimination → balcony.** This needs **3+ players** (so the round
   continues after one dies). With a round Active, drop one body into the void
   (toggle `Config.HAZARDS_ENABLED = true` and let a tile vanish, or nudge a body off
   an edge). The eliminated player's body **teleports up to the balcony** and they
   **keep control of it** — they walk around the lobby and watch the round continue
   below. No parked corpse is left in the arena; the eliminated body is never swapped
   or void-killed again.

4. **Round end → victory cam.** Force a finish: drop bodies into the void (or call
   `require(...ServerScriptService.Server.RoundManager).forceSwap()` to churn, then
   push bodies off) until one player remains. The Results banner shows ("Victory" /
   "Defeated", "Next round in N"). During that window, **all** clients' cameras frame
   the **winner's body** standing in the arena.

5. **Lobby reset → balcony.** After the countdown, **all** bodies teleport **up to
   the balcony**, each client's camera pulls back onto its **own** body, and the
   Lobby banner shows over the gathered balcony. Everyone can walk around again,
   fenced in by the railings.

6. **Mid-round join.** Restart with 1 client; once a round is Active, start a 2nd
   client. The joiner appears on the **balcony** (not loose in the live arena) and is
   folded into the arena at the **next** round start.

## Pass criteria
- [ ] Bodies spawn on the balcony on join (step 1), cannot walk off, and cannot JUMP over the railings.
- [ ] Bodies move balcony → arena at round start (step 2).
- [ ] An eliminated player is sent to the balcony and keeps control of their body (step 3).
- [ ] Victory cam frames the winner for ALL clients during Ended (step 4).
- [ ] Bodies move arena → balcony at the Lobby reset, on their own bodies (step 5).
- [ ] A mid-round joiner waits on the balcony, not in the arena (step 6).
