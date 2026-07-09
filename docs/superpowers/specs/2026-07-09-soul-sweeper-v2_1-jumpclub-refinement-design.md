# Soul Sweeper v2.1 — Jump Club Refinement (bigger true-circle arena, motorized solid beams)

**Date:** 2026-07-09
**Status:** 🟡 Spec'd (approved in review discussion; implementation pending)
**Branch:** `feat/soul-sweeper-arena` (continues on the verified v2 work)
**Amends:** the [2026-07-08 v2 spec](2026-07-08-soul-sweeper-v2-turbine-design.md) — geometry
scale, beam physics, and beam visuals only. Everything else (rotation, `LiveArena` dormancy,
grace collision groups, resist backstop, validator reseeds, budgets discipline, hex) carries
forward unchanged.

---

## 1. Playtest feedback driving this (2026-07-09, Fall Guys Jump Club reference)

1. **Play area too small** → significantly larger platform.
2. **Platform must read as a TRUE circle** ("like the lobby"), not a visibly segmented polygon.
3. **Exactly two beams** on one shared central pivot, different speeds and/or opposite
   directions. *(Player saw "four beams": the two client floor-telegraph arcs rotate ahead of
   the real beams and read as extra beams — a real legibility bug.)*
4. **Physics must be significantly better** — smooth, reliable, natural beam hits.
5. **Beams must look like large solid physical bars**, not glowing light: **upper beam larger
   and thicker, lower beam smaller and thinner** (Jump Club idiom).

