# World Enrichment Roadmap

**Started:** 2026-06-25
**Goal:** Make the game world feel alive, immersive, and engaging instead of "two objects floating in default-skybox void" (the procedural hex pit + one balcony). Establish a single **broadcast "game show" world identity** — "Soul Festival Sky" — that is **reusable across multiple future arenas** (Fall Guys / Stumble Guys model: one world, swappable courses).

This is the **cross-slice source of truth**. Each slice gets its own `docs/specs/` design doc and implementation plan; this file tracks the whole effort and its status.

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
| 1 | **Broadcast World Shell — "Soul Festival Sky"** | 🟡 Spec approved — implementation pending | [2026-06-25-broadcast-world-shell-design.md](superpowers/specs/2026-06-25-broadcast-world-shell-design.md) | Layer 1 shell (dusk atmosphere, soul-wisps, swap-reactive aurora, soul-orb crowd) + `ArenaDescriptor` contract + minimal Layer 2 framing (spotlights, marquee, near orbs), hex arena as first consumer. 100% client-cosmetic. |
| 2 | **Lobby Hub Redress (hybrid rebuild)** | ⚪ Not started | — | Rebuild the balcony ([LobbyArea](../src/server/LobbyArea.luau)) into a broadcast "on-deck" stage matching the Soul Festival world, using the hybrid approach. |
| 3 | **Hex Pit Hybrid Re-skin** | ⚪ Not started | — | Upgrade the hex tiles ([HazardSystem](../src/server/HazardSystem.luau)) from stock parts to hybrid (materials/textures/mesh) matching the new aesthetic — **without changing the erosion gameplay**. |
| 4 | **Ambient Life Systems** | ⚪ Not started | — | Functional jumbotron leaderboard, confetti on win, spotlight sweeps, richer crowd reactions. |
| 5 | **Activities** | ⚪ Not started | — | Warmup / practice-swap things to do while waiting between rounds. |

---

## Notes

- Slices are independent specs built in order; revisit ordering after each playtest.
- When a slice starts, set its status to 🟡 and link its spec; on merge, set 🟢.
