# HUD Theme & Coherence (kid-friendly skin) — Design

**Date:** 2026-06-21
**Status:** Approved — ready for implementation plan
**Related:** builds directly on `docs/specs/2026-06-20-round-flow-bookends-design.md` (the Lobby/Results bookends) and the in-round swap HUD (`ClientSwapHud`). GDD §6/§7 (UX/UI, kid-friendly audience: ages 9–16), GUI reference §5 (responsive caps) / §9 (shared theme).

## Problem

Every on-screen HUD element today picks its own sizes, fonts, colors, and screen
positions in isolation across two `ScreenGui`s (`ClientSwapHud`, `ClientRoundHud`).
There is no shared source of truth, so a localized change to one element (capping the
bookend banner's width) immediately made a neighbor (the "Next round in N" bottom line)
look oversized and mismatched. The drift is structural, not a one-off.

Separately, the HUD reads as flat developer placeholder text, not a finished look for
the game's 9–16 audience.

This work introduces one shared `HudTheme` source of truth for **zones, size caps,
fonts, colors, and panel styling**, migrates every HUD element onto it, and applies a
**kid-friendly, chunky "Roblox-classic" skin** (Natural Disaster Survival vibe).

## Scope

**In scope**
- A new client-side `HudTheme` module: fonts, colors, pixel caps, named zones, panel
  styling + a few small helpers.
- Migrating the existing HUD elements (`ClientRoundHud` banner / bottom line /
  eliminated notice; `ClientSwapHud` timer / big countdown) onto `HudTheme`.
- A kid-friendly skin: bright state-colored panels, thick white outline, big rounded
  corners, bubbly heavy font, white text with a dark stroke, an offset "hard shadow",
  and a bouncy pop-in.
- Consistent layering (`DisplayOrder`) and zone separation so elements never stack.

**Out of scope (deferred / YAGNI)**
- A full art-direction pass beyond this skin (custom motion language, iconography,
  Soul-aware accents, telegraph re-juice) — its own future brainstorm.
- Any change to the swap flash behavior, gameplay logic, remotes, or the pure
  `RoundScreenModel` / `SwapTelegraphModel` (these stay untouched).
- Main menu, lobby player list, mastery stats (already deferred in the bookends spec).

## Design decisions (from brainstorm)

1. **Shared `HudTheme` module** (chosen over folding into `Config` or a widget factory):
   one client-only source of truth, keeping gameplay tunables in `Config` clean.
2. **Unified zones + caps** so nothing balloons on desktop/ultrawide and elements that
   are time-exclusive today are also *position*-separated.
3. **Kid-friendly skin** (Natural Disaster Survival vibe): the **panel fill color is
   driven by state** (green win / red lose / blue neutral), not just an accent stroke.
4. **Light polish only** (pop-in, shadow, gradient) — not a ground-up redesign.

## Architecture

One new file, two migrated files, all client-side. No server changes, no new remotes.

```
src/client/HudTheme.luau   (new)  -- fonts, colors, caps, zones, panel styling + helpers
        ▲                                  ▲
        │                                  │
ClientRoundHud.luau (migrate)      ClientSwapHud.luau (migrate)
  banner / bottom line / notice      timer / big countdown
```

### Component 1 — `src/client/HudTheme.luau` (new)

A plain client-only table of constants plus a few helpers. It is **not** pure-logic
(it holds `Color3`/`Enum`/`UDim`), so it is not lune-tested; it is the client's
presentation source of truth. It maps the semantic `accent` strings that
`RoundScreenModel` already returns (`"neutral" | "win" | "lose"`) to concrete colors —
preserving the rule that the pure model stays Roblox-free.

**Data**

- `HudTheme.Font` — `title = Enum.Font.FredokaOne`, `heading = Enum.Font.FredokaOne`,
  `body = Enum.Font.GothamMedium`.
- `HudTheme.Color`:
  - `textPrimary = Color3.fromRGB(255, 255, 255)`
  - `textStroke = Color3.fromRGB(20, 24, 31)` (dark outline on text)
  - `panelStroke = Color3.fromRGB(255, 255, 255)` (thick white panel outline)
  - `shadow = Color3.fromRGB(0, 0, 0)`
  - `pill = Color3.fromRGB(255, 210, 63)` (the small WINNER pill fill)
  - `pillText = Color3.fromRGB(90, 61, 0)`
  - `panelDark = Color3.fromRGB(17, 22, 31)` (the neutral dark fill for the bottom pill)
- `HudTheme.Accent` — semantic-string → panel gradient stops `{ top, bottom }`:
  - `neutral = { top = Color3.fromRGB(58,160,240),  bottom = Color3.fromRGB(47,127,208) }`
  - `win     = { top = Color3.fromRGB(56,210,122),  bottom = Color3.fromRGB(30,167,92)  }`
  - `lose    = { top = Color3.fromRGB(240,88,78),   bottom = Color3.fromRGB(200,58,50)  }`
- `HudTheme.Cap` — pixel `Vector2` max sizes (the bottom pill never exceeds the banner):
  - `banner = Vector2.new(340, 150)`
  - `bottomLine = Vector2.new(240, 66)`
  - `notice = Vector2.new(320, 80)`
  - `timer = Vector2.new(120, 76)`
- `HudTheme.Zone` — named `{ anchor = Vector2, position = UDim2 }`:
  - `top      = { anchor = (0.5,0),   position = UDim2.new(0.5,0,0,14) }`   (banner)
  - `topTimer = { anchor = (0.5,0),   position = UDim2.fromScale(0.5,0.04) }` (swap timer)
  - `center   = { anchor = (0.5,0.5), position = UDim2.fromScale(0.5,0.40) }` (big 3/2/1)
  - `notice   = { anchor = (0.5,0.5), position = UDim2.fromScale(0.5,0.62) }` (eliminated)
  - `bottom   = { anchor = (0.5,1),   position = UDim2.new(0.5,0,0.97,0) }`  (next round)
- `HudTheme.Radius = UDim.new(0, 18)`, `HudTheme.PillRadius = UDim.new(0, 16)`
- `HudTheme.PanelStrokeThickness = 4`, `HudTheme.TextStrokeThickness = 2`
- `HudTheme.ShadowOffset = 6` (studs/px down), `HudTheme.PopInTime = 0.25`
- `HudTheme.DisplayOrder = { swap = 5, bookend = 10 }` (bookend renders above the flash).

**Helpers** (small, well-bounded):

- `HudTheme.applyMaxSize(guiObject, capKey)` — adds a `UISizeConstraint` with
  `MaxSize = HudTheme.Cap[capKey]`. Returns the constraint.
- `HudTheme.styleText(label, fontKey)` — sets `Font = HudTheme.Font[fontKey]`,
  `TextColor3 = textPrimary`, `TextScaled = true`, and adds a dark text `UIStroke`
  (`textStroke`, `TextStrokeThickness`). One call = consistent readable text.
- `HudTheme.stylePanel(frame)` — one-time decoration of a panel `Frame`: adds `UICorner`
  (`Radius`), a white `UIStroke` (`panelStroke`, `PanelStrokeThickness`), a `UIGradient`
  (vertical), and an offset "hard shadow" (a dark sibling `Frame` behind it: same size,
  `Position` offset down by `ShadowOffset`, `ZIndex` one below, own `UICorner`). Sets
  `frame.BackgroundColor3 = white` so the gradient shows. Returns
  `{ gradient = UIGradient, shadow = Frame }` so the caller can recolor/reposition.
- `HudTheme.setPanelAccent(handle, accentKey)` — sets the panel's `UIGradient.Color`
  from `HudTheme.Accent[accentKey]` (top→bottom). Drives the whole-panel state color.
- `HudTheme.popIn(guiObject, targetSize)` — sets `Size = 0` then tweens to `targetSize`
  with `Back/Out` over `PopInTime` (the bouncy entrance). Caller invokes on show.

### Component 2 — `src/client/ClientRoundHud.luau` (migrate)

Behavior (what shows when) is unchanged — only the *rendering* is re-skinned via
`HudTheme`. Specifically:

- The **banner** becomes a styled panel: `HudTheme.stylePanel` + `Zone.top` +
  `applyMaxSize(banner, "banner")`; its `Size` uses scale (`~0.6 × 0.16`) under the cap.
  On each `applyDisplay`, call `HudTheme.setPanelAccent(handle, d.accent)` so the panel
  fill is green/red/blue by state (replacing the inline `ACCENT` stroke-only map, which
  is **removed** — colors now come from `HudTheme`).
- The **WINNER tag** becomes the yellow pill (`Color.pill` / `Color.pillText`), shown
  when `d.winnerName ~= nil`.
- Title (`Victory`/`Defeated`/`Round over`/lobby lines) and subtitle use
  `HudTheme.styleText(..., "title")` / `("body")`.
- The **bottom line** becomes a fixed **dark pill** (not state-colored): a `Frame`
  styled by `HudTheme.stylePanel` with its gradient set to a flat `Color.panelDark`
  (call `setPanelAccent` is *not* used here), holding a `styleText(..., "body")` label;
  placed at `Zone.bottom` + `applyMaxSize(bottomLabel, "bottomLine")`.
- The **eliminated notice** moves to `Zone.notice` (below center), `applyMaxSize(elim,
  "notice")`. It is **transparent text** (no panel): `styleText(elim, "heading")` then
  override `TextColor3 = HudTheme.Accent.lose.top` so it reads as a clear red callout
  over the arena.
- The banner and bottom line **pop in** (`HudTheme.popIn`) when they transition from
  hidden→visible (track previous visibility to fire only on the rising edge).
- `gui.DisplayOrder = HudTheme.DisplayOrder.bookend`.
- All preserved behavior (spectate retarget, Active-only notice + cross-remote guard,
  phase-based clear) stays exactly as in the current committed file.

### Component 3 — `src/client/ClientSwapHud.luau` (migrate)

- **Timer** → `Zone.topTimer` + `applyMaxSize(timer, "timer")` +
  `styleText(timer, "heading")`.
- **Big countdown** → `Zone.center` + `styleText(big, "title")` (FredokaOne, big).
- **Flash** unchanged (keeps `Config.TELEGRAPH_FLASH_COLOR` and its `RenderStepped`
  intensity logic). `gui.DisplayOrder = HudTheme.DisplayOrder.swap`.
- No change to the telegraph timing or `SwapTelegraphModel` usage.

## Testing

- **No new lune test:** `HudTheme` is presentation data/style (Roblox types), and the
  pure models (`RoundScreenModel`, `SwapTelegraphModel`) are untouched — their existing
  lune suites must still pass.
- **Studio smoke test (extend the existing one):** update
  `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md` (or add a sibling) with a
  HUD-consistency pass run on **both** a wide desktop window and a narrow phone-sized
  window:
  1. Banner, bottom line, and notice are all capped (no full-width slab) and centered;
     the bottom pill is no wider than the banner.
  2. Panel fill color matches state (blue lobby, green victory, red defeat); text is
     white with a dark outline and readable at small size.
  3. The eliminated notice sits **below** the big swap countdown — never stacked on it,
     even for a dead spectator during a swap preview.
  4. Banner/bottom line pop in (bounce) rather than snapping.
  5. The swap timer number stays small/capped (doesn't balloon on desktop).

## Edge cases & accessibility

- **Mobile/desktop:** every element is scale-driven but pixel-capped (`UISizeConstraint`)
  so it neither balloons on desktop nor shrinks unusably on phones (`Cap` values double
  as the practical desktop size; scale handles down-scaling).
- **Color is never the only signal:** outcome is always carried by a word
  (VICTORY/DEFEATED) and the WINNER pill, not just the panel hue (colorblind-safe).
- **Contrast:** white text + dark `UIStroke` keeps text legible over any panel color and
  over the bright arena behind the keep-arena-visible banner.
- **Font fallback:** `FredokaOne` is a built-in Roblox font; if unavailable on a platform
  the engine substitutes a default — text still renders (no hard dependency).

## Files touched

| File | Change |
|------|--------|
| `src/client/HudTheme.luau` | **new** — shared client HUD theme (fonts/colors/caps/zones) + helpers |
| `src/client/ClientRoundHud.luau` | migrate banner / bottom line / notice onto `HudTheme`; remove inline `ACCENT`; state-colored panel; pop-in; notice → its own zone |
| `src/client/ClientSwapHud.luau` | migrate timer / big countdown onto `HudTheme` zones/caps/fonts; set `DisplayOrder` |
| `docs/smoke-tests/2026-06-20-round-bookends-smoke-test.md` | extend with the HUD-consistency + kid-friendly checks (desktop + mobile) |
