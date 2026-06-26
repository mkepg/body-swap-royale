# World Enrichment Roadmap

**Started:** 2026-06-25
**Goal:** Make the game world feel alive, immersive, and engaging instead of "two objects floating in default-skybox void" (the procedural hex pit + one balcony). Establish a single **broadcast "game show" world identity** — "Soul Festival Sky" — that is **reusable across multiple future arenas** (Fall Guys / Stumble Guys model: one world, swappable courses).

This is the **cross-slice source of truth**. Each slice gets its own `docs/superpowers/specs/` design doc and implementation plan; this file tracks the whole effort and its status.

**Status legend:** 🟢 Done · 🟡 In progress / spec'd · ⚪ Not started.

---

## Locked creative + technical decisions (apply to every slice)

- **Theme:** Body-Swap Game Show (broadcast).
- **Backdrop identity:** "Soul Festival Sky" — warm dusk gradient, drifting soul-wisps in the player palette, an aurora that flares on each swap, a distant soul-orb crowd. Deliberately avoids the Stumble Guys signature (candy sky, puffy clouds, bean-shaped grass islands, balloons).
- **Build approach:** Hybrid — procedural geometry + a thin set of sourced assets (skybox/materials/textures), each with a **code-only fallback**. Assets sourced via the Studio MCP, wired into Config, and land in the project owner's Roblox inventory.
- **Architecture:** Two layers separated by a contract. **Layer 1** = arena-agnostic broadcast shell (the world identity). **Layer 2** = footprint-parametric local dressing driven by an **`ArenaDescriptor`** (`center`, `footprint`, `depth`, `accent`). No slice may couple the world to the hex geometry; the hex arena is just the first descriptor consumer.

---

## Slices

| # | Slice | Status | Spec | Notes |
|---|-------|--------|------|-------|
| 1 | **Broadcast World Shell — "Soul Festival Sky"** | 🟢 Done (single-client MCP-verified; 2-client smoke pending) | [spec](superpowers/specs/2026-06-25-broadcast-world-shell-design.md) · [plan](superpowers/plans/2026-06-25-broadcast-world-shell.md) · [smoke](smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md) | Layer 1 shell (dusk skybox + atmosphere, soul-wisps, swap-reactive aurora, soul-orb crowd) + `ArenaDescriptor` contract + Layer 2 framing, hex arena as first consumer. 100% client-cosmetic. Built on `feat/broadcast-world-shell`. |
| 1b | **Per-floor dressing + banner redesign** (Slice 1 polish) | 🟢 Done (single-client MCP-verified) | [spec](superpowers/specs/2026-06-25-per-floor-dressing-and-banner-design.md) · [plan](superpowers/plans/2026-06-25-per-floor-dressing-and-banner.md) | `ArenaDescriptor.levels` → per-floor floor-colored torches (real lights capped to top 3) + soul-orb ring per floor; "Body Swap Royale" banner redesigned into a framed marquee header on the balcony edge. |
| 2 | **Lobby Hub Redress — Festival Grandstand Stage** | 🟢 Done (single-client MCP structural-verified; 2-client/aesthetic smoke pending) | [spec](superpowers/specs/2026-06-26-lobby-grandstand-stage-design.md) · [plan](superpowers/plans/2026-06-26-lobby-grandstand-stage.md) · [smoke](smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md) | Redress the balcony ([LobbyArea](../src/server/LobbyArea.luau)) into a **festival grandstand stage** (Concept B): "Magic-Hour Fair" warm festoon lights against the cool dusk/aurora, a U-wrap soul-orb crowd that reuses the Slice-1 cheer signal, stage deck + bunting + back crest. New client `LobbyStage` (add-only, server geometry untouched) + pure `WorldLayout` helpers (`tierRows`/`festoonStrand`/`buntingFlags`, lune-tested); hybrid asset fields default to code fallbacks (no assets sourced yet). 100% client-cosmetic. Built on `feat/lobby-grandstand-stage`. |
| 3 | **Hex Pit Hybrid Re-skin** | ⚪ Not started | — | Upgrade the hex tiles ([HazardSystem](../src/server/HazardSystem.luau)) from stock parts to hybrid (materials/textures/mesh) matching the new aesthetic — **without changing the erosion gameplay**. |
| 4 | **Ambient Life Systems** | ⚪ Not started | — | Functional jumbotron leaderboard, confetti on win, spotlight sweeps, richer crowd reactions. |
| 5 | **Activities** | ⚪ Not started | — | Warmup / practice-swap things to do while waiting between rounds. |

---

## Parking lot (not scheduled — ideas, not yet slices)

Captured so they aren't lost, but deliberately **not** numbered slices and not committed to this roadmap's order.

- **Dedicated social hub world.** A persistent space players land in *before/around* matches — main menu, shop, cosmetic customization, matchmaking queue, friends, emotes, hanging out (Fall Guys' main-menu/show-select equivalent). Distinct from the in-game balcony ([LobbyArea](../src/server/LobbyArea.luau)), which is between-rounds staging in the match world. A meaty addition: its own world, navigation, and likely a `TeleportService` flow; overlaps TDD §4 (lobby matchmaking) and the `MenuController`/shop systems. If pursued, scope as its **own** roadmap/effort rather than folding into Slice 2.

---

## Notes

- Slices are independent specs built in order; revisit ordering after each playtest.
- When a slice starts, set its status to 🟡 and link its spec; on merge, set 🟢.
