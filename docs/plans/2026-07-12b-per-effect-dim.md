# Per-Effect Dim Knobs — Implementation Plan (supersedes the global ARENA_GLOW_DIM)

**Goal:** Replace `Config.ARENA_GLOW_DIM` (one global factor) with 15 independent per-effect dim knobs, ALL defaulting to `0.0` (no dim = original pre-branch look), per the spec revision `docs/specs/2026-07-12-arena-dim-soul-toggle-design.md` (REVISION 2026-07-12b). Two knobs are gameplay tells built server-side.

**Architecture:** `GlowDim.apply(base, factor)` is unchanged. Each glow site swaps its `Config.ARENA_GLOW_DIM` reference for its specific `Config.GLOW_DIM_*`. The hex-warning knob is the one non-transparency case (darkens an opaque floor color via `Color3:Lerp` toward black).

**Branch:** `feat/arena-dim-soul-toggle` (continues; spec revision committed).

**⚠️ CONFIG DEV-FLIP HAZARD:** Task A edits `src/shared/Config.luau` (holds uncommitted `SOLO_TEST_MODE = true` / `ARENA_OVERRIDE = "sweeper"`; committed values `false`/`""`). Use the flip-down → commit → flip-up dance. Every other task commits only its client/server file with exact `git add <path>` (never `-A`). `docs/marketing/` is untracked — never stage it.

---

### Task A: Config — replace global knob with 15 per-effect knobs (dev-flip dance)

**Files:** Modify `src/shared/Config.luau`

- [ ] **Step 1: Replace the ARENA_GLOW_DIM block.** Edit — old_string:
```lua
-- Global cosmetic-glow dim (see src/shared/GlowDim.luau): softens ALL decorative Neon
-- dressing (hex floor trim, lobby energy rings + spectator orbs, sweeper wake/chase/
-- rotor/shaft/lens, sky wisps/aurora/crowd) toward a soft LED level. Gameplay tells
-- (sweeper kill tells, hex tile warnings -- built server-side) are NOT affected.
-- 0 = today's brightness, 1 = fully faded. Tune by eye in Studio.
Config.ARENA_GLOW_DIM = 0.4
```
new_string:
```lua
-- Per-effect cosmetic-glow dim (see src/shared/GlowDim.luau). Each knob softens ONE
-- visual effect independently: 0 = original brightness (no dim), 1 = fully faded.
-- ALL default 0.0, so out of the box the world looks exactly as it did before the dim
-- feature; raise a knob to dim that one effect. Applied as GlowDim.apply(base, knob)
-- on the effect's Neon transparency (except GLOW_DIM_HEX_WARNING -- see below).
Config.GLOW_DIM_WISPS = 0.0            -- sky soul-wisps (WorldShell)
Config.GLOW_DIM_AURORA = 0.0          -- aurora ribbon + swap flare (WorldShell)
Config.GLOW_DIM_CROWD = 0.0           -- distant crowd orbs (WorldShell)
Config.GLOW_DIM_LOBBY_RINGS = 0.0     -- lobby energy rings (LobbyStage)
Config.GLOW_DIM_SPECTATOR_ORBS = 0.0  -- lobby spectator-soul orbs (LobbyStage)
Config.GLOW_DIM_HEX_TRIM = 0.0        -- hex floor edge-trim (ArenaDressing)
Config.GLOW_DIM_SWEEP_WAKE = 0.0      -- sweeper wake channels (SweeperController)
Config.GLOW_DIM_SWEEP_CHASE = 0.0     -- sweeper rim chase studs (SweeperController)
Config.GLOW_DIM_SWEEP_ROTOR = 0.0     -- sweeper rotor bars (SweeperController)
Config.GLOW_DIM_SWEEP_SHAFT = 0.0     -- sweeper light shaft (SweeperController)
Config.GLOW_DIM_SWEEP_LENS = 0.0      -- sweeper spotlight lenses (SweeperController)
Config.GLOW_DIM_SWEEP_RIM = 0.0       -- sweeper rim accent bars (SweeperController)
Config.GLOW_DIM_SWEEP_DORMANT = 0.0   -- idle-sweeper standby dim (keep dormant dimmest)
-- Gameplay TELLS (server-side): default 0.0 = full brightness (no readability change).
-- Raise only if you deliberately want the danger signal dimmer.
Config.GLOW_DIM_SWEEP_KILL_TELLS = 0.0 -- amber blade / crimson underglow / emitter / lamps (SweeperHazard)
-- Hex tile warning is an opaque floor COLOR, so this knob DARKENS it toward black
-- (0 = full warning red, 1 = black) rather than fading transparency (HazardSystem).
Config.GLOW_DIM_HEX_WARNING = 0.0
```

