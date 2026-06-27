# Beyblade Lobby Implementation Plan

**Goal:** Replace the boxed lobby balcony with a beyblade — a round walkable disc + invisible rim barrier (server, load-bearing), dressed as a spinning top (client, cosmetic).

**Architecture:** Server `LobbyArea` builds a `CanCollide` Cylinder disc (top at `LOBBY_ORIGIN.Y`) ringed by a gap-free invisible barrier (the fall protection). Client `LobbyStage` dresses it: energy rings glowing around the disc rim, a stepped taper body to a tip, and two cheer-reactive spectator-soul clusters. Pure helpers `festoonStrand`/`buntingFlags` (now unused) are removed.

**Tech Stack:** Roblox Luau (Rojo); pure modules tested with lune; client/server glue MCP-verified.

**Spec:** `docs/specs/2026-06-27-beyblade-lobby-design.md`

**Conventions:** lune via `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`. All client `LobbyStage` parts non-colliding (`Anchored, CanCollide=false, CanQuery=false, CanTouch=false, CastShadow=false`).

---

## Task 1: Remove unused pure helpers `festoonStrand` + `buntingFlags`

**Files:** `src/shared/WorldLayout.luau`, `tests/world_layout.spec.luau`

- [ ] **Step 1:** In `tests/world_layout.spec.luau`, delete the two `do ... end` blocks that test `festoonStrand` and `buntingFlags` (each ends with `print("worldlayout: festoonStrand OK")` / `print("worldlayout: buntingFlags OK")`). Leave the `cluster`, `ring`, `paletteIndex`, `footprintCorners`, `wispField` blocks and the final `print("ALL WorldLayout TESTS PASSED")`.
- [ ] **Step 2:** In `src/shared/WorldLayout.luau`, delete the `function WorldLayout.festoonStrand(...)` and `function WorldLayout.buntingFlags(...)` definitions (and their doc comments). Leave `ring`, `paletteIndex`, `footprintCorners`, `wispField`, `cluster`.
- [ ] **Step 3:** Run `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/world_layout.spec`. Expect PASS ending `ALL WorldLayout TESTS PASSED`, with no festoonStrand/buntingFlags lines.
- [ ] **Step 4:** Confirm no remaining references: `grep -rnE "festoonStrand|buntingFlags" src/ tests/` → only matches should be NONE (LobbyStage is rewritten in a later task; if it still references them, that's fine — it's replaced wholesale in Task 4, but this grep is run BEFORE Task 4, so expect matches ONLY in `src/client/LobbyStage.luau`). Note them; they disappear in Task 4.
- [ ] **Step 5:** Commit:
```
git add src/shared/WorldLayout.luau tests/world_layout.spec.luau
git commit -m "$(printf 'refactor(world): drop unused WorldLayout.festoonStrand/buntingFlags\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 2: Config — swap lobby box block for disc/barrier + beyblade

**Files:** `src/shared/Config.luau`

- [ ] **Step 1:** Replace the lobby geometry block. Find this exact run (comment + assignments) and replace it:

REPLACE:
```lua
-- [-32,32] at surface Y=0, so the balcony sits RAISED and SET BACK behind the
-- -Z edge, facing +Z toward the arena center -- standing bodies look down into
-- the pit. The perimeter barriers are LOAD-BEARING: the pad floats over the void,
-- so a gap would let a controlled body walk off and die between rounds.
Config.LOBBY_ORIGIN = Vector3.new(0, 45, -64) -- balcony surface center
Config.LOBBY_PAD_SIZE = Vector3.new(48, 1, 48) -- platform X, thickness(Y), Z
-- LOBBY_WALL_HEIGHT must comfortably exceed a jump so a body can't hop the railing
-- into the void (JUMP_HEIGHT = 7.2; feet clear roughly that high). 12 leaves a safe
-- margin -- the front railing is transparent, so a taller wall doesn't block the view.
Config.LOBBY_WALL_HEIGHT = 12 -- perimeter barrier height (fall protection)
Config.LOBBY_WALL_THICKNESS = 1
Config.LOBBY_CAPACITY = 16 -- grid sized for up to this many bodies
Config.LOBBY_PER_ROW = 4 -- balcony grid columns (rows = ceil(CAPACITY/PER_ROW))
Config.LOBBY_SPACING = 10 -- studs between grid slots
Config.LOBBY_SPAWN_DROP = 5 -- studs above the pad a body spawns at (settles down)
Config.LOBBY_FACE_TARGET = Vector3.new(0, 0, 0) -- bodies face this (arena center)
Config.LOBBY_COLOR_PAD = Color3.fromRGB(120, 170, 230) -- soft blue (echoes lobby banner)
Config.LOBBY_COLOR_WALL = Color3.fromRGB(90, 130, 190) -- slightly darker walls
Config.LOBBY_RAILING_TRANSPARENCY = 0.6 -- arena-facing glass railing (CanCollide, see-through)
```
WITH:
```lua
-- [-32,32] at surface Y=0, so the lobby DISC sits RAISED and SET BACK behind the
-- -Z edge; standing bodies look down into the pit. The disc floats over the void,
-- so the rim BARRIER is LOAD-BEARING: a gap would let a controlled body walk/jump
-- off and die between rounds.
Config.LOBBY_ORIGIN = Vector3.new(0, 45, -64) -- disc top-surface center
Config.LOBBY_DISC_RADIUS = 30   -- walkable disc radius (holds the 4x4 body grid + margin)
Config.LOBBY_DISC_THICKNESS = 2 -- disc vertical thickness (top face sits at LOBBY_ORIGIN.Y)
Config.LOBBY_DISC_COLOR = Color3.fromRGB(40, 42, 58) -- dark metal top
-- LOBBY_WALL_* now describe the INVISIBLE rim barrier. Height must exceed a jump so a
-- body can't hop off (JUMP_HEIGHT = 7.2). The barrier is a gap-free ring of segments.
Config.LOBBY_WALL_HEIGHT = 12 -- barrier height (> JUMP_HEIGHT)
Config.LOBBY_WALL_THICKNESS = 1 -- barrier radial thickness
Config.LOBBY_BARRIER_SEGMENTS = 18 -- ring segments (more = rounder fence)
Config.LOBBY_BARRIER_SLACK = 1.1   -- segment length vs chord (overlap => NO gaps)
Config.LOBBY_CAPACITY = 16 -- grid sized for up to this many bodies
Config.LOBBY_PER_ROW = 4 -- body grid columns (rows = ceil(CAPACITY/PER_ROW))
Config.LOBBY_SPACING = 10 -- studs between grid slots
Config.LOBBY_SPAWN_DROP = 5 -- studs above the disc a body spawns at (settles down)
Config.LOBBY_FACE_TARGET = Vector3.new(0, 0, 0) -- bodies face this (arena center)
```

- [ ] **Step 2:** Replace the entire `LOBBY_STAGE_*` dressing block. Find the run beginning at the comment `-- Stage deck: a thin cosmetic slab skinning the platform top + a lit pit-facing lip.` through the last line `Config.LOBBY_STAGE_BUNTING_TEXTURE = ""        -- Texture id for pennant flags`, and replace ALL of it (every `LOBBY_STAGE_DECK_*`, `_EDGE_*`, `_CLUSTER_*`, `_FESTOON_*`, `_LIGHT_*`, `_BUNTING_*`, `_CREST_*`, `_IDLE_*`, `_CHEER_*`, and asset fields) WITH:
```lua
-- ============ Beyblade lobby cosmetic (client LobbyStage) ============
-- The server LobbyArea builds the load-bearing disc + invisible rim barrier; this
-- block dresses it as a spinning top. All cosmetic parts are non-colliding. Heights
-- are relative to the disc top (= LOBBY_ORIGIN.Y).

