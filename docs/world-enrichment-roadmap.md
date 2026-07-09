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
| 1 | **Broadcast World Shell — "Soul Festival Sky"** | 🟢 Done (single-client MCP-verified; 2-client smoke pending) | [spec](superpowers/specs/2026-06-25-broadcast-world-shell-design.md) · [plan](superpowers/plans/2026-06-25-broadcast-world-shell.md) · [smoke](smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md) | Layer 1 shell (dusk skybox + atmosphere, soul-wisps, swap-reactive aurora, soul-orb crowd) + `ArenaDescriptor` contract + Layer 2 framing, hex arena as first consumer. 100% client-cosmetic. Built on `feat/broadcast-world-shell`. |
| 1b | **Per-floor dressing + banner redesign** (Slice 1 polish) | 🟢 Done (floor dressing superseded by the Slice-2 edge-trim reskin) | [spec](superpowers/specs/2026-06-25-per-floor-dressing-and-banner-design.md) · [plan](superpowers/plans/2026-06-25-per-floor-dressing-and-banner.md) | Originally: per-floor floor-colored torches + soul-orb ring per floor + the framed marquee. **The torches + orb rings were replaced by a floor-colored edge trim in the 2026-06-26 [orb-vocabulary reassessment](superpowers/specs/2026-06-26-orb-vocabulary-reassessment-design.md)** (folded into the Slice-2 branch); the marquee remains. |
| 2 | **Lobby Hub Redress — Beyblade Lobby** | 🟢 Done (lune green + static geometry review; live MCP/2-client smoke pending a Rojo re-sync) | [grandstand spec](superpowers/specs/2026-06-26-lobby-grandstand-stage-design.md) · [reassessment](superpowers/specs/2026-06-26-orb-vocabulary-reassessment-design.md) · [beyblade spec](superpowers/specs/2026-06-27-beyblade-lobby-design.md) · [beyblade plan](superpowers/plans/2026-06-27-beyblade-lobby.md) · [smoke](smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md) | Evolved across the branch: (1) festival **grandstand stage** redress of the balcony; (2) **orb-vocabulary reassessment** — hex floors → floor-colored edge trim (uniform Neon, no real lights), souls vs lights split (≈226 → ≈82 orbs); (3) **beyblade redesign** — the boxed balcony ([LobbyArea](../src/server/LobbyArea.luau)) becomes a round walkable **disc + invisible rim barrier** (load-bearing) dressed as a spinning top (energy rings, stepped taper, tip, rim spectator-soul clusters). Server geometry rewritten for the disc/barrier; client `LobbyStage` re-dressed; pure `WorldLayout.cluster` lune-tested. Built on `feat/lobby-grandstand-stage`. |
| 3 | **Hex Pit Hybrid Re-skin** | ⚪ Not started | — | Upgrade the hex tiles ([HazardSystem](../src/server/HazardSystem.luau)) from stock parts to hybrid (materials/textures/mesh) matching the new aesthetic — **without changing the erosion gameplay**. |
| 4 | **Ambient Life Systems** | ⚪ Not started | — | Functional jumbotron leaderboard, confetti on win, spotlight sweeps, richer crowd reactions. |
| 5 | **Activities** | ⚪ Not started | — | Warmup / practice-swap things to do while waiting between rounds. |

---

## Parking lot (not scheduled — ideas, not yet slices)

Captured so they aren't lost, but deliberately **not** numbered slices and not committed to this roadmap's order.

- **Soul Sweeper v2 arena — "Soul Turbine" + persistent two-arena world.** 🟡 Redesigned the sweeper
  as a single annulus platform + central hub turbine with two solid stacked beams (server-animated,
  physics-collidable); converted the world to persistent multi-arena with per-round rotation and full
  idle-arena dormancy (zero per-frame cost for inactive arenas). Pure `ArenaRotationModel` (lune-tested),
  collision-group grace pass-through, backstop anti-cheat, validator reseeds for beam shoves. Client
  rewrote `SweeperController` as single shared loop fully gated on `LiveArena` attribute. Soul Turbine
  art pass (137 parts, ≤180 budget): procedural annulus + hub + wake channels + rotor + light shaft +
  marquee + under-structure + spotlights; three sourced asset slots (fallback-complete). Verified: 24/24
  lune. See [spec](superpowers/specs/2026-07-08-soul-sweeper-v2-turbine-design.md) and
  [plan](superpowers/plans/2026-07-08-soul-sweeper-v2-turbine.md). **v2.1 refinement** (2026-07-09):
  true-circle platform (EditableMesh annulus over densified 48-segment collision), telegraphs removed,
  motorized solid striped machine-bar beams (HingeConstraint physics), measured-angle strikes. See
  [v2.1 spec](superpowers/specs/2026-07-09-soul-sweeper-v2_1-jumpclub-refinement-design.md) and
  [v2.1 plan](superpowers/plans/2026-07-09-soul-sweeper-v2_1-jumpclub-refinement.md); [smoke test](smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md).
  Tasks 9–10: Studio MCP verification + asset sourcing pending. **v2.2 touch elimination**
  (2026-07-09): beams instantly eliminate on touch (deterministic swept-interval strike on
  measured poses) instead of physics-shoving — the resist backstop, validator reseeds, the
  `SweptAt` tumble, and the entire collision-group system are deleted; round-start grace added
  for every participant (also delays hex spawn-tile arming by up to `GRACE_SECONDS`). See
  [v2.2 spec](superpowers/specs/2026-07-09-soul-sweeper-v2_2-touch-elimination-design.md) and
  [v2.2 plan](superpowers/plans/2026-07-09-soul-sweeper-v2_2-touch-elimination.md).
- **Dedicated social hub world.** A persistent space players land in *before/around* matches — main menu, shop, cosmetic customization, matchmaking queue, friends, emotes, hanging out (Fall Guys' main-menu/show-select equivalent). Distinct from the in-game balcony ([LobbyArea](../src/server/LobbyArea.luau)), which is between-rounds staging in the match world. A meaty addition: its own world, navigation, and likely a `TeleportService` flow; overlaps TDD §4 (lobby matchmaking) and the `MenuController`/shop systems. If pursued, scope as its **own** roadmap/effort rather than folding into Slice 2.

---

## Notes

- Slices are independent specs built in order; revisit ordering after each playtest.
- When a slice starts, set its status to 🟡 and link its spec; on merge, set 🟢.
