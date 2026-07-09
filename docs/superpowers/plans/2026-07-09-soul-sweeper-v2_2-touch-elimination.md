# Soul Sweeper v2.2 — Touch Elimination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beams instantly eliminate any non-grace player they touch (deterministic, no physics knockback); delete the backstop/reseed/tumble/collision-group machinery; add round-start grace.

**Spec:** `docs/superpowers/specs/2026-07-09-soul-sweeper-v2_2-touch-elimination-design.md` (read FIRST).

**Conventions:** as prior plans — lune suite green after every task (`export PATH="$HOME/.rokit/bin:$PATH"; for f in tests/*.spec.luau; do lune run "$f" || break; done`, 24 files). Commit per task, no Co-Authored-By.

---

## Task 1: `SweeperModel.isStruckSwept` (TDD)

**Files:** `src/shared/SweeperModel.luau`, `tests/sweeper_model.spec.luau`

- [ ] **Step 1 (failing tests):** REPLACE the `isStruckAt` and `outwardTarget` test blocks with:

```lua
-- isStruckSwept: swept-interval strike test on measured angles. A beam kills if its
-- arc CROSSED the body's angle since last tick (prevAngle -> angle along direction),
-- padded by the half-width; nil prevAngle or a >1 rad jump (re-park) falls back to
-- the instantaneous check.
do
	local function beam(prev, ang, dir, class)
		return { prevAngle = prev, angle = ang, direction = dir, class = class,
			innerRadius = 6, outerRadius = 52, angularHalfWidth = 0.15 }
	end
	local grounded = { radius = 30, angle = 0.3, airborne = false }
	-- bar swept 0.1 -> 0.5 (dir +1): body at 0.3 was crossed -> struck.
	expect(M.isStruckSwept(grounded, { beam(0.1, 0.5, 1, "low") }), "crossed body -> struck")
	-- same sweep but body at 0.8 (ahead, outside pad) -> safe.
	expect(not M.isStruckSwept({ radius = 30, angle = 0.8, airborne = false },
		{ beam(0.1, 0.5, 1, "low") }), "ahead of the sweep -> safe")
	-- airborne clears the low bar even when crossed.
	expect(not M.isStruckSwept({ radius = 30, angle = 0.3, airborne = true },
		{ beam(0.1, 0.5, 1, "low") }), "airborne clears low even when crossed")
	-- grounded clears the high bar even when crossed.
	expect(not M.isStruckSwept(grounded, { beam(0.1, 0.5, 1, "high") }),
		"grounded clears high even when crossed")
	-- direction -1: bar swept 0.5 -> 0.1; body at 0.3 crossed.
	expect(M.isStruckSwept(grounded, { beam(0.5, 0.1, -1, "low") }), "reverse sweep crosses too")
	-- wrap at the seam: bar swept (TAU-0.1) -> 0.1 (dir +1); body at 0.02 crossed.
	expect(M.isStruckSwept({ radius = 30, angle = 0.02, airborne = false },
		{ beam(TAU - 0.1, 0.1, 1, "low") }), "seam wrap crossed")
	-- re-park jump guard: span > 1 rad falls back to instantaneous -> body 1.5 away is safe.
	expect(not M.isStruckSwept({ radius = 30, angle = 1.5, airborne = false },
		{ beam(0, 3, 1, "low") }), "re-park jump cannot kill across the span")
	-- nil prevAngle: instantaneous only.
	expect(M.isStruckSwept({ radius = 30, angle = 0.05, airborne = false },
		{ beam(nil, 0, 1, "low") }), "first tick instantaneous hit")
	expect(not M.isStruckSwept({ radius = 30, angle = 0.5, airborne = false },
		{ beam(nil, 0, 1, "low") }), "first tick instantaneous miss")
	-- radius band still applies.
	expect(not M.isStruckSwept({ radius = 3, angle = 0.3, airborne = false },
		{ beam(0.1, 0.5, 1, "low") }), "inside hub radius -> safe")
	print("sweeper: isStruckSwept OK")
end
```

