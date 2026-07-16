# Soul Shop — Slice 1 (Catalog + Direct Purchases) — Design

**Date:** 2026-07-16
**Status:** Approved design (brainstormed with user; catalog v1 selected from two
presented iterations, then widened to 15 colors and amended with the Option-A
identity-color resolution, responsive-UI, banner-safe-area, and halo-upgrade
directives — animated concept sheets preserved at
[assets/2026-07-16-soul-shop-v1-concepts.html](assets/2026-07-16-soul-shop-v1-concepts.html)
(approved) and
[assets/2026-07-16-soul-shop-v2-expansion-reference.html](assets/2026-07-16-soul-shop-v2-expansion-reference.html)
(future content reference)).
**Context:** Critical-review Action list "first coin sink" (2026-07-03 review §5/§6:
"earning currency that can't be spent teaches players the number is meaningless") +
GDD §8's Soul monetization lane. The user chose to build toward the GDD-scale shop,
decomposed into slices; this spec is slice 1.

---

## §1 Goal

The first coin sink: a Soul cosmetic shop where players spend round-earned coins on
permanent halo colors, halo styles, and soul trails, equip them, and see them persist
across sessions. Makes every coin earned retroactively meaningful; validates the GDD's
flagship "Soul" cosmetic lane before any Robux monetization.

## §2 Scope decomposition (the GDD-scale shop, sliced)

| Slice | Contents | Status |
|---|---|---|
| **1 (this spec)** | Catalog + rarity model, direct coin purchases, inventory/equip persistence, purchase channel, responsive shop UI, 25-item v1 catalog, server-authoritative identity-color resolution, Soul Halo rendering upgrade, HUD safe-area system + Main Lobby Banner redesign | Approved |
| 2 | Cosmetic boxes / random drops (rarity weights, duplicate handling), v2 catalog expansion (Gemini, Skybound, broadcast-glitch colors, arena-homage styles — see the v2 reference sheet), world try-on preview | Parked |
| 3 | Featured rotation, seasonal/limited items | Parked |
| 4 | Robux products (premium Souls, coin packs) via MarketplaceService | Parked |

Swap-in signatures (GDD §5) are explicitly **out of scope for all current slices** —
they touch the swap-commit presentation path.

## §3 Decision record

