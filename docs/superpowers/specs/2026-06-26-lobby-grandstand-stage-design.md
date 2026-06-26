# Lobby Grandstand Stage (World Slice 2) — Design

**Date:** 2026-06-26
**Status:** Approved — ready for implementation plan
**Slice:** World Enrichment Roadmap **Slice 2 — Lobby Hub Redress (hybrid rebuild)**
**Related:** `docs/world-enrichment-roadmap.md` (cross-slice source of truth); builds on Slice 1 (`WorldShell`) + Slice 1b (`ArenaDressing`); reuses the lobby geometry from the lobby-staging-area design (`2026-06-21-lobby-staging-area-design.md`) and `LobbyArea.luau`. TDD §8 (performance / mobile budgets), GDD §6 (UX / between-round feel).

## Problem

The between-round staging space — the elevated balcony built in the lobby-staging-area slice — is functionally complete (waiting space, victory cam, eliminated-players-return) but visually bare: a soft-blue `Part` platform, three flat walls, and a glass railing, floating in the otherwise-enriched Soul Festival Sky. Slices 1/1b dressed the *sky* and the *arena*; the place players actually **stand and wait** is still stock parts. The wait reads as "standing on a blue slab," not "on deck at a show."

This slice redresses that balcony into a **festival grandstand stage**: the platform becomes the soul-festival main stage, the contestants are the act, and a soul-orb crowd is raked in tiers around them under warm festival lights — while the established cool dusk + aurora sky stays the backdrop. It is **100% client-cosmetic** and changes **no gameplay, geometry, collision, or HUD**.

## Locked creative decisions (from brainstorm, 2026-06-26)

- **Concept B — Festival Grandstand / Stage.** The platform *is* the festival stage; contestants are "the act"; the soul-orb crowd is raked in tiers around them. (Chosen over A · Broadcast Booth and C · Launch Deck.)
- **Mood 3 — "Magic-Hour Fair": warm lights, cool sky.** Warm-gold festoon string-lights, bunting, and stage uplight set **against** the established cool dusk + teal/violet aurora backdrop. Delivers celebratory warmth without abandoning the Soul Festival identity Slices 1/1b locked (the warm lights pop *because* the sky stays cool). Player-palette accents still glow on the crowd and stage edges. (Chosen over 1 · Warm Carnival and 2 · Cool Soul-Festival.)
- **Layout B — U-wrap crowd.** Crowd tiers wrap three sides (back + both wings), players "in the round," with the front (+Z, pit side) left fully open so the downward pit view and the Ended victory cam are never obstructed. (Chosen over A · grandstand-behind and C · side-wings-only.)
- **Build strategy — Hybrid now.** Source a thin set of assets via Studio MCP up front (festoon strand, bunting/pennant texture, soul-orb crowd mesh, stage-deck material), each wired into `Config` with a **code-only fallback**, per the roadmap's hybrid mandate. The slice must ship complete even if every asset falls back to code.

## Scope

**In scope**
- A new client module `LobbyStage.luau` that builds the grandstand dressing once, mirroring `ArenaDressing` (add-only, all parts non-colliding/non-querying).
- Five set elements: **stage deck**, **U-wrap crowd tiers** (soul-orbs), **festoon string-lights**, **bunting/pennants**, **back crest**.
- The U-wrap crowd reuses `WorldShell`'s decaying-cheer-impulse pattern and hooks the **same** `EliminationEvent` / `RoundStateChanged` remotes so the on-deck crowd cheers on eliminations and the winner.
- New **pure** `WorldLayout` helpers for the new placement math (`tierRows`, `festoonStrand`, `buntingFlags`), lune-tested.
- New `Config` block (`LOBBY_STAGE_*`) for all tunables + the hybrid asset fields (each with a code-only fallback).
- Hybrid assets sourced via Studio MCP at implementation time, wired to the new Config asset fields.
- Single-client Studio MCP visual verification + a new smoke-test doc.