- [ ] **Step 2:** Run → FAIL. **Step 3:** In `SweeperModel.luau`, DELETE `isStruckAt` and `outwardTarget`; ADD:

```lua
-- Swept-interval strike test on MEASURED angles: did any beam's arc cross the body
-- since the last tick? beams[i] = { angle, prevAngle?, direction (+1/-1), class,
-- innerRadius, outerRadius, angularHalfWidth }. direction follows the system-wide
-- convention (+1 => measured angle increases; see SweeperHazard.motorTarget).
-- prevAngle == nil (first tick) or a sweep span > 1 rad (a re-park/teleport jump,
-- not real rotation) falls back to the instantaneous half-width check, so a parked
-- bar snapping home can never kill across the jumped arc.
function SweeperModel.isStruckSwept(body, beams)
	for _, beam in ipairs(beams) do
		if not SweeperModel.clears(beam.class, body.airborne)
			and body.radius >= beam.innerRadius and body.radius <= beam.outerRadius then
			local hit
			local span = beam.prevAngle
				and (((beam.angle - beam.prevAngle) * beam.direction) % TAU) or nil
			if span == nil or span > 1 then
				hit = SweeperModel.angularDistance(body.angle, beam.angle) < beam.angularHalfWidth
			else
				local o = ((body.angle - beam.prevAngle) * beam.direction) % TAU
				hit = o <= span + beam.angularHalfWidth or o >= TAU - beam.angularHalfWidth
			end
			if hit then
				return true
			end
		end
	end
	return false
end
```

- [ ] **Step 4:** PASS + full suite green. **Commit** `feat(sweeper-v2.2): pure isStruckSwept (anti-tunneling); isStruckAt+outwardTarget removed`.

## Task 2: Server — kill zones, effects v3, grace cleanup, round-start grace

**Files:** `src/shared/Config.luau`, `src/server/SweeperHazard.luau`, `src/server/ArenaHazard.luau`, `src/server/HexHazard.luau`, `src/server/RoundManager.luau` (read each fully first)

- [ ] **Step 1 Config:** DELETE `SWEEP_OFF_MARGIN`, `SWEEP_RESIST_TICKS`, `SWEEP_RESEED_MARGIN`, `SWEEP_TUMBLE_SECONDS`, `SWEEP_BEAM_DENSITY` (and their comments). Update the sweeper block's header comment: beams are deterministic touch-elimination zones (non-collidable; strike = death via the grace-gated hazard chokepoint).
- [ ] **Step 2 SweeperHazard:** delete `ensureCollisionGroups` (+ its call) and `strikeTicks`; in `buildBeamAssembly` set every part `CanCollide = false`, remove all `CollisionGroup` assignments and the root's `CustomPhysicalProperties`; update the module doc header (touch = elimination; motors are visual). In `step`: keep the motor-target refresh; maintain `rec.prevAngle` (read measured angle, build the beams table `{ angle, prevAngle, direction = rec.beam.direction, class, innerRadius, outerRadius, angularHalfWidth }`, then store `rec.prevAngle = angle` after building); replace the reseed scan + backstop with: for each on-platform, non-grace sample, `if SweeperModel.isStruckSwept(bodyPolar, beamsNow) then eliminations[#eliminations+1] = s.player end`; return `{ eliminations = eliminations }` on ALL paths. `stop()`: also `rec.prevAngle = nil` for every rec (pairs with the span guard across re-parks).
- [ ] **Step 3 contract:** `ArenaHazard.luau` doc → effects = `{ eliminations = { player, ... } }`; `HexHazard.luau` `EMPTY`/step return → `{ eliminations = {} }`.
- [ ] **Step 4 RoundManager:** replace the sweeps+reseeds application block with:

```lua
			-- Beam touch = elimination (spec 2026-07-09 v2.2): route each struck player
			-- through the SAME grace-gated chokepoint as void death. Deterministic server
			-- math on server-owned physics state -- no knockback, nothing to desync.
			if effects and effects.eliminations then
				for _, p in ipairs(effects.eliminations) do
					RoundManager.eliminateFromHazard(p)
				end
			end
```

  DELETE `setGraceCollision` + `clearAllGraceCollision` and every call site (stampGrace, monitor on-change, eliminate, both round boundaries). REVERT the floor probe's `params.CollisionGroup = "GraceBody"` line + its comment (non-collidable bars are ignored by `RespectCanCollide` rays natively — leave a one-line comment saying exactly that). ADD round-start grace in `beginRound`, after `ControlManager.resetControl()`:

