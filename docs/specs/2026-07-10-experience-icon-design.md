# Experience Icon — Design Spec

**Date:** 2026-07-10
**Status:** Approved (brainstormed with visual companion; concept, style, approach, and all three design sections user-approved)
**Scope:** The Roblox Experience Icon only. Thumbnails are the agreed next slice and will reuse this folder structure and palette rules. No logo/wordmark, no in-game surfaces.

---

## 1. Goal

Produce the game's first storefront asset: a 512×512 Experience Icon that wins the
click on the Roblox home page/search results while honestly portraying what Body
Swap Royale actually is. The icon is replaceable at zero cost in the Creator
Dashboard, so the endgame is ship-and-iterate, not perfection.

**Authenticity rule (user-set, binding):** the icon portrays the actual game — a
blocky chunky character consistent with the game's normalized R15 bodies, the real
Soul Festival Sky palette from the world shell, and the actual mechanic (another
player's soul taking over your body). Nothing the game doesn't do.

## 2. Production model

- **AI-generated art**, tool-agnostic. Target free tools: **Microsoft Bing Image
  Creator** and **Gemini image generation**. Prompts are plain descriptive prose
  (no tool-specific parameters), delivered in two lengths: **full** (Gemini) and
  **condensed ~400 chars** (Bing's shorter prompt box).
- Iteration is **re-roll-based** (free tiers have no reliable inpainting/editing):
  single-axis prompt variants + curated re-rolls, not incremental edits.  image, builds size-comparison galleries, downscales/finalizes. **User** runs the
  generations in the AI tools and picks winners.

## 3. Concept — "The Possession Close-Up" (Option A)

One big shocked face filling the frame while a translucent cyan soul-face slides
into it. Chosen over: (B) two-body swap moment — two subjects means small faces,
busy at 64px; (C) faceless emblem — brandable but faceless icons underperform with
the 9–16 audience; (D) arena chaos scene — sells tone but not the mechanic.
A combines the chart-proven big-expressive-face formula with a literal read of the
swap mechanic, and survives the 64px test best.

## 4. Art-direction brief (the contract for "correct")

- **Style:** chunky glossy 3D — soft plastic-toy shading, rounded shapes, rim
  lighting, high saturation (Fall Guys / Stumble Guys key-art register; matches
  the game's normalized chunky R15 bodies).
- **Subject:** ONE chunky toy-like blocky 3D character, head and shoulders filling
  ~70% of frame, cream/tan soft plastic. Huge white eyes, small dark pupils
  darting up-left in comic shock; small open mouth. **Funny-scared, never
  distressed** (party-game tone, moderation-safe).
- **The possession (the mechanic):** a translucent glowing CYAN spectral face —
  serene, slightly **mischievous, not menacing** (it's the incoming player, not a
  monster) — overlaps the upper-left of the head, mid-slide INTO it, wispy trail
  curving off-frame, cyan glow blooming at the contact.
- **Two-tone lighting = the story:** cyan rim light on the soul side of the head;
  warm amber fill from the lower right. The lighting conflict IS the swap.
- **Background — Soul Festival Sky:** deep violet fading to warm amber horizon
  glow; faint soul-wisp bokeh dots; one subtle aurora ribbon; soft vignette. The
  background never competes with the face.
- **Palette:** `#3B2A6E` violet sky · `#E8703A` amber glow · `#F2C894` character ·
  `#6FE3FF` soul cyan · `#FFB84D` accent.
- **Hard rules:** no text or logos; no Roblox trademarks; all critical content
  inside the central ~80% safe zone (Roblox rounds/crops corners); must read at
  64px (shocked face + second face visible as two distinct color masses).

## 5. Approach — master prompt + single-axis variant batch (Approach 1)

One master prompt encoding §4, plus four variants that each change **exactly one
axis** (so results tell us *why* a winner wins):

| Variant | Axis | Master → Variant |
|---|---|---|
| V1 | Expression | comic terror → delighted panic |
| V2 | Soul-face position | corner overlap → descending face-to-face from above |
| V3 | Camera | tight face crop → head-and-shoulders |
| V4 | Background | aurora emphasized → minimal clean gradient |

Rejected approaches: single-prompt conversational iteration (free tools re-roll
the whole image per change — "incremental" is illusory); generate-heavy
curate-only (wastes systematic variation; Bing boost limits make bulk slow).

## 6. Deliverables & repo layout

```
docs/marketing/experience-icon/
  prompts.md            -- master (full + condensed) + V1–V4 + known-failure appendix
  candidates/           -- every generation, named {tool}-{variant}-{roll}.png  (e.g. bing-v2-1.png)
  final/icon-512.png    -- the shipped asset; repo copy is source of truth
```

- **prompts.md known-failure appendix:** pre-written rephrasings for predictable
  misses — the two faces fusing into one two-headed figure (most likely failure;
  fallback decomposes the prompt to "a translucent ghost hovering beside and
  overlapping the head"), wrong palette, photorealism instead of toy-like, added
  text.
- **Review artifacts:** per-batch review table + a visual-companion gallery
  showing every candidate at 512/128/64 px with checklist scores.

## 7. Workflow

1. **Generate (user, ~15 min):** master + V1–V4 through both Bing and Gemini
   (≥10 images). Save EVERYTHING to `candidates/` — bad outputs are data about
   which phrasing each tool misreads.
2. **Review:** read every candidate, score against the §8 checklist,
   push the 3-size gallery. User picks the winner or the winning *traits*
   (e.g. "V2's soul position + V4's background").
3. **Refine (max 2 rounds):** one refinement prompt merging winning traits (+
   appendix fixes if needed); re-roll in whichever tool won Phase 2. Hard cap:
   two rounds — 80%-right shipped beats 95%-right in week three.
4. **Finalize:** downscale winner to 512×512 PNG (scripted, quality-checked),
   commit to `final/`, hand over Creator Dashboard upload steps.
   **Done =** file in repo + icon live on the experience.

## 8. Acceptance checklist (every candidate scored)

1. **64px read** — shocked face + second color mass both legible at 64px
2. **Authenticity** — blocky/chunky character consistent with the game's bodies;
   Soul Festival palette; depicts possession; nothing the game doesn't do
3. **Safe zone** — critical content inside the central ~80%
4. **One focal subject** — no fused two-headed failure, no crowd
5. **Tone** — funny-scared, mischievous soul; zero horror read
6. **Compliance** — no text, no Roblox trademarks, moderation-safe
7. **Contrast pop** — face separates from background in a grayscale squint test

## 9. Failure handling

- Both tools fail checklist #4 (face fusion) across the batch → switch to the
  appendix's decomposed phrasing.
- Chunky-3D style won't land on free tiers → fall back to the style runner-up
  (bold 2D illustration with thick outlines) as an **explicit re-decision with
  the user**, never silent drift.

## 10. Out of scope

Thumbnails (next slice), logo/wordmark, in-game menu art, social/Discord assets,
paid tools, human-commissioned art.