**Explicitly out of scope (deferred / YAGNI)**
- Any change to `LobbyArea.luau` server geometry, collision, or the load-bearing fall protection.
- Any change to body placement / `SpawnLayout`, the round loop, `RoundManager`, the victory cam, HUD, banners' *messaging*, or `ArenaDescriptor`.
- Moving or restyling the existing Slice-1b front marquee (it stays as the pit-facing title card; a *new, distinct, smaller* back crest is added — no duplicate title).
- New reactive systems beyond reusing the existing cheer signals (no swap-reactive stage lights, no new remotes).
- The arena re-skin (Slice 3) and ambient-life systems / live jumbotron (Slice 4).

## Design decisions

- **Add-only client module; server geometry untouched.** `LobbyArea.luau` owns the load-bearing platform/walls/glass-railing and is **not modified**. `LobbyStage.luau` only *adds* cosmetic parts over/around it, exactly as `ArenaDressing` adds torches/orbs over the arena. Every part: `Anchored=true`, `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `CastShadow=false` (the shared `rigPart` idiom). **Load-bearing invariant:** because nothing the slice adds is collidable, no deck/tier/light can become a foothold to walk or jump over the railing — preserving the fall protection the lobby depends on. The smoke test re-verifies walking *and jumping* the railing.
- **Reads the lobby footprint from `Config`, not the arena.** `LobbyStage` consumes `LOBBY_ORIGIN`, `LOBBY_PAD_SIZE`, `LOBBY_WALL_HEIGHT` (and the new `LOBBY_STAGE_*` block). It does **not** require `ArenaDescriptor` — the lobby is shell/staging space, not an arena — so it adds no hex/arena coupling.
- **Pure geometry → `WorldLayout`.** New number-in/number-out helpers join `ring`/`footprintCorners`/`wispField`: `tierRows` (raked U-wrap riser slot positions), `festoonStrand` (catenary sag points between two posts), `buntingFlags` (flag positions along a segment). Client glue converts to `Vector3`. Lune-tested in the existing `tests/world_layout.spec.luau`.
- **Reuse the cheer signal, don't rebuild it.** `WorldShell` already drives a distant crowd's cheer from `EliminationEvent` + the `Ended`/`winnerName` `RoundStateChanged`. `LobbyStage` independently connects the same remotes and applies the same decaying-impulse Heartbeat pop to its grandstand orbs. The two crowds cheer together (additive payoff); no shared-signal refactor (YAGNI).
- **Hybrid via the `WORLD_SKYBOX` fallback idiom.** Each sourced asset is a `Config` field that, when blank/unset, makes the builder take the code path — identical to `WorldShell`'s `if sb.Up ~= "" then` skybox check. Asset sourcing is gated on Studio MCP availability (`list_roblox_studios` / `get_studio_state` / `set_active_studio`) at implementation time; if unavailable, the slice ships on fallbacks.
- **Marquee reconciliation.** The Slice-1b marquee (built in `ArenaDressing.buildBanner`, front edge, faces players over the pit) is **kept untouched** as the title card. The grandstand's back tier is crowned by a *distinct, smaller* festival crest so the backdrop silhouette reads without a second "BODY SWAP ROYALE" sign.
- **Mobile performance discipline (TDD §8).** Festoon bulbs are `Neon` parts (no light cost); real `PointLight`s are capped to a small `LOBBY_STAGE_FESTOON_LIT` count (mirrors `WORLD_TORCH_LIT_FLOORS`). Crowd animation is one shared Heartbeat over all orbs using a decaying scalar (no per-orb tweens), matching `WorldShell.buildCrowd`. All parts shadow-less and non-querying.

## Architecture

```
init.client.luau
   ├─ WorldShell.start()       (existing — Layer 1 sky/wisps/aurora/distant crowd)
   ├─ ArenaDressing.start()    (existing — Layer 2 torches/orbs/marquee)
   └─ LobbyStage.start()       (NEW — lobby grandstand dressing)

