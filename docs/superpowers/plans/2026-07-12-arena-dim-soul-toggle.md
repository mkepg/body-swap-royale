# Arena Cosmetic Dim + Soul-Halo Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add `Config.SOUL_HALO_ENABLED` (gate the over-head Soul halo for clean screenshots) and `Config.ARENA_GLOW_DIM` (one arena-agnostic knob softening all decorative Neon), per `docs/superpowers/specs/2026-07-12-arena-dim-soul-toggle-design.md`.

**Architecture:** One pure `GlowDim` module (lune-tested) raises a base Neon `Transparency` toward 1 by a global factor. Every cosmetic Neon transparency in the four client dressing files routes through it. Gameplay tells (sweeper kill tells, hex tile warnings) are server-side and never touched. The halo toggle is an early-return in `SoulController.start()`.

**Tech Stack:** Luau, Rojo, lune (pure-model tests). No remotes, no server changes.

**Branch:** `feat/arena-dim-soul-toggle` off `main` (spec committed at `f665bf7`).

**⚠️ CONFIG DEV-FLIP HAZARD:** `src/shared/Config.luau` carries two deliberate UNCOMMITTED working-tree dev flips — `Config.SOLO_TEST_MODE = true` and `Config.ARENA_OVERRIDE = "sweeper"` (committed values are `false` and `""`). They must NEVER be committed. Only Task 2 touches Config, and it uses an explicit flip-down → commit → flip-up dance (below). Every other task commits only client files; use exact `git add <path>` (never `-A`/`.`). Also note `docs/marketing/` is untracked on this branch (it belongs to the icon branch) — never stage it.

---

### Task 1: `GlowDim` pure module + lune test (TDD)

**Files:**
- Create: `src/shared/GlowDim.luau`
- Create: `tests/glow_dim.spec.luau`

- [ ] **Step 1: Write the failing test** — create `tests/glow_dim.spec.luau`:

```lua
local M = require("../src/shared/GlowDim")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- endpoints: factor 0 => base unchanged; factor 1 => fully faded (1).
do
	expect(approx(M.apply(0.5, 0), 0.5), "factor 0 returns base")
	expect(approx(M.apply(0.0, 0), 0.0), "factor 0, base 0")
	expect(approx(M.apply(0.5, 1), 1.0), "factor 1 => 1")
	expect(approx(M.apply(0.0, 1), 1.0), "factor 1 from opaque => 1")
	print("glowdim: endpoints OK")
end

-- interpolation: base + (1-base)*factor.
do
	expect(approx(M.apply(0.0, 0.4), 0.4), "opaque, 0.4 => 0.4")
	expect(approx(M.apply(0.5, 0.4), 0.7), "0.5 base, 0.4 => 0.7")
	expect(approx(M.apply(0.8, 0.5), 0.9), "0.8 base, 0.5 => 0.9")
	print("glowdim: interpolation OK")
end

-- monotonic non-decreasing in factor (dimmer never brightens).
do
	local prev = -1
	for i = 0, 10 do
		local v = M.apply(0.3, i / 10)
		expect(v >= prev - 1e-12, "monotonic in factor")
		prev = v
	end
	print("glowdim: monotonic OK")
end

-- clamps out-of-range inputs; result always in [0,1].
do
	expect(approx(M.apply(0.5, -1), 0.5), "negative factor clamps to 0")
	expect(approx(M.apply(0.5, 2), 1.0), "factor > 1 clamps to 1")
	expect(approx(M.apply(-1, 0.5), 0.5), "negative base clamps to 0 => 0.5")
	expect(approx(M.apply(2, 0.5), 1.0), "base > 1 clamps to 1 => 1")
	print("glowdim: clamp OK")
end

print("ALL GlowDim TESTS PASSED")
```

- [ ] **Step 2: Run it, verify it FAILS** (module missing):

```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/glow_dim.spec.luau
```
Expected: error that `../src/shared/GlowDim` cannot be found/required.

- [ ] **Step 3: Implement** — create `src/shared/GlowDim.luau`:

```lua
--[[
	GlowDim (shared, pure) -- one arena-agnostic knob for softening decorative Neon.
	Roblox-free and lune-tested. Raises a base part Transparency toward 1 (Neon emits
	softer the more transparent it is), so a single Config.ARENA_GLOW_DIM factor dims
	all cosmetic dressing uniformly. Gameplay tells are built server-side and are never
	routed through here, so they keep full brightness.

	Location: ReplicatedStorage/Shared/GlowDim (ModuleScript)
--]]

local GlowDim = {}

local function clamp01(x)
	if x < 0 then
		return 0
	elseif x > 1 then
		return 1
	end
	return x
end

-- base in [0,1] (a part's resting Transparency), factor in [0,1] (0 = unchanged,
-- 1 = fully faded). Returns base + (1 - base) * factor, all clamped to [0,1].
-- Monotonic non-decreasing in factor: factor 0 -> base, factor 1 -> 1.
function GlowDim.apply(baseTransparency, factor)
	local b = clamp01(baseTransparency)
	local f = clamp01(factor)
	return b + (1 - b) * f
end

return GlowDim
```

