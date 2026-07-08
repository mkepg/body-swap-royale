# Soul Sweeper — Manual Smoke Test (2026-07-07)

**Requires:** `Config.ACTIVE_ARENA = "sweeper"`. Studio Play (single-client for geometry;
2-client for the swap + latency cases). Beams cosmetic; strikes server-side.

## Setup
1. Set `Config.ACTIVE_ARENA = "sweeper"`. Sync with Rojo, Play.
2. Confirm boot: no console errors; `Workspace.SweeperField` has `SWEEP_TIER_COUNT` discs +
   hubs; discs WIDEN downward; no Baseplate; `Workspace.SweeperBeams` renders rotating bars.

## Cases
1. **Geometry / orientation** — each tier is a distinct color; the bottom disc is widest;
   the kill-plane (`SWEEP_VOID_Y`) sits ~4 studs under the bottom disc.
2. **Beam sync** — a low (amber) bar and a high (red) bar rotate; the faded telegraph leads
   each beam in its rotation direction; lower tiers visibly sweep faster; speed ramps over
   the round.
3. **Low beam = jump** — stand grounded in a low beam's path → swept off (re-pivoted outward)
   → caught by the wider tier below. Jump as it passes → survive.
4. **High beam = stay grounded** — stand grounded under a high beam → survive; jump into it →
   swept off.
5. **Descent + void death** — get swept off the bottom disc → fall past `SWEEP_VOID_Y` →
   eliminated (Elimination event fires; body sent to balcony). Swept off an UPPER disc →
   land on the tier below, still alive.
6. **Grace immunity (observe-first)** — immediately after a swap (or round start), a body in
   a beam's path is NOT swept for the grace window; after grace, normal rules resume.
7. **Cosmetic tumble** — on a sweep, the body plays a brief spin; it does not desync position
   (server owns the outcome).
8. **Swap-onto-incoming-beam** — 2-client: force swaps (`RoundManager.forceSwap()`); confirm a
   player dropped near a beam gets the grace beat and can react; note the inherited-hit feel.
9. **Exploit** — a client holding position in a beam is still swept (server-authoritative);
   movement validator does not fight the sweep (no rubber-band war).

## Results

### 2026-07-07 — Studio MCP Play-Solo verification (deterministic server-side pass)

Verified via the Roblox_Studio MCP against a running Play-Solo server (place had current Rojo
source synced: all new modules present, `SWEEP_VOID_Y=-104`, `SWEEP_TIER_COUNT=3`). Because
Play-Solo is single-client and the round can't reach an Active multiplayer state
(`MIN_PLAYERS_TO_START=2` / `MIN_PLAYERS_TO_CONTINUE=2`), the integrated round + client visuals
stay a manual 2-client gate — but the highest-risk items were confirmed deterministically by
building the real `SweeperHazard` geometry in the server VM and driving `step()` with crafted
samples:

- **Hex regression (case: interface refactor safe):** ✅ Clean boot, no console errors; `HexField`
  built with **2135 parts** through the new `ArenaHazard` interface; round correctly held in Lobby
  at 1 player. Hex path behaves as before.
- **Case 1 — geometry:** ✅ 3 discs, radii **26 / 36 / 46 widening downward**, top surfaces at
  **Y 0 / −50 / −100**, all collidable. `SWEEP_VOID_Y=−104` (4 below the bottom disc).
- **Cylinder disc orientation (spec §13 risk #2):** ✅ RESOLVED. Downward raycast (RespectCanCollide)
  on the top disc hit `SweepDisc_0` at **Y=0 with normalY=1** (flat, up-facing, standable); an
  unanchored test part dropped onto it **rested at Y≈1.0** on the surface.
- **Case 5 — descent catch geometry:** ✅ A probe past the top rim (r=31, inside the mid disc's
  r=36) hits `SweepDisc_1` at **Y=−50** (swept off an upper disc lands on the wider tier below);
  a probe past the bottom rim (r=50) hits **nothing → the void**.
- **Cases 3, 4, 6 — strike/sweep/grace/airborne rules** (driven through the real `SweeperHazard.step`
  against live geometry + real Config, 5 crafted samples): ✅ all correct —
  grounded-under-low → swept outward to (30,0); same but `graceBlocked` → **no sweep** (grace
  immunity); same but airborne → **clears the low beam**; grounded-under-high → **survives**
  (stay-grounded rule); airborne-into-high → swept to (−30,0).
- **`SweeperModel`** loads and runs correctly in the live Roblox VM.

**No tuning changes were needed** for the measured items (the airborne threshold `SWEEP_AIRBORNE_VY=8`
is far below a real jump's launch velocity, and all strike cases resolved correctly).

### Still MANUAL (2-client, needs a real network session) — NOT yet verified
- Case 2 (beam sync visuals + telegraph + speed ramp on-screen), Case 7 (cosmetic tumble render),
  Case 8 (swap-onto-incoming-beam feel + inherited-hit rate), Case 9 (exploit: client holding
  position still swept, no rubber-band war), and live tuning of beam speeds / airborne bands / feel
  during an actual Active round. `screen_capture` can't see the client beams/PlayerGui, and Play-Solo
  can't start an Active multiplayer round — so these require a 2-client Studio session.
- Task 14 (hybrid asset sourcing: disc/beam materials + hero hub mesh) remains pending; the
  procedural fallback is what was verified above.
