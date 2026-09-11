# Experience Thumbnails Implementation Plan

**Goal:** Scaffold the `docs/marketing/thumbnails/` working folder and build the two PowerShell finalize/caption tools so the user can start rolling the 4-image "Swap Story" thumbnail set in Gemini and finalize winners to 1920×1080.

**Architecture:** This slice is scaffolding + tooling only; image generation is human-in-the-loop in Gemini. We create (1) the working folder + README + reference image, (2) the paste-ready Gemini prompt kit, (3) `finalize-thumbnail.ps1` (cover-crop any source to 1920×1080 via HighQualityBicubic — the 16:9 sibling of `finalize-icon.ps1`), and (4) `composite-caption.ps1` (draw a Fredoka caption band onto a 1920×1080 PNG, with graceful font fallback). The two PowerShell scripts are verified by small harness scripts that synthesize an input PNG and assert output dimensions.

**Tech Stack:** Markdown docs; Windows PowerShell + `System.Drawing` (no working ImageMagick); Git Bash for git. Reference spec: `docs/specs/2026-07-12-experience-thumbnails-design.md`.

**Conventions for every task:** run commands from repo root `<repo-root>`. NEVER `git add -A`/`git add .`; stage only the exact files named. NEVER stage `src/shared/Config.luau` (uncommitted dev flips). Branch is already `feat/experience-thumbnails`.

---

## Task 1: Scaffold working folder + reference image

