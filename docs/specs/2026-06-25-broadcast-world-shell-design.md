# Broadcast World Shell — "Soul Festival Sky" (Slice 1)

**Date:** 2026-06-25
**Status:** Design approved — ready for implementation plan
**Type:** Feature design (world / environment art)
**Related:** GDD §1/§5/§6 (world, identity, UX), TDD §1/§8 (client systems, performance)

---

## 1. Motivation

The game world currently reads as empty. At edit time `Workspace` holds only `Terrain` and `Camera`; **everything is built procedurally at runtime** — the 7-floor hex pit ([HazardSystem](../../../src/server/HazardSystem.luau)) and one floating balcony ([LobbyArea](../../../src/server/LobbyArea.luau)) — leaving two objects suspended in default-skybox void. There is no surrounding environment, no authored atmosphere, no ambient life, and no expressed premise.

This slice establishes the game's **world identity**: a bright, festive, broadcast "game show" world with a look unique to *this* game (built on the Soul mechanic), so the arena no longer floats in void and the world feels alive.

### Decisions locked during brainstorming
- **Premise/theme:** Body-Swap Game Show (broadcast).
- **Backdrop direction:** "Soul Festival Sky" — warm dusk gradient, drifting soul-wisps in the player palette, an aurora that flares on every swap, a distant soul-orb crowd. Deliberately avoids the Stumble Guys signature (candy blue→pink sky, puffy clouds, bean-shaped grass islands, balloons).
- **Build approach:** Hybrid (procedural geometry + a thin set of sourced assets), assets sourced by the implementer via the Studio MCP and wired into Config, **each with a code-only fallback**.
- **Multi-arena future:** The game will add more arenas (Fall Guys / Stumble Guys model — one world identity, swappable courses). The design must NOT couple the world to the hex geometry.

---

## 2. Architecture — two layers, 100% client-side cosmetic

The entire shell is **client-side and purely cosmetic**: built in `StarterPlayerScripts/Client`, started from [init.client.luau](../../../src/client/init.client.luau). It has no collision, players never reach it, and it is never gameplay-authoritative — so it lives on the client, costing the server nothing and replicating nothing. This is consistent with the TDD's "ambient VFX is client-computed" rule and contrasts with [LobbyArea](../../../src/server/LobbyArea.luau)/[HazardSystem](../../../src/server/HazardSystem.luau), which are server-built only because they are gameplay-relevant (collision/hazard).

The shell builds **once on client start** and persists across rounds (it does not rebuild per round).

### Two layers separated by a contract

**Layer 1 — Broadcast Shell (arena-agnostic).** The sky, atmosphere, soul-wisps, aurora, and distant soul-orb crowd. Identical for every arena; knows nothing about which course is loaded. This is where most of the "alive world" feeling comes from and is fully reusable across all future arenas.

**Layer 2 — Local Arena Dressing (parametric).** Local framing (spotlight rigs, marquee, near soul-orb spectators) placed around a *specific* course. It does not hardcode the hex; it reads an **`ArenaDescriptor`** and adapts to that footprint.

### The `ArenaDescriptor` contract (the key abstraction)

```lua
ArenaDescriptor = {
    center    : Vector3,  -- arena center (X,Z) + play-surface Y
    footprint : Vector2,  -- X,Z extent of the course; dressing ring sizes to this
    depth     : number,   -- how far the course drops (framing / camera context)
    accent    : Color3,   -- theme accent tint for this arena's dressing
}
```

- The Hex-A-Gone arena is the **first consumer**: it computes its descriptor from [Config](../../../src/shared/Config.luau)/[HexGrid](../../../src/shared/HexGrid.luau) (arena center, top-floor footprint radius → `footprint`, floor span → `depth`).
- Future arenas publish their own descriptor and inherit the shell + dressing with **zero rework**.
- Layer 2 depends only on the descriptor, never on any arena's internals (isolated-units design).

---

## 3. Modules

| Module | Location | Kind | Responsibility |
|--------|----------|------|----------------|
| `WorldLayout` | `src/shared/` | Pure (Roblox-free) | Placement math: wisp spawn positions, soul-orb ring positions, dressing slot positions from a footprint, palette index→color mapping. Clock/RNG injected. **lune-tested.** |
| `ArenaDescriptor` | `src/shared/` | Pure | The descriptor shape + a tiny constructor/validator; a hex-arena descriptor builder helper. |
| `WorldShell` | `src/client/` | Client glue | Builds Layer 1 (atmosphere, sky, wisps, aurora, distant crowd); wires the swap-flare and crowd-cheer hooks. |
| `ArenaDressing` | `src/client/` | Client glue | Builds Layer 2 from a descriptor (spotlight rigs, marquee, near soul-orb spectators). |

`WorldShell` and `ArenaDressing` are started from [init.client.luau](../../../src/client/init.client.luau) alongside the existing controllers. Pure layout math is isolated into `WorldLayout` following the [HexGrid](../../../src/shared/HexGrid.luau) precedent so it is unit-testable without Roblox.

---

## 4. Components & behavior

### Layer 1 — WorldShell