- [ ] **Step 2: Flip dev switches DOWN.** Edit A: `Config.ARENA_OVERRIDE = "sweeper"` → `Config.ARENA_OVERRIDE = ""`. Edit B: `Config.SOLO_TEST_MODE = true` → `Config.SOLO_TEST_MODE = false`.

- [ ] **Step 3: Commit only Config:**
```bash
git add src/shared/Config.luau
git commit -m "feat(arena): per-effect dim knobs replace global ARENA_GLOW_DIM (default 0.0)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: VERIFY no dev flips in the commit:**
```bash
git show --format= -U0 HEAD -- src/shared/Config.luau | grep -E "SOLO_TEST_MODE|ARENA_OVERRIDE" || echo "CLEAN"
```
Expected `CLEAN`. If any dev-flip line appears, STOP (BLOCKED).

- [ ] **Step 5: Restore dev flips.** Edit A: `Config.ARENA_OVERRIDE = ""` → `Config.ARENA_OVERRIDE = "sweeper"`. Edit B: `Config.SOLO_TEST_MODE = false` → `Config.SOLO_TEST_MODE = true`.

- [ ] **Step 6: Confirm restored:**
```bash
git status --short src/shared/Config.luau
```
Expected `M src/shared/Config.luau`.

---

### Task B: WorldShell — wisps / crowd / aurora knobs

**Files:** Modify `src/client/WorldShell.luau`

- [ ] **Step 1: Parameterize `glowOrb`.** Edit — old: `local function glowOrb(size, color, parent)` → new: `local function glowOrb(size, color, parent, dimFactor)`
- [ ] **Step 2: Use the param.** Edit — old: `	p.Transparency = GlowDim.apply(0, Config.ARENA_GLOW_DIM)` → new: `	p.Transparency = GlowDim.apply(0, dimFactor)`
- [ ] **Step 3: Wisp caller.** Edit — old:
```lua
		local orb = glowOrb(Config.WORLD_WISP_SIZE, palette[w.colorIndex], folder)
```
new:
```lua
		local orb = glowOrb(Config.WORLD_WISP_SIZE, palette[w.colorIndex], folder, Config.GLOW_DIM_WISPS)
```
- [ ] **Step 4: Crowd caller.** Edit — old:
```lua
		local orb = glowOrb(Config.WORLD_CROWD_ORB_SIZE, color, folder)
```
new:
```lua
		local orb = glowOrb(Config.WORLD_CROWD_ORB_SIZE, color, folder, Config.GLOW_DIM_CROWD)
```
- [ ] **Step 5: Aurora base.** Edit — old: `	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.ARENA_GLOW_DIM)` → new: `	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.GLOW_DIM_AURORA)`
- [ ] **Step 6: Aurora flare.** Edit — old: `	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_FLARE_TRANSPARENCY, Config.ARENA_GLOW_DIM)` → new: `	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_FLARE_TRANSPARENCY, Config.GLOW_DIM_AURORA)`
- [ ] **Step 7: Aurora tween-back.** Edit — old: `		{ Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.ARENA_GLOW_DIM) })` → new: `		{ Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.GLOW_DIM_AURORA) })`
- [ ] **Step 8: Commit:**
```bash
git add src/client/WorldShell.luau
git commit -m "feat(arena): per-effect knobs for wisps/crowd/aurora

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task C: LobbyStage — rings / spectator-orb knobs

