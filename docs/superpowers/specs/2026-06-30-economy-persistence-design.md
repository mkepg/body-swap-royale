# Economy & Persistence — Design Spec

**Date:** 2026-06-30
**Status:** Approved (brainstorm complete)
**Closes:** TDD §10 MVP Definition-of-Done — the last sentence-completing item, "…and earn currency."

## Goal

Make the round loop reward players with persistent **Coins**, **XP**, and **Levels**.
Two friends can play a round, see per-round rewards on the results screen, watch a
running balance on the HUD, and have that balance survive a rejoin. This completes the
MVP DoD sentence: *"Two friends can join the game, play a round with random swaps,
orient safely after each swap, see a winner declared, and earn currency."*

Everything else in that sentence (join, round, swaps, orient, winner declared) is
already built; only "earn currency" is missing.

## Scope (locked by brainstorm)

**In scope:**
- Coins + XP + Level (one vertical slice).
- Survival-depth reward formula (swaps survived as a placement proxy), no
  elimination-ordering machinery.
- "Robust-enough MVP" DataStore persistence: versioned store, in-memory authoritative
  profile, retry/backoff load, no-clobber-on-failed-load guard, `UpdateAsync` saves on
  leave + `BindToClose` + periodic autosave. No cross-server session locking, no backup
  datastore (those are TDD §10 Beta line items).
- Reward panel on the Ended results screen **and** an always-on Coins/level HUD readout.

**Explicitly deferred (Alpha):** daily login rewards, achievements, cosmetic drops, the
shop, Robux purchases, premium Souls. The reward formula and profile shape leave room to
add these later without rework.

## Reward formula (survival-depth)

Per the GDD §8/§9 numbers, driven by a per-player `survivedSwaps` count and an
`isWinner` flag:

- **XP** = `25` (participation) + `5 × survivedSwaps` + `100` (if winner). Matches the
  GDD XP formula verbatim.
- **Coins** = `base` + `perSwap × survivedSwaps` + `winBonus` (if winner), tuned so a
  typical round lands in the GDD's ~20–100 range. Proposed defaults (in Config):
  `base = 15`, `perSwap = 4`, `winBonus = 40`.

`survivedSwaps` = the number of swap commits a player was still alive through this round.
The winner naturally has the highest count; an early casualty has the lowest. A player
who participated but the round ended on swap 0 still earns the participation base.

## Architecture & module boundaries

Honors the established pure-logic / server-glue split (pure modules are Roblox-free and
lune-tested; server/client glue gets a Studio MCP check + a manual smoke-test doc).

### Pure modules — `src/shared/` (lune-tested)

| Module | Responsibility | Key API |
|--------|----------------|---------|
| `RewardModel` | Per-round reward math from an injected context + tunables. No clocks/RNG. | `RewardModel.rewardFor(ctx, opts) -> { coins, xp }` where `ctx = { survivedSwaps, isWinner, participated }`, `opts` carries the Config tunables. |
| `ProgressionModel` | XP ↔ level math. | `ProgressionModel.xpForLevel(level) -> number` (`100 * level^1.4`, floored); `ProgressionModel.levelFor(totalXp) -> { level, xpIntoLevel, xpForNext, progress }`, clamped at `MAX_LEVEL` (100). |
| `ProfileModel` | The profile shape + sanitation of any loaded DataStore value. | `ProfileModel.default() -> profile`; `ProfileModel.sanitize(blob) -> profile` (nil / partial / corrupt / old-version → valid profile; clamps negatives, fills defaults, stamps the current `version`). |
| `RewardScreenModel` | Pure display decision for the reward panel (mirrors `RoundScreenModel`). | `RewardScreenModel.display(payload, profileView) -> { visible, coinsText, xpText, levelText, levelBarProgress, leveledUp, ... }`. |

Profile shape (the persisted blob): `{ version = 1, coins = <int>, totalXp = <int> }`.
Level is **derived** from `totalXp` via `ProgressionModel` (not stored), so the level
formula can change without a migration.

### Server glue — `src/server/` (MCP + smoke-tested)

