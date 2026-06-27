# Lobby Grandstand Stage — Smoke Test (2026-06-26)

**Slice:** World Slice 2 (Lobby Hub Redress). **Spec:** `docs/specs/2026-06-26-lobby-grandstand-stage-design.md`.
**Nature:** 100% client-cosmetic. Single-client is sufficient for look & feel; a 2-client pass is only needed for the cheer reactivity (step 3).

Keep `Config.HAZARDS_ENABLED = false` so the floor stays safe while observing the lobby.

> **Reassessment (2026-06-26):** orb-vocabulary cleanup — hex floors use a colored edge trim (not torches/orb rings), all floors lit uniformly by Neon (no real PointLights). See `docs/specs/2026-06-26-orb-vocabulary-reassessment-design.md`.
> **Beyblade lobby (2026-06-27):** the lobby is **redesigned from a box into a beyblade** — a round walkable disc + invisible rim barrier, dressed as a spinning top (energy rings, stepped taper, tip, rim spectator-soul clusters). This SUPERSEDES the festival-grandstand lobby (no more box walls / festoon / bunting / back crest). See `docs/specs/2026-06-27-beyblade-lobby-design.md`. Sections 1 + 2 reflect the beyblade.

## 1. Beyblade lobby — look & feel (single client)
- Join and stand on the lobby. Confirm:
  - [ ] You stand on a **round disc** (no box walls); the lobby silhouette is a **beyblade** — a wide top, a **stepped taper** narrowing below, down to a **tip**.
  - [ ] **Glowing energy rings** hug the disc rim (cool ring at the edge, a warmer wider ring just below).
  - [ ] **Two cheer-reactive soul-orb clusters** ("spectator souls") sit at the rim (±X). The bulk of the crowd is the distant WorldShell ring around the pit.
  - [ ] The **front marquee** is still present over the front edge.
- [ ] The beyblade reads against the unchanged **cool dusk + aurora** sky; nothing blocks the downward pit view.

## 1b. Hex floor edge trim (single client, looking into the pit)
- [ ] Each hex floor wears a **floor-colored glowing rim** hugging its edge (a continuous-looking band, not scattered orbs). **No torches and no orb rings** remain.
- [ ] **All floors glow uniformly by Neon** (no real PointLights on any floor) — the top floors look the same style as the deep ones.
- [ ] With `HAZARDS_ENABLED = true`, as tiles erode the holes are **empty** — the trim sits outside the tiles, so a hole never reveals a solid glowing plate that could read as walkable.

## 2. Load-bearing invariant (single client) — CRITICAL for the beyblade
- [ ] Walk the controlled body to the **disc rim from several directions (front, back, both sides)** — it **cannot** walk off the edge into the void (the invisible barrier stops it).
- [ ] **Jump** at the rim from several angles and against the energy rings — no part is a foothold; the body **cannot get over** the barrier into the void. (Barrier is 12 high > jump 7.2; cosmetic parts are non-colliding.)
- [ ] Bodies **spawn on the disc** on join, **teleport down** into the arena at round start, and **return to the disc** at round end / on elimination — same as before.
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

### 2026-06-27 — beyblade lobby (static verification; live MCP deferred)
- Lune `tests/world_layout.spec` green (removed the now-unused `festoonStrand`/`buntingFlags`).
- **Static geometry review (the disc/barrier could not be live-inspected — Studio's Rojo sync was stale this session, still showing the old box lobby):**
  - Disc: `Cylinder`, `CanCollide=true`, `Anchored`, rotated so the axis is vertical; center Y = `LOBBY_ORIGIN.Y − thickness/2` ⇒ **top face exactly at `LOBBY_ORIGIN.Y = 45`**. Radius 30 holds the 4×4 grid (corner slot ≈ 21).
  - Barrier: 18 segments, `CanCollide=true`, `Transparency=1`, height 12 (> jump 7.2); chord 10.42 × slack 1.1 = 11.46 ⇒ **~1.04-stud overlap at every junction (gap-free)**; base flush with the disc top.
- **Still required (manual / after a Rojo re-sync):** live MCP/visual confirmation that `workspace.LobbyArea` builds the new `Disc`+`Barrier` (not the old box) and `workspace.LobbyStage` the beyblade parts, plus the **walk/jump-off** load-bearing checks in section 2 and the look in section 1.

### Manual pass
- Date run / client(s) / outcome:
- Tuning notes (Config values changed):