**Files:** Modify `src/client/LobbyStage.luau`

- [ ] **Step 1: Rings.** Edit — old:
```lua
	a.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.ARENA_GLOW_DIM)
	b.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.ARENA_GLOW_DIM)
```
new:
```lua
	a.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.GLOW_DIM_LOBBY_RINGS)
	b.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.GLOW_DIM_LOBBY_RINGS)
```
- [ ] **Step 2: Spectator orbs.** Edit — old: `			orb.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.ARENA_GLOW_DIM) -- soften the soul glow` → new: `			orb.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.GLOW_DIM_SPECTATOR_ORBS) -- soften the soul glow`
- [ ] **Step 3: Commit:**
```bash
git add src/client/LobbyStage.luau
git commit -m "feat(arena): per-effect knobs for lobby rings + spectator orbs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task D: ArenaDressing — hex-trim knob

**Files:** Modify `src/client/ArenaDressing.luau`

- [ ] **Step 1:** Edit — old: `				bar.Transparency = GlowDim.apply(0, Config.ARENA_GLOW_DIM)` → new: `				bar.Transparency = GlowDim.apply(0, Config.GLOW_DIM_HEX_TRIM)`
- [ ] **Step 2: Commit:**
```bash
git add src/client/ArenaDressing.luau
git commit -m "feat(arena): per-effect knob for hex floor trim

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task E: SweeperController — 6 accent knobs + dormant knob

**Files:** Modify `src/client/SweeperController.luau`

- [ ] **Step 1: Replace the constants block.** Edit — old_string:
```lua
-- Accent bases, each softened once by the global cosmetic dim so every downstream
-- reference (build, wake/chase animation targets, dormancy resets) inherits it.
-- The dormant override is dimmed in lockstep (DORMANT_TRANSPARENCY below) so a
-- dormant arena stays the DIMMEST state even after the live accents are softened
-- (otherwise a dimmed static accent could out-fade the undimmed standby).
local DIM = Config.ARENA_GLOW_DIM
local WAKE_BASE_TRANSPARENCY = GlowDim.apply(0.9, DIM)
local WAKE_LIT_TRANSPARENCY = GlowDim.apply(0.5, DIM)
local CHASE_BASE_TRANSPARENCY = GlowDim.apply(0.75, DIM)
local CHASE_LIT_TRANSPARENCY = GlowDim.apply(0.4, DIM)
local ROTOR_TRANSPARENCY = GlowDim.apply(0.6, DIM)
local SHAFT_TRANSPARENCY = GlowDim.apply(0.8, DIM)
local LENS_TRANSPARENCY = GlowDim.apply(0.5, DIM)
local RIM_ACCENT_TRANSPARENCY = GlowDim.apply(0.55, DIM)
local DORMANT_TRANSPARENCY = GlowDim.apply(Config.SWEEP_STANDBY_TRANSPARENCY, DIM)
```
new_string:
```lua
-- Accent bases, each softened by ITS OWN per-effect dim knob (0 = original, no dim).
-- Every downstream reference (build, wake/chase animation targets, dormancy resets)
-- reads these named constants, so each knob cascades. The dormant standby has its own
-- knob so a dormant arena can be kept the dimmest state under manual tuning.
local WAKE_BASE_TRANSPARENCY = GlowDim.apply(0.9, Config.GLOW_DIM_SWEEP_WAKE)
local WAKE_LIT_TRANSPARENCY = GlowDim.apply(0.5, Config.GLOW_DIM_SWEEP_WAKE)
local CHASE_BASE_TRANSPARENCY = GlowDim.apply(0.75, Config.GLOW_DIM_SWEEP_CHASE)
local CHASE_LIT_TRANSPARENCY = GlowDim.apply(0.4, Config.GLOW_DIM_SWEEP_CHASE)
local ROTOR_TRANSPARENCY = GlowDim.apply(0.6, Config.GLOW_DIM_SWEEP_ROTOR)
local SHAFT_TRANSPARENCY = GlowDim.apply(0.8, Config.GLOW_DIM_SWEEP_SHAFT)
local LENS_TRANSPARENCY = GlowDim.apply(0.5, Config.GLOW_DIM_SWEEP_LENS)
local RIM_ACCENT_TRANSPARENCY = GlowDim.apply(0.55, Config.GLOW_DIM_SWEEP_RIM)
local DORMANT_TRANSPARENCY = GlowDim.apply(Config.SWEEP_STANDBY_TRANSPARENCY, Config.GLOW_DIM_SWEEP_DORMANT)
```
- [ ] **Step 2: Commit:**
```bash
git add src/client/SweeperController.luau
git commit -m "feat(arena): per-effect knobs for sweeper wake/chase/rotor/shaft/lens/rim/dormant

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task F: SweeperHazard (SERVER) — kill-tell knob

**Files:** Modify `src/server/SweeperHazard.luau`

- [ ] **Step 1: Require GlowDim.** Edit — old:
```lua
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
```
new:
```lua
local WorldLayout = require(ReplicatedStorage.Shared.WorldLayout)
local GlowDim = require(ReplicatedStorage.Shared.GlowDim)
```
- [ ] **Step 2: Blade.** Edit — old:
```lua
		blade.Color = color
		blade.Material = Enum.Material.Neon
		weldOn(blade)
