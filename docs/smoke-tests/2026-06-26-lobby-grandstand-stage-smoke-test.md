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

### 2026-06-26 — MCP structural verification (automated, Studio Play solo)
The connected "Body Swap Royale" Studio was put into Play and `workspace.LobbyStage` was inspected:
- **Built to spec:** 85 parts — 1 StageDeck + 1 StageLip + **45** CrowdOrbs (3 rows × 3 edges × 5) + **27** FestoonBulbs (3 strands × 9) + **10** BuntingFlag (WedgePart fallbacks) + 1 BackCrest. `totalDescendants` 91 = +4 capped PointLights + crest SurfaceGui/TextLabel.
- **Light cap honored:** exactly 4 real PointLights (`LOBBY_STAGE_FESTOON_LIT = 4`).
- **Non-colliding confirmed:** StageDeck spot-checked `CanCollide=false, CanQuery=false, CanTouch=false, CastShadow=false, Anchored=true`, at y=45.3 (DECK_LIFT above the platform top). Bunting fallbacks are WedgeParts (asset fields blank ⇒ code path exercised).
- **Hybrid assets:** all four `LOBBY_STAGE_*` asset fields left blank — slice runs fully on code fallbacks. Asset sourcing (MCP upload to owner inventory) deferred as an optional polish pass.
- **Not yet verified (needs the manual pass below):** the *aesthetic* read (magic-hour warm-vs-cool, crest facing, festoon droop framing) — `screen_capture` timed out this session, so sections 1, 3, 4, 5 still need a human/2-client run.

### Manual pass
- Date run / client(s) / outcome:
- Tuning notes (Config values changed):
