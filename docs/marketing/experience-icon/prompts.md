# Experience Icon — Prompt Kit

Tool-agnostic prose prompts (no `--parameters`). Use the **Full** version in
Gemini; use the **Condensed** version in Bing Image Creator. Generate at the
tool's native square size (1:1). Save EVERY output — good and bad — to
`candidates/` as `{tool}-{variant}-{roll}.png` (e.g. `bing-v2-1.png`,
`gemini-master-3.png`). Bad outputs are data.

Spec: `docs/superpowers/specs/2026-07-10-experience-icon-design.md`
(§8 acceptance checklist is what candidates are scored against.)

---

## Master — Full (Gemini)

A square app icon for a family-friendly multiplayer party game, rendered in a
chunky glossy 3D toy style like modern party-game key art. One blocky, boxy
cartoon character shown head and shoulders, filling about seventy percent of
the frame, made of smooth cream-tan plastic with soft rounded edges and a
glossy toy sheen. The character has huge white oval eyes with small dark
pupils darting toward the upper left in comic, funny shock, and a small open
mouth — playfully startled, never distressed. Overlapping the upper-left of
its head, a translucent glowing cyan ghost face — serene and slightly
mischievous, with simple eyes and a small smile — is sliding INTO the
character's head, its wispy light-trail curving away off-frame, with a soft
cyan glow blooming where the two touch. The lighting tells the story: cool
cyan rim light on the left side of the head coming from the ghost, warm amber
fill light from the lower right. Background: a dusk sky fading from deep
violet at the top to a warm amber glow at the bottom, sprinkled with a few
faint glowing soul-wisp bokeh dots and one subtle teal aurora ribbon, softly
vignetted so the character pops. High saturation, bold simple shapes, centered
composition with breathing room on all sides, no text, no letters, no logos,
no watermark.

## Master — Condensed (Bing)

<!-- condensed -->
Chunky glossy 3D toy-style square app icon: one blocky cream cartoon character, head and shoulders filling the frame, huge white eyes in comic shock looking up-left, small open mouth. A translucent glowing cyan ghost face with a mischievous smile slides into its head, wispy trail, cyan glow at contact. Cyan rim light left, warm amber light lower right. Violet-to-amber dusk sky, faint glowing wisp dots. No text, no logos.

---

## Variants — change EXACTLY one axis vs. the master

Apply the same edit to whichever length you're using (for the condensed
version, swap the matching phrase).

### V1 — Expression: comic terror → delighted panic

Replace the eyes/mouth sentence with:
"The character has huge white oval eyes with small dark pupils darting toward
the upper left, and an enormous open-mouthed gleeful grin — delighted panic,
like the drop of a rollercoaster."
(Condensed: replace "huge white eyes in comic shock looking up-left, small
open mouth" with "huge white eyes looking up-left, enormous gleeful
open-mouthed grin, delighted panic".)

### V2 — Soul-face position: corner overlap → descending face-to-face

Replace the ghost-face sentence with:
"Directly above the character, a translucent glowing cyan ghost face — serene
and slightly mischievous, with simple eyes and a small smile — descends
face-to-face toward the character's upturned face, tilted downward, its wispy
light-trail rising off the top of the frame, with a soft cyan glow blooming in
the narrowing gap between them."
(Condensed: replace "slides into its head, wispy trail, cyan glow at contact"
with "descends from above, face-to-face, wispy trail rising, cyan glow in the
gap between them".)

### V3 — Camera: head-and-shoulders (~70%) → tight face crop

Replace the phrase "shown head and shoulders, filling about seventy percent of
the frame" with:
"shown in a tight close-up, the face alone filling almost the whole frame,
the top of the head and chin just inside the edges"
(keep the rest of the sentence — "made of smooth cream-tan plastic…" — unchanged)
(Condensed: replace "head and shoulders filling the frame" with "face in
tight close-up filling the frame".)

### V4 — Background: subtle aurora + wisps → minimal clean gradient

Replace the background sentence with:
"Background: a clean, smooth dusk-gradient sky fading from deep violet at the
top to a warm amber glow at the bottom, softly vignetted so the character
pops — no other background elements."
(Condensed: replace "Violet-to-amber dusk sky, faint glowing wisp dots" with
"clean violet-to-amber gradient sky".)

---

## Known-failure appendix — pre-written fixes

Apply ONLY the fix matching the observed failure; keep everything else as-is.

**Condensed (Bing) forms:** each fix below includes a condensed equivalent. If
a condensed prompt exceeds ~480 chars, first drop "faint glowing wisp dots"
then "Cyan rim light left, warm amber light lower right." — trim the scene,
never the character or the ghost.

**F1 — Face fusion (two faces merge into one two-headed figure).** Decompose
the possession. Replace the ghost-face sentence with:
"Beside the character's head, slightly overlapping its upper-left corner, a
separate translucent glowing cyan ghost — a simple friendly spirit with its
own distinct face — leans toward the character as if about to dive into it,
wispy tail trailing off-frame."
(Condensed: replace "A translucent glowing cyan ghost face with a mischievous
smile slides into its head, wispy trail, cyan glow at contact." with "A
separate friendly translucent cyan ghost, with its own distinct smiling face,
leans in to dive into its head, wispy tail trailing.")

**F2 — Wrong palette (colors drift).** Append:
"Color palette: deep violet #3B2A6E sky, warm amber #E8703A horizon glow,
cream #F2C894 character, bright cyan #6FE3FF ghost, golden #FFB84D accents."
(Condensed: append "Colors: deep violet sky, warm amber glow, cream body,
bright cyan ghost." and trim per the note.)

**F3 — Photorealism (human skin, realistic render).** Prepend:
"Cute cartoon render, smooth plastic toy material, like a poster for a
children's animated movie." and append: "Not realistic, no human skin
texture, no fine surface detail."
(Condensed: append "Cute cartoon plastic toy render, not realistic, no human
skin." and trim per the note.)

**F4 — Text appears anywhere.** Append:
"Absolutely no text, letters, numbers, words, signage, captions, or logos
anywhere in the image."
(Condensed: replace "No text, no logos." with "Absolutely no text, letters,
numbers, or logos anywhere.")

**F5 — Creepy/horror read.** Append:
"Friendly, comedic, bright and colorful — suitable for children."
(Condensed: append "Friendly, comedic, bright, kid-friendly." and trim per
the note.)
