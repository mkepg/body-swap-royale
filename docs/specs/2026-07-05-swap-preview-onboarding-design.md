# Swap Preview Ping + Centralized First-Session Hints — Design

**Date:** 2026-07-05
**Status:** Approved (brainstorm complete)
**Review action:** 2026-07-03 critical review, Action #7 (partial — see Scope).
**Depends on / relates to:** doom-exclusion (shipped), Soul halo (`SoulController`), `SwapPreviewController` (shipped Highlight), economy profile (`ProfileModel`/`EconomyService`/`ProfileStore`).

---

## 1. Purpose

Finish the load-bearing half of the swap preview's fairness thesis and give new players enough
context that the swap mechanic reads as *intentional* rather than a bug — the two cheapest, highest-
leverage changes that must precede a stranger-facing fairness playtest.

Two features, one spec:

1. **Directional ping** — the shipped preview is a `Highlight` only, which is invisible whenever the
   target body is off-camera (the common case). Add a screen-space directional indicator so the player
   can always *find* the body they are about to inherit.
2. **Centralized, anchored first-session hints** — a small data-driven hint system whose first two rows
   decode the swap mechanic in-match, presented as labels anchored to the body the player is looking at:
   their current body during the preview (with the ping pointing to the target), then the Soul halo after
   the swap.

## 2. Scope

**In scope**
- Directional ping: on-target chevron when the target is on-screen; edge arrow pointing toward it when
  off-screen. Amber, matching the existing preview color language. Keep the shipped `Highlight`.
- A centralized hint system: `HintRegistry` (data) + pure `HintModel` (decision) + server-authoritative
  `HintService` (firing + seen-state) + client `HintController` (anchored rendering) + `profile.seenHints`
  persistence.
- Exactly two hint rows now:
  - `SwapPreview` trigger → *"you're about to become the highlighted body"* anchored to the player's
    **current (pre-swap) body** — the ping's edge arrow/highlight points to the body they'll become, so
    the caption sits where the player's attention already is.
  - `ControlSwap` trigger → *"this is you"* anchored to the Soul halo on the inherited body.

**Explicitly out of scope (decided during brainstorm; recorded so they are not lost)**
- **Danger read / amber danger tint.** Deferred: doom-exclusion already removes the genuinely-unfair
  inherited-death cases, in-world tile color already telegraphs danger after commit, and the playtest
  should *measure* whether a danger read is needed before we build it. If added later, the cheap version
  reads the already-replicated tile-warning state client-side (no new server payload).
- **Round-start grace.** Deferred: round start is not disorienting (no swap yet; players spawn oriented
  on the top floor, where tile loss is non-lethal by construction). The real want there is a pre-round
  *intro beat* (a proper countdown/camera phase), which is separate round-structure juice.
- **Full first-launch tutorial round** (GDD §6). The eventual gold-standard onboarding; correctly
  deferred to Alpha until the core loop is validated. The hints are the cheap interim.
- **Richer GDD hint set** (survived-a-dangerous-inherit "clutch", first-win, etc.). These become new
  `HintRegistry` rows + new `fireTrigger` call sites later; the system is built to absorb them with no
  new plumbing.

## 3. Architecture

Follows the established pure-core / thin-glue split. New pure modules are Roblox-free, dependency-
injected, and lune-tested. Glue is thin and verified via Studio MCP + a manual smoke test.

### 3.1 New shared modules

| Module | Kind | Responsibility |
|--------|------|----------------|
| `src/shared/HintRegistry.luau` | pure data | The single source of truth: declarative list of hint rows. Roblox-free. |
| `src/shared/HintModel.luau` | pure, lune-tested | `resolve(registry, seenSet, trigger) -> hint \| nil`; `withSeen(seenSet, id) -> seenSet'`. No time, no Roblox. |
| `src/shared/PingDirectionModel.luau` | pure, lune-tested | Screen-projection math for the ping: given the target's viewport projection + viewport size + margin, decide on-screen vs off-screen and, when off-screen, the clamped edge position + pointing angle. No Roblox types in the signature (plain numbers in/out). |

### 3.2 Modified shared modules

- `src/shared/Remotes.luau` — add `"ShowHint"` to `REMOTE_EVENTS` (server→client only; no new
  client→server remote — the zero-C2S surface is preserved).
- `src/shared/ProfileModel.luau` — `default()` and `sanitize()` include `seenHints` (array of unique
  string ids; sanitize coerces to strings, dedupes, drops non-strings). Migration-safe: an old blob
  with no `seenHints` sanitizes to `{}`. **No `PROFILE_VERSION` bump required.**
- `src/shared/Config.luau` — ping visual tunables (arrow/chevron size, colors, edge margin) and hint
  durations. Arena-agnostic; no geometry.

### 3.3 New server module

- `src/server/HintService.luau` — `fireTrigger(player, trigger)`:
  1. read `profile.seenHints` via `EconomyService.getProfile(player)` (nil profile → no-op);
  2. `HintModel.resolve(HintRegistry, seenSet, trigger)` (the registry is a plain array module);
  3. on a hit: `ShowHint:FireClient(player, { id, text, duration, anchor })`, then append the id to
     `profile.seenHints` (mutates the cached profile; the existing autosave / leave-save path persists it).
  Server-authoritative; the client never reports "seen" back.

