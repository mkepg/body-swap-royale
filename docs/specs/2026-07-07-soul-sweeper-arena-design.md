# Soul Sweeper — Arena #2 Design

**Date:** 2026-07-07
**Status:** 🟡 Spec'd (approved in brainstorm; implementation pending)
**Branch:** `feat/soul-sweeper-arena`
**Based on:** the 2026-07-03 critical review (arena #2 triggers the singleton-decomposition
noted in §2.2/§6), the world-enrichment roadmap ("one world, swappable courses"; hybrid build
approach), and the existing `ArenaDescriptor` contract.

---

## 1. Concept

A second playable arena adapting Fall Guys / Stumble Guys' **"Jump Club" / "Jump Showdown"**
survival round into Body Swap Royale's continuous last-soul-standing-over-a-void loop.

**Soul Sweeper** is a stack of circular broadcast discs over the void. Rotating **soul-beams**
sweep each disc. The player survives by reading each beam and choosing to **jump** (low beam) or
**stay grounded** (high beam). A body that fails to clear a beam is **swept off** its disc's rim;
because discs **widen going downward**, the swept body is caught by the wider tier below — only a
fall off the **bottom** disc reaches the void and ends the run.

The swap loop supplies the novelty: the hard camera cut can drop you onto a disc with a beam
already bearing down — a half-second "read your inherited spot" test — and each swap reshuffles
everyone's position on the shared stack.

**Why this concept** (from the brainstorm): it reuses the game's clean *geometric fall death*,
is the most instantly legible of the Fall Guys survival rounds, and has the simplest contact case
(one beam, one disc) to make server-authoritative. It deliberately trades hex's *emergent
player-caused* hazard for a *reaction gauntlet*; that is an accepted tradeoff for this arena.

---

## 2. Locked design decisions (from the brainstorm)

| # | Decision | Choice |
|---|----------|--------|
| 1 | Beam contact model | **Server re-pivot sweep** (deterministic outward glide via reposition-then-re-own) + a **client cosmetic tumble**. No physics knockback — server stays authoritative over eliminations. |
| 2 | Arena shape | **Stacked discs, widening downward** (descent / second-chance). Only a fall off the bottom disc = void death. |
| 3 | Beam skill | **Jump + don't-jump**: low beams (amber) you jump; high beams (red) pass overhead only if you stay grounded. Height is color- AND shape-coded for legibility after a swap. No crouch. |
| 4 | Fairness | **Observe-first.** No dedicated immunity system. The sweep reuses the SAME `graceBlocked` sample flag hex uses to skip arming, so grace-protected bodies are simply never swept — and any eventual void death still flows through the existing grace-gated monitor. Watch inherited-hit rate before adding more. |
| 5 | Architecture | **Thin `ArenaHazard` interface** both hex and Sweeper implement, selected via `ArenaDescriptor`; `RoundManager` talks to the interface. No full `RoundManager` reducer rewrite. |
| 6 | Hybrid build | **Procedural core = load-bearing build** (works with zero assets, MCP-independent). Sourced layer = **materials on discs + beams + one hero mesh** (central beam-emitter hub), each Config-gated with a code-only fallback. **No dead second geometry path.** |

---

## 3. Architecture — the `ArenaHazard` interface

Today `RoundManager` calls `HazardSystem` directly (`build/start/step/stop`). We introduce a small
contract so `RoundManager` is arena-agnostic and courses become swappable.

### 3.1 The contract (`src/server/ArenaHazard.luau` — a type/doc module, no logic)

An `ArenaHazard` is a table implementing:

```
build()                         -- once at startup: construct geometry (replaces baseplate)
start(now)                      -- beginRound: reset to the round-start state
step(now, samples) -> effects   -- per monitor tick: returns side-effect REQUESTS (see below)
stop()                          -- endRound: freeze to a safe resting state
descriptor() -> ArenaDescriptor -- publishes the Layer-2 dressing descriptor for this arena
voidY() -> number               -- this arena's kill-plane Y (replaces the hex-specific Config.VOID_Y)
```

