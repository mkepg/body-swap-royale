# Economy & Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reward each round with persistent Coins, XP, and Levels — closing the last MVP Definition-of-Done item ("…and earn currency").

**Architecture:** Four pure, Roblox-free, lune-tested modules (`RewardModel`, `ProgressionModel`, `ProfileModel`, `RewardScreenModel`) own all logic; two server-glue modules (`ProfileStore` DataStore wrapper, `EconomyService` session cache + award) and one client module (`ClientEconomyHud`) integrate them. `RoundManager.endRound` awards every round participant; profiles load on join and save on leave / autosave / shutdown with a no-clobber-on-failed-load guard.

**Tech Stack:** Luau, Rojo, lune (pure-module tests via `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`), Roblox `DataStoreService`, `RemoteEvent`s created at runtime by `Remotes.luau`.

**Conventions:** Pure modules take tunables via an injected `opts` table and never `require` Config (keeps them Roblox-free / lune-testable). Test harness mirrors `tests/round_screen_model.spec.luau` (`require("../src/shared/<Module>")`, local `expect`/`fail`).

---

### Task 1: Config economy block

**Files:**
- Modify: `src/shared/Config.luau` (append before `return Config`)

- [ ] **Step 1: Add the economy tunables block**

Insert immediately before the final `return Config` line:

```lua
-- ===== Economy & Persistence (Coins + XP + Level) =====
-- Reward formula (RewardModel). XP matches the GDD §9 formula verbatim; coins
-- are tuned to the GDD §8 ~20-100/round range via survival depth (swaps survived).
Config.REWARD_XP_BASE = 25          -- participation
Config.REWARD_XP_PER_SWAP = 5       -- per swap survived
Config.REWARD_XP_WIN = 100          -- winner bonus
Config.REWARD_COINS_BASE = 15       -- participation
Config.REWARD_COINS_PER_SWAP = 4    -- per swap survived
Config.REWARD_COINS_WIN = 40        -- winner bonus

-- Progression (ProgressionModel). XP to advance FROM level L = floor(COEFF * L ^ EXP).
Config.PROGRESSION_XP_COEFF = 100
Config.PROGRESSION_XP_EXP = 1.4
Config.PROGRESSION_MAX_LEVEL = 100

-- Persistence (ProfileStore / EconomyService).
Config.DATASTORE_NAME = "PlayerData_v1"
Config.PROFILE_VERSION = 1
Config.ECONOMY_LOAD_RETRIES = 4         -- load attempts before giving up (then persisted=false)
Config.ECONOMY_SAVE_RETRIES = 3         -- save attempts before logging failure
Config.ECONOMY_RETRY_BACKOFF = 1.0      -- seconds; multiplied by the attempt number
Config.ECONOMY_AUTOSAVE_SECONDS = 120   -- periodic background-save cadence
```