LobbyStage.start()  (client, 100% local cosmetic, add-only)
   reads Config.LOBBY_* + Config.LOBBY_STAGE_* + Config.SOUL_PALETTE
   uses pure WorldLayout.{tierRows, festoonStrand, buntingFlags, ring, paletteIndex}
   ├─ buildStageDeck(folder)       cosmetic slab over the platform + warm edge glow
   ├─ buildCrowdTiers(folder)      U-wrap raked risers of soul-orbs  ── cheer-reactive
   ├─ buildFestoon(folder)         catenary Neon bulb strands (+ capped PointLights)
   ├─ buildBunting(folder)         pennant-flag swags along tier fronts
   ├─ buildBackCrest(folder)       small festival crest crowning the back tier
   └─ connect EliminationEvent / RoundStateChanged  → cheer() over the tier orbs
```

### Component 1 — `src/shared/WorldLayout.luau` (changed: 3 new pure helpers)

Roblox-free, number-in/number-out, deterministic. Final names/signatures may be refined in the plan; the contracts:

- `WorldLayout.tierRows(originX, originZ, halfX, halfZ, rows, spacing, rise, depth, perSide)` → list of `{ x, y, z }` riser slot offsets forming a **U** (back row + two wings) around the rectangle `(originX,originZ ± halfX/halfZ)`. Row `r` (1=innermost) sits at height `r*rise` and recedes outward by `r*depth`; `perSide`/`spacing` control how many orbs per edge and their gap. Slots are pairwise distinct; the front (+Z) edge is intentionally **empty** (open pit side).
- `WorldLayout.festoonStrand(x1, y1, z1, x2, y2, z2, count, sag)` → `count` points along the segment from end 1 to end 2 with a parabolic vertical droop peaking at `sag` mid-span (catenary approximation). Endpoints returned at the posts; interior points dip.
- `WorldLayout.buntingFlags(x1, z1, x2, z2, y, count)` → `count` evenly spaced `{ x, z }` (constant `y`) along the segment for pennant placement.

**Contracts to assert (lune):** `tierRows` produces the documented count (`rows * (perSide_back + 2*perSide_wing)` or equivalent), strictly increasing `y` per row, strictly increasing outward offset per row, no point on the open front edge, all points pairwise distinct. `festoonStrand` returns `count` points, endpoints at the posts, mid-span `y` below the endpoint `y` by ~`sag`, symmetric. `buntingFlags` returns `count` collinear, evenly spaced points at constant `y`.

### Component 2 — `src/client/LobbyStage.luau` (new, client)

Mirrors `ArenaDressing`: a single `start()` that rebuilds a named `workspace.LobbyStage` folder (destroy-and-recreate guard like `ArenaDressing.newFolder`), using a local `rigPart`-style helper (all parts non-colliding/non-querying/shadow-less). Builders:

- **`buildStageDeck`** — a thin cosmetic slab pivoted just above the platform top (`LOBBY_ORIGIN.Y + LOBBY_PAD_SIZE.Y/2 + ε`), sized to the pad, dark broadcast-deck color/material (hybrid: `LOBBY_STAGE_DECK_TEXTURE` else `SmoothPlastic` + `LOBBY_STAGE_DECK_COLOR`), with a thin warm/​player-palette Neon edge-strip toward the +Z railing for the "lit stage lip" read.
- **`buildCrowdTiers`** — from `WorldLayout.tierRows(...)` around the pad footprint; each slot gets a soul-orb (hybrid: `LOBBY_STAGE_ORB_MESH` else the `WorldShell` Neon ball), colored `SOUL_PALETTE[paletteIndex(i, n)]`. Orbs are stored with `{ part, base, baseSize, phase, cheer=0 }` and driven by one Heartbeat doing the idle wobble + decaying cheer pop (copy `WorldShell.buildCrowd`'s loop, reusing `LOBBY_STAGE_*` cheer tunables).
- **`buildFestoon`** — strands strung between post anchor points across the tiers/wings; each strand’s bulbs from `WorldLayout.festoonStrand(...)` as warm-gold `Neon` parts (hybrid: `LOBBY_STAGE_FESTOON_MESH` else Neon bulb on a thin cylinder "wire"). A real `PointLight` is added only to the first `LOBBY_STAGE_FESTOON_LIT` bulbs (mobile cap).
- **`buildBunting`** — pennant flags from `WorldLayout.buntingFlags(...)` along the tier fronts; each flag a player-palette triangle (hybrid: `LOBBY_STAGE_BUNTING_TEXTURE` on a thin part else a `WedgePart`).
- **`buildBackCrest`** — a small framed crest centered above the back tier (a `Part` + `SurfaceGui` like the marquee, but smaller and with festival text, e.g. ★ SOUL FESTIVAL ★), distinct from the kept front marquee.
- **`cheer()` + connections** — on `EliminationEvent.OnClientEvent` and on `RoundStateChanged` `Ended`+`winnerName` (with the same `task.delay(0.25, cheer)` double-pop as `WorldShell`), set each tier orb's `cheer` impulse. Session-lifetime connections.

### Component 3 — `src/shared/Config.luau` (changed: new `LOBBY_STAGE_*` block)

A documented block in the house style (each value carries a comment explaining the reasoning). Proposed fields (final values per the plan):

- **Geometry:** `LOBBY_STAGE_DECK_INSET`, `LOBBY_STAGE_DECK_THICKNESS`, `LOBBY_STAGE_TIER_ROWS`, `LOBBY_STAGE_TIER_RISE`, `LOBBY_STAGE_TIER_DEPTH`, `LOBBY_STAGE_TIER_PER_SIDE`, `LOBBY_STAGE_TIER_SPACING`, `LOBBY_STAGE_FESTOON_SAG`, `LOBBY_STAGE_FESTOON_BULBS`, `LOBBY_STAGE_FESTOON_LIT` (real-light cap), `LOBBY_STAGE_BUNTING_COUNT`, back-crest size/height.
- **Color/mood:** `LOBBY_STAGE_DECK_COLOR`, `LOBBY_STAGE_EDGE_COLOR`, `LOBBY_STAGE_FESTOON_COLOR` (warm gold), `LOBBY_STAGE_LIGHT_RANGE`/`_BRIGHTNESS`, crest colors. Crowd orbs + bunting reuse `SOUL_PALETTE`.
- **Cheer:** `LOBBY_STAGE_IDLE_SPEED`/`_AMP`, `LOBBY_STAGE_CHEER_BOB`/`_SCALE`/`_SECONDS` (mirror the `WORLD_CROWD_*` names/values).
- **Hybrid asset fields (blank ⇒ code fallback, per the `WORLD_SKYBOX` idiom):** `LOBBY_STAGE_DECK_TEXTURE`, `LOBBY_STAGE_ORB_MESH`, `LOBBY_STAGE_FESTOON_MESH`, `LOBBY_STAGE_BUNTING_TEXTURE` (all default `""`).

### Component 4 — `src/client/init.client.luau` (changed: one line)

Add `LobbyStage.start()` alongside the existing `WorldShell.start()` / `ArenaDressing.start()` calls (require + start; same shape).

### Component 5 — hybrid assets (Studio MCP, implementation-time)

Source a thin set via the connected Studio MCP and set the corresponding `LOBBY_STAGE_*` asset fields: stage-deck material/texture, soul-orb crowd mesh, festoon strand/bulb, bunting pennant texture. Gated on MCP availability; each has a verified code fallback so the slice ships regardless. Assets land in the project owner's inventory (per the roadmap's hybrid note).

## Testing

- **Lune unit tests** — extend `tests/world_layout.spec.luau` for `tierRows`, `festoonStrand`, `buntingFlags` against the contracts above (counts, monotonic rise/recede, empty front edge, pairwise-distinct slots, catenary droop + symmetry, collinear evenly-spaced bunting). Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`.
- **Studio MCP visual check** — confirm with `list_roblox_studios` + `get_studio_state` / `set_active_studio`; build the place and `screen_capture` the lobby to verify the grandstand reads as intended (warm lights vs cool sky, U-wrap crowd, open pit side, front marquee + back crest both present, no front-view obstruction). Verify against **workspace instances** (the `workspace.LobbyStage` folder), not by re-requiring stateful modules.
- **Studio smoke test** — new `docs/smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md` (single-client is sufficient since cosmetic; add a 2-client note for the cheer). Checks:
  1. **Look & feel:** standing on the balcony, the stage deck, U-wrap soul crowd, warm festoon lights, bunting, and back crest are present; the sky/aurora stays cool; the front pit view is unobstructed.
  2. **Load-bearing invariant:** a body still cannot walk or **jump** over the railing — no added part is a foothold (all cosmetic parts non-colliding). (Same check as the lobby-staging smoke test, re-verified.)
  3. **Cheer reactivity:** on an elimination and on a winner being named, the grandstand orbs pop/cheer (alongside the distant `WorldShell` crowd).
  4. **Victory cam unobstructed:** during the Ended window the camera frames the winner in the pit with no grandstand geometry in the way.
  5. **Perf:** FPS is stable on the lobby with the new lights (real `PointLight`s capped to `LOBBY_STAGE_FESTOON_LIT`).

