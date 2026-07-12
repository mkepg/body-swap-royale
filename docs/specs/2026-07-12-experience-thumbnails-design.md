# Experience Thumbnails — "Swap Story" Set (Design)

**Date:** 2026-07-12
**Status:** Approved concept, pre-production (prompt kit + tooling next)
**Related:**
- [body-swap-royale-gdd.md](../../body-swap-royale-gdd.md) §1 (core loop)
- [2026-07-12-experience-icon-swap-concept-design.md](2026-07-12-experience-icon-swap-concept-design.md) — the shipped "Swap Arrows" icon; thumbnails are the same brand family
- `docs/marketing/experience-icon/` — the icon slice, which is the workflow of record (README, prompts.md, finalize-icon.ps1)

## 1. Goal

Produce the Roblox Experience **Thumbnails** — the 16:9 images in the store-page
carousel (Roblox recommends 1920×1080; up to ~10 allowed). Unlike the single icon,
the carousel can tell the mechanic as a **sequence/story** across multiple images.
The set must feel like the same brand family as the shipped "Swap Arrows" icon
(orange/blue boy + pink/teal girl, cyan soul-⇄, Soul Festival dusk palette).

Core loop being communicated (GDD §1): every 30 seconds control is randomly
reassigned — you get swapped into another player's body; combat-free survival
royale where the arena itself is the threat.

## 2. The set — "Swap Story" (4 images)

Four 16:9 frames, one clear idea each, in carousel order. Each carries a
**composited caption band** (see §4). Frame #1 is the primary store thumbnail.

| # | Idea | Scene | Caption (working) |
|---|------|-------|-------------------|
| 1 | **The swap (hero)** | Boy (near-white cube head, spiky ORANGE hair, royal-blue hoodie w/ orange accents) + girl (long PINK ponytail, teal hoodie), head-and-shoulders, angled slightly inward, both comic-surprise. Bold glowing CYAN soul-energy double-arrow ⇄ between/above their heads. The icon reflowed to 16:9 with more dusk sky. | **SWAPPED into their body** |
| 2 | **Every 30 seconds** | 3–4 blocky avatars mid-scramble in the dusk arena; cyan soul-wisps/arrows arcing between several of them; a glowing cyan soul-RING (no digits) as a timer motif. Reads "control keeps reassigning." | **Every 30 seconds** |
| 3 | **Survive the arena** | Single blocky avatar in comic panic reacting to an environmental hazard (crumbling platform / glowing hazard edge). Combat-free — the arena is the threat, last one standing. | **Survive the arena** |
| 4 | **Play with friends** | Lineup of 4+ distinct colorful blocky avatars together, festive dusk, a little cyan swap-glow. Social/party pull. | **Grab your friends** |

Captions are composited in post (§4), so wording is cheap to change during
finalize; the table values are the current defaults.

### 2.1 Recurring brand elements (consistency with the icon)
- Same two hero characters (boy orange/blue, girl pink/teal) appear in #1; their
  color logic (warm hair, cool outfits) governs any additional avatars.
- Every frame: unmistakable classic Roblox avatars — cube heads, flat printed
  **decal** faces (no protruding 3D eyeballs), slab torsos, straight
  non-tapering block arms, **NO hands/fingers**. Off-model = re-roll.
- Cyan #6FE3FF stays the only bright-cyan element per frame (the swap-energy
  focal signal); recurs across the set to tie it to the icon.

### 2.2 Palette & staging (unchanged Soul Festival dusk)
Violet #3B2A6E → amber #E8703A dusk sky; cyan #6FE3FF soul energy/wisps;
gold #FFB84D accents; near-white skin. A few faint soul-wisp dots, one subtle
teal aurora ribbon, soft vignette. **16:9 landscape, full-bleed.**

## 3. Two locked defaults

- **Timer motif on #2 = a glowing cyan soul-ring shape, NO numbers.** Gemini
  cannot render "0:30" cleanly and the caption already carries "30 seconds";
  keep all Gemini art digit-free.
- **Tracking = same as the icon slice:** candidates + reference + finals all
  committed to git; `desktop.ini` gitignored. Work on branch
  `feat/experience-thumbnails` off `main`. `src/shared/Config.luau` has
  uncommitted dev flips — **never stage/commit it**; this slice touches no Luau.

## 4. Text: composited caption band (NOT Gemini-rendered)

