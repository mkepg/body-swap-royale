# Beyblade Lobby — Design

**Date:** 2026-06-27
**Status:** Approved — ready for plan
**Branch:** `feat/lobby-grandstand-stage` (continues the Slice-2 lobby work).
**Touches:** server `LobbyArea.luau` (load-bearing), client `LobbyStage.luau` (cosmetic), `Config`, a one-line `ArenaDressing` banner-mount tweak, and removal of two now-unused pure helpers.
**Related:** `2026-06-26-lobby-grandstand-stage-design.md`, `2026-06-26-orb-vocabulary-reassessment-design.md`.

## Problem / goal

The between-round lobby is a walled **box** balcony (platform + 3 solid walls + a glass railing). Redesign it into a **single-floor structure players stand on top of, shaped like a beyblade** (a spinning top): a wide round top disc to stand on, a stepped taper body below narrowing to a performance tip, and glowing energy rings at the rim — floating, elevated, over the pit.

## Locked decisions (from brainstorm, 2026-06-27)

- **Shape:** beyblade — round walkable **top disc**, **stepped taper** body (decreasing-radius layers) down to a **tip**, **energy rings** at the rim.
- **Fall safety = hybrid:** a **low visible energy ring** at the rim (cosmetic, on-theme) **plus an invisible taller barrier** above it (the real, load-bearing fall protection — gap-free, taller than a jump).
- **Dressing = blend into beyblade detailing:** the old festival "lights" become the **energy rings**; the two small **soul-orb clusters are kept** (cheer-reactive "spectator souls" at the rim); **bunting, back crest, festoon strands, and the rectangular deck are dropped**.
- **Unchanged:** lobby position (set-back, elevated over the pit at `LOBBY_ORIGIN = (0,45,-64)`), the victory cam, the round loop, the body grid/slots, and the **front marquee** (kept, re-anchored off the disc radius). The **top surface does not spin** (players stand on a static disc; any spin would be cosmetic on a lower ring — not in this scope).

## Architecture (two-layer split preserved)

- **Server `LobbyArea.luau` (load-bearing — rewritten).** Replaces the box with:
  - **Disc:** an anchored `CanCollide` `Cylinder` part, axis vertical, **top face at `LOBBY_ORIGIN.Y`**, radius `LOBBY_DISC_RADIUS` (sized to hold the 4×4 body grid + margin). The single walkable floor.
  - **Invisible barrier ring:** a **gap-free** ring of `LOBBY_BARRIER_SEGMENTS` tall, thin, `Transparency = 1`, `CanCollide` box segments at the disc rim, height `LOBBY_WALL_HEIGHT` (> `JUMP_HEIGHT = 7.2`), oriented tangent with `LOBBY_BARRIER_SLACK` overlap so there are no gaps. **This is the fall protection** — a body can neither walk nor jump off. Uses the pure `WorldLayout.ring` for segment placement.
  - Idempotent singleton (same `built` guard).
- **Client `LobbyStage.luau` (cosmetic — re-dressed as the beyblade, add-only, all parts non-colliding).** Centered at `LOBBY_ORIGIN` X/Z:
  - **Deck:** a thin `Cylinder` skin just above the disc top (dark metal).
  - **Energy rings:** 2 `Neon` `Cylinder` discs slightly **wider** than the deck, sitting just under it so only the glowing **rim** shows (the deck occludes their centers) — concentric glowing bands. The topmost (`RING_COLOR_A`, cool) is the **visible half of the hybrid fall ring**; a lower, wider warm ring (`RING_COLOR_B`) reads as the energy layer.
  - **Stepped taper:** `LOBBY_BEY_STEPS` (a list of `{radiusFrac, depth, thickness}`) → stacked metal `Cylinder` discs of decreasing radius below the disc.
  - **Tip:** a small vertical spike (thin `Cylinder`) + a `Neon` tip below the lowest step.
  - **Spectator souls:** the two cheer-reactive soul-orb clusters, repositioned to the **rim** (at `LOBBY_BEY_CLUSTER_RADIUS × disc radius` on ±X), reusing `WorldLayout.cluster` + the existing `EliminationEvent`/`RoundStateChanged` cheer Heartbeat.
  - **Dropped:** `buildFestoon`/`buildStrand`, `buildBunting`, `buildBackCrest`, the rectangular `buildStageDeck`.