`samples` is the existing array of `{ position: Vector3, graceBlocked: boolean }`, **extended**
with the two fields Sweeper needs (both cheap, both server-derived, both harmless to hex which
ignores them):

- `player` — so a returned sweep can be tied back to a controller for the re-own.
- `body` — the controlled body instance (for the pivot) and to read airborne state.
- `velocityY` — root `AssemblyLinearVelocity.Y` (airborne/vertical-state derivation).

`step` returns an **effects** table describing side effects for `RoundManager` to apply — keeping
all body manipulation and elimination in `RoundManager` (decision/side-effect split preserved):

```
effects = {
  sweeps = { { player = Player, body = Model, target = CFrame }, ... }  -- outward re-pivot requests
}
```

Hex returns `effects = {}` (it never sweeps; its bodies fall through gone tiles by gravity).
`RoundManager` applies each sweep with the existing primitive:
`BodyManager.pivotTo(body, target)` → `ControlManager.regrantControl(player)` →
`noteServerReposition(body)` (so the sweep is never read as a movement-validation violation).
Death still occurs only via the existing `VOID_Y` check in the monitor, which is grace-gated.

### 3.2 Implementations

- **`HexHazard`** (`src/server/HexHazard.luau`) — a thin wrapper delegating to today's
  `HazardSystem` (which is left essentially unchanged) and returning `descriptor() =
  ArenaDescriptor.hex()` and empty `effects`. This is a *refactor*, not a rewrite: the goal is
  that hex behaves identically.
- **`SweeperHazard`** (`src/server/SweeperHazard.luau`) — new; §5.

### 3.3 Arena selection

`Config.ACTIVE_ARENA` (string: `"hex"` | `"sweeper"`) selects the hazard at startup. `RoundManager`
resolves it once into a local `arena` and calls the interface everywhere it currently names
`HazardSystem`. The client resolves the SAME flag to pick which dressing/controller to start. This
is the minimal, deterministic selector; round-to-round rotation is a later, additive change.

> **Note — client arena selection:** `ArenaDressing` currently hardcodes `ArenaDescriptor.hex()`.
> It becomes `ArenaDescriptor.forActive()` (a small dispatch on `Config.ACTIVE_ARENA`). The
> Sweeper descriptor is a new `ArenaDescriptor.sweeper()`.

---

## 4. Geometry — the stacked, downward-widening discs

Driven entirely by Config + published through `ArenaDescriptor.sweeper()` (arena-agnostic; no
hardcoded world coordinates in logic).

- `SWEEP_TIER_COUNT` discs, top → bottom, each at `y = SWEEP_TOP_SURFACE_Y - k * SWEEP_TIER_GAP`.
- Radii **increase** downward: `radius(k) = SWEEP_TOP_RADIUS + k * SWEEP_RADIUS_STEP`, so a body
  pushed just past disc *k*'s rim falls onto disc *k+1* (wider), not into the void. The bottom
  disc is the widest and last stand.
- Each disc is one procedural cylinder Part (anchored, `SWEEP_SMOOTH_SIDES` handled by the client
  mesh for smoothness like the beyblade lobby; the SERVER collision disc is a plain `Cylinder`
  Part — collision fidelity, not visual). A **central hub** (hero mesh / procedural cone fallback)
  sits at each disc center as the beam emitter.
- Per-tier color from a palette (`SWEEP_TIER_COLORS`, reusing the "distinct color per level" idea
  hex uses for depth orientation).
- `VOID_Y` for this arena = `4` studs below the bottom disc surface (same rule hex uses). Because
  `Config.VOID_Y` is currently hex-specific, it becomes arena-scoped: the active arena publishes
  its kill-plane. **Cleanest approach:** `RoundManager` and `hasFloorBeneath` read
  `arena.voidY()` (added to the interface) instead of `Config.VOID_Y` directly, OR `Config.VOID_Y`
  is computed from the active arena. Spec choice: **add `voidY()` to the `ArenaHazard` interface**;
  hex returns today's value, Sweeper returns its bottom-disc-derived value. (This also cleanly
  removes a latent hex coupling.)