- **Dusk atmosphere.** Set client-side: `Lighting` (ClockTime, Ambient/OutdoorAmbient, Brightness), an `Atmosphere` (warm density/haze), `ColorCorrection` and `Bloom` for the festival grade — amber→rose→violet. Sky via a dusk **skybox asset** (`Sky` with face textures) sourced via MCP; **fallback**: code-only gradient via Atmosphere + Lighting tint with no custom Sky.
- **Soul-wisps.** N drifting glowing parts (or a single `ParticleEmitter` rig) colored from `Config.SOUL_PALETTE`, slow client-driven drift in the sky volume. Count and bounds tunable in Config; respects the mobile particle budget.
- **Aurora ribbon.** An overhead translucent band (layered transparent parts or a textured plane) that **flares on each swap** — a brief brightness/sweep pulse. Hook: the existing per-client swap signal (`SetControlledBody(isSwap=true)`, fired to every player at swap T0) and/or `RoundStateChanged.swapAtServerTime` for synchronized timing. No new remote.
- **Distant soul-orb crowd.** A horizon ring of glowing orbs (`WorldLayout` ring positions) with an idle client wobble that **cheers** (brighten/bob) on `EliminationEvent` and a bigger cheer on the `RoundStateChanged` winner phase. No new remote.

### Layer 2 — ArenaDressing (minimal in this slice)

From the consumed `ArenaDescriptor`:
- **Spotlight rigs** at footprint corners/ring positions (cosmetic light cones, mobile-budgeted).
- **Marquee** — a "BODY SWAP ROYALE" sign placed above the balcony-facing edge.
- **Near soul-orb spectators** — a closer ring of orbs hugging the arena rim.

Deferred to later slices: a *functional* jumbotron leaderboard, confetti on win, spotlight sweeps, richer crowd animation.

---

## 5. Data flow & hooks (no new remotes)

```
Client start (init.client)
  → WorldShell.start()      builds atmosphere/sky/wisps/aurora/distant crowd (once)
  → ArenaDressing.start()   consumes the hex ArenaDescriptor, builds local framing (once)

Existing signals reused (cosmetic listeners only):
  SetControlledBody(isSwap=true) / RoundStateChanged.swapAtServerTime → aurora flare
  EliminationEvent                                                    → crowd cheer (bob/brighten)
  RoundStateChanged (winner phase)                                    → crowd big cheer
  SoulMap / Config.SOUL_PALETTE                                       → wisp + orb colors
```

All hooks are read-only cosmetic listeners on **existing** remotes; the shell never sends anything and never affects authoritative state.

---

## 6. Build approach & assets (hybrid)

- Geometry and placement are **procedural in code**, tuned by a new `WORLD_*` block in [Config](../../../src/shared/Config.luau) (wisp count/colors/bounds, orb ring radius/count, aurora flare params, dressing offsets, atmosphere/lighting values, assetIds).
- The implementer **sources assets via the Studio MCP** (catalog search and/or generation): primarily the **dusk skybox**, optionally a wisp/aurora texture. Each is verified with `screen_capture` and its assetId wired into Config.
- **Every asset has a code-only fallback** (gradient sky, solid-color wisps, untextured aurora plane). The shell must render acceptably with all assetIds blank.
- Assets land in the project owner's Roblox inventory (assetIds tied to the account) — accepted trade-off of the hybrid path.

---

## 7. Performance (mobile-first)

- 100% client cosmetic: **zero server CPU, zero replication.**
- Wisp/orb counts, spotlight count, and effect toggles are Config-driven, with conservative defaults sized for the mobile particle budget (TDD §8).
- A low-end path (reduced counts / disabled aurora) is exposed via Config flags for a future quality-tier hook; this slice ships sensible defaults, not the full tier system.

---

## 8. Testing

- **Unit (lune):** `WorldLayout` placement math — deterministic wisp/orb/dressing positions for a given footprint and seed, palette index→color mapping, `ArenaDescriptor` validation. Run via `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec`.
- **Visual (Studio MCP):** `screen_capture` in Edit and play mode to confirm the dusk grade, sky, wisps, aurora, and crowd render correctly behind the arena (the method used to verify the hex arena geometrically).
- **Manual smoke test** (`docs/smoke-tests/`): shell appears behind the arena; aurora flares on swap; crowd cheers on elimination/win; no obvious FPS regression; acceptable appearance with all assetIds blank (fallback path).

---

## 9. Scope boundary & slice roadmap

**In this slice (Slice 1):** Layer 1 WorldShell + the `ArenaDescriptor` contract + minimal Layer 2 framing (spotlights, marquee, near orbs), with the hex arena as the first descriptor consumer.

**Explicitly NOT in this slice — later slices:**
- **Slice 2 — Lobby hub redress (hybrid rebuild):** rebuild the balcony into a broadcast "on-deck" stage matching the Soul Festival world, using the hybrid approach.
- **Slice 3 — Hex pit hybrid re-skin:** upgrade the hex tiles from stock parts to hybrid (materials/textures/mesh) matching the new aesthetic, **without changing the erosion gameplay**.
- **Slice 4 — Ambient life systems:** functional jumbotron leaderboard, confetti on win, spotlight sweeps, richer crowd reactions.
- **Slice 5 — Activities:** warmup / practice-swap things to do while waiting between rounds.

---

## 10. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Sourced assets unavailable / poor quality | Code-only fallback for every asset; shell renders without any assetId. |
| Client-side `Lighting`/`Atmosphere` edits affect only local view | Intended — the shell is per-client cosmetic; no expectation of authoritative lighting. |
| Mobile FPS regression from wisps/orbs/lights | Conservative Config defaults, particle-budget sizing, low-end toggles, MCP/manual perf check. |
| Coupling the world to hex geometry (kills multi-arena future) | `ArenaDescriptor` contract; Layer 2 reads only the footprint; hex is just the first consumer. |
| Aurora flare desync between clients | Prefer `RoundStateChanged.swapAtServerTime` for a shared timestamp; flare is brief and forgiving. |

---

*End of design — Slice 1 of the world-enrichment effort.*
