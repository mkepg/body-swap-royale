# Soul Sweeper v2 — "Soul Turbine" Manual Smoke Test (2026-07-08)

**Requires:** 2-client Studio session (unless solo noted). Branch: `feat/soul-sweeper-arena`.

## Setup
1. Sync the latest Rojo source; start two Studio clients in Play mode.
2. Confirm boot (both clients):
   - No console errors; `Workspace.SweeperField` folder exists with annulus segments + hub pillar.
   - Two solid beam parts (`SweepBeam_low` / `SweepBeam_high`) animating at the platform center.
   - `Workspace.Bodies` contains both players' avatar bodies, spawned on the mid-ring facing the hub.
   - `workspace:GetAttribute("LiveArena") == "sweeper"` (visible via script or DevTools attribute dump).

## Cases

### 1. **Annulus walk + seam crossing (2-client)**
- Walk around the annulus in a complete circle on both the annulus and mid-ring.
- Cross seams between adjacent segments (48 tangent boxes as of v2.1) — body should not catch or trip; no gaps visible.
- Confirm: **annulus walkable and seamless** (coplanar overlap absorbs the geometry transition).

### 2. **Gap-ring fall (solo)**
- Walk inward toward the center hole (r=12); the gap ring (r 6→12) is an open fall.
- Crossing the inner edge should void the body; confirm **body eliminated and moved to balcony** after falling below `SWEEP_VOID_Y` (24 studs below surface).
- Confirm: **hub pillar (r=6) is non-walkable** — trying to stand on it fails (sheer geometry).

### 3. **Hub non-walkable (solo)**
- Attempt to walk on the central hub pillar (`SweepHub`); it should not support the body.
- Body slides off or falls into the void.
- Confirm: **hub is collision-solid but non-walkable by design** (pillar shape).

### 4. **Beam shove feel + consistency under latency (2-client)**
- Have one player stand grounded in the low beam's path; the second observes.
- Let the beam pass through (not resisting the shove): body should be pushed outward naturally.
- Repeat with intentional network-simulated latency (Studio throttle via DevTools or Roblox network settings) — shove should feel consistent, not jarring or teleport-like.
- Have one player stand in the high beam's path while grounded; beam should pass over them without sweeping (high beam is above head height).
- Confirm: **solid beam shove is smooth, network latency does not cause jank**, high beam clears grounded bodies.