### 3.4 Modified server modules

- `src/server/RoundManager.luau` — the single call site for both triggers (it already owns `firePreview`
  and the commit sequence):
  - in `firePreview`, after `SwapPreview:FireClient(pair.player, pair.body)`, call
    `HintService.fireTrigger(pair.player, "SwapPreview")`.
  - at the swap commit (where each swapped player's control is set with `isSwap = true`), call
    `HintService.fireTrigger(player, "ControlSwap")`.
  (Keeping both triggers in `RoundManager` avoids coupling `ControlManager` to `HintService`.)

### 3.5 New client module

- `src/client/HintController.luau` — `start()`:
  - tracks the current preview target (from `SwapPreview.OnClientEvent`) and the local controlled body
    (from `SetControlledBody.OnClientEvent`), so it can resolve an `anchor` to a body;
  - on `ShowHint`, renders an anchored `BillboardGui` label on the anchor body's `Head` (fallback
    `HumanoidRootPart`), `AlwaysOnTop`, styled with `HudTheme` fonts/stroke: fade in → hold `duration`
    → fade out;
  - a simple sequential queue so two hints never overlap (the two shipped hints are ~3s apart, but the
    queue guards future rows);
  - `anchor = "target"` → the preview target body; `anchor = "controlledBody"` → the local controlled
    body (the Soul-halo body).

### 3.6 Modified client modules

- `src/client/SwapPreviewController.luau` — replace the bare `Highlight` with the full ping:
  - keep the `Highlight` on the target;
  - add an **on-target chevron** (`BillboardGui` above the target head) shown while the target is
    on-screen;
  - add an **off-screen edge arrow** (`ScreenGui`, `HudTheme`-styled) that, when the target is
    off-screen, sits at the clamped screen edge and rotates to point toward the target;
  - a per-frame (`RenderStepped`) update while a preview is active projects the target via the camera,
    feeds `PingDirectionModel`, and toggles chevron vs edge-arrow + positions/rotates the arrow;
  - clears on the existing triggers (`SetControlledBody` retarget / leaving `Active`).
- `src/client/init.client.luau` — `require` + `start()` `HintController`.

### 3.7 Data flow

```
Preview start (server)
  RoundManager.firePreview
    -> SwapPreview:FireClient(player, body)         (existing; drives ping highlight + arrow)
    -> HintService.fireTrigger(player,"SwapPreview")
         -> HintModel.resolve(registry, seenHints, "SwapPreview")
         -> hit? ShowHint:FireClient(player,{id,text,duration,anchor="controlledBody"}); seenHints += id
         -- NB: preview fires BEFORE the commit's SetControlledBody, so "controlledBody"
         --     here = the player's CURRENT (pre-swap) body.

Swap commit (server)
  RoundManager commit (isSwap=true per player)
    -> SetControlledBody:FireClient(player, body, true)   (existing; ping clears, halo re-emphasizes)
    -> HintService.fireTrigger(player,"ControlSwap")
         -> hit? ShowHint:FireClient(player,{id,text,duration,anchor="controlledBody"}); seenHints += id

Client
  SwapPreviewController: RenderStepped while preview active -> PingDirectionModel -> chevron|edge-arrow
  HintController: ShowHint -> anchored BillboardGui label on target|controlledBody, fade in/hold/out
```

## 4. Data shapes

### 4.1 Hint row (`HintRegistry`)
```
{
  id       = "swap-preview-intro",   -- unique string; stored in seenHints
  trigger  = "SwapPreview",          -- generic gameplay event name
  once     = true,                   -- gate on seen-state
  priority = 10,                     -- higher wins if multiple match one trigger
  duration = 3.0,                    -- seconds the label holds
  anchor   = "controlledBody",       -- "target" | "controlledBody" (here: the pre-swap current body)
  text     = "You're about to become the highlighted body — get ready!",
}
```
Row two: `id="swap-commit-intro"`, `trigger="ControlSwap"`, `anchor="controlledBody"`,
`text="Your controls just moved — the glowing halo is always you."`, `duration≈3.5`.

### 4.2 `ShowHint` payload (server→client)
`{ id: string, text: string, duration: number, anchor: "target" | "controlledBody" }`

### 4.3 `profile.seenHints`
Array of unique hint-id strings. `ProfileModel.default` → `{}`. `sanitize` coerces any loaded value to
an array of unique strings (non-strings dropped, deduped). Persisted inside the existing profile blob.

## 5. Pure-model contracts (lune-tested)

### 5.1 `HintModel`
- `resolve(registry, seenSet, trigger)`:
  - returns the highest-`priority` row whose `trigger == trigger` and (`once == false` **or** its `id`
    is not in `seenSet`); `nil` if none.
  - `seenSet` accepted as either an array of ids or a set-like table; document and pick one (array in,
    normalized internally) — keep the signature total and side-effect-free.
