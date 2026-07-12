# Experience Thumbnails — Prompt Kit ("Swap Story")

**Concept:** four 16:9 carousel frames telling the core loop as a sequence —
the swap (hero), every-30-seconds chaos, survive-the-arena stakes (set in the
real **Hex-A-Gone arena**), and play-with-friends social (set in the real
**Soul Sweeper turbine arena**) — same brand family as the shipped "Swap
Arrows" icon (orange/blue boy + pink/teal girl, cyan soul-⇄, Soul Festival dusk
palette). T3 and T4 depict the actual in-game environments so players get what
they see. See
`docs/specs/2026-07-12-experience-thumbnails-design.md`.

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
`docs/specs/2026-07-12-experience-thumbnails-design.md` §6.

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

## T3 — Survive the arena (stakes) · Hex-A-Gone arena

> Depicts the game's real **Hex-A-Gone arena**: stacked circular floors of small flat-top hexagon tiles, each floor a distinct color (amber → green → teal → blue → indigo → magenta, top to bottom) descending into a void; a tile flashes ALARM RED the moment it's stepped on, then drops away for good, leaving hex-shaped holes.

### Master

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatar — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that it has NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Setting: a "Hex-A-Gone" style arena floor made of small flat-top HEXAGON tiles packed into a fine glossy honeycomb with thin dark seams between tiles, arranged as stacked circular honeycomb floors descending into a deep dark void. Each floor is a different bright SOLID color from top to bottom — the top floor warm AMBER-GOLD, and the floors visible below it through the gaps green, then teal, then blue, then indigo, then magenta — so the pit reads as a rainbow of honeycomb layers, and each floor is ringed by a glowing segmented edge-trim border. Several hex tiles on the top amber floor are glowing ALARM RED (armed, about to vanish), and a few tiles have already dropped away leaving empty HEX-SHAPED HOLES that reveal the colorful honeycomb layers far below. Show ONE blocky Roblox-style avatar standing on the amber honeycomb floor right at the crumbling edge of a fresh hex hole, in a comic panic decal face — wide white oval eyes with dark outlines and small dark pupils, and an open mouth in alarm — in a dynamic, off-balance pose with arms out for balance as the glowing red hex tile under its feet is about to drop. Playful peril rather than horror. Combat-free: absolutely NO weapons and NO other character attacking — the eroding hex ARENA itself is the only threat. The avatar has near-white glossy plastic skin, colorful warm hair and a cool-toned outfit. Lighting: warm amber glow bouncing up off the honeycomb floor and hot red light from the armed hex tiles, cool cyan ambient soul-energy light drifting nearby. Background: a dusk sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom, the deep dark void of the hex pit dropping away below the floor, bright cyan #6FE3FF soul energy wisps, gold #FFB84D accents, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V1 — Action (standing at the edge → mid-fall through the pit)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatar — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that it has NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Setting: a "Hex-A-Gone" style arena of small flat-top HEXAGON tiles in a fine glossy honeycomb with thin dark seams, arranged as stacked circular honeycomb floors descending into a deep dark void — the top floor warm AMBER-GOLD, the floors below it green, teal, blue, indigo and magenta, each ringed by a glowing segmented edge-trim border, with several tiles glowing ALARM RED and many empty HEX-SHAPED HOLES punched through the floors. Show ONE blocky Roblox-style avatar MID-FALL, having just dropped through a vanished hex hole in the amber top floor and now tumbling down between the colorful honeycomb layers toward the floors below, in a comic panic decal face — wide white oval eyes with dark outlines and small dark pupils, open mouth in alarm — arms and legs flailing in a playful off-balance tumbling pose. Playful peril rather than horror. Combat-free: absolutely NO weapons and NO other character attacking — the eroding hex ARENA itself is the only threat. The avatar has near-white glossy plastic skin, colorful warm hair and a cool-toned outfit. Lighting: colorful bounce light from the surrounding honeycomb layers and hot red light from armed tiles, cool cyan ambient soul-energy light drifting nearby. Background: the rainbow honeycomb floors receding above and below the falling avatar into the deep dark hex pit, a dusk sky fading from deep violet #3B2A6E to warm amber #E8703A visible above through the top hole, bright cyan #6FE3FF soul-wisps, gold #FFB84D accents, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V2 — Camera angle (low dramatic view up from inside the pit)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatar — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that it has NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). From a LOW dramatic camera angle looking UP from inside the pit, show a "Hex-A-Gone" style arena of small flat-top HEXAGON tiles in a fine glossy honeycomb with thin dark seams, arranged as stacked circular honeycomb floors — the top floor warm AMBER-GOLD, the floors below it green, teal, blue, indigo and magenta, each ringed by a glowing segmented edge-trim border, several tiles glowing ALARM RED and empty HEX-SHAPED HOLES punched through. ONE blocky Roblox-style avatar stands on the amber honeycomb rim at the edge of a hex hole, looming dramatically overhead against the dusk sky in a comic panic decal face — wide white oval eyes with dark outlines and small dark pupils, open mouth in alarm — arms out for balance in a dynamic off-balance pose as the glowing red hex tile under its feet is about to drop. Playful peril rather than horror. Combat-free: absolutely NO weapons and NO other character attacking — the eroding hex ARENA itself is the only threat. The avatar has near-white glossy plastic skin, colorful warm hair and a cool-toned outfit. Lighting: warm amber glow off the honeycomb floor and hot red light from armed tiles above, cool cyan ambient soul-energy light. Background: the underside of the rainbow honeycomb floors and the deep dark hex pit rising around the camera, a dusk sky fading from deep violet #3B2A6E to warm amber #E8703A glimpsed above, bright cyan #6FE3FF soul-wisps, gold #FFB84D accents, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

