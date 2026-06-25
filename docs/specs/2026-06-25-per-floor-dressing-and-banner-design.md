# Per-Floor Arena Dressing + Banner Redesign (Slice 1 polish)

**Date:** 2026-06-25
**Status:** Design approved — ready for implementation plan
**Type:** Feature design (world / environment art) — extends Slice 1
**Builds on:** [Broadcast World Shell spec](2026-06-25-broadcast-world-shell-design.md) · [roadmap](../../world-enrichment-roadmap.md)

---

## 1. Motivation

Slice 1 dresses only the **top** hex floor (4 corner torches + a 12—now—orb ring + the banner). The Hex-A-Gone arena has **7 stacked floors** (Y = 0, −50, … −300) that players descend through, but the lower six are bare. This polish pass:

1. Puts **torches and an orb ring on every floor**, so descending the pit stays visually rich.
2. Makes **each torch's light match its floor's color** (`HEX_FLOOR_COLORS`).
3. Adjusts counts/spacing so seven dressed floors read as depth, not clutter.
4. **Redesigns the "Body Swap Royale" banner** into a framed marquee header that's integrated with the lobby instead of a plain floating bar.

### Decisions locked during brainstorming
- **Torch light strategy (perf):** Option #1 — every torch glows its floor color via **Neon head**; **real dynamic `PointLight`s are budget-capped to the top N floors** (default 3). Deep floors are Neon-only. Rationale: 28 dynamic lights would be culled by the engine, force Voxel re-lights every time an eroding tile vanishes near them, bleed color across the 50-stud floor gaps, and hurt mobile.
- **Torches are short posts (~12 studs), not 60-stud masts** — a 60-stud pole would stab through the floor above (floors are 50 apart). This also changes the **top floor** from tall masts to short torches, for cross-floor consistency.
- **Banner:** Option A — a framed marquee header (glowing frame, gradient backing, outlined FredokaOne title, "ON AIR" pill, ✦ accents), **mounted on support posts at the balcony's front edge** facing the waiting players (integrated with the lobby, not floating).
- **Architecture:** extend `ArenaDescriptor` with a `levels` list so per-floor dressing stays arena-agnostic (the hex arena publishes 7 levels; a flat arena would publish one). No slice may read `HEX_*` from `ArenaDressing`.

---

## 2. Architecture — extend the `ArenaDescriptor` contract

Add a `levels` field to the descriptor; everything else is unchanged and backward-compatible.

```lua
ArenaDescriptor = {
    center    : Vector3,                       -- unchanged (top play surface)
    footprint : Vector2,                       -- unchanged (X,Z extent)
    depth     : number,                        -- unchanged
    accent    : Color3,                        -- unchanged (== levels[1].color)
    levels    : { { y: number, color: Color3 } },  -- NEW: one per dressable floor, top→bottom
}
```

- `ArenaDescriptor.hex()` populates `levels` from Config: for `k = 0 .. HEX_FLOOR_COUNT-1`, `y = TILE_SURFACE_Y - k*HEX_FLOOR_GAP`, `color = HEX_FLOOR_COLORS[k+1]`. `accent` stays `levels[1].color`.
- `ArenaDescriptor.validate(desc)` additionally asserts `levels` is a non-empty array whose entries have a `Vector*`-free `y` number and a `Color3` `color`.
- `ArenaDressing` iterates `desc.levels`. An arena with a single level dresses one floor — no special-casing.

---

## 3. Components

### 3.1 Per-floor torches (`ArenaDressing`)

For each level, build **4 torches** at the footprint corners (`WorldLayout.footprintCorners`, reused):

- **Post:** a short anchored part, `WORLD_TORCH_POST_HEIGHT` (~12) tall, dark metal, base sitting on the level's `y`.
- **Flame head:** a Neon part on top, **tinted to `level.color`** — this is what makes every floor's torch read in its floor color (free, all 7 floors).
- **Real light (budget-capped):** only for the first `WORLD_TORCH_LIT_FLOORS` levels (default 3): a `PointLight` colored `level.color`, modest `Range`/`Brightness`. Deeper floors get **no** dynamic light.
- **Flame particles (budget-capped):** also only on the lit (top N) floors — a low-rate `ParticleEmitter` in `level.color`. Deep floors stay Neon-only so the **mobile particle budget** isn't blown by 28 emitters.

### 3.2 Per-floor orb ring (`ArenaDressing`)

For each level, a ring of **`WORLD_NEAR_ORB_COUNT` = 12** (reduced from 18) soul-palette Neon ball orbs at radius `WORLD_NEAR_ORB_RADIUS`, centered on the level, at `level.y + WORLD_NEAR_ORB_Y`. Orbs are soul-palette colored (unchanged intent), distinct from the floor-colored torches.

### 3.3 Redesigned banner (`ArenaDressing.buildBanner`, replaces `buildMarquee`)

A **framed marquee header** mounted at the balcony's arena-facing front edge, facing the waiting players (−Z `Front` face), held up by **two support posts** rising from the balcony so it's integrated, not floating:

- **Panel:** a part sized `WORLD_BANNER_SIZE`, at the front-edge Z, `WORLD_BANNER_HEIGHT` above the balcony surface.
- **SurfaceGui face:** a `Frame` with `UICorner` (rounded) + `UIStroke` (glowing `WORLD_BANNER_FRAME_COLOR`) + `UIGradient` backing (`WORLD_BANNER_BG_TOP`→`BG_BOTTOM`); the title `TextLabel` (FredokaOne, `WORLD_BANNER_TEXT_COLOR`) with a `UIStroke` outline; a small rounded **"★ ON AIR ★" pill** label; and ✦ accent labels in the corners.
- **Posts:** two thin parts (`WORLD_BANNER_POST_COLOR`) from the balcony surface up to the panel.