> **The one geometry call flagged in the brainstorm:** discs widen downward so outward sweeps are
> caught. If future tuning wants lower discs *smaller/harder*, a separate catch mechanism (safety
> ring) would be needed — out of scope for v1.

---

## 5. Server strike detection & the sweep (`SweeperHazard`)

**Beams are cosmetic; strikes are pure server math.** No beam part ever collides with a body.

Each monitor tick, for each alive body sample, `SweeperHazard.step`:

1. **Locate the tier.** Find the disc whose surface `y` is nearest at/below `sample.position.Y`
   within a `SWEEP_STAND_BAND` (mirrors hex's floor bands). A body between tiers (mid-fall) is on
   no tier → not evaluated (it is falling; gravity/void handles it).
2. **Compute polar coords** relative to that tier's center: `radius = |xz - center.xz|`,
   `angle = atan2(dz, dx)`.
3. **Derive vertical state** (server-observable, no client input): `airborne = (position.Y -
   tierSurfaceY) > SWEEP_AIRBORNE_BAND` OR `velocityY > SWEEP_AIRBORNE_VY`. Feeds the pure clear
   rule.
4. **Ask the pure `SweeperModel`** whether any of that tier's beams currently overlaps
   `(radius, angle)` AND is NOT cleared by the body's vertical state (low beam cleared by airborne;
   high beam cleared by grounded). See §6.
5. On a strike of a body whose sample is **NOT** `graceBlocked`: compute the outward sweep target
   (radial direction from tier center through the body, out to `tierRadius + SWEEP_OFF_MARGIN`, same
   Y) and add `{ player, body, target }` to `effects.sweeps`. `graceBlocked` bodies are skipped
   (the free grace immunity, §2 decision 4).

`build/start/stop` construct/reset the procedural geometry (beams are cosmetic on the client, so
the server only owns the collision discs + hub; `start`/`stop` mostly no-op beyond ensuring discs
are solid). Beam *phase in time* is derived from a single round-start timestamp shared with the
client via `GetServerTimeNow()` (same clock discipline as the swap countdown) so server strike math
and client rendering agree without replicating per-beam state.

---

## 6. Pure logic — `SweeperModel` (Roblox-free, lune-tested)

Mirrors the `HexErosionModel` discipline: dependency-injected, deterministic, no Roblox globals.
All angles in radians; all inputs plain numbers/tables.

```
SweeperModel.beamAngle(beam, elapsed) -> number
  -- beam = { baseAngle, direction (+1/-1), angularSpeed, armIndex, armCount }
  -- returns the current angle of this arm: baseAngle + direction*angularSpeed*elapsed
  --         + armIndex * (2π / armCount), normalized to [0, 2π)

SweeperModel.rampedSpeed(baseSpeed, elapsed, opts) -> number
  -- opts = { rampPerSecond, maxSpeed }; monotonic speed-up over the round, clamped

SweeperModel.overlaps(radius, angle, beam, opts) -> boolean
  -- opts = { innerRadius, outerRadius, angularHalfWidth }
  -- true iff innerRadius <= radius <= outerRadius AND angularDistance(angle, beamAngle) < halfWidth

SweeperModel.clears(beamClass, airborne) -> boolean
  -- "low" cleared iff airborne == true; "high" cleared iff airborne == false

SweeperModel.isStruck(bodyPolar, verticalState, tierBeams, elapsed, opts) -> boolean
  -- composes rampedSpeed → beamAngle → overlaps → (not clears) across a tier's beams;
  -- returns true iff ANY beam overlaps and is not cleared. Pure orchestration; the glue
  -- passes tier beam configs + the elapsed time + opts, gets a yes/no.

SweeperModel.outwardTarget(bodyXZ, centerXZ, outRadius) -> { x, z }
  -- radial unit vector from center through body, scaled to outRadius (the glue lifts it to a CFrame
  -- at the tier Y). Pure vector math on plain numbers (no Vector3).
```