-- Energy rings: Neon discs WIDER than the server disc, centered at its mid-height so
-- their rim glows around the disc edge (the opaque disc occludes the center). Ring A
-- (cool) is the visible half of the hybrid fall ring; ring B (warm) is lower + wider.
Config.LOBBY_BEY_RING_COLOR_A = Color3.fromRGB(120, 230, 220)
Config.LOBBY_BEY_RING_COLOR_B = Color3.fromRGB(255, 207, 107)
Config.LOBBY_BEY_RING_OVERHANG_A = 1.4   -- studs ring A extends past the disc radius
Config.LOBBY_BEY_RING_OVERHANG_B = 3.0   -- studs ring B extends past the disc radius
Config.LOBBY_BEY_RING_DROP_B = 1.6       -- studs ring B sits below ring A
Config.LOBBY_BEY_RING_THICKNESS = 0.6

-- Stepped taper body below the disc, down to a tip. Each entry { radiusFrac, depth
-- below the disc top (studs), thickness }. Metal discs of decreasing radius.
Config.LOBBY_BEY_STEP_COLOR = Color3.fromRGB(54, 56, 74)
Config.LOBBY_BEY_STEPS = {
	{ 0.82, 4, 3 },
	{ 0.55, 9, 3 },
	{ 0.30, 14, 3 },
}
-- Tip: a thin vertical Neon spike at the bottom center.
Config.LOBBY_BEY_TIP_COLOR = Color3.fromRGB(120, 230, 220)
Config.LOBBY_BEY_TIP_DIAMETER = 2.4
Config.LOBBY_BEY_TIP_HEIGHT = 7
Config.LOBBY_BEY_TIP_DEPTH = 19          -- studs below the disc top the tip CENTER sits