- **`ArenaDressing.buildBanner`:** one line — mount the marquee off `LOBBY_DISC_RADIUS` instead of `LOBBY_PAD_SIZE.Z/2` (marquee stays as the floating title over the front).
- **`WorldLayout.luau`:** **remove `festoonStrand` and `buntingFlags`** (added earlier this branch, now unused) and their lune tests. `cluster`, `ring`, `paletteIndex` remain (still used).
- **`Config`:** swap the lobby block — remove box keys (`LOBBY_PAD_SIZE`, `LOBBY_COLOR_PAD`, `LOBBY_COLOR_WALL`, `LOBBY_RAILING_TRANSPARENCY`) and the dropped-dressing keys (`LOBBY_STAGE_DECK_*` rectangular, `LOBBY_STAGE_EDGE_*`, `LOBBY_STAGE_FESTOON_*`, `LOBBY_STAGE_BUNTING_*`, `LOBBY_STAGE_CREST_*`, `LOBBY_STAGE_CLUSTER_INSET/FRONT/LIFT`, `LOBBY_STAGE_LIGHT_*`, `LOBBY_STAGE_BUNTING_TEXTURE`/`FESTOON_MESH`); add disc/barrier keys (`LOBBY_DISC_RADIUS/THICKNESS/COLOR`, `LOBBY_BARRIER_SEGMENTS/SLACK`) and beyblade-cosmetic keys (`LOBBY_BEY_*`). **Keep** `LOBBY_ORIGIN`, the grid keys (`LOBBY_CAPACITY/PER_ROW/SPACING`), `LOBBY_SPAWN_DROP`, `LOBBY_FACE_TARGET`, `LOBBY_WALL_HEIGHT/THICKNESS` (now the barrier dims), and `LOBBY_STAGE_CLUSTER_PER_SIDE/SPACING`, `LOBBY_STAGE_ORB_SIZE`, `LOBBY_STAGE_IDLE_*`, `LOBBY_STAGE_CHEER_*`, `LOBBY_STAGE_ORB_MESH`.

## Load-bearing invariant (the critical correctness point)

The disc floats over the void; the **invisible barrier ring is the only thing stopping a between-rounds void death.** It MUST be **gap-free** (segments overlap via `LOBBY_BARRIER_SLACK`) and **taller than a jump** (`LOBBY_WALL_HEIGHT 12 > JUMP_HEIGHT 7.2`). The cosmetic client parts are all `CanCollide = false` and cannot substitute for it. The smoke test explicitly re-checks walking **and jumping** the rim from multiple angles.

## Geometry notes

- A Roblox `Cylinder` part has its length on the local **X** axis; to stand it as a flat disc, rotate `CFrame.Angles(0, 0, math.rad(90))` so X points up, and use `Size = Vector3.new(thickness, diameter, diameter)`. Disc center Y = `LOBBY_ORIGIN.Y - thickness/2` so the **top face is at `LOBBY_ORIGIN.Y`** (bodies drop onto it exactly as before).
- `LOBBY_DISC_RADIUS = 30` (diameter 60) holds the 4×4 grid (corner slot ≈ radius 21) with margin.
- Barrier segment length = chord between adjacent ring points × `LOBBY_BARRIER_SLACK (1.1)`; centers at radius `LOBBY_DISC_RADIUS`, so the inner face sits just inside the disc edge.

## Testing

- **Lune:** `tests/world_layout.spec.luau` stays green after removing the `festoonStrand`/`buntingFlags` blocks (`ring`, `cluster`, etc. still covered). Run `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`.
- **MCP structural (Play):** inspect `workspace.LobbyArea` — one `Disc` (`CanCollide=true`, `Cylinder`, top at `LOBBY_ORIGIN.Y`) + `LOBBY_BARRIER_SEGMENTS` `Barrier` parts (`CanCollide=true`, `Transparency=1`, height `LOBBY_WALL_HEIGHT`); inspect `workspace.LobbyStage` — deck + 2 energy rings + taper steps + tip + ~`2 × LOBBY_STAGE_CLUSTER_PER_SIDE` CrowdOrbs; all cosmetic parts `CanCollide=false`; no box/festoon/bunting/crest parts remain.
- **Smoke doc:** extend the Slice-2 smoke doc with the beyblade checks (stand on the disc; **walk and jump the rim from several angles — cannot leave**; beyblade silhouette reads; energy rings + spectator-soul cheer; bodies still spawn/teleport correctly; victory cam unobstructed).

## Out of scope
- Spinning the structure; relocating the lobby; gameplay/round-loop/body-slot changes; `ArenaDescriptor`; sourcing hybrid assets (beyblade ships as code).