1. **The zero client→server remote property is deliberately retired.** The game
   previously had zero client→server remotes (2026-07-03 review §2.5 called this "rare
   and excellent"). A shop inherently needs upstream intent. Options were designed and
   compared (world-anchored physical shop preserving the property vs. a validated
   remote); the user chose the **validated remote** (scales to the GDD-scale shop
   trajectory). The replacement guarantee is the **validation contract** (§5): the
   client message is a *claim*, never a command — the server independently verifies
   catalog membership, ownership, balance, and rate before acting. Nothing in the
   channel can grant a survival advantage (GDD §8 anti-pay-to-win guardrail intact).
2. **Approach A architecture** (user-approved): pure `ShopModel` decisions +
   `EconomyService` extension + RemoteEvent pair. No RemoteFunction, no second
   profile-owning service.
3. **Shop access:** lobby + eliminated spectators (never while alive in an active
   round). Turns dead-time into browse-time; addresses the review's "eliminated
   experience is thin" note.
4. **Catalog v1** chosen over the 29-item v2 expansion (v2's additions are recorded
   as slice-2 content candidates, not rejected), then widened per decision #8 to the
   25-item set in §7.
5. **Buying auto-equips** the purchased item into its slot (instant gratification;
   the buyer's intent is unambiguous).
6. **Pricing bands are per-rarity Config knobs** with per-item override support;
   exact values in §8, derived from the live earn model (~50 coins/typical round).
7. **Identity-color resolution is server-authoritative (Option A, user-selected).**
   The purchased-color-vs-assigned-color conflict is resolved by:
   `resolvedColor = equipped halo_color's fill, else the auto-assigned palette
   color` — computed on the SERVER, broadcast as `SoulMap.color`, so every consumer
   of "player X's color" (halos today, any future banner/spectate surface) agrees by
   construction. Free assignment continues untouched for non-buyers and stays
   distinct among them. **The premium palette is disjoint by design from the 8 free
   hues** — machine-checked (§10): every *static* premium fill must sit at RGB
   Euclidean distance ≥ 90 from every free palette color. Animated colors are exempt
   (their identity is the motion signature) but must be mutually distinct. Two
   players wearing the same purchased color is accepted: emphasis answers "which is
   me"; styles/trails/nameplates answer "who is who".
8. **Widened v1 color catalog** (user-directed): 15 colors (was 9), pulling the
   broadcast-glitch family forward from the v2 exploration and adding new pales/
   pastels/darks. Full table in §7.
9. **Shop UI must be fully responsive/adaptive** (user-directed): dynamic layouts
   and scaling over fixed positioning; clean and balanced on desktop, tablet, and
   mobile at all supported aspect ratios; explicit safe-area handling (§6.2–6.3).
10. **The Main Lobby Banner is redesigned in this slice** (user-directed): on mobile
   it currently collides with the Roblox top menu. Placement, sizing, margins, and
   safe-area handling are reworked so it never overlaps Roblox core UI (§6.3).
11. **The Soul Halo base rendering is upgraded** (user-authorized): the free Classic
   halo re-renders through the same `SoulStyles` pipeline as premium styles — one
   rendering path, no special cases — with a quality pass on the default look (§6.1).

## §4 Data model

### §4.1 `src/shared/ShopCatalog.luau` (new — pure data)

Array of item records; no logic, no Roblox APIs beyond Color3 values (kept here so
the catalog is the single visual source of truth for BOTH server validation and
client rendering; lune tests inject plain tables where color equality suffices).

```luau
{
  id = "halo_color_void",       -- permanent; persisted into profiles; never renamed
  kind = "halo_color",          -- "halo_color" | "halo_style" | "trail"
  name = "Void",                -- display only
  rarity = "rare",              -- "common"|"uncommon"|"rare"|"epic"|"legendary"
  price = nil,                  -- nil => Config.SHOP_PRICES[rarity]; number overrides
  -- kind-specific payload:
  fill = Color3.fromRGB(30,16,48),       -- halo_color: base color
  luminous = Color3.fromRGB(190,120,255),-- halo_color: glow variant (default = fill)
  anim = { kind = "none"|"osc"|"flicker"|"steps"|"sweep"|"gradient"|"flash"|"hue", ... },
  -- halo_color motion: osc=smooth 2-color, flicker=irregular 2-color, steps=hard
  -- snaps (glitch family), sweep=UIGradient band, gradient=multi-stop drift,
  -- flash=static fill + timed luminous rim pulse, hue=full rotation
  styleKey = "eclipse",                  -- halo_style: renderer key
  trailKey = "comet",                    -- trail: renderer key
}
```

**The fill/luminous rule:** every color declares a `luminous` variant (defaults to
`fill`). Style glow elements (Eclipse corona, Seraph ring) and trails bind `luminous`;
solid elements bind `fill`. This is what makes dark colors (Void) compose with every
style without dark-on-dark illegibility.

### §4.2 `src/shared/ShopModel.luau` (new — pure, lune-tested)

All purchase/equip decisions:

- `validatePurchase(profile, catalog, itemId)` → `{ ok = true, item = item }` or
  `{ ok = false, err = "unknown_item" | "already_owned" | "insufficient_coins" }`
- `applyPurchase(profile, item)` → deducts `price`, appends to `ownedItems`, sets
  `equipped[item.kind] = item.id` (auto-equip, decision #5). Pure transform.
- `validateEquip(profile, catalog, itemId)` → ok/err (`unknown_item` | `not_owned`);
  `itemId == "default"` is always valid for any kind and clears the slot.
- `applyEquip(profile, kind, itemIdOrDefault)`.
- `priceOf(item, prices)` → item.price or prices[item.rarity].

### §4.3 `ProfileModel` extension

Persisted blob gains `ownedItems` (unique string list — existing `toStringList`
sanitizer) and `equipped` (table with keys `halo_color`/`halo_style`/`trail`, string
values; unknown keys/types dropped by sanitize). `Config.PROFILE_VERSION` bumps.
No migration needed — `sanitize` coerces old blobs (missing fields → empty).
Equipped ids are **re-validated against the catalog at render and equip time**, so a
later catalog removal degrades to default instead of erroring.

## §5 Server flow

### §5.1 Remotes

`REMOTE_EVENTS` gains `"ShopRequest"` (client→server — **the first**) and
`"ShopResult"` (server→client).

### §5.2 `EconomyService.onShopRequest(player, payload)` — the validation gauntlet

In order; every rejection fires `ShopResult { ok=false, err=... }` except rate-limit
excess and malformed payloads, which are dropped silently (honest clients cannot
produce them):

1. **Rate limit** — per-player sliding window, `Config.SHOP_RATE_MAX = 5` requests
   per `Config.SHOP_RATE_WINDOW = 2` seconds.
2. **Payload sanitation** — table; `action ∈ {"buy","equip"}`; `itemId` string,
   ≤ 64 chars.
3. **Profile gate** — profile must be loaded AND `persisted == true` (the existing
   no-clobber flag). A player must never spend coins that can't save.
   `err = "profile_unavailable"`.
4. **ShopModel decision** (§4.2) → apply to cached profile.
5. **Notify** — `ShopResult { ok=true, action, itemId }` to the requester +
   the existing `ProfileUpdated` (new balance) + SoulMap re-broadcast (§5.3).
6. **Save policy** — mark dirty; debounced async save `Config.SHOP_SAVE_DEBOUNCE = 5`s
   after the last purchase (not per-request), atop existing save-on-leave/BindToClose.

Purchases are processed sequentially on the single server Luau thread — a same-tick
duplicate buy resolves as `already_owned`, no locking needed.

### §5.3 Replication of equipped looks

The existing `SoulMap` broadcast entry grows from `{ body, color }` to
`{ body, color, colorId?, styleId?, trailId? }`. Ids are the wearer's equipped
items; clients resolve them against the shared catalog; unknown/missing ids render
as the free default. No new replication channel; premium looks reach every client
through the path that already re-parents identity on swap.

### §5.4 Identity-color resolution (server-authoritative)

Per decision #7: the server computes `resolvedColor` = equipped color's `fill`
(from the shared catalog) when a valid `halo_color` is equipped, else the
auto-assigned `SoulPalette` color — and broadcasts THAT as `SoulMap.color`. The
`colorId` rides alongside so clients can run the color's animation spec locally
(an animated color's `fill` is its representative base for any consumer needing a
single Color3). A pure `SoulResolveModel.resolve(profileEquipped, catalog,
assignedColor)` function owns this decision and is lune-tested. Invalid/stale
equipped ids resolve to the assigned color (never an error).

## §6 Client

### §6.1 Rendering (`SoulController` + new `SoulStyles` module)

- **One rendering pipeline for every halo, free included.** `SoulStyles.build(styleKey,
  colorSpec, sizePx)` returns the billboard gui tree for ALL styles; the free look is
  `styleKey = "classic"` — the current inline dot construction in `SoulController`
  is deleted, not special-cased. This is the long-term architecture: adding a style
  is adding a builder, never touching the reconcile loop.
- **Classic gets a quality pass** (decision #11): the flat dot becomes a layered
  construction — core dot + soft under-glow disc (larger, semi-transparent circle
  behind the core) + the emphasis stroke — so even the free halo reads as an object
  with depth rather than a UI dot, and premium styles inherit the same layered
  language. Same instance budget class (≤3 frames); exact values tuned in the
  Studio visual pass against the dusk sky.
- **Halo styles** are pure billboard-UI constructions (zero particles — the 50-particle
  low-tier budget stays untouched at 16 players). The mine-emphasis rule (2× size,
  42px vs 24px, + stroke) applies to every style's primary element unchanged.
- **Emphasis stroke auto-darkens** to `(20,24,31)` when the fill's luminance > 0.75
  (the pale family — Moonlit/Frostbite/Seafoam/Roseglass — and any future pale) so
  "which one is me" never washes out.
- **Animated colors** run in ONE shared Heartbeat animator (`SoulStyles.step`) driving
  every animated halo on screen; per-frame cost ≤ 16 color writes (within the review
  §2.7 cosmetic per-frame budget line).
- **Trails**: `SoulController` maintains ≤ 2 `Trail` instances per body (Comet and
  Meteor use 2; all others 1), attachments on the torso, `Color` bound to the wearer's
  luminous color. On swap the trail properties are re-bound to the new controller's
  equips; `Trail.Color` reassignment recolors live segments (verify in the Studio
  pass; if segments keep old color briefly, accept — sub-second).
- Trail specs: Wisp (width 0.35 studs, lifetime 0.45s), Soul Stream (1.4, 0.8s),
  Sparkline (0.9, 0.6s, 5-hump WidthScale), Comet (core 0.35 near-white + sheath 1.8,
  1.0s), Meteor (2 × 0.55 on shoulder offsets, 1.2s, alternating 1.1s opacity pulse).
- `SOUL_HALO_ENABLED = false` suppresses all cosmetic rendering as today (marketing
  screenshots); the shop itself still functions.

### §6.2 Shop UI (`ClientShopHud`) — responsive by construction

- **Layout is derived, never fixed** (decision #9): a pure, lune-tested
  `ShopLayoutModel.layout(viewportW, viewportH, guiInset)` returns the panel
  geometry, grid column count, card size, and type scale — the same pattern as the
  shipped `TouchJumpLayout`. Rendering consumes the model's output; no hardcoded
  pixel positions.
- **Breakpoint behavior:** wide viewports (desktop/tablet landscape) get a
  right-anchored side panel (38% width, clamped 330–460 px) with a 2-column card
  grid — the world and your body stay visible, so equips render live on you.
  Short/narrow viewports (phones, landscape-locked per the mobile control model)
  shrink to a denser panel with reduced paddings and a minimum 44 px touch-target
  floor; if the panel would cover > 55% of the viewport width it becomes a
  full-height sheet with a close affordance. Text uses `TextScaled` +
  `UITextSizeConstraint` caps; the grid uses `UIGridLayout` + aspect-ratio
  constraints so cards reflow instead of clipping.
- **Safe areas:** all shop chrome respects `GuiService` insets (Roblox top bar,
  notches) via the shared safe-area helper introduced in §6.3 — nothing renders
  under core UI on any device.
- HudTheme language throughout: FredokaOne headings, panelDark, white stroke,
  Radius 18. Header: title + coin chip (live from `ProfileUpdated`). Tabs: COLORS /
  STYLES / TRAILS. Cards sorted rarity-ascending then price.
- **Cards render live previews with the same `SoulStyles` constructions the world
  uses** — the preview IS the product. Trail cards use a small animated ribbon mock.
- Card states: price tag → (tap) expanded card with BUY → owned: EQUIP → equipped:
  glowing border + EQUIPPED. **Two-tap buy** guards against touch misfires.
- Feedback: success = coin count tick-down + card burst; `insufficient_coins` = chip
  shake + red flash; `profile_unavailable` = shop button disabled with hint text.
- **Access rule:** the shop toggle button is visible only when the local player is
  not alive in an active round — lobby phases, or eliminated (spectating). Derived
  from existing `RoundStateChanged` + elimination client state; no new remotes.
- Rarity chips: Common `#b8c0cd` · Uncommon `#5ed17a` · Rare `#4da6ff` ·
  Epic `#b06cf0` · Legendary gold `#ffc94d` with sweep shimmer.

### §6.3 HUD safe-area system + Main Lobby Banner redesign

- **Root cause, fixed once:** `HudTheme.Zone.top` places banners at a fixed
  `y = 14 px`, which sits under the Roblox top menu on mobile. Slice 1 introduces
  a **safe-area layer in HudTheme**: zones are computed from
  `GuiService:GetGuiInset()` / `ScreenInsets` at runtime (and recomputed on
  viewport change), so EVERY zone consumer — round banner, swap telegraph, notices,
  the new shop — inherits correct placement. No per-screen patches.
- **Main Lobby Banner** (the round-state banner rendered via `HudTheme.Zone.top` +
  `Cap.banner`): re-placed below the computed safe top with a breathing margin;
  size caps become viewport-relative (cap shrinks on short viewports rather than
  overlapping); pop-in animation preserved. Visual polish pass (margins, stroke,
  gradient) to match the shop's finish. Verified on desktop, tablet, and phone
  viewport profiles in the Studio pass.
- The existing zone API (`HudTheme.placeInZone`) keeps its signature — consumers
  are untouched except where they cached positions.

## §7 Catalog v1 (25 items)

### Halo colors (15) — premium = "light the free palette can't make"

Three families: **pale light** (static commons), **living color** (smooth animation),
**broadcast glitch** (hard step-cuts — the game-show family). Static fills are
machine-checked disjoint from the free palette (decision #7).

| Item | Rarity | Family | Visual spec |
|---|---|---|---|
| Moonlit | Common | pale | static pale lavender-white `(226,218,255)` |
| Frostbite | Common | pale | static glacial ice `(190,235,255)` |
| Seafoam | Common | pale | static soft mint `(170,255,190)` |
| Roseglass | Common | pale | static pale blush `(255,224,236)` |
| Ember | Uncommon | living | flicker `(200,30,20)` ↔ `(255,150,54)`, irregular ~1.3s (two overlaid sine phases) |
| Tidepool | Uncommon | living | smooth 4s oscillation `(30,90,220)` ↔ `(45,220,200)` |
| Cotton Candy | Uncommon | living | pastel 3.5s oscillation `(255,183,221)` ↔ `(178,216,255)` |
| Neon Buzz | Uncommon | glitch | failing-sign stutter: warm neon `(255,233,201)` snapping to dead `(84,72,60)` in step-cuts, ~2.8s loop |
| Void | Rare | dark | fill `(30,16,48)` + **luminous rim** `(190,120,255)` (rendered as ring child, not the emphasis stroke) |
| Static | Rare | glitch | channel-hop: hard snaps across off-air tints `(205,212,222)` / `(159,216,222)` / `(222,196,184)` / `(170,182,216)`, ~3.4s loop |
| Duskfall | Rare | living | vertical UIGradient plum `(122,75,214)` → rose `(232,106,154)` → amber `(255,179,92)`, offset drifting over 7s — the festival sunset worn |
| Stormcloud | Rare | dark | fill slate `(70,80,105)` + lightning tick: luminous `(200,215,255)` rim flash twice, ~4s loop |
| Gilded | Epic | living | metallic sweep `(201,154,46)` ↔ `(255,224,138)`, 3s period (UIGradient offset) |
| Aurora | Epic | living | 6s oscillation `(200,110,255)` ↔ `(120,255,180)` — base = `WORLD_AURORA_BASE_COLOR` |
| Prism | Legendary | living | full hue rotation, 8s period, S 0.72 / V 1.0 |

### Halo styles (5) — colorless frames; any style × any color

| Item | Rarity | Construction |
|---|---|---|
| Ring | Uncommon | hollow annulus, ring thickness ≈ 18% of billboard px |
| Pulse | Uncommon | solid dot + ripple ring scaling 1→1.9, fading, 1.6s loop |
| Twin Orbit | Rare | core dot 70% + rotating carrier (3s/rev) with two 25% satellites |
| Eclipse | Epic | dark disc `(25,16,38)` + thick luminous border + outer glow |
| Seraph | Legendary | thin outer ring (6s/rev) carrying 3 diamond shards + core dot + 2.4s ripple |

### Soul trails (5) — inherit the wearer's luminous color; recolor on swap

| Item | Rarity | Behavior |
|---|---|---|
| Wisp | Uncommon | thin whisper, quick fade |
| Soul Stream | Rare | wide silk ribbon |
| Sparkline | Rare | beaded dashes (WidthScale humps) |
| Comet | Epic | white-hot core + soft color sheath (2 trails) |
| Meteor | Legendary | twin shoulder streams, alternating pulse (2 trails) |

Cut during design iteration (recorded so they aren't re-proposed): Graphite (illegible
on dusk sky), static Gold (collides with free yellow at 24px), Spike Crown (mush at
24px), 3D part-based halos (breaks AlwaysOnTop consistency + per-body render cost).

## §8 Pricing

`Config.SHOP_PRICES = { common = 200, uncommon = 450, rare = 900, epic = 1800,
legendary = 4000 }`. At the live earn model (≈50 coins/typical round;
`REWARD_COINS_BASE 15 + 4/swap + 40 win`): first purchase within session one
(~4 rounds), legendary ≈ 80 rounds. Full v1 collection (25 items) = ◈29,450 ≈ a
committed month — headroom under the GDD's "~3 months for a meaningful collection"
curve for slices 2–3. All knobs post-playtest tunable; per-item `price` override
supported.

## §9 Edge cases

- **Profile not persisted** (DataStore outage): purchases rejected (§5.2 gate) —
  never spend unsaveable coins.
- **Same-tick duplicate buy:** sequential processing → second returns `already_owned`.
- **Equip while eliminated/no body:** allowed; renders on next controlled body.
- **Item later removed from catalog:** profile keeps the id (never destructively
  cleaned); render + equip validation degrade to default; shop hides it.
- **Player leaves mid-debounce:** existing save-on-leave flushes the dirty profile.
- **Emphasis vs pale colors:** stroke auto-darken rule (§6.1).
- **Free-color auto-distinctness** (GDD edge case) is intentionally weakened: two
  players CAN now wear the same purchased color. Accepted — styles/trails/emphasis
  still disambiguate, and the GDD's premium lane always implied this. Premium-vs-free
  collisions are prevented structurally by the disjoint-palette invariant (§3 #7).
- **Animated colors at a frozen glance:** a mid-animation frame may pass near a free
  hue (Ember sweeps through orange). Accepted — the motion signature is the identity
  and animation never pauses; only *static* fills carry the distance invariant.

## §10 Testing

**lune (pure):** `shop_model.spec` (every validate/apply path incl. all error codes,
auto-equip, default-equip, price override); `profile_model.spec` extension (sanitize
garbage `ownedItems`/`equipped`); `shop_catalog.spec` (unique ids, known kinds &
rarities, luminous defaulting, positive prices, **static-fill disjointness: RGB
Euclidean distance ≥ 90 from every `SOUL_PALETTE` entry**); `soul_resolve_model.spec`
(equipped > assigned, stale-id fallback); `shop_layout_model.spec` (panel/grid/type
outputs across desktop, tablet, and phone viewport profiles, inset handling,
44 px touch-target floor, sheet-mode threshold).

**Studio smoke (2-client):** buy → other client sees the new halo via SoulMap; equip
persists across rejoin; insufficient-coins and rate-limit paths; 24px other-player
legibility for every style on the dusk sky; animated colors; trail recolor at swap;
**responsive sweep** — shop panel + Main Lobby Banner at desktop, tablet, and phone
viewport sizes with the Roblox top bar inset (banner must clear core UI on every
profile); Classic halo quality pass vs the current dot.

## §11 Out of scope (slice 1)

Boxes/drops, featured rotation, Robux, swap-in signatures, world try-on of unowned
items, achievements/daily rewards (GDD §8 lists them; separate systems), any
`GLOW_DIM_*` extension to premium cosmetics.

## §12 Execution

Branch `feat/soul-shop-slice1` (created off `main` at `b7bf8cf`). writing-plans →
subagent-driven execution (fresh subagent per task; spec review + code-quality review
per task). CHANGELOG entry at the end. **Never commit the dev flips** in
`src/shared/Config.luau` (`SOLO_TEST_MODE`, `ARENA_OVERRIDE`) — use the flip→stage→
verify→commit→flip-back procedure from the 2026-07-13 plan header.
