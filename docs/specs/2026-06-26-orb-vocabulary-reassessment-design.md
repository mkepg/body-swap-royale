# Orb-Vocabulary Reassessment — Design

**Date:** 2026-06-26
**Status:** Approved — ready for plan
**Branch:** `feat/lobby-grandstand-stage` (folded into the in-flight World Slice 2 work, before merge)
**Touches:** World Slice 2 (`LobbyStage`, this branch) **and** shipped Slice 1b (`ArenaDressing` floor dressing).
**Related:** `docs/specs/2026-06-26-lobby-grandstand-stage-design.md`, `docs/world-enrichment-roadmap.md`.

## Problem

A review of the assembled world found that **glowing soul-orbs had become the entire visual vocabulary** — used for sky wisps, the distant crowd, every hex floor's ring, the new lobby crowd, *and* the lobby festoon "bulbs." Inventory at the time:

| Where | Glowing orbs |
|---|---|
| Sky wisps (`WorldShell`) | 22 |
| Distant crowd ring (`WorldShell`) | 48 |
| Per-floor rings, 12 × 7 floors (`ArenaDressing`) | 84 |
| Lobby crowd (Slice 2) | 45 |
| Lobby festoon bulbs (Slice 2) | 27 |

≈ **226 glowing spheres** (+28 neon torch heads). When everything is a glowing ball, nothing reads as distinct: the festival *lights* look like *souls*, the lobby crowd piles onto an already-visible distant crowd, and `Config` itself already warned *"reduced so 7 stacked rings aren't soup."* Two specific failures:
- The lobby U-wrap crowd's **back tier is behind the pit-facing camera (unseen)** and the **wings are peripheral** — 45 orbs for a payoff that barely registers from the primary POV.
- The festoon **lights rendered as the same primitive as souls**, so the Magic-Hour warm/cool contrast muddied.

## Principle

**A glowing soul-orb means one thing — a living soul (the crowd / sky wisps). Lights are a visually distinct form. Density follows visibility.**

## Changes

### 1. Lobby crowd → small wing clusters *(Slice 2, `LobbyStage`)*
Drop the U-wrap entirely (no back tier). Replace it with **two small soul clusters (~6 orbs each, ~12 total)** at the **pit-view edges** (front ±X corners), where peripheral vision and cheer-pops actually register. Still reuses the existing `EliminationEvent` / `RoundStateChanged` cheer signal. (45 → ~12.)

- The pure `WorldLayout.tierRows` helper (added earlier this branch) becomes obsolete and is **removed along with its lune test**; a new pure `WorldLayout.cluster` replaces it (small centered point group), lune-tested.

### 2. Lobby festoon → string-lights, not soul-balls *(Slice 2, `LobbyStage`)*
Keep the catenary placement (`WorldLayout.festoonStrand` unchanged), but render each strand as a **thin dark wire (hung between consecutive bulb points) with smaller warm bulbs on it**. The visible wire is the tell that distinguishes a hung light from a free-floating soul. Warm gold stays; bulbs shrink. This is the lobby's primary *seen* festival element (visible looking forward/up over the pit).

### 3. Hex floors → floor-colored edge trim, not torches + orb rings *(shipped Slice 1b, `ArenaDressing`)*
Replace **both** the per-floor 4 corner torches **and** the 12-orb ring with a single **floor-colored glowing edge trim per floor**: a ring of thin `Neon` tangent segments hugging the floor rim, tinted to that floor's `levels[i].color`. Read: a "lit tier" in a polished game-show arena — one coherent rim per floor instead of 16 scattered glowing elements.

