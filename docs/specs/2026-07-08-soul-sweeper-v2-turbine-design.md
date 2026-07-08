# Soul Sweeper v2 — "Soul Turbine" + Persistent Two-Arena World

**Date:** 2026-07-08
**Status:** 🟡 Spec'd (design approved in brainstorm; implementation pending)
**Branch:** `feat/soul-sweeper-arena` (continues on top of the verified v1 work)
**Supersedes:** the geometry, contact mechanism, and arena-selection sections of the
[2026-07-07 v1 spec](2026-07-07-soul-sweeper-arena-design.md). The v1 `ArenaHazard` interface,
`ArenaRegistry`, pure `SweeperModel` (+ lune tests), `SweptAt` tumble pipeline, and grace gating
all carry forward.

---

## 1. What changed and why

Playtest-direction feedback (2026-07-08) redefined the arena and the world:

1. **One platform, not tiers.** A single large circular platform sized for the max player count,
   like Fall Guys' Jump Club — the stacked-disc descent is gone.
2. **A real machine.** The platform has a **center hole**; inside it sits the **rotating hub
   mechanism** the two beams attach to — the rotation system must read as physically grounded.
3. **Two stacked beams.** A low beam that forces jumps and a high beam that adds
   timing/positioning pressure (our jump / don't-jump rule — bodies can't crouch).
4. **Natural physics.** Beam contact must feel smooth/consistent/natural — the v1 10 Hz outward
   re-pivot teleport is demoted from primary mechanism to anti-cheat backstop.
5. **Persistent multi-arena world.** All arenas permanently built and visible from the lobby;
   **one live match at a time rotates between arenas**. (True concurrent matches were explicitly
   deferred — that is the full singleton decomposition, a separate effort.)
6. **Idle arenas go fully dormant** — parked beams, standby dimming via one-time property flips,
   **zero per-frame writes** for the inactive arena.
7. **Art direction: "Soul Turbine"** (chosen over Carnival Zoetrope / Astral Clockwork) — the
   arena as a colossal broadcast machine; visual quality is a first-class requirement.

---

## 2. Locked decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Platform | Single annulus: outer radius ~38 (16 players), center hole radius ~10, hub pillar radius ~5 → a real ~5-stud **fall-gap ring** around the hub (denies center-camping, where the beam is slowest). |
| 2 | Descent | None. Off the outer rim or into the gap → void. Kill-plane ~24 studs below the surface (a visible fall beat). |
| 3 | Beams | Exactly two independent rotors on the shared hub: **low** (amber, ankle height, jump it) and **high** (red, ~5.5 studs, stay grounded), opposite directions, different base speeds, existing ramp. |
| 4 | Contact | **Solid collidable beams**, server-animated every Heartbeat from the same `angle(t)` math the strike detection uses. The owning client's physics resolves the shove locally (smooth, zero-latency). |
| 5 | Anti-cheat | The v1 server strike math becomes the **backstop**: a body inside a beam arc for N consecutive ticks (resisting) gets the hard outward re-pivot + `SweptAt`. |
| 6 | Grace | Server-set **collision group**: grace bodies don't collide with beams (pass through physically); the strike backstop already skips `graceBlocked`. Deterministic, no client trust. |
| 7 | Validator | A beam shove is huge input-less displacement → the MovementValidator must not rubber-band it. The live arena's `step` returns the bodies currently in/near a sweep arc; RoundManager **reseeds** validation for them (same primitive as `noteServerReposition`). |
| 8 | World | Both arenas built at startup and permanently visible: hex at origin (unmoved — no risk threading offsets through HexGrid), Sweeper centered at `SWEEP_CENTER` (~`(110, 0, 0)`). Round rotation picks the live arena per round; `Config.ARENA_OVERRIDE` pins one for testing (replaces `ACTIVE_ARENA` as a build switch). |
| 9 | Dormancy | A server-authoritative `LiveArena` attribute drives everything: server animates only the live arena's beams (dormant beams parked, no writes); the client's single shared cosmetic loop skips dormant arenas; standby dim is a one-time flip. |
| 10 | Art | **Soul Turbine** (§7), Neon-only lighting vocabulary (no real PointLights, per the orb reassessment), Config-gated sourced assets with procedural fallbacks, hard part/write budgets. |

---

## 3. Geometry