- [ ] **Step 4: Run it, verify it PASSES:**

```bash
export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/glow_dim.spec.luau
```
Expected: `ALL GlowDim TESTS PASSED`.

- [ ] **Step 5: Commit:**

```bash
git add src/shared/GlowDim.luau tests/glow_dim.spec.luau
git commit -m "feat(arena): GlowDim pure module + lune tests

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Config additions (⚠️ dev-flip dance)

**Files:**
- Modify: `src/shared/Config.luau`

- [ ] **Step 1: Add the two new tunables.** Edit — anchor on the existing soul-wisps comment (unique):

old_string:
```lua
-- Soul-wisps: drifting glowing orbs colored from SOUL_PALETTE, high in the sky.
```
new_string:
```lua
-- ===== Visual polish flags (2026-07-12) =====
-- Soul identity halo: the over-head colored dot (SoulController). true = shown in
-- live play so players recognize who controls which body across swaps; flip to false
-- for clean marketing screenshots (no floating UI pips over heads). Read once at boot.
Config.SOUL_HALO_ENABLED = true

-- Global cosmetic-glow dim (see src/shared/GlowDim.luau): softens ALL decorative Neon
-- dressing (hex floor trim, lobby energy rings + spectator orbs, sweeper wake/chase/
-- rotor/shaft/lens, sky wisps/aurora/crowd) toward a soft LED level. Gameplay tells
-- (sweeper kill tells, hex tile warnings -- built server-side) are NOT affected.
-- 0 = today's brightness, 1 = fully faded. Tune by eye in Studio.
Config.ARENA_GLOW_DIM = 0.4

-- Soul-wisps: drifting glowing orbs colored from SOUL_PALETTE, high in the sky.
```

- [ ] **Step 2: Flip the dev switches DOWN to committed values** (so they don't land in the commit). Two edits:

Edit A — old_string: `Config.ARENA_OVERRIDE = "sweeper"` → new_string: `Config.ARENA_OVERRIDE = ""`
Edit B — old_string: `Config.SOLO_TEST_MODE = true` → new_string: `Config.SOLO_TEST_MODE = false`

- [ ] **Step 3: Stage + commit ONLY Config:**

```bash
git add src/shared/Config.luau
git commit -m "feat(arena): Config.SOUL_HALO_ENABLED + Config.ARENA_GLOW_DIM

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: VERIFY the commit did NOT include the dev flips:**

```bash
git show --format= -U0 HEAD -- src/shared/Config.luau | grep -E "SOLO_TEST_MODE|ARENA_OVERRIDE" || echo "CLEAN: no dev-flip lines in commit"
```
Expected: `CLEAN: no dev-flip lines in commit`. If any `SOLO_TEST_MODE`/`ARENA_OVERRIDE` line appears, STOP and report — the flips leaked.

- [ ] **Step 5: Restore the dev flips in the working tree** (uncommitted). Two edits:

Edit A — old_string: `Config.ARENA_OVERRIDE = ""` → new_string: `Config.ARENA_OVERRIDE = "sweeper"`
Edit B — old_string: `Config.SOLO_TEST_MODE = false` → new_string: `Config.SOLO_TEST_MODE = true`

- [ ] **Step 6: Confirm the restored state is uncommitted:**

```bash
git status --short src/shared/Config.luau
git diff -U0 src/shared/Config.luau | grep -E "SOLO_TEST_MODE = true|ARENA_OVERRIDE = \"sweeper\""
```
Expected: `M src/shared/Config.luau`, and the grep shows both dev-flip lines present as uncommitted changes.

---

### Task 3: SoulController halo toggle

**Files:**
- Modify: `src/client/SoulController.luau`

- [ ] **Step 1: Require Config.** Edit:

old_string:
```lua
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
```
new_string:
```lua
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
```

- [ ] **Step 2: Early-return in start().** Edit:

old_string:
```lua
function SoulController.start()
	SoulMap.OnClientEvent:Connect(reconcile)
```
new_string:
```lua
function SoulController.start()
	if not Config.SOUL_HALO_ENABLED then
		return -- halos suppressed (e.g. clean marketing screenshots)
	end
	SoulMap.OnClientEvent:Connect(reconcile)
```

