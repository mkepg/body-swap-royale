# Experience Icon "Swap Arrows" Kit Refresh — Implementation Plan

**Goal:** Refresh the Experience Icon prompt kit so it produces the approved "Swap Arrows" concept (two Roblox avatars + a glowing cyan soul-energy ⇄ swap symbol), Gemini-only and reference-guided, replacing the stale single-character / Bing-era kit.

**Architecture:** Documentation-only change to `docs/marketing/experience-icon/` and one supersede pointer. No Luau, no runtime code. "Tests" are grep-based consistency checks (no stale Bing/cream text remains; the new concept vocabulary is present). The actual image generation stays human-in-the-loop in Gemini and is NOT part of this plan.

**Tech Stack:** Markdown docs. Verification via `Grep`. Git for commits (stage ONLY the listed files — never `git add -A`; `src/shared/Config.luau` carries uncommitted dev-flips that must never be committed).

**Spec:** `docs/specs/2026-07-12-experience-icon-swap-concept-design.md`

---

## Pre-flight (do once before Task 1)

- [ ] **Branch off main** (repo default branch is `main`; do not commit doc work directly to it):

```bash
git checkout -b feat/experience-icon-swap-kit
```

## File Structure

- **Rewrite:** `docs/marketing/experience-icon/prompts.md` — becomes the Gemini-only Swap Arrows kit (Master + V1–V4 + F1–F7). All Bing "Condensed" blocks and the Bing char-count maintenance section are removed.
- **Modify:** `docs/marketing/experience-icon/README.md` — concept, layout, workflow updated to Swap Arrows / Gemini-only / reference-guided; spec pointer updated.
- **Modify:** `docs/marketing/experience-icon/RESUME-master4-ref.md` — add a top banner marking it historical, superseded by the Swap Arrows concept.

---

## Task 1: Rewrite `prompts.md` as the Swap Arrows kit

**Files:**
- Rewrite: `docs/marketing/experience-icon/prompts.md`

- [ ] **Step 1: Replace the ENTIRE file contents with the following**

````markdown
# Experience Icon — Prompt Kit ("Swap Arrows")

**Concept:** two blocky Roblox avatars + a glowing cyan soul-energy **⇄** swap
symbol between their heads — "these two players are swapping bodies." See
`docs/specs/2026-07-12-experience-icon-swap-concept-design.md`.

**Tool:** Gemini only (Bing was dropped — inferior results). **Reference-guided:**
upload `reference/ref-avatar.png` (grey R15 avatar) with EVERY prompt — it guides
the block proportions/silhouette for BOTH avatars. Generate square 1:1. Save EVERY
output — good and bad — to `candidates/` as `gemini-{variant}-{roll}.png`
(e.g. `gemini-swap-1.png`, `gemini-v2-1.png`). Bad outputs are data.

Each prompt below is complete and self-contained — upload the reference, copy the
whole block, paste. Variants change the Master on exactly one axis (named in the
heading).

Spec / acceptance checklist: the 8 checks in
`docs/specs/2026-07-12-experience-icon-swap-concept-design.md` §3.

---