All values Config-driven; the descriptor publishes them for dressing. Sweeper local coordinates
are relative to `SWEEP_CENTER` (world `(110, 0, 0)`), surface at `SWEEP_SURFACE_Y = 0`.

- **Walkable annulus:** inner (hole) radius `SWEEP_HOLE_RADIUS = 10`, outer radius
  `SWEEP_PLATFORM_RADIUS = 38`. Roblox has no annulus primitive, so the **collision floor is a
  segmented ring** of ~`SWEEP_PLATFORM_SEGMENTS = 28` anchored tangent boxes (the proven
  lobby-barrier/`WorldLayout.ring` trick) with length slack so segments overlap — **no gaps, no
  seam-catching**: segment top surfaces are coplanar (identical Y, identical size), so a body
  crossing a seam never trips.
- **Hub pillar:** radius `SWEEP_HUB_RADIUS = 5`, standing in the hole → the **gap ring**
  (r 5→10) is open void drop. The hub is non-walkable (`CanCollide` true but a sheer pillar).
- **Kill-plane:** `SWEEP_VOID_Y = SWEEP_SURFACE_Y - 24`.
- **Beams (physical):** two anchored box parts, hub-to-rim span (r 5→38), heights
  `SWEEP_BEAM_LOW_Y = 1.2` / `SWEEP_BEAM_HIGH_Y = 5.5` above the surface, cross-section ~1×1.
  High-beam clearance rule: 5.5 passes over a standing R15 body (~5.0 head at normalized scales)
  only when grounded — **verify the exact clearance live and tune** (`SWEEP_BEAM_HIGH_Y` is the
  knob; the strike-math `clears` rule stays authoritative regardless).
- **Cross-arena spacing:** hex rim (r≈30 + trim) to sweeper rim (r38 at x=110) leaves ~40 studs
  of void between arenas; a beam fling cannot realistically cross it. Noted, accepted.

**Spawns:** the `ArenaHazard` interface gains `spawnCFrame(index)`. Hex implements it with the
existing `HexGrid.spawnSlots` spiral (moved behind the interface, same output). Sweeper returns
slots on a mid-ring (`WorldLayout.ring` at radius ≈ (10+38)/2 = 24, up to `LOBBY_CAPACITY`
slots, facing the hub). `RoundManager.beginRound` re-assigns every participant's arena slot from
the **live** arena via a new `BodyManager.setArenaSlot(player, cf)` setter before `resetBody`
(BodyManager stays dumb; `sendToArena` rescue keeps working since it reads the same table).

---

## 4. Beams — physics + authority

**One source of truth for beam angles:** the pure `SweeperModel.beamAngle/rampedSpeed` (unchanged
from v1), evaluated from `elapsed = now - startClock` (server) — the server's Heartbeat animation,
the strike backstop, and the client's telegraph/wake cosmetics all derive from the same function,
so visuals, physics, and authority cannot desync.

- **Server animation:** `SweeperHazard` owns the two beam parts; a Heartbeat connection (running
  ONLY while this arena is live) sets each beam's CFrame from `angle(t)`. Anchored parts —
  replication interpolates for remote observers; the local player's own body collides against the
  replicated beam on their client → the natural shove.
- **Collision groups (server, PhysicsService):** groups `SweepBeam` and `GraceBody`, registered
  non-colliding. `RoundManager` already flips the `GraceProtected` attribute per body per tick;
  the same code path now also moves the body's parts between `Default` ↔ `GraceBody` groups
  (on-change only, mirrors the existing attribute discipline).
- **Backstop (anti-cheat + attribution):** the v1 strike math runs each monitor tick. A
  non-grace body whose polar position overlaps a beam arc for `SWEEP_RESIST_TICKS = 3`
  consecutive ticks (a normally-shoved body clears the arc in 1–2) is force-swept: hard outward
  re-pivot + `SweptAt` stamp (v1 machinery, unchanged). This also remains the guarantee that a
  physics-resisting exploiter still loses.
- **Validator handshake:** `step` returns `effects.reseeds = {body, ...}` for every body
  currently inside/near an arc (`arc half-width + SWEEP_RESEED_MARGIN`); RoundManager calls the
  existing reseed primitive for each, so a legitimate shove is never scored as a speed violation.
  Server-derived; no client input.
- **`effects` shape (v2):** `{ sweeps = {...v1...}, reseeds = { body, ... } }`. Hex returns both
  empty.

---

