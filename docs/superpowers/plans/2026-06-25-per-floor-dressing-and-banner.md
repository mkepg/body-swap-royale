# Per-Floor Arena Dressing + Banner Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Dress every hex floor with floor-colored torches + an orb ring (real lights budget-capped to the top floors), and redesign the "Body Swap Royale" banner into a framed marquee header — extending Slice 1.

**Architecture:** Extend `ArenaDescriptor` with a `levels` list so `ArenaDressing` dresses each floor parametrically (stays arena-agnostic). All client-cosmetic. Spec: `docs/superpowers/specs/2026-06-25-per-floor-dressing-and-banner-design.md`.

**Tech Stack:** Luau, Rojo, lune (regression only — no new pure math), Roblox Studio MCP (visual verification).

**Conventions:** tab indentation; `CanCollide=false` cosmetics; `Shared:WaitForChild` requires; client modules not lune-testable → MCP + smoke verification; every parametric value in Config.

---

## File Structure

| File | Change |
|------|--------|
| `src/shared/ArenaDescriptor.luau` (modify) | Add `levels` to `hex()`; assert `levels` in `validate()`. |
| `src/shared/Config.luau` (modify) | Remove `WORLD_SPOTLIGHT_*` + `WORLD_MARQUEE_*`; add `WORLD_TORCH_*` + `WORLD_BANNER_*`; `WORLD_NEAR_ORB_COUNT` 18→12. |
| `src/client/ArenaDressing.luau` (modify) | `buildSpotlights`→`buildTorches` (per-level, budget light/flame); `buildNearOrbs`→`buildOrbRings` (per-level); `buildMarquee`→`buildBanner` (framed); `start()` validates + iterates levels. |
| `docs/smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md` (modify) | Add per-floor + banner checks. |

---

## Task 1: `ArenaDescriptor` — add `levels`

**Files:** Modify `src/shared/ArenaDescriptor.luau`

- [ ] **Step 1: Add `levels` to `hex()`.** Replace the body of `ArenaDescriptor.hex()` with:

```lua
function ArenaDescriptor.hex()
	local halfWidth = Config.HEX_SIZE * 1.5 * Config.HEX_RADIUS + Config.HEX_SIZE
	local extent = halfWidth * 2
	-- One dressable level per hex floor, top -> bottom, each carrying its floor color.
	local levels = {}
	for k = 0, Config.HEX_FLOOR_COUNT - 1 do
		levels[#levels + 1] = {
			y = Config.TILE_SURFACE_Y - k * Config.HEX_FLOOR_GAP,
			color = Config.HEX_FLOOR_COLORS[k + 1],
		}
	end
	return {
		center = Vector3.new(0, Config.TILE_SURFACE_Y, 0),
		footprint = Vector2.new(extent, extent),
		depth = Config.HEX_FLOOR_GAP * (Config.HEX_FLOOR_COUNT - 1),
		accent = Config.HEX_FLOOR_COLORS[1],
		levels = levels,
	}
end
```

- [ ] **Step 2: Assert `levels` in `validate()`.** Inside `ArenaDescriptor.validate(desc)`, before `return desc`, add:

```lua
	assert(type(desc.levels) == "table" and #desc.levels > 0,
		"ArenaDescriptor.levels must be a non-empty array")
	for i, lv in ipairs(desc.levels) do
		assert(type(lv.y) == "number", "ArenaDescriptor.levels[" .. i .. "].y must be a number")
		assert(typeof(lv.color) == "Color3", "ArenaDescriptor.levels[" .. i .. "].color must be a Color3")
	end
```

