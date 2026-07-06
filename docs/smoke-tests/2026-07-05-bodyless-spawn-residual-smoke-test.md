# Smoke test — residual bodyless-spawn holes (2026-07-05)

Follow-up to the 2026-07-03 first-join bodiless-spawn fix. That fix made four layers
self-healing (build retries, `ControllerUserId` reconcile, economy decoupling,
re-embodiment sweep) but the bug still recurred intermittently. Two residual holes were
root-caused and closed:

1. **Dead cached camera (client).** `ClientControl` / `ClientRoundHud` cached
   `workspace.CurrentCamera` once at require time; if the engine replaces the startup
   camera on a cold join, every retarget landed on the dead instance — permanent
   camera-only spawn with a healthy server. Both now read the camera live; the
   per-frame re-assert also restores `CameraType.Custom` on a fresh camera.
2. **Sweep blind to broken bodies (server).** The re-embodiment sweep only retried when
   `getOwnBody(p) == nil`, so a registered body whose parts were engine-destroyed
   (`FallenPartsDestroyHeight` beats the grace-shielded void monitor on a straight
   fall from the lowest floor: ~1.43 s to −500 vs the 1.5 s grace window) blinded it
   forever — and its rootless rider skipped the void check, hanging the round. The
   sweep now heals any registered-but-broken body (`BodyManager.isIntact`), and
   `FallenPartsDestroyHeight` is pushed to −50000 so the engine can never dismember a
   falling body before the monitor catches it.

Plus: the `SetControlledBody` client handler no longer errors when the fire outruns the
body's replication (nil argument), and a client watchdog warns with the failing layer if
a player sits bodiless > 5 s.

Setup: Studio, `rojo serve` connected, Start Server + 2 Players unless noted.

**2026-07-06 — MCP solo-session verification (Play Solo, driven via Studio MCP):**
tests 1, 2.3, 4.1 (passively) and 5.1 PASSED; details inline below. Still pending
manually: 2.4 (mid-round heal), 4.2 (watchdog signal), 5.2, and the 2-client cold-join
sweep — these need a real Start Server + 2 Players session.

## 1. Camera replacement self-heal (client)

1. Start server + 1 player; wait for the balcony spawn ("controlling: Body_…" in the
   client log).
2. In the CLIENT command bar: `workspace.CurrentCamera:Destroy()`.
3. **[x]** (2026-07-06, MCP solo) Within a frame the view snaps back to the player's
   body (per-frame re-assert binds the NEW camera: `CameraType = Custom`, subject =
   our humanoid). Verified: new camera instance, `CameraType.Custom`, subject == our
   humanoid 0.5 s after the destroy; no errors.

## 2. Broken-body heal (server sweep)

1. Start server + 2 players; wait for both balcony spawns (Lobby countdown running).
2. In the SERVER command bar, destroy one player's body parts to fake an
   engine-dismembered wreck:
   `for _, d in ipairs(workspace.Bodies:GetChildren()[1]:GetDescendants()) do if d:IsA("BasePart") then d:Destroy() end end`
3. **[x]** (2026-07-06, MCP solo) Within `Config.BODY_RECONCILE_SECONDS` (2 s) the
   server warns `"…'s body is broken … rebuilding"` and rebuilds: a fresh intact body
   on the balcony slot, correct `ControllerUserId`, wreck destroyed, client rebound
   (`controlling: Body_… (spawn)`), camera on the NEW humanoid.
4. **[ ]** Repeat mid-round (Active): the wreck's rider is eliminated (round does NOT
   hang), the owner is re-embodied on the balcony like a late joiner, and the round
   ends normally.

## 3. Nil-body assignment guard (client)

Hard to force deliberately (needs the remote to outrun replication). Passive check:
**[ ]** on cold joins the client log never shows the old
`attempt to index nil with 'FindFirstChildOfClass'` error; if the race fires, it logs
`SetControlledBody carried no body` and the reconcile attaches within a frame.

## 4. Watchdog silence + signal

1. **[~]** (2026-07-06, MCP solo: silent through boot, camera destroy, and the ~2 s
   bodiless heal window — correct, under the 5 s threshold.) Full 2-player check
   still pending: healthy session (join → round → elimination → round end → lobby),
   no `[BSR][watchdog]` warns ever appear (eliminated players still control a body).
2. **[ ]** With the server sweep loop commented out (dev-only) and a body deleted
   whole (`workspace.Bodies:GetChildren()[1]:Destroy()` on the server), the victim's
   client warns `bodiless: N bodies, none with ControllerUserId == …` every 5 s —
   naming the failing layer. Restore the sweep afterward.

## 5. FallenPartsDestroyHeight

1. **[x]** (2026-07-06, MCP solo) In a running session,
   `workspace.FallenPartsDestroyHeight` reads −50000 (rojo applied the project
   property to the live place).
2. **[ ]** Mid-round, a body knocked off the lowest floor is still teleported to the
   balcony by the void monitor once grace ends (elimination unchanged); its parts are
   never destroyed mid-fall.
