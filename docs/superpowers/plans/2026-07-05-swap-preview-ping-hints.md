# Swap Preview Ping + First-Session Hints — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a directional ping to the swap preview (so an off-camera target is always findable) and a centralized, data-driven first-session hint system whose two rows decode the swap mechanic in-place on the ping target and the Soul halo.

**Architecture:** Pure Roblox-free modules (`HintModel`, `PingDirectionModel`, `HintRegistry`) hold all decision/data and are lune-tested; thin server glue (`HintService`, `RoundManager` call sites) fires hints server-authoritatively (no client→server remote); thin client glue (`SwapPreviewController` rewrite, new `HintController`) renders. Seen-state persists in the existing economy profile (`seenHints`).

**Tech Stack:** Luau, Rojo, lune (pure tests via `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`), Roblox Studio MCP for glue verification.

**Conventions (match existing code):**
- Lune specs are plain scripts: `require("../src/shared/X")`, local `fail`/`expect` helpers, `do ... end` blocks, `print` per case, final `print("ALL X TESTS PASSED")`. No framework.
- Pure modules take plain numbers/tables in and out — **no Roblox types in their signatures**.
- Tunables live in `Config`. Never hardcode geometry.

---

## File Structure

**Create (pure, shared):**
- `src/shared/HintModel.luau` — resolve/withSeen decision core.
- `src/shared/HintRegistry.luau` — declarative hint rows (data).
- `src/shared/PingDirectionModel.luau` — off-screen/edge/angle projection math.
- `tests/hint_model.spec.luau`, `tests/ping_direction_model.spec.luau`.

**Create (glue):**
- `src/server/HintService.luau` — server-authoritative firing + seen-state.
- `src/client/HintController.luau` — anchored label renderer + queue.
- `docs/smoke-tests/2026-07-05-preview-ping-hints-smoke-test.md`.

**Modify:**
- `src/shared/Remotes.luau` — add `ShowHint`.
- `src/shared/ProfileModel.luau` — `seenHints` in default/sanitize.
- `src/shared/Config.luau` — ping + hint tunables.
- `src/server/RoundManager.luau` — fire `SwapPreview`/`ControlSwap` triggers.
- `src/client/SwapPreviewController.luau` — full rewrite (Highlight + chevron + edge arrow).
- `src/client/init.client.luau` — start `HintController`.
- `tests/profile_model.spec.luau` — assert `seenHints`.
- `CHANGELOG.md` — entry.

---

## Task 1: `HintModel` (pure decision core)

**Files:**
- Create: `src/shared/HintModel.luau`
- Test: `tests/hint_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/hint_model.spec.luau`:

```lua
local HintModel = require("../src/shared/HintModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local REG = {
	{ id = "a", trigger = "SwapPreview", once = true, priority = 10 },
	{ id = "b", trigger = "SwapPreview", once = true, priority = 20 },
	{ id = "c", trigger = "ControlSwap", once = false, priority = 5 },
}

-- unseen + trigger match -> highest priority row.
do
	local h = HintModel.resolve(REG, {}, "SwapPreview")
	expect(h and h.id == "b", "highest-priority match wins (got " .. tostring(h and h.id) .. ")")
	print("hint: priority tie-break OK")
end

-- unknown trigger -> nil.
do
	expect(HintModel.resolve(REG, {}, "Nope") == nil, "unknown trigger -> nil")
	print("hint: unknown trigger OK")
end

-- once + already seen -> that row is skipped; falls to next unseen match.
do
	local h = HintModel.resolve(REG, { "b" }, "SwapPreview")
	expect(h and h.id == "a", "seen 'b' -> next unseen match 'a'")
	local none = HintModel.resolve(REG, { "a", "b" }, "SwapPreview")
	expect(none == nil, "all matches seen -> nil")
	print("hint: once-ever gating OK")
end

-- once = false always returns even if seen.
do
	local h = HintModel.resolve(REG, { "c" }, "ControlSwap")
	expect(h and h.id == "c", "once=false ignores seen")
	print("hint: once=false OK")
end

-- accepts a set-like seen table too.
do
	local h = HintModel.resolve(REG, { b = true }, "SwapPreview")
	expect(h and h.id == "a", "set-like seen honored")
	print("hint: set-like seen OK")
end

-- empty registry -> nil.
do
	expect(HintModel.resolve({}, {}, "SwapPreview") == nil, "empty registry -> nil")
	print("hint: empty registry OK")
end

-- withSeen is non-mutating + idempotent + deduped.
do
	local orig = { "x" }
	local out = HintModel.withSeen(orig, "y")
	expect(#orig == 1, "original not mutated")
	expect(#out == 2, "withSeen adds")
	local again = HintModel.withSeen(out, "y")
	expect(#again == 2, "withSeen idempotent (no dup)")
	print("hint: withSeen OK")
end

print("ALL HintModel TESTS PASSED")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hint_model.spec.luau`
Expected: FAIL (module not found / attempt to call nil).

- [ ] **Step 3: Write minimal implementation**