### 5. **High-beam clearance — grounded vs jumping (knob: `SWEEP_BEAM_HIGH_BOTTOM`, 2-client)**
- Player stands grounded in the high beam's path; beam should pass over (no sweep).
- Player jumps into the high beam as it passes; body should be swept outward.
- Tune `Config.SWEEP_BEAM_HIGH_BOTTOM` (the bar's BOTTOM face height, v2.1) if needed: confirm it must clear a normalized R15 avatar's head (~5 studs height) when grounded but **not** when airborne/jumping.
- Confirm: **clearance rule works as designed** — high beam tuning affects sweep behavior predictably.

### 6. **Grace pass-through (swap then stand in arc, 2-client)**
- Force a swap via command bar (`RoundManager.forceSwap()`) on one player.
- While in the grace window (~1.5 s), have the swapped player move into the incoming beam's arc.
- Beam should pass through; player should **not be swept despite being in the arc**.
- After grace ends (or player moves), normal beam shove resumes.
- Confirm: **grace collision group blocks both physics shove and backstop** (body goes into `GraceBody` group, beams don't collide).

### 7. **Resist backstop (anchor-cheat simulation, 2-client)**
- Have one player stand grounded in a beam's arc; have them anchor themselves via command bar (`game.Players.LocalPlayer:GetCharacterFromPlayer().PrimaryPart.Anchored = true` or similar exploit simulation).
- Let the beam hit for 3+ consecutive ticks (resist the physics shove).
- Body should be force-swept outward after the 3-tick resist threshold (`SWEEP_RESIST_TICKS`), regardless of anchor.
- Confirm: **backstop fires after resist ticks**, hard re-pivot applied, `SweptAt` attribute stamped (body plays tumble cosmetic).

### 8. **Rotation: hex → sweeper → hex + `LiveArena` flips (2-client)**
- Note the current `workspace:GetAttribute("LiveArena")` (should be `"sweeper"`).
- Let the round end (one player remains). Round should auto-end.
- Next round begins: `LiveArena` should flip to `"hex"` (the non-active arena).
- Verify the spawn layout changes: sweeper spawns were on a mid-ring facing the turbine; hex spawns are on spiral rings facing center.
- Bodies should respawn correctly with the new arena's `spawnCFrame(index)`.
- Let the hex round end; the next round should flip back to `"sweeper"`, with `LiveArena = "sweeper"` and sweeper spawn rings.
- Confirm: **per-round rotation works**, spawn rings match the live arena, `LiveArena` attribute tracks correctly.

### 9. **Dormancy: idle arena dim + frozen (2-client, lobby view)**
- Have a round running in the sweeper arena. From the lobby (no bodies spawned yet), observe the hex arena in the distance (if both are visible; alternate: use `ARENA_OVERRIDE` to force a hex round, then check dormant sweeper).
- Dormant-arena beams should be parked at rest angles (no rotation animation).
- Dormant-arena cosmetics (wake channels, chase lights, rotor rings) should be at `SWEEP_STANDBY_TRANSPARENCY = 0.85` (dimmed).
- Switch the active arena (wait for a round to end and the next to start with `ARENA_OVERRIDE` rotation): observe `LiveArena` attribute change; the newly-dormant arena should dim + freeze within a frame.
- Confirm: **dormant arenas cost zero per-frame writes**, beams parked, cosmetics dimmed one-time.

### 10. **Wake/telegraph readability after swap cut (2-client)**
- In an active sweeper round, move one player close to the low beam's path.
- Watch the wake channels (thin radial floor strips igniting amber) behind the low bar (v2.1: the telegraph arcs were removed).
- Perform a swap (or wait for one); the visual telegraph should remain readable even as control switches.
- Wake strips should fade across a fixed ~0.9-radian trailing arc (v2.1), reflecting the low bar's measured position.
- Confirm: **wake channels + telegraph are visible and readable, not obscured by swap cuts**, cosmetic loop handles dormancy switches correctly.

### 11. **Validator non-interference during shoves (2-client, exploit-resistance)**
- Have a player standing in a beam's arc; get shoved.
- The shove is a huge input-less displacement that the MovementValidator would normally flag as impossible.
- Player should **not** be rubber-banded or corrected during the shove (no jank, smooth motion).
- After the shove, if they try to fly/teleport, the validator should catch and correct them (normal exploit protection resumes).
- Confirm: **validator reseeds bodies in/near beam arcs**, no interference during legitimate shoves, exploit detection still works elsewhere.

## v2.1 Addendum — Jump Club Refinement Cases

> These cases verify the v2.1 motorized solid-beam and true-circle refinements. Run after v2 Cases 1–11 confirm.

### 12. **Fling feel — real velocity, not penetration-shove (solo or 2-client)**
- Spawn a test body (via command bar: `Instance.new("Part"); part.CanCollide = true; part.Parent = workspace`)
  directly in the path of a rotating bar.
- Watch the body as the bar makes contact: it should be **launched with real velocity** (not nudged or
  penetration-pushed).
- Observe the trajectory: angular momentum from the spinning bar transfers to the body's linear velocity;
  the fling is smooth and repeatable.
- **Knob:** `Config.SWEEP_BEAM_DENSITY` (density tuning for fling magnitude if feel is off).
- Confirm: **fling feels natural and consistent**, body receives real impulse, not jank.

### 13. **Stall attempt — bar wins (solo or 2-client)**
- Have a player stand grounded in a beam's arc and resist (e.g., via an anchor cheat or simply by holding
  position in a simulator).
- Observe the backstop counter: after **~3 consecutive struck ticks** (`Config.SWEEP_RESIST_TICKS`), the
  beam wins — body is hard re-swept outward (force re-pivot), regardless of resistance.
- Verify the timing: a resister is backstop-swept within **~0.3 seconds** (3 ticks × 0.1 s sampler).
- Confirm: **bar cannot be stalled**, backstop fires reliably.

### 14. **True-circle visual — smooth annulus, local segment hide (solo)**
- Observe the sweeper platform floor: it should render as a **smooth seamless annulus** (no visible
  polygon segments, true circle appearance).
- This is the client `EditableMesh` annulus; on success, the server's 48 collision segments are hidden
  locally via `LocalTransparencyModifier = 1` (collision still active, visuals hidden).
- **Fallback case (if EditableMesh unavailable):** the server segments remain visible (the pre-v2.1 look);
  everything still works, just segmented appearance.
- Confirm: **annulus renders as true circle** (or visibly segmented if fallback), no visual jank.

### 15. **High-bar clearance — 3-stud thickness at grounded (solo or 2-client)**
- Have a player stand grounded at various radii in the high beam's path as it rotates.
- The high bar (now 3 studs thick, bottom at `SWEEP_BEAM_HIGH_BOTTOM = 5.5`) should pass cleanly over
  a grounded body's head.
- Verify the knob: if a grounded body is caught, **reduce** `SWEEP_BEAM_HIGH_BOTTOM`; if too low,
  increase it. Target: clearance just over a normalized R15 head.
- Confirm: **grounded body clears the high bar**, jumping into it gets swept.

### 16. **Exactly two rotating bars visible, telegraphs gone (solo or 2-client)**
- Observe the sweeper arena during a round: **exactly two solid striped bars** should be rotating
  around the hub.
- The old telegraph arcs (thin faded leading beams) should **not be visible** — they are deleted in v2.1.
- Readability now comes from the solid bars themselves + wake channels (thin radial floor strips lighting up).
- Confirm: **two bars only, no phantom telegraphs**, visual clutter reduced.

### 17. **Rotor ring 2 clears the thick bar (solo or 2-client)**
- Observe the cosmetic rotor rings near the hub as they spin.
- Rotor ring 2 (the outer visual ring) should **clear the high beam** (moved to `surfaceY + 9.5` in v2.1)
  without clipping through the bar (which tops out at ~8.5 studs with the 3-thick sizing).
- Confirm: **rotor ring 2 animation is clean**, no visual intersections with the beam.

## v2.2 Addendum — Touch Elimination

> Beams are now non-collidable deterministic kill zones (spec 2026-07-09 v2.2): touch = instant
> elimination via the grace-gated chokepoint, no physics knockback. Physics-contact cases from v2
> and v2.1 no longer apply and are retired below; run the new cases after the retired ones are
> confirmed gone (no shove/tumble/rubber-band of any kind on beam contact).

### Retired cases (no physics contact in v2.2)
- **Case 4 (beam shove feel + consistency under latency):** RETIRED by v2.2 (no physics contact).
- **Case 7 (resist backstop):** RETIRED by v2.2 (no physics contact).
- **Case 11 (validator non-interference during shoves):** RETIRED by v2.2 (no physics contact).
- **Case 12 (fling feel):** RETIRED by v2.2 (no physics contact).
- **Case 13 (stall attempt):** RETIRED by v2.2 (no physics contact).

### New cases

#### a. **Touch = instant elimination (2-client, needs an Active round)**
- Grounded in the low bar's path: eliminated the moment the bar reaches you (confirm body → balcony,
  `EliminationEvent` broadcast).