- `withSeen(seenSet, id)` → a new set/array including `id` (no mutation; idempotent).
- Tests: trigger match; unknown trigger → nil; `once` already seen → nil; `once=false` always returns;
  priority tie-break; empty registry → nil; `withSeen` idempotent + non-mutating.

### 5.2 `PingDirectionModel`
- Input (plain numbers): target's projected screen position `(x, y, depthOrOnScreenFlag)`, viewport
  `(w, h)`, edge `margin`. (The Roblox `Camera:WorldToViewportPoint` call happens in the controller; the
  model receives its numeric outputs so it stays Roblox-free.)
- Output: `{ onScreen = bool, x, y, angleDeg }` — when off-screen (behind camera or outside the
  viewport rect), `x,y` are clamped to the margin rect and `angleDeg` points from screen center toward
  the (possibly behind-camera) target; when on-screen, `onScreen=true` with the projected `x,y`.
- Must handle the **behind-camera** case correctly (WorldToViewportPoint returns off-screen / negative
  depth): treat as off-screen and flip the direction so the arrow points the correct way.
- Tests: target dead-center → onScreen; target off each edge → correct clamped edge + angle quadrant;
  behind-camera → off-screen + direction flipped; exactly at margin boundary → deterministic.

## 6. Presentation details

- **Ping colors:** reuse the shipped amber (`Highlight.FillColor = (255,200,60)`,
  outline `(255,220,120)`); chevron + edge arrow share this palette (Config-driven).
- **Chevron:** a `BillboardGui` triangle/`▼` above the target head, `AlwaysOnTop`, only visible while
  `onScreen`.
- **Edge arrow:** a `ScreenGui` arrow image/label positioned at the clamped edge and rotated by
  `angleDeg`; only visible while `not onScreen`.
- **Hint label:** a `BillboardGui` panel (small, `HudTheme.styleText`, dark panel + white text/stroke)
  above the anchor head, `AlwaysOnTop`; tween transparency in over ~0.2s, hold `duration`, fade out
  ~0.3s. If the target is off-screen the label rides with it (billboard), so the ping arrow does the
  "turn toward it" job and the label is read once the player looks.
- **Non-blocking:** never pauses input or the round; auto-dismisses; the queue enforces one at a time.

## 7. Persistence & failure behavior

- `seenHints` lives in the profile blob; saved by the existing autosave / leave-save / BindToClose path.
- A player who sees a hint then leaves before autosave still persists it (leave-save runs).
- A profile whose load failed (`persisted=false`) is never saved — such a player may see the hints again
  next session; acceptable (rare, and re-teaching is harmless).
- `HintService.fireTrigger` on a nil profile (not yet loaded / left) is a no-op.

## 8. Testing & verification

- **Lune (pure):** `tests/hint_model.spec.luau`, `tests/ping_direction_model.spec.luau`. All existing
  suites must stay green. Run: `export PATH="$HOME/.rokit/bin:$PATH"; lune run tests/<file>.spec.luau`.
- **Studio MCP (glue):** verify in the real Luau VM —
  - the ping: force a preview (`RoundManager.forceSwap()` per the disconnect smoke test), confirm the
    edge arrow appears and points toward an off-camera target and the chevron appears when it's framed;
  - the hints: confirm `ShowHint` fires once for a fresh `seenHints`, the anchored labels render on the
    target then the halo, and a second preview/swap does **not** re-fire (seen-state gating);
  - read live state via attributes/instances (the probe `require` cache is separate — do not
    `require(module).state`).
- **Manual smoke test:** add `docs/smoke-tests/2026-07-05-preview-ping-hints-smoke-test.md` covering:
  off-camera target is findable via the arrow; first-time player sees both hints once; returning
  player (seenHints populated) sees neither; hints never overlap; nothing blocks input.

## 9. Definition of Done

- New pure modules exist, are Roblox-free, and are lune-tested; full suite green.
- Ping shows a chevron on-screen and an edge arrow (correctly pointing, incl. behind-camera) off-screen;
  the shipped `Highlight` is retained; clears on commit / leaving Active.
- Hint system centralized as specified; the two rows fire once-ever per player, persist via
  `seenHints`, render anchored to the player's current body (preview) then the Soul halo (commit), and
  never overlap or block input.
- Zero client→server remotes added (verified).
- Studio MCP glue verification done; manual smoke-test doc added; `CHANGELOG.md` updated.
- Docs: note the deferred items (danger read, round-start grace, tutorial round, richer hints) so the
  roadmap keeps them.

## 10. Deferred / future notes

- Danger read — add only if the playtest's post-swap-death / early-leave data demands it; cheap version
  reads already-replicated tile-warning state client-side.
- Round-start intro beat — a proper pre-round phase (countdown + camera), not a grace stamp.
- Tutorial round (GDD §6) — the eventual onboarding; pull forward only if hints prove insufficient.
- Richer hints — new `HintRegistry` rows + `fireTrigger` call sites; inherit once-ever + persistence +
  queue for free.
