# Experience Icon — Prompt Kit ("Swap Arrows")

**Concept:** two blocky Roblox avatars + a glowing cyan soul-energy **⇄** swap
symbol between their heads — "these two players are swapping bodies." See
`docs/specs/2026-07-12-experience-icon-swap-concept-design.md`.

**Tool:** Gemini only (Bing was dropped — inferior results). **Reference-guided:**
upload `reference/ref-avatar.png` (grey R15 avatar) with EVERY prompt — it guides
the block proportions/silhouette for BOTH avatars. Generate square 1:1. Save EVERY
output — good and bad — to the local scratch folder as `gemini-{variant}-{roll}.png`
(e.g. `gemini-swap-1.png`, `gemini-v2-1.png`). Bad outputs are data.
The Master prompt's variant token is `swap` (save Master rolls as `gemini-swap-1.png`, `-2`, …); the four variants use `v1`–`v4`; refinement rounds use `r1`/`r2`.

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
