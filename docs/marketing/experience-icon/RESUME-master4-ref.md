# Experience Icon — Session Resume + master4-ref Plan (self-contained)

> **HISTORICAL (superseded 2026-07-12).** The single-character "Possession Close-Up"
> below shipped as `candidates/gemini-master8-ref-1.png` but tested as not
> communicating the game. The active concept is now **"Swap Arrows"** — see
> `docs/superpowers/specs/2026-07-12-experience-icon-swap-concept-design.md` and
> `prompts.md`. This file is kept for its process notes and reference-image recipe.

**Purpose:** Rebuild and continue the Experience Icon workflow from scratch in a
fresh session, with the full history of what failed and why, and a concrete plan
for the next (not-yet-created) iteration, **master4-ref**. This document is
self-contained: every prompt needed is inline, so it works even if the other
`docs/marketing/experience-icon/` files are missing.

---

## 0. Project context (read before doing anything)

- **Repo:** `C:\Users\gomez\repos\Roblox_Projects\body-swap-royale` (Roblox/Luau, Rojo).
- **Branch discipline:** start work on a fresh branch off `main`. The arena-dim
  work is merged; the icon kit was committed on an **un-merged** branch
  (`feat/experience-icon`) and currently also exists as **untracked** files under
  `docs/marketing/experience-icon/`. This document is written to survive that:
  don't rely on the other files existing — everything you need is here.
- **DEV-FLIP HAZARD:** `src/shared/Config.luau` carries two deliberate uncommitted
  dev flips (`SOLO_TEST_MODE = true`, `ARENA_OVERRIDE = "sweeper"`). NEVER commit
  them. This icon work touches no Luau, so you shouldn't be staging Config at all.
