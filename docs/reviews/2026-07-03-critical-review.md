# Body Swap Royale — Critical Engineering & Game-Design Review

**Date:** 2026-07-03
**Reviewer stance:** skeptical principal engineer + game-design director. This is a review, not a validation: every verdict below was reached by challenging the current design first.
**Evidence base:** full read of `src/`, design docs (GDD/TDD v1.3, world-enrichment roadmap, all specs/plans), CHANGELOG, smoke-test docs; all 18 lune suites executed and passing (verified this session); **live Studio session (solo Play)** used to verify boot, arena geometry, the contact probe, and the server-pivot replication question. Claims that still require a 2-client/latency environment are marked **[needs 2-client verification]**.

**Classification legend:** `[Root-cause fix]` `[Workaround — needs proper solution]` `[Symptom hidden]` `[Missing system]` `[Unjustified complexity]` `[Debt: justified?]`

---

## 1. Executive Summary — highest-leverage issues

Ranked by impact × likelihood × cost-to-fix-later.

| # | Issue | Verdict | One line |
|---|-------|---------|----------|
| 1 | **Client-authoritative movement with zero server validation** | **REDESIGN** (add the validation layer, keep the ownership model) | An exploiter literally cannot lose a round today (fly/teleport = safe camping above the void check); this blocks any playtest with strangers. |
| 2 | **Grace-as-timer + predictable swap moment = pre-swap suicide hand-off (documented, unfixed)** | **REPLACE** (timer stays, but handoff-at-rest + doom-exclusion become the real fix) | The project's own spec proves timer-only grace is *architecturally incapable* of protecting the victim; the fix is designed, reviewed, and sitting unbuilt while cosmetic slices ship. |
| 3 | **Persistence has no session locking; `UpdateAsync` ignores the stored value** | **REDESIGN before multi-server** | Last-write-wins is fine for one Studio server and silently loses currency the day two servers exist; `BindToClose` also saves serially and can blow the 30s budget under retries. |
| 4 | **The character-less foundation is right, but it stands on undocumented `PlayerModule` internals** | **KEEP the model / fix the dependency** (vendor the PlayerModule) | `moveFunction` override, `controls.humanoid` pokes, and a priority-2000 `Jump` re-assert all break silently on any Roblox controls refactor. |
| 5 | **A load-bearing replication pattern ("reposition-then-re-own") is applied inconsistently** | **MAKE UNIFORM** (severity downgraded after live test) | Live probe: a server pivot on a client-owned *idle* body replicated and stuck without re-owning — so `sendToLobby` likely works and the re-own is hardening. But the real elimination case pivots a *fast-falling* body under latency; make the pattern uniform either way. **[needs 2-client verification]** |
| 6 | **The grace shield shimmer is a client-side guess that desyncs from the server's grace gate** | **REDESIGN (small)** | Inherited momentum ends server grace early while the shimmer keeps pulsing — players will die *inside a visible shield*, which is worse for perceived fairness than no shimmer at all. |
| 7 | **RoundManager is a 533-line module-level singleton and the only untested layer** | **KEEP for MVP / decompose before arena #2** | The pure/glue split is genuinely excellent, but every recent bug (contact arming, disconnect strand, doom hand-off) lives in the glue, which is covered only by 13 *manual* smoke-test documents. |
| 8 | **Roadmap order: world dressing has outpaced fairness, anti-cheat, and the economy sink** | **RESEQUENCE** | Two full cosmetic slices shipped while the known kill-exploit, movement validation, the swap preview's danger read, and any coin sink remain open. |

---

## 2. Per-System Deep Dives (engineering)

### 2.1 ControlModel / SwapController / ControlManager — the swap core

