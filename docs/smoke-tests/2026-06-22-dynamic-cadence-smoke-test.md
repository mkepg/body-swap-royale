# Dynamic swap cadence smoke test (manual, 2-client Studio)

Validates that the swap interval is dynamic — it shrinks cycle-over-cycle — and that
the HUD countdown matches the actual swap timing. lune covers the pure `CadenceModel`
math (`tests/cadence_model.spec.luau`); this covers the `RoundManager` runtime wiring,
which lune can't reach. Run a **2-player local server** (Test → Clients and Servers →
2 → Start).

> **N=2 note:** with two players nobody is eliminated until the round ends, so the
> alive-count driver is inert and the ramp is carried entirely by the progress term
> (this is the case `CADENCE_STALL_WEIGHT = 1.0` exists to cover). The interval should
> still march 20s → 8s over successive swaps.

**Optional fast setup** (Server view, command bar) — keep the floor safe so a body
doesn't die before you've watched a few cycles:
`local C = require(game.ReplicatedStorage.Shared.Config); C.HAZARDS_ENABLED = false; C.LOBBY_COUNTDOWN_SECONDS = 2`

**Procedure & PASS criteria:**
1. **Round start.** After both clients join and the round begins, note the swap
   countdown shown on the HUD at the top of the first cycle — it should start near
   `CADENCE_MAX_INTERVAL` (20s).
2. **Interval shrinks.** Let several swaps fire without anyone dying. Each successive
   cycle's starting countdown should be **shorter** than the previous one (e.g. ~20 →
   ~18.5 → ~17 …), trending toward `CADENCE_MIN_INTERVAL` (8s). PASS = the countdown is
   visibly and monotonically decreasing across cycles.
3. **Floor holds.** After enough swaps (≈`CADENCE_SWAPS_TO_FLOOR` = 8), the starting
   countdown should sit at ~8s and not drop below it. PASS = it bottoms out at the
   floor, never lower.
4. **HUD matches the swap.** On any cycle, the swap (hard cut + FOV punch) fires when
   the countdown reaches 0 — the dynamic deadline and the HUD agree. PASS = no drift
   between the displayed countdown and the moment the swap happens.

To shorten the wait while testing, lower the envelope instead of the (now removed)
`CYCLE_SECONDS`, e.g.
`local C = require(game.ReplicatedStorage.Shared.Config); C.CADENCE_MAX_INTERVAL = 8; C.CADENCE_MIN_INTERVAL = 4`.
(Opts are read from Config each cycle, so the change takes effect on the next swap.)