## 2. Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Scale | `SWEEP_PLATFORM_RADIUS 38→52`, `SWEEP_HOLE_RADIUS 10→12`, `SWEEP_HUB_RADIUS 5→6`, `SWEEP_CENTER (110,0,0)→(140,0,0)` (hex clearance), `SWEEP_SPAWN_RADIUS 24→32` (mid-annulus), `LOBBY_FACE_TARGET (55,0,0)→(70,0,0)`. |
| 2 | True circle | **The lobby technique**: server collision stays a segmented ring but densified `28→48` segments (max deviation from a perfect circle ≈ 0.1 studs — imperceptible); the **client builds one seamless smooth annulus MeshPart** (EditableMesh, the `LobbyStage.buildEditableCyl` pattern adapted to a ring: inner ring R=hole, outer ring R=platform, top/bottom quad strips + outer & inner skirts) carrying the `SweeperStageFloor` MaterialVariant, and hides the server segments locally via `LocalTransparencyModifier = 1`. EditableMesh unavailable (pcall fails) → segments stay visible (current look), nothing breaks. Runtime CSG rejected (new dependency for a 0.1-stud gain). |
| 3 | Two beams only | Config already defines exactly two (low `+`dir, high `−`dir, different base speeds). **Delete the two floor-telegraph arcs entirely** (build + per-frame positioning). Readability = the chunky physical bars + the amber wake channels. |
| 4 | Beam physics | **Motorized constraint physics** (the v2 spec §11-1 escalation path). Each beam is an **unanchored welded assembly** driven by a `HingeConstraint` motor (`ActuatorType = Motor`) on an anchored hub axle: real angular velocity → real contact impulses → players get flung naturally and consistently. `MotorMaxTorque` huge (players cannot stall it), high-density parts, **server-owned** (`SetNetworkOwner(nil)`). The server updates `AngularVelocity = direction × rampedSpeed(elapsed)` each monitor tick (the ramp survives). The v2 Heartbeat CFrame animation is **deleted** — the physics engine rotates the beams. |
| 5 | Angle source of truth | **The measured physical pose.** The strike backstop and all client cosmetics read each beam's actual angle from its replicated root CFrame (`atan2` of the bar-center offset from the hub). `SweeperModel` gains a pure `isStruckAt(body, beams)` that takes **measured angles** (replacing the elapsed-based `isStruck`, which is removed along with its tests — nothing else consumed it). This **retires the yaw-sign risk class entirely**: geometry, physics, authority, and cosmetics observe one physical object; there is no computed-vs-physical mapping to disagree. `rampedSpeed`/`beamAngle` remain (motor target + tests). |
| 6 | Beam visuals | **Solid striped machine bars** (Fall Guys idiom), `SmoothPlastic`, NOT Neon: alternating colored segments (welded parts — stripes without textures), rounded end cap, and a hub collar so each bar visibly mounts the pivot. **Low beam thin:** ~1×1 cross-section, bottom at `SWEEP_BEAM_LOW_BOTTOM = 0.6` (jumpable), amber/cream stripes. **High beam thick:** ~3×3, bottom at `SWEEP_BEAM_HIGH_BOTTOM = 5.5` (the load-bearing grounded-clearance knob, renamed from `SWEEP_BEAM_HIGH_Y` semantics: BOTTOM face, not center), crimson/cream stripes. Config: `SWEEP_BEAM_STRIPES = 6`, `SWEEP_BEAM_STRIPE_COLOR` (warm cream), `SWEEP_BEAM_LOW_THICKNESS = 1`, `SWEEP_BEAM_HIGH_THICKNESS = 3`. |
| 7 | Client timing | With measured angles, the client no longer needs `RoundStartServerT` for beams (wake ignition follows the low bar's replicated pose; chase/rotors keep local clocks). The attribute stays published (harmless, and a future consumer may want it). |

## 3. What this deletes (no dead code left behind)

- `SweeperHazard`: the Heartbeat CFrame animation (`startAnimation`/`stopAnimation` beam
  stepping), `beamCFrame`'s `-angle` yaw note (the whole risk class is gone).
- `SweeperModel.isStruck` (elapsed-based) + its spec blocks → replaced by `isStruckAt` + tests.
- Client: both telegraph arcs (build + loop), `SWEEP_TELEGRAPH_LEAD` config.
- `SWEEP_BEAM_SIZE`/`SWEEP_BEAM_LOW_Y`/`SWEEP_BEAM_HIGH_Y` replaced by the §2-6 keys.

## 4. Behavior details

- **start(live):** motors set to ramped target velocity; **stop(dormant):** motors braked
  (`AngularVelocity = 0`) and the assemblies re-parked at `baseAngle` via `PivotTo` (unanchored
  server-owned assemblies pivot fine). Dormant cost ≈ zero (a braked motor at rest).
- **Backstop:** unchanged logic (`SWEEP_RESIST_TICKS` consecutive struck ticks → hard outward
  re-pivot + `SweptAt`), now fed measured angles via `isStruckAt`. It matters MORE now: with
  real physics most hits fling players naturally, so the backstop only catches resisters.
- **Reseeds:** unchanged (bodies near a measured arc get validator reseeds) — physics flings
  are large input-less displacements, exactly what the reseed protects.
- **Grace:** unchanged — `GraceBody`↔`SweepBeam` non-collidable; grace bodies phase through the
  solid bars; the backstop's `graceBlocked` skip still applies.
- **Floor probe:** unchanged (`GraceBody`-group ray already ignores beams — v2 fix `f142fec`).
- **Budgets:** telegraphs −2 parts; smooth annulus +1 MeshPart; stripes/collars/caps live on the
  SERVER (assembly parts), not in the client dressing budget. Client `assert(≤180)` stays.

## 5. Risks / live-verification items (Task 6)

1. **Constraint stability at speed** — huge torque + high density at `SWEEP_SPEED_MAX`; verify
   no wobble/precession (single upright hinge axis should be clean).
2. **Fling magnitude tuning** — beam density / body knockback feel; verify a dropped test body
   in the bar's path is launched with real velocity (not penetration-shoved).
3. **Players stalling beams** — verify a body wedged against the bar cannot stop it
   (`MotorMaxTorque` wins) and the backstop sweeps a resister within ~0.3 s.
4. **EditableMesh availability** — smooth annulus renders; else fallback look verified.
5. **High-beam clearance** — grounded body passes under the 3-thick bar (bottom 5.5); jumping
   into it gets hit. Knob: `SWEEP_BEAM_HIGH_BOTTOM`.
6. **Replication smoothness** of physics-owned beams for remote observers at max ramp.