-- Spectator souls: two cheer-reactive soul-orb clusters at the rim (±X).
Config.LOBBY_BEY_CLUSTER_RADIUS = 0.8    -- fraction of disc radius the clusters sit at
Config.LOBBY_BEY_CLUSTER_LIFT = 2.5      -- studs above the disc top

-- Crowd cluster shape + cheer (reused by the spectator souls).
Config.LOBBY_STAGE_CLUSTER_PER_SIDE = 6  -- orbs per cluster (2 => ~12 total)
Config.LOBBY_STAGE_CLUSTER_SPACING = 2.6 -- studs between orbs in a cluster
Config.LOBBY_STAGE_ORB_SIZE = 2.2
Config.LOBBY_STAGE_IDLE_SPEED = 0.5
Config.LOBBY_STAGE_IDLE_AMP = 0.4
Config.LOBBY_STAGE_CHEER_BOB = 6         -- studs an orb pops up on a cheer
Config.LOBBY_STAGE_CHEER_SCALE = 0.5     -- orb size pop fraction at full cheer
Config.LOBBY_STAGE_CHEER_SECONDS = 0.5   -- cheer decay time

-- Hybrid asset field (blank "" => code fallback). Crowd-orb mesh only; the rest of
-- the beyblade ships as code.
Config.LOBBY_STAGE_ORB_MESH = ""
```

- [ ] **Step 3:** Verify no removed key lingers anywhere: `grep -rnE "LOBBY_PAD_SIZE|LOBBY_COLOR_|LOBBY_RAILING|LOBBY_STAGE_DECK|LOBBY_STAGE_EDGE|LOBBY_STAGE_FESTOON|LOBBY_STAGE_LIGHT|LOBBY_STAGE_BUNTING|LOBBY_STAGE_CREST|LOBBY_STAGE_CLUSTER_INSET|LOBBY_STAGE_CLUSTER_FRONT|LOBBY_STAGE_CLUSTER_LIFT" src/` — matches will still exist in `LobbyArea.luau`, `ArenaDressing.luau`, `LobbyStage.luau` (rewritten/edited in Tasks 3–5). That's expected at this point. Confirm none remain in `Config.luau` itself: `grep -nE "LOBBY_PAD_SIZE|LOBBY_RAILING" src/shared/Config.luau` → none.
- [ ] **Step 4:** Commit:
```
git add src/shared/Config.luau
git commit -m "$(printf 'feat(world): swap lobby box config for beyblade disc/barrier + cosmetic\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 3: Server `LobbyArea` — disc + invisible barrier (LOAD-BEARING)