**Files:**
- Create: `docs/marketing/thumbnails/candidates/.gitkeep`
- Create: `docs/marketing/thumbnails/final/.gitkeep`
- Create: `docs/marketing/thumbnails/reference/ref-avatar.png` (copy of the icon slice's reference)

- [ ] **Step 1: Create the folder tree with keep-files**

Run:
```bash
mkdir -p docs/marketing/thumbnails/candidates docs/marketing/thumbnails/final docs/marketing/thumbnails/reference
touch docs/marketing/thumbnails/candidates/.gitkeep docs/marketing/thumbnails/final/.gitkeep
```

- [ ] **Step 2: Copy the grey R15 reference avatar from the icon slice**

Run:
```bash
cp docs/marketing/experience-icon/reference/ref-avatar.png docs/marketing/thumbnails/reference/ref-avatar.png
```

- [ ] **Step 3: Verify the reference copied and is a valid PNG (non-zero size)**

Run:
```bash
ls -l docs/marketing/thumbnails/reference/ref-avatar.png
```
Expected: file exists, size > 1000 bytes (same size as the source).

- [ ] **Step 4: Commit**

```bash
git add docs/marketing/thumbnails/candidates/.gitkeep docs/marketing/thumbnails/final/.gitkeep docs/marketing/thumbnails/reference/ref-avatar.png
git commit -m "chore(thumbnails): scaffold working folder + reference avatar"
```

---

## Task 2: Write the working-folder README

**Files:**
- Create: `docs/marketing/thumbnails/README.md`

- [ ] **Step 1: Write the README**

Write `docs/marketing/thumbnails/README.md` with this content:

```markdown
# Experience Thumbnails — Working Folder

Production kit for the Roblox Experience **Thumbnails** (16:9 store carousel).
Concept + pipeline spec: `docs/specs/2026-07-12-experience-thumbnails-design.md`.
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
2. **Review:** score each candidate vs the spec §6 checklist; verify legibility by downscaling to carousel width.
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
```

- [ ] **Step 2: Verify no placeholders and links resolve**

Run:
```bash
grep -nE "TODO|TBD|FIXME" docs/marketing/thumbnails/README.md || echo "clean"
ls docs/specs/2026-07-12-experience-thumbnails-design.md scripts/finalize-thumbnail.ps1 2>/dev/null || echo "note: finalize-thumbnail.ps1 comes in Task 4"
```
Expected: "clean"; the spec path resolves (the script path is created later, that's fine).

- [ ] **Step 3: Commit**

```bash
git add docs/marketing/thumbnails/README.md
git commit -m "docs(thumbnails): add working-folder README"
```

---

## Task 3: Write the Gemini prompt kit

**Files:**
- Create: `docs/marketing/thumbnails/prompts.md`

Built in the exact style of `docs/marketing/experience-icon/prompts.md` (read it first
as the reference). Four Masters (one per frame), 2 variants each on a single axis,
and shared failure-fix add-ons. Every prompt ends with the no-text guard and requests
16:9. The reference avatar is uploaded with every prompt.

- [ ] **Step 1: Read the icon kit for house style**

Run:
```bash
sed -n '1,30p' docs/marketing/experience-icon/prompts.md
```
Expected: see the header + Master format to mirror (self-contained paste-ready blocks, reference-upload note, no-text guard).

- [ ] **Step 2: Write `docs/marketing/thumbnails/prompts.md`**

Write the file with:
- A header mirroring the icon kit: concept one-liner, "Gemini only / reference-guided / request 16:9 landscape", the `gemini-t{frame}-{variant}-{roll}.png` naming rule, and a pointer to spec §6.
- **Four Master prompts** — `T1` (hero swap), `T2` (30s chaos, glowing cyan soul-RING with NO digits + 3–4 avatars + swap-wisps), `T3` (survive: one avatar comic panic at an ENVIRONMENTAL hazard — crumbling platform / glowing floor edge, NO weapons, NO other player attacking), `T4` (4+ distinct colorful avatars together, festive party lineup). Each is a complete self-contained block that:
  - opens with the reference-guide sentence from the icon Master (block head, straight non-tapering block arms, flat slab torso, NO hands/fingers; "Do not copy its colors, outfit, or pose");
  - specifies the Soul Festival dusk palette (violet #3B2A6E → amber #E8703A sky, cyan #6FE3FF soul energy, gold #FFB84D accents, near-white skin, faint wisps, one teal aurora ribbon, soft vignette);
  - for T1, describes the boy (orange hair, royal-blue hoodie w/ orange accents) and girl (pink ponytail, teal hoodie) with flat printed decal comic-surprise faces, and the cyan double-arrow ⇄ between/above their heads;
  - requests a **wide 16:9 landscape composition, filling the whole 16:9 canvas**, subject centered within the safe zone;
  - ends with: "No text, no letters, no numbers, no logos, no watermark, no border."
- **Per-frame variants** — for each Master, `V1` and `V2` each changing exactly ONE axis (e.g. T1: V1 camera distance, V2 background density; T2: V1 avatar count, V2 ring prominence; T3: V1 hazard type, V2 camera angle; T4: V1 lineup arrangement, V2 expression), full text written out for paste.
- **Failure-fixes** — reuse/adapt the icon kit's F-list as sentences to ADD before re-rolling: F1 off-model Roblox, F2 palette drift, F3 text/letters appear, F4 creepy/horror read, F5 not 16:9 / has border, F6 (T2/T4 only) avatars merge or wrong count, F7 (T3 only) reads as combat/violence → keep it environmental & comic.

- [ ] **Step 3: Verify structure and guards**

Run:
```bash
grep -c "No text, no letters, no numbers" docs/marketing/thumbnails/prompts.md
grep -nE "16:9|landscape" docs/marketing/thumbnails/prompts.md | head
grep -nE "^## |^### " docs/marketing/thumbnails/prompts.md
```
Expected: the no-text guard count ≥ 4 (one per Master, more with variants); 16:9/landscape appears in every Master; headings show four Masters + variants + failure-fixes.

- [ ] **Step 4: Commit**

```bash
git add docs/marketing/thumbnails/prompts.md
git commit -m "docs(thumbnails): add Gemini prompt kit (T1-T4 + variants + fixes)"
```

---

## Task 4: `finalize-thumbnail.ps1` — cover-crop any source to 1920×1080

**Files:**
- Create: `scripts/finalize-thumbnail.ps1`
- Test: `scripts/tests/test-finalize-thumbnail.ps1`

Cover-crop semantics: scale the source so it fully covers 1920×1080, then center-crop
the overflow (no letterbox bars). Sibling of `finalize-icon.ps1`; same HighQuality
interpolation.

- [ ] **Step 1: Write the failing test harness**

Write `scripts/tests/test-finalize-thumbnail.ps1`:

```powershell
# Verifies finalize-thumbnail.ps1 outputs exactly 1920x1080 from an off-ratio source.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$tmp = Join-Path $env:TEMP ("finthumb-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # synthesize a 1024x1024 square source (worst case for 16:9 crop)
    $src = Join-Path $tmp "src.png"
    $b = New-Object System.Drawing.Bitmap(1024, 1024)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.Clear([System.Drawing.Color]::Purple); $g.Dispose(); $b.Save($src); $b.Dispose()

    $out = Join-Path $tmp "out.png"
    & powershell -NoProfile -ExecutionPolicy Bypass -File scripts/finalize-thumbnail.ps1 -Source $src -Out $out
    if (-not (Test-Path $out)) { throw "FAIL: no output written" }
    $o = [System.Drawing.Image]::FromFile($out)
    try {
        if ($o.Width -ne 1920 -or $o.Height -ne 1080) { throw "FAIL: got $($o.Width)x$($o.Height), want 1920x1080" }
    } finally { $o.Dispose() }
    Write-Output "PASS: finalize-thumbnail produces 1920x1080"
} finally { Remove-Item -Recurse -Force $tmp }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/test-finalize-thumbnail.ps1
```
Expected: FAIL — the script `scripts/finalize-thumbnail.ps1` does not exist yet (error like "cannot find path").

- [ ] **Step 3: Write `scripts/finalize-thumbnail.ps1`**

```powershell
<#
Finalize a Thumbnail: cover-crop the source to 16:9 and scale to 1920x1080 PNG.
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/finalize-thumbnail.ps1 -Source candidates\gemini-t1-m-1.png -Out docs\marketing\thumbnails\final\thumb-1-1920.png
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Out = "docs/marketing/thumbnails/final/thumb-1-1920.png",
    [int]$Width = 1920,
    [int]$Height = 1080
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$srcPath = (Resolve-Path $Source).Path
$img = [System.Drawing.Image]::FromFile($srcPath)
$bmp = $null
try {
    # cover-crop: pick the largest source rect matching the target aspect, centered
    $targetAspect = $Width / $Height
    $srcAspect = $img.Width / $img.Height
    if ($srcAspect -gt $targetAspect) {
        # source too wide -> crop width
        $cropH = $img.Height
        $cropW = [int][Math]::Round($img.Height * $targetAspect)
    } else {
        # source too tall/square -> crop height
        $cropW = $img.Width
        $cropH = [int][Math]::Round($img.Width / $targetAspect)
    }
    $cropX = [int](($img.Width - $cropW) / 2)
    $cropY = [int](($img.Height - $cropH) / 2)

    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $srcRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $cropW, $cropH)
        $dstRect = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
        $g.DrawImage($img, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    } finally {
        $g.Dispose()
    }

    $outDir = Split-Path $Out -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    $outPath = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("Wrote {0} ({1}x{2}, cover-cropped from {3}x{4})" -f $Out, $Width, $Height, $img.Width, $img.Height)
} finally {
    if ($bmp) { $bmp.Dispose() }
    $img.Dispose()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/test-finalize-thumbnail.ps1
```
Expected: `PASS: finalize-thumbnail produces 1920x1080`

- [ ] **Step 5: Commit**

```bash
git add scripts/finalize-thumbnail.ps1 scripts/tests/test-finalize-thumbnail.ps1
git commit -m "feat(thumbnails): add finalize-thumbnail.ps1 (cover-crop to 1920x1080)"
```

---

## Task 5: `composite-caption.ps1` — draw a Fredoka caption band

**Files:**
- Create: `scripts/composite-caption.ps1`
- Test: `scripts/tests/test-composite-caption.ps1`

Draws a bottom band (upward dark gradient) and centered caption text on a 1920×1080
PNG. `-Highlight <word>` renders that word in gold #FFB84D, the rest white. Uses
Fredoka if installed, else falls back to Arial Black / any bold sans (never crash on
missing font). Output stays 1920×1080.

- [ ] **Step 1: Write the failing test harness**

Write `scripts/tests/test-composite-caption.ps1`:

```powershell
# Verifies composite-caption.ps1 keeps 1920x1080 and actually draws pixels in the band.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$tmp = Join-Path $env:TEMP ("capt-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $src = Join-Path $tmp "src.png"
    $b = New-Object System.Drawing.Bitmap(1920, 1080)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.Clear([System.Drawing.Color]::FromArgb(59,42,110)); $g.Dispose(); $b.Save($src); $b.Dispose()

    $out = Join-Path $tmp "out.png"
    & powershell -NoProfile -ExecutionPolicy Bypass -File scripts/composite-caption.ps1 -Source $src -Text "SWAPPED into their body" -Highlight "SWAPPED" -Out $out
    if (-not (Test-Path $out)) { throw "FAIL: no output written" }
    $o = [System.Drawing.Bitmap]::FromFile($out)
    try {
        if ($o.Width -ne 1920 -or $o.Height -ne 1080) { throw "FAIL: got $($o.Width)x$($o.Height)" }
        # scan the caption-band region (~83%-93% down) for near-white or gold text pixels.
        # Scanning a row range (not a single row) avoids landing in a gap between glyphs.
        $found = $false
        for ($y = [int](1080 * 0.83); $y -lt [int](1080 * 0.93) -and -not $found; $y += 4) {
            for ($x = 0; $x -lt 1920; $x += 3) {
                $p = $o.GetPixel($x, $y)
                if (($p.R -gt 200 -and $p.G -gt 200 -and $p.B -gt 200) -or ($p.R -gt 220 -and $p.G -gt 150 -and $p.B -lt 120)) { $found = $true; break }
            }
        }
        if (-not $found) { throw "FAIL: no caption text pixels found in band" }
    } finally { $o.Dispose() }
    Write-Output "PASS: composite-caption draws caption and keeps 1920x1080"
} finally { Remove-Item -Recurse -Force $tmp }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/test-composite-caption.ps1
```
Expected: FAIL — `scripts/composite-caption.ps1` does not exist yet.

- [ ] **Step 3: Write `scripts/composite-caption.ps1`**

```powershell
<#
Composite a caption band onto a 1920x1080 thumbnail.
- Draws an upward dark gradient band along the bottom, then centered caption text.
- -Highlight renders that one word in gold; the rest is white.
- Uses Fredoka if installed, else falls back to a bold sans; never crashes on missing font.
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/composite-caption.ps1 -Source thumb-1-1920.png -Text "SWAPPED into their body" -Highlight "SWAPPED" -Out thumb-1-1920.png
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Highlight = "",
    [string]$Out = "",
    [int]$FontSize = 96
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not $Out) { $Out = $Source }
$srcPath = (Resolve-Path $Source).Path
$img = [System.Drawing.Bitmap]::FromFile($srcPath)
$bmp = $null
try {
    $W = $img.Width; $H = $img.Height
    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.DrawImage($img, 0, 0, $W, $H)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

        # bottom gradient band (~26% of height)
        $bandH = [int]($H * 0.26)
        $bandRect = New-Object System.Drawing.Rectangle(0, ($H - $bandH), $W, $bandH)
        $c0 = [System.Drawing.Color]::FromArgb(0, 8, 3, 22)
        $c1 = [System.Drawing.Color]::FromArgb(235, 8, 3, 22)
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bandRect, $c0, $c1, 90)
        $g.FillRectangle($grad, $bandRect); $grad.Dispose()

        # pick font with graceful fallback
        $familyName = $null
        foreach ($fn in @("Fredoka", "Fredoka One", "Baloo 2", "Arial Black", "Segoe UI Black", "Arial")) {
            try { $test = New-Object System.Drawing.FontFamily($fn); $familyName = $fn; $test.Dispose(); break } catch {}
        }
        if (-not $familyName) { $familyName = [System.Drawing.FontFamily]::GenericSansSerif.Name }
        $font = New-Object System.Drawing.Font($familyName, $FontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $gold  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 184, 77))
        $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 10, 4, 26))

        # measure whole line, then draw word-by-word so -Highlight can recolor one word.
        # NOTE: loop var is $word (not $w) — PowerShell names are case-insensitive, so $w
        # would alias the image-width $W and clobber it.
        $words = $Text -split '\s+'
        $spaceW = $g.MeasureString(" ", $font).Width
        $totalW = 0.0
        foreach ($word in $words) { $totalW += $g.MeasureString($word, $font).Width + $spaceW }
        $totalW -= $spaceW
        $startX = ($W - $totalW) / 2
        $lineH = $g.MeasureString($Text, $font).Height
        $baselineY = $H - ($bandH / 2) - ($lineH / 2)

        $x = $startX
        foreach ($word in $words) {
            $wordW = $g.MeasureString($word, $font).Width
            $brush = if ($Highlight -and ($word.Trim(',','.','!') -ieq $Highlight)) { $gold } else { $white }
            $g.DrawString($word, $font, $shadow, ($x + 3), ($baselineY + 3))
            $g.DrawString($word, $font, $brush, $x, $baselineY)
            $x += $wordW + $spaceW
        }

        $white.Dispose(); $gold.Dispose(); $shadow.Dispose(); $font.Dispose()
    } finally {
        $g.Dispose()
    }

    $outPath = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("Wrote {0} (caption: '{1}', font: {2})" -f $Out, $Text, $familyName)
} finally {
    if ($bmp) { $bmp.Dispose() }
    $img.Dispose()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/test-composite-caption.ps1
```
Expected: `PASS: composite-caption draws caption and keeps 1920x1080`

- [ ] **Step 5: Commit**

```bash
git add scripts/composite-caption.ps1 scripts/tests/test-composite-caption.ps1
git commit -m "feat(thumbnails): add composite-caption.ps1 (Fredoka caption band)"
```

---

## Task 6: End-to-end dry run + memory update

**Files:**
- Modify: `<project-memory>/MEMORY.md`
- Create: `<project-memory>/experience-thumbnails-slice.md`

- [ ] **Step 1: Dry-run the full finalize chain on the reference image**

Run (proves both scripts chain without a real candidate yet):
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/finalize-thumbnail.ps1 -Source docs/marketing/thumbnails/reference/ref-avatar.png -Out "$TEMP/dryrun.png"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/composite-caption.ps1 -Source "$TEMP/dryrun.png" -Text "SWAPPED into their body" -Highlight "SWAPPED" -Out "$TEMP/dryrun.png"
```
Expected: both print "Wrote …"; no errors. (Output is throwaway — not committed.)

- [ ] **Step 2: Write the memory note**

Write `.../memory/experience-thumbnails-slice.md`:

```markdown
---
name: experience-thumbnails-slice
description: Thumbnails marketing slice — Swap Story 4-image set, kit + finalize tooling scaffolded 2026-07-12.
metadata:
  type: project
---

Body Swap Royale Experience **Thumbnails** (16:9 store carousel), branch `feat/experience-thumbnails`.
Set = "Swap Story" 4 images: (1) hero swap, (2) every-30s chaos, (3) survive the arena, (4) play with friends.
Captions are **composited in post** (Fredoka via `scripts/composite-caption.ps1`), prompts stay text-free.
Finalize = `scripts/finalize-thumbnail.ps1` (cover-crop → 1920×1080) then caption. Kit in `docs/marketing/thumbnails/prompts.md`.
Spec: `docs/specs/2026-07-12-experience-thumbnails-design.md`. Same brand family as [[experience-icon-phase-b]].
Remaining after scaffolding: user rolls T1–T4 in Gemini, we score/finalize, user uploads via Creator Dashboard.
```

- [ ] **Step 3: Add the MEMORY.md index line**

Add under the existing list in `.../memory/MEMORY.md`:
```markdown
- [Experience Thumbnails slice](experience-thumbnails-slice.md) — Swap Story 4-image set; captions composited in post; finalize-thumbnail.ps1 + composite-caption.ps1 tooling.
```

- [ ] **Step 4: Commit the repo-side plan/scaffolding state (memory dir is outside the repo, not committed)**

Run:
```bash
git status --short
```
Expected: only intended thumbnail/script files are tracked; `src/shared/Config.luau` still shows ` M` and is NOT staged. Nothing to commit here if Tasks 1–5 already committed; this step is a final guard.

---

## Self-review notes

- **Spec coverage:** §5.1 folder → Task 1/2; §4+§5 prompt kit → Task 3; §5.4b finalize → Task 4; §4 caption composite → Task 5; §7 deliverables all covered; §8 risks (font fallback → Task 5 fallback chain; 16:9 crop → Task 4 cover-crop; hazard-not-combat → Task 3 T3 wording + F7). 
- **Config.luau guard** repeated in header + Task 6.
- **Naming consistency:** `gemini-t{frame}-{variant}-{roll}.png`, `thumb-{n}-1920.png`, `finalize-thumbnail.ps1`, `composite-caption.ps1`, `-Highlight` param — used identically across README, prompts, scripts, and tests.

## Post-implementation notes (fixes found during review / end-to-end verify)

The committed scripts are the source of truth; they evolved past the code blocks above during the two-stage review and a real-flow render. Changes applied:

1. **`$w`/`$W` collision (caption):** PowerShell variable names are case-insensitive, so the `foreach ($w in $words)` loop aliased image-width `$W`. Renamed the loop var to `$word` / `$wordW`.
2. **GDI+ file-lock on in-place `-Out` (caption, Critical):** `Image.FromFile` locks the source, so the documented `-Out == -Source` usage threw on `Save`. Now dispose `$img` immediately after `DrawImage` (and guard the trailing `finally` with `if ($img)`).
3. **Caption width overflow (caption, found by rendering the real flow):** a fixed 96px font ran "SWAPPED into their body" off both edges. Added auto-fit — shrink the font proportionally until the line fits `$W * 0.90`.
4. **Highlight robustness (caption):** strip leading/trailing punctuation before matching `-Highlight`, and `Write-Warning` if it matches no word.
5. **Test coverage:** caption test now scans a band ROW RANGE (not one fragile row), asserts no text bleeds into the outer 4% safe margin, and exercises the in-place `-Out` path; finalize test now also exercises the crop-width branch with a 2560×1080 source.

Final commits: `dea0885` (lock + highlight + test gaps), `dda6a15` (auto-fit + margin guard).
