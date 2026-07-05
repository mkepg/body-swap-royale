# Smoke test — MVP Movement Validation (2026-07-04)

Validates the server rubber-band clamp (spec `docs/specs/2026-07-04-movement-validation-design.md`).
The pure model is lune-covered; this exercises the glue in a running server. Requires a 2-client Studio
session (one client to exploit, one honest) unless noted. Read live state via Attributes/instances — the
command-bar `require` cache is separate from the game scripts.

## Setup
- Play Solo (2 players via Test > Clients and Servers where a case needs an honest observer).
- `Config.MOVE_VALIDATION_ENABLED` must be `true`.

## Cases (server command bar unless stated)

1. **Horizontal teleport (client-owned body).** With a round Active, on a client set the controlled
   body's `HumanoidRootPart.Position` +200 studs on X. EXPECT: within ~0.5 s the body snaps back to its
   last grounded pose; it does not stay displaced; the round continues.

2. **Straight-up teleport / fly.** On a client, repeatedly set the body's Y up (or anchor+raise). EXPECT:
   the body is snapped back down within ~0.5 s; it never camps above the arena.

3. **Hover over an eroded hole.** Let the tile under a body erode (or force it), then hold the body's Y
   so it does not fall. EXPECT: snapped back to its last grounded pose within ~0.5 s (does NOT win by
   floating over the void).

4. **Honest play is untouched (critical).** With validation on, walk, sprint-turn, jump, jump ACROSS an
   eroded gap, and ride a swap normally on the honest client. EXPECT: zero rubber-banding — no snap-backs,
   no stutter — across a full round. Repeat with artificial latency (Studio > Network > incoming/outgoing
   lag, e.g. 200-400 ms) and confirm still no false corrections.

5. **Legit fall is untouched.** Walk off a floor edge over a hole. EXPECT: the body falls normally and
   either lands on the floor below or dies at VOID_Y via the existing grace-gated void monitor — never
   snapped back mid-fall.

6. **Eliminated-body containment.** After a player is eliminated (body on the balcony, still owned), on
   that client teleport the body toward/into the arena. EXPECT: snapped back; it cannot re-enter as a
   physics actor.

7. **Server repositions never self-correct.** Observe round start (spawn drop), an elimination
   (send-to-lobby), and round end (return-to-lobby). EXPECT: none of these server PivotTos trigger a
   rubber-band the following tick (bodies settle where the server placed them).

8. **Disconnect rescue still works.** Reproduce the disconnect-strand case (an eliminated player leaves,
   handing a body to a live survivor). EXPECT: the survivor's rescued body lands in the arena and is not
   rubber-banded; the round can still end.

## Pass criteria
All 8 cases behave as EXPECTED. Case 4 (honest play, incl. latency) is the gate: any false positive fails
the test and blocks the stranger playtest.
