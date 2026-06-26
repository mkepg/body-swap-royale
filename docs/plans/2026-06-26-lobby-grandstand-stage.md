# Lobby Grandstand Stage (World Slice 2) Implementation Plan

**Goal:** Redress the between-round lobby balcony into a festival grandstand stage ("Magic-Hour Fair": warm festoon lights + U-wrap soul-orb crowd against the cool dusk/aurora) — 100% client-cosmetic, add-only, server geometry untouched.

**Architecture:** Three new pure `WorldLayout` helpers (`tierRows`, `festoonStrand`, `buntingFlags`, lune-tested) supply placement math; a new client `LobbyStage` module turns them into non-colliding cosmetic parts over the untouched load-bearing `LobbyArea` balcony, reusing `WorldShell`'s cheer pattern; a new `Config.LOBBY_STAGE_*` block holds all tunables + hybrid asset fields (blank ⇒ code fallback). Hybrid assets are sourced via Studio MCP last, with the slice fully shippable on fallbacks.

**Tech Stack:** Roblox Luau, Rojo project; pure modules tested with lune (`lune run tests/<name>.spec`); client glue verified via Studio MCP + a smoke-test doc.

**Spec:** `docs/specs/2026-06-26-lobby-grandstand-stage-design.md`

**Conventions for every task:**
- Run lune tests with: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`
- Pure modules (`src/shared/WorldLayout.luau`) must stay Roblox-free (no `Vector3`/`Color3`/`os.clock`/global RNG).
- All cosmetic parts in `LobbyStage` are `Anchored=true, CanCollide=false, CanQuery=false, CanTouch=false, CastShadow=false` (load-bearing invariant: nothing becomes a foothold over the railing).
---

## Task 1: `WorldLayout.tierRows` — U-wrap crowd slot math (pure, TDD)

**Files:**
- Modify: `src/shared/WorldLayout.luau`
- Test: `tests/world_layout.spec.luau`

- [ ] **Step 1: Write the failing test**

Add this block to `tests/world_layout.spec.luau` immediately before the final `print("ALL WorldLayout TESTS PASSED")` line:

```lua
-- tierRows(originX, originZ, baseY, halfX, halfZ, rows, rise, depth, perSide, spacing):
-- U-wrap risers (back + 2 wings, front/+Z open). Per row: perSide back orbs +
-- perSide left + perSide right => rows*3*perSide points. y climbs per row; rows
-- recede outward; NOTHING reaches the front edge (z stays <= originZ).
do
	local ox, oz, baseY = 0, -64, 45
	local halfX, halfZ = 24, 24
	local rows, rise, depth, perSide, spacing = 3, 3.5, 3, 5, 7
	local t = WorldLayout.tierRows(ox, oz, baseY, halfX, halfZ, rows, rise, depth, perSide, spacing)
	expect(#t == rows * 3 * perSide, "tierRows count must be rows*3*perSide, got " .. #t)

	-- front edge stays open: no point at/beyond the +Z railing line.
	local maxZ = -math.huge
	for _, p in ipairs(t) do maxZ = math.max(maxZ, p.z) end
	expect(maxZ <= oz + 1e-6, "tierRows must leave the front (+Z) edge open (z <= originZ)")

	-- y spans the 3 rows (rake): lowest = baseY+rise, highest = baseY+rows*rise.
	local minY, maxY = math.huge, -math.huge
	for _, p in ipairs(t) do minY = math.min(minY, p.y); maxY = math.max(maxY, p.y) end
	expect(approx(minY, baseY + rise), "lowest row sits at baseY + rise")
	expect(approx(maxY, baseY + rows * rise), "highest row sits at baseY + rows*rise")

	-- outward recede: a back-row point in row 2 is further -Z than in row 1.
	-- (back points have x near originX; find min z per height)
	local backZ = { [1] = math.huge, [2] = math.huge, [3] = math.huge }
	for _, p in ipairs(t) do
		local r = approx(p.y, baseY + rise) and 1 or (approx(p.y, baseY + 2 * rise) and 2 or 3)
		backZ[r] = math.min(backZ[r], p.z)
	end
	expect(backZ[1] > backZ[2] and backZ[2] > backZ[3], "outer rows recede further back (-Z)")

	-- pairwise distinct
	for i = 1, #t do
		for j = i + 1, #t do
			expect(not (approx(t[i].x, t[j].x) and approx(t[i].y, t[j].y) and approx(t[i].z, t[j].z)),
				"tierRows points must be pairwise distinct")
		end
	end
	print("worldlayout: tierRows OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`
Expected: FAIL (attempt to call `WorldLayout.tierRows` — a nil value).

- [ ] **Step 3: Write minimal implementation**

In `src/shared/WorldLayout.luau`, add before the final `return WorldLayout`:

```lua
-- U-wrap crowd risers around a rectangle centered at (originX,originZ) with half-
-- extents halfX/halfZ. Three dressed edges (back -Z + left -X + right +X); the
-- front (+Z) edge is intentionally left open (pit view + victory cam). Row r
-- (1..rows) sits at y = baseY + r*rise and recedes outward by r*depth. Back run:
-- `perSide` points along X centered on originX, gap `spacing`. Wings: `perSide`
-- points filling the BACK HALF of the Z range (never crossing originZ), so no
-- point ever reaches the front. Returns { { x, y, z }, ... }.
function WorldLayout.tierRows(originX, originZ, baseY, halfX, halfZ, rows, rise, depth, perSide, spacing)
	local out = {}
	for r = 1, rows do
		local y = baseY + r * rise
		local o = r * depth
		-- back edge
		local zBack = originZ - halfZ - o
		for k = 0, perSide - 1 do
			local x = originX + (k - (perSide - 1) / 2) * spacing
			out[#out + 1] = { x = x, y = y, z = zBack }
		end
		-- wings: fill the back half along Z (z in (originZ-halfZ, originZ])
		local step = halfZ / perSide
		for k = 1, perSide do
			local z = originZ - halfZ + k * step
			out[#out + 1] = { x = originX - halfX - o, y = y, z = z } -- left wing
			out[#out + 1] = { x = originX + halfX + o, y = y, z = z } -- right wing
		end
	end
	return out
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`
Expected: PASS, prints `worldlayout: tierRows OK` and `ALL WorldLayout TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/WorldLayout.luau tests/world_layout.spec.luau
git commit -m "$(printf 'feat(world): add pure WorldLayout.tierRows for U-wrap crowd\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 2: `WorldLayout.festoonStrand` — catenary string-light points (pure, TDD)

**Files:**
- Modify: `src/shared/WorldLayout.luau`
- Test: `tests/world_layout.spec.luau`

- [ ] **Step 1: Write the failing test**

Add before the final `print("ALL WorldLayout TESTS PASSED")`:

```lua
-- festoonStrand(x1,y1,z1, x2,y2,z2, count, sag): `count` points along the segment
-- with a parabolic droop (0 at the posts, `sag` below mid). Endpoints exact; the
-- droop is symmetric about mid-span.
do
	local pts = WorldLayout.festoonStrand(0, 20, 0, 8, 20, 0, 5, 4)
	expect(#pts == 5, "festoonStrand returns `count` points")
	-- endpoints at the posts (no droop)
	expect(approx(pts[1].x, 0) and approx(pts[1].y, 20) and approx(pts[1].z, 0), "end 1 at post 1")
	expect(approx(pts[5].x, 8) and approx(pts[5].y, 20) and approx(pts[5].z, 0), "end 2 at post 2")
	-- mid-span droops by `sag`
	expect(approx(pts[3].x, 4) and approx(pts[3].y, 16), "mid-span dips by sag (20-4=16)")
	-- symmetric droop: t=0.25 and t=0.75 have equal y
	expect(approx(pts[2].y, pts[4].y), "droop symmetric about mid-span")
	-- interior points are below the endpoint height
	expect(pts[2].y < 20 and pts[3].y < 20 and pts[4].y < 20, "interior bulbs dip below the posts")
	print("worldlayout: festoonStrand OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`
Expected: FAIL (`WorldLayout.festoonStrand` is nil).

- [ ] **Step 3: Write minimal implementation**

In `src/shared/WorldLayout.luau`, add before the final `return WorldLayout`:

```lua
-- `count` bulb positions along the segment (x1,y1,z1)->(x2,y2,z2) with a parabolic
-- droop: 0 at the endpoints, `sag` studs below the lerped height at mid-span
-- (droop(t) = sag * 4t(1-t)). Approximates a hanging festoon strand.
function WorldLayout.festoonStrand(x1, y1, z1, x2, y2, z2, count, sag)
	local out = {}
	for i = 0, count - 1 do
		local t = (count == 1) and 0 or i / (count - 1)
		local droop = sag * 4 * t * (1 - t)
		out[#out + 1] = {
			x = x1 + (x2 - x1) * t,
			y = y1 + (y2 - y1) * t - droop,
			z = z1 + (z2 - z1) * t,
		}
	end
	return out
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`
Expected: PASS, prints `worldlayout: festoonStrand OK`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/WorldLayout.luau tests/world_layout.spec.luau
git commit -m "$(printf 'feat(world): add pure WorldLayout.festoonStrand catenary points\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 3: `WorldLayout.buntingFlags` — pennant placement (pure, TDD)

**Files:**
- Modify: `src/shared/WorldLayout.luau`
- Test: `tests/world_layout.spec.luau`

- [ ] **Step 1: Write the failing test**

Add before the final `print("ALL WorldLayout TESTS PASSED")`:

```lua
-- buntingFlags(x1,z1,x2,z2, y, count): `count` evenly spaced points along the
-- segment at constant height y.
do
	local f = WorldLayout.buntingFlags(-24, -64, 24, -64, 6, 5)
	expect(#f == 5, "buntingFlags returns `count` points")
	for _, p in ipairs(f) do expect(approx(p.y, 6), "bunting y is constant") end
	expect(approx(f[1].x, -24) and approx(f[5].x, 24), "endpoints at the segment ends")
	-- evenly spaced: consecutive gaps equal
	local g1 = f[2].x - f[1].x
	for i = 2, #f - 1 do
		expect(approx(f[i + 1].x - f[i].x, g1), "bunting points evenly spaced")
	end
	print("worldlayout: buntingFlags OK")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`
Expected: FAIL (`WorldLayout.buntingFlags` is nil).

- [ ] **Step 3: Write minimal implementation**

In `src/shared/WorldLayout.luau`, add before the final `return WorldLayout`:

```lua
-- `count` evenly spaced points along the segment (x1,z1)->(x2,z2) at constant
-- height `y`, for hanging pennant flags.
function WorldLayout.buntingFlags(x1, z1, x2, z2, y, count)
	local out = {}
	for i = 0, count - 1 do
		local t = (count == 1) and 0 or i / (count - 1)
		out[#out + 1] = { x = x1 + (x2 - x1) * t, y = y, z = z1 + (z2 - z1) * t }
	end
	return out
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`
Expected: PASS, prints `worldlayout: buntingFlags OK` then `ALL WorldLayout TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/WorldLayout.luau tests/world_layout.spec.luau
git commit -m "$(printf 'feat(world): add pure WorldLayout.buntingFlags placement\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 4: `Config.LOBBY_STAGE_*` tunables block

**Files:**
- Modify: `src/shared/Config.luau`

No lune test (Config uses Roblox `Vector3`/`Color3`, so it is not lune-requireable — it is verified in Studio at Task 7). This task only adds data.

- [ ] **Step 1: Add the Config block**

Append this block to `src/shared/Config.luau` immediately **before** its final `return Config` line:

```lua
-- ============ Lobby Grandstand Stage (World Slice 2) ============
-- Consumed by the client LobbyStage module to redress the lobby balcony into a
-- festival grandstand stage. Add-only + non-colliding (LobbyArea geometry is
-- server-owned and untouched). "Magic-Hour Fair": warm festoon lights against the
-- cool dusk/aurora. All heights are relative to the platform top (= LOBBY_ORIGIN.Y).

-- Stage deck: a thin cosmetic slab skinning the platform top + a lit pit-facing lip.
Config.LOBBY_STAGE_DECK_INSET = 0.5         -- shrink from pad edges so it reads as a skin
Config.LOBBY_STAGE_DECK_THICKNESS = 0.4
Config.LOBBY_STAGE_DECK_LIFT = 0.3          -- studs above the platform top face
Config.LOBBY_STAGE_DECK_COLOR = Color3.fromRGB(28, 26, 44)    -- dark broadcast deck
Config.LOBBY_STAGE_EDGE_COLOR = Color3.fromRGB(120, 230, 220) -- lit stage lip (cool accent)
Config.LOBBY_STAGE_EDGE_THICKNESS = 0.6

-- U-wrap crowd tiers (back + 2 wings; front/+Z open). Neon orbs only (no per-orb
-- light) for mobile. Heights above the platform top.
Config.LOBBY_STAGE_TIER_ROWS = 3
Config.LOBBY_STAGE_TIER_RISE = 3.5          -- studs each row climbs
Config.LOBBY_STAGE_TIER_DEPTH = 3           -- studs each row recedes outward
Config.LOBBY_STAGE_TIER_PER_SIDE = 5        -- orbs per edge per row
Config.LOBBY_STAGE_TIER_SPACING = 7         -- studs between back-row orbs
Config.LOBBY_STAGE_TIER_BASE_LIFT = 2       -- studs above platform top the first row sits
Config.LOBBY_STAGE_ORB_SIZE = 2.4

-- Festoon string-lights: warm-gold Neon bulbs in a catenary sag; real PointLights
-- capped to LOBBY_STAGE_FESTOON_LIT total (mobile budget, like WORLD_TORCH_LIT_FLOORS).
Config.LOBBY_STAGE_FESTOON_COLOR = Color3.fromRGB(255, 207, 107) -- warm gold
Config.LOBBY_STAGE_FESTOON_BULBS = 9        -- bulbs per strand
Config.LOBBY_STAGE_FESTOON_SAG = 4          -- studs of mid-span droop
Config.LOBBY_STAGE_FESTOON_BULB_SIZE = 0.7
Config.LOBBY_STAGE_FESTOON_HEIGHT = 16      -- studs above platform top the strands hang
Config.LOBBY_STAGE_FESTOON_LIT = 4          -- TOTAL real PointLights across all strands
Config.LOBBY_STAGE_LIGHT_RANGE = 18
Config.LOBBY_STAGE_LIGHT_BRIGHTNESS = 1.4

-- Bunting pennants along the back tier front.
Config.LOBBY_STAGE_BUNTING_COUNT = 10
Config.LOBBY_STAGE_BUNTING_SIZE = Vector3.new(1.6, 1.8, 0.2)
Config.LOBBY_STAGE_BUNTING_HEIGHT = 6       -- studs above platform top

-- Back crest: small festival header crowning the back tier (distinct from the kept
-- front marquee in ArenaDressing — no duplicate title).
Config.LOBBY_STAGE_CREST_SIZE = Vector3.new(20, 5, 0.5)
Config.LOBBY_STAGE_CREST_HEIGHT = 17        -- studs above platform top
Config.LOBBY_STAGE_CREST_TEXT = "★ SOUL FESTIVAL ★"
Config.LOBBY_STAGE_CREST_BG = Color3.fromRGB(58, 42, 92)
Config.LOBBY_STAGE_CREST_TEXT_COLOR = Color3.fromRGB(255, 227, 166)

-- Crowd cheer (mirror WORLD_CROWD_* so the grandstand reacts like the distant crowd).
Config.LOBBY_STAGE_IDLE_SPEED = 0.5
Config.LOBBY_STAGE_IDLE_AMP = 0.4
Config.LOBBY_STAGE_CHEER_BOB = 6            -- studs an orb pops up on a cheer
Config.LOBBY_STAGE_CHEER_SCALE = 0.5        -- orb size pop fraction at full cheer
Config.LOBBY_STAGE_CHEER_SECONDS = 0.5      -- cheer decay time

-- Hybrid asset fields (blank "" ⇒ code fallback, per the WORLD_SKYBOX idiom). Set
-- by Studio MCP sourcing in the final task; the slice ships fully on fallbacks.
Config.LOBBY_STAGE_DECK_TEXTURE = ""        -- Texture id for the deck top
Config.LOBBY_STAGE_ORB_MESH = ""            -- MeshId for crowd orbs
Config.LOBBY_STAGE_FESTOON_MESH = ""        -- MeshId for festoon bulbs
Config.LOBBY_STAGE_BUNTING_TEXTURE = ""     -- Texture id for pennant flags
```

- [ ] **Step 2: Sanity-check the edit**

Confirm the block sits before `return Config` and that you didn't paste it twice. Check one representative field appears exactly once:

Run: `grep -n "Config.LOBBY_STAGE_DECK_INSET" src/shared/Config.luau`
Expected: exactly **1** matching line. If 2+, you duplicated the block — remove the extra copy.

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "$(printf 'feat(world): add LOBBY_STAGE_* config for the grandstand stage\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 5: `LobbyStage` client module + bootstrap wiring

**Files:**
- Create: `src/client/LobbyStage.luau`
- Modify: `src/client/init.client.luau`

No lune test (Roblox-coupled client glue — verified in Studio at Task 7, same as `WorldShell`/`ArenaDressing`). Write the complete module, then wire it into the bootstrap.

- [ ] **Step 1: Create `src/client/LobbyStage.luau` with this exact content**

```lua
--[[
	LobbyStage (client) -- World Slice 2: redresses the between-round lobby balcony
	into a festival grandstand stage. 100% local cosmetic, ADD-ONLY: the load-bearing
	LobbyArea geometry (platform / walls / glass railing) is server-owned and untouched;
	every part built here is non-colliding/non-querying/shadow-less, so nothing can
	become a foothold over the railing.

	"Magic-Hour Fair": warm-gold festoon lights + bunting against the cool dusk/aurora
	sky. A U-wrap soul-orb crowd (back + 2 wings; front/+Z left open for the pit view +
	victory cam) cheers on eliminations/wins, reusing WorldShell's decaying-impulse
	pattern. Hybrid assets fall back to code when the Config asset fields are blank.

	Location: StarterPlayerScripts/Client/LobbyStage (ModuleScript)
	Connections are session-lifetime (matches WorldShell/ArenaDressing).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local WorldLayout = require(Shared:WaitForChild("WorldLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local EliminationEvent = Remotes.get("EliminationEvent")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local LobbyStage = {}

local function newFolder()
	local f = workspace:FindFirstChild("LobbyStage")
	if f then f:Destroy() end
	f = Instance.new("Folder")
	f.Name = "LobbyStage"
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

-- platform top face (LOBBY_ORIGIN is the pad surface center, so top = its Y).
local function topY()
	return Config.LOBBY_ORIGIN.Y
end

-- Cosmetic deck skin over the platform + a lit pit-facing lip.
local function buildStageDeck(folder)
	local pad = Config.LOBBY_PAD_SIZE
	local inset = Config.LOBBY_STAGE_DECK_INSET
	local deck = rigPart(
		Vector3.new(pad.X - inset * 2, Config.LOBBY_STAGE_DECK_THICKNESS, pad.Z - inset * 2),
		Config.LOBBY_ORIGIN + Vector3.new(0, Config.LOBBY_STAGE_DECK_LIFT, 0),
		Config.LOBBY_STAGE_DECK_COLOR, Enum.Material.SmoothPlastic, folder)
	deck.Name = "StageDeck"
	if Config.LOBBY_STAGE_DECK_TEXTURE ~= "" then
		local tex = Instance.new("Texture")
		tex.Face = Enum.NormalId.Top
		tex.Texture = Config.LOBBY_STAGE_DECK_TEXTURE
		tex.StudsPerTileU = 8
		tex.StudsPerTileV = 8
		tex.Parent = deck
	end
	-- warm/lit lip along the +Z (pit-facing) edge
	local lip = rigPart(
		Vector3.new(pad.X - inset * 2, Config.LOBBY_STAGE_DECK_THICKNESS * 1.2, Config.LOBBY_STAGE_EDGE_THICKNESS),
		Config.LOBBY_ORIGIN + Vector3.new(0, Config.LOBBY_STAGE_DECK_LIFT + 0.1,
			pad.Z / 2 - inset - Config.LOBBY_STAGE_EDGE_THICKNESS),
		Config.LOBBY_STAGE_EDGE_COLOR, Enum.Material.Neon, folder)
	lip.Name = "StageLip"
end

-- U-wrap soul-orb crowd; one Heartbeat drives idle wobble + decaying cheer pop.
local tierOrbs = {}
local function buildCrowdTiers(folder)
	local pad = Config.LOBBY_PAD_SIZE
	local palette = Config.SOUL_PALETTE
	local slots = WorldLayout.tierRows(
		Config.LOBBY_ORIGIN.X, Config.LOBBY_ORIGIN.Z,
		topY() + Config.LOBBY_STAGE_TIER_BASE_LIFT,
		pad.X / 2, pad.Z / 2,
		Config.LOBBY_STAGE_TIER_ROWS, Config.LOBBY_STAGE_TIER_RISE,
		Config.LOBBY_STAGE_TIER_DEPTH, Config.LOBBY_STAGE_TIER_PER_SIDE,
		Config.LOBBY_STAGE_TIER_SPACING)
	for i, s in ipairs(slots) do
		local color = palette[WorldLayout.paletteIndex(i, #palette)]
		local sz = Config.LOBBY_STAGE_ORB_SIZE
		local orb = rigPart(Vector3.new(sz, sz, sz), Vector3.new(s.x, s.y, s.z),
			color, Enum.Material.Neon, folder)
		orb.Shape = Enum.PartType.Ball
		orb.Name = "CrowdOrb"
		if Config.LOBBY_STAGE_ORB_MESH ~= "" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = Config.LOBBY_STAGE_ORB_MESH
			mesh.Parent = orb
		end
		tierOrbs[#tierOrbs + 1] = {
			part = orb, base = orb.Position, baseSize = sz,
			phase = (s.x + s.z), cheer = 0,
		}
	end
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() * Config.LOBBY_STAGE_IDLE_SPEED * math.pi * 2
		for _, e in ipairs(tierOrbs) do
			local p = e.part
			if p.Parent then
				local idle = math.sin(t + e.phase) * Config.LOBBY_STAGE_IDLE_AMP
				local pop = e.cheer * Config.LOBBY_STAGE_CHEER_BOB
				p.Position = e.base + Vector3.new(0, idle + pop, 0)
				local s = e.baseSize * (1 + e.cheer * Config.LOBBY_STAGE_CHEER_SCALE)
				p.Size = Vector3.new(s, s, s)
				if e.cheer > 0 then
					e.cheer = math.max(0, e.cheer - dt / Config.LOBBY_STAGE_CHEER_SECONDS)
				end
			end
		end
	end)
end

-- Festoon: warm-gold Neon bulbs in a catenary sag along the back + both wings.
-- Real PointLights are capped to LOBBY_STAGE_FESTOON_LIT total across all strands.
local litBudget = 0
local function buildStrand(folder, x1, z1, x2, z2)
	local y = topY() + Config.LOBBY_STAGE_FESTOON_HEIGHT
	local pts = WorldLayout.festoonStrand(x1, y, z1, x2, y, z2,
		Config.LOBBY_STAGE_FESTOON_BULBS, Config.LOBBY_STAGE_FESTOON_SAG)
	local sz = Config.LOBBY_STAGE_FESTOON_BULB_SIZE
	for _, pt in ipairs(pts) do
		local bulb = rigPart(Vector3.new(sz, sz, sz), Vector3.new(pt.x, pt.y, pt.z),
			Config.LOBBY_STAGE_FESTOON_COLOR, Enum.Material.Neon, folder)
		bulb.Shape = Enum.PartType.Ball
		bulb.Name = "FestoonBulb"
		if Config.LOBBY_STAGE_FESTOON_MESH ~= "" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh
			mesh.MeshId = Config.LOBBY_STAGE_FESTOON_MESH
			mesh.Parent = bulb
		end
		if litBudget < Config.LOBBY_STAGE_FESTOON_LIT then
			litBudget += 1
			local light = Instance.new("PointLight")
			light.Color = Config.LOBBY_STAGE_FESTOON_COLOR
			light.Range = Config.LOBBY_STAGE_LIGHT_RANGE
			light.Brightness = Config.LOBBY_STAGE_LIGHT_BRIGHTNESS
			light.Parent = bulb
		end
	end
end

local function buildFestoon(folder)
	litBudget = 0
	local pad = Config.LOBBY_PAD_SIZE
	local hx, hz = pad.X / 2, pad.Z / 2
	local ox, oz = Config.LOBBY_ORIGIN.X, Config.LOBBY_ORIGIN.Z
	buildStrand(folder, ox - hx, oz - hz, ox + hx, oz - hz) -- back (-Z)
	buildStrand(folder, ox - hx, oz - hz, ox - hx, oz + hz) -- left wing (-X)
	buildStrand(folder, ox + hx, oz - hz, ox + hx, oz + hz) -- right wing (+X)
end

-- Bunting pennants hanging along the back tier front (player-palette triangles).
local function buildBunting(folder)
	local pad = Config.LOBBY_PAD_SIZE
	local hx, hz = pad.X / 2, pad.Z / 2
	local ox, oz = Config.LOBBY_ORIGIN.X, Config.LOBBY_ORIGIN.Z
	local palette = Config.SOUL_PALETTE
	local y = topY() + Config.LOBBY_STAGE_BUNTING_HEIGHT
	local flags = WorldLayout.buntingFlags(ox - hx, oz - hz, ox + hx, oz - hz, y, Config.LOBBY_STAGE_BUNTING_COUNT)
	for i, fl in ipairs(flags) do
		local color = palette[WorldLayout.paletteIndex(i, #palette)]
		if Config.LOBBY_STAGE_BUNTING_TEXTURE ~= "" then
			local flag = rigPart(Config.LOBBY_STAGE_BUNTING_SIZE, Vector3.new(fl.x, fl.y, fl.z),
				color, Enum.Material.SmoothPlastic, folder)
			flag.Name = "BuntingFlag"
			local tex = Instance.new("Texture")
			tex.Face = Enum.NormalId.Front
			tex.Texture = Config.LOBBY_STAGE_BUNTING_TEXTURE
			tex.Parent = flag
		else
			local flag = Instance.new("WedgePart")
			flag.Anchored = true
			flag.CanCollide = false
			flag.CanQuery = false
			flag.CanTouch = false
			flag.CastShadow = false
			flag.Material = Enum.Material.SmoothPlastic
			flag.Size = Config.LOBBY_STAGE_BUNTING_SIZE
			flag.Color = color
			flag.CFrame = CFrame.new(fl.x, fl.y, fl.z) * CFrame.Angles(math.pi, 0, 0) -- point the flag down
			flag.Name = "BuntingFlag"
			flag.Parent = folder
		end
	end
end

-- Small festival crest crowning the back tier; faces into the stage (+Z / Back).
local function buildBackCrest(folder)
	local pad = Config.LOBBY_PAD_SIZE
	local pos = Config.LOBBY_ORIGIN + Vector3.new(0, Config.LOBBY_STAGE_CREST_HEIGHT, -pad.Z / 2)
	local panel = rigPart(Config.LOBBY_STAGE_CREST_SIZE, pos,
		Config.LOBBY_STAGE_CREST_BG, Enum.Material.SmoothPlastic, folder)
	panel.Name = "BackCrest"

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- +Z, toward the stage / players' backs / the pit beyond
	gui.CanvasSize = Vector2.new(400, 100)
	gui.LightInfluence = 0
	gui.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = Config.LOBBY_STAGE_CREST_TEXT
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Config.LOBBY_STAGE_CREST_TEXT_COLOR
	label.Parent = gui
end

local function cheer()
	for _, e in ipairs(tierOrbs) do
		e.cheer = 0.6 + math.random() * 0.4
	end
end

function LobbyStage.start()
	local folder = newFolder()
	buildStageDeck(folder)
	buildCrowdTiers(folder)
	buildFestoon(folder)
	buildBunting(folder)
	buildBackCrest(folder)

	-- Reuse WorldShell's cheer triggers: the grandstand cheers on any elimination
	-- and on a winner being named (with a second pop), additive to the distant crowd.
	EliminationEvent.OnClientEvent:Connect(function() cheer() end)
	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state and state.phase == "Ended" and state.winnerName then
			cheer()
			task.delay(0.25, cheer)
		end
	end)
end

return LobbyStage
```

- [ ] **Step 2: Wire it into the bootstrap**

In `src/client/init.client.luau`, add the require after the `ArenaDressing` require (line 18):

```lua
local ArenaDressing = require(script.ArenaDressing)
local LobbyStage = require(script.LobbyStage)
```

and add the start call after `ArenaDressing.start()` (line 27):

```lua
ArenaDressing.start()
LobbyStage.start()
```

- [ ] **Step 3: Verify the module parses (no test runtime, just confirm structure)**

Confirm the file ends with `return LobbyStage` and that `init.client.luau` now has both the require line and the start call:

Run: `grep -n "LobbyStage" src/client/init.client.luau`
Expected: **2** matching lines — `local LobbyStage = require(script.LobbyStage)` and `LobbyStage.start()`. If only 1, you missed the start call.

- [ ] **Step 4: Commit**

```bash
git add src/client/LobbyStage.luau src/client/init.client.luau
git commit -m "$(printf 'feat(world): build the lobby grandstand stage (Slice 2)\n\nAdd-only client LobbyStage: deck, U-wrap soul crowd, festoon lights,\nbunting, back crest. Reuses WorldShell cheer triggers. Server geometry\nuntouched; hybrid assets fall back to code.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 6: Smoke-test doc

**Files:**
- Create: `docs/smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md`

- [ ] **Step 1: Write the smoke-test doc with this content**

```markdown
# Lobby Grandstand Stage — Smoke Test (2026-06-26)

**Slice:** World Slice 2 (Lobby Hub Redress). **Spec:** `docs/specs/2026-06-26-lobby-grandstand-stage-design.md`.
**Nature:** 100% client-cosmetic. Single-client is sufficient for look & feel; a 2-client pass is only needed for the cheer reactivity (step 3).

Keep `Config.HAZARDS_ENABLED = false` so the floor stays safe while observing the lobby.

## 1. Look & feel (single client)
- Join and stand on the balcony. Confirm the redress is present:
  - [ ] **Stage deck** skinning the platform with a lit pit-facing **lip**.
  - [ ] **U-wrap soul crowd**: raked orb tiers wrap the back and both wings; the **front (pit) side is open** (no orbs blocking the downward view).
  - [ ] **Warm-gold festoon lights** strung overhead (back + wings) with a visible droop.
  - [ ] **Bunting** pennants along the back, in player-palette colors.
  - [ ] **Back crest** ("★ SOUL FESTIVAL ★") crowning the back tier.
  - [ ] The **front marquee** (Slice 1b) is still present and unchanged over the pit.
- [ ] **Magic-Hour read:** the warm lights/bunting sit against the unchanged **cool dusk + teal/violet aurora** sky (warm vs cool contrast).

## 2. Load-bearing invariant (single client)
- [ ] Walk the controlled body into the railing and into every tier/deck/light — it **cannot** walk through onto a tier or off the edge.
- [ ] **Jump** at the railing and under the festoon — no added part is a foothold; the body cannot get over the railing into the void. (All LobbyStage parts are non-colliding.)

## 3. Cheer reactivity (2 clients, or forced)
- [ ] Trigger an elimination (drop a body into the void with 3+ players, or `RoundManager.forceSwap()` then eliminate). The **grandstand orbs pop/cheer** (alongside the distant WorldShell crowd).
- [ ] On a winner being named (round end), the grandstand orbs cheer again (double pop).
- [ ] A disconnect-decided round (no winner) does **not** trigger a winner cheer.

## 4. Victory cam unobstructed (2 clients)
- [ ] During the Ended window, the camera frames the winner in the pit with **no grandstand geometry** intruding into the shot.

## 5. Performance
- [ ] On the lobby with the new lights, FPS is stable (real PointLights are capped to `Config.LOBBY_STAGE_FESTOON_LIT`). Note any drop on a mid-tier/mobile profile.

## Result
- Date run / client(s) / outcome:
- Tuning notes (Config values changed):
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md
git commit -m "$(printf 'docs(smoke): add lobby grandstand stage smoke test\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 7: Studio MCP visual verification + hybrid asset sourcing (gated)

**Files:**
- Possibly modify: `src/shared/Config.luau` (set `LOBBY_STAGE_*` asset fields + tune values)

This task is interactive and **gated on Studio MCP availability**. If MCP is unavailable, record that and stop — the slice ships fully on code fallbacks (Tasks 1–6); revisit when Studio is connected.

- [ ] **Step 1: Confirm Studio MCP is live**

Use `list_roblox_studios`, then `get_studio_state` / `set_active_studio`. If no studio is connected, write "MCP unavailable — shipping on fallbacks" into the smoke-test doc's Result section and **skip to the plan's completion**.

- [ ] **Step 2: Sync + build the place**

Ensure the Rojo project is synced into the connected Studio so `LobbyStage` runs on play. Enter play (or run the client) so `workspace.LobbyStage` is built.

- [ ] **Step 3: Visually verify (against workspace instances, not stateful modules)**

`screen_capture` the lobby. Confirm against `workspace.LobbyStage`:
- deck + lit lip present; U-wrap crowd with the **front open**; festoon droop reads; bunting + back crest present; front marquee intact; warm-vs-cool contrast holds; nothing intrudes on the forward pit view.
- Use `inspect_instance` on `workspace.LobbyStage` to confirm part counts and that every part has `CanCollide=false`.
- Tune any `Config.LOBBY_STAGE_*` value as needed and re-verify (e.g. tier heights, festoon height, crest facing/position).

- [ ] **Step 4: Source hybrid assets (optional within this task)**

For each of the four asset slots, use the MCP asset tools (`search_asset` / `insert_asset` / `generate_mesh` / `generate_material` as appropriate) to source a fitting asset, then set the matching `Config.LOBBY_STAGE_*` field to its id and re-verify the builder uses it (and that blanking it restores the fallback). Sourced assets land in the project owner's inventory. Any slot may be left `""` (fallback) if no suitable asset is found.

- [ ] **Step 5: Record + commit any tuning**

Fill in the smoke-test doc Result section (date, outcome, Config values changed). If any Config values or asset ids changed:

```bash
git add src/shared/Config.luau docs/smoke-tests/2026-06-26-lobby-grandstand-stage-smoke-test.md
git commit -m "$(printf 'chore(world): MCP-verify + tune lobby grandstand stage\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Completion

When Tasks 1–6 are done (and Task 7 done or recorded-as-skipped):
- Lune: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec` is green (all helpers incl. the 3 new ones).
- The lobby reads as a festival grandstand stage with the pit view, victory cam, and load-bearing fall protection unchanged.
- On finishing the branch: this also flips roadmap Slice 2 to 🟢 and links the plan, then integrates `feat/lobby-grandstand-stage`.
```