---

## T4 — Play with friends (social) · Soul Sweeper arena

> Depicts the game's real **Soul Sweeper arena** (a.k.a. Soul Turbine): a large round dark metallic disc floating over a void, with a central hub emitter and two rotating turbine BEAM bars — a LOW glowing AMBER bar near the floor you JUMP, and a raised HIGH glowing CRIMSON-RED bar you stay grounded under — plus glowing amber marquee lights around the rim and radial amber wake-strips across the disc. Friends playing it together = social pull AND accurate gameplay.

### Master

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Setting: a "Soul Sweeper" turbine arena — a large round dark glossy metallic disc (dark indigo-navy metal) floating over a dark void, its surface marked with radial spoke-lines and glowing amber strips running outward from the center, and a glowing AMBER marquee of chase-lights around the rim. At the exact center of the disc stands a chunky dark cylindrical HUB with a glowing amber emitter pillar on top. From the hub, two long horizontal BEAM bars sweep around the disc like a rotating turbine: a LOW glowing AMBER bar close to the floor, and a raised HIGH glowing CRIMSON-RED bar higher up. Show FOUR or more distinct, colorful blocky Roblox-style avatars together ON the disc, actively PLAYING and having fun: a couple of them JUMPING up in the air to clear the low amber beam as it sweeps toward their feet, the others standing grounded and ducking slightly as the high crimson beam passes overhead — all with cheerful decal faces printed FLAT on their cube heads like sticker decals — happy grins or delighted-surprise huge white oval eyes with dark outlines and small dark pupils. Give each avatar a different warm hair color (orange, pink, yellow, purple) and a different cool-toned outfit (blues, teals, purples). Festive, energetic, celebratory multiplayer party vibe — friends playing together. Lighting: warm amber and crimson glow from the sweeping beams and the hub, soft cyan soul-glow highlights drifting among the players. Background: a dusk SUNSET sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom with a soft glowing sun near the horizon, the dark void around and below the floating disc, a few faint glowing cyan #6FE3FF soul-wisp dots, gold #FFB84D accents, near-white character skin, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V1 — Camera distance (pulled-back hero shot of the whole turbine disc)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). From an elevated three-quarter camera angle looking down at the whole arena, show a "Soul Sweeper" turbine arena — a large round dark glossy metallic disc (dark indigo-navy metal) floating over a dark void, its full circular surface visible with radial spoke-lines and glowing amber strips running outward from the center and a glowing AMBER marquee of chase-lights around the rim. At the center stands a chunky dark cylindrical HUB with a glowing amber emitter pillar, and two long horizontal BEAM bars sweep out from it across the disc: a LOW glowing AMBER bar near the floor and a raised HIGH glowing CRIMSON-RED bar higher up. FOUR or more distinct, colorful blocky Roblox-style avatars are spread across the disc, smaller in frame, actively playing — some JUMPING the low amber beam, others grounded under the high crimson beam — all with cheerful decal faces (happy grins or delighted-surprise huge white oval eyes with dark outlines and small dark pupils). Give each a different warm hair color (orange, pink, yellow, purple) and a different cool-toned outfit (blues, teals, purples). Festive, energetic multiplayer party vibe. Lighting: warm amber and crimson glow from the sweeping beams and hub, soft cyan soul-glow highlights. Background: a dusk SUNSET sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom with a soft glowing sun near the horizon, the dark void around and below the floating disc, faint cyan #6FE3FF soul-wisp dots, gold #FFB84D accents, near-white character skin, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
```

### V2 — Action (close-up dramatic mid-air jump over the low amber beam)

```text
Use the blocky character in the attached reference image ONLY as a structural guide for the body proportions and silhouette of the avatars — the rectangular block head, the straight rectangular block arms that do NOT taper, the flat slab torso, and the fact that they have NO hands and NO fingers. Do not copy its colors, outfit, or pose. Create a WIDE 16:9 LANDSCAPE key-art image for a family-friendly multiplayer party game, in a chunky glossy 3D toy style like modern party-game key art, filling the whole 16:9 canvas with the subject centered within a safe zone (nothing important near the edges). Close, dynamic action shot on a "Soul Sweeper" turbine arena — a round dark glossy metallic disc (dark indigo-navy metal) floating over a dark void, with radial glowing amber strips and an amber marquee of chase-lights around the rim, and a chunky dark central HUB with a glowing amber emitter pillar. A LOW glowing AMBER beam bar sweeps toward the camera close to the floor, and a raised HIGH glowing CRIMSON-RED beam bar sits higher up behind. Show TWO OR THREE distinct, colorful blocky Roblox-style avatars in a big dramatic MID-AIR JUMP, leaping high to clear the low amber beam as it sweeps under their feet, with one or two more avatars grounded in the background under the high crimson beam — all with cheerful, thrilled decal faces (big open-mouthed grins, huge white oval eyes with dark outlines and small dark pupils). Give each avatar a different warm hair color (orange, pink, yellow, purple) and a different cool-toned outfit (blues, teals, purples). Festive, high-energy multiplayer party vibe — friends playing together. Lighting: strong warm amber glow from the low beam lighting the jumping avatars from below, crimson glow behind, soft cyan soul-glow highlights. Background: a dusk SUNSET sky fading from deep violet #3B2A6E at the top to a warm amber #E8703A glow at the bottom with a soft glowing sun near the horizon, the dark void around and below the floating disc, faint cyan #6FE3FF soul-wisp dots, gold #FFB84D accents, near-white character skin, one subtle teal aurora ribbon, soft vignette. High saturation, bold simple shapes. No text, no letters, no numbers, no logos, no watermark, no border.
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
No weapons and no character attacking anyone; the danger is purely the eroding hex floor — tiles flashing red and dropping away into the void; keep it comedic peril, not a fight.
```

### F8 — (T3) Hex arena not accurate
```text
The floor MUST be a honeycomb of small flat-top HEXAGON tiles arranged in stacked circular floors, each floor a distinct solid color (top amber-gold, then green, teal, blue, indigo, magenta) descending into a dark void, with a glowing segmented trim ring around each floor, some hex tiles glowing alarm-red, and several missing tiles leaving hex-shaped holes — a Fall-Guys "Hex-A-Gone" style step-eroding floor. Not square tiles, not a solid platform, not lava.
```

### F9 — (T4) Sweeper arena not accurate
```text
The arena MUST be a round dark metallic turbine disc floating over a void with a chunky central hub emitter pillar and TWO rotating horizontal beam bars sweeping around it — a LOW glowing AMBER bar near the floor and a raised HIGH glowing CRIMSON-RED bar higher up — plus a glowing amber marquee of lights around the rim and radial amber strips across the disc. Players JUMP the low amber beam and stay grounded under the high crimson beam. Not a flat empty stage, not a square arena, not a spinning-blade weapon.
```
