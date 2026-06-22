# Lobby Staging Area (Elevated Balcony) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an elevated balcony overlooking the arena where players gather between rounds and on join, with a victory cam framing the winner during the Ended results window.

**Architecture:** A new pure `SpawnLayout` module owns both the arena spawn math (extracted unchanged from `BodyManager`) and the balcony grid math, lune-tested. A new server `LobbyArea` module builds the balcony geometry once. `BodyManager` places bodies on the balcony on join and gains a `returnToLobby`; `RoundManager` builds the balcony at startup, fires a victory cam at round end, and relocates everyone to the balcony at the Lobby transition (reusing `resetControl`).

**Tech Stack:** Roblox Luau, Rojo project. Pure modules in `src/shared/` tested with lune (`tests/*.spec.luau`). Server modules in `src/server/`. Config-driven tunables in `src/shared/Config.luau`.

**Spec:** `docs/superpowers/specs/2026-06-21-lobby-staging-area-design.md`

**Conventions to honor:**
- Pure modules are Roblox-free (no `Vector3`/`CFrame`/`Color3`/`game`), number-in/number-out; the server converts to Roblox types.
- Lune test runner: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<name>.spec`. Test files use the `expect`/`fail` helper pattern (see `tests/tile_field_model.spec.luau`).
- Geometry-build modules expose a singleton `build()` guarded against rebuild (see `HazardSystem.build`).
- Commit after each task. End commit messages with the `Co-Authored-By` trailer below.

```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

### Task 1: `SpawnLayout` pure module (arena + balcony slot math)

**Files:**
- Create: `src/shared/SpawnLayout.luau`
- Test: `tests/spawn_layout.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/spawn_layout.spec.luau`:

```lua
local SpawnLayout = require("../src/shared/SpawnLayout")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local function approx(a, b)
	return math.abs(a - b) < 1e-9
end

-- arenaSlot reproduces today's documented positions exactly.
-- Real values: SPAWN_ORIGIN = (-4, 5, 4), SPAWN_SPACING = 8 -> X = -4,4,12,20,28.
do
	local ox, oy, oz, spacing = -4, 5, 4, 8
	local expectedX = { -4, 4, 12, 20, 28 }
	for i = 1, 5 do
		local x, y, z = SpawnLayout.arenaSlot(i, ox, oy, oz, spacing)
		expect(x == expectedX[i], "arenaSlot X wrong at index " .. i)
		expect(y == oy, "arenaSlot Y must equal originY at index " .. i)
		expect(z == oz, "arenaSlot Z must equal originZ at index " .. i)
	end
	print("spawn: arenaSlot reproduces documented positions OK")
end

-- lobbySlot lays a centered grid: distinct, spaced, wrapping at perRow.
do
	local perRow, rows, spacing = 4, 4, 10
	local slots = {}
	for i = 1, 16 do
		local dx, dz = SpawnLayout.lobbySlot(i, perRow, rows, spacing)
		slots[i] = { dx = dx, dz = dz }
	end

	-- pairwise distinct
	for i = 1, 16 do
		for j = i + 1, 16 do
			expect(not (slots[i].dx == slots[j].dx and slots[i].dz == slots[j].dz),
				"lobbySlot slots " .. i .. " and " .. j .. " overlap")
		end
	end

	-- columns centered on 0: first row dx = -15,-5,5,15 -> sum 0, spacing 10
	local sum = slots[1].dx + slots[2].dx + slots[3].dx + slots[4].dx
	expect(approx(sum, 0), "lobbySlot columns must be centered on 0")
	expect(approx(slots[2].dx - slots[1].dx, spacing), "lobbySlot column spacing wrong")

	-- rows centered on 0: column-0 dz across rows = -15,-5,5,15 -> sum 0
	local rowSum = slots[1].dz + slots[5].dz + slots[9].dz + slots[13].dz
	expect(approx(rowSum, 0), "lobbySlot rows must be centered on 0")

	-- wrap: index 1 and 5 share a column (same dx), advance a row (differ dz)
	expect(slots[1].dx == slots[5].dx, "lobbySlot must wrap columns at perRow")
	expect(slots[1].dz ~= slots[5].dz, "lobbySlot must advance the row after perRow")

	-- footprint: every offset stays within +/- (span/2); span = (n-1)*spacing
	local halfX = (perRow - 1) / 2 * spacing
	local halfZ = (rows - 1) / 2 * spacing
	for i = 1, 16 do
		expect(math.abs(slots[i].dx) <= halfX + 1e-9, "lobbySlot dx out of footprint at " .. i)
		expect(math.abs(slots[i].dz) <= halfZ + 1e-9, "lobbySlot dz out of footprint at " .. i)
	end
	print("spawn: lobbySlot centered grid OK")
end

print("ALL SpawnLayout TESTS PASSED")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec`
Expected: FAIL — module `../src/shared/SpawnLayout` does not exist (require error).

