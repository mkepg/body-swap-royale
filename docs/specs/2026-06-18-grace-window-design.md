# Post-Swap Grace Window — Design Spec

**Date:** 2026-06-18
**Status:** Approved (design); implementation pending
**Related:** [GDD §4 Post-Swap Grace Window](../../body-swap-royale-gdd.md#4-core-gameplay-mechanics), [TDD §2 Grace Window Logic](../../body-swap-royale-tdd.md#2-swap--grace-algorithms), [TDD §1 Systems](../../body-swap-royale-tdd.md#1-systems-architecture), [TDD §7 HasMovedSinceSwap](../../body-swap-royale-tdd.md#7-security-and-anti-cheat), [TDD §10 MVP Scope](../../body-swap-royale-tdd.md#10-development-roadmap). Builds on the shipped [RoundManager spine](2026-06-18-round-manager-design.md) and the pure modules `RoundState` / `ControlModel`.

## Purpose

The RoundManager spine gates the swap to the Active phase and drives a death → eliminate → winner path via a void monitor that calls `RoundManager.eliminate` the instant a controlled body's root crosses `VOID_Y`. With nothing between the death trigger and elimination, a player who inherits a body that is already falling (or sitting next to a hazard) can be eliminated before their first input — the single biggest source of "I lost and it wasn't my fault" (GDD §4, §11).

The **post-swap grace window** closes that gap: for a short window immediately after each swap, the inherited body cannot die from environmental hazards, giving the player a beat to orient. The window ends early once the player has actually started moving (they've oriented), with a hard floor that always protects briefly. This spec adds the grace gate between every hazard death trigger and `RoundManager.eliminate`, so the existing void monitor — and any future hazard — consults it before eliminating.

## Scope

**In scope:**
- A new pure, time-injected, lune-tested module `GraceModel` holding per-player grace state and the `CanDieFromHazard` decision (TDD §2).
- Thin glue in `RoundManager`: the real clock, stamping grace on each swap, deriving the `HasMovedSinceSwap` signal from observed horizontal position change, and a single reusable hazard-elimination gate the void monitor consults.
- One new `Config` tunable (`GRACE_MOVE_EPSILON`).
- A lune test for `GraceModel` and a grace scenario added to the Studio smoke test.

**Out of scope (later steps):**
- Any client-side grace visual (shield shimmer + Soul-aura pulse, GDD §4). Grace is server-authoritative and fully verifiable without a visual; the cue belongs with the Soul / SwapVFX work, which is not built.
- Telegraphed hazards beyond the void (disappearing tiles, sweeping beams, crushers). The gate is built to be reused by them, but none are added here.
- Swap preview/warning, the Soul system, the real HUD.
- Server-side movement validation (anti-cheat). The grace movement signal is the same observed-displacement signal anti-cheat will need, but this spec does not build validation.
- The proposed No-Doom Assignment Rule (GDD §12) — gated by a fairness playtest, not part of MVP grace.

## Design decisions (resolved during brainstorming)

1. **New pure `GraceModel` + thin glue.** The `CanDieFromHazard` predicate is a pure function of `(now, graceUntil, graceMinFloor, hasMoved)`. It lives in a pure, time-injected, lune-tested module — matching the established split where `RoundState` takes thresholds and `ControlModel` takes `randint`. Only the real clock, timestamps, and observed positions live in the glue. (Rejected: folding grace into `RoundState`, which would couple round lifecycle with per-body timers; and an all-inline glue table, which would leave the one piece of real branching logic outside unit testing.)
2. **`HasMovedSinceSwap` = horizontal (XZ) displacement only.** The server derives movement from observed position change (TDD §7), comparing the current root position to the swap-time position on the XZ plane. Pure falling / being pushed down does **not** count as "moved," matching the GDD's "does NOT block falling" — a body dropped into the void keeps its full grace window and won't early-exit just from falling.
3. **Stamp grace on swaps only.** Grace is stamped on the per-cycle swap (`isSwap = true`), matching the GDD ("after each swap"). Round-start `resetControl` does **not** stamp: everyone spawns on safe pads in their own body, so there is no inherited danger to orient around. The `GraceModel` "no entry → can die" rule makes this clean — before the first swap there is simply no grace entry.
4. **Server-only this step; defer the visual.** The authoritative gate ships with zero client visual. Surviving a void-drop during the window is the observable in the smoke test.
5. **One reusable hazard gate; disconnects bypass it.** A single `RoundManager.eliminateFromHazard(player)` consults grace and then calls `eliminate`. The void monitor (and any future hazard, or a `Humanoid.Died` hook) routes through it. Disconnect-driven elimination stays on the raw `eliminate` path — grace never saves a player from a disconnect, only from a hazard.

## Components

| Module | Change | Responsibility |
|--------|--------|----------------|
| **`GraceModel`** (`src/shared/GraceModel.luau`, new) | new | Pure, time-injected per-player grace state (`graceUntil`, `graceMinFloor`, `hasMoved`) and the `canDieFromHazard` predicate. Knows nothing about Roblox, clocks, or positions. Lune-tested. |
| `RoundManager` (`src/server/RoundManager.luau`) | + grace glue | Owns the clock (`os.clock()`), stamps grace on each swap, captures swap-time positions, samples horizontal displacement in the void monitor to drive `markMoved`, exposes `eliminateFromHazard` as the single hazard gate, clears grace on eliminate/disconnect. |
| `Config` (`src/shared/Config.luau`) | + `GRACE_MOVE_EPSILON` | New tunable. `GRACE_SECONDS` (1.5) and `GRACE_FLOOR_SECONDS` (0.5) already exist. |

No client, remote, `RoundState`, `ControlModel`, `ControlManager`, `SwapController`, or `BodyManager` changes.

## Pure module: `GraceModel`

State, keyed by player (same key convention as `RoundState` / `ControlModel`):

```
model.byPlayer[player] = { graceUntil = <number>, graceMinFloor = <number>, hasMoved = <bool> }
```

Operations (all `now` and thresholds are injected — the module never reads a clock):

```
function GraceModel.new()
    -- returns { byPlayer = {} }

function GraceModel.onSwap(model, player, now, graceSeconds, floorSeconds)
    -- model.byPlayer[player] = {
    --   graceUntil    = now + graceSeconds,
    --   graceMinFloor = now + floorSeconds,
    --   hasMoved      = false,
    -- }

function GraceModel.markMoved(model, player)
    -- if model.byPlayer[player] then model.byPlayer[player].hasMoved = true end
    -- (no-op when no entry exists)

function GraceModel.canDieFromHazard(model, player, now) -> boolean
    local g = model.byPlayer[player]
    if not g then return true end                      -- no grace active (e.g. round-start spawn)
    if now < g.graceMinFloor then return false end     -- hard floor: always protected briefly
    if now < g.graceUntil and not g.hasMoved then
        return false                                   -- still in grace, hasn't oriented yet
    end
    return true

function GraceModel.clear(model, player)
    -- model.byPlayer[player] = nil
```

The floor check is first and unconditional: within the floor a body is protected even if it has already moved. This matches the TDD §2 pseudocode (`now < GraceMinFloor → false` before any `hasMoved` test).

## Glue in `RoundManager`

New module-level state:

```
local GraceModel = require(ReplicatedStorage.Shared.GraceModel)
local grace = GraceModel.new()
local swapPos = {}                 -- [player] = Vector3 root position captured at swap time
local function now() return os.clock() end   -- monotonic; single source of "now"
```

**On swap** (`doSwap`, after `SwapController.swap(roster)` succeeds): for each player in the roster,

```
GraceModel.onSwap(grace, player, now(), Config.GRACE_SECONDS, Config.GRACE_FLOOR_SECONDS)
local body = ControlManager.getControlledBody(player)   -- the player's NEW body post-swap
local root = body and body:FindFirstChild("HumanoidRootPart")
swapPos[player] = root and root.Position or nil
```

**Movement sampling** — folded into the existing void monitor loop (it already iterates alive players reading each controlled body's root position at ~10 Hz, so sampling displacement there is cohesive, not a new loop). Per alive player, per tick, before/alongside the void check:

```
local origin = swapPos[player]
if origin then
    local d = root.Position - origin
    local horizontal = (Vector3.new(d.X, 0, d.Z)).Magnitude
    if horizontal > Config.GRACE_MOVE_EPSILON then
        GraceModel.markMoved(grace, player)
        swapPos[player] = nil          -- once moved, stop recomputing
    end
end
```

**The hazard gate** — a single reusable seam replacing the monitor's direct `RoundManager.eliminate` call:

```
function RoundManager.eliminateFromHazard(player)
    if GraceModel.canDieFromHazard(grace, player, now()) then
        return RoundManager.eliminate(player)
    end
    return { ended = false, winner = nil }   -- still protected by grace
end
```

The void monitor calls `RoundManager.eliminateFromHazard(player)` when `root.Position.Y < Config.VOID_Y` (instead of `eliminate`). Any future hazard, or a `Humanoid.Died` hook, routes through the same gate.

**Cleanup:** `RoundManager.eliminate` clears `grace`/`swapPos` for that player (`GraceModel.clear`, `swapPos[player] = nil`); `RoundManager.removePlayer` does the same. Disconnect-driven elimination (inside `removePlayer`) stays on the raw path and is **not** gated by grace.

### Runtime note — falling body during grace

A body inheriting a position over the void falls but is not eliminated until grace ends. With `VOID_Y = -50` and grace ≤ 1.5 s, the body stays well above `FallenPartsDestroyHeight` (default −500) for the whole window, so it is never destroyed out from under the gate. When grace expires the next monitor tick (≤ 0.1 s later) eliminates and parks it normally — no orphaned body, bijection intact. A purely falling body never trips `markMoved` (horizontal-only), so it keeps the full window — exactly the "inherited a falling body" fairness case the grace exists for.

## Config

```
Config.GRACE_MOVE_EPSILON = 0.5   -- horizontal studs of displacement that counts as "oriented",
                                  -- ending grace early. At WALK_SPEED=16 a body covers ~1.6 studs
                                  -- per 0.1s tick, so 0.5 detects intentional movement quickly while
                                  -- ignoring sampling jitter.
```

`GRACE_SECONDS = 1.5` and `GRACE_FLOOR_SECONDS = 0.5` are unchanged.

## Testing

**Pure (lune):** new `tests/grace_model.spec.luau`, run with `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/grace_model.spec.luau`. Cases, all with injected `now`:
- No entry (never swapped) → `canDieFromHazard` returns `true`.
- Just after `onSwap` at `t0`, within the floor (`now < graceMinFloor`) → `false`, **even after `markMoved`** (floor is unconditional and checked first).
- After the floor, before `graceUntil`, not moved → `false`.
- After the floor, before `graceUntil`, moved → `true` (early exit).
- At/after `graceUntil`, not moved → `true`.
- `clear` removes the entry → subsequent `canDieFromHazard` returns `true`.

**Glue (manual 2-client Studio smoke test):** extend `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md`. Temporarily lower `CYCLE_SECONDS` and raise `VOID_Y`; use `RoundManager.forceSwap()` to swap on demand.
1. **Round-start drop (no grace):** before any swap, walk a body into the void → eliminated immediately (baseline; proves no entry → can die).
2. **Post-swap drop (grace protects):** `forceSwap()`, then immediately walk/fall a body into the void within the window → it is **not** eliminated for ~1.5 s, then is eliminated and parked when grace expires. The contrast with step 1 is the proof the gate works.
3. **Early exit:** `forceSwap()`, move horizontally past the floor, then enter the void → eliminated promptly (grace ended on movement), not after the full window.
4. Confirm the winner/round-reset flow from the spine still behaves (grace changes only the hazard→eliminate edge).

## Files touched

- `src/shared/GraceModel.luau` — new pure module.
- `src/server/RoundManager.luau` — require/instantiate `GraceModel`; `now()` helper; stamp `onSwap` + capture `swapPos` in `doSwap`; sample horizontal displacement → `markMoved` in the void monitor; add `eliminateFromHazard` and call it from the monitor; clear grace/`swapPos` in `eliminate` and `removePlayer`.
- `src/shared/Config.luau` — add `GRACE_MOVE_EPSILON`.
- `tests/grace_model.spec.luau` — new lune test.
- `docs/smoke-tests/2026-06-18-round-loop-smoke-test.md` — add the grace procedure.
- `CHANGELOG.md` — record under `[Unreleased]`.
- `docs/body-swap-royale-tdd.md` — mark §2 Grace Window Logic and §10 grace items 🟡→🟢; note `CanDieFromHazard` implemented in `GraceModel`.
- `docs/body-swap-royale-gdd.md` — flip Complete Feature Inventory #3 (post-swap grace window) 🟡→🟢.