Create `src/shared/HintModel.luau`:

```lua
--[[
	HintModel -- PURE decision core for the centralized hint system. Roblox-free,
	time-free. Given the hint registry, a player's seen-set, and an incoming trigger
	event, decides which hint (if any) to show, honoring per-hint `once` gating and
	`priority`. `withSeen` is the immutable seen-set update. All logic lives here so
	the server glue (HintService) stays dumb and this is lune-testable.
	Location (Roblox): ReplicatedStorage/Shared/HintModel  (ModuleScript)
--]]

local HintModel = {}

-- Accept EITHER an array of ids { "a", "b" } OR a set { a = true } -> canonical set.
local function toSet(seen)
	local set = {}
	if type(seen) == "table" then
		for _, id in ipairs(seen) do
			set[id] = true
		end
		for k, v in pairs(seen) do
			if type(k) == "string" and v then
				set[k] = true
			end
		end
	end
	return set
end

-- Highest-priority registry row whose trigger matches and which is either not `once`
-- or not yet in `seen`. nil if none.
function HintModel.resolve(registry, seen, trigger)
	local seenSet = toSet(seen)
	local best = nil
	for _, hint in ipairs(registry) do
		if hint.trigger == trigger and not (hint.once and seenSet[hint.id]) then
			if not best or (hint.priority or 0) > (best.priority or 0) then
				best = hint
			end
		end
	end
	return best
end

-- Immutable: a new sorted array of unique ids including `id`.
function HintModel.withSeen(seen, id)
	local set = toSet(seen)
	set[id] = true
	local out = {}
	for k in pairs(set) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

return HintModel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hint_model.spec.luau`
Expected: PASS, ends with `ALL HintModel TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add src/shared/HintModel.luau tests/hint_model.spec.luau
git commit -m "feat(hints): pure HintModel resolve/withSeen (lune-tested)"
```

---

## Task 2: `HintRegistry` (declarative hint data)

**Files:**
- Create: `src/shared/HintRegistry.luau`
- Test: append a block to `tests/hint_model.spec.luau`

- [ ] **Step 1: Write the failing test** (append before the final `print` in `tests/hint_model.spec.luau`)

```lua
-- Registry rows are well-formed and unique.
do
	local Registry = require("../src/shared/HintRegistry")
	expect(#Registry >= 2, "registry has the two shipped rows")
	local ids, triggers = {}, {}
	for _, row in ipairs(Registry) do
		expect(type(row.id) == "string" and row.id ~= "", "row has id")
		expect(not ids[row.id], "row id unique: " .. tostring(row.id))
		ids[row.id] = true
		expect(row.anchor == "target" or row.anchor == "controlledBody",
			"row anchor valid: " .. tostring(row.anchor))
		expect(type(row.text) == "string" and #row.text > 0, "row has text")
		expect(type(row.duration) == "number" and row.duration > 0, "row has duration")
		triggers[row.trigger] = true
	end
	expect(triggers.SwapPreview and triggers.ControlSwap, "both triggers present")
	print("hint: registry well-formed OK")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hint_model.spec.luau`
Expected: FAIL (HintRegistry not found).

- [ ] **Step 3: Write implementation**

Create `src/shared/HintRegistry.luau`:

```lua
--[[
	HintRegistry -- the SINGLE SOURCE OF TRUTH for first-session / contextual hints.
	Pure data, Roblox-free. Each row:
	  { id, trigger, once, priority, duration, anchor, text }
	 - trigger: a generic gameplay event name fired server-side (HintService.fireTrigger)
	 - once:    gate on the player's persisted seenHints (true = show one time ever)
	 - anchor:  "target" (the swap-preview body) | "controlledBody" (the Soul-halo body)
	Adding a hint = adding a row here + firing its trigger. No other plumbing.
	Location (Roblox): ReplicatedStorage/Shared/HintRegistry  (ModuleScript)
--]]

local HintRegistry = {
	{
		id = "swap-preview-intro",
		trigger = "SwapPreview",
		once = true,
		priority = 10,
		duration = 3.0,
		anchor = "target",
		text = "You're about to become the highlighted body — get ready!",
	},
	{
		id = "swap-commit-intro",
		trigger = "ControlSwap",
		once = true,
		priority = 10,
		duration = 3.5,
		anchor = "controlledBody",
		text = "Your controls just moved — the glowing halo is always you.",
	},
}

return HintRegistry
```

- [ ] **Step 4: Run to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/hint_model.spec.luau`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/shared/HintRegistry.luau tests/hint_model.spec.luau
git commit -m "feat(hints): HintRegistry with the two first-session rows"
```

---

## Task 3: `PingDirectionModel` (pure projection math)

**Files:**
- Create: `src/shared/PingDirectionModel.luau`
- Test: `tests/ping_direction_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/ping_direction_model.spec.luau`:

```lua
local M = require("../src/shared/PingDirectionModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1) end

local W, H, MARGIN = 1000, 800, 50 -- center = (500, 400)

-- dead-center, in front -> onScreen.
do
	local r = M.resolve(500, 400, 10, W, H, MARGIN)
	expect(r.onScreen, "center in front -> onScreen")
	print("ping: onScreen center OK")
end

-- far off the right, in front -> off-screen, clamped to right margin, points right (~90deg).
do
	local r = M.resolve(5000, 400, 10, W, H, MARGIN)
	expect(not r.onScreen, "off right -> not onScreen")
	expect(near(r.x, W - MARGIN, 2), "clamped to right margin, got " .. r.x)
	expect(near(r.rotationDeg, 90, 1), "points right (~90), got " .. r.rotationDeg)
	print("ping: off-right OK")
end

-- far above, in front -> off-screen, clamped to top margin, points up (~0deg).
do
	local r = M.resolve(500, -5000, 10, W, H, MARGIN)
	expect(not r.onScreen, "above -> not onScreen")
	expect(near(r.y, MARGIN, 2), "clamped to top margin, got " .. r.y)
	expect(near(r.rotationDeg, 0, 1), "points up (~0), got " .. r.rotationDeg)
	print("ping: off-top OK")
end

-- behind camera (z<0), projected point reads bottom-left; must flip to point the true way.
do
	-- target behind + to the true right: WorldToViewportPoint mirrors it to the left.
	local r = M.resolve(200, 400, -10, W, H, MARGIN)
	expect(not r.onScreen, "behind camera -> not onScreen")
	-- projected dx = 200-500 = -300; flipped -> +300 -> points right (~90).
	expect(near(r.rotationDeg, 90, 1), "behind-camera direction flipped, got " .. r.rotationDeg)
	print("ping: behind-camera flip OK")
end

-- a point just inside the margin rect, in front -> onScreen.
do
	local r = M.resolve(MARGIN + 5, 400, 10, W, H, MARGIN)
	expect(r.onScreen, "just inside left margin -> onScreen")
	print("ping: inside-margin OK")
end

print("ALL PingDirectionModel TESTS PASSED")
```

- [ ] **Step 2: Run to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/ping_direction_model.spec.luau`
Expected: FAIL (module not found).

- [ ] **Step 3: Write implementation**

Create `src/shared/PingDirectionModel.luau`:

```lua
--[[
	PingDirectionModel -- PURE screen-projection math for the swap-preview directional
	ping. The controller does the Roblox call (Camera:WorldToViewportPoint) and passes
	the raw numbers here so this stays Roblox-free + lune-testable.

	resolve(sx, sy, sz, w, h, margin):
	  sx,sy = viewport pixel coords; sz = depth (>0 in front of camera, <=0 behind);
	  w,h   = viewport size; margin = edge inset for the off-screen arrow.
	Returns { onScreen, x, y, rotationDeg }:
	  onScreen -> target projects inside the margin rect AND is in front; x,y = sx,sy.
	  else     -> x,y clamped to the margin rect along the direction to the target;
	              rotationDeg rotates an UP-pointing arrow (screen -Y) to face it
	              (0 = up, 90 = right, 180 = down, -90 = left).
	Location (Roblox): ReplicatedStorage/Shared/PingDirectionModel  (ModuleScript)
--]]

local PingDirectionModel = {}

function PingDirectionModel.resolve(sx, sy, sz, w, h, margin)
	local cx, cy = w * 0.5, h * 0.5
	local inFront = sz > 0
	local onScreen = inFront
		and sx >= margin and sx <= (w - margin)
		and sy >= margin and sy <= (h - margin)
	if onScreen then
		return { onScreen = true, x = sx, y = sy, rotationDeg = 0 }
	end

	local dx, dy = sx - cx, sy - cy
	if not inFront then
		dx, dy = -dx, -dy -- behind camera: WorldToViewportPoint mirrors the point; flip it
	end
	if dx == 0 and dy == 0 then
		dy = -1 -- degenerate: point up
	end

	local halfW = math.max(cx - margin, 1)
	local halfH = math.max(cy - margin, 1)
	local scale
	if dx == 0 then
		scale = halfH / math.abs(dy)
	elseif dy == 0 then
		scale = halfW / math.abs(dx)
	else
		scale = math.min(halfW / math.abs(dx), halfH / math.abs(dy))
	end

	return {
		onScreen = false,
		x = cx + dx * scale,
		y = cy + dy * scale,
		rotationDeg = math.deg(math.atan2(dx, -dy)),
	}
end