- [ ] **Step 3: Sanity-check (no lune test — Roblox client module).** Confirm the file still parses by grepping the guard is present exactly once:

```bash
grep -c "if not Config.SOUL_HALO_ENABLED then" src/client/SoulController.luau
```
Expected: `1`.

- [ ] **Step 4: Commit:**

```bash
git add src/client/SoulController.luau
git commit -m "feat(arena): gate Soul halo behind Config.SOUL_HALO_ENABLED

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: WorldShell cosmetic dim (wisps, crowd, aurora)

**Files:**
- Modify: `src/client/WorldShell.luau`

- [ ] **Step 1: Require GlowDim.** Edit:

old_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))
```
new_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local GlowDim = require(Shared:WaitForChild("GlowDim"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))
```

- [ ] **Step 2: Dim wisp + crowd orbs** (the shared `glowOrb` helper; they currently have no explicit transparency = fully bright). Edit:

old_string:
```lua
	p.Material = Enum.Material.Neon
	p.Size = Vector3.new(size, size, size)
	p.Color = color
	p.Parent = parent
	return p
```
new_string:
```lua
	p.Material = Enum.Material.Neon
	p.Transparency = GlowDim.apply(0, Config.ARENA_GLOW_DIM)
	p.Size = Vector3.new(size, size, size)
	p.Color = color
	p.Parent = parent
	return p
```

- [ ] **Step 3: Dim aurora base.** Edit:

old_string:
```lua
	auroraPart.Transparency = Config.WORLD_AURORA_BASE_TRANSPARENCY
```
new_string:
```lua
	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.ARENA_GLOW_DIM)
```

- [ ] **Step 4: Dim aurora flare peak.** Edit:

old_string:
```lua
	auroraPart.Transparency = Config.WORLD_AURORA_FLARE_TRANSPARENCY
```
new_string:
```lua
	auroraPart.Transparency = GlowDim.apply(Config.WORLD_AURORA_FLARE_TRANSPARENCY, Config.ARENA_GLOW_DIM)
```

- [ ] **Step 5: Dim aurora tween-back target.** Edit:

old_string:
```lua
		{ Transparency = Config.WORLD_AURORA_BASE_TRANSPARENCY })
```
new_string:
```lua
		{ Transparency = GlowDim.apply(Config.WORLD_AURORA_BASE_TRANSPARENCY, Config.ARENA_GLOW_DIM) })
```

> Note: the swap-triggered aurora flare is dimmed too (it's atmospheric feedback, not a gameplay tell — the swap has its own HUD telegraph). If the Studio pass finds the flare too weak, that's a `ARENA_GLOW_DIM` tuning observation, not a bug.

- [ ] **Step 6: Commit:**

```bash
git add src/client/WorldShell.luau
git commit -m "feat(arena): route WorldShell wisp/crowd/aurora glow through GlowDim

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: LobbyStage cosmetic dim (energy rings + spectator orbs)

**Files:**
- Modify: `src/client/LobbyStage.luau`

- [ ] **Step 1: Require GlowDim.** Edit:

old_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))
```
new_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local GlowDim = require(Shared:WaitForChild("GlowDim"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))
```

- [ ] **Step 2: Dim the two energy rings.** Edit:

old_string:
```lua
	-- soften the rim glow
	a.Transparency = Config.LOBBY_BEY_GLOW_TRANSPARENCY
	b.Transparency = Config.LOBBY_BEY_GLOW_TRANSPARENCY
```
new_string:
```lua
	-- soften the rim glow (global cosmetic dim on top of the base softening)
	a.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.ARENA_GLOW_DIM)
	b.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.ARENA_GLOW_DIM)
```

- [ ] **Step 3: Dim the spectator-soul orbs.** Edit:

old_string:
```lua
			orb.Transparency = Config.LOBBY_BEY_GLOW_TRANSPARENCY -- soften the soul glow
```
new_string:
```lua
			orb.Transparency = GlowDim.apply(Config.LOBBY_BEY_GLOW_TRANSPARENCY, Config.ARENA_GLOW_DIM) -- soften the soul glow
```

- [ ] **Step 4: Commit:**

