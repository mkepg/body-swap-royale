# Soul Sweeper T4 Visual Glow-Up — Design Spec (2026-07-13)

## §1 Goal & source of truth

Make the real Soul Sweeper arena match the shipped T4 thumbnail reference
**`docs/marketing/thumbnails/candidates/gemini-t4-master-1.png`** as closely as
possible — overall appearance, layout, atmosphere, lighting, colors, materials,
and polish — **while preserving all existing gameplay and functionality** (swap
loop, bar physics/strike math, fall-gap hazard, dormancy, arena rotation).

"Play what you see": players who click the T4 thumbnail must land in that arena.

Decisions locked during brainstorm (visual companion session, all user-confirmed):

1. **Cosmetics fate = option B:** delete chase studs, rotor rings, light shaft,
   spotlight fixtures, rim accent bars, and the sweeper's ArenaDressing edge
   trim; the wake beat survives by **fusing into the permanent seam lines**
   (seams idle dim, flare as the low bar sweeps past).
2. **Bars = layered construction:** the glow is a core **inset in a dark
   shell** — dark structural rails along the top and bottom edges frame the
   emissive center. Not a bare neon rod.
3. **Hub = stacked column with glass-encased lantern:** flared base skirt,
   two stacked drums with a shadow groove, high-bar ledge, **glass cylinder
   lantern** (visible transparent walls, air gap) around an amber Neon core
   with a PointLight, dark bezel rings, rounded top cap. Fall-gap moat stays
   open and gets a faint amber inner-rim readability line.
4. **Disc = 12 wedges:** permanent amber neon radial seams (hole → rim) over
   the glossy dark disc, continuous amber rim ring on the outer edge face,
   faint moat line at the hole edge.

## §2 Reference reading (what "match" means)

From `gemini-t4-master-1.png` (plus zoom crops studied during brainstorm):

- **Disc:** near-black indigo, glossy (reflects the bar glows), read as ~12
  pie wedges separated by amber neon seam lines running hub → rim.
- **Rim:** one continuous bright amber band around the outer edge face,
  casting warm underglow.
- **Hub (bottom → top):** wide flared dark skirt at the foot; two stacked dark
  drums with a horizontal shadow groove; a thin wider ledge; a **clear glass
  cylinder** with specular highlights encasing a brilliant amber core (visible
  air gap, dark bezel rings clamping top and bottom); dark rounded cap.
- **Low bar (amber/JUMP):** emissive amber core the full span, dark rail along
  the top edge, darker bronze rail along the bottom edge, rounded glowing tip
  at the rim end, dark collar at the hub.
- **High bar (crimson/STAY GROUNDED):** same construction in crimson — dark
  top rail, bright crimson core face, deep maroon under-rail, rounded tip.
- **Atmosphere:** dusk gradient sky, sun at horizon, cyan soul wisps, faint
  aurora — **already shipped** by the world-enrichment slices (T4's prompt was
  ground-truthed from the live game). No sky/lighting service changes in this
  slice; any color deltas are handled by the element colors above.

## §3 What is built today (delta baseline)

- Server `SweeperHazard`: 48-segment collision annulus (dark indigo,
  `SweeperStageFloor` MaterialVariant on Metal), plain metal hub pillar
  (collidable r=6, the beam-motor axle), bars = dark Metal spine + welded
  dressing (low: housing top + amber Neon underside blade + end emitter ball;
  high: crimson underglow strip + twin end lamps) + hub collar, hinge motors.
- Client `SweeperController` (`SweeperDressing` folder): 36 wake channels,
  32 chase studs, 2×8 rotor rings, HubMesh hybrid hook (unused), light shaft,
  under-structure struts + lower ring, 3 spotlight fixtures (housing + lens),
  48 rim accent bars, EditableMesh smooth annulus (hides the segmented floor
  locally), dormancy sync (`LiveArena` attribute), one Heartbeat loop,
  part-budget assert (≤180).