## 5. Persistent world + round rotation

- **Build:** `RoundManager.start()` builds **all** registered arenas once (`ArenaRegistry.all()`),
  each at its own center. `HexHazard/HazardSystem` is untouched (origin); `SweeperHazard` builds
  at `SWEEP_CENTER`.
- **Rotation:** a pure `ArenaRotationModel.next(currentId, arenaIds, override)` (lune-tested)
  picks the next round's arena — simple alternation; `override ~= ""` pins it.
  `RoundManager.beginRound` resolves `arena = ArenaRegistry.get(nextId)` — **the `arena` local
  becomes round-scoped**, replacing the v1 startup-resolved one. `voidY()`, `step`, spawn slots,
  grace/hazard gating all read the current round's arena (the monitor only runs during Active, so
  there is no between-rounds ambiguity).
- **Live signal:** `RoundManager` sets `workspace:SetAttribute("LiveArena", id)` at round start
  and `""` at round end. Server: gates beam animation. Client: gates every cosmetic loop + drives
  the dormancy flips. (One attribute, authoritative, mirrors the `GraceProtected` discipline.)
- **Config:** `ACTIVE_ARENA` is replaced by `ARENA_OVERRIDE` (`""` = rotate; `"hex"`/`"sweeper"`
  = pin). The client no longer selects an arena — it dresses **all** descriptors
  (`ArenaDescriptor.all()`) and starts the sweeper cosmetics unconditionally (they self-gate on
  `LiveArena`).
- **Lobby:** geometry unchanged; `LOBBY_FACE_TARGET` moves to the midpoint `(55, 0, 0)` so
  waiting bodies (and their cameras) face between the two arenas.

**Dormancy contract (idle arena):**
- Server: beam Heartbeat connection disconnected; beams parked at fixed rest angles.
- Client: the shared cosmetic loop skips every dormant arena's elements (zero writes/frame);
  on a `LiveArena` change it performs **one** standby/live flip: Neon transparency
  `SWEEP_STANDBY_TRANSPARENCY = 0.85` vs live values, chase lights off, light shaft dimmed,
  rotor rings stopped.

---

## 6. Client — `SweeperController` v2

The server now owns the beam parts, so the client **no longer builds beams**. It renders, in one
shared Heartbeat loop (gated on `LiveArena == "sweeper"`):

- **Floor telegraph:** a leading arc segment ahead of each beam (from the same `angle(t)`),
  colored by beam class.
- **Wake channels (the signature art beat):** `SWEEP_WAKE_CHANNELS = 36` thin radial Neon strips
  flush with the platform surface; the strips just behind the low beam **ignite amber and fade
  over ~1.2 s**. Implemented as per-strip target transparency from angular distance to the beam —
  only strips near a beam change per frame (bounded writes).
- **Hub rotor spin:** the two cosmetic rotor rings counter-rotate (live only).
- **Marquee chase:** rim studs ignite in a stepped chase pattern (live only, a few writes/tick).
- **Tumble:** unchanged v1 `SweptAt` watcher — now fires only on backstop sweeps.
- **Dormancy:** on `LiveArena` change, one flip to standby/live state; loop skips dormant work.