return PingDirectionModel
```

- [ ] **Step 4: Run to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/ping_direction_model.spec.luau`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/shared/PingDirectionModel.luau tests/ping_direction_model.spec.luau
git commit -m "feat(ping): pure PingDirectionModel edge/angle math (lune-tested)"
```

---

## Task 4: `ProfileModel.seenHints` (persistence field)

**Files:**
- Modify: `src/shared/ProfileModel.luau`
- Test: `tests/profile_model.spec.luau`

- [ ] **Step 1: Add failing assertions** — append before the final `print` in `tests/profile_model.spec.luau`:

```lua
-- seenHints: default empty; sanitize keeps unique strings, drops junk, dedupes.
do
	local d = ProfileModel.default(V)
	expect(type(d.seenHints) == "table" and #d.seenHints == 0, "default seenHints = {}")
	local p = ProfileModel.sanitize({ coins = 1, totalXp = 1, seenHints = { "a", "a", 7, "b" } }, V)
	expect(#p.seenHints == 2, "dedupe + drop non-strings -> 2, got " .. #p.seenHints)
	local n = ProfileModel.sanitize({ seenHints = "nope" }, V)
	expect(type(n.seenHints) == "table" and #n.seenHints == 0, "non-array seenHints -> {}")
	print("profile: seenHints OK")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/profile_model.spec.luau`
Expected: FAIL (seenHints nil).

- [ ] **Step 3: Implement** — edit `src/shared/ProfileModel.luau`.

Replace `ProfileModel.default`:

```lua
function ProfileModel.default(version)
	return { version = version, coins = 0, totalXp = 0, seenHints = {} }
end
```

Add this helper right after `toCount` (before `ProfileModel.default`):

```lua
-- Array of unique non-empty strings; anything else -> {}. (Persisted hint-seen ids.)
local function toStringList(v)
	local out, seen = {}, {}
	if type(v) == "table" then
		for _, item in ipairs(v) do
			if type(item) == "string" and item ~= "" and not seen[item] then
				seen[item] = true
				out[#out + 1] = item
			end
		end
	end
	return out
end
```

Replace the body of `ProfileModel.sanitize` so it also sets `seenHints`:

```lua
function ProfileModel.sanitize(blob, version)
	local profile = ProfileModel.default(version)
	if type(blob) == "table" then
		profile.coins = toCount(blob.coins) or 0
		profile.totalXp = toCount(blob.totalXp) or 0
		profile.seenHints = toStringList(blob.seenHints)
	end
	return profile
end
```

Also update the module's top comment: the persisted blob is now `{ version, coins, totalXp, seenHints }`.

- [ ] **Step 4: Run to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/profile_model.spec.luau`
Expected: PASS. Migration-safe (old blobs get `seenHints = {}`); **no PROFILE_VERSION bump**.

- [ ] **Step 5: Commit**

```bash
git add src/shared/ProfileModel.luau tests/profile_model.spec.luau
git commit -m "feat(profile): persist seenHints (migration-safe, no version bump)"
```

---

## Task 5: `Config` tunables + `ShowHint` remote

**Files:**
- Modify: `src/shared/Config.luau`
- Modify: `src/shared/Remotes.luau`

- [ ] **Step 1: Add Config block** — insert before the final `return Config` in `src/shared/Config.luau`:

```lua
-- ===== Swap-preview directional ping =====
Config.PING_COLOR = Color3.fromRGB(255, 200, 60)          -- amber; matches the preview Highlight fill
Config.PING_OUTLINE_COLOR = Color3.fromRGB(255, 220, 120)
Config.PING_EDGE_MARGIN = 48        -- px inset from the screen edge for the off-screen arrow
Config.PING_ARROW_SIZE = 44         -- px, off-screen edge arrow
Config.PING_CHEVRON_SIZE = 28       -- px, on-target chevron
Config.PING_CHEVRON_HEIGHT = 3.2    -- studs above the target head

-- ===== First-session hints =====
Config.HINT_FADE_IN = 0.2           -- seconds
Config.HINT_FADE_OUT = 0.3          -- seconds
Config.HINT_LABEL_HEIGHT = 3.4      -- studs above the anchor head
Config.HINT_LABEL_SIZE = Vector2.new(224, 56) -- px billboard size
```

- [ ] **Step 2: Add the remote** — in `src/shared/Remotes.luau`, add `"ShowHint"` to the `REMOTE_EVENTS` list (server→client; the client never fires it, so the zero client→server-remote property is preserved). Change:

```lua
local REMOTE_EVENTS = {
	"SetControlledBody", "RoundStateChanged", "EliminationEvent", "SpectateBody", "SwapPreview", "SoulMap",
	"RewardGranted",  -- server->client: per-round reward delta { coins, xp, leveledUp }
	"ProfileUpdated", -- server->client: authoritative HUD state { coins, level, xpIntoLevel, xpForNext, progress }
	"ShowHint",       -- server->client: first-session hint { id, text, duration, anchor }
}
```

- [ ] **Step 3: Sanity-check** there is no lune test for these (Roblox types). Run the full suite to confirm nothing broke:

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: every suite prints its `ALL ... PASSED`.

- [ ] **Step 4: Commit**

```bash
git add src/shared/Config.luau src/shared/Remotes.luau
git commit -m "feat(preview): Config ping/hint tunables + ShowHint remote (server->client)"
```

---

## Task 6: `HintService` (server-authoritative firing)

**Files:**
- Create: `src/server/HintService.luau`

- [ ] **Step 1: Implement** — create `src/server/HintService.luau`:

```lua
--[[
	HintService (server) -- server-authoritative first-session hint firing. The client
	NEVER reports back (no client->server remote): the server owns the decision AND the
	seen-state. fireTrigger(player, trigger):
	  1. read the player's persisted seenHints via EconomyService (nil profile -> no-op);
	  2. HintModel.resolve against the registry;
	  3. on a hit: fire ShowHint to that client + append the id to seenHints (mutates the
	     cached profile; the existing autosave / leave-save path persists it).
	Location (Roblox): ServerScriptService/Server/HintService  (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HintModel = require(ReplicatedStorage.Shared.HintModel)
local HintRegistry = require(ReplicatedStorage.Shared.HintRegistry)
local EconomyService = require(script.Parent.EconomyService)

local ShowHint = Remotes.get("ShowHint")

local HintService = {}

function HintService.fireTrigger(player, trigger)
	local profile = EconomyService.getProfile(player)
	if not profile then
		return -- not loaded yet / already left: nothing to gate against
	end
	local hint = HintModel.resolve(HintRegistry, profile.seenHints, trigger)
	if not hint then
		return
	end
	ShowHint:FireClient(player, {
		id = hint.id,
		text = hint.text,
		duration = hint.duration,
		anchor = hint.anchor,
	})
	profile.seenHints = HintModel.withSeen(profile.seenHints, hint.id)
end

return HintService
```

- [ ] **Step 2: Verify it loads in Studio (MCP)** — the pure requires are lune-covered; confirm the server module requires cleanly in the real VM:

Use MCP `execute_luau` (datamodel `Server`):

```lua
local HintService = require(game.ServerScriptService.Server.HintService)
return type(HintService.fireTrigger)
```

Expected: `function`. (If MCP is unreachable, STOP and notify the user.)

- [ ] **Step 3: Commit**

```bash
git add src/server/HintService.luau
git commit -m "feat(hints): server-authoritative HintService.fireTrigger"
```

---

## Task 7: Fire the triggers from `RoundManager`

**Files:**
- Modify: `src/server/RoundManager.luau`

- [ ] **Step 1: Require HintService** — near the other server requires at the top of `src/server/RoundManager.luau` (where `ControlManager`, `BodyManager` etc. are required), add:

```lua
local HintService = require(script.Parent.HintService)
```

- [ ] **Step 2: Fire `SwapPreview`** — in `firePreview` (currently around line 267-271), add the trigger after the existing `SwapPreview:FireClient`:

```lua
local function firePreview(plan)
	for _, pair in ipairs(plan.to) do
		SwapPreview:FireClient(pair.player, pair.body)
		HintService.fireTrigger(pair.player, "SwapPreview")
	end
end
```

- [ ] **Step 3: Fire `ControlSwap`** — in `commitSwap` (around line 314-328), after `stampGrace(players)`, loop the committed players and fire. The `stampGrace` order matters: `SwapController.commit` has already fired `SetControlledBody` to each client, so firing the hint after keeps the client's `controlledBody` current when `ShowHint` arrives. Change the tail of `commitSwap`:

```lua
	SwapController.commit(plan)
	local players = {}
	for _, pair in ipairs(plan.to) do
		players[#players + 1] = pair.player
	end
	stampGrace(players)
	for _, p in ipairs(players) do
		HintService.fireTrigger(p, "ControlSwap")
	end
end
```

- [ ] **Step 4: Verify the require graph loads (MCP)** — no lune coverage for RoundManager glue. Confirm the server boots without a require cycle:

Use MCP `execute_luau` (datamodel `Server`):

```lua
local ok, err = pcall(function()
	return require(game.ServerScriptService.Server.RoundManager)
end)
return ok and "RoundManager loaded" or ("ERROR: " .. tostring(err))
```

Expected: `RoundManager loaded`. If it reports a require cycle (RoundManager↔HintService↔EconomyService), STOP — HintService must not require RoundManager; report to the user. (If MCP is unreachable, STOP and notify the user.)

- [ ] **Step 5: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(hints): fire SwapPreview/ControlSwap triggers from RoundManager"
```

---

## Task 8: `SwapPreviewController` rewrite (the directional ping)

**Files:**
- Modify (full rewrite): `src/client/SwapPreviewController.luau`

- [ ] **Step 1: Replace the file** with the full ping implementation:

```lua
--[[
	SwapPreviewController -- the swap-preview DIRECTIONAL PING. Highlights the body
	THIS client will inherit AND guides the eye to it, because the target is frequently
	off-camera (a Highlight you can't see is not a preview):
	  - the shipped amber Highlight on the target body,
	  - an on-target chevron (BillboardGui) while the target is on-screen,
	  - an off-screen edge arrow (ScreenGui) that points toward the target otherwise.
	A per-frame update projects the target via the camera and feeds the pure
	PingDirectionModel (Roblox-free, lune-tested). Clears on the commit's
	SetControlledBody retarget or when the round leaves Active.
	Location: StarterPlayerScripts/Client/SwapPreviewController  (ModuleScript)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PingDirectionModel = require(Shared:WaitForChild("PingDirectionModel"))

local SwapPreview = Remotes.get("SwapPreview")
local SetControlledBody = Remotes.get("SetControlledBody")
local RoundStateChanged = Remotes.get("RoundStateChanged")

local localPlayer = Players.LocalPlayer

local SwapPreviewController = {}
local target = nil          -- the Model this client will inherit
local highlight = nil
local chevron = nil         -- BillboardGui on the target head
local screenGui = nil
local arrow = nil           -- off-screen edge arrow (TextLabel)
local renderConn = nil

local function ensureGui()
	if screenGui then
		return
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SwapPingGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 20
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

	arrow = Instance.new("TextLabel")
	arrow.Name = "EdgeArrow"
	arrow.Size = UDim2.fromOffset(Config.PING_ARROW_SIZE, Config.PING_ARROW_SIZE)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.Text = "\u{25B2}" -- up triangle; rotationDeg rotates it to face the target
	arrow.TextScaled = true
	arrow.TextColor3 = Config.PING_COLOR
	arrow.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 24, 31)
	stroke.Parent = arrow
	arrow.Parent = screenGui
end

local function makeChevron(body)
	local head = body:FindFirstChild("Head") or body:FindFirstChild("HumanoidRootPart")
	if not head then
		return nil
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "SwapPingChevron"
	bb.Size = UDim2.fromOffset(Config.PING_CHEVRON_SIZE, Config.PING_CHEVRON_SIZE)
	bb.StudsOffsetWorldSpace = Vector3.new(0, Config.PING_CHEVRON_HEIGHT, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = "\u{25BC}" -- down triangle over the head
	lbl.TextScaled = true
	lbl.TextColor3 = Config.PING_COLOR
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(20, 24, 31)
	stroke.Parent = lbl
	lbl.Parent = bb
	return bb
end

local function clear()
	target = nil
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	if chevron then
		chevron:Destroy()
		chevron = nil
	end
	if arrow then
		arrow.Visible = false
	end
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function update()
	if not (target and target.Parent) then
		clear()
		return
	end
	local root = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Head")
	local camera = Workspace.CurrentCamera
	if not (root and camera) then
		return
	end
	local vp = camera.ViewportSize
	local sp = camera:WorldToViewportPoint(root.Position)
	local r = PingDirectionModel.resolve(sp.X, sp.Y, sp.Z, vp.X, vp.Y, Config.PING_EDGE_MARGIN)
	if chevron then
		chevron.Enabled = r.onScreen
	end
	if arrow then
		if r.onScreen then
			arrow.Visible = false
		else
			arrow.Visible = true
			arrow.Position = UDim2.fromOffset(r.x, r.y)
			arrow.Rotation = r.rotationDeg
		end
	end
end

local function begin(body)
	clear()
	if not (body and body:IsA("Model")) then
		return
	end
	target = body
	highlight = Instance.new("Highlight")
	highlight.Name = "SwapTargetHighlight"
	highlight.FillColor = Config.PING_COLOR
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Config.PING_OUTLINE_COLOR
	highlight.Adornee = body
	highlight.Parent = body
	chevron = makeChevron(body)
	ensureGui()
	renderConn = RunService.RenderStepped:Connect(update)
end

function SwapPreviewController.start()
	SwapPreview.OnClientEvent:Connect(begin)
	-- The commit retargets control -> the preview is over.
	SetControlledBody.OnClientEvent:Connect(clear)
	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state.phase ~= "Active" then
			clear()
		end
	end)
end

return SwapPreviewController
```

- [ ] **Step 2: Verify in Studio (MCP)** — see Task 11's live check; for now confirm the module compiles/loads on the client VM:

Use MCP `execute_luau` (datamodel `Client`):

```lua
local ok, err = pcall(function()
	return require(game.Players.LocalPlayer.PlayerScripts.Client.SwapPreviewController)
end)
return ok and "SwapPreviewController loaded" or ("ERROR: " .. tostring(err))
```

Expected: `SwapPreviewController loaded`. (Adjust the path if PlayerScripts differs; the important check is a clean require. If MCP is unreachable, STOP and notify the user.)

- [ ] **Step 3: Commit**

```bash
git add src/client/SwapPreviewController.luau
git commit -m "feat(ping): SwapPreviewController edge arrow + on-target chevron"
```

---

## Task 9: `HintController` (anchored label renderer)

**Files:**
- Create: `src/client/HintController.luau`

- [ ] **Step 1: Implement** — create `src/client/HintController.luau`:

```lua
--[[
	HintController -- renders server-authoritative first-session hints as labels
	ANCHORED to the thing they explain: the swap-preview target ("you become this") or
	the local controlled body / Soul-halo body ("this is you"). The "which hint /
	once-ever" decision already happened server-side (HintService); this only renders.
	A sequential queue guarantees one hint at a time (future rows may fire close
	together). Non-blocking: never pauses input; auto-dismisses.
	Location: StarterPlayerScripts/Client/HintController  (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShowHint = Remotes.get("ShowHint")
local SwapPreview = Remotes.get("SwapPreview")
local SetControlledBody = Remotes.get("SetControlledBody")

local HintController = {}
local previewTarget = nil     -- last SwapPreview body
local controlledBody = nil    -- last SetControlledBody body
local queue = {}
local showing = false

local function anchorBody(anchor)
	if anchor == "controlledBody" then
		return controlledBody
	end
	return previewTarget
end

local function present(hint)
	local body = anchorBody(hint.anchor)
	if not (body and body.Parent) then
		return -- anchor gone; drop this hint silently
	end
	local head = body:FindFirstChild("Head") or body:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "HintLabel"
	bb.Size = UDim2.fromOffset(Config.HINT_LABEL_SIZE.X, Config.HINT_LABEL_SIZE.Y)
	bb.StudsOffsetWorldSpace = Vector3.new(0, Config.HINT_LABEL_HEIGHT, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(17, 22, 31)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Config.PING_OUTLINE_COLOR
	stroke.Transparency = 1
	stroke.Parent = panel
	panel.Parent = bb

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(0.9, 0.78)
	lbl.Position = UDim2.fromScale(0.05, 0.11)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = hint.text
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 235, 190)
	lbl.TextTransparency = 1
	local ls = Instance.new("UIStroke")
	ls.Thickness = 1
	ls.Color = Color3.fromRGB(20, 24, 31)
	ls.Transparency = 1
	ls.Parent = lbl
	lbl.Parent = panel

	local inInfo = TweenInfo.new(Config.HINT_FADE_IN)
	TweenService:Create(panel, inInfo, { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(stroke, inInfo, { Transparency = 0 }):Play()
	TweenService:Create(lbl, inInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(ls, inInfo, { Transparency = 0 }):Play()

	task.delay(Config.HINT_FADE_IN + (hint.duration or 3), function()
		local outInfo = TweenInfo.new(Config.HINT_FADE_OUT)
		TweenService:Create(panel, outInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, outInfo, { Transparency = 1 }):Play()
		TweenService:Create(ls, outInfo, { Transparency = 1 }):Play()
		local fade = TweenService:Create(lbl, outInfo, { TextTransparency = 1 })
		fade.Completed:Connect(function()
			if bb then
				bb:Destroy()
			end
		end)
		fade:Play()
	end)
end

local function pump()
	if showing then
		return
	end
	local hint = table.remove(queue, 1)
	if not hint then
		return
	end
	showing = true
	present(hint)
	-- Hold the slot for the label's full lifetime so two never overlap.
	local life = Config.HINT_FADE_IN + (hint.duration or 3) + Config.HINT_FADE_OUT
	task.delay(life, function()
		showing = false
		pump()
	end)
end

function HintController.start()
	SwapPreview.OnClientEvent:Connect(function(body)
		previewTarget = body
	end)
	SetControlledBody.OnClientEvent:Connect(function(body)
		controlledBody = body
	end)
	ShowHint.OnClientEvent:Connect(function(hint)
		if type(hint) ~= "table" or type(hint.text) ~= "string" then
			return
		end
		queue[#queue + 1] = hint
		pump()
	end)
end

return HintController
```

- [ ] **Step 2: Verify it loads (MCP)** — MCP `execute_luau` (datamodel `Client`):

```lua
local ok, err = pcall(function()
	return require(game.Players.LocalPlayer.PlayerScripts.Client.HintController)
end)
return ok and "HintController loaded" or ("ERROR: " .. tostring(err))
```

Expected: `HintController loaded`. (If MCP is unreachable, STOP and notify the user.)

- [ ] **Step 3: Commit**

```bash
git add src/client/HintController.luau
git commit -m "feat(hints): HintController anchored-label renderer + queue"
```

---

## Task 10: Wire `HintController` into the client bootstrap

**Files:**
- Modify: `src/client/init.client.luau`

- [ ] **Step 1: Add the require + start** — in `src/client/init.client.luau`, add the require alongside the others (after `SoulController`):

```lua
local SoulController = require(script.SoulController)
local HintController = require(script.HintController)
```

and the start call after `SoulController.start()`:

```lua
SoulController.start()
HintController.start()
```

- [ ] **Step 2: Verify the client boots (MCP)** — start Play, read the console for the ready line and any errors:

Use MCP `start_stop_play` to start Play, then `get_console_output`. Expected: `[BSR] Client ready (ownership-transfer model).` and NO red errors mentioning HintController / SwapPreviewController / PingDirectionModel. Stop Play afterward. (If MCP is unreachable, STOP and notify the user.)

- [ ] **Step 3: Commit**

```bash
git add src/client/init.client.luau
git commit -m "feat(hints): start HintController in the client bootstrap"
```

---

## Task 11: Studio glue verification + smoke-test doc + CHANGELOG

**Files:**
- Create: `docs/smoke-tests/2026-07-05-preview-ping-hints-smoke-test.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Live-verify the ping + hints in Studio (MCP).** With one Play session:
  1. Confirm a fresh profile has empty `seenHints` (read the body/attribute or `EconomyService.getProfile` on the Server datamodel).
  2. Force a swap to exercise a preview + commit without waiting the cadence: on the **Server** datamodel, `require(game.ServerScriptService.Server.RoundManager).forceSwap()` (per the disconnect smoke test) — note `forceSwap` runs `doSwap` (no preview window). To exercise the *preview* path and the `SwapPreview` hint, instead drive a real round (2 bots / 2 players) OR temporarily call `firePreview` semantics; document whichever you used.
  3. Confirm `ShowHint` fires once: read that the client received a hint (e.g., check for the `HintLabel` BillboardGui under the controlled body / target) and that `profile.seenHints` now contains the id.
  4. Trigger a second preview/swap and confirm NO second `ShowHint` for the same id (seen-state gating).
  5. Confirm the off-screen edge arrow appears (turn the camera away from the target) and the on-target chevron shows when the target is framed.
  Record actual observed results. If any glue is broken, fix it (new commit) before writing the doc. (If MCP is unreachable at any point, STOP and notify the user.)

- [ ] **Step 2: Write the smoke-test doc** — create `docs/smoke-tests/2026-07-05-preview-ping-hints-smoke-test.md` documenting the manual 2-client procedure and the acceptance cases:
  - Off-camera target: the edge arrow appears at the screen edge and points toward it; framing the target swaps the arrow for the on-target chevron.
  - First-time player: sees the preview hint on the target, then the commit hint on the halo — each once.
  - Returning player (seenHints populated): sees neither hint.
  - Hints never overlap (sequential queue); nothing blocks input/movement.
  Include the exact MCP snippets used in Step 1 and the observed results from this run.

- [ ] **Step 3: Update CHANGELOG** — add under `## [Unreleased] > ### Added` in `CHANGELOG.md`:

```markdown
- **Swap-preview directional ping + centralized first-session hints (review Action #7, partial).**
  The preview now guides the eye to an off-camera target — an on-target chevron when it's framed, a
  screen-edge arrow that points toward it (incl. behind-camera) otherwise — via the pure, lune-tested
  `PingDirectionModel` (`SwapPreviewController` rewrite; keeps the amber Highlight). New centralized,
  data-driven hint system decodes the swap for first-timers: `HintRegistry` (rows) + pure `HintModel`
  (`tests/hint_model.spec.luau`) + server-authoritative `HintService` (fires from `RoundManager`;
  no client→server remote) + client `HintController` rendering labels ANCHORED to the ping target
  ("you become this") then the Soul halo ("this is you"), once-ever per player via persisted
  `profile.seenHints` (migration-safe, no `PROFILE_VERSION` bump). Tunables in `Config.PING_*` /
  `Config.HINT_*`. Smoke test `docs/smoke-tests/2026-07-05-preview-ping-hints-smoke-test.md`.
  Deferred (recorded in the spec): danger read, round-start grace, tutorial round, richer hint set.
```

- [ ] **Step 4: Run the full lune suite one last time**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || exit 1; done`
Expected: every suite prints `ALL ... PASSED`.

- [ ] **Step 5: Commit**

```bash
git add docs/smoke-tests/2026-07-05-preview-ping-hints-smoke-test.md CHANGELOG.md
git commit -m "docs(preview): ping+hints smoke test + CHANGELOG (review Action #7)"
```

---

## Self-Review (completed by plan author)

- **Spec coverage:** ping edge-arrow+chevron (Task 3, 8) ✓; keep Highlight (Task 8) ✓; centralized hint system — registry (T2), pure model (T1), server firing (T6/T7), client render (T9/T10) ✓; anchored presentation (T9) ✓; `seenHints` persistence, migration-safe (T4) ✓; `ShowHint` server→client only, zero-C2S preserved (T5) ✓; lune tests (T1/T2/T3/T4) ✓; Studio MCP verification (T6-T11) ✓; smoke doc + CHANGELOG (T11) ✓; deferred items recorded (spec + CHANGELOG) ✓.
- **Placeholders:** none — every code step shows complete code.
- **Type consistency:** `HintModel.resolve(registry, seen, trigger)` / `withSeen(seen, id)` consistent across T1/T6; `ShowHint` payload `{id,text,duration,anchor}` consistent T6/T9; `PingDirectionModel.resolve(sx,sy,sz,w,h,margin)->{onScreen,x,y,rotationDeg}` consistent T3/T8; `Config.PING_*`/`HINT_*` names consistent T5/T8/T9; `anchor` values `"target"`/`"controlledBody"` consistent registry(T2)/controller(T9).
- **Ordering risk noted:** server fires `SetControlledBody` (commit) before `ShowHint` (ControlSwap) so the client's `controlledBody` is current — pinned in T7 Step 3.
- **Require-cycle guard:** HintService requires EconomyService (not RoundManager); RoundManager requires HintService — acyclic. Verified in T7 Step 4.
