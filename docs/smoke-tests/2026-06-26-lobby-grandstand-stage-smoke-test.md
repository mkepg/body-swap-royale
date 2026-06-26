# Lobby Grandstand Stage — Smoke Test (2026-06-26)

**Slice:** World Slice 2 (Lobby Hub Redress). **Spec:** `docs/superpowers/specs/2026-06-26-lobby-grandstand-stage-design.md`.
**Nature:** 100% client-cosmetic. Single-client is sufficient for look & feel; a 2-client pass is only needed for the cheer reactivity (step 3).

Keep `Config.HAZARDS_ENABLED = false` so the floor stays safe while observing the lobby.

> **Reassessment (2026-06-26):** the orb-vocabulary cleanup is folded in — lobby crowd is now two small clusters (not a U-wrap), festoon is string-lights on a wire, and the hex floors use a colored edge trim (not torches/orb rings). See `docs/superpowers/specs/2026-06-26-orb-vocabulary-reassessment-design.md`. Checks below reflect that.

## 1. Look & feel (single client)
- Join and stand on the balcony. Confirm the redress is present:
  - [ ] **Stage deck** skinning the platform with a lit pit-facing **lip**.
  - [ ] **Two small soul clusters** at the pit-view edges (front ±X); **no crowd behind/around** blocking the view. The bulk of the crowd is the distant WorldShell ring out around the pit.
  - [ ] **Festoon string-lights**: small warm bulbs on a visible **thin dark wire** with a droop — they read as *lights*, not floating soul-orbs.
  - [ ] **Bunting** pennants along the back, in player-palette colors.
  - [ ] **Back crest** ("★ SOUL FESTIVAL ★") crowning the back.
  - [ ] The **front marquee** (Slice 1b) is still present and unchanged over the pit.
- [ ] **Magic-Hour read:** the warm lights/bunting sit against the unchanged **cool dusk + teal/violet aurora** sky (warm vs cool contrast).

## 1b. Hex floor edge trim (single client, looking into the pit)
- [ ] Each hex floor wears a **floor-colored glowing rim** hugging its edge (a continuous-looking band, not scattered orbs). **No torches and no orb rings** remain.
- [ ] The **top floors are lit** (you can see the erosion); deeper floors glow via the trim color only.
- [ ] With `HAZARDS_ENABLED = true`, as tiles erode the holes are **empty** — the trim sits outside the tiles, so a hole never reveals a solid glowing plate that could read as walkable.

## 2. Load-bearing invariant (single client)
- [ ] Walk the controlled body into the railing and into every cluster/deck/light — it **cannot** walk through onto anything or off the edge.
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

### 2026-06-26 — reassessment MCP structural verification (automated, Studio Play solo)
After the orb-vocabulary reassessment, re-inspected in Play:
- **`workspace.ArenaDressing`:** 113 children = **112 FloorTrim** (16 segments × 7 floors) + 1 Banner; `totalDescendants` 134 = +**12 PointLights** (4 × top-3 lit floors) + 9 banner GUI. A trim segment spot-checked `CanCollide=false`/`Anchored`/`Neon`, floor-colored (top yellow, floor-2 green), oriented tangent, at radius 40 (= footprint-half + margin, outside the tiles). **No `TorchPost`/`TorchHead`/`NearOrb` remain.**
- **`workspace.LobbyStage`:** exactly **12 CrowdOrb** (two 6-orb clusters), plus **FestoonWire** segments and smaller **FestoonBulb**s; no back-tier crowd.
- Lune `tests/world_layout.spec` green (`cluster` covers the new helper; `tierRows` removed).
- **Still needs the manual pass:** the *aesthetic* read (floors as clean colored rims, festoon reading as lights, clusters only at the edges) and the erosion-vs-trim check (1b) — `screen_capture` timed out, so a human/2-client run is still required.

### Manual pass
- Date run / client(s) / outcome:
- Tuning notes (Config values changed):