---

## 4. Config changes

Replace the `WORLD_SPOTLIGHT_*` block (tall-mast params) with `WORLD_TORCH_*`, retune the orb count, and add `WORLD_BANNER_*`:

```lua
-- Per-floor torches (short posts; Neon head = floor color on all floors;
-- real light + flame particles only on the top WORLD_TORCH_LIT_FLOORS floors).
Config.WORLD_TORCH_MARGIN = 14          -- studs outward from footprint corners
Config.WORLD_TORCH_POST_HEIGHT = 12     -- short post (< HEX_FLOOR_GAP 50 so it can't pierce the floor above)
Config.WORLD_TORCH_HEAD_SIZE = 3
Config.WORLD_TORCH_LIT_FLOORS = 3       -- top N floors get a real PointLight + flame particles (perf dial)
Config.WORLD_TORCH_LIGHT_RANGE = 34     -- < HEX_FLOOR_GAP so light doesn't bleed across floors
Config.WORLD_TORCH_LIGHT_BRIGHTNESS = 2
Config.WORLD_TORCH_FLAME_RATE = 6       -- particles/sec per lit torch (kept low for the mobile budget)

-- Orb ring per floor (soul-palette). Reduced from 18 so seven stacked rings aren't soup.
Config.WORLD_NEAR_ORB_COUNT = 12        -- (retune of the existing key)

-- Framed marquee header (banner), mounted on posts at the balcony front edge.
Config.WORLD_BANNER_TEXT = "BODY SWAP ROYALE"   -- (renamed from WORLD_MARQUEE_TEXT)
Config.WORLD_BANNER_SIZE = Vector3.new(64, 16, 2)
Config.WORLD_BANNER_HEIGHT = 14                 -- studs above the balcony surface
Config.WORLD_BANNER_FRAME_COLOR = Color3.fromRGB(255, 216, 77)   -- glowing amber frame
Config.WORLD_BANNER_BG_TOP = Color3.fromRGB(36, 16, 72)
Config.WORLD_BANNER_BG_BOTTOM = Color3.fromRGB(22, 10, 46)
Config.WORLD_BANNER_TEXT_COLOR = Color3.fromRGB(255, 216, 77)
Config.WORLD_BANNER_POST_COLOR = Color3.fromRGB(40, 40, 50)
```

The existing `WORLD_NEAR_ORB_RADIUS`, `WORLD_NEAR_ORB_Y`, `WORLD_NEAR_ORB_SIZE` keys are reused. The old `WORLD_MARQUEE_SIZE`/`WORLD_MARQUEE_HEIGHT`/`WORLD_SPOTLIGHT_*` keys are removed (migrated to the above).

---

## 5. Performance

- **Dynamic lights:** `WORLD_TORCH_LIT_FLOORS × 4` = **12** (default), not 28. Range kept under the floor gap so no cross-floor bleed and smaller voxel footprint. This is the primary perf dial.
- **Particles:** flame emitters only on the lit floors (≤ 12 low-rate emitters) to respect the mobile particle budget.
- **Geometry:** ~28 torch posts/heads + ~84 orbs are all anchored, `CanCollide=false`, cheap parts. No new per-frame loops (orbs/torches are static; only the existing wisp + crowd Heartbeats run).
- Still 100% client-cosmetic; zero server cost, zero replication.

---

## 6. Testing

- **Pure math:** none new required (`WorldLayout.footprintCorners`/`ring` already lune-tested). The full lune suite must stay green.
- **Visual (Studio MCP):** `screen_capture` confirming — torches on all 7 floors glowing their floor color; real light only on the top 3; orb rings per floor; no posts piercing the floor above; the redesigned framed banner legible from the balcony. `get_console_output` clean.
- **Smoke test:** update the Slice 1 smoke-test doc with the per-floor + banner checks (incl. a mobile/perf glance, since lights/particles changed).

---

## 7. Scope boundary

**In:** per-floor torches + orb rings via the `levels`-extended descriptor; floor-colored torch light (budget-capped); the framed marquee header banner; Config migration.

**Out (unchanged from the roadmap):** Slice 2 (lobby hybrid rebuild), Slice 3 (hex pit hybrid re-skin), Slice 4 (live jumbotron/confetti — the banner is *static* here), Slice 5 (activities). The distant soul-orb crowd and wisps/aurora from Slice 1 are untouched.

---

## 8. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Even 12 lights + erosion re-lights hitch on mobile | `WORLD_TORCH_LIT_FLOORS` dial (drop to 2 or 0); range < floor gap shrinks voxel cost; verify in the smoke test. |
| 28 flame emitters blow the particle budget | Flames only on the lit top-N floors; low `WORLD_TORCH_FLAME_RATE`. |
| Torch posts clip the floor above | `WORLD_TORCH_POST_HEIGHT` (12) ≪ `HEX_FLOOR_GAP` (50). |
| Banner SurfaceGui face wrong way again | Mounted at the front edge facing −Z (the balcony viewers), as verified for the current marquee. |
| Coupling per-floor dressing to hex geometry | `levels` lives in the descriptor; `ArenaDressing` never reads `HEX_*`. |

---

*End of design — Slice 1 polish (per-floor dressing + banner redesign).*