- Airborne (jump) over the low bar as it passes: survive.
- Grounded under the high bar: survive (beam passes over).
- Jump into the high bar as it passes: eliminated.
- Confirm: **class rules unchanged (jump the low bar, stay grounded under the high bar)**, but a
  failed read now kills instead of shoving.

#### b. **Anti-tunneling (2-client or solo geometry probe, needs an Active round for the live-death half)**
- At max ramp speed (late-round), stand in the bar's path and hold position.
- Confirm: **still eliminated** — the swept-interval strike (`SweeperModel.isStruckSwept`) checks
  whether the bar's arc crossed your angle since the last tick, so no rotation speed can skip over
  a stationary body between 10 Hz samples.

#### c. **Round-start grace (2-client only — can't start a round solo)**
- Spawn into a round such that a bar's path will reach your spawn angle almost immediately.
- Confirm: **you survive the first ~1.5 s** (`GRACE_SECONDS`) even if the bar sweeps over your
  spawn point during that window; moving early ends your grace before the window naturally.
- On the hex arena, confirm: **spawn tiles do not arm during the same ~1.5 s window** (round-start
  grace's intended side effect on hex).

#### d. **Grace pass-through after swaps (unchanged, 2-client)**
- Force a swap via command bar (`RoundManager.forceSwap()`); while in the post-swap grace window,
  move the swapped player into an incoming beam's arc.
- Confirm: **the bar passes through with no death** during the window (grace behavior is unchanged
  from v2/v2.1 — only the physics collision machinery that used to enforce it was deleted; the
  `graceBlocked` strike skip + `eliminateFromHazard`'s own grace re-check now do the whole job).

#### e. **Validator fully active (solo or 2-client)**
- Play normally near and through beam arcs (walking, jumping, swap-timed movement) for a full round.
- Confirm: **no rubber-banding anywhere on the platform during normal play** — the validator no
  longer carries beam-zone exceptions (there are no shove displacements to exempt).
- Attempt a fly/teleport exploit (command bar `CFrame` jump): confirm the validator **still catches
  and corrects it** — exploit protection is unaffected, just no longer punched-through near beams.

**Solo-able:** case (e) fully; case (b)'s geometry/timing half (a dropped test part in the bar's
path, observed to be caught every tick) is solo-probeable, but confirming actual elimination
requires an Active round. **2-client required:** (a), (c), (d), and the live-death half of (b) —
all need `RoundManager` in an Active round state, which is not reachable solo.

## Results

### 2026-07-08 — Studio MCP Play-Solo verification (Task 9, deterministic pass)

Run against a fully Rojo-synced Play-Solo session (all v2 modules confirmed present by Source
inspection before Play). Clean boot: no console errors; both arenas coexist (**HexField 2135
parts** + **SweeperField 31 parts** = 28 floor segments + hub + 2 beams); no Baseplate.

**Geometry (server raycast probes, RespectCanCollide):**
- Annulus top **coplanar at Y=0 across 6 sampled angles** (seam walk proxy) — no height steps.
- **Gap ring (r 5→10) is true void** (ray off-beam-angle → no hit down to the kill-plane);
  annulus floor hits at r=24; past the rim (r=41) → nothing; hub top solid at Y=+8.
- **Parked-beam yaw mapping confirmed:** low beam at polar angle 0, high at ±π, both at
  radius 21.5, heights +1.2 / +5.5 — the world mapping `angle → (cos, sin)` matches the strike
  math's `atan2` convention at both parked angles (dynamic agreement re-check remains a
  2-client observation via telegraph alignment).