## Edge cases & robustness

- **Rebuild idempotency:** `start()` destroys and recreates `workspace.LobbyStage` (like `ArenaDressing.newFolder`), so a re-entry can't duplicate geometry.
- **Missing assets:** every hybrid field defaults `""` → the builder takes the code path (asserted by the `WORLD_SKYBOX`-style guard). No runtime error if an asset id is wrong/unset; the slice renders fully on fallbacks.
- **Crowd front edge stays open:** `tierRows` never emits a slot on the +Z (pit) edge; asserted in the lune test so a future tuning can't silently wall off the victory-cam sightline.
- **No collision regression:** all added parts `CanCollide=false`; the load-bearing balcony parts are server-owned and untouched. The smoke test explicitly re-checks walking and jumping the railing.
- **Cheer with no winner:** the `RoundStateChanged` handler cheers only when `phase == "Ended" and winnerName` (a disconnect-decided round with `winnerName == nil` does not cheer), matching `WorldShell`.
- **Mobile light budget:** real lights capped via `LOBBY_STAGE_FESTOON_LIT`; everything else is `Neon`/static. Tunable down without touching code.

## Files touched

| File | Change |
|------|--------|
| `src/shared/WorldLayout.luau` | **changed** — add pure `tierRows`, `festoonStrand`, `buntingFlags` |
| `src/client/LobbyStage.luau` | **new** — builds the grandstand dressing once (deck, U-wrap crowd, festoon, bunting, back crest); cheer-reactive |
| `src/shared/Config.luau` | **changed** — new `LOBBY_STAGE_*` block (geometry, color/mood, cheer, hybrid asset fields w/ code-only fallbacks) |
| `src/client/init.client.luau` | **changed** — one line: `LobbyStage.start()` |
| `tests/world_layout.spec.luau` | **changed** — lune coverage for the 3 new helpers |
| `docs/smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md` | **new** — Studio visual/runtime check |
| `docs/world-enrichment-roadmap.md` | **changed** — set Slice 2 status 🟡 (→ 🟢 on merge), link this spec |

## Definition of done

Standing on the between-round balcony reads as a **festival grandstand stage**: a lit stage deck, a U-wrap soul-orb crowd that cheers on eliminations/wins, warm festoon lights and bunting against the unchanged cool dusk + aurora, the front marquee kept and a back crest added — with the pit view, victory cam, and load-bearing fall protection all unchanged. Pure helpers are lune-green; the look is MCP-verified; the smoke-test doc is written. Gameplay, collision, and HUD are untouched.