- **Production model:** AI-generated art, free tools. **Gemini is now the primary
  tool** (it accepts a reference image); **Bing Image Creator is secondary/likely
  dead for this** (text-only, can't take a reference — see §2).

## 1. The goal (unchanged across all iterations)

A **512×512 Roblox Experience Icon**, concept **A — "The Possession Close-Up":**
one big, blocky **Roblox-avatar** character in comic shock while a translucent
**cyan soul-face** slides into its head (the swap/possession mechanic in one read).

- **Style:** chunky glossy 3D, party-game key-art register (Fall Guys / Stumble
  Guys energy — never name those brands in the prompt).
- **Palette (Soul Festival Sky):** violet `#3B2A6E` → amber `#E8703A` dusk sky;
  cream character `#F2C894`; cyan soul `#6FE3FF`; gold accent `#FFB84D`.
- **Tone:** funny-scared (comedic panic), never distressed/horror. The ghost is
  mischievous, not menacing — it's the incoming *player*, not a monster.
- **Hard constraints:** square 1:1; all critical content inside the central ~80%
  (Roblox rounds corners); must read at **64px**; **no text, no logos, no Roblox
  trademarks**; moderation-safe.
- **Acceptance checklist (score every candidate against all 7):**
  1. **64px read** — shocked face + second color mass both legible at 64px.
  2. **Authenticity** — unmistakably a **Roblox avatar** (see §3), Soul Festival
     palette, depicts possession, nothing the game doesn't do.
  3. **Safe zone** — critical content within central ~80%.
  4. **One focal subject** — no fused two-headed figure, no crowd.
  5. **Tone** — funny-scared, mischievous soul; zero horror.
  6. **Compliance** — no text, no trademarks, moderation-safe.
  7. **Contrast pop** — subject separates from the dusk background in a grayscale
     squint test.

## 2. Iteration log — what was tried, what failed, and why

> These are direct observations from reviewing the actual generated images, not
> assumptions. Candidates live in `docs/marketing/experience-icon/candidates/`.

### master1 — original prompt ("chunky glossy 3D toy style, blocky boxy cartoon character")
Files: `gemini-master-1.png`, `bing-master-1.jpg`.

- **Gemini result:** composition, palette, ghost, and tone were all good — but the
  character rendered as a **generic vinyl/marshmallow mascot**: bulging 3D spherical
  eyeballs *protruding* off the face, a soft rounded head (not a distinct cube), and
  rounded arms implying hands. It read as "cute mascot," **not a Roblox avatar**. The
  single most recognizable Roblox trait — a **flat face printed on the head like a
  sticker** — was entirely absent.
- **Bing result:** two extra failures on top of the same generic character:
  (a) **landscape**, not square (cropping would slice the ghost); (b) **blank eyes**
  — white ovals with no pupils, reading vacant/eerie (wrong tone).
- **Why it failed / lesson:** the words "toy style" actively invite LEGO/vinyl-toy
  tropes (dome eyes, rounded limbs). Nothing in the prompt anchored the
  Roblox-specific silhouette or the flat decal face. Bing additionally needs
  *explicit* "square 1:1" and *explicit* "pupils."

### master2 — Roblox-geometry wording ("blocky video-game avatar, face printed FLAT on the cube head like a sticker decal, box-segment body, block arms, no fingers")
Files: `gemini-master2-*.png`.

- **What improved:** the **flat decal face started landing** — the user confirmed
  "the avatar face from gemini-master2-1 captures the Roblox style much better." This
  proved the phrase **"face printed flat on the head like a decal/sticker"** is the
  key lever that produces the Roblox face.
- **What still failed:** the overall **body and proportions** still read as a generic
  blocky toy, not a Roblox avatar. The face was right; the silhouette
  (head:torso:limb ratios, the characteristic rectangular slab torso and straight
  block limbs) did not lock. Verdict from the user: "they do not look like Roblox
  avatars at all" *except* the face.
- **Why it failed / lesson:** the face is solvable with wording; **proportions are
  not reliably solvable with wording.** Also, deliberately avoiding the word "Roblox"
  left the model without an anchor for the specific shape.

### master3 — explicit "classic blocky Roblox avatar" wording (+ 480-char Bing variant)
Files: `gemini-master3-1.png` (the **closest** candidate so far).

- **What improved:** distinct **cube head** with a proper **flat printed cartoon
  face** (comic-shock eyes + small open mouth) — the Roblox face signature fully
  achieved. Square, full-bleed (no baked frame), correct dusk palette, mischievous
  cyan ghost, right comedic tone. Passes most of the checklist.
- **What still failed:** the **proportions remain slightly off-model** — the arms
  **taper** (LEGO-ish) instead of being straight rectangular prisms; the head-to-body
  ratio and torso shape aren't quite R15. The result reads as "a blocky character
  wearing a Roblox face," not unmistakably "a Roblox avatar."
- **Why it failed / lesson (the decisive one):** even with an explicit "Roblox
  avatar" description plus geometry adjectives, **text prompting plateaus at
  'blocky-toy-with-a-flat-face.'** A free text-to-image model cannot reliably
  reproduce a *specific proprietary silhouette* (R15: rectangular slab torso,
  straight cylindrical/block limbs, no hands, specific proportions) from words alone.

### The core lesson driving master4-ref
Stop asking text to *describe* the Roblox shape — **show** it. A specific proprietary
silhouette needs **image conditioning** (a reference image), not more adjectives.
- **Gemini can do this** (upload a reference image alongside the prompt).
- **Bing Image Creator cannot** (text-only, no image upload) → Bing is retired for
  the primary path; keep it only as a text-only backup if Gemini is unavailable.

## 3. What "looks like a Roblox avatar" concretely means (the authenticity bar)
Bake these into every judgment; they're what master1–3 kept missing:
- **Flat face printed on the front of a cube head** like a sticker/decal — NOT 3D
  protruding eyeballs. (Solved by master2/3 wording; keep it.)
- **Rectangular slab torso** — a boxy block, wider/flatter, not a rounded body.
- **Straight rectangular/cylindrical limbs** — arms and legs are plain blocks that
  do **not taper**; **no hands, no fingers.** (The master3 gap.)
- **Blocky, clean, glossy plastic** — smooth surfaces, high saturation.
- **Proportions:** big cube head on a simple block body; readable as an avatar at a
  glance and at 64px.

## 4. master4-ref — the planned reference iteration (NOT yet created)

**Thesis:** the first iteration expected to clear the authenticity bar, because it
fixes the one thing text could not — **proportions/silhouette** — via a reference
image, while keeping everything master3 already got right (flat face, palette, ghost,
tone, square, full-bleed).

### 4.1 Objectives
1. **Lock Roblox R15 proportions** (slab torso, straight non-tapering block limbs,
   no hands) by conditioning on a real default-avatar reference.
2. **Preserve master3's wins:** flat decal face, comic-shock expression, cyan
   possession ghost, Soul Festival dusk palette, square + full-bleed, comedic tone.
3. **Pass all 7 acceptance checks (§1)** — especially #2 authenticity and #1 64px.

### 4.2 Design principles
- **Show, don't tell** for shape: reference image = structural authority for the body.
- **Tell, don't show** for scene: the prompt owns the possession moment, lighting,
  palette, tone, and framing (the reference is a plain avatar, not the scene).
- **One controlled variable per variant** (so we learn *why* something works).
- **Behavior of the reference:** guide **proportions and silhouette only** — the
  model must re-skin it in cream plastic, add the flat cartoon face, the ghost, and
  the dusk scene. Do NOT copy the reference's colors, outfit, or pose verbatim.

### 4.3 Visual language (unchanged targets, restated for the generator)
Cube head + flat printed cartoon face (huge white eyes, small dark pupils darting
up-left in comic shock, small open mouth) · rectangular slab torso · straight block
arms, no hands · cream `#F2C894` glossy plastic · translucent cyan `#6FE3FF` ghost
face (mischievous smile) sliding into the head with a wispy trail + cyan contact
glow · cool cyan rim light left, warm amber fill lower-right · violet→amber dusk sky
with faint wisps + one subtle aurora · square, full-bleed, centered.

### 4.4 Constraints / must-introduce improvements (vs. master1–3)
- **MUST fix proportions:** straight, non-tapering block limbs; **no hands/fingers**;
  slab torso; R15 head:body ratio (this is the master3 gap).
- **MUST keep the flat decal face** (never revert to protruding 3D eyeballs — the
  master1 failure).
- **MUST be square + full-bleed** (the Bing-master1 failure); if any tool adds a
  border or letterboxes, re-roll.
- **MUST keep pupils / directed gaze** (the Bing-master1 blank-eye failure).
- **MUST stay brand-free:** no "Roblox" logo, no text, no third-party marks in the
  image, even though the *reference* is a Roblox avatar and the *prompt* may say the
  word "Roblox avatar" as a shape descriptor.

### 4.5 The reference image to use
A **plain default Roblox avatar** (grey/neutral, no elaborate cosmetics — we want its
*shape*, not someone's outfit). Sources, in order of authenticity:
1. **Best (on-model):** open the game in Studio, drop a default **R15 dummy** (or the
   game's normalized body), screenshot it against a plain background.
2. **Fastest:** a clean "Roblox default avatar render" (front view, plain background).
Use a front-facing, full-or-upper-body, uncluttered shot so proportions read clearly.

### 4.6 master4-ref prompt — Gemini (upload the reference image, then paste this)

```text
Use the blocky character in the attached reference image ONLY as a structural
guide for the body proportions and silhouette — the rectangular block head, the
straight rectangular block arms and legs that do NOT taper, the flat slab torso,
and the fact that it has NO hands and NO fingers. Do not copy its colors, outfit,
or pose. Rebuild that same blocky avatar as a square app icon for a family-friendly
multiplayer party game, in a chunky glossy 3D toy style like modern party-game key
art. Render the character in smooth cream-tan glossy plastic, shown head and
shoulders, filling about seventy percent of the frame. Its face is a simple cartoon
face printed FLAT on the front of the cube head like a sticker decal (not protruding
eyeballs): huge white oval eyes with small dark pupils darting toward the upper left
in comic, funny shock, and a small open mouth — playfully startled, never distressed.
Overlapping the upper-left of its head, a translucent glowing cyan ghost face —
serene and slightly mischievous, with simple eyes and a small smile — is sliding
INTO the character's head, its wispy light-trail curving away off-frame, with a soft
cyan glow blooming where the two touch. Lighting: cool cyan rim light on the left
side of the head from the ghost, warm amber fill light from the lower right.
Background: a dusk sky fading from deep violet at the top to a warm amber glow at the
bottom, a few faint glowing soul-wisp dots, one subtle teal aurora ribbon, softly
vignetted so the character pops. High saturation, bold simple shapes, centered,
filling the whole square canvas with breathing room on all sides. No text, no
letters, no logos, no watermark, no border.
```

### 4.7 master4-ref single-axis variants (run after the base, change ONE thing)
- **v1 — Expression:** comic terror → delighted panic (huge gleeful open-mouthed grin
  instead of a small open mouth).
- **v2 — Ghost position:** corner overlap → the ghost descending face-to-face from
  directly above, wispy trail rising off the top.
- **v3 — Camera:** head-and-shoulders (~70%) → tight face-only close-up.
- **v4 — Reference strength:** re-run the base but instruct "follow the reference's
  proportions **strictly / exactly**" to push authenticity harder (tests whether more
  reference adherence helps or stiffens the pose).

### 4.8 Known-failure fixes (apply only the matching one)
- **Proportions still LEGO/tapered:** add "the arms and legs are perfectly straight
  rectangular blocks of uniform thickness, like the reference; absolutely no hands,
  no fingers, no tapering."
- **Face fused / two-headed:** "the cyan ghost is a SEPARATE translucent spirit
  beside and overlapping the head, with its own distinct face, leaning in to dive
  into the head — not merged with it."
- **3D eyeballs came back:** "the face is a flat 2D cartoon decal printed on the cube
  surface, completely flush, no 3D eyeballs, no depth."
- **Colors drift:** "Palette: deep violet #3B2A6E sky, warm amber #E8703A glow, cream
  #F2C894 character, bright cyan #6FE3FF ghost, gold #FFB84D accents."
- **Text/logo appears:** "Absolutely no text, letters, numbers, words, or logos
  anywhere in the image."
- **Creepy/horror read:** "Friendly, comedic, bright, and colorful — for children."
- **Not square / bordered:** "Perfectly square 1:1 composition, full-bleed to all
  edges, no frame, no border, no letterboxing."

## 5. Workflow to rebuild from scratch

**Folder + naming** (create if missing):
```
docs/marketing/experience-icon/
  candidates/   -- every roll: {tool}-{variant}-{roll}.png  e.g. gemini-master4-ref-1.png
  final/        -- final/icon-512.png (the shipped asset)
```
Save EVERY roll (bad ones are data). For master4-ref rolls use
`gemini-master4-ref-1.png`, `-2`, …; for its variants `gemini-master4-ref-v1-1.png`, etc.

**Loop (spec §7 phases):**
1. **Generate (user):** upload the reference to Gemini, run the §4.6 base prompt, then
   the §4.7 variants; save all to `candidates/`.
2. **Review (Claude):** score each against the §1 checklist; push a 512/128/64px
   comparison gallery via the brainstorming visual companion; user picks a winner or
   winning traits.
3. **Refine (≤2 rounds):** merge winning traits + any §4.8 fix; re-roll in Gemini.
4. **Finalize:** `powershell -NoProfile -ExecutionPolicy Bypass -File
   scripts/finalize-icon.ps1 -Source docs/marketing/experience-icon/candidates/<winner>.png`
   → writes `final/icon-512.png` (center-crop + high-quality downscale to 512²). If the
   script is missing, recreate it (it uses System.Drawing: center-crop to square, then
   HighQualityBicubic resize to 512×512, save PNG; accepts `-Source`, `-Out`
   defaulting to `docs/marketing/experience-icon/final/icon-512.png`, `-Size` 512).
5. **Upload (Creator Dashboard):** create.roblox.com → Creations → the experience →
   **Configure → Places → [start place] → Icon** → media type Image → Change → upload
   `final/icon-512.png` → Save. Moderation review precedes public display; the icon is
   replaceable at zero cost — ship and iterate.

## 6. If the reference approach also plateaus (fallback ladder)
1. Try §4.7 **v4** (strict reference adherence) + the "straight blocks, no fingers" fix.
2. Try a **cleaner/simpler reference** (plain grey R15 dummy, front view, no cosmetics).
3. If Gemini still won't hold proportions, re-decide with the user: either accept the
   best "Roblox-faced blocky" result (master3-class) as good-enough for a v1 icon
   (it's replaceable later), or escalate to a commissioned/edited asset. Do NOT
   silently ship an off-brand character.