**Steelman.** This is the strongest subsystem. The bijection invariant is explicit and machine-checked ([ControlModel.luau:49-65](../../src/shared/ControlModel.luau#L49-L65)), plan/commit separation gives a truthful preview ([ControlModel.luau:73-117](../../src/shared/ControlModel.luau#L73-L117)), the disconnect absorb rule is a real root-cause fix for the body-lifecycle/control-map entanglement, and all of it is lune-tested. Sattolo ([ControlModel.luau:19-25](../../src/shared/ControlModel.luau#L19-L25)) is O(n), retry-free, and correct at n=2.

**Challenges.**

- **Sattolo is not uniform over derangements — it samples only single n-cycles.** For n=4 there are 9 derangements; Sattolo can produce only the 6 four-cycles and never the 3 double-transpositions (A↔B, C↔D). Consequence: for n≥3, *mutual swaps never happen*. Is that a problem? Practically no — players can't observe the cycle structure in one round, and single-cycle guarantees maximal "everyone displaced." Verdict: **keep**, but document the non-uniformity in the TDD (§2 currently implies "derangement" generically), because a future "swap partner" feature or telemetry on swap graphs would silently inherit this bias. `[Debt: justified]`
- **The commit can silently diverge from the preview.** `commitSwap` recomputes over the live roster when the plan went stale ([RoundManager.luau:184-198](../../src/server/RoundManager.luau#L184-L198)) — correct for the bijection, but the recomputed plan is committed *without re-firing `SwapPreview`*, so a player can inherit a body they were never shown. The mid-preview re-plan loop ([RoundManager.luau:387-401](../../src/server/RoundManager.luau#L387-L401)) narrows this to the last ≤0.25s, but the hole exists precisely at the moment (a death during preview) when the swap is most chaotic. Cheap fix: fire the preview once more on the recompute path, even if it lands ~0ms before the cut — or accept and document that the preview is best-effort in churn. `[Symptom hidden — the preview's truthfulness claim is weaker than documented]`
- **`applyOwnership` swallows `SetNetworkOwner` failures in a bare `pcall`** ([ControlManager.luau:44-52](../../src/server/ControlManager.luau#L44-L52)). If the call fails (anchored root, body mid-destroy), the model says player P controls body B while physics ownership says otherwise — the exact desync class the absorb rule was built to prevent, hidden by error suppression. At minimum `warn` on failure; better, return the failure so RoundManager can re-try or re-plan. `[Symptom hidden]`

### 2.2 RoundManager — the glue

**Steelman.** The decision/side-effect split is disciplined: RoundState decides *who/when*, ControlModel decides *the map*, GraceModel decides *protection*, and RoundManager only sequences clocks and Roblox calls. The `hasValidBody`/`eligibleSet` guards ([RoundManager.luau:91-137](../../src/server/RoundManager.luau#L91-L137)) show real defensive maturity.

**Challenges.**

- **Module-level singleton state everywhere** (`model`, `grace`, `swapPos`, cadence counters, economy counters, `monitorToken` — [RoundManager.luau:41-69](../../src/server/RoundManager.luau#L41-L69)). The world-enrichment roadmap's own premise is multiple arenas; the TDD (§5) already prescribes the `new()` pattern "when RoundManager introduces multiple round instances." Fine for MVP — but note the same singleton shape also infects `HazardSystem` (one `tiles` array, one `workspace.HexField`), `BodyManager`, and `ControlManager`, so "arena #2" is a cross-cutting refactor, not a RoundManager patch. Budget it as one deliberate decomposition, not incremental patching. `[Debt: justified now, priced wrong later]`
- **Elimination path skips the re-own step.** `RoundManager.eliminate` calls `BodyManager.sendToLobby` ([RoundManager.luau:224-227](../../src/server/RoundManager.luau#L224-L227)), which pivots a **client-owned** assembly from the server ([BodyManager.luau:189-207](../../src/server/BodyManager.luau#L189-L207)) — and unlike `beginRound` (`resetBody` → `resetControl`) and the disconnect rescue (`sendToArena` → `regrantControl`, [RoundManager.luau:490-494](../../src/server/RoundManager.luau#L490-L494)), it never re-asserts ownership afterward. The codebase's own comments state the re-own exists "so the teleport replicates onto the client-owned body" ([ControlManager.luau:100-103](../../src/server/ControlManager.luau#L100-L103)). **Live test (this review, solo Play):** a server `PivotTo` on the client-owned, idle body replicated correctly and *stuck* on both server and client with network ownership unchanged — so the mechanism works in the benign case and the re-own reads as hardening, not necessity. The unexercised case is the real elimination scenario: a body *falling at speed* whose owning client is actively streaming physics under real latency — the exact condition that presumably motivated the re-own pattern. Make the pattern uniform (add the re-own to `sendToLobby`; it's one call and provably harmless) rather than carrying two beliefs about the same primitive. `[Workaround applied inconsistently]` **[needs 2-client verification for the falling case]**
- **The GDD's simultaneous-death rule is not implemented.** GDD §4 promises "most recently swapped-into body is eliminated first"; in practice the winner of a same-tick double-death is decided by `Players:GetPlayers()` iteration order in the monitor loop ([RoundManager.luau:257-289](../../src/server/RoundManager.luau#L257-L289)) — the first body found below `VOID_Y` triggers `maybeEnd`, and the second elimination no-ops because the phase already left Active. Low frequency, but it decides *round wins*. Either implement the rule (sort the tick's deaths by swap timestamp before eliminating) or delete it from the GDD. `[Missing system, small]`
- **Leavers get nothing from the round economy** — `PlayerRemoving` runs `RoundManager.removePlayer` then `EconomyService.onPlayerRemoving` (save + drop) immediately ([init.server.luau:31-34](../../src/server/init.server.luau#L31-L34)), while `endRound`'s award runs later on the round loop thread and hits a nil profile ([EconomyService.luau:97-100](../../src/server/EconomyService.luau#L97-L100)). Defensible (anti-rage-quit), but it's an accidental policy, not a chosen one — decide it deliberately, because "I disconnected at the results screen and got nothing" is a support-ticket generator.

### 2.3 GraceModel + the void monitor

**Steelman.** The pure model matches TDD §2 exactly and is trivially testable. Routing *all* hazard deaths through one `eliminateFromHazard` gate is the right chokepoint, and reusing the same gate to block tile-arming ([RoundManager.luau:279-283](../../src/server/RoundManager.luau#L279-L283)) is elegant.

**Challenges.**

- **`hasMoved` is derived from horizontal drift, so the server cannot distinguish "player oriented" from "body carries inherited momentum" or "body got shoved"** ([RoundManager.luau:263-271](../../src/server/RoundManager.luau#L263-L271)). The GDD explicitly says being pushed should *not* end grace; this implementation ends it. This is Layer 1 of the doom spec and it is a **real correctness gap today**, not just under griefing. Root cause: the server is inferring input from position because it has no input signal. The right fix is already in the doom spec — **zero velocity at handoff** so drift after a swap *is* input — optionally plus a client "first input" remote (cheat-bounded: lying only extends protection to the existing 1.5s cap). `[Symptom hidden]`
- **Grace is stamped only on swaps, never at round start** ([RoundManager.luau:151-159](../../src/server/RoundManager.luau#L151-L159) is only called from `commitSwap`). Combined with contact-arming, every player's spawn tile arms the instant the round begins, giving ~1.2s to move at t=0 with no intro beat (GDD §4 promises a 3s pre-round). Cheap, high-feel fix: stamp a grace window in `beginRound` too — it reuses the exact existing machinery and restores the missing intro beat.

### 2.4 HazardSystem (Hex-A-Gone)

**Steelman.** This is a well-earned design. Erosion decisions are pure and monotonic (`HexErosionModel`), death stays geometric (fall past `VOID_Y` — no new death path), the contact probe (downward spherecast, include-filtered to the HexField, `RespectCanCollide=true`, [HazardSystem.luau:160-166](../../src/server/HazardSystem.luau#L160-L166), [211-239](../../src/server/HazardSystem.luau#L211-L239)) is *current-state* rather than memory-based — the same property that made the doom-spec reviewer reject last-safe-position rescue. The `-0` axial-key bug fix with a `tostring` regression test shows real debugging rigor. Cost at scale is a non-issue: ≤16 spherecasts + one sweep of ~476 tile records per 0.1s tick, with property writes only on phase change.

**Challenges.**

- The 5-part wedge-composed tile is itself labeled a **fallback** for the EditableMesh path that silently no-ops because a Studio security setting is off (CHANGELOG 2026-06-25). That's 5× the parts (**2,135 anchored parts, measured live: 427 tiles at 61/floor** — vs 427 as MeshParts) and a permanently more complex build path, retained *alongside* the unused `HexPrism` module. Pick one: either enable Mesh/Image Access and delete the wedge path, or declare stock-parts the permanent answer and delete `HexPrism` (still shipped and tested but dead). Carrying both is `[Unjustified complexity]` — small, but it's exactly how codebases silt up.
- **The contact-probe geometry was verified live this session** (solo Play, probing the built arena with HazardSystem's exact parameters): (a) a body standing on the **center tile** — the historical `-0` bug tile — hits `Hex_0_0_0_B` at exactly the expected distance; (b) a probe over the grout seam between tiles hits an adjacent tile's wedge (either neighbor is a valid arm target, as documented); (c) with a tile's parts set `CanCollide=false` (gone), the probe returns nil via `RespectCanCollide` — vanished tiles can't re-arm, and the 6-stud band correctly does *not* reach the floor 50 studs below; (d) bonus: the **doom-exclusion spec's deep probe** was prototyped live — with the center tile gone, a root→`VOID_Y` ray passes through the hole and finds `Hex_1_0_0_B` at y=−50, empirically confirming the spec's core "losing a tile is not a death" claim. What remains unverified is the *full arming loop* (monitor-driven sampling + grace gating during an Active round), which needs a 2-player session. **[needs 2-client verification for the loop, geometry confirmed]**
- `HazardSystem.step` recomputes `durations()` and re-checks `Config.HAZARDS_ENABLED` per tick — fine, deliberate for command-bar tuning; no action.

### 2.5 Economy & persistence

**Steelman.** The layering is textbook: pure `RewardModel`/`ProgressionModel`/`ProfileModel` (level derived from totalXp — migration-free curve changes, a genuinely good call), a dumb `ProfileStore` wrapper, and a service that owns the cache. No-clobber-on-failed-load (`persisted=false`) prevents the classic "outage wipes profiles" disaster. Currency math is 100% server-side; the client only renders. **There are zero client→server remotes in the entire game** ([Remotes.luau:17-21](../../src/shared/Remotes.luau#L17-L21)) — the remote attack surface is literally nil, which is a rare and excellent property.

**Challenges.**

- **No session locking, and `UpdateAsync` discards the stored value** ([ProfileStore.luau:46-49](../../src/server/ProfileStore.luau#L46-L49) — the transform ignores its argument and returns the session profile). The comment owns it ("single-server MVP; last write wins"), and for the current 2-friend Studio phase it *is* justified. But the failure mode is silent currency loss on server hop (leave server A → join B while A's retry-backed save is in flight → B loads stale → whoever saves last wins), and it gets *harder* to migrate the longer real player data accumulates. This is SE-1 territory: adopt ProfileService/ProfileStore (community) or implement lock-key + merge-in-transform **before any public listing**, not after. `[Debt: justified now, with a hard expiry]`
- **`BindToClose` saves serially** ([EconomyService.luau:130-135](../../src/server/EconomyService.luau#L130-L135)): 16 players × up to 3 attempts × backoff (1s, 2s waits) is far beyond the ~30s shutdown budget in a DataStore brownout — precisely the scenario BindToClose exists for. Fix is mechanical: `task.spawn` each save, count completions, wait on the counter. `[Missing system, small]`
- **Coins have no sink.** The full earn loop shipped (awards, HUD, XP fill animation — polished!) with nothing to buy. Earning currency that can't be spent is worse than neutral for retention: it teaches players the number is meaningless. The first sink (see §6) should outrank further world dressing.

### 2.6 Client control stack (`InputController` / `ClientControl`)

See §3.1 — this is the foundational-call discussion.

### 2.7 Client presentation (HUDs, Soul, animator, world)

**Steelman.** Display decisions are pure and tested (`RoundScreenModel`, `SwapTelegraphModel`, `XpFillModel`, etc.); renderers are thin; HUD zones/fonts centralized in `HudTheme`; the countdown targets `swapAtServerTime` via `GetServerTimeNow()` (correct clock); mobile got real care (GUI inset respected, landscape lock at the right layer, corner placement reasoned about — [ClientEconomyHud.luau:54-64](../../src/client/ClientEconomyHud.luau#L54-L64)).

**Challenges.**

- **The grace shimmer lies.** `SoulController.playGraceShimmer` approximates the window from *local input* ([SoulController.luau:101-144](../../src/client/SoulController.luau#L101-L144)), while the server ends grace on *horizontal drift* ([RoundManager.luau:263-271](../../src/server/RoundManager.luau#L263-L271)). Inherited momentum (the doom-spec Layer 1 case) ends real grace almost immediately while the shimmer pulses on — the player dies visibly shielded. A fairness feature that misreports protection actively damages the trust it was built to create. Fix: replicate the authoritative window (send `graceUntil`/grace-ended alongside `SetControlledBody`, or an attribute on the body) instead of guessing. Bundling this with velocity-zero handoff makes the local guess nearly correct anyway — but replicate it regardless; cosmetic state that shadows authoritative state should be *fed* by it, not re-derived. `[Symptom hidden]`
- **`ClientAnimator.register` never retries.** If a body's Humanoid hasn't replicated one frame after `ChildAdded` (`task.defer`, [ClientAnimator.luau:105-107](../../src/client/ClientAnimator.luau#L105-L107)), `loadTracks` returns nil and that body is *never* animated on that client for the session — the "self-healing" claim covers stopped tracks, not failed registration. Same class of late-replication bug the project already fixed twice in `ClientControl` (its comment even says so). Retry until the humanoid appears. `[Missing system, small]`
- **The swap preview is ~40% of its design.** Shipped: target-body Highlight ([SwapPreviewController.luau:30-41](../../src/client/SwapPreviewController.luau#L30-L41)). Missing from GDD §5: the directional ping (the target is frequently *behind the camera* — a Highlight you can't see is not a preview) and the amber danger read (the entire "readable challenge, not a dice roll" argument rests on it). This isn't polish; it's the load-bearing half of the fairness thesis. 
- WorldShell/LobbyStage per-frame cosmetic loops (~70 part `Position`/`Size` writes per Heartbeat) are fine today; set a budget line now (the roadmap's "Ambient Life" slice will want to add more of these).

### 2.8 Testing & developer workflow

The pure-core/lune discipline is the best thing in this codebase: 18 suites, all passing, runnable in seconds from the terminal, with real regression tests for real bugs (the `-0` case). The Rojo + rokit + spec-plan-smoke pipeline is coherent and the decision history is unusually well preserved.

The gap: **every recent defect lived in the glue, and the glue's only coverage is 13 manual smoke-test documents.** That burden compounds — each new system adds a manual procedure, and nobody re-runs 13 procedures per change, so regressions in RoundManager/ControlManager sequencing will ship. Two moves, in order of value:
1. **Extract the round loop's *sequencing decisions* into a pure reducer** (phase, deadlines, plan/re-plan/commit decisions as data, driven by injected time/events) so lune can test "death during preview → re-plan → commit" without Studio. RoundManager keeps only Roblox calls.
2. **A bot-driven Studio harness** (server-side scripted humanoids + MCP `execute_luau` assertions) to automate the highest-value smoke tests (swap/absorb/eliminate/strand). Cheaper than it sounds; pays for itself by the third re-run.

Also: doc rot is starting — GDD §13 still says "RoundManager not implemented," GDD §4 still says fixed 30s cycles (the shipped dynamic 20→8s cadence is a *design* change that never made it back into the design doc), TDD says the grace visual is deferred (it shipped). The docs are this project's institutional memory; a stale GDD quietly poisons future design reviews.

---

## 3. Architecture & Networking — the foundational calls

### 3.1 Character-less bodies (`CharacterAutoLoads = false`) — **KEEP, with one structural change**

The prompt demands this be pressure-tested rather than assumed. Doing so:

**The case against:** the project is in a permanent guerrilla war with the platform. StreamingEnabled must stay off (no focus). The touch HUD, TouchJump, and `Player:Move` all assume a Character; the fixes ([InputController.luau:51](../../src/client/InputController.luau#L51) `moveFunction` no-op, [82-84](../../src/client/InputController.luau#L82-L84) `OnCharacterAdded(body)` with a non-Character model, [106-118](../../src/client/InputController.luau#L106-L118) a touch-only jump button whose input is re-asserted at `RenderPriority.Last` every frame to out-write the ControlModule) each reach into **undocumented PlayerModule internals**. Health/death, the reset button, seats, tools, proximity prompts, player-list integration — every Character-keyed platform feature will need a bespoke answer forever.

**The case for (and why it wins):** the two alternatives were *tested and falsified*, not assumed — server-routed input added 0.3–0.6s of feel-killing latency, and `Player.Character` reassignment **synchronously destroys the previous body**, which is fatal to a derangement over persistent avatar-bodies (TDD revision history). The remaining alternative — a **hidden dummy Character** parked off-map purely to pacify PlayerModule — deserves the hard look the prompt asks for: it would un-gate the default touch HUD and TouchJump "for free." But it fails on inspection: the dummy is never the controlled body, so *all* of the custom camera/movement/animation layer remains; the touch HUD would bind to the dummy's humanoid (wrong humanoid — you'd re-point it at the real body, which is exactly today's `ensureControls`); it resurrects Reset-button/respawn/Died plumbing for a body that must never be seen; and with streaming off, its one real gift (a streaming focus) buys nothing. The dummy adds a second body-like entity with its own failure modes to remove approximately none of the existing code. **Character-less is the right foundation.**

**But the PlayerModule dependency is a `[Workaround — needs proper solution]`.** Three internals (`moveFunction`, `controls.humanoid`, `OnCharacterAdded`'s tolerance of non-Characters) can change in any Roblox release, and the failure mode is "mobile players silently lose controls in production." The proper fix is standard practice: **vendor (fork) the PlayerModule into the project** so the referenced internals are frozen, and adapt it once — delete the Character gating instead of spoofing around it. One-time cost, permanent de-risk, and it *deletes* the jump-reassert hack rather than defending it.

### 3.2 Client-authoritative movement — **KEEP ownership, but validation is not optional and not "Beta"**

The ownership-transfer model is correct for feel and is the only latency-acceptable design given the falsified alternatives. But the current exploit surface, concretely:

- **Fly/hover:** the *only* death check is `root.Position.Y < VOID_Y` at 10Hz ([RoundManager.luau:285-287](../../src/server/RoundManager.luau#L285-L287)). A client that holds its body's Y never dies. Guaranteed win, every round.
- **Teleport camping:** teleport your body to the lobby balcony (Y=64) or anywhere off-arena; nothing observes "body left the arena volume." Same result with less effort.
- **Post-elimination interference:** an eliminated player *keeps network ownership* of a body on the balcony (§2.2); a teleport puts that body back in the arena as a physical griefing tool (shoving, blocking) that the round logic no longer watches.
- **Speed:** WalkSpeed is a client-owned humanoid property in effect; nothing bounds displacement per tick.
- Additionally, alive bodies collide with each other while being simulated by *different* clients — shove-griefing is possible in a "combat-free" game, and cross-owner contact resolution is janky by nature. Decide deliberately whether body↔body collision belongs in this game (a collision group turning it off is one line and also removes the eliminated-ghost-body vector).

The TDD already classifies validation "load-bearing from MVP" (§7) yet it sits unchecked in §10 while cosmetic slices ship — the plan and the priority diverged. The MVP-sized version is small precisely because the monitor loop already samples every body every 0.1s: clamp per-tick horizontal displacement to `WALK_SPEED × dt × slack`, clamp upward displacement against jump physics, and on violation re-pivot via the existing reposition-then-re-own primitive. That also *is* the anti-fly check (persistent airborne-with-no-floor-probe → falling or cheating; the doom-exclusion probe from §3.3 gives you the floor test for free). `[Missing system — the single highest-leverage one]`

### 3.3 Swap primitive + grace + the doom exploit — **accept the exclusion spec, with two amendments**

The [2026-07-01 spec](../specs/2026-07-01-swap-doom-exclusion-design.md) is good work: it correctly identifies that timer-grace *cannot* rescue a below-the-rim body (protection ≠ delay), correctly rejects memory-based rescue on the eroding-arena edge, and the "floor-beneath-before-kill-plane" probe is current-state, arena-agnostic, and punishes the griefer instead of the victim. The edge-case table is honest. This review also **empirically confirmed the probe's central claim** against the live arena (§2.4d): with a tile gone, a root→`VOID_Y` ray finds the next floor at y=−50 — upper-floor tile loss is not doom, exactly as the spec argues, which retires its residual concern #1 (probe correctness). Judgment: **build it** — with these amendments:

1. **Ship velocity-zero-at-handoff first and independently.** It fixes the momentum-ends-grace bug (§2.3) for *every* swap, not just griefed ones, matches the "orient after a swap" fantasy, and shrinks the doom window to positional cases only. It is also ~5 lines against the existing `pivotBodyTo` machinery. The spec bundles it; unbundle and ship it now.
2. **Re-probe classification as close to `SetNetworkOwner` as possible and accept the residual race** (spec's own concern #2) — erosion timescales (1.2s) dwarf the commit window; don't add complexity for it.
3. On the spec's concern #5 (exclusion-vs-rescue feel): exclusion is the right philosophy *and* the right engineering — a rescue re-introduces the memory/teleport problems the spec just escaped. The "no swap this cycle" beat when the safe set collapses below 2 is fine: it coincides with the round ending anyway.

**Is grace-as-timer the right primitive at all?** After the amendments: yes. Grace's real job is narrow — "you cannot be eliminated, and you cannot arm tiles, until you've had a beat to orient" — and a server-stamped timer with an input-based early exit expresses exactly that. The failures attributed to grace (momentum, doomed inheritance) were actually *handoff* problems; fixing the handoff (at-rest, never-doomed) is the root cause, and the timer then does the one job it's good at. Replacing it with anything stateful (invulnerability flags on humanoids, positional rescues) would be more machinery for less clarity.

### 3.4 Networking posture — summary

Server authoritative for: ownership assignment, swap timing/plan, grace, elimination, economy, hazard state. Client authoritative for: its own body's physics (unvalidated — §3.2). Replication: no streaming, full world + 16 rigs (fine at this scope; the TDD's ReplicationFocus-per-swap note is the correct future answer). Remote surface: **zero client→server events** — outstanding. The exploit surface is therefore *entirely* the physics channel, which concentrates the anti-cheat problem in one place — a genuinely good property that makes §3.2 tractable.

---

## 4. Performance & Scalability

**Current scope: comfortably fine.** Measured against the code, not vibes:

| Load | Cost | Assessment |
|------|------|------------|
| Void/erosion monitor | ≤16 spherecasts + 427 tile-phase evals @ 10Hz, writes on change only | Trivial. |
| Arena geometry | 427 tiles × 5 parts = **2,135 anchored parts (measured live)** + trim/lobby cosmetics (LobbyArea: 49 parts) | Fine on mobile; would be 427 with the EditableMesh path (§2.4). |
| Swap commit | ≤16 × (SetNetworkOwner + FireClient) + SoulMap broadcast | Sub-millisecond burst; masked by the camera cut. |
| Client per-frame | move resolve + ensureControls + camera check; 16 animator rigs; ~70 cosmetic part writes (wisps/crowd) | Fine. `FindFirstChildOfClass` per frame per body is noise at n=16. |
| Replication | 16 R15 rigs + full arena, streaming off | Fine; heavy layered-clothing avatars are the only wildcard (normalize if it bites). |

**Real scalability risks, in order:**
1. **The singleton topology** (one HexField, one Bodies folder, one RoundManager state) is the multi-arena blocker — an architecture cost, not a perf cost (§2.2).
2. **16-player behavior is unmeasured** — the TDD's own note ("not yet tested at 4+ concurrent") still stands. The swap-commit ownership storm, spawn-spiral crowding (slots ~6.9 studs apart with colliding bodies), and 16-rig animator cost are all *probably* fine and all unverified. A bot-fill test (§2.8) answers this cheaply.
3. **Cosmetic per-frame creep** — each world slice adds Heartbeat loops; budget them (one shared loop, a part-write cap) before Slice 4 "Ambient Life."
4. StreamingEnabled stays correctly off until a large-world arena exists; when it does, the documented ReplicationFocus-on-swap plan is right — just remember it also needs the *preview target* streamed in, or the T-3s highlight will point at unloaded space.

---

## 5. Game Design & Player Experience

### Mechanic-by-mechanic

- **Random swaps (the hook): KEEP.** The one-mechanic clarity is the product. The plan/preview/commit implementation preserves it faithfully.
- **Hex erosion as the sole hazard: KEEP — this is the best design decision in the project.** Erosion is *player-caused*, so what you inherit after a swap is literally your predecessor's footsteps burned into the floor. It makes "experience the consequences of others' decisions" physically visible, and it generates the sabotage/mastery tension the GDD wants without any extra systems. The 7-floor colored stack doubles as an orientation aid after the camera cut. Genuinely elegant.
- **Swap preview: REDESIGN (finish it).** A Highlight with no directional ping and no danger tint fails its own design brief the moment the target is off-screen or near an armed tile (§2.7). The GDD's fairness thesis — "a readable challenge, not a blind dice roll" — is not shipped yet; don't run the §12 fairness playtest until it is, or the playtest will falsely condemn the grace tuning.
- **Grace: KEEP, after the handoff fixes** (§3.3). Also stamp it at round start (§2.3) — the current spawn-instant tile-arming with no intro beat contradicts GDD §4's pre-round and is needlessly harsh on new players.
- **Orient-after-swap: the hard cut + FOV punch is right** (fly-across was correctly rejected). What's missing is the half-second of *information*: which floor am I on (solved by floor colors), where's the edge, am I on a warning tile. Velocity-zero handoff buys most of this; consider a brief (~0.3s) armed-tile vignette on the inherited tile only if playtests show deaths-in-first-second persisting.
- **Dynamic cadence (20→8s): KEEP the mechanism, question the floor.** The stall-breaker is smart (N=2 rounds genuinely need it). But at the 8s floor with a 3s preview, free play is 5s — the loop degenerates into continuous telegraph, and at N=2 a swap is a pure position-trade every 8s, which *maximizes* the sabotage incentive precisely when it's most legible to the victim. Consider a 10–12s floor and let erosion (the floor is disappearing!) provide the endgame pressure instead. Tune with data, but don't assume the current floor is right. Also: the GDD still describes fixed 30s cycles — the design doc must own this change (§2.8).
- **Identity halos (free Soul): KEEP.** Cheap, readable, and the emphasized own-halo answers "which one is me" honestly. The shimmer desync (§2.7) is the one blemish and it's fixable.
- **Economy/progression: KEEP the architecture, close the loop.** Survival-depth rewards are the right shape (paying per-swap-survived is a *placement proxy* that never rewards sabotage — good instinct). But with no sink, no daily hook, and no visible stats, there is currently **no reason to return tomorrow**. The cheapest honest retention move is the first Soul-color/halo-variant shop (coins only) — it validates the flagship monetization lane with zero pay-to-win risk and makes every earned coin retroactively meaningful.
- **Eliminated experience: adequate, watch it.** Balcony + victory cam works for 2–5 minute rounds. The bigger issue is eliminated players remain *physics actors* (§3.2). Slice 5 "Activities" is the right eventual answer; a spectate-the-killer-chain camera is a cheaper interim.

### The unsolved design debt (flagged honestly in the GDD, worth restating)

The **backwards incentive** — your pre-swap positioning benefits a random opponent, so the optimal pre-swap play is sabotage — is the one structural threat to the whole design, and the GDD correctly refuses to solve it blind (§12 Ghost Points experiment, gated on playtest). Two review notes: (1) the doom-exclusion fix removes only the *lethal* sabotage; parking on warning tiles remains optimal play, which is arguably fine (it's legible, counterable chaos — the preview's danger tint is the counterplay, another reason to finish it); (2) the §12 gate question ("does inherited death feel fair?") **requires telemetry that doesn't exist** — post-swap death rate, early-leave rate. Minimal analytics events must precede the playtest or the gate can't be evaluated. That's a missing dependency in the roadmap, not just a nice-to-have.

**Onboarding is absent** and the mechanic *does* read as a bug without context (GDD §6 says so itself). The full tutorial is rightly Alpha-scoped, but a first-session text overlay on the first preview ("You're about to become the glowing body!") and first swap ("Your controls moved — the halo is you") is an afternoon of work and should precede any stranger-facing test.

### What to cut or defer (anti-feature-creep)

- **AI post-round recap (GDD USP #6): defer hard.** External API cost/latency/moderation surface for a feature whose retention value is unproven and whose audience (9–16) may not read it. It is currently scoped ⚪ Priority-3 — correct; resist any pull forward until the core loop retains without it.
- **Replay system: defer** (heavy, low leverage pre-retention).
- **No-Doom *rescue* variant: delete from consideration** — the exclusion spec supersedes it and the GDD §12 rescue text should point there.
- **Mirror Match modifier: defer until premium Souls exist** (its whole point is Soul-only identity).
- **World Slices 4–5: defer behind the do-before-playtest list** (§6). Slice 3 (hex re-skin) is pure polish on the game's strongest system — fine whenever, but it beats nothing on the critical path.

---

## 6. Roadmap & Priority Re-sequencing

**What the current plan gets right:** MVP DoD was honestly tracked and honestly met (two friends, full round, swaps, grace, winner, currency). The world-identity investment (Slices 1–2) was front-loaded deliberately and delivered a coherent look. Economy before cosmetics-content was the right dependency order.

**What it gets wrong:** the TDD's own "Priority 1 — cannot ship without" list has *movement validation* and *swap preview* in it, both open, while roadmap energy went to two cosmetic slices; the known kill-exploit spec sits approved-in-principle but unbuilt; the fairness playtest that gates GDD §12 has no telemetry to answer it; and the economy shipped earn-side only. The pattern to correct: **fairness/integrity work keeps losing scheduling contests to visible work.**

**Recommended sequence** (rationale + deferred debt per item in §7):

1. **Handoff-at-rest + doom exclusion** (the approved spec, unbundled: velocity-zero first).
2. **MVP movement validation** (displacement clamps + re-pivot correction, piggybacked on the existing monitor; includes the eliminated-body containment + collision-group decision).
3. **Finish the swap preview** (ping + danger tint) **+ round-start grace + first-session hints.**
4. **Minimal analytics events** (post-swap deaths, early-leaves, hazard-parking) — the §12 gate's prerequisite.
5. **→ Friend-scale playtest at 4–8 players** (the fairness question, plus the unmeasured 16-player physics on a bot fill).
6. **First coin sink** (Soul color/halo shop, coins only).
7. **Session-locked persistence** (ProfileService-style) + BindToClose parallelism — must land before public listing.
8. **Vendor the PlayerModule fork.**
9. **RoundManager decomposition + bot harness** — before arena #2, not after.
10. World Slices 3–5, matchmaking/lobby UX toward GDD's 4/6/12 thresholds, then the Alpha cosmetics/shop track.

Items 1–4 are each small; the re-sequencing costs roughly one slice of world-dressing delay and buys a playtest whose results can actually be trusted.

---

## 7. Ranked Action List

### Do now (correctness of the core loop)
| # | Action | Why now | Debt if deferred |
|---|--------|---------|------------------|
| 1 | Velocity-zero at swap handoff (`pivotBodyTo`-style reset in `commitSwap`) | Fixes momentum-cancels-grace for all swaps; 5 lines; halves the doom problem | Grace remains partly fictional; every playtest datapoint about fairness is polluted |
| 2 | Implement doom-exclusion probe per the 2026-07-01 spec | Closes the documented kill exploit; the design is already reviewed | A known, reproducible grief becomes community knowledge the day two friends find it |
| 3 | Replicate authoritative grace to the client (kill the shimmer guess) | Players must never die inside a visible shield | Fairness feature actively erodes trust |
| 4 | Add the re-own to `sendToLobby` (make the pattern uniform); confirm the falling-body case in the next 2-client smoke | Live solo-Play test showed the pivot sticks on an idle body, so this is hardening — but it's one line, and the falling-under-latency case is exactly the elimination scenario | Two contradictory beliefs about one load-bearing primitive |
| 5 | `warn` on `SetNetworkOwner` pcall failure; `ClientAnimator` registration retry | Silent-failure hygiene, minutes each | Invisible desyncs, unanimated bodies |

### Do before any playtest with strangers
| # | Action | Why | Debt if deferred |
|---|--------|-----|------------------|
| 6 | MVP movement validation (displacement clamp + re-pivot; airborne/off-arena containment; body-collision decision) | An exploiter currently cannot lose; eliminated bodies are unmonitored physics actors | One exploiter ruins every session; word spreads at Roblox speed |
| 7 | Swap preview ping + danger tint; round-start grace; first-session hint overlays | The fairness thesis isn't shipped without them; onboarding cliff | Playtest falsely condemns grace tuning; new players churn confused |
| 8 | Minimal analytics (post-swap death, early-leave, hazard-parking events) | GDD §12's gate is unanswerable without it | Design decisions made on anecdote |
| 9 | Parallelize `BindToClose` saves | Shutdown under DataStore brownout is exactly when saves matter | Lost sessions during the worst outage window |

### Do before scale / public listing
| # | Action | Why | Debt if deferred |
|---|--------|-----|------------------|
| 10 | Session-locked persistence (ProfileService-style lock + merge) | Multi-server data loss is silent and cumulative | Corrupted-economy support burden; migration gets harder with real data |
| 11 | Vendor/fork PlayerModule; delete the spoofing layer | Freeze the undocumented internals mobile controls depend on | A random Roblox Tuesday update breaks mobile in production |
| 12 | Decompose RoundManager (pure sequencing reducer) + bot-driven Studio harness; retire manual smoke docs to acceptance-checklists | Glue is the only untested layer and the only bug source; manual regression doesn't scale | Each feature multiplies untested interaction surface |
| 13 | Pick one tile build path (EditableMesh or wedge) and delete the other | 5× parts or dead module — carrying both is silt | Confusion + part-count tax on every future arena |

### Later
| # | Action | Note |
|---|--------|------|
| 14 | Cadence floor retune (10–12s?) with playtest data | Mechanism is right; the floor is a guess |
| 15 | Simultaneous-death tiebreak (or delete the GDD rule) | Rare but decides wins |
| 16 | Leaver-award policy decision | Make the accidental policy deliberate |
| 17 | ReplicationFocus-on-swap plan when a streamed arena arrives | Remember the preview target must be streamed too |
| 18 | Ghost Points experiment behind a flag, after telemetry baseline | The right first move on the backwards incentive |

---

## Appendix — claims verified vs. assumed

- **Verified statically this session:** all 18 lune suites pass (executed); every code citation above read directly; remote inventory (zero C→S) confirmed from `Remotes.luau`.
- **Verified live this session (Studio solo Play):**
  - Clean boot, no console errors; round correctly held in Lobby at 1 player (`MIN_PLAYERS_TO_START=2` gate works); player has no `Character`; body spawns on the balcony, client-owned, unanchored.
  - Arena as-built: HexField = 2,135 parts (427 tiles × 5, 61 tiles/floor); LobbyArea = 49 parts (disc + 48 barrier segments); `StreamingEnabled=false`; no Baseplate.
  - **Server pivot on a client-owned body replicates and sticks without re-owning** (idle body, zero latency) — finding #5 downgraded from "possibly broken" to "make the pattern uniform."
  - **Contact-probe geometry** (center tile incl. the `-0` case, grout seam, gone-tile `RespectCanCollide` filtering, no cross-floor hits) behaves exactly as designed.
  - **Doom-exclusion spec's floor-beneath probe** empirically confirmed: through a gone tile, the ray finds the next floor at y=−50 before `VOID_Y`.
- **[needs 2-client verification]:** the full grace-gated arming loop during an Active round; `sendToLobby` on a *fast-falling* body under real latency; 4+ player swap behavior (TDD's own open note); touch HUD on a real device (MCP screen capture can't see PlayerGui; probe `require` cache is separate from game scripts, so live singleton state can't be read directly).