- [ ] **Step 3: Write the minimal implementation**

Create `src/shared/SpawnLayout.luau`:

```lua
--[[
	SpawnLayout -- PURE slot geometry.
	Location (Roblox): ReplicatedStorage/Shared/SpawnLayout  (ModuleScript)

	No Roblox APIs (no Vector3/CFrame/Color3), no clocks, no RNG. Number-in /
	number-out; the server glue (BodyManager) turns the returned components into
	CFrames. Mirrors the project's other pure modules (TileFieldModel, RoundState).

	Two layouts:
	  arenaSlot -- the in-arena spawn row (reproduces the math BodyManager used
	               inline: body `index` at originX + (index-1)*spacing, tile centers).
	  lobbySlot -- a centered grid on the elevated lobby balcony.
--]]

local SpawnLayout = {}

-- Arena spawn slot for 1-based `index`. Returns world components x, y, z.
-- x = originX + (index-1)*spacing; y, z pass through. This MUST match the
-- positions BodyManager produced before extraction (tile-center invariant).
function SpawnLayout.arenaSlot(index, originX, originY, originZ, spacing)
	return originX + (index - 1) * spacing, originY, originZ
end

-- Balcony grid offset for 1-based `index`, from the pad center.
-- `perRow` columns, `rows` total rows, `spacing` studs between slots.
-- Columns fill left-to-right, wrapping to the next row every `perRow`.
-- Both axes are centered on 0, so the grid straddles the pad origin.
-- Returns dx, dz offsets (the server adds the balcony origin + height + facing).
function SpawnLayout.lobbySlot(index, perRow, rows, spacing)
	local i = index - 1
	local col = i % perRow
	local row = math.floor(i / perRow)
	local dx = (col - (perRow - 1) / 2) * spacing
	local dz = (row - (rows - 1) / 2) * spacing
	return dx, dz
end

return SpawnLayout
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec`
Expected: PASS — prints `ALL SpawnLayout TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/SpawnLayout.luau tests/spawn_layout.spec.luau
git commit -m "feat(lobby): pure SpawnLayout (arena + balcony slot math)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Config — balcony tunables

**Files:**
- Modify: `src/shared/Config.luau` (add a new block before `return Config`)

- [ ] **Step 1: Add the balcony config block**

In `src/shared/Config.luau`, immediately AFTER the spawn block (the lines defining `Config.SPAWN_ORIGIN` and `Config.SPAWN_SPACING`) and BEFORE the `Config.ANIM` block, insert:

```lua
-- Lobby staging area: an elevated balcony overlooking the arena. Players wait
-- here between rounds and on join; LobbyArea builds the geometry and BodyManager
-- places bodies on the grid slots (pure SpawnLayout). The arena spans X,Z in
-- [-32,32] at surface Y=0, so the balcony sits RAISED and SET BACK behind the
-- -Z edge, facing +Z toward the arena center -- standing bodies look down into
-- the pit. The perimeter barriers are LOAD-BEARING: the pad floats over the void,
-- so a gap would let a controlled body walk off and die between rounds.
Config.LOBBY_ORIGIN = Vector3.new(0, 45, -64) -- balcony surface center
Config.LOBBY_PAD_SIZE = Vector3.new(48, 1, 48) -- platform X, thickness(Y), Z
Config.LOBBY_WALL_HEIGHT = 8 -- perimeter barrier height (fall protection)
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

