# Arena Cosmetic Dim + Soul-Halo Toggle — Design Spec

**Date:** 2026-07-12
**Status:** Approved (brainstormed; design approved before spec)
**Branch:** `feat/arena-dim-soul-toggle` off `main` (`e1eb26e`)

Two small, independent visual changes requested together:

1. **Soul-halo toggle** — a config flag to disable the over-head Soul identity
   halo, primarily to take clean marketing screenshots without deleting the
   system.
2. **Global cosmetic dim** — soften ALL decorative arena glow to a dim,
   LED-like level via one arena-agnostic knob, WITHOUT dimming gameplay-critical
   tells.

Constraint reminder: never stage `src/shared/Config.luau`'s dev flips
(`SOLO_TEST_MODE`, `ARENA_OVERRIDE`) — commit only the intended additions to it.
Zero client→server remotes. Arena-agnostic (no per-arena special cases).

---

## REVISION 2026-07-12b — per-effect knobs (SUPERSEDES the single `ARENA_GLOW_DIM`)

Follow-up request: replace the one global `Config.ARENA_GLOW_DIM` with an
**independent dim knob per visual effect**, for fine-grained manual tuning. The
`GlowDim` module and the halo toggle (Part 1) are unchanged. Part 2 below is
superseded by this section.

**Every knob defaults to `0.0` (no dim) — reproducing the ORIGINAL pre-branch
look exactly** (`GlowDim.apply(base, 0) = base`). The feature ships as a no-op;
the user dials each effect up to dim it. This also avoids the dormancy-inversion
at defaults (raw shaft 0.8 < raw standby 0.85).

Two effects are **gameplay tells** built server-side; per the approved choice
they get knobs too but default to `0.0` (full brightness — no readability
regression unless deliberately tuned). This adds server-file edits
(`SweeperHazard`, `HazardSystem`), a first for this feature.

| Config knob | Controls | File | Mechanism |
|---|---|---|---|
| `GLOW_DIM_WISPS` | sky soul-wisps | WorldShell | Neon transparency |
| `GLOW_DIM_AURORA` | aurora ribbon + swap flare | WorldShell | Neon transparency |
| `GLOW_DIM_CROWD` | distant crowd orbs | WorldShell | Neon transparency |
| `GLOW_DIM_LOBBY_RINGS` | lobby energy rings | LobbyStage | Neon transparency |
| `GLOW_DIM_SPECTATOR_ORBS` | lobby spectator orbs | LobbyStage | Neon transparency |
| `GLOW_DIM_HEX_TRIM` | hex floor edge-trim | ArenaDressing | Neon transparency |
| `GLOW_DIM_SWEEP_WAKE` | sweeper wake channels | SweeperController | Neon transparency |
| `GLOW_DIM_SWEEP_CHASE` | sweeper rim chase studs | SweeperController | Neon transparency |
| `GLOW_DIM_SWEEP_ROTOR` | sweeper rotor bars | SweeperController | Neon transparency |
| `GLOW_DIM_SWEEP_SHAFT` | sweeper light shaft | SweeperController | Neon transparency |
| `GLOW_DIM_SWEEP_LENS` | sweeper spotlight lenses | SweeperController | Neon transparency |
| `GLOW_DIM_SWEEP_RIM` | sweeper rim accent bars | SweeperController | Neon transparency |
| `GLOW_DIM_SWEEP_DORMANT` | idle-sweeper standby dim | SweeperController | Neon transparency |
| `GLOW_DIM_SWEEP_KILL_TELLS` | **tell:** blade/underglow/emitter/lamps | SweeperHazard (server) | Neon transparency |
| `GLOW_DIM_HEX_WARNING` | **tell:** hex tile warning color | HazardSystem (server) | color darken → black |

**Mechanism details:**
- Transparency knobs: `part.Transparency = GlowDim.apply(<base>, Config.<knob>)`
  at each site. Bases are the current raw values (wisp/crowd/trim/kill-tells = 0;
  aurora = `WORLD_AURORA_*`; lobby = `LOBBY_BEY_GLOW_TRANSPARENCY`; sweeper = the 8
  named accent literals; dormant = `SWEEP_STANDBY_TRANSPARENCY`).
- `GLOW_DIM_HEX_WARNING` is the one non-transparency knob: the warning is
  `Config.TILE_COLOR_WARNING` on an opaque floor tile, so dimming darkens the
  COLOR via `Config.TILE_COLOR_WARNING:Lerp(Color3.new(), Config.GLOW_DIM_HEX_WARNING)`
  (0 = full red, 1 = black). Precomputed once at module load in `HazardSystem`.
- `GLOW_DIM_SWEEP_DORMANT`: `DORMANT_TRANSPARENCY = GlowDim.apply(
  Config.SWEEP_STANDBY_TRANSPARENCY, Config.GLOW_DIM_SWEEP_DORMANT)` replaces the
  old global-dim coupling; keeping a dormant arena dimmest is now the user's tuning
  responsibility (raise this if a heavily-dimmed live element out-fades it).
- `WorldShell.glowOrb` gains a `dimFactor` param so wisps and crowd (which share
  the helper) can take different knobs.

The old single `Config.ARENA_GLOW_DIM` is REMOVED.

---

## Part 1 — Soul-halo toggle

**What:** The over-head "soul orb" is the free Soul identity halo — a small
`AlwaysOnTop` colored `BillboardGui` dot rendered above each controlled body's
Head by `src/client/SoulController.luau` (42px emphasized for your own body,
24px for others). It also drives the post-swap grace shimmer.