- Client `ArenaDressing`: descriptor-driven Neon edge trim per arena
  (sweeper's carried via `trimDim`).

## §4 Design

### §4.1 Server — SweeperHazard bar dressing rewrite (layered bars)

The **spine root part is untouched in size, pose, physics, name, and role**
(strike math, kill band, measured angle, hinge, network ownership all read it).
Only its *appearance* and the welded dressing change.

- **Emissive core = the spine itself:** `Material = Neon`,
  `Color = SWEEP_BEAM_LOW_COLOR / SWEEP_BEAM_HIGH_COLOR`,
  `Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)`.
  Hitbox↔visual alignment is exact by construction: the glowing body IS the
  part the kill band derives from (v2.4 invariant strengthened).
- **Delete** the old dressing parts: `_Housing`, `_Blade`, `_Emitter`,
  `_Underglow`, both `_Lamp`s.
- **Top rail (both classes):** dark strip welded along the top edge.
  Size `(span − capDiameter) × RAIL_THICK × (thick + 0.3)`, RAIL_THICK = 0.25,
  color `SWEEP_RAIL_COLOR` (dark indigo, same family as the disc),
  `Material = SmoothPlastic`, offset `+ (thick/2 + RAIL_THICK/2)` local Y.
- **Under-rail (both classes):** mirror of the top rail at
  `− (thick/2 + RAIL_THICK/2)`, color per class:
  `SWEEP_BEAM_LOW_UNDERRAIL_COLOR` (bronze) / `SWEEP_BEAM_HIGH_UNDERRAIL_COLOR`
  (deep maroon).
- **End cap:** Neon Ball, diameter = `thick`, class color, same kill-tell
  transparency, welded at the rim tip (`+span/2` local X). Rails stop short of
  it (hence `span − capDiameter` length). Replaces emitter/lamps.
- **Collar:** kept as-is (dark, at the hub).
- **Envelope invariants (fairness):**
  - No dressing part extends past the spine's vertical extent by more than
    0.3 studs (the current underglow's precedent; rails add 0.25).
  - High-bar visual underside = `5.5 − 0.25 = 5.25` studs, no worse than
    today's `5.2` (underglow strip) — grounded clearance unchanged in practice.
  - Low-bar visual top = `0.6 + 1.0 + 0.25 = 1.85` studs — jumpable unchanged.
  - All dressing stays `CanCollide = false`, `Massless = true`, welded.

### §4.2 Client — SweeperController rewrite

**Deleted** (with their constants, Heartbeat branches, and dormancy entries):
chase studs, rotor rings + spin animation, light shaft, spotlight fixtures,
rim accent bars, HubMesh hybrid hook (§3b — superseded by the built hub; the
place carries no HubMesh).

**Kept:** EditableMesh smooth annulus + local segment hide (the glossy disc),
under-structure struts + lower ring (reads "built" from below), dormancy
mechanism (`LiveArena` attribute, one-time flips), single Heartbeat loop,
measured-pose low-bar tracking, part-budget assert.

**New/refit elements:**

1. **Seam system (refit of wake channels):** `Config.SWEEP_SEAM_COUNT = 12`
   radial Neon strips, hole edge → rim (same span math as today's wake), width
   0.9, thickness 0.15, `y = surface + 0.05`, color `SWEEP_ACCENT`.
   - Idle: `SEAM_IDLE_TRANSPARENCY = GlowDim.apply(0.35, GLOW_DIM_SWEEP_SEAM)`
     — permanently visible dim amber (the reference's constant seams).
   - Flare: existing wake logic re-targeted — behind the low bar's measured
     angle within `SEAM_FLARE_WINDOW = 0.9` rad, transparency interpolates
     from `SEAM_FLARE_TRANSPARENCY = GlowDim.apply(0, GLOW_DIM_SWEEP_SEAM)`
     back to idle. Same change-threshold write suppression.
   - **Groove strips:** one dark strip under each seam (width 1.6, thickness
     0.12, `y = surface + 0.03`, `SWEEP_RAIL_COLOR`, SmoothPlastic) so seams
     read inset like the reference.
2. **Rim ring:** 48 tangent Neon segments (floor-chord construction, slack
   overlap) wrapped on the outer edge **face**: radius `PLATFORM_RADIUS + 0.2`,
   height 1.2, radial depth 0.4, `y center = surface − 0.55` (band top at
   `surface + 0.05`, flush with the deck), color `SWEEP_ACCENT`,
   transparency `GlowDim.apply(0, GLOW_DIM_SWEEP_RIM_RING)` — the brightest
   dressing element, per the reference. Replaces chase studs + rim accent bars
   + the ArenaDressing trim.
3. **Moat line:** same construction at the hole edge (radius
   `HOLE_RADIUS − 0.2`, 24 segments, height 0.5, depth 0.3), transparency
   `GlowDim.apply(0.5, GLOW_DIM_SWEEP_MOAT)` — the faint inner-rim readability
   line marking the fall-gap at play speed (user-confirmed over max fidelity).
4. **Hub stack** (all anchored, `CanCollide=false`, dark `SWEEP_RAIL_COLOR`
   family, Metal/SmoothPlastic; vertical cylinders use the Z-roll convention):
   - *Skirt:* two stacked cylinders (r 8.5 then 7.2) from below the surface
     (top at `surface + 0.2`) flaring down into the fall-gap. The moat stays
     open: skirt max radius 8.5 < hole radius 12.
   - *Drums:* two cylinders r 6.3 (y 0→3.3) and r 6.15 (y 3.5→6.8) with a
     recessed darker groove ring (r 5.95, y 3.3→3.5) between them.
   - *Ledge:* thin cylinder r 7.2, y 9.3→9.7 — **above the high-bar collar's
     sweep** (collar top ≈ y 9.0; must not visually intersect).
   - *Lantern:* outer **Glass** cylinder r 3.4, y 10.2→14.0,
     `Transparency = 0.45` (walls must render); inner **Neon** amber core
     r 2.3, y 10.5→13.7, `GlowDim.apply(0, GLOW_DIM_SWEEP_LANTERN)`; visible
     air gap between them; **PointLight** (amber, Brightness 2, Range 26) at
     the core's center, `Enabled` follows dormancy.
   - *Bezels:* dark rings r 3.8 at y 9.9→10.3 and y 13.9→14.3.
   - *Cap:* r 3.2 cylinder y 14.3→15.3 + smaller rounding disc r 2.6
     y 15.3→15.7.
   - The collidable r=6 pillar and the motor axle attachments are untouched;
     drum overhang (6.3 vs 6.0) is cosmetic-only and non-collidable.
5. **Dormancy:** static list = rim ring segments, moat segments, lantern core
   (+ PointLight.Enabled), groove strips excluded (non-Neon); seams reset like
   wake does today (idle vs dormant, resync flag). `SWEEP_STANDBY_TRANSPARENCY`
   override unchanged; all idle/lit values stay < 0.85 so dormancy still dims.
6. **Part budget:** ~12 seams + 12 grooves + 48 rim + 24 moat + ~12 hub +
   annulus + ~17 under-structure ≈ 126 → assert stays ≤ 180.

### §4.3 Client — ArenaDressing trim opt-out (arena-agnostic)

- `ArenaDescriptor` gains an optional `trim: boolean?` (default `true`).
  `ArenaDescriptor.sweeper()` sets `trim = false` and drops `trimDim`.
- `validate()`: `trimDim` required **iff** `trim ~= false`.
- `ArenaDressing.buildFloorTrim` skips descriptors with `trim == false`.
- Hex descriptor and its trim are unchanged. No arena-name checks anywhere —
  the flag rides the descriptor (arena-agnostic pattern preserved).

### §4.4 Config changes

**Deleted keys** (grep `src/ tests/ scripts/ docs/` for stragglers):
`SWEEP_WAKE_CHANNELS`, `SWEEP_CHASE_STUDS`, `GLOW_DIM_SWEEP_WAKE`,
`GLOW_DIM_SWEEP_CHASE`, `GLOW_DIM_SWEEP_ROTOR`, `GLOW_DIM_SWEEP_SHAFT`,
`GLOW_DIM_SWEEP_LENS`, `GLOW_DIM_SWEEP_RIM`, `GLOW_DIM_SWEEP_TRIM`.

**New keys** (defaults; all GlowDim knobs default 0.0 = full bright):
```
Config.SWEEP_SEAM_COUNT = 12
Config.SWEEP_RAIL_COLOR = Color3.fromRGB(24, 30, 56)
Config.SWEEP_BEAM_LOW_UNDERRAIL_COLOR = Color3.fromRGB(122, 74, 24)
Config.SWEEP_BEAM_HIGH_UNDERRAIL_COLOR = Color3.fromRGB(84, 18, 38)
Config.GLOW_DIM_SWEEP_SEAM = 0.0
Config.GLOW_DIM_SWEEP_RIM_RING = 0.0
Config.GLOW_DIM_SWEEP_MOAT = 0.0
Config.GLOW_DIM_SWEEP_LANTERN = 0.0
```
Kept: `GLOW_DIM_SWEEP_KILL_TELLS` (now dims the whole cores + caps),
`GLOW_DIM_SWEEP_DORMANT`, `SWEEP_STANDBY_TRANSPARENCY`, all `SWEEP_*` gameplay
keys, the `SWEEP_DISC_MATERIAL` hybrid mechanism.

**Visual-pass tunables** (adjust only during §6 iteration, with before/after
captures): `SWEEP_PLATFORM_COLOR` (reference reads slightly darker),
`SWEEP_ACCENT` (reference amber reads more golden), rail/underrail colors,
seam idle transparency, lantern PointLight brightness/range.

### §4.5 DEV-FLIP COMMIT HAZARD (process invariant)

`src/shared/Config.luau` currently carries uncommitted dev flips
(`ARENA_OVERRIDE = "sweeper"`, `SOLO_TEST_MODE = true`). **They must never be
staged or committed.** Any commit touching Config must stage hunks selectively
(`git add -p`-style) and then verify:
`git diff --cached src/shared/Config.luau | grep -E 'ARENA_OVERRIDE|SOLO_TEST_MODE'`
returns nothing. (The flips are convenient for the visual pass — leave them in
the working tree.)

## §5 Testing

- **All existing lune suites stay green** (26/26): strike math
  (`sweeper_model.spec`), `glow_dim.spec`, `world_layout.spec` are untouched
  by design; any test or script referencing a deleted Config key must be
  updated in the same task that deletes the key.
- No new pure module is introduced (seam flare reuses the existing inline
  client wake math; layout reuses `WorldLayout.ring`), so no new lune suite.
  If an implementer does extract pure logic, it gets a suite per the test
  workflow.
- Runtime checks are covered by the §6 visual pass + console error scan
  (`get_console_output`), since lune cannot exercise Roblox instances.

## §6 Verification — Studio MCP visual pass

1. Rojo serve is persistent (port 34872 in use = already running); verify
   Source markers before assuming a disconnect.
2. Studio Play solo (dev flips pin `sweeper` + solo start), let the round
   start so the arena is live.
3. `screen_capture` (editor viewport shows the 3D world in play; HUD/GUI is
   NOT capturable — do not attempt UI verification this way) from an angle
   approximating the reference (elevated three-quarter view, rim in frame).
4. Side-by-side against `gemini-t4-master-1.png` (push to the visual companion
   if the user wants to arbitrate) — check per element: disc gloss/color, seam
   count/brightness, rim ring, moat line, hub stack + glass lantern read,
   layered bars (dark rails visible framing the glow), end caps.
5. Tune §4.4 visual-pass tunables, max 2 iterations, re-capture each.
6. Sanity while in play: bars spin, kill tells read, no console errors, seams
   flare behind the low bar, dormancy flip when the round rotates to hex
   (or via a forced state if convenient).

## §6b Iteration 2 amendment (2026-07-14, user-directed after the first build)

Three refinements from an in-game review superseded parts of §4.2 items 2–3 and
the disc finish:

1. **True circles, not polygons.** The 48/24-segment tangent rings read jagged
   (overlapping chord ends). The rim + moat are now TWO EditableMesh true-circle
   meshes (180 sides): `DiscShell` = smooth disc annulus + rim fascia lips +
   moat lips (one dark-metal mesh, replaces the separate SmoothAnnulus), and
   `EdgeNeon` = rim belt + moat belt (one Neon mesh; both share
   `GLOW_DIM_SWEEP_RIM_RING`; `GLOW_DIM_SWEEP_MOAT` retired). Segmented rings
   remain only as the EditableMesh-less fallback.
   - Hard-won constraints (encoded as code comments): a MeshPart renders its
     LIVE EditableMesh (destroying the editable blanks the part); every live
     editable holds a slab of a small device-wide memory budget that LobbyStage
     already draws from — hence exactly TWO meshes; neon belt edges need a
     0.10-stud VERTICAL setback behind the lips (flush edges leave a sub-pixel
     glow sliver at grazing angles that rasterizes as a dashed line); lip tops
     sit flush with the deck (+0.02) so the metal edge catchlight doesn't read
     as a separate line.
2. **Embedded neon everywhere.** The glow must read recessed INSIDE dark metal,
   never laid on top: rim/moat belts sit 0.15/0.14 behind their lips; each seam
   strip gains two dark flank rails on its groove plate (flank tops 0.20 >
   strip top 0.125) — the same shell language as the bars.
3. **Premium dark-metal disc.** The rocky `SweeperStageFloor` MaterialVariant
   read like obsidian; default is now smooth `Metal` + `SWEEP_DISC_REFLECTANCE`
   (0.15) on shell and server floor segments (variant mechanism kept, `""` by
   default).

## §7 Out of scope

- Sky/lighting service changes (shipped world slices already match T4's
  atmosphere; T4 was ground-truthed from them).
- Hex arena, lobby, thumbnails/marketing assets, GDD §12 work.
- Any gameplay tuning (cadence, bands, speeds, kill math).
- The T4 thumbnail itself is NOT regenerated — the game moves toward it.

## §8 Execution process

Branch `feat/sweeper-t4-visual-glowup` (off `main`, already created). Plan via
writing-plans → subagent-driven execution (fresh subagent per task; spec review
+ code-quality review per task). CHANGELOG entry at the end. Never commit the
dev flips (§4.5).
