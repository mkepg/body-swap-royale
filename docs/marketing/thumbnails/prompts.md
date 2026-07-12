# Experience Thumbnails — Prompt Kit ("Swap Story")

**Concept:** four 16:9 carousel frames telling the core loop as a sequence —
the swap (hero), every-30-seconds chaos, survive-the-arena stakes, and
play-with-friends social — same brand family as the shipped "Swap Arrows"
icon (orange/blue boy + pink/teal girl, cyan soul-⇄, Soul Festival dusk
palette). See
`docs/superpowers/specs/2026-07-12-experience-thumbnails-design.md`.

**Tool:** Gemini only. **Reference-guided:** upload `reference/ref-avatar.png`
(grey R15) with EVERY prompt; request 16:9 landscape.

Save EVERY output — good and bad — to `candidates/` as
`gemini-t{frame}-{variant}-{roll}.png` (frame ∈ `t1`..`t4`; variant ∈
`m` (master) | `v1`/`v2` | `r1`/`r2` for refine rounds; roll = 1, 2, …).
Bad outputs are data.

Each prompt below is complete and self-contained — upload the reference,
copy the whole block, paste. Variants change the Master on exactly one axis
(named in the heading).

Spec / acceptance checklist: the 9 checks in
`docs/superpowers/specs/2026-07-12-experience-thumbnails-design.md` §6.

---

## T1 — The swap (hero)