## 1 · Master

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of BOTH characters — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a square app icon for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art. Show TWO cool, stylish Roblox-style avatars, head and shoulders, side by side and angled slightly toward each other, together filling the lower two-thirds of the frame. LEFT character (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, wearing a royal-blue hoodie with orange accents; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. RIGHT character (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, wearing a teal hoodie; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. Between and just above their two heads, a bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a soft cyan bloom and a few faint cyan soul-wisps and sparks around it. This glowing cyan swap symbol is the bright focal center of the icon; both characters glance up toward it in surprise. Lighting: cool cyan glow from the central swap symbol lighting the inner sides of both heads, warm amber fill light from below. Background: a dusk sky fading from deep violet at the top to a warm amber glow at the bottom, a few faint glowing soul-wisp dots, one subtle teal aurora ribbon, softly vignetted so the characters pop. High saturation, bold simple shapes, centered, filling the whole square canvas. No text, no letters, no numbers, no logos, no watermark, no border.
```

---

## 2 · Variants — each changes EXACTLY one axis vs. the Master

Each variant is the Master prompt with one change; the full text is written out so
you can paste without editing.

### V1 — Glyph dominance (bigger, more central swap symbol)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of BOTH characters — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a square app icon for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art. Show TWO cool, stylish Roblox-style avatars, head and shoulders, side by side and angled slightly toward each other, sitting lower in the frame and a little smaller so the swap symbol dominates. LEFT character (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, wearing a royal-blue hoodie with orange accents; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. RIGHT character (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, wearing a teal hoodie; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. Dominating the upper-center of the icon, a large bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a strong cyan bloom and cyan soul-wisps and sparks around it. This big glowing cyan swap symbol is the clear focal center; both characters glance up toward it in surprise. Lighting: cool cyan glow from the central swap symbol lighting the inner sides of both heads, warm amber fill light from below. Background: a dusk sky fading from deep violet at the top to a warm amber glow at the bottom, a few faint glowing soul-wisp dots, one subtle teal aurora ribbon, softly vignetted so the characters pop. High saturation, bold simple shapes, centered, filling the whole square canvas. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V2 — Camera (tight two-head close-up)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of BOTH characters — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a square app icon for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art. Tight close-up of TWO cool, stylish Roblox-style avatar HEADS, side by side and angled toward each other, the two cube heads filling most of the frame with just a sliver of shoulders. LEFT head (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, a royal-blue hoodie collar; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. RIGHT head (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, a teal hoodie collar; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. Between and just above the two heads, a bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a soft cyan bloom and a few faint cyan soul-wisps and sparks. This glowing cyan swap symbol is the bright focal center; both characters glance up toward it in surprise. Lighting: cool cyan glow from the central swap symbol on the inner sides of both heads, warm amber fill light from below. Background: a dusk sky fading from deep violet at the top to a warm amber glow at the bottom, a few faint glowing soul-wisp dots, one subtle teal aurora ribbon, softly vignetted. High saturation, bold simple shapes, centered, filling the whole square canvas. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V3 — Expression (comic surprise → delighted grins)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of BOTH characters — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a square app icon for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art. Show TWO cool, stylish Roblox-style avatars, head and shoulders, side by side and angled slightly toward each other, together filling the lower two-thirds of the frame. LEFT character (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, wearing a royal-blue hoodie with orange accents; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a big open-mouthed delighted grin, gleeful and excited. RIGHT character (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, wearing a teal hoodie; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a big open-mouthed delighted grin, gleeful and excited. Between and just above their two heads, a bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a soft cyan bloom and a few faint cyan soul-wisps and sparks around it. This glowing cyan swap symbol is the bright focal center; both characters look up toward it with delight. Lighting: cool cyan glow from the central swap symbol lighting the inner sides of both heads, warm amber fill light from below. Background: a dusk sky fading from deep violet at the top to a warm amber glow at the bottom, a few faint glowing soul-wisp dots, one subtle teal aurora ribbon, softly vignetted so the characters pop. High saturation, bold simple shapes, centered, filling the whole square canvas. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V4 — Background (full aurora+wisps → clean minimal gradient)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of BOTH characters — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a square app icon for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art. Show TWO cool, stylish Roblox-style avatars, head and shoulders, side by side and angled slightly toward each other, together filling the lower two-thirds of the frame. LEFT character (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, wearing a royal-blue hoodie with orange accents; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. RIGHT character (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, wearing a teal hoodie; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. Between and just above their two heads, a bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a soft cyan bloom. This glowing cyan swap symbol is the bright focal center; both characters glance up toward it in surprise. Lighting: cool cyan glow from the central swap symbol lighting the inner sides of both heads, warm amber fill light from below. Background: a clean, smooth dusk-gradient sky fading from deep violet at the top to a warm amber glow at the bottom, softly vignetted so the characters pop — no other background elements, no wisps, no aurora. High saturation, bold simple shapes, centered, filling the whole square canvas. No text, no letters, no numbers, no logos, no watermark, no border.
```

---

## 3 · Failure-fix prompts — apply ONLY the one matching the observed failure

Each is a sentence to ADD to the end of the Master prompt (before re-rolling).

### F1 — The two avatars merge, or only one character appears
```text
There must be TWO clearly separate, distinct avatars with a visible gap between them — two heads, two bodies, two different characters (one with orange spiky hair, one with long pink hair). Do not merge or blend them into a single character.
```

### F2 — Off-model (doesn't look like Roblox avatars)
```text
Both characters are unmistakably classic blocky Roblox avatars: cube heads, flat 2D printed decal faces flush on the head (no protruding 3D eyeballs), rectangular slab torsos, straight non-tapering block arms, and NO hands and NO fingers.
```

### F3 — The swap symbol reads as a flat 2D UI icon, or is missing
```text
The swap symbol is a glowing THREE-DIMENSIONAL soul-energy double-arrow that belongs inside the scene — glossy, with bloom and drifting cyan wisps — not a flat 2D user-interface icon. Keep it bold and clearly TWO arrows curving in opposite directions to read as "swap".
```

### F4 — Colors drift off palette
```text
Palette: deep violet #3B2A6E sky, warm amber #E8703A horizon glow, near-white character skin, bright cyan #6FE3FF swap symbol and wisps, gold #FFB84D accents; orange hair on the left character, pink hair on the right character.
```

### F5 — Text / letters / logo appear
```text
Absolutely no text, letters, numbers, words, signage, captions, or logos anywhere in the image.
```

### F6 — Creepy / horror read
```text
Friendly, comedic, bright, and colorful — suitable for young children; playful surprise, never scary or eerie.
```

### F7 — Not square / has a border
```text
Perfectly square 1:1 composition, full-bleed to all four edges, no frame, no border, no letterboxing.
```
````

- [ ] **Step 2: Verify no stale content remains and new vocabulary is present**

Run (via the Grep tool or ripgrep):
- `Grep pattern="[Bb]ing|[Cc]ondensed|cream-tan|480" path="docs/marketing/experience-icon/prompts.md"` → Expected: **no matches** (all Bing/cream/char-budget content gone).
- `Grep pattern="Swap symbol|PINK hair|reference image" path="docs/marketing/experience-icon/prompts.md"` → Expected: **multiple matches** (new concept present).
- `Grep pattern="### V1|### V2|### V3|### V4|### F1|### F7" path="docs/marketing/experience-icon/prompts.md"` → Expected: all present.

- [ ] **Step 3: Commit (stage ONLY this file)**

```bash
git add docs/marketing/experience-icon/prompts.md
git commit -m "docs(icon): rewrite prompt kit for Swap Arrows concept (Gemini-only)"
```

---

## Task 2: Update `README.md` for the new concept

**Files:**
- Modify: `docs/marketing/experience-icon/README.md`

- [ ] **Step 1: Replace the top spec pointer**

Change line 4 from:
```
Spec: `docs/specs/2026-07-10-experience-icon-design.md`
```
to:
```
Concept spec: `docs/specs/2026-07-12-experience-icon-swap-concept-design.md`
(supersedes the 2026-07-10 possession concept). Process/palette/checklist history: the 2026-07-10 spec.
```

- [ ] **Step 2: Replace the `## Layout` bullet for `prompts.md`**

Change:
```
- `prompts.md` — master prompt (full + condensed) + variants V1–V4 + failure fixes
```
to:
```
- `prompts.md` — Gemini-only "Swap Arrows" kit: Master + variants V1–V4 + failure fixes F1–F7
```

- [ ] **Step 3: Replace the `candidates/` bullet**

Change:
```
- `candidates/` — EVERY generated image, named `{tool}-{variant}-{roll}.png`
  (`tool` ∈ `bing` | `gemini`; `variant` ∈ `master` | `v1`..`v4` | `r1` | `r2`
  for refinement rounds; `roll` = 1, 2, 3…)
```
to:
```
- `candidates/` — EVERY generated image, named `gemini-{variant}-{roll}.png`
  (`variant` ∈ `swap` (master) | `v1`..`v4` | `r1` | `r2` for refinement rounds;
  `roll` = 1, 2, 3…). Earlier `bing-*` / `master*` files are historical.
```

- [ ] **Step 4: Replace Workflow step 1 (Bing-era) with a Gemini-only version**

Change:
```
1. **Generate (user):** run master + V1–V4 in both Bing Image Creator and
   Gemini (≥10 images). Save everything to `candidates/`.
```
to:
```
1. **Generate (user):** upload `reference/ref-avatar.png` to Gemini and run
   Master + V1–V4 (≥10 images). Save everything to `candidates/`.
```

- [ ] **Step 5: Update the spec reference in the Workflow heading**

Change `## Workflow (spec §7)` to `## Workflow` and change the Review-step reference
`against the spec §8 checklist` to `against the concept-spec §3 checklist`.

- [ ] **Step 6: Verify**

- `Grep pattern="[Bb]ing|condensed" path="docs/marketing/experience-icon/README.md"` → Expected: **no matches**.
- `Grep pattern="Swap Arrows|ref-avatar" path="docs/marketing/experience-icon/README.md"` → Expected: matches.

- [ ] **Step 7: Commit (stage ONLY this file)**

```bash
git add docs/marketing/experience-icon/README.md
git commit -m "docs(icon): update README for Swap Arrows / Gemini-only workflow"
```

---

## Task 3: Mark the master4-ref resume doc as superseded

**Files:**
- Modify: `docs/marketing/experience-icon/RESUME-master4-ref.md`

- [ ] **Step 1: Insert a banner as the new second line (immediately after the H1 title line)**

Add this block right after the first `#` heading line:
```
> **HISTORICAL (superseded 2026-07-12).** The single-character "Possession Close-Up"
> below shipped as `candidates/gemini-master8-ref-1.png` but tested as not
> communicating the game. The active concept is now **"Swap Arrows"** — see
> `docs/specs/2026-07-12-experience-icon-swap-concept-design.md` and
> `prompts.md`. This file is kept for its process notes and reference-image recipe.
```

- [ ] **Step 2: Verify**

- `Grep pattern="HISTORICAL \(superseded" path="docs/marketing/experience-icon/RESUME-master4-ref.md"` → Expected: 1 match near the top.

- [ ] **Step 3: Commit (stage ONLY this file)**

```bash
git add docs/marketing/experience-icon/RESUME-master4-ref.md
git commit -m "docs(icon): mark master4-ref resume as superseded by Swap Arrows"
```

---

## Done / Handoff (human-in-the-loop, NOT an agent task)

After the three tasks, the kit is ready. The user then, outside this plan:
1. Uploads `reference/ref-avatar.png` to Gemini and rolls the Master + V1–V4 → `candidates/gemini-swap-*.png`.
2. Claude scores them vs the spec §3 checklist and verifies the 64px read (PowerShell + System.Drawing downscale — there is no working ImageMagick; `convert` is Windows `convert.exe`).
3. Pick a winner → ≤2 refine rounds → `finalize-icon.ps1` + bottom-right ✦ watermark inpaint → `final/icon-512.png` → upload via Creator Dashboard.

---

## Self-Review

- **Spec coverage:** Task 1 implements the concept (§2 Master, §2.1 two characters incl. female Player 2, §2.2 glyph, §2.3 palette) and the acceptance vocabulary; F1–F7 map to spec §5 risks (merge, off-model, glyph-as-UI) plus standard fixes. Task 2/3 implement §4 (Gemini-only, reference-guided, kit refresh, provisional-asset note via README/resume). No spec section left unimplemented.
- **Placeholder scan:** every prompt is written in full; no TBD/TODO; verification uses concrete grep patterns with expected results.
- **Consistency:** character vocabulary is identical across Master and all four variants (orange-hair boy + blue hoodie; pink-ponytail girl + teal hoodie; cyan ⇄ soul symbol); naming convention `gemini-{variant}-{roll}` is consistent between prompts.md and README. Commit steps stage only named files (never `git add -A`), protecting the `Config.luau` dev-flips.