```bash
git add src/client/LobbyStage.luau
git commit -m "feat(arena): route LobbyStage ring/orb glow through GlowDim

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: ArenaDressing cosmetic dim (hex floor trim)

**Files:**
- Modify: `src/client/ArenaDressing.luau`

- [ ] **Step 1: Require GlowDim.** Edit:

old_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local ArenaDescriptor = require(Shared:WaitForChild("ArenaDescriptor"))
```
new_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local GlowDim = require(Shared:WaitForChild("GlowDim"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local ArenaDescriptor = require(Shared:WaitForChild("ArenaDescriptor"))
```

- [ ] **Step 2: Dim the floor-trim bars** (currently no explicit transparency = fully bright Neon — a big contributor to the too-bright hex look). Edit:

old_string:
```lua
				bar.Name = "FloorTrim"
```
new_string:
```lua
				bar.Name = "FloorTrim"
				bar.Transparency = GlowDim.apply(0, Config.ARENA_GLOW_DIM)
```

- [ ] **Step 3: Commit:**

```bash
git add src/client/ArenaDressing.luau
git commit -m "feat(arena): route hex floor-trim glow through GlowDim

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: SweeperController cosmetic dim (8 accent constants)

**Files:**
- Modify: `src/client/SweeperController.luau`

- [ ] **Step 1: Require GlowDim.** Edit:

old_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
```
new_string:
```lua
local Config = require(Shared:WaitForChild("Config"))
local GlowDim = require(Shared:WaitForChild("GlowDim"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
```

- [ ] **Step 2: Dim all 8 accent constants at definition** (every build/animation/dormancy reference reads these named constants, so dimming here cascades everywhere with no other edits). Edit:

old_string:
```lua
local WAKE_BASE_TRANSPARENCY = 0.9
local WAKE_LIT_TRANSPARENCY = 0.5
local CHASE_BASE_TRANSPARENCY = 0.75
local CHASE_LIT_TRANSPARENCY = 0.4
local ROTOR_TRANSPARENCY = 0.6
local SHAFT_TRANSPARENCY = 0.8
local LENS_TRANSPARENCY = 0.5
local RIM_ACCENT_TRANSPARENCY = 0.55
```
new_string:
```lua
-- Accent bases, each softened once by the global cosmetic dim so every downstream
-- reference (build, wake/chase animation targets, dormancy resets) inherits it.
-- The dormant override (Config.SWEEP_STANDBY_TRANSPARENCY) is intentionally left
-- undimmed; at a high ARENA_GLOW_DIM a faint element (shaft) may approach it, which
-- is cosmetically irrelevant (both near-invisible).
local DIM = Config.ARENA_GLOW_DIM
local WAKE_BASE_TRANSPARENCY = GlowDim.apply(0.9, DIM)
local WAKE_LIT_TRANSPARENCY = GlowDim.apply(0.5, DIM)
local CHASE_BASE_TRANSPARENCY = GlowDim.apply(0.75, DIM)
local CHASE_LIT_TRANSPARENCY = GlowDim.apply(0.4, DIM)
local ROTOR_TRANSPARENCY = GlowDim.apply(0.6, DIM)
local SHAFT_TRANSPARENCY = GlowDim.apply(0.8, DIM)
local LENS_TRANSPARENCY = GlowDim.apply(0.5, DIM)
local RIM_ACCENT_TRANSPARENCY = GlowDim.apply(0.55, DIM)
```

> `GlowDim` must be required (Step 1) BEFORE these constant definitions run — the require sits at the top of the file with the others, so it is in scope.

- [ ] **Step 3: Commit:**

```bash
git add src/client/SweeperController.luau
git commit -m "feat(arena): route Soul Sweeper dressing glow through GlowDim

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Full suite + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the whole lune suite — all green (adds glow_dim; nothing regressed):**

```bash
export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" >/dev/null && echo "PASS $f" || echo "FAIL $f"; done
```
Expected: every line `PASS ...` (26 suites incl. the new `tests/glow_dim.spec.luau`).

- [ ] **Step 2: Add a CHANGELOG entry** under a new `## [2026-07-12]` / `### Added` at the top of the entries (match existing style). Edit anchors on the first existing dated entry heading:

old_string:
```lua
## [2026-07-10]
```
new_string:
```lua
## [2026-07-12]

### Added
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

## [2026-07-10]
```

- [ ] **Step 3: Commit:**

```bash
git add CHANGELOG.md
git commit -m "docs(arena): CHANGELOG for cosmetic-dim + soul-halo toggle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Post-plan verification (orchestrator + user)

- **Lune:** Task 8 Step 1 (whole suite green).
- **Studio (user-driven, manual — cannot be automated):**
  - Halo: flip `Config.SOUL_HALO_ENABLED = false`, Play Solo, confirm no over-head dots; flip back to `true`, confirm they return.
  - Dim: Play across hex + sweeper + lobby; confirm dressing reads dim/soft-LED while (a) sweeper amber-blade/crimson kill tells and (b) hex tile warning-red stay full-brightness; tune `Config.ARENA_GLOW_DIM` up/down to taste (higher = dimmer).
- Commit-hygiene gate: no commit on the branch contains `SOLO_TEST_MODE`/`ARENA_OVERRIDE` changes; `git status` still shows `Config.luau` modified (the restored dev flips).