### Master

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show TWO cool, stylish Roblox-style avatars, head and shoulders, side by side and angled slightly toward each other. LEFT character (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, wearing a royal-blue hoodie with orange accents; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. RIGHT character (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, wearing a teal hoodie; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. Between and just above their two heads, a bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a soft cyan bloom and a few faint cyan soul-wisps and sparks around it. This glowing cyan swap symbol is the bright focal center of the image; both characters glance up toward it in surprise. Lighting: cool cyan glow from the central swap symbol lighting the inner sides of both heads, warm amber fill light from below. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V1 — Camera (tighter two-head close-up)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Tight close-up of TWO cool, stylish Roblox-style avatar HEADS, side by side and angled toward each other, the two cube heads filling most of the frame width with just a sliver of shoulders. LEFT head (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, a royal-blue hoodie collar; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. RIGHT head (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, a teal hoodie collar; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. Between and just above the two heads, a bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a soft cyan bloom and a few faint cyan soul-wisps and sparks around it. This glowing cyan swap symbol is the bright focal center of the image; both characters glance up toward it in surprise. Lighting: cool cyan glow from the central swap symbol lighting the inner sides of both heads, warm amber fill light from below. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V2 — Background (denser wisps/aurora vs. cleaner gradient)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show TWO cool, stylish Roblox-style avatars, head and shoulders, side by side and angled slightly toward each other. LEFT character (a boy): near-white glossy plastic cube head with chunky spiky bright-ORANGE hair, wearing a royal-blue hoodie with orange accents; its face is a simple cartoon face printed FLAT on the front of the cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. RIGHT character (a girl): near-white glossy plastic cube head with long chunky PINK hair in a ponytail, wearing a teal hoodie; the same flat printed cartoon decal face — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in playful comic surprise. Between and just above their two heads, a bold glowing CYAN soul-energy double-arrow SWAP symbol: two thick glossy cyan arrows curving horizontally — the top arrow points right, the bottom arrow points left — like a swap/exchange icon made of glowing spirit energy, with a strong cyan bloom and several drifting cyan soul-wisps and sparks around it. This glowing cyan swap symbol is the bright focal center of the image; both characters glance up toward it in surprise. Lighting: cool cyan glow from the central swap symbol lighting the inner sides of both heads, warm amber fill light from below. Background: a richly detailed dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, many faint glowing cyan soul-wisp dots drifting across the sky, two overlapping subtle teal aurora ribbons, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

---

## T2 — Every 30 seconds (chaos)

### Master

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show THREE to FOUR distinct blocky Roblox-style avatars scattered across the wide frame, mid-scramble as if control is jumping between bodies, each with a simple cartoon face printed FLAT on the front of its cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in comic surprise. Give each avatar a different hair color (orange, pink, purple, or yellow) and a different cool-toned outfit (blues, teals, purples) — keep bright cyan reserved only for the glowing energy, not for hair or outfits. Cyan soul-energy wisps and small glowing swap-arrows arc BETWEEN several of the avatars, suggesting control is jumping around the group. Near the center of the frame, a large glowing CYAN soul-energy RING or portal shape floats as a "timer" motif — a smooth glowing ring made of soul energy with NO numbers, NO digits, NO clock face, and NO text of any kind, just a bold glossy glowing ring with soft bloom. Chaotic, playful energy — everyone reacting to the sudden reassignment. Lighting: cool cyan glow from the ring and arcing wisps lighting the avatars, warm amber fill light from below. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V1 — Avatar count (3 vs. 4)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show exactly THREE distinct blocky Roblox-style avatars scattered across the wide frame, mid-scramble as if control is jumping between bodies, each with a simple cartoon face printed FLAT on the front of its cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in comic surprise. Give each avatar a different hair color (orange, pink, or purple) and a different cool-toned outfit (blues, teals, purples) — keep bright cyan reserved only for the glowing energy, not for hair or outfits. Cyan soul-energy wisps and small glowing swap-arrows arc BETWEEN the three avatars, suggesting control is jumping around the group. Near the center of the frame, a large glowing CYAN soul-energy RING or portal shape floats as a "timer" motif — a smooth glowing ring made of soul energy with NO numbers, NO digits, NO clock face, and NO text of any kind, just a bold glossy glowing ring with soft bloom. Chaotic, playful energy — everyone reacting to the sudden reassignment. Lighting: cool cyan glow from the ring and arcing wisps lighting the avatars, warm amber fill light from below. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V2 — Ring prominence (dominant vs. subtle)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show THREE to FOUR distinct blocky Roblox-style avatars scattered across the wide frame, mid-scramble as if control is jumping between bodies, each with a simple cartoon face printed FLAT on the front of its cube head like a sticker decal — huge white oval eyes with dark outlines and small dark pupils, and a small open mouth in comic surprise. Give each avatar a different hair color (orange, pink, purple, or yellow) and a different cool-toned outfit (blues, teals, purples) — keep bright cyan reserved only for the glowing energy, not for hair or outfits. Faint cyan soul-energy wisps and small glowing swap-arrows arc subtly BETWEEN a couple of the avatars, suggesting control is jumping around the group. In the background near the center, a small, subtle glowing CYAN soul-energy RING or portal shape floats quietly as a "timer" motif — a smooth glowing ring made of soul energy with NO numbers, NO digits, NO clock face, and NO text of any kind, understated and secondary to the avatars themselves. Chaotic, playful energy — everyone reacting to the sudden reassignment. Lighting: cool cyan glow from the wisps lighting the avatars, warm amber fill light from below. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

---

## T3 — Survive the arena (stakes)

### Master

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatar — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that it has NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show ONE blocky Roblox-style avatar in a comic panic decal face — wide white oval eyes with dark outlines and small dark pupils, and an open mouth in alarm — reacting to an ENVIRONMENTAL hazard: the edge of a crumbling floating platform is breaking away beneath its feet in a dusk arena. The avatar is in a dynamic, off-balance pose, arms out for balance, playful peril rather than horror. Combat-free: absolutely NO weapons, NO other characters, NO one attacking — the ARENA itself is the threat. The avatar has near-white glossy plastic skin with a colorful hair and outfit choice consistent with the game's cool-outfit/warm-hair character logic. Lighting: warm amber glow from a glowing hazard crack in the crumbling platform, cool cyan ambient soul-energy light drifting nearby. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, floating platform fragments below in the void, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V1 — Hazard type (crumbling platform vs. glowing floor crack)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatar — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that it has NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show ONE blocky Roblox-style avatar in a comic panic decal face — wide white oval eyes with dark outlines and small dark pupils, and an open mouth in alarm — reacting to an ENVIRONMENTAL hazard: a bright glowing hazard crack is splitting open the floor directly beneath its feet in a dusk arena, hot cyan-white light spilling out of the crack. The avatar is in a dynamic, off-balance pose, leaping back from the crack, playful peril rather than horror. Combat-free: absolutely NO weapons, NO other characters, NO one attacking — the ARENA itself is the threat. The avatar has near-white glossy plastic skin with a colorful hair and outfit choice consistent with the game's cool-outfit/warm-hair character logic. Lighting: bright glow from the hazard crack lighting the avatar from below, cool cyan ambient soul-energy light drifting nearby. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, solid arena floor around the crack, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V2 — Camera angle (low dramatic vs. eye-level)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatar — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that it has NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). From a low dramatic upward-looking camera angle, show ONE blocky Roblox-style avatar in a comic panic decal face — wide white oval eyes with dark outlines and small dark pupils, and an open mouth in alarm — reacting to an ENVIRONMENTAL hazard: the edge of a crumbling floating platform is breaking away beneath its feet in a dusk arena, seen from below so the avatar looms dramatically against the dusk sky. The avatar is in a dynamic, off-balance pose, arms out for balance, playful peril rather than horror. Combat-free: absolutely NO weapons, NO other characters, NO one attacking — the ARENA itself is the threat. The avatar has near-white glossy plastic skin with a colorful hair and outfit choice consistent with the game's cool-outfit/warm-hair character logic. Lighting: warm amber glow from a glowing hazard crack in the crumbling platform, cool cyan ambient soul-energy light drifting nearby. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, floating platform fragments below in the void, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

---

## T4 — Play with friends (social)

### Master

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show FOUR or more distinct, colorful blocky Roblox-style avatars standing together in a friendly party LINEUP, all with cheerful decal faces printed FLAT on their cube heads like sticker decals — happy grins or delighted-surprise huge white oval eyes with dark outlines and small dark pupils. Give each avatar a different warm hair color (orange, pink, yellow, purple) and a different cool-toned outfit (blues, teals, purples) — keep bright cyan reserved only for the glowing energy, not for hair or outfits. A little cyan soul-glow drifts among them, small wisps and sparkles connecting the group. Festive, celebratory dusk party vibe — everyone looks happy to be together. Lighting: warm amber ambient light from the dusk horizon, soft cyan highlights from the drifting soul-glow. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V1 — Lineup arrangement (straight row vs. loose cluster)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show FOUR or more distinct, colorful blocky Roblox-style avatars standing together in a loose, casual friendly cluster (not a strict straight line — some closer to camera, some slightly behind, some turned toward each other), all with cheerful decal faces printed FLAT on their cube heads like sticker decals — happy grins or delighted-surprise huge white oval eyes with dark outlines and small dark pupils. Give each avatar a different warm hair color (orange, pink, yellow, purple) and a different cool-toned outfit (blues, teals, purples) — keep bright cyan reserved only for the glowing energy, not for hair or outfits. A little cyan soul-glow drifts among them, small wisps and sparkles connecting the group. Festive, celebratory dusk party vibe — everyone looks happy to be together. Lighting: warm amber ambient light from the dusk horizon, soft cyan highlights from the drifting soul-glow. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V2 — Expression (big grins vs. delighted surprise)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Show FOUR or more distinct, colorful blocky Roblox-style avatars standing together in a friendly party LINEUP, all with big open-mouthed delighted grins printed FLAT on their cube heads like sticker decals — huge white oval eyes with dark outlines and small dark pupils, gleeful and excited. Give each avatar a different warm hair color (orange, pink, yellow, purple) and a different cool-toned outfit (blues, teals, purples) — keep bright cyan reserved only for the glowing energy, not for hair or outfits. A little cyan soul-glow drifts among them, small wisps and sparkles connecting the group. Festive, celebratory dusk party vibe — everyone looks thrilled to be together. Lighting: warm amber ambient light from the dusk horizon, soft cyan highlights from the drifting soul-glow. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, bright cyan #6FE3FF soul energy, gold #FFB84D accents, near-white character skin, a few faint glowing cyan soul-wisp dots, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

---

## Failure-fix add-ons — apply ONLY the one matching the observed failure

Each is a sentence to ADD to the end of a prompt before re-rolling.

### F1 — Off-model (doesn't look like Roblox avatars)
```text
Both/all characters are unmistakably classic blocky Roblox avatars: cube heads, flat 2D printed decal faces flush on the head (no protruding 3D eyeballs), rectangular slab torsos, straight non-tapering block arms, and NO hands and NO fingers.
```

### F2 — Palette drift
```text
Palette: deep violet #3B2A6E sky, warm amber #E8703A horizon glow, near-white character skin, bright cyan #6FE3FF soul energy and wisps, gold #FFB84D accents.
```

### F3 — Text / letters / numbers appear
```text
Absolutely no text, letters, numbers, words, clock digits, signage, captions, or logos anywhere in the image.
```

### F4 — Creepy / horror read
```text
Friendly, comedic, bright and colorful, suitable for young children; playful surprise, never scary or eerie.
```

### F5 — Not 16:9 / has a border
```text
Wide 16:9 landscape composition, full-bleed to all four edges, no frame, no border, no letterboxing.
```

### F6 — (T2/T4) Avatars merge or wrong count
```text
There must be N clearly separate, distinct avatars with visible gaps between them; do not merge or blend them.
```

### F7 — (T3) Reads as combat/violence
```text
No weapons and no character attacking anyone; the danger is purely the environment (crumbling/glowing hazard); keep it comedic peril, not a fight.
```