```lua
	-- Round-start grace (2026-07-03 review recommendation, now load-bearing: beams
	-- kill on touch, so every player gets the standard orient beat before the bars
	-- -- or the hex tiles -- can hurt them).
	local participants = {}
	for player in pairs(roundParticipants) do
		participants[#participants + 1] = player
	end
	stampGrace(participants)
```

  (Check `stampGrace` ordering: it must run AFTER bodies are on their spawn slots and control is granted — verify against the actual beginRound sequence; `stampGrace` records controlled-body positions for the has-moved check.)
- [ ] **Step 5:** grep: zero refs to deleted keys/functions (`SWEEP_OFF_MARGIN|SWEEP_RESIST_TICKS|SWEEP_RESEED_MARGIN|SWEEP_TUMBLE_SECONDS|SWEEP_BEAM_DENSITY|setGraceCollision|clearAllGraceCollision|GraceBody|SweepBeam"|isStruckAt|outwardTarget|reseeds|sweeps`) — `GraceBody`/`SweepBeam` may remain ONLY if some non-collision-group usage exists (there shouldn't be any). Suite green. **Commit** `feat(sweeper-v2.2): touch-elimination server path; backstop/reseeds/collision-groups deleted; round-start grace`.

## Task 3: Client + docs

**Files:** `src/client/SweeperController.luau`, `src/client/init.client.luau`, `src/client/ClientControl.luau`, `CHANGELOG.md`, `docs/world-enrichment-roadmap.md`, `docs/smoke-tests/2026-07-08-soul-sweeper-v2-smoke-test.md`

- [ ] **Step 1:** SweeperController: delete `watchTumble` entirely; `start(getOwnBody)` → `start()` (delete the parameter + its call); doc-header updated (touch = elimination; no tumble). `init.client.luau`: `SweeperController.start()` (no argument). `ClientControl.luau`: delete `getBody()` (it existed solely for the tumble — confirm no other caller via grep).
- [ ] **Step 2:** Docs: CHANGELOG `## [2026-07-09]` gains a v2.2 entry (touch elimination, deletions list, round-start grace incl. the hex side effect); roadmap line updated; smoke doc — retire/rewrite the contact cases: case 4 (shove feel) → replaced by "touch = instant elimination, both bars, jump/stand rules"; case 7 (backstop) → retired; case 11 (reseeds) → retired (validator now fully active everywhere — new case: no rubber-banding anywhere on the platform during normal play); case 12/13 (fling/stall) → retired; add a case: round-start grace beat (players spawned in a bar's path survive the first 1.5 s on BOTH arenas; hex spawn tiles don't arm during it).
- [ ] **Step 3:** Suite green; grep client for `SweptAt|watchTumble|getBody` (zero). **Commit** `feat(sweeper-v2.2): client tumble removed + docs`.

## Task 4 (CONTROLLER-EXECUTED, MCP): live verification

Boot clean (both arenas); beams `CanCollide=false`, no CollisionGroup, no PhysicsService groups registered... (groups may persist from prior sessions in the place — registration is gone from code; verify code-side only); motors still spin (drive hinge directly, measured rate matches sign convention); hex regression; round-start grace: can't start a round solo — verify `stampGrace` call presence + rely on 2-client. Record results; commit.

## Self-review notes
- Spec §2 → T1 (3), T2 (1,2,4,5,6,7), T3 (5-client, 8-docs), T4 (verification). §3 → T1. §4 → T2/T3.
- Consistency: `isStruckSwept` beam fields set in T2 step 2 match T1's signature; `eliminations` produced T2, consumed T2 (RoundManager); prevAngle cleared in stop() pairs with the span guard; `stampGrace` exists in RoundManager (verify list-arg shape — it takes an array of players).
