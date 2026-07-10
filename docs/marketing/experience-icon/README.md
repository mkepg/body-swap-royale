# Experience Icon — Working Folder

Production kit for the Roblox Experience Icon.
Spec: `docs/superpowers/specs/2026-07-10-experience-icon-design.md`

## Layout

- `prompts.md` — master prompt (full + condensed) + variants V1–V4 + failure fixes
- `candidates/` — EVERY generated image, named `{tool}-{variant}-{roll}.png`
  (`tool` ∈ `bing` | `gemini`; `variant` ∈ `master` | `v1`..`v4` | `r1` | `r2`
  for refinement rounds; `roll` = 1, 2, 3…)
- `final/icon-512.png` — the shipped asset; the repo copy is the source of truth

## Workflow (spec §7)

1. **Generate (user):** run master + V1–V4 in both Bing Image Creator and
   Gemini (≥10 images). Save everything to `candidates/`.
2. **Review (Claude):** every candidate scored against the spec §8 checklist;
   3-size gallery (512/128/64 px) pushed to the visual companion; user picks
   the winner or winning traits.
3. **Refine (max 2 rounds):** merged-traits prompt (`r1`, then `r2` at most),
   re-rolled in the tool that won Phase 2.
4. **Finalize:** `scripts/finalize-icon.ps1 -Source <winner.png>` writes
   `final/icon-512.png` (center-crop + high-quality downscale). Commit it.

## Uploading to Roblox (Creator Dashboard)

1. https://create.roblox.com → **Creations** → select the Body Swap Royale
   experience.
2. **Configure** (⚙) → **Basic Info** → **Icon** → upload
   `final/icon-512.png` (512×512 PNG).
3. Save. The icon goes through moderation review (usually minutes–hours);
   it can be replaced at any time at zero cost — ship and iterate.
