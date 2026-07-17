# Soul Shop Slice 1 — Solo Studio Verification Record (2026-07-16)

**Session:** MCP-driven, Studio solo Play, `SOLO_TEST_MODE = true` + `ARENA_OVERRIDE = "sweeper"`
dev pins active. Branch `feat/soul-shop-slice1` at `b89a122`. Spec:
[2026-07-16-soul-shop-slice1-design.md](../superpowers/specs/2026-07-16-soul-shop-slice1-design.md).

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
