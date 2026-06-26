# Lobby Grandstand Stage — Smoke Test (2026-06-26)

**Slice:** World Slice 2 (Lobby Hub Redress). **Spec:** `docs/specs/2026-06-26-lobby-grandstand-stage-design.md`.
**Nature:** 100% client-cosmetic. Single-client is sufficient for look & feel; a 2-client pass is only needed for the cheer reactivity (step 3).

Keep `Config.HAZARDS_ENABLED = false` so the floor stays safe while observing the lobby.

## 1. Look & feel (single client)
- Join and stand on the balcony. Confirm the redress is present:
  - [ ] **Stage deck** skinning the platform with a lit pit-facing **lip**.
  - [ ] **U-wrap soul crowd**: raked orb tiers wrap the back and both wings; the **front (pit) side is open** (no orbs blocking the downward view).
  - [ ] **Warm-gold festoon lights** strung overhead (back + wings) with a visible droop.
  - [ ] **Bunting** pennants along the back, in player-palette colors.
  - [ ] **Back crest** ("★ SOUL FESTIVAL ★") crowning the back tier.
  - [ ] The **front marquee** (Slice 1b) is still present and unchanged over the pit.
- [ ] **Magic-Hour read:** the warm lights/bunting sit against the unchanged **cool dusk + teal/violet aurora** sky (warm vs cool contrast).

## 2. Load-bearing invariant (single client)
- [ ] Walk the controlled body into the railing and into every tier/deck/light — it **cannot** walk through onto a tier or off the edge.
- [ ] **Jump** at the railing and under the festoon — no added part is a foothold; the body cannot get over the railing into the void. (All LobbyStage parts are non-colliding.)

## 3. Cheer reactivity (2 clients, or forced)
- [ ] Trigger an elimination (drop a body into the void with 3+ players, or `RoundManager.forceSwap()` then eliminate). The **grandstand orbs pop/cheer** (alongside the distant WorldShell crowd).
- [ ] On a winner being named (round end), the grandstand orbs cheer again (double pop).
- [ ] A disconnect-decided round (no winner) does **not** trigger a winner cheer.

## 4. Victory cam unobstructed (2 clients)
- [ ] During the Ended window, the camera frames the winner in the pit with **no grandstand geometry** intruding into the shot.

## 5. Performance
- [ ] On the lobby with the new lights, FPS is stable (real PointLights are capped to `Config.LOBBY_STAGE_FESTOON_LIT`). Note any drop on a mid-tier/mobile profile.

## Result
- Date run / client(s) / outcome:
- Tuning notes (Config values changed):