- **Collision groups:** `SweepBeam`↔`GraceBody` NOT collidable; `GraceBody`↔`Default` collidable;
  beams carry `CollisionGroup = "SweepBeam"`.
- **Floor-probe fix (f142fec) empirically confirmed:** a Default-group ray through the gap ring
  at the parked beam's angle **hits `SweepBeam_low`** (the bug the final review predicted), while
  the same ray cast as `GraceBody` **passes through → no floor** (the fix).

**Client (Play-Solo client VM):**
- `SweeperDressing` = **exactly 137 parts**, inventory matches design (36 wake, 32 chase, 2×8
  rotors, 12 lower ring, 4 struts, 3+3 spotlights, 28 rim accent, 2 telegraphs, 1 shaft).
- **Standby state applied at build** (wake + chase at `SWEEP_STANDBY_TRANSPARENCY = 0.85`).
- `ArenaDressing` dresses **both** arenas (112 trim bars at hex, 16 at the sweeper).
- **Live-flip simulation** (attributes set server-side): telegraph swept ~25 studs/s, wake strips
  left standby, chase animating; clearing `LiveArena` → telegraph frozen + wake back to 0.85
  within a frame. **Dormancy engages and disengages correctly; dormant beams are frozen**
  (CFrame stable across samples; no Heartbeat connection exists before a sweeper round).

**Still MANUAL (2-client)** — cases 1, 4, 5, 7–11: shove feel under latency, high-beam clearance
tuning, grace pass-through in a live round, resist backstop on a real client, full rotation
(hex → sweeper → hex) with `LiveArena` flips + ring spawns, wake/telegraph readability after a
swap cut, validator non-interference.

### 2026-07-09 — Task 10 asset sourcing (Studio MCP)

- **Stage-floor material:** generated MaterialVariant **`SweeperStageFloor`** (base `Metal`,
  dark indigo glass-metal with amber circuitry; 3 alternate takes parked under
  `MaterialService.AssistantMaterials` for later eyeballing). Runtime-verified in Play: the
  variant resolves from MaterialService and applies to a floor segment. Wired via
  `Config.SWEEP_DISC_MATERIAL` / `_BASE` (commit `b30346c`); `""` still falls back to Glass.
- **Beams:** deliberately left Neon at the time (`SWEEP_BEAM_MATERIAL = ""`) — [superseded by
  v2.1: solid striped SmoothPlastic machine bars; the slot was retired] — the emissive glow WAS the
  energy-vane read; the slot remains for a future textured look.
- **Hub hero mesh:** generated turbine-core mesh (~6×14×6 textured MeshPart), parked as
  `ReplicatedStorage.SweeperAssets.HubMesh` — the folder lives in the PLACE file outside
  Rojo's `Shared` mapping, so syncs never delete it. Runtime-verified: replicates to the
  client and clones cleanly. The client seats its bounding box on the hub base
  (presence-based; absent ⇒ procedural pillar + rotors stand alone).
