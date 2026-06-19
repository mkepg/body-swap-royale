# Disappearing Tile Hazard — Design Spec

**Date:** 2026-06-19
**Status:** Approved (design); implementation pending
**Related:** [GDD §5 Dynamic Hazard System](../../body-swap-royale-gdd.md#5-detailed-feature-breakdown), [TDD §3 Dynamic Hazard System](../../body-swap-royale-tdd.md#3-feature-technical-considerations), [TDD §1 Systems](../../body-swap-royale-tdd.md#1-systems-architecture), [TDD §10 MVP Scope](../../body-swap-royale-tdd.md#10-development-roadmap). Builds on the shipped [RoundManager spine](2026-06-18-round-manager-design.md) and the [Post-Swap Grace Window](2026-06-18-grace-window-design.md), reusing the `RoundManager.eliminateFromHazard` gate and the pure-module + server-glue split established by `RoundState` / `ControlModel` / `GraceModel`.

## Purpose

The MVP arena currently has exactly one death source: a body whose root crosses `VOID_Y` is eliminated through the grace gate by the void monitor. But the arena is just a baseplate — the only way to die is to walk off the edge. There is no danger *in* the play space, so a body can park safely forever and the swap is a toy rather than a survival challenge (GDD §5: "keep players engaged in active danger so passive parking isn't viable").

The **disappearing tile hazard** turns the floor itself into the threat. The arena floor becomes a grid of tiles that cycle `solid → warning (red) → gone → solid`; a body standing on a tile that vanishes drops through and is eliminated. This gives the arena real, telegraphed danger and — because elimination routes through the existing `eliminateFromHazard` gate — exercises the post-swap grace window through a second source: inherit a body on a vanishing tile and the grace window buys the beat to jump clear.

## Scope

**In scope:**
- A new pure, time-injected, lune-tested module `TileFieldModel` holding the per-tile phase decision (`phaseAt`) and a deterministic offset helper.
- A new server-glue module `HazardSystem`: builds the tile grid procedurally at runtime, removes the baseplate, and runs a token-gated loop that maps each tile's phase to part properties.
- New `Config` tunables (tile timing, grid dimensions, colors, geometry) and a raised `VOID_Y` so fall-through is a quick, grace-protectable death.
- Three minimal `RoundManager` hooks (`build` at startup, `start` in `beginRound`, `stop` in `endRound`).
- A lune test for `TileFieldModel` and a new Studio smoke-test doc.

**Out of scope (later steps):**
- Any other hazard type (sweeping beam, wind gust, crusher, shrinking floor — GDD §5). The model + system are built to host more later, but only the disappearing tile ships here.
- Swap preview/warning, the Soul system, the real HUD, client-side hazard VFX beyond the replicated part properties.
- Server-side movement validation (anti-cheat).
- Multiple maps; this is the single MVP arena.
- The proposed No-Doom Assignment Rule (GDD §12).

## Design decisions (resolved during brainstorming)

1. **Shallow kill plane via geometry, reusing the void monitor unchanged.** Death is purely geometric: a `gone` tile has `CanCollide = false`, the body falls, and the **existing** void monitor eliminates it via `eliminateFromHazard` when its root crosses `VOID_Y`. To make that death quick enough for the grace window (1.5s) to matter, `VOID_Y` is raised from `-50` to `-4` — just under the tile bottoms — so fall-through crosses it in ~0.6s. No new death path, no `Touched` handler, no monitor change. (Rejected: a dedicated kill plane with hazard-owned `Touched`/region death detection, which duplicates a death path that already exists and works; and leaving tiles high over the old `-50` void, which makes the ~1.8s fall outlast the grace window so grace barely interacts with the hazard.)
2. **Independent staggered cycles, deterministic — no RNG.** Each tile loops on one shared period, distinguished only by a per-tile phase `offset`. Phase is a pure function of `(now, roundStart, offset, durations)`. (Rejected: a random scheduler, which needs an injected RNG/seed to stay testable; and a sweeping-wave pattern, which reads as scripted rather than the GDD's "floor is lava" chaos.)
3. **Round-start safety from one constraint.** Every tile's `offset ∈ [0, solid)`, so at `now == roundStart` every tile is `solid` (`t = offset < solid`). The whole floor is guaranteed solid at the start of each round, then drifts into `warning`/`gone` staggered over the first `solid` seconds. This also gives freshly-spawned players orientation time with no special case. The offset is derived deterministically from each tile's `(row, col)` so the pattern is identical every round — learnable and testable.
4. **Full tile-field arena.** The entire floor is disappearing tiles (no safe parking spot), satisfying GDD §5's "passive parking isn't viable" and maximizing swap-inheritance tension. There is no separate outer void; falling through any tile is the death.
5. **Server-authoritative visuals, no client module.** Tile `Color` / `Transparency` / `CanCollide` are ordinary part properties that replicate to every client for free when the server sets them. The red telegraph is therefore server-authoritative with zero client code — matching how the project defers client visuals. (Rejected: a client `HazardController` rendering the warning, which is pure overhead and makes a gameplay-critical telegraph client-trusted.)
6. **Pure model owns no Roblox, decides only phase.** `TileFieldModel` returns `"solid" | "warning" | "gone"` and nothing about parts, collision, color, or death — the same single-responsibility split as `GraceModel`. The server maps phase → part properties; death stays geometric.

## Components

| Module | Change | Responsibility |
|--------|--------|----------------|
| **`TileFieldModel`** (`src/shared/TileFieldModel.luau`, new) | new | Pure, time-injected. `phaseAt(now, roundStart, offset, durations)` → tile phase; a deterministic `offsetFor(row, col, solid)` helper. Knows nothing about Roblox, parts, or death. Lune-tested. |
| **`HazardSystem`** (`src/server/HazardSystem.luau`, new) | new | Server glue. `build()` (remove baseplate, construct the tile grid once, store per-tile offsets), `start(roundStart)` (force solid, run the token-gated apply loop), `stop()` (kill loop, force solid). Owns all Roblox APIs the hazard touches. |
| **`Config`** (`src/shared/Config.luau`) | edit | New tile tunables (timing, grid size, tile size, surface Y, thickness, colors); raise `VOID_Y` to `-4` with an updated comment. |
| **`RoundManager`** (`src/server/RoundManager.luau`) | edit | Three hooks: `HazardSystem.build()` is invoked at startup (via `init.server`), `HazardSystem.start(os.clock())` in `beginRound` after `resetControl`, `HazardSystem.stop()` in `endRound`. Death path, void monitor, grace gate, parking, spectate unchanged. |
| **`init.server`** (`src/server/init.server.luau`) | edit | Call `HazardSystem.build()` once at startup so the arena exists before the first round. |

## `TileFieldModel` interface

```lua
-- durations = { solid = number, warning = number, gone = number }   (seconds)

-- Phase of a single tile at time `now`, given the round's start time and the
-- tile's fixed phase offset. Pure: no Roblox, no clock, no RNG.
function TileFieldModel.phaseAt(now, roundStart, offset, durations) -> "solid" | "warning" | "gone"
    local period = durations.solid + durations.warning + durations.gone
    local t = (now - roundStart + offset) % period
    if t < durations.solid then
        return "solid"
    elseif t < durations.solid + durations.warning then
        return "warning"
    else
        return "gone"
    end
end

-- Deterministic per-tile offset in [0, solid): identical every round, so the
-- floor is solid at roundStart and the drop pattern is learnable. Pure hash of
-- the tile's grid coordinates; no RNG.
function TileFieldModel.offsetFor(row, col, solid) -> number   -- in [0, solid)
```

## Data flow

```
STARTUP (server):
  init.server → HazardSystem.build()
      → remove Workspace.Baseplate
      → construct TILE_GRID_SIZE² anchored tiles under Workspace/TileField,
        each storing offsetFor(row, col, solid)

ROUND START (server):
  RoundManager.beginRound() → ... resetControl() → HazardSystem.start(os.clock())
      → force all tiles solid; spin token-gated loop (~0.1s):
            for each tile:
              phase = TileFieldModel.phaseAt(os.clock(), roundStart, tile.offset, durations)
              if phase changed: apply
                  solid   → CanCollide=true,  Transparency=0, Color=grey
                  warning → CanCollide=true,  Transparency=0, Color=red
                  gone    → CanCollide=false, Transparency=1

DEATH (unchanged — existing void monitor):
  body over a `gone` tile falls → root.Position.Y < VOID_Y (now -4, ~0.6s)
      → RoundManager.eliminateFromHazard(player)   ← grace-gated, already built

ROUND END (server):
  RoundManager.endRound() → HazardSystem.stop()
      → kill loop; force all tiles solid (clean Lobby/Ended floor; parked bodies rest)
```

## Geometry and the shallow kill plane

| Value | Setting | Rationale |
|-------|---------|-----------|
| Tile surface `Y` | `0` | Top of the tile field. |
| Tile thickness | `1` | Bottoms at `Y = -1`. |
| `VOID_Y` | `-50` → **`-4`** | Just under the tile bottoms. A body standing on a tile (root ≈ `Y 2`) sits ~6 studs above it; falling through a `gone` tile crosses `-4` in ~0.6s, inside the 1.5s grace window. Still far above `FallenPartsDestroyHeight` (`-500`). |
| `SPAWN_ORIGIN.Y` | `5` (unchanged) | Round-start bodies settle onto the solid floor from just above it. |

Because the whole arena is tiles, there is no separate outer void; `VOID_Y` is now purely the under-tile kill plane.

## New `Config` tunables

```lua
Config.TILE_SOLID_SECONDS   = 4        -- standable time per cycle
Config.TILE_WARNING_SECONDS = 2        -- red telegraph (GDD §5: "red 2s before")
Config.TILE_GONE_SECONDS    = 1.5      -- vanished window
Config.TILE_GRID_SIZE       = 8        -- 8×8 = 64 tiles
Config.TILE_SIZE            = 8        -- studs per tile → 64×64 arena
Config.TILE_SURFACE_Y       = 0
Config.TILE_THICKNESS       = 1
Config.TILE_COLOR_SOLID     = Color3.fromRGB(150, 150, 150)  -- neutral grey
Config.TILE_COLOR_WARNING   = Color3.fromRGB(200,  40,  40)  -- alarm red
-- VOID_Y raised from -50 to -4 (see Geometry).
```

Tile durations are grouped into the `durations` table the model expects when `HazardSystem` calls `phaseAt`.

## Testing strategy

**Pure model — lune** (`tests/tile_field_model.spec.luau`):
- `phaseAt` returns `"solid"` at `t = 0` (`now == roundStart`) for any `offset ∈ [0, solid)` — the round-start-safety invariant.
- Exact phase boundaries: just before/after `solid` → `solid`/`warning`; just before/after `solid + warning` → `warning`/`gone`; wrap at `period` returns to `solid`.
- A non-zero `offset` shifts the phase timeline by exactly `offset`.
- Monotonic progression `solid → warning → gone → solid` across one full period.
- `offsetFor` is deterministic (same coords → same value) and always in `[0, solid)`.

**Runtime — Studio smoke test** (new `docs/smoke-tests/2026-06-19-disappearing-tile-smoke-test.md`, 2-client): tiles telegraph red then vanish; a body standing on a vanished tile falls through and is eliminated; round-start floor is fully solid; round-end floor returns to solid; and a `RoundManager.forceSwap()` onto a `warning` tile confirms the grace window protects the body for the beat before it can be eliminated. Physics, part replication, and the apply loop are exactly what lune cannot cover, matching the project's test split.

## Definition of done

- `TileFieldModel` exists as a pure module with passing lune tests covering the cases above.
- `HazardSystem` builds the full tile-field arena at startup, removes the baseplate, and drives tile phases server-side during Active rounds.
- A body that falls through a vanished tile is eliminated through the existing grace-gated void path; no new death code was added.
- The round-start floor is fully solid; the round-end floor returns to solid.
- The Studio smoke test passes and is recorded.
- GDD §13 item 8 and TDD §10 / §1 hazard rows move from 🟡 toward 🟢 with accurate annotations.
