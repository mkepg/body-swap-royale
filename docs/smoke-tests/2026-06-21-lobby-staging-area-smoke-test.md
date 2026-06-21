# Lobby Staging Area — 2-Client Studio Smoke Test (2026-06-21)

Runtime checks the lune tests can't cover: balcony geometry, body relocation
across the round lifecycle, and the victory cam. Pairs with the unit test
`tests/spawn_layout.spec.luau` (slot math) and the spec
`docs/superpowers/specs/2026-06-21-lobby-staging-area-design.md`.

## Setup
- Roblox Studio, **2 players** (Test > Clients and Servers > 2 players, Start).
- Set `Config.HAZARDS_ENABLED = false` so the arena floor stays solid while you
  observe the loop (no body falls mid-test). Restore to `true` afterward.

## Procedure

1. **Join → balcony.** Both clients spawn on the **elevated balcony** (not in the
   arena). Each can walk their body around the platform; looking forward/down they
   see the arena below. Walking into any edge is blocked — the perimeter walls and
   the (semi-transparent) front railing stop the body; nobody falls into the void.

2. **Round start → arena.** Once both are present, the lobby countdown runs and at
   round start both bodies **teleport down into the arena** spawn row; each client's
   camera retargets to its own body in the arena. (With hazards enabled, tiles begin
   their cycle here.)

3. **Round end → victory cam.** Force a finish: in the server command bar drop one
   body into the void, or call `require(...ServerScriptService.Server.RoundManager).forceSwap()`
   to churn, then push a body off. When one player remains, the Results banner shows
   ("Victory" / "Defeated", "Next round in N"). During that window, **both** clients'
   cameras frame the **winner's body** standing in the arena.

4. **Lobby reset → balcony.** After the countdown, **both** bodies teleport **up to
   the balcony**, each client's camera pulls back onto its **own** body, and the
   Lobby banner shows over the gathered balcony. Both can walk around again, fenced
   in by the railings.

5. **Mid-round join.** Restart with 1 client; once a round is Active, start the 2nd
   client. The joiner appears on the **balcony** (not loose in the live arena) and is
   folded into the arena at the **next** round start.

## Pass criteria
- [ ] Bodies spawn on the balcony on join (step 1) and cannot walk off (railings hold).
- [ ] Bodies move balcony → arena at round start (step 2).
- [ ] Victory cam frames the winner for ALL clients during Ended (step 3).
- [ ] Bodies move arena → balcony at the Lobby reset, on their own bodies (step 4).
- [ ] A mid-round joiner waits on the balcony, not in the arena (step 5).
