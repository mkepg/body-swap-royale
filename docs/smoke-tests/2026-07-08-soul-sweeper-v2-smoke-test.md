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
- Cross seams between adjacent segments (28 tangent boxes) — body should not catch or trip; no gaps visible.
- Confirm: **annulus walkable and seamless** (coplanar overlap absorbs the geometry transition).

### 2. **Gap-ring fall (solo)**
- Walk inward toward the center hole (r=10); the gap ring (r 5→10) is an open fall.
- Crossing the inner edge should void the body; confirm **body eliminated and moved to balcony** after falling below `SWEEP_VOID_Y` (24 studs below surface).
- Confirm: **hub pillar (r=5) is non-walkable** — trying to stand on it fails (sheer geometry).

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

### 5. **High-beam clearance — grounded vs jumping (knob: `SWEEP_BEAM_HIGH_Y`, 2-client)**
- Player stands grounded in the high beam's path; beam should pass over (no sweep).
- Player jumps into the high beam as it passes; body should be swept outward.
- Tune `Config.SWEEP_BEAM_HIGH_Y` if needed: confirm it must clear a normalized R15 avatar's head (~5 studs height) when grounded but **not** when airborne/jumping.
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
- Watch the wake channels (thin radial floor strips igniting amber) and telegraph (thin arc ahead of the beam).
- Perform a swap (or wait for one); the visual telegraph should remain readable even as control switches.
- Wake strips should fade over ~1.2 seconds, reflecting the low beam's recent position.
- Confirm: **wake channels + telegraph are visible and readable, not obscured by swap cuts**, cosmetic loop handles dormancy switches correctly.

### 11. **Validator non-interference during shoves (2-client, exploit-resistance)**
- Have a player standing in a beam's arc; get shoved.
- The shove is a huge input-less displacement that the MovementValidator would normally flag as impossible.
- Player should **not** be rubber-banded or corrected during the shove (no jank, smooth motion).
- After the shove, if they try to fly/teleport, the validator should catch and correct them (normal exploit protection resumes).
- Confirm: **validator reseeds bodies in/near beam arcs**, no interference during legitimate shoves, exploit detection still works elsewhere.

## Results

### Expected Status
- All cases pass: smoke test green, ready for Task 9 (Studio MCP verification + tuning) and Task 10 (asset sourcing).

### Tuning Knobs (if issues found)
- `Config.SWEEP_BEAM_HIGH_Y` — clearance for high beam (tuned via Case 5 if bodies snag).
- `Config.SWEEP_RESIST_TICKS` — consecutive struck ticks before backstop (tuned via Case 7 if resisting feels too lenient).
- `Config.SWEEP_RESEED_MARGIN` — arc band for validator reseeding (tuned via Case 11 if validation jank occurs).
- `Config.SWEEP_STAND_BAND` — Y margin for "on platform" detection (tuned if edge cases allow false kills).

### Live Verification Notes
- **Case 2, 3, 4, 5, 6, 7, 11:** Deterministic 10 Hz monitor samples; ready for Studio MCP scripted verification (Task 9).
- **Case 1, 8, 9, 10:** Manual 2-client (swap state, network timing, cosmetic readability, round lifecycle).
- **Task 9 (Controller-executed):** Geometry probes (annulus seam walk via dropped-part slide, gap-ring drop-through, hub block); yaw convention (stationary probe animated to angle, overlap with beam part); collision groups (grace body vs beam pass-through); backstop trigger (anchored body in arc → swept after 3 ticks); rotation + `LiveArena` + spawn rings across two forced rounds; dormancy (no Heartbeat writes when idle — assert beam CFrame frozen); hex regression.
- **Task 10 (Controller-executed):** Asset sourcing (disc material, beam material, hub mesh) → set Config slots + verify sourced + fallback both render.
