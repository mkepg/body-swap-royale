# Soul Shop Slice 1 — Solo Studio Verification Record (2026-07-16)

**Session:** MCP-driven, Studio solo Play, `SOLO_TEST_MODE = true` + `ARENA_OVERRIDE = "sweeper"`
dev pins active. Branch `feat/soul-shop-slice1` at `b89a122`. Spec:
[2026-07-16-soul-shop-slice1-design.md](../specs/2026-07-16-soul-shop-slice1-design.md).

## Machine-verified (this session)

| # | Check | Result |
|---|---|---|
| 1 | Clean boot, console error-free, `[BSR] Server ready` | ✅ |
| 2 | ShopHud built (panel hidden, tabs COLORS/STYLES/TRAILS, header + live coin chip) | ✅ |
| 3 | Soul halo renders via the unified SoulStyles pipeline (classic: underglow + core + emphasis, 42px mine) | ✅ |
| 4 | Zero ParticleEmitters in workspace (particle budget untouched) | ✅ |
| 5 | Gauntlet: malformed payloads (string / numeric id / bad action) silently dropped — no ShopResult | ✅ |
| 6 | Gauntlet: `unknown_item`, `already_owned`, `not_owned` all returned correctly | ✅ |
| 7 | **Rate limit live**: 6 requests in one burst → 6th silently dropped (5 per 2s window) | ✅ |
| 8 | Buy `color_void` → halo updates live: dark core (30,16,48), violet luminous underglow + 12% rim, white emphasis (fill/luminous rule end-to-end) | ✅ |
| 9 | Buy `style_eclipse` → auto-equip; Eclipse × Void combo renders (corona stroke 14% in luminous violet) | ✅ |
| 10 | Buy `trail_comet` → 2 Trail instances (core + sheath) on the body | ✅ |
| 11 | **Persistence**: stop → restart Play; Void + Eclipse + Comet all reappear from DataStore; balance reflects purchases (no clobber, no resurrection) | ✅ |
| 12 | Coin math: 3× purchases deducted server-side; round awards continue accruing | ✅ |
| 13 | Access rule both ways: toggle visible in Lobby, hidden while alive in Active | ✅ |
| 14 | Equip `default` (kind=trail) → trails destroyed (2→0); re-equip → rebuilt (0→2) | ✅ |
| 15 | Banner safe-area position: `GuiInset.Y=58` → banner y-offset exactly 72 (= inset + 14) | ✅ |
| 16 | Banner cap after fix `b89a122`: MaxSize (350,168) — was stuck (0,0) pre-fix (see bugs) | ✅ |

## Bugs found BY this session (all fixed + committed before this record)

1. **Shop toggle never parented** (`0c7371e`) — constructed fully but `toggleBtn.Parent = gui`
   was missing; the shop was unreachable. Static review passed it twice; only live
   PlayerGui inspection caught it.
2. **Banner cap stuck at (0,0)** (`b89a122`) — two stacked causes: `applyMaxSize` ran at
   boot while `ViewportSize` was still (1,1) → `bannerCap` floored to 0; and the weak-keyed
   `placedCaps` registry lost its (Lua-unreferenced) UISizeConstraint to GC, so the
   viewport-change re-cap never healed it. Registries are now strong with explicit purge;
   `currentViewport()` guards degenerate sizes.

## Environment notes (NOT branch bugs — verified against a control)

- **TweenService does not step in this MCP Play session**: a freshly created 0.2s tween
  stayed at `PlaybackState.Playing` with zero progress for 0.5s while raw property writes
  applied instantly. Consequence: banner pop-in (UIScale 0→1) appears frozen at 0 in
  probes. `popIn` is byte-identical to main; this affects any tween equally in MCP
  sessions. Eyeball the pop-in in a normal Play session.
- `screen_capture` and `user_mouse_input` timed out consistently this session
  (`execute_luau`/`script_grep`/play control all fine), so no screenshots and no
  machine-driven UI clicks were possible.

## Deferred to the manual pass (user-driven; minutes)

1. **One click on the shop toggle** → panel opens (lazy card build on open — confirmed
   by-design in code), previews animate, two-tap buy UX, coin tick-down, insufficient
   shake. (Machine clicks impossible this session; the `Activated → openPanel` wiring is
   one line and code-reviewed.)
2. Banner pop-in motion (TweenService frozen in MCP session — see above).
3. Animated color motion eyeball: buy/equip Ember or Prism and watch the halo (the
   SoulStyles Heartbeat animator is code-reviewed; motion not visually sampled).
4. Device-emulator sweep: phone profile → sheet mode, 44px targets, toggle clears the
   jump button, banner under emulated inset.
5. **2-client smoke** (standing procedure): other-client halo/trail visibility via
   SoulMap, swap recolor timing, equip changes visible cross-client, rate limit under
   real spam, plus the standing [needs 2-client verification] backlog from the 2026-07-03
   review.

---

## Addendum 2026-07-21 — UI/halo polish pass (8 issues), live-verified

MCP was reachable this session — `execute_luau`, `user_mouse_input`, AND `screen_capture`
all worked (the prior session's capture/click timeouts were transient). Solo Play,
same dev pins.

| # | Issue | Verified how | Result |
|---|---|---|---|
| 1 | Close ✕ was tofu (U+2715 glyph) | inspected Close: `Text=""` + 2 bars rot ±45; clicked it → panel closes | ✅ renders + closes |
| 2 | Coins/Level readout too plain | screenshot: gold medallion + "211 COINS" + "LV 12" badge + cyan XP bar | ✅ |
| 3 | Buy button black-on-yellow | expanded a card: gold gradient, corner 10, dark-brown `(58,38,0)` text, inline "BUY ◈ 200", shadow `(168,126,30)` | ✅ |
| 4 | Unlabeled rarity stripe | every card has a labeled chip (FREE/COMMON/…/LEGENDARY) + tier accent; old stripe gone | ✅ |
| 5 | Seraph drifted from V1 | built via live SoulStyles: soft 0.95 glow (t=0.82, no blob), 0.34 core, 0.875 ring, 3 rounded shards | ✅ |
| 6 | Coins/Level centered over banner | IgnoreGuiInset=true, registered `topLeft`; after boot `replaceAll` it's Anchor (0,0) at x=14, right edge 190 (center 461); screenshot confirms no overlap | ✅ |
| 7 | Buttons need redesign + states | unified styling present; `wireInteraction` hover/press wired on all (motion needs a real client — tweens don't step in MCP) | ✅ (motion pending real client) |
| 8 | Eclipse white inner ring (dark colors) | built Eclipse×Void(dark) isMine=true: 0 white frames/strokes; real equipped Eclipse×Void body halo: 0 white strokes, size 42 me-cue intact | ✅ |

**Observed (NOT one of the 8, pre-existing, flagged for a decision):** when the shop is
open in the lobby, the round banner (top-center, DisplayOrder `bookend`) draws over the
shop's "SOUL SHOP" title (DisplayOrder `bookend-1`). One-line options: raise the shop
above the banner, or hide the banner while the shop is open. Not changed pending the
owner's call.