- [ ] **Step 2: Sanity-check the file parses**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_screen_model.spec.luau`
Expected: `ALL RoundScreenModel TESTS PASSED` (an unrelated test; confirms the repo still runs — Config isn't required by it, so this only proves nothing else broke).

- [ ] **Step 3: Commit**

```bash
git add src/shared/Config.luau
git commit -m "feat(economy): add Coins/XP/Level + persistence tunables to Config"
```

---

### Task 2: ProgressionModel (pure)

**Files:**
- Create: `src/shared/ProgressionModel.luau`
- Test: `tests/progression_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/progression_model.spec.luau`:

```lua
local ProgressionModel = require("../src/shared/ProgressionModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local OPTS = { coeff = 100, exp = 1.4, maxLevel = 100 }

-- xpForLevel(1) = floor(100 * 1^1.4) = 100.
do
	expect(ProgressionModel.xpForLevel(1, OPTS) == 100, "L1 needs 100, got " .. tostring(ProgressionModel.xpForLevel(1, OPTS)))
	print("progression: xpForLevel-base OK")
end

-- xpForLevel is strictly increasing.
do
	local prev = -1
	for level = 1, 50 do
		local need = ProgressionModel.xpForLevel(level, OPTS)
		expect(need > prev, "xpForLevel not increasing at level " .. level)
		prev = need
	end
	print("progression: xpForLevel-monotonic OK")
end

-- 0 xp -> level 1, no progress.
do
	local v = ProgressionModel.levelFor(0, OPTS)
	expect(v.level == 1, "0 xp is level 1, got " .. tostring(v.level))
	expect(v.xpIntoLevel == 0, "0 xp into level")
	expect(v.xpForNext == 100, "next needs 100")
	expect(v.progress == 0, "no progress")
	print("progression: levelFor-zero OK")
end

-- Just below the L1->L2 threshold stays level 1; exactly at it becomes level 2.
do
	local below = ProgressionModel.levelFor(99, OPTS)
	expect(below.level == 1, "99 xp still level 1, got " .. tostring(below.level))
	expect(below.xpIntoLevel == 99, "99 into level 1")
	expect(below.progress > 0 and below.progress < 1, "progress in (0,1), got " .. tostring(below.progress))
	local at = ProgressionModel.levelFor(100, OPTS)
	expect(at.level == 2, "100 xp is level 2, got " .. tostring(at.level))
	expect(at.xpIntoLevel == 0, "0 into level 2")
	print("progression: levelFor-threshold OK")
end

-- Clamp at maxLevel: enormous xp pins to maxLevel with full progress and no next.
do
	local v = ProgressionModel.levelFor(1e12, OPTS)
	expect(v.level == 100, "clamped to maxLevel, got " .. tostring(v.level))
	expect(v.progress == 1, "max level full progress")
	expect(v.xpForNext == 0, "no next at max level")
	print("progression: levelFor-clamp OK")
end

print("ALL ProgressionModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/progression_model.spec.luau`
Expected: FAIL (cannot require `ProgressionModel` — file does not exist).

- [ ] **Step 3: Write the implementation**

Create `src/shared/ProgressionModel.luau`:

```lua
--[[
	ProgressionModel -- PURE XP <-> level math. Roblox-free, no clocks/RNG; the
	caller injects tunables via `opts = { coeff, exp, maxLevel }` (server passes
	Config values; tests pass literals). Level is DERIVED from cumulative totalXp,
	never stored, so the curve can change without a data migration.
	Location (Roblox): ReplicatedStorage/Shared/ProgressionModel  (ModuleScript)
--]]

local ProgressionModel = {}

-- XP required to advance FROM `level` to `level + 1`.
function ProgressionModel.xpForLevel(level, opts)
	return math.floor(opts.coeff * level ^ opts.exp)
end

-- Derive { level, xpIntoLevel, xpForNext, progress } from cumulative totalXp.
-- Players start at level 1 with 0 xp; reaching level L costs the sum of
-- xpForLevel(1..L-1). Clamped at opts.maxLevel (full bar, no next).
function ProgressionModel.levelFor(totalXp, opts)
	local level = 1
	local remaining = math.max(0, math.floor(totalXp))
	while level < opts.maxLevel do
		local need = ProgressionModel.xpForLevel(level, opts)
		if remaining < need then
			break
		end
		remaining -= need
		level += 1
	end
	if level >= opts.maxLevel then
		return { level = opts.maxLevel, xpIntoLevel = 0, xpForNext = 0, progress = 1 }
	end
	local need = ProgressionModel.xpForLevel(level, opts)
	return {
		level = level,
		xpIntoLevel = remaining,
		xpForNext = need,
		progress = need > 0 and remaining / need or 0,
	}
end

return ProgressionModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/progression_model.spec.luau`
Expected: `ALL ProgressionModel TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add src/shared/ProgressionModel.luau tests/progression_model.spec.luau
git commit -m "feat(economy): pure ProgressionModel (XP<->level), lune-tested"
```

---

### Task 3: RewardModel (pure)

**Files:**
- Create: `src/shared/RewardModel.luau`
- Test: `tests/reward_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/reward_model.spec.luau`:

```lua
local RewardModel = require("../src/shared/RewardModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local OPTS = {
	xpBase = 25, xpPerSwap = 5, xpWin = 100,
	coinsBase = 15, coinsPerSwap = 4, coinsWin = 40,
}

-- Participation only (0 swaps, not winner): base coins + base xp.
do
	local r = RewardModel.rewardFor({ survivedSwaps = 0, isWinner = false, participated = true }, OPTS)
	expect(r.xp == 25, "base xp, got " .. tostring(r.xp))
	expect(r.coins == 15, "base coins, got " .. tostring(r.coins))
	print("reward: participation-only OK")
end

-- Per-swap scaling (3 swaps, not winner).
do
	local r = RewardModel.rewardFor({ survivedSwaps = 3, isWinner = false, participated = true }, OPTS)
	expect(r.xp == 25 + 15, "xp 25+5*3, got " .. tostring(r.xp))
	expect(r.coins == 15 + 12, "coins 15+4*3, got " .. tostring(r.coins))
	print("reward: per-swap OK")
end

-- Winner bonus on top of swaps (5 swaps + win).
do
	local r = RewardModel.rewardFor({ survivedSwaps = 5, isWinner = true, participated = true }, OPTS)
	expect(r.xp == 25 + 25 + 100, "xp 25+25+100, got " .. tostring(r.xp))
	expect(r.coins == 15 + 20 + 40, "coins 15+20+40, got " .. tostring(r.coins))
	print("reward: winner-bonus OK")
end

-- Non-participant earns nothing.
do
	local r = RewardModel.rewardFor({ survivedSwaps = 9, isWinner = false, participated = false }, OPTS)
	expect(r.xp == 0 and r.coins == 0, "non-participant earns 0")
	print("reward: non-participant OK")
end

-- Defensive: negative/nil survivedSwaps clamps to 0.
do
	local r = RewardModel.rewardFor({ survivedSwaps = -4, isWinner = false, participated = true }, OPTS)
	expect(r.xp == 25 and r.coins == 15, "negative swaps clamp to base")
	print("reward: negative-clamp OK")
end

print("ALL RewardModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/reward_model.spec.luau`
Expected: FAIL (cannot require `RewardModel`).

- [ ] **Step 3: Write the implementation**

Create `src/shared/RewardModel.luau`:

```lua
--[[
	RewardModel -- PURE per-round reward math. Roblox-free, no clocks/RNG.
	ctx  = { survivedSwaps, isWinner, participated }
	opts = { xpBase, xpPerSwap, xpWin, coinsBase, coinsPerSwap, coinsWin }
	Returns { coins, xp }. Survival-depth model: longer survival (more swaps lived
	through) earns more, with a flat participation base and a winner bonus.
	Location (Roblox): ReplicatedStorage/Shared/RewardModel  (ModuleScript)
--]]

local RewardModel = {}

function RewardModel.rewardFor(ctx, opts)
	if not ctx.participated then
		return { coins = 0, xp = 0 }
	end
	local swaps = math.max(0, ctx.survivedSwaps or 0)
	local xp = opts.xpBase + opts.xpPerSwap * swaps
	local coins = opts.coinsBase + opts.coinsPerSwap * swaps
	if ctx.isWinner then
		xp += opts.xpWin
		coins += opts.coinsWin
	end
	return { coins = coins, xp = xp }
end

return RewardModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/reward_model.spec.luau`
Expected: `ALL RewardModel TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add src/shared/RewardModel.luau tests/reward_model.spec.luau
git commit -m "feat(economy): pure RewardModel (survival-depth rewards), lune-tested"
```

---

### Task 4: ProfileModel (pure)

**Files:**
- Create: `src/shared/ProfileModel.luau`
- Test: `tests/profile_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/profile_model.spec.luau`:

```lua
local ProfileModel = require("../src/shared/ProfileModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local V = 1

-- default() is a fresh zeroed profile stamped with the version.
do
	local p = ProfileModel.default(V)
	expect(p.version == 1 and p.coins == 0 and p.totalXp == 0, "default profile zeroed @ v1")
	print("profile: default OK")
end

-- sanitize(nil) -> default.
do
	local p = ProfileModel.sanitize(nil, V)
	expect(p.version == 1 and p.coins == 0 and p.totalXp == 0, "nil -> default")
	print("profile: sanitize-nil OK")
end

-- sanitize a full valid blob preserves values, restamps version.
do
	local p = ProfileModel.sanitize({ version = 0, coins = 230, totalXp = 1450 }, V)
	expect(p.coins == 230 and p.totalXp == 1450, "values preserved")
	expect(p.version == 1, "version restamped to current")
	print("profile: sanitize-valid OK")
end

-- Partial blob fills missing fields with 0.
do
	local p = ProfileModel.sanitize({ coins = 50 }, V)
	expect(p.coins == 50 and p.totalXp == 0, "missing totalXp -> 0")
	print("profile: sanitize-partial OK")
end

-- Corrupt / wrong-type / negative values coerce to non-negative ints.
do
	local p = ProfileModel.sanitize({ coins = -10, totalXp = "garbage" }, V)
	expect(p.coins == 0, "negative coins clamp to 0, got " .. tostring(p.coins))
	expect(p.totalXp == 0, "string totalXp -> 0")
	local q = ProfileModel.sanitize({ coins = 12.9, totalXp = 7.2 }, V)
	expect(q.coins == 12 and q.totalXp == 7, "floats floored")
	local r = ProfileModel.sanitize("not a table", V)
	expect(r.coins == 0 and r.totalXp == 0, "non-table -> default")
	print("profile: sanitize-corrupt OK")
end

print("ALL ProfileModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/profile_model.spec.luau`
Expected: FAIL (cannot require `ProfileModel`).

- [ ] **Step 3: Write the implementation**

Create `src/shared/ProfileModel.luau`:

```lua
--[[
	ProfileModel -- PURE profile shape + sanitation. Roblox-free. The persisted
	blob is { version, coins, totalXp }; level is derived from totalXp at read time
	(ProgressionModel), never stored. sanitize() coerces ANY loaded DataStore value
	(nil / partial / corrupt / old-version) into a valid current-version profile, so
	the ProfileStore wrapper stays dumb. `version` is injected (Config.PROFILE_VERSION).
	Location (Roblox): ReplicatedStorage/Shared/ProfileModel  (ModuleScript)
--]]

local ProfileModel = {}

-- Non-negative integer, or nil if v isn't a usable number.
local function toCount(v)
	if type(v) ~= "number" or v ~= v then -- reject non-numbers and NaN
		return nil
	end
	return math.max(0, math.floor(v))
end

function ProfileModel.default(version)
	return { version = version, coins = 0, totalXp = 0 }
end

function ProfileModel.sanitize(blob, version)
	local profile = ProfileModel.default(version)
	if type(blob) == "table" then
		profile.coins = toCount(blob.coins) or 0
		profile.totalXp = toCount(blob.totalXp) or 0
	end
	return profile
end

return ProfileModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/profile_model.spec.luau`
Expected: `ALL ProfileModel TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add src/shared/ProfileModel.luau tests/profile_model.spec.luau
git commit -m "feat(economy): pure ProfileModel (shape + sanitize), lune-tested"
```

---

### Task 5: RewardScreenModel (pure)

**Files:**
- Create: `src/shared/RewardScreenModel.luau`
- Test: `tests/reward_screen_model.spec.luau`

- [ ] **Step 1: Write the failing test**

Create `tests/reward_screen_model.spec.luau`:

```lua
local RewardScreenModel = require("../src/shared/RewardScreenModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

-- No grant -> panel hidden.
do
	local d = RewardScreenModel.display(nil, { level = 5, progress = 0.2 })
	expect(d.visible == false, "no grant hides panel")
	print("reward-screen: hidden OK")
end

-- A normal grant renders +Coins / +XP and a plain level line.
do
	local d = RewardScreenModel.display(
		{ coins = 27, xp = 40, leveledUp = false },
		{ level = 6, progress = 0.5 }
	)
	expect(d.visible == true, "grant shows panel")
	expect(d.coinsText == "+27 Coins", "got " .. tostring(d.coinsText))
	expect(d.xpText == "+40 XP", "got " .. tostring(d.xpText))
	expect(d.levelText == "Level 6", "got " .. tostring(d.levelText))
	expect(d.levelBarProgress == 0.5, "progress passed through")
	expect(d.leveledUp == false, "no level-up flag")
	print("reward-screen: grant OK")
end

-- A level-up grant calls it out.
do
	local d = RewardScreenModel.display(
		{ coins = 95, xp = 150, leveledUp = true },
		{ level = 7, progress = 0.1 }
	)
	expect(d.leveledUp == true, "level-up flagged")
	expect(d.levelText == "Level Up!  7", "got " .. tostring(d.levelText))
	print("reward-screen: level-up OK")
end

print("ALL RewardScreenModel TESTS PASSED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/reward_screen_model.spec.luau`
Expected: FAIL (cannot require `RewardScreenModel`).

- [ ] **Step 3: Write the implementation**

Create `src/shared/RewardScreenModel.luau`:

```lua
--[[
	RewardScreenModel -- PURE display decision for the end-of-round reward panel.
	Roblox-free; mirrors RoundScreenModel. The renderer (ClientEconomyHud) maps these
	strings/values to GUI. `grant` is the per-round delta from RewardGranted
	({ coins, xp, leveledUp }) or nil; `profileView` is the post-award totals from
	ProfileUpdated ({ level, progress, ... }).
	Location (Roblox): ReplicatedStorage/Shared/RewardScreenModel  (ModuleScript)
--]]

local RewardScreenModel = {}

function RewardScreenModel.display(grant, profileView)
	if grant == nil then
		return { visible = false }
	end
	local levelText
	if grant.leveledUp then
		levelText = "Level Up!  " .. tostring(profileView.level)
	else
		levelText = "Level " .. tostring(profileView.level)
	end
	return {
		visible = true,
		coinsText = "+" .. tostring(grant.coins) .. " Coins",
		xpText = "+" .. tostring(grant.xp) .. " XP",
		levelText = levelText,
		levelBarProgress = profileView.progress,
		leveledUp = grant.leveledUp == true,
	}
end

return RewardScreenModel
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/reward_screen_model.spec.luau`
Expected: `ALL RewardScreenModel TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add src/shared/RewardScreenModel.luau tests/reward_screen_model.spec.luau
git commit -m "feat(economy): pure RewardScreenModel (reward-panel display), lune-tested"
```

---

### Task 6: Register the two new remotes

**Files:**
- Modify: `src/shared/Remotes.luau:17-18`

- [ ] **Step 1: Add the remote names**

Replace the `REMOTE_EVENTS` list:

```lua
local REMOTE_EVENTS =
	{ "SetControlledBody", "RoundStateChanged", "EliminationEvent", "SpectateBody", "SwapPreview", "SoulMap" }
```

with:

```lua
local REMOTE_EVENTS = {
	"SetControlledBody", "RoundStateChanged", "EliminationEvent", "SpectateBody", "SwapPreview", "SoulMap",
	"RewardGranted",  -- server->client: per-round reward delta { coins, xp, leveledUp }
	"ProfileUpdated", -- server->client: authoritative HUD state { coins, level, xpIntoLevel, xpForNext, progress }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/shared/Remotes.luau
git commit -m "feat(economy): register RewardGranted + ProfileUpdated remotes"
```

---

### Task 7: ProfileStore (server DataStore wrapper)

**Files:**
- Create: `src/server/ProfileStore.luau`

No lune test (touches `DataStoreService`); verified by the smoke test in Task 12. Keep it thin — all shape decisions delegate to the lune-tested `ProfileModel`.

- [ ] **Step 1: Write the implementation**

Create `src/server/ProfileStore.luau`:

```lua
--[[
	ProfileStore (server) -- thin DataStoreService wrapper. load() retries with
	backoff and, on total failure, returns (default, ok=false) so the caller refuses
	to save (no clobber). save() uses UpdateAsync (read-modify-write, never SetAsync)
	and retries. All shape/sanitation logic lives in the pure ProfileModel.
	Location (Roblox): ServerScriptService/Server/ProfileStore  (ModuleScript)
--]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileModel = require(ReplicatedStorage.Shared.ProfileModel)

local ProfileStore = {}
local store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)

local function keyFor(userId)
	return "player_" .. tostring(userId)
end

-- Returns (profile, ok). ok=false means the load failed every attempt: a default
-- profile is returned for play this session, but the caller must NOT save it.
function ProfileStore.load(userId)
	local key = keyFor(userId)
	for attempt = 1, Config.ECONOMY_LOAD_RETRIES do
		local success, result = pcall(function()
			return store:GetAsync(key)
		end)
		if success then
			return ProfileModel.sanitize(result, Config.PROFILE_VERSION), true
		end
		task.wait(Config.ECONOMY_RETRY_BACKOFF * attempt)
	end
	return ProfileModel.default(Config.PROFILE_VERSION), false
end

-- Returns ok. UpdateAsync transform returns the sanitized session profile (the
-- in-memory profile is authoritative in this single-server MVP; last write wins).
function ProfileStore.save(userId, profile)
	local key = keyFor(userId)
	local clean = ProfileModel.sanitize(profile, Config.PROFILE_VERSION)
	for attempt = 1, Config.ECONOMY_SAVE_RETRIES do
		local success = pcall(function()
			store:UpdateAsync(key, function()
				return clean
			end)
		end)
		if success then
			return true
		end
		task.wait(Config.ECONOMY_RETRY_BACKOFF * attempt)
	end
	warn(string.format("[BSR] economy: save failed for UserId %s", tostring(userId)))
	return false
end

return ProfileStore
```

- [ ] **Step 2: Commit**

```bash
git add src/server/ProfileStore.luau
git commit -m "feat(economy): ProfileStore DataStore wrapper (retry + no-clobber)"
```

---

### Task 8: EconomyService (server session cache + award)

**Files:**
- Create: `src/server/EconomyService.luau`

No lune test (Roblox services); verified by the smoke test in Task 12.

- [ ] **Step 1: Write the implementation**

Create `src/server/EconomyService.luau`:

```lua
--[[
	EconomyService (server) -- owns the in-memory authoritative profile cache (the
	session source of truth) and the persisted flag. Loads on join, saves on leave /
	autosave / BindToClose, and awards each round via the pure RewardModel +
	ProgressionModel. Pushes ProfileUpdated (HUD totals) + RewardGranted (per-round
	delta) to the owning client. A profile whose load failed is flagged persisted=false
	and never saved (no clobber).
	Location (Roblox): ServerScriptService/Server/EconomyService  (ModuleScript)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RewardModel = require(ReplicatedStorage.Shared.RewardModel)
local ProgressionModel = require(ReplicatedStorage.Shared.ProgressionModel)
local ProfileStore = require(script.Parent.ProfileStore)

local ProfileUpdated = Remotes.get("ProfileUpdated")
local RewardGranted = Remotes.get("RewardGranted")

local EconomyService = {}

local profiles = {}  -- [player] = { version, coins, totalXp }
local persisted = {} -- [player] = bool (false => load failed: never save)

local function progressionOpts()
	return {
		coeff = Config.PROGRESSION_XP_COEFF,
		exp = Config.PROGRESSION_XP_EXP,
		maxLevel = Config.PROGRESSION_MAX_LEVEL,
	}
end

local function rewardOpts()
	return {
		xpBase = Config.REWARD_XP_BASE,
		xpPerSwap = Config.REWARD_XP_PER_SWAP,
		xpWin = Config.REWARD_XP_WIN,
		coinsBase = Config.REWARD_COINS_BASE,
		coinsPerSwap = Config.REWARD_COINS_PER_SWAP,
		coinsWin = Config.REWARD_COINS_WIN,
	}
end

local function viewOf(profile)
	local lv = ProgressionModel.levelFor(profile.totalXp, progressionOpts())
	return {
		coins = profile.coins,
		level = lv.level,
		xpIntoLevel = lv.xpIntoLevel,
		xpForNext = lv.xpForNext,
		progress = lv.progress,
	}
end

local function pushProfile(player)
	local profile = profiles[player]
	if profile then
		ProfileUpdated:FireClient(player, viewOf(profile))
	end
end

local function save(player)
	local profile = profiles[player]
	if profile and persisted[player] then
		ProfileStore.save(player.UserId, profile)
	end
end

function EconomyService.getProfile(player)
	return profiles[player]
end

function EconomyService.onPlayerAdded(player)
	local profile, ok = ProfileStore.load(player.UserId)
	profiles[player] = profile
	persisted[player] = ok
	pushProfile(player)
	if not ok then
		warn(string.format(
			"[BSR] economy: load failed for %s (UserId %d); this session will NOT be saved",
			player.Name, player.UserId))
	end
end

function EconomyService.onPlayerRemoving(player)
	save(player)
	profiles[player] = nil
	persisted[player] = nil
end

-- Award one round to one player. ctx = { survivedSwaps, isWinner, participated }.
-- Mutates the cached profile and fires RewardGranted (delta) + ProfileUpdated (totals).
function EconomyService.awardRound(player, ctx)
	local profile = profiles[player]
	if not profile then
		return -- player left mid-round (profile already saved + dropped)
	end
	local before = ProgressionModel.levelFor(profile.totalXp, progressionOpts()).level
	local reward = RewardModel.rewardFor(ctx, rewardOpts())
	profile.coins += reward.coins
	profile.totalXp += reward.xp
	local after = ProgressionModel.levelFor(profile.totalXp, progressionOpts()).level
	RewardGranted:FireClient(player, {
		coins = reward.coins,
		xp = reward.xp,
		leveledUp = after > before,
	})
	pushProfile(player)
end

function EconomyService.start()
	-- Periodic background autosave for everyone in the server.
	task.spawn(function()
		while true do
			task.wait(Config.ECONOMY_AUTOSAVE_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				save(player)
			end
		end
	end)
	-- Flush all cached profiles on shutdown (within Roblox's BindToClose budget).
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			save(player)
		end
	end)
end

return EconomyService
```

- [ ] **Step 2: Commit**

```bash
git add src/server/EconomyService.luau
git commit -m "feat(economy): EconomyService session cache + round award + persistence"
```

---

### Task 9: RoundManager integration (survivedSwaps + award at endRound)

**Files:**
- Modify: `src/server/RoundManager.luau` (require, round-scoped state, beginRound, runActivePhase, endRound)

- [ ] **Step 1: Require EconomyService**

After the existing `local LobbyArea = require(script.Parent.LobbyArea)` line (~line 32), add:

```lua
local EconomyService = require(script.Parent.EconomyService)
```

- [ ] **Step 2: Add round-scoped economy state**

After the cadence-state block (the `local cadenceStartCount = 0` / `local swapsSoFar = 0` lines, ~line 52), add:

```lua
-- Economy: per-player swaps-survived counter (a placement proxy) + the round's
-- participant set, so endRound can award everyone who played. `awarded` guards
-- against double-paying a single round-end. All reset in beginRound.
local survivedSwaps = {}     -- [player] = int
local roundParticipants = {} -- [player] = true
local awarded = false
```

- [ ] **Step 3: Initialize the economy state in beginRound**

In `beginRound`, the first line is currently:

```lua
	RoundState.beginRound(model, eligibleSet()) -- Lobby -> Active; only valid-bodied present players become alive
```

Replace it with (capture the eligible set so participants = the alive-at-start roster):

```lua
	local eligible = eligibleSet()
	RoundState.beginRound(model, eligible) -- Lobby -> Active; only valid-bodied present players become alive
	-- Economy: snapshot participants + zero their swaps-survived for this round.
	survivedSwaps = {}
	roundParticipants = {}
	for player in pairs(eligible) do
		roundParticipants[player] = true
		survivedSwaps[player] = 0
	end
	awarded = false
```

- [ ] **Step 4: Increment survivedSwaps on each committed swap**

In `runActivePhase`, the commit block at T0 currently reads:

```lua
		-- Commit at T0.
		if plan then
			commitSwap(plan)
			swapsSoFar += 1 -- advances the cadence progress term (counts planned swaps; a
			-- late roster-collapse abort inside commitSwap is benign -- the round is ending)
		end
```

Replace it with:

```lua
		-- Commit at T0.
		if plan then
			commitSwap(plan)
			swapsSoFar += 1 -- advances the cadence progress term (counts planned swaps; a
			-- late roster-collapse abort inside commitSwap is benign -- the round is ending)
			-- Economy: every participant still alive just survived this swap.
			for player in pairs(roundParticipants) do
				if RoundState.isAlive(model, player) then
					survivedSwaps[player] = (survivedSwaps[player] or 0) + 1
				end
			end
		end
```

- [ ] **Step 5: Award rewards in endRound**

In `endRound`, just after the winner is read:

```lua
	local winner = RoundState.getWinner(model)
	print("[BSR] round ended; winner:", winner and winner.Name or "(none)")
```

insert the award block right after that `print`:

```lua
	-- Economy: award every participant exactly once for this round (survival-depth).
	if not awarded then
		awarded = true
		for player in pairs(roundParticipants) do
			EconomyService.awardRound(player, {
				survivedSwaps = survivedSwaps[player] or 0,
				isWinner = player == winner,
				participated = true,
			})
		end
	end
```

- [ ] **Step 6: Verify the existing round-state tests still pass**

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/round_state.spec.luau`
Expected: `ALL ... TESTS PASSED` (RoundManager isn't lune-tested, but RoundState is its pure core; this confirms no regression to the logic it drives).

- [ ] **Step 7: Commit**

```bash
git add src/server/RoundManager.luau
git commit -m "feat(economy): track survivedSwaps + award participants at round end"
```

---

### Task 10: Wire EconomyService into the server bootstrap

**Files:**
- Modify: `src/server/init.server.luau`

- [ ] **Step 1: Require + start EconomyService and hook join/leave**

Replace the body below the header comment with:

```lua
local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local RoundManager = require(script.RoundManager)
local EconomyService = require(script.EconomyService)

local function onPlayerAdded(player)
	EconomyService.onPlayerAdded(player) -- load/cache the profile + push it to the client
	RoundManager.addPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	RoundManager.removePlayer(player)
	EconomyService.onPlayerRemoving(player) -- save + drop AFTER the round handles the leave
end)

EconomyService.start() -- autosave loop + BindToClose flush
RoundManager.start()
print("[BSR] Server ready (ownership-transfer model + round loop + economy).")
```

- [ ] **Step 2: Commit**

```bash
git add src/server/init.server.luau
git commit -m "feat(economy): wire EconomyService into server bootstrap"
```

---

### Task 11: ClientEconomyHud (reward panel + persistent balance)

**Files:**
- Create: `src/client/ClientEconomyHud.luau`
- Modify: `src/client/init.client.luau`

No lune test (Roblox GUI); verified visually via Studio MCP + the smoke test. Uses `HudTheme` helpers (`makePanel`, `styleText`, `setPanelFlat`, `setPanelAccent`, `popIn`, `Color`, `DisplayOrder`) exactly as `ClientRoundHud` does.

- [ ] **Step 1: Write the implementation**

Create `src/client/ClientEconomyHud.luau`:

```lua
--[[
	ClientEconomyHud -- renders the economy UI: a persistent top-left Coins/Level
	readout (from ProfileUpdated) and the end-of-round reward panel (from
	RewardGranted + the latest ProfileUpdated). WHAT to show in the panel is the pure
	RewardScreenModel's decision; this module only renders (HudTheme skin). The panel
	auto-hides shortly after it appears (the Ended window is brief).
	Location: StarterPlayerScripts/Client/ClientEconomyHud  (ModuleScript)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardScreenModel = require(Shared:WaitForChild("RewardScreenModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local RewardGranted = Remotes.get("RewardGranted")
local ProfileUpdated = Remotes.get("ProfileUpdated")

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

local ClientEconomyHud = {}
local player = Players.LocalPlayer

-- Latest authoritative HUD view from ProfileUpdated; the reward panel reads level
-- + progress from it, the persistent readout reads coins + level.
local lastView = { coins = 0, level = 1, progress = 0 }

local balanceCoins, balanceLevel       -- persistent readout labels
local rewardRoot, rewardCoins, rewardXp, rewardLevel, rewardBarFill -- reward panel
local PANEL_VISIBLE_SECONDS = 4.5
local hideToken = nil

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EconomyHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = HudTheme.DisplayOrder.bookend -- same layer as the results banner
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ===== Persistent Coins/Level readout (top-left) =====
	local handle = HudTheme.makePanel(gui, UDim2.fromScale(0.16, 0.07), "top", nil)
	HudTheme.setPanelFlat(handle, HudTheme.Color.panelDark)
	handle.root.AnchorPoint = Vector2.new(0, 0)
	handle.root.Position = UDim2.new(0, 14, 0, 14)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = handle.panel

	balanceCoins = Instance.new("TextLabel")
	balanceCoins.Name = "Coins"
	balanceCoins.BackgroundTransparency = 1
	balanceCoins.Size = UDim2.fromScale(0.92, 0.55)
	balanceCoins.LayoutOrder = 1
	balanceCoins.Text = "0 Coins"
	HudTheme.styleText(balanceCoins, "heading")
	balanceCoins.Parent = handle.panel

	balanceLevel = Instance.new("TextLabel")
	balanceLevel.Name = "Level"
	balanceLevel.BackgroundTransparency = 1
	balanceLevel.Size = UDim2.fromScale(0.92, 0.40)
	balanceLevel.LayoutOrder = 2
	balanceLevel.Text = "Level 1"
	HudTheme.styleText(balanceLevel, "body")
	balanceLevel.Parent = handle.panel

	-- ===== End-of-round reward panel (center) =====
	local panel = HudTheme.makePanel(gui, UDim2.fromScale(0.34, 0.22), "center", nil)
	HudTheme.setPanelAccent(panel, "neutral")
	rewardRoot = panel.root
	rewardRoot.Visible = false

	local plist = Instance.new("UIListLayout")
	plist.FillDirection = Enum.FillDirection.Vertical
	plist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	plist.VerticalAlignment = Enum.VerticalAlignment.Center
	plist.SortOrder = Enum.SortOrder.LayoutOrder
	plist.Padding = UDim.new(0, 4)
	plist.Parent = panel.panel

	local function panelLine(name, scaleY, order, fontKey)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(0.92, scaleY)
		l.LayoutOrder = order
		l.Text = ""
		HudTheme.styleText(l, fontKey)
		l.Parent = panel.panel
		return l
	end

	rewardLevel = panelLine("RewardLevel", 0.26, 1, "title")
	rewardCoins = panelLine("RewardCoins", 0.22, 2, "heading")
	rewardXp = panelLine("RewardXp", 0.22, 3, "body")

	-- Thin level-bar track + fill at the bottom of the panel.
	local track = Instance.new("Frame")
	track.Name = "LevelBarTrack"
	track.Size = UDim2.fromScale(0.88, 0.12)
	track.LayoutOrder = 4
	track.BackgroundColor3 = HudTheme.Color.panelDark
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track
	track.Parent = panel.panel

	rewardBarFill = Instance.new("Frame")
	rewardBarFill.Name = "Fill"
	rewardBarFill.AnchorPoint = Vector2.new(0, 0.5)
	rewardBarFill.Position = UDim2.fromScale(0, 0.5)
	rewardBarFill.Size = UDim2.fromScale(0, 1)
	rewardBarFill.BackgroundColor3 = HudTheme.Accent.win.top
	rewardBarFill.BorderSizePixel = 0
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = rewardBarFill
	rewardBarFill.Parent = track
end

local function applyView(view)
	lastView = view
	balanceCoins.Text = string.format("%d Coins", view.coins)
	balanceLevel.Text = "Level " .. tostring(view.level)
end

local function showReward(grant)
	local d = RewardScreenModel.display(grant, lastView)
	if not d.visible then
		return
	end
	rewardLevel.Text = d.levelText
	rewardCoins.Text = d.coinsText
	rewardXp.Text = d.xpText
	rewardBarFill.Size = UDim2.fromScale(math.clamp(d.levelBarProgress or 0, 0, 1), 1)
	HudTheme.setPanelAccent(rewardLevel.Parent.Parent, d.leveledUp and "win" or "neutral")
	rewardRoot.Visible = true
	HudTheme.popIn(rewardRoot)

	-- Auto-hide after a few seconds; a newer reward cancels the previous timer.
	local token = {}
	hideToken = token
	task.delay(PANEL_VISIBLE_SECONDS, function()
		if hideToken == token then
			rewardRoot.Visible = false
		end
	end)
end

function ClientEconomyHud.start()
	build()
	ProfileUpdated.OnClientEvent:Connect(applyView)
	RewardGranted.OnClientEvent:Connect(showReward)
end

return ClientEconomyHud
```

- [ ] **Step 2: Start it from the client bootstrap**

In `src/client/init.client.luau`, add the require alongside the others (after the `LobbyStage` require):

```lua
local ClientEconomyHud = require(script.ClientEconomyHud)
```

and add its start call after `LobbyStage.start()`:

```lua
ClientEconomyHud.start()
```

- [ ] **Step 3: Commit**

```bash
git add src/client/ClientEconomyHud.luau src/client/init.client.luau
git commit -m "feat(economy): ClientEconomyHud (reward panel + persistent balance)"
```

---

### Task 12: Smoke-test doc

**Files:**
- Create: `docs/smoke-tests/2026-06-30-economy-persistence-smoke-test.md`

- [ ] **Step 1: Write the smoke-test procedure**

Create `docs/smoke-tests/2026-06-30-economy-persistence-smoke-test.md`:

```markdown
# Economy & Persistence — 2-Client Smoke Test (2026-06-30)

Covers the server/client glue that lune can't: `EconomyService`, `ProfileStore`
(DataStore), the `RoundManager` award seam, and `ClientEconomyHud`. Pure logic
(`RewardModel`/`ProgressionModel`/`ProfileModel`/`RewardScreenModel`) is lune-green.

**Setup:** Studio, 2 players (Play Solo gives 1; use Team Test / Start Server with 2
clients). DataStore API access must be enabled for the place
(Game Settings → Security → Enable Studio Access to API Services).

## Checks

1. **Persistent readout on join.** Each client shows a top-left "N Coins / Level L"
   readout immediately after spawn (from `ProfileUpdated`). A brand-new test player
   reads "0 Coins / Level 1".
2. **Earn on round end.** Play a full round to a winner. Both clients see the centered
   reward panel: `+Coins`, `+XP`, a level line, and a filled level bar. The top-left
   Coins total increases by exactly the panel's `+Coins`.
3. **Survival-depth gradient.** The winner's `+Coins`/`+XP` exceeds an early
   casualty's (more swaps survived → more reward). Force quick swaps with
   `RoundManager.forceSwap()` in the command bar to build up `survivedSwaps` if needed.
4. **Level-up callout.** Accumulate XP across rounds (or temporarily lower
   `Config.PROGRESSION_XP_COEFF`) until a level threshold is crossed; the reward panel
   reads "Level Up!  N" and the bar resets low.
5. **Persistence across rejoin.** Note a client's Coins total, leave, rejoin → the
   total is restored (saved on `PlayerRemoving`).
6. **No-clobber on failed load.** Temporarily point `Config.DATASTORE_NAME` at a
   throwaway name OR simulate a load failure; confirm the session still plays/earns,
   the console logs "load failed … will NOT be saved", and the real saved value is
   untouched after the session ends. Restore `DATASTORE_NAME` afterward.
7. **Shutdown flush.** Earn coins, then stop the server (don't leave first); rejoin a
   fresh server → the earnings persisted (BindToClose flushed).

## Notes
- Rojo sync can go stale — confirm the place has the latest code (`script_read`) before
  trusting an MCP visual check.
- The reward panel auto-hides after a few seconds (`PANEL_VISIBLE_SECONDS`).
```

- [ ] **Step 2: Commit**

```bash
git add docs/smoke-tests/2026-06-30-economy-persistence-smoke-test.md
git commit -m "docs(smoke): economy & persistence 2-client smoke test"
```

---

### Task 13: Update the TDD roadmap status

**Files:**
- Modify: `docs/body-swap-royale-tdd.md` (§1 component table line ~98; §10 MVP checklist line ~647)

- [ ] **Step 1: Flip EconomyService to done in the §1 component table**

Find the table row (~line 98):

```
| EconomyService | Awards XP and currency on server side only | ⚪ |
```

Replace with:

```
| EconomyService | Awards XP and currency on server side only | 🟢 `EconomyService.luau` + `ProfileStore.luau`; pure `RewardModel`/`ProgressionModel`/`ProfileModel`/`RewardScreenModel` |
```

- [ ] **Step 2: Tick the MVP DataStore item**

Find (~line 647):

```
- [ ] ⚪ DataStore for player level and coins
```

Replace with:

```
- [x] 🟢 DataStore for player level and coins — *`ProfileStore` (UpdateAsync, retry, no-clobber-on-failed-load) + `EconomyService` session cache; survival-depth Coins/XP/Level awarded at round end; reward panel + persistent HUD balance*
```

- [ ] **Step 3: Note the closed DoD in the gap callout**

Find the gap note (~line 652):

```
> **Gap to DoD:** death/elimination, grace, win declaration, currency, and a RoundManager to sequence the round are all still required. The swap, control, animation, and camera layers are in place.
```

Replace with:

```
> **DoD status (2026-06-30):** death/elimination, grace, win declaration, the RoundManager, and now **currency** (Coins/XP/Level + DataStore persistence) are all in place — the MVP Definition-of-Done sentence ("…and earn currency") is met. Remaining MVP-scope polish: swap preview, Control Signature visuals, movement validation, lobby matchmaking, and basic menu/results UI.
```

- [ ] **Step 4: Commit**

```bash
git add docs/body-swap-royale-tdd.md
git commit -m "docs(tdd): mark DataStore/EconomyService done — MVP DoD currency item closed"
```

---

## Self-Review

**Spec coverage:**
- Coins+XP+Level → Tasks 2,3,8 (RewardModel/ProgressionModel + award). ✔
- Survival-depth formula + survivedSwaps counter → Tasks 3,9. ✔
- Robust-enough persistence (versioned store, retry, no-clobber, UpdateAsync, autosave, BindToClose) → Tasks 7,8. ✔
- Reward panel + persistent balance → Tasks 5,11. ✔
- Two remotes → Task 6. ✔
- Config block → Task 1. ✔
- Lune tests for all 4 pure modules → Tasks 2-5. ✔
- Smoke-test doc → Task 12. ✔
- TDD status updates / DoD closure → Task 13. ✔

**Type/name consistency:** `RewardModel.rewardFor(ctx, opts)`, `ProgressionModel.xpForLevel(level, opts)` / `levelFor(totalXp, opts)`, `ProfileModel.default(version)` / `sanitize(blob, version)`, `RewardScreenModel.display(grant, profileView)`, `EconomyService.onPlayerAdded/onPlayerRemoving/awardRound/getProfile/start`, `ProfileStore.load/save` — used consistently across tasks. Remote payloads: `ProfileUpdated` = `{ coins, level, xpIntoLevel, xpForNext, progress }`; `RewardGranted` = `{ coins, xp, leveledUp }` — produced in Task 8, consumed in Task 11. ✔

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows complete code. ✔
```