`angularDistance(a, b)` (wrap-around minimal angle) is an internal pure helper with its own tests
(including the seam at 0/2π — the analogue of hex's `-0` regression test).

Beam/tier **configuration** (arm counts, base speeds, directions, height classes per tier) lives in
Config as plain tables and is passed into the pure model; the model contains no arena constants.

---

## 7. Client — `SweeperController` (100% cosmetic, MCP-independent core)

Location `StarterPlayerScripts/Client/SweeperController` (started when `Config.ACTIVE_ARENA ==
"sweeper"`; hex's client stack is untouched).

- **Beam rendering.** Cosmetic beam parts per tier, positioned each frame from
  `SweeperModel.beamAngle` using a round-start server time (from `RoundStateChanged` /
  `GetServerTimeNow()`), so they visually match the server's strike math. Low beams amber + a
  distinct silhouette (e.g. a low flat bar); high beams red + a distinct silhouette (a raised
  bar). Color AND shape coded (accessibility, matches the game's telegraph philosophy).
- **Predictive sweep telegraph.** A short shadow/arc on the disc *ahead* of each beam (computed
  from the same `beamAngle`), colored by height class — the "read your inherited spot" aid after a
  swap.
- **Cosmetic tumble.** On the authoritative sweep, play a brief ragdoll/spin/knock animation, fed
  by authoritative state and never driving it — the same discipline the grace-shimmer fix
  established. **Signal mechanism (decided): a body Attribute `SweptAt`** (server stamps
  `os.clock()`/`GetServerTimeNow()` on the swept body when it enqueues the sweep), which the client
  watches via `GetAttributeChangedSignal`, mirroring how `GraceProtected` already drives the Soul
  shimmer. No new remote; zero client→server.
- **Tier hub + dressing** via the hybrid pipeline (§8), driven by the descriptor.

---

## 8. Hybrid build (matches the world-enrichment contract)

- **Procedural core (always works, no assets, MCP-independent):** collision discs + hub (server),
  cosmetic smooth-mesh discs / beams / hub / tier trim (client), all from Config + descriptor.
- **Sourced layer (Config-gated, `""` → fallback):**
  - `SWEEP_DISC_MATERIAL` / `SWEEP_BEAM_MATERIAL` — MaterialVariant or texture asset IDs applied to
    the procedural parts; fallback = stock `Material` + `Color`/`Neon`.
  - `SWEEP_HUB_MESH` — the ONE hero mesh (central beam-emitter hub); fallback = a procedural cone.
- **Guardrails (review §2.4 lessons):** exactly one live geometry path (procedural); sourced assets
  only re-dress it; uploaded asset IDs (not runtime EditableMesh), each with a clean `""` fallback.
- **Sequencing:** the procedural core + pure model are built and verified FIRST (no MCP). Sourced
  assets (materials + hub mesh) are sourced via Studio MCP and wired to Config as a LATER task, so
  a disconnected MCP never blocks the arena landing.

---

## 9. RoundManager integration (surgical)

- Resolve `arena = ArenaRegistry.forActive()` once (a tiny module returning the `HexHazard` or
  `SweeperHazard` singleton for `Config.ACTIVE_ARENA`).
- Replace the four direct `HazardSystem.*` calls (`build`/`start`/`step`/`stop`) with `arena.*`.
- Extend the per-tick sample with `player`, `body`, `velocityY` (already have `body`/root in scope).
- After `arena.step(...)`, apply `effects.sweeps` via the reposition-then-re-own primitive.
- Replace direct `Config.VOID_Y` reads (`hasFloorBeneath`, the void check) with `arena.voidY()`.
- No changes to the grace gate, movement validator, cadence, economy, or swap logic.

Everything else in `RoundManager` is untouched — the interface indirection is the whole change.

---

## 10. Fairness & exploit posture (stress-tested)

- **Inherited hit:** grace-protected bodies are never swept (`graceBlocked` skip) and can't die to
  the void while protected — a just-swapped/round-start player always gets their orient beat. Beams
  are periodic and escapable, so there is no positional-doom analogue to solve (unlike an
  eroded-away hex floor). **No extra machinery; observe inherited-hit rate first.**
- **Exploit resistance:** the sweep is a **server** re-pivot, so a client cannot "refuse" a beam
  (the client-authoritative fly/teleport concern from review §3.2 does not reopen here). The
  existing `MovementValidator` still runs on every owned body; server sweeps are excluded from it
  via `noteServerReposition`.
- **Griefing sweep:** the outward target is derived from current state (radial), arena-agnostic,
  and only ever pushes a body toward *its own* rim — it cannot be aimed at another player.
- **Edge cases to verify in smoke:** body exactly on a tier boundary; body airborne over a high
  beam vs grounded under it; simultaneous strike + swap commit; a body swept at the instant grace
  expires; a body straddling the hub/inner radius (excluded by `innerRadius`).

---

## 11. Testing

- **Pure (`lune`)** — `tests/SweeperModel.spec.luau`: `beamAngle` wrap-around, `rampedSpeed` clamp
  & monotonicity, `overlaps` (in/out of arc, radius bounds), `clears` (both classes), `isStruck`
  composition (multi-arm, multi-beam), `angularDistance` seam at 0/2π, `outwardTarget` direction &
  magnitude. Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/SweeperModel.spec.luau`.
- **Glue** — Studio MCP verification (geometry builds, tier bands, strike→sweep→tier-catch, grace
  skip, cosmetic tumble) once MCP is reachable, plus a new manual 2-client smoke doc
  `docs/smoke-tests/2026-07-07-soul-sweeper-smoke-test.md` (cases from §10 + the full descent and
  the swap-onto-incoming-beam read).
- **Regression** — all existing lune suites still green (the `HexHazard` refactor must not change
  hex behavior).

---

## 12. Scope

**v1 (this spec):** stacked downward-widening Sweeper arena; jump/don't-jump low+high beams;
server-math strikes + re-pivot sweep + cosmetic tumble + predictive telegraph; `ArenaHazard`
interface with hex refactored behind it + `ArenaRegistry` selection; `SweeperModel` pure + tests;
`ArenaDescriptor.sweeper()` + client dressing/controller; procedural build with materials + one
hero-mesh hybrid layer (fallbacks); Config block; smoke doc.

**Deferred:** crumbling-disc pressure; sidestep-gap beams; beam-immunity flicker / swap-placement
guard (pending observation); full `RoundManager` sequencing-reducer decomposition + bot harness;
mesh discs/beams; round-to-round arena rotation; asset sourcing beyond the one hero mesh + two
materials.

---

## 13. Risks / open questions

1. **`SweptAt` attribute cadence** — the server may stamp it on consecutive ticks while a body is
   still in a beam; the client must debounce so the tumble animation isn't re-triggered every tick
   (play only on a rising edge / when not already tumbling).
2. **Disc smoothness on the server collision disc** — a primitive `Cylinder` Part is a coarse
   collision proxy under a smooth client mesh; verify bodies don't catch on facets at the rim
   (mitigate with a slightly inset collision radius vs the visual mesh, like the lobby disc).
3. **`voidY()` on the interface** touches `hasFloorBeneath` and the void check — small but
   load-bearing; the `HexHazard` value must exactly equal today's `Config.VOID_Y`.
4. **Airborne thresholds** (`SWEEP_AIRBORNE_BAND`/`_VY`) need tuning so a legitimate jump reliably
   clears a low beam and a grounded stance reliably survives a high beam — a smoke-test tuning loop.
5. **MCP currently disconnected** — blocks the asset-sourcing and live-glue-verification tasks only;
   the procedural core + pure model proceed without it.