- [ ] **Step 2: Sanity-check it loads (no syntax error)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec`
Expected: PASS (unchanged) — confirms the repo still parses; Config itself is exercised at runtime.

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(lobby): balcony geometry + grid config tunables

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `LobbyArea` server module (build the balcony once)

**Files:**
- Create: `src/server/LobbyArea.luau`

This is Roblox-geometry code (no pure unit test; verified by the smoke test in Task 6). It mirrors `HazardSystem.build`'s singleton-folder pattern.

- [ ] **Step 1: Implement `LobbyArea`**

Create `src/server/LobbyArea.luau`:

```lua
--[[
	LobbyArea (server) -- the elevated balcony overlooking the arena.
	Location: ServerScriptService/Server/LobbyArea  (ModuleScript)

	Builds the balcony geometry ONCE (mirrors HazardSystem.build): an anchored
	platform raised above and set back from the arena, fully enclosed by perimeter
	barriers so a controlled body cannot walk off into the void between rounds.
	The arena-facing wall is a transparent-but-CanCollide glass railing so the
	downward view stays open.

	Body POSITIONING on the balcony is owned by BodyManager (via SpawnLayout +
	Config); this module is geometry-only.

	Depends on: ReplicatedStorage.Shared.Config
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local LobbyArea = {}

local built = false

local function makePart(name, size, position, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Build the balcony once. A second call is a no-op (singleton).
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

	local origin = Config.LOBBY_ORIGIN -- pad surface center
	local pad = Config.LOBBY_PAD_SIZE
	local wallH = Config.LOBBY_WALL_HEIGHT
	local wallT = Config.LOBBY_WALL_THICKNESS

	-- Platform: top face at origin.Y (body slots add LOBBY_SPAWN_DROP above it).
	makePart(
		"Platform",
		pad,
		origin - Vector3.new(0, pad.Y / 2, 0),
		Config.LOBBY_COLOR_PAD,
		folder
	)

	-- Perimeter barriers, centered on the wall midline (origin.Y + wallH/2).
	local wallY = origin.Y + wallH / 2
	local halfX = pad.X / 2
	local halfZ = pad.Z / 2

	-- Back wall (-Z, away from the arena) and the two side walls are solid.
	makePart(
		"Wall_Back",
		Vector3.new(pad.X, wallH, wallT),
		Vector3.new(origin.X, wallY, origin.Z - halfZ),
		Config.LOBBY_COLOR_WALL,
		folder
	)

	makePart(
		"Wall_Left",
		Vector3.new(wallT, wallH, pad.Z),
		Vector3.new(origin.X - halfX, wallY, origin.Z),
		Config.LOBBY_COLOR_WALL,
		folder
	)
	makePart(
		"Wall_Right",
		Vector3.new(wallT, wallH, pad.Z),
		Vector3.new(origin.X + halfX, wallY, origin.Z),
		Config.LOBBY_COLOR_WALL,
		folder
	)

	-- Front railing (+Z, faces the arena): CanCollide but transparent so the
	-- downward view is unobstructed. LOAD-BEARING fall protection.
	local rail = makePart(
		"Railing_Front",
		Vector3.new(pad.X, wallH, wallT),
		Vector3.new(origin.X, wallY, origin.Z + halfZ),
		Config.LOBBY_COLOR_WALL,
		folder
	)
	rail.Transparency = Config.LOBBY_RAILING_TRANSPARENCY
	rail.CanCollide = true
end

return LobbyArea
```

- [ ] **Step 2: Commit**

```bash
git add src/server/LobbyArea.luau
git commit -m "feat(lobby): LobbyArea builds the elevated balcony geometry

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `BodyManager` — SpawnLayout + balcony slots + returnToLobby

**Files:**
- Modify: `src/server/BodyManager.luau`

- [ ] **Step 1: Require `SpawnLayout` and add slot-CFrame helpers**

In `src/server/BodyManager.luau`, AFTER the existing `local Config = require(...)` line (line 13), add:

```lua
local SpawnLayout = require(ReplicatedStorage.Shared.SpawnLayout)
```

Then change the state tables. Replace this line:

```lua
BodyManager.spawnByOwner = {} -- [player] = CFrame the body spawned at (for round-start reposition)
```

with:

```lua
BodyManager.arenaSlotByOwner = {} -- [player] = arena spawn CFrame (round-start reposition)
BodyManager.lobbySlotByOwner = {} -- [player] = balcony slot CFrame (join + between-rounds)
```

- [ ] **Step 2: Add the two slot-CFrame builders**

In `src/server/BodyManager.luau`, immediately BEFORE `function BodyManager.createBody(player)`, add:

```lua
-- Arena spawn CFrame for a 1-based body index (today's single-row layout).
local function arenaCFrame(index)
	local o = Config.SPAWN_ORIGIN
	local x, y, z = SpawnLayout.arenaSlot(index, o.X, o.Y, o.Z, Config.SPAWN_SPACING)
	return CFrame.new(x, y, z)
end

-- Balcony slot CFrame for a 1-based body index. Grid offset (pure SpawnLayout)
-- + the balcony origin + a small drop, oriented (yaw only) to face the arena so
-- the avatar -- and its third-person camera -- point at the pit below.
local function lobbyCFrame(index)
	local rows = math.ceil(Config.LOBBY_CAPACITY / Config.LOBBY_PER_ROW)
	local dx, dz = SpawnLayout.lobbySlot(index, Config.LOBBY_PER_ROW, rows, Config.LOBBY_SPACING)
	local pos = Config.LOBBY_ORIGIN + Vector3.new(dx, Config.LOBBY_SPAWN_DROP, dz)
	-- Look at the arena center, kept level with `pos` so the body stands upright
	-- (yaw-only facing; the player tilts the camera to look down).
	local target = Vector3.new(Config.LOBBY_FACE_TARGET.X, pos.Y, Config.LOBBY_FACE_TARGET.Z)
	return CFrame.lookAt(pos, target)
end
```

- [ ] **Step 3: Spawn new bodies onto the balcony and store both slots**

In `BodyManager.createBody`, replace this block:

```lua
	BodyManager._index += 1
	local pos = Config.SPAWN_ORIGIN + Vector3.new((BodyManager._index - 1) * Config.SPAWN_SPACING, 0, 0)
	local spawnCFrame = CFrame.new(pos)
	body:PivotTo(spawnCFrame)
	BodyManager.spawnByOwner[player] = spawnCFrame
	body:SetAttribute("OwnerUserId", player.UserId)
	body.Parent = ensureFolder()
```

with:

```lua
	BodyManager._index += 1
	local index = BodyManager._index
	-- A joining player starts in the waiting state, so spawn on the balcony.
	-- Both slots are stored so resetBody (arena) and returnToLobby (balcony) can
	-- reposition the body for the rest of its life without recomputing.
	BodyManager.arenaSlotByOwner[player] = arenaCFrame(index)
	BodyManager.lobbySlotByOwner[player] = lobbyCFrame(index)
	body:PivotTo(BodyManager.lobbySlotByOwner[player])
	body:SetAttribute("OwnerUserId", player.UserId)
	body.Parent = ensureFolder()
```

- [ ] **Step 4: Update `resetBody`, `removeBody`, and add `returnToLobby`**

In `BodyManager.removeBody`, replace:

```lua
	BodyManager.bodyByOwner[player] = nil
	BodyManager.spawnByOwner[player] = nil
```

with:

```lua
	BodyManager.bodyByOwner[player] = nil
	BodyManager.arenaSlotByOwner[player] = nil
	BodyManager.lobbySlotByOwner[player] = nil
```

In `BodyManager.resetBody`, replace:

```lua
	local body = BodyManager.bodyByOwner[player]
	local cf = BodyManager.spawnByOwner[player]
```

with:

```lua
	local body = BodyManager.bodyByOwner[player]
	local cf = BodyManager.arenaSlotByOwner[player]
```

Then, immediately AFTER the `BodyManager.resetBody` function (after its closing `end`, before `BodyManager.parkBody`), add:

```lua
-- Between rounds (and the Lobby phase): reposition a player's OWN body to its
-- balcony slot and re-enable physics. The mirror of resetBody; unanchors so the
-- subsequent ControlManager.resetControl can SetNetworkOwner (errors if anchored).
function BodyManager.returnToLobby(player)
	local body = BodyManager.bodyByOwner[player]
	local cf = BodyManager.lobbySlotByOwner[player]
	if not body or not cf then
		return
	end
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	root.Anchored = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	body:PivotTo(cf)
end
```

- [ ] **Step 5: Verify the pure test still passes (no regression to SpawnLayout)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec`
Expected: PASS (unchanged). BodyManager itself is Roblox-bound and verified by the smoke test.

- [ ] **Step 6: Commit**

```bash
git add src/server/BodyManager.luau
git commit -m "feat(lobby): BodyManager spawns on the balcony + returnToLobby

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `RoundManager` — build balcony, victory cam, relocate at Lobby reset

**Files:**
- Modify: `src/server/RoundManager.luau`

- [ ] **Step 1: Require `LobbyArea`**

In `src/server/RoundManager.luau`, AFTER the line `local HazardSystem = require(script.Parent.HazardSystem)` (line 29), add:

```lua
local LobbyArea = require(script.Parent.LobbyArea)
```

- [ ] **Step 2: Build the balcony at startup**

In `RoundManager.start`, replace:

```lua
	HazardSystem.build() -- construct the tile-field arena once (replaces the baseplate)
```

with:

```lua
	HazardSystem.build() -- construct the tile-field arena once (replaces the baseplate)
	LobbyArea.build() -- construct the elevated lobby balcony once
```

- [ ] **Step 3: Add the victory cam + balcony relocation to `endRound`**

Replace the entire `endRound` function:

```lua
local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
	-- Tick the post-round countdown so the Results banner shows a truthful
	-- "Next round in N" -- reusing the same secondsRemaining channel the Lobby
	-- countdown uses, so the client stays clock-free (server owns clocks).
	-- broadcastState already carries winnerName during Ended.
	local remaining = Config.ROUND_END_SECONDS
	broadcastState(remaining) -- always show the Results banner at least once (Ended)
	while remaining > 1 do
		task.wait(1)
		remaining -= 1
		broadcastState(remaining) -- tick N-1 .. 1
	end
	task.wait(remaining > 0 and 1 or 0) -- wait out the final second (skip if N == 0)
	RoundState.reset(model) -- Ended -> Lobby
	broadcastState() -- phase Lobby
end
```

with:

```lua
local function endRound()
	stopMonitor()
	HazardSystem.stop() -- freeze tiles solid for the Ended/Lobby floor
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
	-- Victory cam: while the Results banner is up, point EVERY present player's
	-- camera at the winner standing in the arena below. Bodies are NOT relocated
	-- yet, so the winner stays put as the cam subject. Reuses SpectateBody (the
	-- client sets CameraSubject unconditionally). Skipped if there is no winner
	-- (disconnect-decided round) -- nothing to frame.
	local remaining = Config.ROUND_END_SECONDS
	broadcastState(remaining) -- always show the Results banner at least once (Ended)
	if winner then
		local winnerBody = ControlManager.getControlledBody(winner)
		if winnerBody then
			for _, p in ipairs(Players:GetPlayers()) do
				SpectateBody:FireClient(p, winnerBody)
			end
		end
	end
	while remaining > 1 do
		task.wait(1)
		remaining -= 1
		broadcastState(remaining) -- tick N-1 .. 1
	end
	task.wait(remaining > 0 and 1 or 0) -- wait out the final second (skip if N == 0)
	-- Relocate everyone to the balcony for the Lobby wait. Order mirrors
	-- beginRound: unanchor + pivot (returnToLobby) BEFORE resetControl, which
	-- SetNetworkOwners (errors on an anchored part) and fires SetControlledBody --
	-- pulling each camera off the victory-cam subject back onto its own body,
	-- now standing on the balcony.
	for _, p in ipairs(Players:GetPlayers()) do
		BodyManager.returnToLobby(p)
	end
	ControlManager.resetControl()
	RoundState.reset(model) -- Ended -> Lobby
	broadcastState() -- phase Lobby
end
```

- [ ] **Step 4: Verify the pure test still passes (no regression)**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec`
Expected: PASS (unchanged). RoundManager is Roblox-bound and verified by the smoke test.

- [ ] **Step 5: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(lobby): build balcony, victory cam, relocate at Lobby reset

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Smoke test document

**Files:**
- Create: `docs/smoke-tests/2026-06-21-lobby-staging-area-smoke-test.md`

- [ ] **Step 1: Write the smoke test doc**

Create `docs/smoke-tests/2026-06-21-lobby-staging-area-smoke-test.md`:

```markdown
# Lobby Staging Area — 2-Client Studio Smoke Test (2026-06-21)

Runtime checks the lune tests can't cover: balcony geometry, body relocation
across the round lifecycle, and the victory cam. Pairs with the unit test
`tests/spawn_layout.spec.luau` (slot math) and the spec
`docs/superpowers/specs/2026-06-21-lobby-staging-area-design.md`.

## Setup
- Roblox Studio, **2 players** (Test > Clients and Servers > 2 players, Start).
- Set `Config.HAZARDS_ENABLED = false` so the arena floor stays solid while you
  observe the loop (no body falls mid-test). Restore to `true` afterward.

## Procedure

1. **Join → balcony.** Both clients spawn on the **elevated balcony** (not in the
   arena). Each can walk their body around the platform; looking forward/down they
   see the arena below. Walking into any edge is blocked — the perimeter walls and
   the (semi-transparent) front railing stop the body; nobody falls into the void.

2. **Round start → arena.** Once both are present, the lobby countdown runs and at
   round start both bodies **teleport down into the arena** spawn row; each client's
   camera retargets to its own body in the arena. (With hazards enabled, tiles begin
   their cycle here.)

3. **Round end → victory cam.** Force a finish: in the server command bar drop one
   body into the void, or call `require(...ServerScriptService.Server.RoundManager).forceSwap()`
   to churn, then push a body off. When one player remains, the Results banner shows
   ("Victory" / "Defeated", "Next round in N"). During that window, **both** clients'
   cameras frame the **winner's body** standing in the arena.

4. **Lobby reset → balcony.** After the countdown, **both** bodies teleport **up to
   the balcony**, each client's camera pulls back onto its **own** body, and the
   Lobby banner shows over the gathered balcony. Both can walk around again, fenced
   in by the railings.

5. **Mid-round join.** Restart with 1 client; once a round is Active, start the 2nd
   client. The joiner appears on the **balcony** (not loose in the live arena) and is
   folded into the arena at the **next** round start.

## Pass criteria
- [ ] Bodies spawn on the balcony on join (step 1) and cannot walk off (railings hold).
- [ ] Bodies move balcony → arena at round start (step 2).
- [ ] Victory cam frames the winner for ALL clients during Ended (step 3).
- [ ] Bodies move arena → balcony at the Lobby reset, on their own bodies (step 4).
- [ ] A mid-round joiner waits on the balcony, not in the arena (step 5).
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-21-lobby-staging-area-smoke-test.md
git commit -m "docs(lobby): 2-client smoke test for the staging area

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] Run the pure test once more: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/spawn_layout.spec` → `ALL SpawnLayout TESTS PASSED`.
- [ ] `git log --oneline` shows the six task commits on `feat/lobby-staging-area`.
- [ ] Perform the Studio smoke test (Task 6) and tick its pass criteria. Runtime-only
  behavior (geometry, relocation, victory cam) is validated here, not by lune.
```
