# Broadcast World Shell ("Soul Festival Sky") Implementation Plan

**Goal:** Build a bright, festive, arena-agnostic broadcast world ("Soul Festival Sky") that surrounds the arena so the game world feels alive instead of floating in void — Slice 1 of the world-enrichment effort.

**Architecture:** 100% client-side cosmetic (built in `StarterPlayerScripts/Client`, zero server cost, zero replication). Two layers separated by a contract: **Layer 1** = arena-agnostic shell (dusk atmosphere, soul-wisps, swap-reactive aurora, distant soul-orb crowd); **Layer 2** = footprint-parametric local dressing (spotlights, marquee, near orbs) driven by an `ArenaDescriptor`. The hex arena is the first descriptor consumer. Pure placement math lives in a Roblox-free `WorldLayout` module, lune-tested like `HexGrid`.

**Tech Stack:** Luau, Rojo, lune (unit tests for pure modules), Roblox Studio MCP (visual verification + asset sourcing). Spec: `docs/specs/2026-06-25-broadcast-world-shell-design.md`. Roadmap: `docs/world-enrichment-roadmap.md`.

**Conventions to honor:**
- Pure logic in Roblox-free, lune-tested modules (`require("../src/shared/X")`, `expect`/`fail` helpers, final `print("ALL ... PASSED")`). Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`.
- Client glue isn't lune-testable → verified via Studio MCP `screen_capture` + a manual smoke-test doc (the project's established path for non-pure code).
- Every sourced asset has a code-only fallback; the shell must render with all assetIds blank.
- Client event connections are session-lifetime (matches `SoulController`/`ClientRoundHud`); transient flare/cheer tweens self-clean.

---

## File Structure

| File | Responsibility | Tested by |
|------|----------------|-----------|
| `src/shared/WorldLayout.luau` (create) | Pure placement math: ring, wisp field, footprint corners, palette index. Roblox-free. | lune |
| `tests/world_layout.spec.luau` (create) | Unit tests for `WorldLayout`. | — |
| `src/shared/ArenaDescriptor.luau` (create) | Thin data builder: `ArenaDescriptor.hex()` → `{center,footprint,depth,accent}` from Config. Uses Roblox types (glue). | MCP probe |
| `src/shared/Config.luau` (modify) | Add `WORLD_*` tunables + assetId fields (with blank-fallback semantics). | — |
| `src/client/WorldShell.luau` (create) | Layer 1: atmosphere, sky, wisps, aurora (flare on swap), distant orb crowd (cheer on elim/win). | MCP screen_capture + smoke |
| `src/client/ArenaDressing.luau` (create) | Layer 2: spotlights, marquee, near orbs from the descriptor. | MCP screen_capture + smoke |
| `src/client/init.client.luau` (modify) | Require + start `WorldShell` and `ArenaDressing`. | — |
| `docs/smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md` (create) | Manual verification procedure. | — |

---

## Task 1: `WorldLayout` pure placement module (TDD)

**Files:**
- Create: `tests/world_layout.spec.luau`
- Create: `src/shared/WorldLayout.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/world_layout.spec.luau`:

```lua
local WorldLayout = require("../src/shared/WorldLayout")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function approx(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- ring(cx, cz, radius, count): `count` points, each exactly `radius` from center.
do
	local pts = WorldLayout.ring(10, -5, 20, 8)
	expect(#pts == 8, "ring must return `count` points")
	for _, p in ipairs(pts) do
		local d = math.sqrt((p.x - 10) ^ 2 + (p.z + 5) ^ 2)
		expect(approx(d, 20, 1e-4), "each ring point must be `radius` from center, got " .. d)
	end
	-- first point starts at angle 0 (+X axis)
	expect(approx(pts[1].x, 30) and approx(pts[1].z, -5), "ring point 1 must be at +X")
	print("worldlayout: ring OK")
end

-- paletteIndex(i, len): 1-based, wraps.
do
	expect(WorldLayout.paletteIndex(1, 8) == 1, "paletteIndex(1,8)==1")
	expect(WorldLayout.paletteIndex(8, 8) == 8, "paletteIndex(8,8)==8")
	expect(WorldLayout.paletteIndex(9, 8) == 1, "paletteIndex wraps to 1")
	expect(WorldLayout.paletteIndex(10, 8) == 2, "paletteIndex(10,8)==2")
	print("worldlayout: paletteIndex OK")
end

-- footprintCorners(cx, cz, footX, footZ, margin): 4 corners at half-extent + margin.
do
	local c = WorldLayout.footprintCorners(0, 0, 60, 40, 5)
	expect(#c == 4, "must be 4 corners")
	-- half extents: x=30+5=35, z=20+5=25
	expect(approx(c[1].x, -35) and approx(c[1].z, -25), "corner 1 = (-35,-25)")
	expect(approx(c[3].x, 35) and approx(c[3].z, 25), "corner 3 = (35,25)")
	print("worldlayout: footprintCorners OK")
end

-- wispField is deterministic for a seed, count is exact, points are in-bounds,
-- colorIndex wraps over paletteLen.
do
	local a = WorldLayout.wispField(0, 100, 0, 50, 40, 12, 8, 1234)
	local b = WorldLayout.wispField(0, 100, 0, 50, 40, 12, 8, 1234)
	expect(#a == 12, "wispField count exact")
	for i = 1, #a do
		expect(approx(a[i].x, b[i].x) and approx(a[i].y, b[i].y) and approx(a[i].z, b[i].z),
			"wispField must be deterministic for a seed")
		expect(a[i].x >= -50 and a[i].x <= 50, "wisp x in [-spread,spread]")
		expect(a[i].y >= 100 and a[i].y <= 140, "wisp y in [cy, cy+height]")
		expect(a[i].colorIndex >= 1 and a[i].colorIndex <= 8, "colorIndex within palette")
	end
	local c = WorldLayout.wispField(0, 100, 0, 50, 40, 12, 8, 9999)
	expect(not (approx(a[1].x, c[1].x) and approx(a[1].z, c[1].z)), "different seed -> different field")
	print("worldlayout: wispField OK")
end

print("ALL WorldLayout TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec.luau`
Expected: FAIL — module `../src/shared/WorldLayout` not found.

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/WorldLayout.luau`:

```lua
--[[
	WorldLayout -- PURE placement math for the broadcast world shell.
	Location (Roblox): ReplicatedStorage/Shared/WorldLayout (ModuleScript)

	No Roblox APIs (no Vector3/Color3), no os.clock, no math.random global state.
	Number-in / number-out; client glue (WorldShell/ArenaDressing) turns the
	returned offsets into Vector3s. Mirrors the project's other pure modules
	(HexGrid, SpawnLayout) so it is lune-testable without Roblox.
--]]

local WorldLayout = {}

-- `count` evenly spaced points on a circle of `radius` around (cx, cz).
-- Returns { { x, z }, ... }. Point 1 is at angle 0 (the +X axis), going CCW.
function WorldLayout.ring(cx, cz, radius, count)
	local out = {}
	for i = 0, count - 1 do
		local a = (2 * math.pi * i) / count
		out[#out + 1] = { x = cx + radius * math.cos(a), z = cz + radius * math.sin(a) }
	end
	return out
end

-- 1-based palette index for the i-th element, wrapping over `len`.
function WorldLayout.paletteIndex(i, len)
	return (i - 1) % len + 1
end

-- The 4 corners of a rectangular footprint (cx,cz / footX,footZ extents),
-- pushed outward by `margin`. Order: (-,-), (+,-), (+,+), (-,+).
function WorldLayout.footprintCorners(cx, cz, footX, footZ, margin)
	local hx = footX / 2 + margin
	local hz = footZ / 2 + margin
	return {
		{ x = cx - hx, z = cz - hz },
		{ x = cx + hx, z = cz - hz },
		{ x = cx + hx, z = cz + hz },
		{ x = cx - hx, z = cz + hz },
	}
end

-- Deterministic pseudo-random wisp positions inside a box volume centered at
-- (cx,cy,cz): x,z in [-spread,spread], y in [cy, cy+height]. Uses a seeded LCG
-- (no global RNG) so tests are stable. colorIndex wraps over `paletteLen`.
function WorldLayout.wispField(cx, cy, cz, spread, height, count, paletteLen, seed)
	local out = {}
	local s = seed % 2147483647
	if s <= 0 then s += 2147483646 end
	local function rnd()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
	for i = 1, count do
		out[#out + 1] = {
			x = cx + (rnd() * 2 - 1) * spread,
			y = cy + rnd() * height,
			z = cz + (rnd() * 2 - 1) * spread,
			colorIndex = (i - 1) % paletteLen + 1,
		}
	end
	return out
end

return WorldLayout
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec.luau`
Expected: PASS — ends with `ALL WorldLayout TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/WorldLayout.luau tests/world_layout.spec.luau
git commit -m "feat(world): pure WorldLayout placement math (ring/wisp/corners/palette)"
```

---

## Task 2: `Config` WORLD_* tunables

**Files:**
- Modify: `src/shared/Config.luau` (append a new block before `return Config`)

- [ ] **Step 1: Add the WORLD_* block**

In `src/shared/Config.luau`, immediately before the final `return Config` line, insert:

```lua
-- ===== Broadcast World Shell ("Soul Festival Sky") -- Slice 1 ============
-- All client-side cosmetic. Every assetId below has a code-only fallback: an
-- empty string ("") means "skip the asset, use the procedural fallback", so the
-- shell renders with no uploaded assets. Reuses Config.SOUL_PALETTE for colors.

-- Atmosphere / lighting grade (warm dusk: amber -> rose -> violet). Set client-side.
Config.WORLD_CLOCK_TIME = 17.2                                  -- golden-hour sun angle
Config.WORLD_AMBIENT = Color3.fromRGB(95, 70, 110)             -- soft violet fill
Config.WORLD_OUTDOOR_AMBIENT = Color3.fromRGB(150, 110, 130)   -- warm outdoor fill
Config.WORLD_FOG_COLOR = Color3.fromRGB(255, 175, 150)         -- warm haze
Config.WORLD_ATMOSPHERE_DENSITY = 0.32
Config.WORLD_ATMOSPHERE_HAZE = 2.2
Config.WORLD_BLOOM_INTENSITY = 0.9
Config.WORLD_COLORCORRECTION_TINT = Color3.fromRGB(255, 225, 235)
Config.WORLD_COLORCORRECTION_SATURATION = 0.12
-- Dusk skybox: six face assetIds. Leave all "" to use the gradient fallback
-- (Atmosphere + Lighting tint only, no Sky instance).
Config.WORLD_SKYBOX = { Up = "", Down = "", Left = "", Right = "", Front = "", Back = "" }

-- Soul-wisps: drifting glowing orbs colored from SOUL_PALETTE, high in the sky.
Config.WORLD_WISP_COUNT = 22            -- mobile-budgeted default
Config.WORLD_WISP_CENTER_Y = 140        -- height above arena center the field sits at
Config.WORLD_WISP_SPREAD = 220          -- horizontal half-extent of the field
Config.WORLD_WISP_HEIGHT = 80           -- vertical thickness of the field
Config.WORLD_WISP_SIZE = 3              -- stud diameter of each wisp
Config.WORLD_WISP_DRIFT_SPEED = 0.4     -- bob cycles/sec
Config.WORLD_WISP_DRIFT_AMP = 6         -- bob amplitude (studs)
Config.WORLD_WISP_SEED = 20260625       -- deterministic field seed

-- Aurora ribbon overhead; flares (brightens) briefly on each swap.
Config.WORLD_AURORA_Y = 200             -- height of the ribbon
Config.WORLD_AURORA_SIZE = Vector3.new(800, 0.2, 220)
Config.WORLD_AURORA_BASE_TRANSPARENCY = 0.85
Config.WORLD_AURORA_FLARE_TRANSPARENCY = 0.45
Config.WORLD_AURORA_FLARE_SECONDS = 1.1

-- Distant soul-orb crowd: a far ring on the horizon that cheers (bobs) on events.
Config.WORLD_CROWD_RADIUS = 420
Config.WORLD_CROWD_Y = 30
Config.WORLD_CROWD_COUNT = 48
Config.WORLD_CROWD_ORB_SIZE = 8
Config.WORLD_CROWD_CHEER_BOB = 10       -- studs an orb pops up on a cheer
Config.WORLD_CROWD_CHEER_SECONDS = 0.5

-- Layer 2 local dressing (parametric from the ArenaDescriptor).
Config.WORLD_SPOTLIGHT_MARGIN = 14      -- studs outward from the footprint corners
Config.WORLD_SPOTLIGHT_HEIGHT = 60      -- rig height above the play surface
Config.WORLD_SPOTLIGHT_RANGE = 90
Config.WORLD_SPOTLIGHT_BRIGHTNESS = 3
Config.WORLD_NEAR_ORB_RADIUS = 70       -- ring of close spectator orbs around the rim
Config.WORLD_NEAR_ORB_COUNT = 18
Config.WORLD_NEAR_ORB_Y = 6
Config.WORLD_NEAR_ORB_SIZE = 4
Config.WORLD_MARQUEE_TEXT = "BODY SWAP ROYALE"
Config.WORLD_MARQUEE_SIZE = Vector3.new(60, 12, 2)
Config.WORLD_MARQUEE_HEIGHT = 28        -- above the play surface, on the balcony side
```

- [ ] **Step 2: Sanity-check the file loads (no syntax error)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hex_grid.spec.luau`
Expected: still PASS (proves no unrelated breakage; Config isn't imported by that test but this confirms the repo's lune runner is healthy). Then visually confirm the block is well-formed Luau (balanced braces, all keys assigned).

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(world): add WORLD_* config block for the broadcast shell"
```

---

## Task 3: `ArenaDescriptor` (hex consumer)

**Files:**
- Create: `src/shared/ArenaDescriptor.luau`

- [ ] **Step 1: Write the module**

Create `src/shared/ArenaDescriptor.luau`:

```lua
--[[
	ArenaDescriptor -- the contract between the arena-agnostic world shell and a
	specific arena. Glue (uses Roblox Vector/Color types), so NOT lune-tested; the
	hex descriptor is verified by an MCP probe and the smoke test.

	Shape:
	  { center: Vector3, footprint: Vector2, depth: number, accent: Color3 }
	  center    -- arena center (X,Z) + play-surface Y
	  footprint -- X,Z extent of the course (Layer 2 dressing sizes to this)
	  depth     -- how far the course drops below the surface
	  accent    -- theme tint for this arena's dressing

	Future arenas add their own builder here; ArenaDressing consumes whichever
	descriptor it is handed and never reads arena internals.
--]]

local Shared = script.Parent
local Config = require(Shared.Config)

local ArenaDescriptor = {}

-- The Hex-A-Gone arena's descriptor, derived from the hex Config. The flat-top
-- field's world half-width is ~ HEX_SIZE * 1.5 * HEX_RADIUS; pad by one tile so
-- the dressing clears the outermost tiles. depth = floor span below the top.
function ArenaDescriptor.hex()
	local halfWidth = Config.HEX_SIZE * 1.5 * Config.HEX_RADIUS + Config.HEX_SIZE
	local extent = halfWidth * 2
	return {
		center = Vector3.new(0, Config.TILE_SURFACE_Y, 0),
		footprint = Vector2.new(extent, extent),
		depth = Config.HEX_FLOOR_GAP * (Config.HEX_FLOOR_COUNT - 1),
		accent = Config.HEX_FLOOR_COLORS[1],
	}
end

return ArenaDescriptor
```

- [ ] **Step 2: Probe the descriptor in Studio (MCP)**

In Studio (Edit mode), run via MCP `execute_luau` (datamodel_type `Edit`):

```lua
local d = require(game.ReplicatedStorage.Shared.ArenaDescriptor).hex()
return string.format("center=%s footprint=%s depth=%.0f accent=%s",
	tostring(d.center), tostring(d.footprint), d.depth, tostring(d.accent))
```

Expected: a line like `center=0, 0, 0 footprint=64, 64 depth=300 accent=...`. Confirms the module loads and the fields are the right types/values. (If a subagent lacks MCP access, the orchestrator runs this at the review checkpoint.)

- [ ] **Step 3: Commit**

```bash
git add src/shared/ArenaDescriptor.luau
git commit -m "feat(world): ArenaDescriptor contract + hex consumer"
```

---

## Task 4: `WorldShell` (Layer 1) — atmosphere, sky, wisps, aurora, crowd

**Files:**
- Create: `src/client/WorldShell.luau`

- [ ] **Step 1: Write the module**

Create `src/client/WorldShell.luau`:

```lua
--[[
	WorldShell (client) -- Layer 1 of the broadcast world: the arena-agnostic
	"Soul Festival Sky". 100% local cosmetic (no replication): dusk atmosphere,
	drifting soul-wisps, an aurora that flares on each swap, and a distant
	soul-orb crowd that cheers on eliminations/wins. Built once on start.

	Location: StarterPlayerScripts/Client/WorldShell (ModuleScript)
	Connections are session-lifetime (matches SoulController/ClientRoundHud).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local SetControlledBody = Remotes.get("SetControlledBody")
local EliminationEvent = Remotes.get("EliminationEvent")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local WorldShell = {}

local function newFolder()
	local f = workspace:FindFirstChild("WorldShell")
	if f then f:Destroy() end
	f = Instance.new("Folder")
	f.Name = "WorldShell"
	f.Parent = workspace
	return f
end

local function glowOrb(size, color, parent)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = Vector3.new(size, size, size)
	p.Color = color
	p.Parent = parent
	return p
end

-- Dusk grade + optional skybox (fallback: no Sky, gradient via atmosphere only).
local function buildAtmosphere(folder)
	Lighting.ClockTime = Config.WORLD_CLOCK_TIME
	Lighting.Ambient = Config.WORLD_AMBIENT
	Lighting.OutdoorAmbient = Config.WORLD_OUTDOOR_AMBIENT
	Lighting.FogColor = Config.WORLD_FOG_COLOR

	local atmo = Instance.new("Atmosphere")
	atmo.Density = Config.WORLD_ATMOSPHERE_DENSITY
	atmo.Haze = Config.WORLD_ATMOSPHERE_HAZE
	atmo.Color = Config.WORLD_FOG_COLOR
	atmo.Decay = Config.WORLD_FOG_COLOR
	atmo.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = Config.WORLD_BLOOM_INTENSITY
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Config.WORLD_COLORCORRECTION_TINT
	cc.Saturation = Config.WORLD_COLORCORRECTION_SATURATION
	cc.Parent = Lighting

	local sb = Config.WORLD_SKYBOX
	if sb.Up ~= "" then
		local sky = Instance.new("Sky")
		sky.SkyboxUp, sky.SkyboxDn = sb.Up, sb.Down
		sky.SkyboxLf, sky.SkyboxRt = sb.Left, sb.Right
		sky.SkyboxFt, sky.SkyboxBk = sb.Front, sb.Back
		sky.Parent = Lighting
	end
	-- Tag the effects under the folder name space by parenting clones is not
	-- needed; they live in Lighting for the session (client-only view).
end

local function buildWisps(folder)
	local palette = Config.SOUL_PALETTE
	local field = WorldLayout.wispField(
		0, Config.WORLD_WISP_CENTER_Y, 0,
		Config.WORLD_WISP_SPREAD, Config.WORLD_WISP_HEIGHT,
		Config.WORLD_WISP_COUNT, #palette, Config.WORLD_WISP_SEED)
	local wisps = {}
	for _, w in ipairs(field) do
		local orb = glowOrb(Config.WORLD_WISP_SIZE, palette[w.colorIndex], folder)
		orb.Position = Vector3.new(w.x, w.y, w.z)
		wisps[#wisps + 1] = { part = orb, baseY = w.y, phase = (w.x + w.z) }
	end
	-- One Heartbeat bob for the whole field (cheap; session-lifetime).
	RunService.Heartbeat:Connect(function()
		local t = os.clock() * Config.WORLD_WISP_DRIFT_SPEED * math.pi * 2
		for _, wp in ipairs(wisps) do
			local p = wp.part
			if p.Parent then
				p.Position = Vector3.new(
					p.Position.X,
					wp.baseY + math.sin(t + wp.phase) * Config.WORLD_WISP_DRIFT_AMP,
					p.Position.Z)
			end
		end
	end)
end

local auroraPart = nil
local function buildAurora(folder)
	auroraPart = Instance.new("Part")
	auroraPart.Name = "Aurora"
	auroraPart.Anchored = true
	auroraPart.CanCollide = false
	auroraPart.CanQuery = false
	auroraPart.CanTouch = false
	auroraPart.CastShadow = false
	auroraPart.Material = Enum.Material.Neon
	auroraPart.Size = Config.WORLD_AURORA_SIZE
	auroraPart.Position = Vector3.new(0, Config.WORLD_AURORA_Y, 0)
	auroraPart.Color = Config.SOUL_PALETTE[5] -- purple base
	auroraPart.Transparency = Config.WORLD_AURORA_BASE_TRANSPARENCY
	auroraPart.Parent = folder
end

local flareToken = nil
local function flareAurora()
	if not (auroraPart and auroraPart.Parent) then return end
	local token = {}
	flareToken = token
	auroraPart.Color = Config.SOUL_PALETTE[math.random(1, #Config.SOUL_PALETTE)]
	auroraPart.Transparency = Config.WORLD_AURORA_FLARE_TRANSPARENCY
	local tw = TweenService:Create(auroraPart,
		TweenInfo.new(Config.WORLD_AURORA_FLARE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = Config.WORLD_AURORA_BASE_TRANSPARENCY })
	tw:Play()
	task.delay(Config.WORLD_AURORA_FLARE_SECONDS, function()
		if flareToken == token then flareToken = nil end
	end)
end

local crowd = {}
local function buildCrowd(folder)
	local palette = Config.SOUL_PALETTE
	local pts = WorldLayout.ring(0, 0, Config.WORLD_CROWD_RADIUS, Config.WORLD_CROWD_COUNT)
	for i, pt in ipairs(pts) do
		local color = palette[WorldLayout.paletteIndex(i, #palette)]
		local orb = glowOrb(Config.WORLD_CROWD_ORB_SIZE, color, folder)
		orb.Position = Vector3.new(pt.x, Config.WORLD_CROWD_Y, pt.z)
		crowd[#crowd + 1] = orb
	end
end

local function cheer()
	for _, orb in ipairs(crowd) do
		if orb.Parent then
			local base = Vector3.new(orb.Position.X, Config.WORLD_CROWD_Y, orb.Position.Z)
			local up = base + Vector3.new(0, Config.WORLD_CROWD_CHEER_BOB * (0.6 + math.random() * 0.8), 0)
			orb.Position = up
			TweenService:Create(orb,
				TweenInfo.new(Config.WORLD_CROWD_CHEER_SECONDS, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
				{ Position = base }):Play()
		end
	end
end

function WorldShell.start()
	local folder = newFolder()
	buildAtmosphere(folder)
	buildWisps(folder)
	buildAurora(folder)
	buildCrowd(folder)

	-- Aurora flares when this client is told it swapped (fired to everyone at T0).
	SetControlledBody.OnClientEvent:Connect(function(_, isSwap)
		if isSwap then flareAurora() end
	end)
	-- Crowd cheers on any elimination, and a bigger cheer when a winner is named.
	EliminationEvent.OnClientEvent:Connect(function() cheer() end)
	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state and state.phase == "Ended" and state.winnerName then
			cheer()
			task.delay(0.25, cheer)
		end
	end)
end

return WorldShell
```

- [ ] **Step 2: Wire it into the client bootstrap (temporary, for verification)**

In `src/client/init.client.luau`, add the require and start (final wiring is Task 6, but it's needed to see anything):

```lua
local WorldShell = require(script.WorldShell)
```
and after the other `.start()` calls:
```lua
WorldShell.start()
```

- [ ] **Step 3: Verify in Studio (MCP)**

Start play via MCP `start_stop_play`, then `screen_capture` (camera pointed at the arena from above, e.g. position `[0, 120, 180]` looking at `[0, 0, 0]`). Confirm: warm dusk grade, glowing wisps high in the sky, an aurora band overhead, a distant ring of colored orbs on the horizon. Read `get_console_output` for errors. Stop play.

Expected: no console errors; the sky reads warm/festive with visible wisps + aurora + distant crowd. (If a subagent lacks MCP, the orchestrator performs this at the checkpoint.)

- [ ] **Step 4: Commit**

```bash
git add src/client/WorldShell.luau src/client/init.client.luau
git commit -m "feat(world): WorldShell Layer 1 (atmosphere, wisps, swap-flare aurora, crowd)"
```

---

## Task 5: `ArenaDressing` (Layer 2) — spotlights, marquee, near orbs

**Files:**
- Create: `src/client/ArenaDressing.luau`

- [ ] **Step 1: Write the module**

Create `src/client/ArenaDressing.luau`:

```lua
--[[
	ArenaDressing (client) -- Layer 2 of the broadcast world: local framing built
	parametrically from an ArenaDescriptor (never from arena internals), so any
	future arena gets dressed by publishing its own descriptor. 100% local cosmetic.

	Slice 1 dressing: spotlight rigs at the footprint corners, a "BODY SWAP ROYALE"
	marquee on the balcony side, and a near ring of soul-orb spectators.

	Location: StarterPlayerScripts/Client/ArenaDressing (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local ArenaDescriptor = require(Shared:WaitForChild("ArenaDescriptor"))

local ArenaDressing = {}

local function newFolder()
	local f = workspace:FindFirstChild("ArenaDressing")
	if f then f:Destroy() end
	f = Instance.new("Folder")
	f.Name = "ArenaDressing"
	f.Parent = workspace
	return f
end

local function rigPart(size, pos, color, material, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Parent = parent
	return p
end

local function buildSpotlights(folder, desc)
	local corners = WorldLayout.footprintCorners(
		desc.center.X, desc.center.Z,
		desc.footprint.X, desc.footprint.Y, -- Vector2.Y holds the Z extent
		Config.WORLD_SPOTLIGHT_MARGIN)
	local topY = desc.center.Y + Config.WORLD_SPOTLIGHT_HEIGHT
	for _, c in ipairs(corners) do
		local pole = rigPart(Vector3.new(2, Config.WORLD_SPOTLIGHT_HEIGHT, 2),
			Vector3.new(c.x, desc.center.Y + Config.WORLD_SPOTLIGHT_HEIGHT / 2, c.z),
			Color3.fromRGB(40, 40, 50), Enum.Material.Metal, folder)
		local head = rigPart(Vector3.new(5, 3, 5), Vector3.new(c.x, topY, c.z),
			desc.accent, Enum.Material.Neon, folder)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = 75
		light.Range = Config.WORLD_SPOTLIGHT_RANGE
		light.Brightness = Config.WORLD_SPOTLIGHT_BRIGHTNESS
		light.Color = desc.accent
		light.Parent = head
		pole.Name, head.Name = "SpotlightPole", "SpotlightHead"
	end
end

local function buildMarquee(folder, desc)
	-- Place on the balcony side (-Z), facing the arena (+Z). Balcony is at
	-- Config.LOBBY_ORIGIN; sit the marquee just in front of its edge, high up.
	local z = Config.LOBBY_ORIGIN.Z + 6
	local part = rigPart(Config.WORLD_MARQUEE_SIZE,
		Vector3.new(0, desc.center.Y + Config.WORLD_MARQUEE_HEIGHT, z),
		Color3.fromRGB(20, 16, 36), Enum.Material.SmoothPlastic, folder)
	part.Name = "Marquee"

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- +Z face, toward the arena
	gui.CanvasSize = Vector2.new(600, 120)
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = Config.WORLD_MARQUEE_TEXT
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 216, 77)
	label.Parent = gui
end

local function buildNearOrbs(folder, desc)
	local palette = Config.SOUL_PALETTE
	local pts = WorldLayout.ring(desc.center.X, desc.center.Z,
		Config.WORLD_NEAR_ORB_RADIUS, Config.WORLD_NEAR_ORB_COUNT)
	for i, pt in ipairs(pts) do
		local orb = rigPart(
			Vector3.new(Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE, Config.WORLD_NEAR_ORB_SIZE),
			Vector3.new(pt.x, desc.center.Y + Config.WORLD_NEAR_ORB_Y, pt.z),
			palette[WorldLayout.paletteIndex(i, #palette)], Enum.Material.Neon, folder)
		orb.Shape = Enum.PartType.Ball
		orb.Name = "NearOrb"
	end
end

function ArenaDressing.start()
	local folder = newFolder()
	local desc = ArenaDescriptor.hex()
	buildSpotlights(folder, desc)
	buildMarquee(folder, desc)
	buildNearOrbs(folder, desc)
end

return ArenaDressing
```

- [ ] **Step 2: Wire it in (temporary, for verification)**

In `src/client/init.client.luau`, add:
```lua
local ArenaDressing = require(script.ArenaDressing)
```
and after `WorldShell.start()`:
```lua
ArenaDressing.start()
```

- [ ] **Step 3: Verify in Studio (MCP)**

Play via `start_stop_play`; `screen_capture` from `[0, 90, 120]` looking at `[0, 0, 0]`. Confirm four spotlight rigs at the pit corners casting accent-tinted light down, a glowing "BODY SWAP ROYALE" marquee on the balcony side facing the arena, and a near ring of orbs around the rim. Check `get_console_output` for errors. Stop play.

Expected: no errors; dressing frames the pit and reads as a broadcast set.

- [ ] **Step 4: Commit**

```bash
git add src/client/ArenaDressing.luau src/client/init.client.luau
git commit -m "feat(world): ArenaDressing Layer 2 (spotlights, marquee, near orbs)"
```

---

## Task 6: Source the dusk skybox (MCP) + finalize wiring + smoke test

**Files:**
- Modify: `src/shared/Config.luau` (set `WORLD_SKYBOX` faces if an asset is sourced)
- Modify: `src/client/init.client.luau` (confirm final ordering)
- Create: `docs/smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md`

- [ ] **Step 1: Source a dusk skybox via MCP (optional, with fallback)**

Using the Studio MCP, search the catalog (`search_asset`) for a warm dusk/sunset skybox, or generate one. If a usable 6-face set (or single sky asset) is found, set the face IDs in `Config.WORLD_SKYBOX`. Verify with `screen_capture` that the horizon reads warm dusk. **If nothing acceptable is found, leave `WORLD_SKYBOX` faces as `""`** — the gradient fallback (atmosphere/lighting only) is the accepted result; do not block the slice on an asset. Note any assetIds used in the smoke-test doc (they live in the project owner's inventory).

- [ ] **Step 2: Confirm final client wiring**

Open `src/client/init.client.luau` and confirm `WorldShell` and `ArenaDressing` are required and started after the existing controllers. Final ordering should be: existing controllers, then `WorldShell.start()`, then `ArenaDressing.start()`. (They were added in Tasks 4–5; this step is the consolidation check.)

- [ ] **Step 3: Write the smoke-test doc**

Create `docs/smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md`:

```markdown
# Smoke Test — Broadcast World Shell ("Soul Festival Sky"), Slice 1

**Date:** 2026-06-25
**Scope:** Client-cosmetic world shell (WorldShell + ArenaDressing). No gameplay logic changed.
**Spec:** docs/specs/2026-06-25-broadcast-world-shell-design.md

## Setup
- Open the place in Studio. Start a 2-client play session (Play Solo is enough for visuals; 2 clients needed for the swap-flare check).

## Checks
1. **Atmosphere** — On join, the sky reads warm dusk (amber→rose→violet), not the default blue. No console errors.
2. **Wisps** — Glowing colored orbs drift/bob high above the arena; colors match the Soul palette.
3. **Aurora** — A translucent band sits overhead. On a swap (wait for the cycle, or `RoundManager.forceSwap()` from the server command bar), it briefly flares brighter, then fades back over ~1s, for every client.
4. **Distant crowd** — A ring of glowing orbs sits on the horizon. On an elimination and on the winner banner, the orbs bob ("cheer").
5. **Spotlights** — Four lit rigs stand at the pit corners, casting accent-tinted light downward.
6. **Marquee** — A glowing "BODY SWAP ROYALE" sign on the balcony side faces the arena and is readable.
7. **Near orbs** — A ring of orbs hugs the arena rim.
8. **No gameplay regression** — A normal round still runs: swaps, grace, hex erosion, void death, winner declared. The shell never blocks movement (all parts CanCollide=false) and never appears under server ownership.
9. **Fallback** — With `Config.WORLD_SKYBOX` faces blank, the dusk look still holds via atmosphere/lighting.
10. **Perf sanity** — No obvious FPS drop vs. before on a mid-tier setting.

## Result
- [ ] PASS / notes:
```

- [ ] **Step 4: Run the full lune suite (no regressions)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec.luau && lune run tests/hex_grid.spec.luau`
Expected: both end with `ALL ... PASSED`.

- [ ] **Step 5: Execute the smoke test in Studio and record the result**

Perform the checks above via MCP (`start_stop_play`, `screen_capture`, `get_console_output`; `RoundManager.forceSwap()` to force the aurora flare). Tick the boxes / fill the result line in the smoke-test doc.

- [ ] **Step 6: Commit**

```bash
git add src/shared/Config.luau src/client/init.client.luau docs/smoke-tests/2026-06-25-broadcast-world-shell-smoke-test.md
git commit -m "feat(world): finalize broadcast shell wiring + skybox + smoke test"
```

- [ ] **Step 7: Update the roadmap status**

In `docs/world-enrichment-roadmap.md`, change the Slice 1 row status from `🟡 Spec approved — implementation pending` to `🟢 Done` and link this plan. Commit:

```bash
git add docs/world-enrichment-roadmap.md
git commit -m "docs(roadmap): mark Slice 1 (broadcast world shell) done"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §2 two-layer client-cosmetic → Tasks 4/5 + init wiring. §3 modules (WorldLayout/ArenaDescriptor/WorldShell/ArenaDressing) → Tasks 1/3/4/5. §4 components (dusk atmosphere, wisps, swap-flare aurora, distant crowd; spotlights/marquee/near orbs) → Tasks 4/5. §5 hooks (SetControlledBody/EliminationEvent/RoundStateChanged, no new remotes) → Task 4. §6 hybrid assets + fallback → Task 2 (blank-default) + Task 6 (sourcing). §7 perf (client-only, Config-budgeted) → Tasks 2/4. §8 testing (lune for WorldLayout, MCP + smoke for glue) → Tasks 1/4/5/6. §9 scope (minimal Layer 2; no jumbotron/confetti) → honored. Roadmap status → Task 6 Step 7.

**Placeholder scan:** No TBD/TODO; all code is complete and inline.

**Type consistency:** `WorldLayout.ring/paletteIndex/footprintCorners/wispField` signatures match between `src/shared/WorldLayout.luau`, the tests, and both client consumers. `ArenaDescriptor.hex()` returns `{center:Vector3, footprint:Vector2, depth, accent:Color3}`; `ArenaDressing` reads `desc.center`, `desc.footprint.X/.Y`, `desc.accent` consistently. `Config.WORLD_*` keys referenced in Tasks 4/5 are all defined in Task 2. Note documented in code: `footprint` is a `Vector2` whose `.Y` field carries the Z extent (passed as the `footZ` arg).
```