```
new:
```lua
		blade.Color = color
		blade.Material = Enum.Material.Neon
		blade.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
		weldOn(blade)
```
- [ ] **Step 3: Emitter.** Edit — old:
```lua
		emitter.Color = color
		emitter.Material = Enum.Material.Neon
		weldOn(emitter)
```
new:
```lua
		emitter.Color = color
		emitter.Material = Enum.Material.Neon
		emitter.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
		weldOn(emitter)
```
- [ ] **Step 4: Underglow.** Edit — old:
```lua
		underglow.Color = color
		underglow.Material = Enum.Material.Neon
		weldOn(underglow)
```
new:
```lua
		underglow.Color = color
		underglow.Material = Enum.Material.Neon
		underglow.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
		weldOn(underglow)
```
- [ ] **Step 5: Lamp.** Edit — old:
```lua
			lamp.Color = color
			lamp.Material = Enum.Material.Neon
			weldOn(lamp)
```
new:
```lua
			lamp.Color = color
			lamp.Material = Enum.Material.Neon
			lamp.Transparency = GlowDim.apply(0, Config.GLOW_DIM_SWEEP_KILL_TELLS)
			weldOn(lamp)
```
- [ ] **Step 6: Commit:**
```bash
git add src/server/SweeperHazard.luau
git commit -m "feat(arena): per-effect knob for sweeper kill tells (default 0 = full bright)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task G: HazardSystem (SERVER) — hex-warning color knob

**Files:** Modify `src/server/HazardSystem.luau`