| Module | Responsibility |
|--------|----------------|
| `ProfileStore` | Thin `DataStoreService` wrapper. `load(userId) -> profile, ok` (pcall + bounded retry/backoff; on total failure returns a default profile with `ok = false`). `save(userId, profile) -> ok` via **`UpdateAsync`** (read-modify-write; never `SetAsync`). Uses `ProfileModel.sanitize` on the loaded value. |
| `EconomyService` | Owns the in-memory authoritative `profiles[player]` cache (the session source of truth) and the `persisted[player]` flag. API: `onPlayerAdded(player)` (load → cache → push `ProfileUpdated`), `onPlayerRemoving(player)` (save if persisted → drop), `awardRound(player, ctx)` (compute via `RewardModel`, mutate the cached profile, recompute level, fire `RewardGranted` + `ProfileUpdated`), `getProfile(player)`. Runs an autosave loop (`ECONOMY_AUTOSAVE_SECONDS`) and a `BindToClose` flush. |

### Client glue — `src/client/`

| Module | Responsibility |
|--------|----------------|
| `ClientEconomyHud` | Renders (a) an always-on Coins + level readout, and (b) the Ended-window reward panel, both via `RewardScreenModel` + `HudTheme`. Listens to `ProfileUpdated` (totals → balance + level bar) and `RewardGranted` (deltas → reward panel). New module so `ClientRoundHud` stays focused on the banner. |

### Wiring points (existing files touched)

- `src/shared/Remotes.luau` — add `"RewardGranted"` and `"ProfileUpdated"` to the
  `REMOTE_EVENTS` list.
- `src/shared/Config.luau` — add an economy tunables block (see below).
- `src/server/init.server.luau` — `require` and start `EconomyService`; call
  `EconomyService.onPlayerAdded/onPlayerRemoving` from the existing `PlayerAdded` /
  `PlayerRemoving` handlers (alongside `RoundManager`).
- `src/server/RoundManager.luau` — track `survivedSwaps` + the round participant set;
  call `EconomyService.awardRound` for each participant in `endRound`.
- `src/client/init.client.luau` — start `ClientEconomyHud`.

## Data flow

1. **Join** → `init.server` `PlayerAdded` → `EconomyService.onPlayerAdded` →
   `ProfileStore.load` (retry) → `ProfileModel.sanitize` → cache + set `persisted` →
   fire `ProfileUpdated` to that client → HUD shows balance.
2. **During Active** → `RoundManager` keeps `survivedSwaps[player]`, reset to 0 for each
   participant in `beginRound` (which also captures the `roundParticipants` set). Each
   time a swap **commits**, increment `survivedSwaps` for every player still alive.
3. **Round end** → in `endRound`, after the winner is known, for each player in
   `roundParticipants`: build `ctx = { survivedSwaps = survivedSwaps[p] or 0,
   isWinner = (p == winner), participated = true }` → `EconomyService.awardRound(p, ctx)`
   → `RewardModel.rewardFor` → mutate cached profile (`coins +=`, `totalXp +=`,
   recompute level) → fire `RewardGranted` (delta) + `ProfileUpdated` (new totals).
   Guarded so each round-end awards each participant exactly once.
4. **Client** → `RewardGranted` shows the reward panel during the Ended window;
   `ProfileUpdated` updates the persistent balance + the panel's level bar.
5. **Leave / shutdown** → `onPlayerRemoving` saves via `UpdateAsync` (if `persisted`);
   the autosave loop saves periodically; `BindToClose` flushes all cached profiles within
   the shutdown budget.

## Error handling (data-safety guardrails)

- **Failed load** → cache a default profile but set `persisted[player] = false`. The
  player can still play and earn *this session*, but **all saves are refused** for that
  player, so a transient DataStore outage can never overwrite real saved data with
  defaults. Logged.
- **Save** → `UpdateAsync` inside pcall + bounded retry/backoff; final failure is logged
  and the profile stays cached for the next autosave / `BindToClose` attempt.
