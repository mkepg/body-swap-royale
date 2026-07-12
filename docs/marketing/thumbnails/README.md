# Experience Thumbnails — Working Folder

Production kit for the Roblox Experience **Thumbnails** (16:9 store carousel).
Concept + pipeline spec: `docs/superpowers/specs/2026-07-12-experience-thumbnails-design.md`.
Same brand family as the shipped icon (`docs/marketing/experience-icon/`), which
is the workflow of record.

## The set — "Swap Story" (4 images, 1920×1080)

1. **The swap (hero)** — boy (orange/blue) + girl (pink/teal) + cyan soul-⇄. Caption: "SWAPPED into their body". *Primary store thumbnail.*
2. **Every 30 seconds** — 3–4 avatars mid-scramble, cyan swap-wisps, glowing soul-ring (no digits). Caption: "Every 30 seconds".
3. **Survive the arena** — one avatar in comic panic at an environmental hazard. Caption: "Survive the arena".
4. **Play with friends** — lineup of 4+ colorful avatars, festive. Caption: "Grab your friends".

## Layout

- `prompts.md` — Gemini kit: four Masters (T1–T4) + per-frame variants + failure-fixes.
- `reference/ref-avatar.png` — grey R15 avatar; upload with EVERY prompt.
- `candidates/` — every roll, `gemini-t{frame}-{variant}-{roll}.png` (frame ∈ `t1`..`t4`; variant ∈ `m`|`v1`..|`r1`/`r2`; roll = 1,2,…). Bad rolls are data — keep them.
- `final/` — shipped assets `thumb-1-1920.png` … `thumb-4-1920.png`.

## Workflow

1. **Generate (user):** upload `reference/ref-avatar.png` to Gemini, run the Master + variants for each frame, request 16:9 landscape. Save everything to `candidates/`.
2. **Review (Claude):** score each candidate vs the spec §6 checklist; verify legibility by downscaling to carousel width.
3. **Refine (≤2 rounds per frame):** merged-traits prompt, re-rolled in Gemini.
4. **Finalize (per frame):**
   a. Remove the Gemini ✦ watermark on the full-res winner via inpaint (match interpolation axis to any hard edge; verify at full-res AND final size).
   b. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/finalize-thumbnail.ps1 -Source <cleaned.png> -Out docs/marketing/thumbnails/final/thumb-1-1920.png` (cover-crop → 1920×1080).
   c. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/composite-caption.ps1 -Source docs/marketing/thumbnails/final/thumb-1-1920.png -Text "SWAPPED into their body" -Highlight "SWAPPED" -Out docs/marketing/thumbnails/final/thumb-1-1920.png` (draw caption band).
   d. Commit the final.

## Uploading to Roblox (Creator Dashboard)

1. https://create.roblox.com → **Creations** → select Body Swap Royale.
2. **Configure → Places** → click the start place.
3. Select **Thumbnails** in the left nav → add each `final/thumb-*-1920.png` in carousel order → **Save**.
4. Images go through moderation; they're replaceable at zero cost — ship and iterate.
