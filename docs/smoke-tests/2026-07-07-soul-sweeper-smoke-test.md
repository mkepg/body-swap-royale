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
(Fill in during the session; note any tuning changes to SWEEP_* Config values.)