**Files:** `src/server/LobbyArea.luau` (full rewrite)

- [ ] **Step 1:** Replace the ENTIRE contents of `src/server/LobbyArea.luau` with:
```lua
--[[
	LobbyArea (server) -- the beyblade lobby's LOAD-BEARING geometry: a round
	walkable DISC players stand on, raised and set back over the pit, ringed by an
	INVISIBLE BARRIER (gap-free, taller than a jump) that is the fall protection.
	Location: ServerScriptService/Server/LobbyArea (ModuleScript)

	Body POSITIONING on the disc is owned by BodyManager (SpawnLayout + Config); this
	module is geometry-only. The beyblade's cosmetic body (energy rings, taper, tip,
	spectator souls) is the client LobbyStage's job.

	Depends on: ReplicatedStorage.Shared.Config, ReplicatedStorage.Shared.WorldLayout
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldLayout = require(Shared.WorldLayout)

local LobbyArea = {}

local built = false

-- Build the lobby once. A second call is a no-op (singleton).
function LobbyArea.build()
	if built then
		return
	end
	built = true

	local folder = workspace:FindFirstChild("LobbyArea")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "LobbyArea"
		folder.Parent = workspace
	end

	local origin = Config.LOBBY_ORIGIN
	local r = Config.LOBBY_DISC_RADIUS
	local th = Config.LOBBY_DISC_THICKNESS

	-- Walkable disc: a CanCollide Cylinder, axis vertical, top face at origin.Y.
	-- A Cylinder's length is its local X; rotate X -> up, Size = (length, dia, dia).
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = true
	disc.Size = Vector3.new(th, r * 2, r * 2)
	disc.CFrame = CFrame.new(origin.X, origin.Y - th / 2, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = Config.LOBBY_DISC_COLOR
	disc.Material = Enum.Material.Metal
	disc.TopSurface = Enum.SurfaceType.Smooth
	disc.BottomSurface = Enum.SurfaceType.Smooth
	disc.Parent = folder

	-- Invisible rim barrier (LOAD-BEARING): a gap-free ring of tall, thin, transparent
	-- CanCollide segments at the disc rim, taller than a jump. Each segment's length is
	-- the chord between adjacent ring points x slack, so neighbours overlap (no gaps).
	local segs = Config.LOBBY_BARRIER_SEGMENTS
	local wallH = Config.LOBBY_WALL_HEIGHT
	local wallT = Config.LOBBY_WALL_THICKNESS
	local pts = WorldLayout.ring(origin.X, origin.Z, r, segs)
	local chord = 2 * r * math.sin(math.pi / segs)
	local segLen = chord * Config.LOBBY_BARRIER_SLACK
	local yMid = origin.Y + wallH / 2
	for i = 1, segs do
		local pt = pts[i]
		local nxt = pts[(i % segs) + 1]
		local seg = Instance.new("Part")
		seg.Name = "Barrier"
		seg.Anchored = true
		seg.CanCollide = true
		seg.Transparency = 1
		seg.Size = Vector3.new(wallT, wallH, segLen)
		seg.CFrame = CFrame.lookAt(Vector3.new(pt.x, yMid, pt.z), Vector3.new(nxt.x, yMid, nxt.z))
		seg.Parent = folder
	end
end

return LobbyArea
```
- [ ] **Step 2:** There is no lune test for server glue. Sanity-check it parses and references valid Config: `grep -nE "LOBBY_DISC_|LOBBY_BARRIER_|LOBBY_WALL_" src/server/LobbyArea.luau` should match only keys defined in Task 2. Confirm the file ends with `return LobbyArea`.
- [ ] **Step 3:** Commit:
```
git add src/server/LobbyArea.luau
git commit -m "$(printf 'feat(world): rebuild LobbyArea as a beyblade disc + invisible rim barrier\n\nLoad-bearing: CanCollide Cylinder disc (top at LOBBY_ORIGIN.Y) ringed by\na gap-free invisible barrier taller than a jump. Body placement unchanged.\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 4: Client `LobbyStage` — beyblade cosmetic (full rewrite)

**Files:** `src/client/LobbyStage.luau` (full rewrite)

- [ ] **Step 1:** Replace the ENTIRE contents of `src/client/LobbyStage.luau` with:
```lua
--[[
	LobbyStage (client) -- the beyblade lobby's cosmetic dressing. 100% local
	cosmetic, ADD-ONLY: the load-bearing LobbyArea geometry (the walkable disc + the
	invisible rim barrier) is server-owned and untouched; every part built here is
	non-colliding/non-querying/shadow-less.

	The lobby is shaped like a beyblade (spinning top): glowing rim ENERGY RINGS
	around the server disc (the old festival "lights", reinterpreted; the topmost is
	the visible half of the hybrid fall ring), a STEPPED TAPER body down to a TIP, and
	two cheer-reactive SOUL-ORB clusters ("spectator souls") at the rim that pulse on
	eliminations/wins (reusing WorldShell's decaying-impulse pattern).

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

-- A vertical-axis Cylinder centered on the lobby, with its CENTER at world height
-- `centerY`. `length` is the vertical extent; `diameter` the round cross-section.
local function rigCyl(name, diameter, length, centerY, color, material, parent)
	local o = Config.LOBBY_ORIGIN
	local p = rigPart(Vector3.new(length, diameter, diameter),
		Vector3.new(o.X, centerY, o.Z), color, material, parent)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(o.X, centerY, o.Z) * CFrame.Angles(0, 0, math.rad(90))
	p.Name = name
	return p
end

-- top face of the server disc (= LOBBY_ORIGIN.Y).
local function topY()
	return Config.LOBBY_ORIGIN.Y
end

-- Glowing energy rings around the disc rim. Each is a Neon disc WIDER than the
-- server disc, centered at the disc's mid-height; the opaque server disc occludes
-- the centre, so only the protruding rim glows.
local function buildEnergyRings(folder)
	local r = Config.LOBBY_DISC_RADIUS
	local midY = topY() - Config.LOBBY_DISC_THICKNESS / 2
	local t = Config.LOBBY_BEY_RING_THICKNESS
	rigCyl("EnergyRing", (r + Config.LOBBY_BEY_RING_OVERHANG_A) * 2, t, midY,
		Config.LOBBY_BEY_RING_COLOR_A, Enum.Material.Neon, folder)
	rigCyl("EnergyRing", (r + Config.LOBBY_BEY_RING_OVERHANG_B) * 2, t,
		midY - Config.LOBBY_BEY_RING_DROP_B, Config.LOBBY_BEY_RING_COLOR_B, Enum.Material.Neon, folder)
end

-- Stepped taper body below the disc + a tip spike.
local function buildBody(folder)
	local r = Config.LOBBY_DISC_RADIUS
	for _, step in ipairs(Config.LOBBY_BEY_STEPS) do
		local radiusFrac, depth, thickness = step[1], step[2], step[3]
		rigCyl("BeyStep", r * 2 * radiusFrac, thickness, topY() - depth,
			Config.LOBBY_BEY_STEP_COLOR, Enum.Material.Metal, folder)
	end
	rigCyl("BeyTip", Config.LOBBY_BEY_TIP_DIAMETER, Config.LOBBY_BEY_TIP_HEIGHT,
		topY() - Config.LOBBY_BEY_TIP_DEPTH, Config.LOBBY_BEY_TIP_COLOR, Enum.Material.Neon, folder)
end

-- Two cheer-reactive soul-orb clusters at the rim (±X); one Heartbeat drives idle
-- wobble + a decaying cheer pop (same pattern as WorldShell's crowd).
local crowdOrbs = {}
local function buildSpectatorSouls(folder)
	table.clear(crowdOrbs)
	local palette = Config.SOUL_PALETTE
	local o = Config.LOBBY_ORIGIN
	local rimX = Config.LOBBY_DISC_RADIUS * Config.LOBBY_BEY_CLUSTER_RADIUS
	local baseY = topY() + Config.LOBBY_BEY_CLUSTER_LIFT
	local n, sp = Config.LOBBY_STAGE_CLUSTER_PER_SIDE, Config.LOBBY_STAGE_CLUSTER_SPACING
	local centers = { o.X - rimX, o.X + rimX }
	local idx = 0
	for _, cx in ipairs(centers) do
		for _, s in ipairs(WorldLayout.cluster(cx, o.Z, baseY, n, sp)) do
			idx += 1
			local color = palette[WorldLayout.paletteIndex(idx, #palette)]
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
			crowdOrbs[#crowdOrbs + 1] = {
				part = orb, base = orb.Position, baseSize = sz,
				phase = (s.x + s.z), cheer = 0,
			}
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() * Config.LOBBY_STAGE_IDLE_SPEED * math.pi * 2
		for _, e in ipairs(crowdOrbs) do
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

local function cheer()
	for _, e in ipairs(crowdOrbs) do
		e.cheer = 0.6 + math.random() * 0.4
	end
end

function LobbyStage.start()
	local folder = newFolder()
	buildBody(folder)
	buildEnergyRings(folder)
	buildSpectatorSouls(folder)

	-- Reuse WorldShell's cheer triggers: the spectator souls pulse on any elimination
	-- and on a winner being named (second pop), additive to the distant crowd.
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
- [ ] **Step 2:** Confirm the file ends with `return LobbyStage` and that no removed Config key is referenced: `grep -nE "LOBBY_PAD_SIZE|LOBBY_STAGE_FESTOON|LOBBY_STAGE_BUNTING|LOBBY_STAGE_CREST|LOBBY_STAGE_DECK|LOBBY_STAGE_EDGE|festoonStrand|buntingFlags" src/client/LobbyStage.luau` → none.
- [ ] **Step 3:** Commit:
```
git add src/client/LobbyStage.luau
git commit -m "$(printf 'feat(world): re-dress LobbyStage as the beyblade (energy rings, taper, tip, spectator souls)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Task 5: `ArenaDressing` marquee mount — off the disc radius

**Files:** `src/client/ArenaDressing.luau`

- [ ] **Step 1:** In `buildBanner`, replace the line:
```lua
	local mountZ = Config.LOBBY_ORIGIN.Z + Config.LOBBY_PAD_SIZE.Z / 2 + Config.WORLD_BANNER_FORWARD
```
WITH:
```lua
	local mountZ = Config.LOBBY_ORIGIN.Z + Config.LOBBY_DISC_RADIUS + Config.WORLD_BANNER_FORWARD
```
- [ ] **Step 2:** Confirm no `LOBBY_PAD_SIZE` remains anywhere: `grep -rn "LOBBY_PAD_SIZE" src/` → none.
- [ ] **Step 3:** Commit:
```
git add src/client/ArenaDressing.luau
git commit -m "$(printf 'fix(world): mount the marquee off the lobby disc radius (was pad depth)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Completion (controller-run)
- Lune green (`tests/world_layout.spec`).
- MCP structural: `workspace.LobbyArea` = 1 `Disc` (Cylinder, CanCollide, top at `LOBBY_ORIGIN.Y`) + `LOBBY_BARRIER_SEGMENTS` `Barrier` (CanCollide, Transparency 1, height 12); `workspace.LobbyStage` = 2 `EnergyRing` + 3 `BeyStep` + 1 `BeyTip` + 12 `CrowdOrb`, all `CanCollide=false`.
- Update the Slice-2 smoke doc with the beyblade walk/jump-off checks; update the roadmap.
- Finish and integrate the branch.