Gemini renders text unreliably (garbled letters). Therefore:
- **Prompts always say "no text, no letters, no numbers, no logos."**
- Captions are **composited by us in post**, after the art is generated,
  watermark-cleaned, and cropped to 1920×1080: crisp vector type in the
  **Fredoka** brand font, placed in a bottom band with a dark upward gradient
  for contrast (gold #FFB84D keyword + white), within the central safe zone.
- This keeps letters perfect and moderation-safe, and makes caption wording
  trivially editable without re-rolling art.

## 5. Production pipeline (carries the icon playbook forward)

1. **Generate (user):** Gemini only (Bing dropped). Upload
   `reference/ref-avatar.png` (grey R15) with EVERY prompt to lock block
   proportions. Request **16:9 landscape**. Save EVERY roll (good + bad = data)
   to `docs/marketing/thumbnails/candidates/` as
   `gemini-t{frame}-{variant}-{roll}.png` (frame ∈ `t1`..`t4`; variant ∈
   `m` (master) | `v1`..`vN` | `r1`/`r2` for refine rounds; roll = 1,2,3…).
2. **Review:** every candidate scored vs the §6 checklist; legibility
   verified by downscaling to carousel width and Reading the output (PowerShell +
   System.Drawing HighQualityBicubic — no working ImageMagick). Shortlist per frame.
3. **Refine (≤2 rounds per frame):** merged-traits prompt, re-rolled in Gemini.
4. **Finalize (per chosen frame):**
   a. Remove the Gemini ✦ watermark from the winner's bottom-right on the
      full-res PNG via inpaint. Match the interpolation axis to any hard edge the
      ✦ sits on (per-column vertical interpolation for a vertical seam). Verify at
      full-res AND final size.
   b. Run the **16:9 finalize script** (`scripts/finalize-thumbnail.ps1`, a
      landscape variant of `finalize-icon.ps1`): crop/pad to exactly 1920×1080
      via HighQualityBicubic.
   c. Composite the caption band (Fredoka vector) via
      `scripts/composite-caption.ps1` (System.Drawing text draw).
   d. Export to `docs/marketing/thumbnails/final/thumb-{1-4}-1920.png`. Commit.
5. **Upload (user):** Creator Dashboard → **Configure → Places** → start place →
   **Thumbnails** → add each image. Goes through moderation; replaceable at zero
   cost — ship and iterate.

### 5.1 Working folder layout (mirrors the icon slice)
```
docs/marketing/thumbnails/
  README.md          — workflow of record for this slice
  prompts.md         — Gemini kit: 4 masters (T1–T4) + per-frame variants + failure-fixes
  reference/         — reuse the grey R15 ref-avatar.png (same file uploaded to Gemini)
  candidates/        — every roll, gemini-t{frame}-{variant}-{roll}.png
  final/             — thumb-1-1920.png … thumb-4-1920.png (shipped assets)
```

## 6. Acceptance checklist (adapted from the icon's 8 → 9)

1. **Carousel-size legible** — the frame's idea reads at carousel width (verify by downscale).
2. **Authenticity** — unmistakable classic Roblox avatars (cube heads, decal faces, no hands).
3. **Communicates its one idea** — swap / 30s reassign / survival / social, respectively.
4. **Safe zone** — subject + caption within the central ~90%; Roblox may crop edges.
5. **One clear idea** — no competing subjects; the frame says exactly one thing.
6. **Tone** — comic surprise, mischievous, kid-friendly, zero horror.
7. **Compliance** — captions moderation-safe; no other text/letters/logos; ✦ watermark removed at finalize.
8. **Brand consistency** — same characters, palette, and cyan soul motif as the shipped icon; the set reads as one family.
9. **Caption contrast** — composited text passes contrast over its band at small size.

## 7. Deliverables of THIS slice (scaffolding + tooling)

The image generation is human-in-the-loop; what is built now is everything the
user needs to start rolling and to finalize:
- `docs/marketing/thumbnails/` folder + `README.md` + `reference/ref-avatar.png`.
- `docs/marketing/thumbnails/prompts.md` — the paste-ready Gemini kit (4 masters +
  variants + failure-fixes), built in the style of the icon's `prompts.md`.
- `scripts/finalize-thumbnail.ps1` — crop/pad any source to 1920×1080 (HighQualityBicubic).
- `scripts/composite-caption.ps1` — draw a Fredoka caption band onto a 1920×1080 PNG.

## 8. Risks / open questions

- **Gemini aspect ratio** — it may output square/other ratios; request 16:9 and
  let the finalize script crop/pad. Composition must keep subject + caption safe
  under a center-crop.
- **Multi-avatar frames (#2, #4)** — more characters = more off-model drift risk;
  the reference image + explicit per-character wording should hold; re-roll drift.
- **Caption font availability** — `composite-caption.ps1` needs Fredoka installed,
  or falls back to a bundled/graceful default; the script must handle a missing font.
- **Frame #3 hazard reading as combat/violence** — keep it environmental
  (crumbling/floor hazard), comic panic, never a weapon or another player attacking.