- **Double-award guard** → `endRound` awards each participant exactly once per round (a
  per-round "awarded" flag), so a re-entrant or disconnect-driven end can't double-pay.
- **BindToClose** → iterate cached profiles, save each (skipping `persisted = false`),
  within Roblox's shutdown budget.

## Config additions

```lua
-- ===== Economy & Persistence =====
-- Reward formula (RewardModel). XP matches the GDD §9 formula verbatim;
-- coins are tuned to the GDD §8 ~20-100/round range via survival depth.
Config.REWARD_XP_BASE = 25          -- participation
Config.REWARD_XP_PER_SWAP = 5       -- per swap survived
Config.REWARD_XP_WIN = 100          -- winner bonus
Config.REWARD_COINS_BASE = 15       -- participation
Config.REWARD_COINS_PER_SWAP = 4    -- per swap survived
Config.REWARD_COINS_WIN = 40        -- winner bonus

-- Progression (ProgressionModel). level XP curve = COEFF * level ^ EXP.
Config.PROGRESSION_XP_COEFF = 100
Config.PROGRESSION_XP_EXP = 1.4
Config.PROGRESSION_MAX_LEVEL = 100

-- Persistence (ProfileStore / EconomyService).
Config.DATASTORE_NAME = "PlayerData_v1"
Config.PROFILE_VERSION = 1
Config.ECONOMY_LOAD_RETRIES = 4         -- attempts before giving up (then persisted=false)
Config.ECONOMY_RETRY_BACKOFF = 1.0      -- seconds, grows per attempt
Config.ECONOMY_AUTOSAVE_SECONDS = 120   -- periodic background save cadence
```

## Testing & verification

### Lune (pure modules) — `tests/*.spec.luau`

Following the existing harness (`require("../src/shared/<Module>")`, `expect`/`fail`):

- `tests/reward_model.spec.luau` — participation-only (0 swaps), per-swap scaling,
  winner bonus, winner + swaps combined, non-participant returns zero.
- `tests/progression_model.spec.luau` — `xpForLevel` monotonic increasing; `levelFor`
  boundaries (exact threshold, just-below, just-above), level-up across a threshold,
  clamp at `MAX_LEVEL`, `progress` in `[0,1)`.
- `tests/profile_model.spec.luau` — `default()` shape; `sanitize` of nil / partial /
  negative / wrong-type / old-version blobs all yield a valid current-version profile.
- `tests/reward_screen_model.spec.luau` — win vs participate text, level-up vs not,
  hidden when no payload, level-bar progress value.

Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`.

### Server/client glue — Studio MCP + manual smoke test

New `docs/smoke-tests/2026-06-30-economy-persistence-smoke-test.md` (2-client):
1. Play a full round; verify the Ended reward panel shows `+Coins` / `+XP` and the level
   bar, and the persistent HUD balance increases by the same delta.
2. Winner earns more than an early casualty (survival-depth gradient).
3. **Rejoin proves persistence:** leave, rejoin → balance is restored.
4. Level-up renders when a threshold is crossed.
5. No-clobber: with a key whose load is forced to fail, the session still plays/earns but
   never overwrites the real saved value (verify the real value survives).

## Definition of done

- Four pure modules implemented and lune-green.
- `EconomyService` + `ProfileStore` wired; rewards awarded at `endRound`; profile loads on
  join and saves on leave / autosave / shutdown.
- `ClientEconomyHud` shows the reward panel + persistent balance.
- Smoke-test doc written; a 2-client pass confirms earn + persist + level-up + no-clobber.
- TDD §10 MVP "DataStore for player level and coins" ticked; `EconomyService` flipped to
  🟢 in TDD §1; this is called out as closing the last MVP DoD item.

## Out of scope / future hooks

- Daily rewards, achievements, cosmetic drops, shop, Robux, premium Souls (Alpha).
- Cross-server session locking + backup datastore (Beta, TDD §10).
- The profile blob is versioned and `ProfileModel.sanitize` centralizes migration, so
  adding fields later (e.g. `cosmetics`, `dailyStreak`) is additive.