- [ ] **Step 1: Precompute the darkened warning color.** Edit — old:
```lua
-- Map a phase to all parts of a tile (caller applies only on change). Solid shows
-- the floor's own color; warning shows the universal red; gone hides + drops collision.
local function applyPhase(tile, phase)
```
new:
```lua
-- Warning color, darkened toward black by GLOW_DIM_HEX_WARNING (0 = full red = original,
-- 1 = black). Precomputed once: the warning is an opaque floor color (not a glow), so
-- "dimming" it darkens the color rather than fading transparency.
local WARNING_COLOR = Config.TILE_COLOR_WARNING:Lerp(Color3.new(), Config.GLOW_DIM_HEX_WARNING)

-- Map a phase to all parts of a tile (caller applies only on change). Solid shows
-- the floor's own color; warning shows the universal red; gone hides + drops collision.
local function applyPhase(tile, phase)
```
- [ ] **Step 2: Use it in applyPhase.** Edit — old: `		canCollide, transparency, color = true, 0, Config.TILE_COLOR_WARNING` → new: `		canCollide, transparency, color = true, 0, WARNING_COLOR`
- [ ] **Step 3: Commit:**
```bash
git add src/server/HazardSystem.luau
git commit -m "feat(arena): per-effect knob for hex tile warning (color darken; default 0 = full red)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task H: Full suite + CHANGELOG

**Files:** Modify `CHANGELOG.md`

- [ ] **Step 1: Confirm no stale `ARENA_GLOW_DIM` references remain in code:**
```bash
grep -rn "ARENA_GLOW_DIM" src/ || echo "CLEAN: no ARENA_GLOW_DIM references"
```
Expected: `CLEAN`. If any remain, STOP (a site was missed).

- [ ] **Step 2: Run the whole lune suite (GlowDim unchanged; all green):**
```bash
export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" >/dev/null 2>&1 && echo "PASS $f" || echo "FAIL $f"; done
```
Expected: every line `PASS` (26 suites). Any `FAIL` → STOP (BLOCKED).

- [ ] **Step 3: Update the CHANGELOG entry.** Edit — old_string:
```lua
- **Global cosmetic-glow dim + Soul-halo toggle.** `Config.ARENA_GLOW_DIM` (default
  0.4) softens ALL decorative Neon dressing to a dim LED level via the new pure
  `src/shared/GlowDim.luau` (`tests/glow_dim.spec.luau`): hex floor edge-trim, lobby
  energy rings + spectator orbs, Soul Sweeper wake/chase/rotor/shaft/lens accents, and
  the sky wisps/aurora/crowd. Gameplay-critical tells (sweeper amber-blade/crimson kill
  tells, hex tile warning colors -- built server-side) are untouched, so readability and
  fairness are unchanged; arena-agnostic (a future arena inherits the dim by routing its
  cosmetic Neon through `GlowDim.apply`). `Config.SOUL_HALO_ENABLED` (default true) gates
  the over-head Soul identity halo for clean marketing screenshots. Verified: 26/26 lune
  suites; Studio visual pass pending. See
  [spec](superpowers/specs/2026-07-12-arena-dim-soul-toggle-design.md) and
  [plan](superpowers/plans/2026-07-12-arena-dim-soul-toggle.md).
```
new_string:
```lua
- **Per-effect cosmetic-glow dim + Soul-halo toggle.** 15 independent `Config.GLOW_DIM_*`
  knobs each soften ONE visual effect via the pure `src/shared/GlowDim.luau`
  (`tests/glow_dim.spec.luau`): sky wisps/aurora/crowd, lobby rings + spectator orbs,
  hex floor trim, sweeper wake/chase/rotor/shaft/lens/rim/dormant, plus the two
  server-side gameplay tells (sweeper kill tells; hex tile warning, which darkens the
  warning color rather than fading it). ALL default `0.0` (no dim = original brightness),
  so the world ships unchanged and each effect is tuned up independently; the two tell
  knobs default `0.0` (full bright) so readability/fairness are unaffected unless
  deliberately tuned. `Config.SOUL_HALO_ENABLED` (default true) gates the over-head Soul
  identity halo for clean marketing screenshots. Verified: 26/26 lune suites; Studio
  visual pass pending. See
  [spec](superpowers/specs/2026-07-12-arena-dim-soul-toggle-design.md) and
  [plan](superpowers/plans/2026-07-12b-per-effect-dim.md).
```
- [ ] **Step 4: Commit:**
```bash
git add CHANGELOG.md
git commit -m "docs(arena): CHANGELOG for per-effect dim knobs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Verification (orchestrator + user)

- No `ARENA_GLOW_DIM` remains in `src/` (Task H Step 1); 26/26 lune green (Step 2).
- Commit hygiene: no commit contains `SOLO_TEST_MODE`/`ARENA_OVERRIDE`; `git status` still shows `Config.luau` modified (dev flips).
- **Studio (user):** with all knobs at 0.0, confirm the world looks like the ORIGINAL (pre-dim) game. Then raise individual knobs to taste; confirm each affects only its effect, and that raising a tell knob dims only that tell.