- **Trim radius is derived from the descriptor footprint** (`footprint.X / 2`), not a hardcoded radius — so it hugs the padded rim and is arena-agnostic (an improvement over the old fixed `WORLD_NEAR_ORB_RADIUS = 70`).
- **Placed at the rim, outside the outermost tiles** (no part sits under a play tile), so eroding tiles never reveal a glowing plate that could be misread as solid floor. (Gameplay-clarity guard.)
- **Lighting:** the torches were the only floor light. Replace with a few **floor-colored `PointLight` uplights on the top `WORLD_TRIM_LIT_FLOORS = 3` floors** (attached to a small, evenly-spaced subset of that floor's trim segments) — preserving visibility of the erosion on the floors you actually play on, at the same ~12-light budget the torches used. Deep floors get trim color but no real light (mobile budget), matching the old `WORLD_TORCH_LIT_FLOORS` discipline.
- The **front marquee** (`ArenaDressing.buildBanner`) is untouched.

### 4. Keep as-is
- **Distant crowd ring (48)** — the canonical reactive audience, visible across the pit. Unchanged.
- **Sky wisps (22)** — sparse, atmospheric, different context (sky vs ground). Unchanged.

**Net:** ≈226 glowing spheres → ≈ (22 wisps + 48 distant + ~12 lobby cluster) = **~82 soul-orbs**, plus a distinct **lights** form (festoon string-lights + floor trim). Each remaining orb means something.

## Architecture / files

All changes are **100% client-cosmetic, add-only over untouched server geometry** (same invariant as the rest of the world layer): every part `Anchored`, `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `CastShadow=false`.

| File | Change |
|---|---|
| `src/shared/WorldLayout.luau` | **remove** `tierRows`; **add** pure `cluster(cx, cz, baseY, n, spacing)` |
| `tests/world_layout.spec.luau` | remove the `tierRows` block; add a `cluster` block |
| `src/client/ArenaDressing.luau` | replace `buildTorches`/`buildTorch` + `buildOrbRings` with `buildFloorTrim` (per-floor tangent-segment rim from `WorldLayout.ring`, footprint-derived radius, top-N uplights); keep `buildBanner` |
| `src/client/LobbyStage.luau` | crowd: `buildCrowdTiers` → `buildCrowdClusters` (two wing clusters via `cluster`); festoon: add wire segments + smaller bulbs |
| `src/shared/Config.luau` | remove `WORLD_TORCH_*` + `WORLD_NEAR_ORB_*` + `LOBBY_STAGE_TIER_*`; add `WORLD_TRIM_*` and `LOBBY_STAGE_CLUSTER_*` + festoon wire fields |

### `WorldLayout.cluster` contract (pure, lune-tested)
`cluster(cx, cz, baseY, n, spacing)` → `n` points `{x,y,z}` in a single centered row along X at constant `y=baseY`, centered on `(cx,cz)` with gap `spacing` (so the group straddles the center). Assert: count `== n`; constant `y`; centered (mean x ≈ cx); even spacing; pairwise distinct.

### `buildFloorTrim` (client, in `ArenaDressing`)
For each `desc.levels[i]`: positions from `WorldLayout.ring(center.X, center.Z, footprint.X/2 + WORLD_TRIM_MARGIN, WORLD_TRIM_SEGMENTS)`; each segment a thin `Neon` bar at `lv.y + WORLD_TRIM_Y` tinted `lv.color`, oriented tangent (face toward the next ring point via `CFrame.lookAt`), sized so consecutive bars nearly meet (reads continuous). For the top `WORLD_TRIM_LIT_FLOORS` floors, attach a floor-colored `PointLight` (`WORLD_TRIM_LIGHT_RANGE`/`_BRIGHTNESS`) to `WORLD_TRIM_LIGHTS_PER_FLOOR` evenly-spaced segments.

## Testing
- **Lune:** `tests/world_layout.spec.luau` stays green with `cluster` covered and `tierRows` removed. `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`.
- **MCP structural:** in Play, inspect `workspace.ArenaDressing` (per-floor trim segment count = `WORLD_TRIM_SEGMENTS × HEX_FLOOR_COUNT`; PointLights = `WORLD_TRIM_LIGHTS_PER_FLOOR × WORLD_TRIM_LIT_FLOORS`; no `TorchPost`/`TorchHead`/`NearOrb`) and `workspace.LobbyStage` (CrowdOrb count ≈ `2 × cluster n`; festoon wire segments present; no back-tier orbs). Confirm all new parts `CanCollide=false`.
- **Smoke doc:** extend `docs/smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md` with the reassessment checks (floors read as colored lit rims; tiles erode without revealing a solid glowing plate; lobby crowd only at the pit-view edges; festoon reads as string-lights; top-floor visibility preserved).

## Out of scope
- The distant crowd and sky wisps (keep).
- Any gameplay, server geometry, HUD, or `ArenaDescriptor` change.
- Sourcing hybrid assets (still deferred; trim/clusters/festoon all ship as code).