- **Pending one Rojo connect:** the wiring code (`b30346c`) postdates the last Studio sync —
  on the next Rojo connect, verify visually: annulus renders the `SweeperStageFloor` skin and
  the turbine housing appears at the hub with rotors spinning around it.

### Tuning Knobs (if issues found)
- `Config.SWEEP_BEAM_HIGH_BOTTOM` — high-bar underside clearance (tuned via Case 5 if bodies snag).
- `Config.SWEEP_RESIST_TICKS` — consecutive struck ticks before backstop (tuned via Case 7 if resisting feels too lenient).
- `Config.SWEEP_RESEED_MARGIN` — arc band for validator reseeding (tuned via Case 11 if validation jank occurs).
- `Config.SWEEP_STAND_BAND` — Y margin for "on platform" detection (tuned if edge cases allow false kills).

### Live Verification Notes
- **Case 2, 3, 4, 5, 6, 7, 11:** Deterministic 10 Hz monitor samples; ready for Studio MCP scripted verification (Task 9).
- **Case 1, 8, 9, 10:** Manual 2-client (swap state, network timing, cosmetic readability, round lifecycle).
- **Task 9 (Controller-executed):** Geometry probes (annulus seam walk via dropped-part slide, gap-ring drop-through, hub block); yaw convention (stationary probe animated to angle, overlap with beam part); collision groups (grace body vs beam pass-through); backstop trigger (anchored body in arc → swept after 3 ticks); rotation + `LiveArena` + spawn rings across two forced rounds; dormancy (no Heartbeat writes when idle — assert beam CFrame frozen); hex regression.
- **Task 10 (Controller-executed):** Asset sourcing (disc material, beam material, hub mesh) → set Config slots + verify sourced + fallback both render.

### 2026-07-09 — v2.1 Studio MCP Play-Solo verification (plan Task 6)

Run against a fully Rojo-synced Play-Solo session (v2.1 markers confirmed in Source before
Play). Clean boot, no console errors.

- **Geometry:** 48 floor segments; hub spans −6..+10 (r 6); low bar 46×1×1 SmoothPlastic at
  bottom 0.6; high bar 46×3×3 at bottom 5.5; both parked at base angles; 6 stripe shells;
  roots unanchored, `GetNetworkOwner() = nil` (server), group `SweepBeam`, motors
  `ActuatorType=Motor`, torque 1e9.
- **Spin stability (case 13/17 prerequisite):** motor-driven rotation is **perfectly clean** —
  max tilt 0°, max vertical drift 0 studs over 1.5 s (the hinge attachment axis math holds).
- **⚠ Sign inversion caught + fixed:** the probe showed hinge +ω DECREASES the measured
  `atan2(Z,X)` angle (right-hand rule about world-up), silently inverting the `direction`
  convention (the client wake would trail on the wrong side). Fixed at one point —
  `motorTarget()` negates (`fix(sweeper-v2.1): negate motor target`) — and re-verified live:
  a `direction=+1` bar now sweeps at **+0.701 rad/s measured** for a 0.7 target.
- **Case 12 (fling):** an unanchored 2×2×2 dummy in the bar's path was launched at
  **27 studs/s peak** and thrown ~35 studs — real momentum transfer, not penetration-shove.
- **Case 13 (stall):** rotation rate unchanged (0.70) through the collision — the motor holds
  its target under contact. Brake leaves residual angular speed ≈ 0.001.
- **Case 14 (true circle):** `SmoothAnnulus` EditableMesh MeshPart rendered (104-stud diameter,
  top at +0.02, `Metal` + `SweeperStageFloor` variant applied); server segments hidden locally
  (`LocalTransparencyModifier = 1`, collision untouched).
- **Case 16 (two bars):** **zero** telegraph parts in the dressing — exactly two rotating bars.
- **Case 17 (rotor clearance):** rotor ring 2 at Y=9.5, above the thick bar's 8.5 top.
- **Budget:** 157 dressing parts (≤180 assert holds; includes the hub hero mesh).

**Still MANUAL (2-client):** shove FEEL on a real player body under latency (case 4/12 feel
half), high-bar clearance vs a real avatar (case 5/15), grace pass-through in a live round
(case 6), backstop on a real resisting client (case 7/13 player half), rotation + spawn rings
(case 8), dormancy from the lobby (case 9), wake readability after a swap cut (case 10),
validator non-interference (case 11).
