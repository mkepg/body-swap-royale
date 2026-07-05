# Smoke Test — Swap-Preview Ping + First-Session Hints (2026-07-05)

Covers the directional ping (`SwapPreviewController` rewrite + pure `PingDirectionModel`) and the
centralized first-session hint system (`HintRegistry` / `HintModel` / `HintService` / `HintController`,
persisted via `profile.seenHints`). Review Action #7 (partial). Spec:
`docs/superpowers/specs/2026-07-05-swap-preview-onboarding-design.md`.

Pure logic is lune-covered (`tests/hint_model.spec.luau`, `tests/ping_direction_model.spec.luau`,
`tests/profile_model.spec.luau`). This doc covers the runtime glue that lune can't.

---

## Auto-verified this session (solo Play + Studio MCP)

Done from the controller via MCP `execute_luau` against a live solo Play session:

- **Clean boot / no require cycle.** Server + client bootstrap with no errors; `[BSR] Server ready …`
  and `[BSR] Client ready …` both print. `HintService` (server) and `RoundManager`'s new trigger calls
  do not introduce a require cycle.
- **`ShowHint` remote created at runtime** (server→client) and **delivers to the client** (probe handler
  received a fired payload). No client→server remote added (zero-C2S preserved).
- **`HintController` renders the anchored label** with the real swap ordering — fire `SetControlledBody`
  (client sets `controlledBody`) then `ShowHint {anchor="controlledBody"}`: a `HintLabel` `BillboardGui`
  appears on the controlled body's `Head`, `AlwaysOnTop=true`, with the payload text. (Firing `ShowHint`
  before the anchor's remote correctly renders nothing — the documented drop path.)
- **`SwapPreviewController.begin` runs on `SwapPreview`** — the `SwapPingGui` ScreenGui is created; the
  amber `Highlight` + `SwapPingChevron` are created in `begin` before it. In solo **Lobby** they are then
  immediately torn down because the controller (correctly) clears the ping on every `RoundStateChanged`
  reporting a non-Active phase — so the persistent ping visuals require a real Active round (below).
- **`PingDirectionModel` real-VM parity** — `require`d in the client VM, `resolve` matches the lune
  expectations: center → `onScreen=true`; far-right in front → `onScreen=false, x=950 (w-margin), rot=90`;
  behind-camera projected-left → `onScreen=false, rot=90` (direction flipped).

### Reproduce the auto-checks (MCP snippets)
```lua
-- Server datamodel: fire the real runtime remotes to the sole player.
local Players, RS = game:GetService("Players"), game:GetService("ReplicatedStorage")
local p = Players:GetPlayers()[1]
local body
for _, m in ipairs(workspace:GetDescendants()) do
  if m:IsA("Model") and m:GetAttribute("ControllerUserId") == p.UserId then body = m break end
end
RS.Remotes.SetControlledBody:FireClient(p, body, true)      -- sets HintController.controlledBody
task.wait(0.15)
RS.Remotes.ShowHint:FireClient(p, { id="t", text="This is you", duration=10, anchor="controlledBody" })

-- Client datamodel: confirm the label rendered on the head.
local lp = game:GetService("Players").LocalPlayer
local b for _, m in ipairs(workspace:GetDescendants()) do
  if m:IsA("Model") and m:GetAttribute("ControllerUserId") == lp.UserId then b = m break end end
local head = b:FindFirstChild("Head")
return head:FindFirstChild("HintLabel") ~= nil   -- expect true
```
Note: solo firing pollutes state across attempts (`showing` holds for a hint's full lifetime; stray
`SetControlledBody` fires clear the ping). Restart Play between attempts for a clean read.

---

## Manual 2-client gate (the part solo Play can't cover)

Two clients (two Studio Play-Solo instances or a Team Test), fresh accounts with **empty `seenHints`**.
Drive a real round to an actual swap (or `RoundManager.forceSwap()` on the Server datamodel per the
disconnect smoke test — note `forceSwap` skips the preview window, so use a real round to exercise the
preview ping + `SwapPreview` hint).

| # | Case | Expected |
|---|------|----------|
| 1 | Off-camera target during the T-3s preview | The amber **edge arrow** appears at the screen edge and points toward the target; turning the camera to frame the target swaps the arrow for the on-target **chevron** above its head. The `Highlight` is on the target throughout. |
| 2 | First-ever preview (fresh `seenHints`) | The **"You're about to become the highlighted body — get ready!"** label appears anchored to the player's **current (pre-swap) body** (the ping arrow/highlight points to the body they'll become), once. |
| 3 | First-ever swap commit | The **"Your controls just moved — the glowing halo is always you."** label appears anchored to the Soul-halo body, once. |
| 4 | Second preview / swap, same session | **No** hint labels re-appear (seen-state gating). |
| 5 | Returning player (rejoin; `seenHints` persisted) | **Neither** hint appears on their first preview/swap. |
| 6 | Two hints in quick succession | They never overlap — the second waits for the first to finish (sequential queue). Nothing blocks movement/input. |
| 7 | Preview clears | On commit (`SetControlledBody`) and when the round leaves Active, the ping (highlight/chevron/arrow) disappears. |

Case 5 is the true "first-session" check: it exercises `profile.seenHints` persisting across a
leave/rejoin (autosave / leave-save path). Case 4 exercises in-session gating (in-memory profile mutation).

## Result log
- 2026-07-05 (controller, solo + MCP): auto-checks above all pass. Manual 2-client cases 1–7 **pending**
  a 2-player session.