Budgets (hard lines, per the review's cosmetic-creep warning): ≤ **180 dressing parts** for the
sweeper, **one** shared Heartbeat loop, ≤ **40 part-writes per frame** typical (wake strips near
beams + chase step + 2 rotors).

---

## 7. Art direction — "Soul Turbine" (buildable element list)

The arena is a colossal broadcast-stage machine hanging in the Soul Festival Sky. Every element
below ships procedural-first; the two sourced-asset slots are Config-gated with fallbacks.

| Element | Build |
|---------|-------|
| **Platform** | Dark glass/metal annulus segments (deep indigo `#141A30`-family, `Glass`/`SmoothPlastic`), thin amber rim bevel. |
| **Wake channels** | 36 radial Neon strips inset in the top surface (§6) — the floor "remembers" the sweep. Legibility double-duty: where the beam just was → where it's going. |
| **Hub turbine** | The hero piece. Procedural: stacked core cylinder + two counter-rotating rotor rings + a bright Neon core; `SWEEP_HUB_MESH` Config slot for a sourced turbine mesh (fallback = the procedural build). |
| **Light shaft** | A translucent Neon column rising from below through the hole, `#F4A261` amber; dim on standby. The turbine visibly "draws" soul energy. |
| **Beams** | Server parts, Neon: low = amber `#F4A261`, high = crimson `#E14B4B`; distinct silhouettes (low = flat blade, high = raised bar on end-posts) so class reads by shape as well as color. |
| **Rim marquee** | 32 small Neon chase studs around the outer rim + a `WORLD_TRIM`-vocabulary accent ring — the broadcast "stage edge". |
| **Under-structure** | 4 angled conduit struts converging from below to the hub base + one lower ring — static geometry so the platform reads as built, not floating. |
| **Spotlights** | 3 angled stage-light fixtures (housing + Neon lens) aimed at the platform — static, no real lights. |
| **Materials** | `SWEEP_DISC_MATERIAL` / `SWEEP_BEAM_MATERIAL` Config slots (sourced via MCP, task-gated) with stock-material fallbacks. |

Palette: platform indigo + amber energy (low/shaft/marquee) + crimson (high beam only — danger is
always crimson, matching the hex warning-red convention) against the dusk sky. The high beam is
the ONLY crimson element so "don't jump" reads instantly.

---

## 8. Fairness & exploit posture

- **Grace:** physical pass-through (collision group) + backstop skip → a just-swapped body cannot
  be shoved or swept, full stop.
- **Resist exploit:** a client refusing the physics shove is caught by the 3-tick backstop →
  hard re-pivot. An exploiter still cannot win.
- **Shove vs validator:** reseed handshake (§4) — no rubber-band war; the validator still catches
  fly/teleport/speed everywhere else (reseeding near beams narrows coverage there; the backstop
  covers the beam zone).
- **Beam-shoves-into-players:** beams can push bodies into each other; body↔body collision policy
  is unchanged from the current game (the review's open collision-group decision) — out of scope.
- **Idle-arena griefing:** dormant arenas host no bodies (spawns always target the live arena);
  eliminated bodies still park on the balcony under movement validation.

---

## 9. Testing

- **Pure (lune):** `SweeperModel` suite unchanged (angles/strikes still authoritative);
  **new** `ArenaRotationModel` spec (alternation, override pin, unknown-id fallback);
  spawn-ring math reuses the already-tested `WorldLayout.ring`.
- **Studio MCP (now available):** geometry probes (annulus walkability incl. seam-crossing, gap
  ring drop, hub non-walkable), collision-group registration + grace pass-through, beam Heartbeat
  animation + parked dormancy, backstop trigger on a held body, per-round rotation + `LiveArena`
  flips, spawn slots on both arenas, hex regression (build at origin, rounds still run).
- **Manual 2-client smoke (rewritten doc):** shove feel + consistency under latency, high-beam
  clearance tuning, wake/telegraph readability after a swap cut, dormancy visual check from the
  lobby, resist-exploit case.

---

## 10. Scope

**v2 (this spec):** annulus platform + hub + gap ring; two solid stacked beams with Heartbeat
animation; collision groups + grace pass-through; strike backstop + validator reseeds; per-round
arena rotation + `ARENA_OVERRIDE`; `spawnCFrame` on the interface + per-round slot assignment;
`LiveArena` dormancy (server + client); Soul Turbine art pass (procedural complete + 3 sourced
asset slots via MCP); `ArenaRotationModel` + tests; rewritten smoke doc; roadmap/CHANGELOG.

**Deferred:** beam light-trails beyond the wake channels; concurrent matches; hex visual re-skin
(Slice 3); crumbling platform pressure; spectate-camera polish for lobby viewers.

## 11. Risks / open questions

1. **Anchored-CFrame beam shove feel** — the core bet. Anchored animated parts push via contact
   resolution (proven in classic Roblox sweeper obbies) but can feel "hard" rather than springy;
   if live feel demands it, escalate to a constraint-driven beam (server-owned assembly) as a
   follow-up — the angle source of truth would then become the physics state read back into the
   strike math (contained change, noted, not built now).
2. **High-beam clearance** (`SWEEP_BEAM_HIGH_Y`) vs jump apex — live tuning required.
3. **Replication smoothness** of the beam for non-owning observers at speed — verify at max ramp.
4. **Segmented-annulus seams** — coplanar overlap should be seamless; verify walking the full ring.
5. **Collision-group timing** — groups must be registered before any body parts get assigned;
   registration lives in `SweeperHazard.build()` (startup) to be safe.