**Design:** Add `Config.SOUL_HALO_ENABLED = true`. In `SoulController.start()`,
early-return when the flag is false so no `SoulMap`/`SetControlledBody`
listeners are connected and no halos are built. Default `true` keeps live
gameplay identical; flipping to `false` (a dev flip like `SOLO_TEST_MODE`, but
this one is a real committed default) gives a halo-free screenshot state.

**Screenshot guidance (documented, not enforced):** turn the halo OFF for
single-character hero/beauty shots (it reads as a floating UI pip / artifact in
a still); leave it ON for multi-body gameplay/mechanic thumbnails where the
colored halos communicate the swap-identity hook.

**Scope note:** the flag gates the entire `SoulController` (halo + its grace
shimmer). The server's authoritative grace gate is untouched; only the client
cosmetic shimmer goes away with the halo. Acceptable — this flag is a
screenshot/dev convenience, and disabling it during real play is not intended.

## Part 2 — Global cosmetic dim

**Key structural fact:** gameplay-critical tells are already built server-side
and are NOT touched by this change:
- Sweeper kill tells (amber blade / crimson underglow / end emitters) —
  `src/server/SweeperHazard.luau`.
- Hex tile warning/erosion colors (solid → warning → gone) —
  `src/server/HazardSystem.luau`.

All DECORATIVE glow is built client-side in four files and is the only thing
dimmed:
- `src/client/WorldShell.luau` — soul-wisps, aurora, distant crowd orbs.
- `src/client/LobbyStage.luau` — beyblade energy rings + spectator-soul orbs.
- `src/client/ArenaDressing.luau` — hex floor Neon edge-trim bars.
- `src/client/SweeperController.luau` — wake strips, rim chase studs, rotor
  bars, light shaft, spotlight lenses (all "accent level").

**Mechanism:** Neon emits softer as its part `Transparency` rises toward 1 —
the lever the codebase already uses to dim (e.g. `LOBBY_BEY_GLOW_TRANSPARENCY`,
`SWEEP_STANDBY_TRANSPARENCY`). We apply a single global dim factor to every
cosmetic Neon transparency value.

**Design:**
- New `Config.ARENA_GLOW_DIM` (number in `[0, 1]`; `0` = today's brightness,
  `1` = fully faded/invisible). Starting default **0.4**, tuned by eye in Studio.
- New pure module `src/shared/GlowDim.luau` with one function:
  `GlowDim.apply(baseTransparency, factor)` → `baseTransparency + (1 - baseTransparency) * factor`.
  Monotonic, and clamps `factor` to `[0, 1]` and the result to `[0, 1]`.
  Roblox-free, lune-tested (`tests/glow_dim.spec.luau`).
- Every cosmetic Neon transparency endpoint in the four client files is passed
  through `GlowDim.apply(base, Config.ARENA_GLOW_DIM)`. This includes the
  sweeper's ANIMATED endpoints (wake target, chase lit/base, dormancy resets)
  so the dim holds during animation, and the lobby's existing
  `LOBBY_BEY_GLOW_TRANSPARENCY` base.

**Why not the alternatives:**
- Global Bloom/Exposure reduction dims everything in one line but also dims the
  server-side kill tells and tile warnings — the readability/fairness regression
  the design explicitly avoids.
- Hand-bumping each arena's transparency constants individually drifts
  arena-to-arena and is not one coherent, arena-agnostic knob.

**Robustness (the tell-preservation guarantee):** because the four edited files
contain ONLY decorative Neon and the tells live in server modules this change
never opens, there is no code path by which a tell is dimmed. Adding a new
arena later inherits the dim for free by routing its cosmetic Neon through
`GlowDim.apply`, and preserves its tells for free by building them like the
existing server-side tells.

---

## Files touched

| File | Change |
|---|---|
| `src/shared/Config.luau` | + `SOUL_HALO_ENABLED = true`, + `ARENA_GLOW_DIM = 0.4` |
| `src/shared/GlowDim.luau` | NEW — pure `apply(base, factor)` |
| `tests/glow_dim.spec.luau` | NEW — lune unit tests |
| `src/client/SoulController.luau` | early-return when `SOUL_HALO_ENABLED` is false |
| `src/client/WorldShell.luau` | route wisp/aurora/crowd Neon transparency through `GlowDim.apply` |
| `src/client/LobbyStage.luau` | route ring/orb Neon transparency through `GlowDim.apply` |
| `src/client/ArenaDressing.luau` | route hex trim Neon transparency through `GlowDim.apply` |
| `src/client/SweeperController.luau` | route all cosmetic Neon transparency (incl. animated endpoints) through `GlowDim.apply` |

## Verification

- **Lune:** `tests/glow_dim.spec.luau` — endpoints (`factor 0` → base, `factor 1`
  → 1), monotonic in factor, clamps out-of-range factor, result stays in `[0,1]`.
  All existing suites remain green.
- **Studio (manual):** visual pass across hex + sweeper + lobby confirming
  (a) dressing reads dim/soft LED, (b) sweeper kill tells + hex warning tiles
  remain full-brightness, (c) tune `ARENA_GLOW_DIM` to taste; and a halo on/off
  Play-Solo check via `SOUL_HALO_ENABLED`.

## Out of scope

Premium Soul VFX, floor-ring Soul cosmetics, any server-side lighting change,
Bloom/atmosphere retuning, per-arena distinct dim levels, thumbnail capture
itself (separate marketing slice).