- [ ] **Step 3: MCP probe (coordinator).** In Studio Edit, run via MCP:
```lua
local d = require(game.ReplicatedStorage.Shared.ArenaDescriptor).hex()
require(game.ReplicatedStorage.Shared.ArenaDescriptor).validate(d)
return string.format("levels=%d first.y=%.0f first.color=%s last.y=%.0f",
	#d.levels, d.levels[1].y, tostring(d.levels[1].color), d.levels[#d.levels].y)
```
Expected: `levels=7 first.y=0 first.color=0.96..,0.78..,0.27.. last.y=-300`. (Subagent can't run this — confirm structural correctness + that referenced Config keys exist; coordinator runs the probe.)

- [ ] **Step 4: Commit.**
```bash
git add src/shared/ArenaDescriptor.luau
git commit -m "feat(world): ArenaDescriptor publishes per-floor levels"
```

---

## Task 2: `Config` — migrate to torch + banner keys

**Files:** Modify `src/shared/Config.luau`

- [ ] **Step 1: Remove the old keys.** Delete these lines from the WORLD_* block:
- `Config.WORLD_SPOTLIGHT_MARGIN`, `Config.WORLD_SPOTLIGHT_HEIGHT`, `Config.WORLD_SPOTLIGHT_RANGE`, `Config.WORLD_SPOTLIGHT_BRIGHTNESS`
- `Config.WORLD_MARQUEE_TEXT`, `Config.WORLD_MARQUEE_SIZE`, `Config.WORLD_MARQUEE_HEIGHT`

Leave `WORLD_NEAR_ORB_RADIUS`, `WORLD_NEAR_ORB_Y`, `WORLD_NEAR_ORB_SIZE` in place.

- [ ] **Step 2: Change the orb count.** Change `Config.WORLD_NEAR_ORB_COUNT = 18` to:
```lua
Config.WORLD_NEAR_ORB_COUNT = 12        -- ring per floor; reduced so 7 stacked rings aren't soup
```

- [ ] **Step 3: Add the torch + banner blocks.** Where the spotlight/marquee keys were (still inside the WORLD_* block, before `return Config`), add:

```lua
-- Per-floor torches: short posts; Neon head = floor color on ALL floors; a real
-- PointLight + flame particles only on the top WORLD_TORCH_LIT_FLOORS floors
-- (perf dial -- avoids 28 dynamic lights / particle-budget blowout / cross-floor bleed).
Config.WORLD_TORCH_MARGIN = 14          -- studs outward from the footprint corners
Config.WORLD_TORCH_POST_HEIGHT = 12     -- short (< HEX_FLOOR_GAP 50 so it can't pierce the floor above)
Config.WORLD_TORCH_HEAD_SIZE = 3
Config.WORLD_TORCH_LIT_FLOORS = 3       -- top N floors get a real PointLight + flame particles
Config.WORLD_TORCH_LIGHT_RANGE = 34     -- < HEX_FLOOR_GAP so light doesn't bleed across floors
Config.WORLD_TORCH_LIGHT_BRIGHTNESS = 2
Config.WORLD_TORCH_FLAME_RATE = 6       -- particles/sec per lit torch (low for the mobile budget)

-- Framed marquee header (banner) on support posts at the balcony's arena-facing edge.
Config.WORLD_BANNER_TEXT = "BODY SWAP ROYALE"
Config.WORLD_BANNER_SIZE = Vector3.new(64, 16, 2)
Config.WORLD_BANNER_HEIGHT = 14                 -- studs above the balcony surface
Config.WORLD_BANNER_FRAME_COLOR = Color3.fromRGB(255, 216, 77)   -- glowing amber frame
Config.WORLD_BANNER_BG_TOP = Color3.fromRGB(36, 16, 72)
Config.WORLD_BANNER_BG_BOTTOM = Color3.fromRGB(22, 10, 46)
Config.WORLD_BANNER_TEXT_COLOR = Color3.fromRGB(255, 216, 77)
Config.WORLD_BANNER_POST_COLOR = Color3.fromRGB(40, 40, 50)
```

- [ ] **Step 4: Verify nothing else references the removed keys.** Grep the repo for `WORLD_SPOTLIGHT` and `WORLD_MARQUEE` — the ONLY remaining references should be in `src/client/ArenaDressing.luau` (rewritten in Task 3). Confirm no other file references them.

- [ ] **Step 5: Lune health check.** `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_grid.spec.luau` → `ALL HexGrid TESTS PASSED`.

- [ ] **Step 6: Commit.**
```bash
git add src/shared/Config.luau
git commit -m "feat(world): migrate Config to WORLD_TORCH_*/WORLD_BANNER_*; orb ring 18->12"
```

---

## Task 3: `ArenaDressing` — per-floor torches/orbs + framed banner

**Files:** Modify `src/client/ArenaDressing.luau`

- [ ] **Step 1: Replace the three builders + `start()`.** Replace `buildSpotlights`, `buildMarquee`, `buildNearOrbs`, and `ArenaDressing.start()` with the following (keep the file header, the `require`s, `newFolder`, and `rigPart` as-is):

```lua
-- One short torch: dark post + Neon head tinted to the floor color (all floors).
-- `lit` floors additionally get a real floor-colored PointLight + a low-rate flame.
local function buildTorch(folder, x, z, baseY, color, lit)
	local postH = Config.WORLD_TORCH_POST_HEIGHT
	local post = rigPart(Vector3.new(1.5, postH, 1.5),
		Vector3.new(x, baseY + postH / 2, z),
		Color3.fromRGB(40, 40, 50), Enum.Material.Metal, folder)
	post.Name = "TorchPost"

	local hs = Config.WORLD_TORCH_HEAD_SIZE
	local head = rigPart(Vector3.new(hs, hs, hs),
		Vector3.new(x, baseY + postH + hs / 2, z),
		color, Enum.Material.Neon, folder)
	head.Name = "TorchHead"

	if lit then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = Config.WORLD_TORCH_LIGHT_RANGE
		light.Brightness = Config.WORLD_TORCH_LIGHT_BRIGHTNESS
		light.Parent = head

		local flame = Instance.new("ParticleEmitter")
		flame.Color = ColorSequence.new(color)
		flame.Rate = Config.WORLD_TORCH_FLAME_RATE
		flame.Lifetime = NumberRange.new(0.5, 0.9)
		flame.Speed = NumberRange.new(2, 4)
		flame.Size = NumberSequence.new(1.2, 0)
		flame.Transparency = NumberSequence.new(0.2, 1)
		flame.LightEmission = 1
		flame.Parent = head
	end
end

-- 4 torches at the footprint corners of every level; only the top
-- WORLD_TORCH_LIT_FLOORS levels get a real light + flame.
local function buildTorches(folder, desc)
	for i, lv in ipairs(desc.levels) do
		local lit = i <= Config.WORLD_TORCH_LIT_FLOORS
		local corners = WorldLayout.footprintCorners(
			desc.center.X, desc.center.Z, desc.footprint.X, desc.footprint.Y,
			Config.WORLD_TORCH_MARGIN)
		for _, c in ipairs(corners) do
			buildTorch(folder, c.x, c.z, lv.y, lv.color, lit)
		end
	end
end

-- A soul-palette orb ring around every level (distinct from the floor-colored torches).
local function buildOrbRings(folder, desc)
	local palette = Config.SOUL_PALETTE
	for _, lv in ipairs(desc.levels) do
		local pts = WorldLayout.ring(desc.center.X, desc.center.Z,
			Config.WORLD_NEAR_ORB_RADIUS, Config.WORLD_NEAR_ORB_COUNT)
		for i, pt in ipairs(pts) do
			local orb = rigPart(
				Vector3.new(Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE),
				Vector3.new(pt.x, lv.y + Config.WORLD_NEAR_ORB_Y, pt.z),
				palette[WorldLayout.paletteIndex(i, #palette)], Enum.Material.Neon, folder)
			orb.Shape = Enum.PartType.Ball
			orb.Name = "NearOrb"
		end
	end
end

-- Framed marquee header on two support posts at the balcony's arena-facing edge,
-- facing the waiting players (-Z Front face). Built from lobby Config, not the arena.
local function buildBanner(folder)
	local frontEdgeZ = Config.LOBBY_ORIGIN.Z + Config.LOBBY_PAD_SIZE.Z / 2
	local y = Config.LOBBY_ORIGIN.Y + Config.WORLD_BANNER_HEIGHT
	local panel = rigPart(Config.WORLD_BANNER_SIZE,
		Vector3.new(0, y, frontEdgeZ),
		Config.WORLD_BANNER_BG_BOTTOM, Enum.Material.SmoothPlastic, folder)
	panel.Name = "Banner"

	-- Two posts from the balcony surface up to the panel (mounted, not floating).
	local halfW = Config.WORLD_BANNER_SIZE.X / 2 - 3
	local postH = Config.WORLD_BANNER_HEIGHT + Config.WORLD_BANNER_SIZE.Y / 2
	for _, sx in ipairs({ -halfW, halfW }) do
		local post = rigPart(Vector3.new(1.2, postH, 1.2),
			Vector3.new(sx, Config.LOBBY_ORIGIN.Y + postH / 2, frontEdgeZ),
			Config.WORLD_BANNER_POST_COLOR, Enum.Material.Metal, folder)
		post.Name = "BannerPost"
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- -Z, toward the balcony players
	gui.CanvasSize = Vector2.new(640, 160) -- 4:1 matches the 64x16 panel
	gui.Parent = panel

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Config.WORLD_BANNER_BG_TOP
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.14, 0)
	corner.Parent = frame
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Config.WORLD_BANNER_BG_TOP, Config.WORLD_BANNER_BG_BOTTOM)
	grad.Rotation = 90
	grad.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.WORLD_BANNER_FRAME_COLOR
	stroke.Thickness = 6
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.9, 0.52)
	title.Position = UDim2.fromScale(0.05, 0.34)
	title.BackgroundTransparency = 1
	title.Text = Config.WORLD_BANNER_TEXT
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Config.WORLD_BANNER_TEXT_COLOR
	title.Parent = frame
	local tstroke = Instance.new("UIStroke")
	tstroke.Color = Color3.fromRGB(60, 20, 10)
	tstroke.Thickness = 2
	tstroke.Parent = title

	local pill = Instance.new("TextLabel")
	pill.Size = UDim2.fromScale(0.3, 0.16)
	pill.Position = UDim2.fromScale(0.35, 0.08)
	pill.BackgroundColor3 = Color3.fromRGB(255, 61, 139)
	pill.Text = "★ ON AIR ★"
	pill.Font = Enum.Font.GothamBold
	pill.TextScaled = true
	pill.TextColor3 = Color3.new(1, 1, 1)
	pill.Parent = frame
	local pcorner = Instance.new("UICorner")
	pcorner.CornerRadius = UDim.new(0.5, 0)
	pcorner.Parent = pill
end

function ArenaDressing.start()
	local folder = newFolder()
	local desc = ArenaDescriptor.validate(ArenaDescriptor.hex())
	buildTorches(folder, desc)
	buildOrbRings(folder, desc)
	buildBanner(folder)
end
```

- [ ] **Step 2: Self-check.** Re-read the file: confirm `buildSpotlights`/`buildMarquee`/`buildNearOrbs` are fully gone, no remaining `WORLD_SPOTLIGHT_*`/`WORLD_MARQUEE_*` references, `return ArenaDressing` intact, all created parts go through `rigPart` (so `CanCollide=false`). Run `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec.luau` (dependency intact) → `ALL WorldLayout TESTS PASSED`.

- [ ] **Step 3: Commit.**
```bash
git add src/client/ArenaDressing.luau
git commit -m "feat(world): per-floor torches + orb rings; framed marquee header banner"
```

- [ ] **Step 4: MCP visual verification (coordinator).** Play; `execute_luau` to count `ArenaDressing` children (expect 7×4 torch posts + 7×4 heads + 7×12 orbs + 1 banner + 2 posts) and confirm `PointLight` count == `WORLD_TORCH_LIT_FLOORS`×4 = 12. `screen_capture` an establishing shot (torches glow per-floor color; only top 3 lit; orb rings per floor; no post pierces the floor above) and a balcony shot (framed banner legible). `get_console_output` clean.

---

## Task 4: Smoke test + final verification

**Files:** Modify `docs/smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md`

- [ ] **Step 1: Add checks.** Append a section to the smoke-test doc:

```markdown
## Per-floor dressing + banner redesign (2026-06-25 polish)
13. **[ ] Per-floor torches** — every one of the 7 floors has 4 corner torches whose Neon heads glow that floor's color; only the top 3 floors cast a real PointLight + flame.
14. **[ ] No clipping** — torch posts (~12 studs) do not pierce the floor above (floors are 50 apart).
15. **[ ] Per-floor orb rings** — each floor has a 12-orb soul-palette ring; the stack reads as depth, not clutter.
16. **[ ] Framed banner** — "BODY SWAP ROYALE" shows in the framed header (glow frame, gradient, ON AIR pill) on its posts at the balcony edge, legible to waiting players.
17. **[ ] Perf glance** — with ~12 dynamic lights + flame particles, no obvious FPS drop; watch during tile erosion (Voxel re-lights). Dial `WORLD_TORCH_LIT_FLOORS` down if needed.
```

- [ ] **Step 2: Full lune suite.** `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" >/dev/null && echo "PASS $f" || echo "FAIL $f"; done` → all PASS.

- [ ] **Step 3: Commit.**
```bash
git add docs/smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md
git commit -m "docs(smoke): add per-floor dressing + banner checks"
```

---

## Self-Review (plan author)

**Spec coverage:** §2 levels → Task 1. §3.1 torches (per-floor, Neon all, light+flame top N) → Task 3 buildTorch/buildTorches + Task 2 config. §3.2 orb rings (12/floor) → Task 3 buildOrbRings + Task 2. §3.3 framed banner → Task 3 buildBanner + Task 2 WORLD_BANNER_*. §4 config migration → Task 2. §5 perf (12 lights, capped flames) → Task 2/3. §6 testing → Tasks 1/3/4.

**Placeholder scan:** none.

**Type consistency:** `desc.levels[i] = {y, color}` produced in Task 1, consumed in Task 3 (`lv.y`, `lv.color`). `desc.footprint.X/.Y` used as X/Z extents (matches Slice 1). Config keys added in Task 2 are exactly those referenced in Task 3 (`WORLD_TORCH_*`, `WORLD_BANNER_*`, `WORLD_NEAR_ORB_*`). `ArenaDescriptor.validate` returns desc (chained in `start()`).
