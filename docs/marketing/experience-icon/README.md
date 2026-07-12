# Experience Icon — Working Folder

Production kit for the Roblox Experience Icon.
Concept spec: `docs/specs/2026-07-12-experience-icon-swap-concept-design.md`
(supersedes the 2026-07-10 possession concept). Process/palette/checklist history: `docs/specs/2026-07-10-experience-icon-design.md`.

## Layout

- `prompts.md` — Gemini-only "Swap Arrows" kit: Master + variants V1–V4 + failure fixes F1–F7
- `candidates/` — EVERY generated image, named `gemini-{variant}-{roll}.png`
  (`variant` ∈ `swap` (master) | `v1`..`v4` | `r1` | `r2` for refinement rounds;
  `roll` = 1, 2, 3…). Earlier `bing-*` / `master*` files are historical.
- `final/icon-512.png` — the shipped asset; the repo copy is the source of truth

## Workflow

1. **Generate (user):** upload `reference/ref-avatar.png` to Gemini and run
   Master + V1–V4 (≥10 images). Save everything to `candidates/`.
2. **Review:** every candidate scored against the concept-spec §3 checklist;
   3-size gallery (512/128/64 px) pushed to the visual companion; user picks
   the winner or winning traits.
3. **Refine (max 2 rounds):** merged-traits prompt (`r1`, then `r2` at most),
   re-rolled in the tool that won Phase 2.
4. **Finalize:** first remove the Gemini ✦ watermark from the winner's
   bottom-right corner (bilinear-gradient inpaint on the full-res PNG — see the
   concept spec §4; `finalize-icon.ps1` does NOT do this itself), then run
   `scripts/finalize-icon.ps1 -Source <cleaned.png>` to write `final/icon-512.png`
   (center-crop + high-quality downscale). Commit it.

## Uploading to Roblox (Creator Dashboard)

1. https://create.roblox.com → **Creations** → select the Body Swap Royale
   experience.
2. Left nav: **Configure → Places** → click the experience's start place.
3. In the place's settings, select **Icon** in the left nav → media type
   **Image** → **Change** → upload `final/icon-512.png` (512×512 PNG) →
   **Save Changes**.
4. The icon goes through moderation review before it appears publicly; it can
   be replaced at any time at zero cost — ship and iterate. (If the dashboard
   labels differ slightly, the invariant is: the icon lives under the START
   PLACE's settings, not the experience-level Basic Info.)
