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
        $img.Dispose(); $img = $null   # release the source file lock so in-place -Out can Save
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

        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $gold  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 184, 77))
        $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 10, 4, 26))

        # Pick a font size that fits the caption within the horizontal safe zone (~90% width),
        # then measure. NOTE: loop var is $word (not $w) — PowerShell var names are
        # case-insensitive, so $w would alias the image-width $W and clobber it.
        $maxTextW = $W * 0.90
        $words = $Text -split '\s+'
        $size = $FontSize
        $font = New-Object System.Drawing.Font($familyName, $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $spaceW = $g.MeasureString(" ", $font).Width
        $totalW = 0.0
        foreach ($word in $words) { $totalW += $g.MeasureString($word, $font).Width + $spaceW }
        $totalW -= $spaceW
        if ($totalW -gt $maxTextW) {
            $size = [Math]::Max(24, [int]($size * ($maxTextW / $totalW)))
            $font.Dispose()
            $font = New-Object System.Drawing.Font($familyName, $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $spaceW = $g.MeasureString(" ", $font).Width
            $totalW = 0.0
            foreach ($word in $words) { $totalW += $g.MeasureString($word, $font).Width + $spaceW }
            $totalW -= $spaceW
        }
        $startX = ($W - $totalW) / 2
        $lineH = $g.MeasureString($Text, $font).Height
        $baselineY = $H - ($bandH / 2) - ($lineH / 2)

        $x = $startX
        $matchedHighlight = $false
        foreach ($word in $words) {
            $wordW = $g.MeasureString($word, $font).Width
            $bare = $word -replace '^[^\w]+|[^\w]+$', ''   # strip leading/trailing punctuation before matching
            $isHighlight = $Highlight -and ($bare -ieq $Highlight)
            if ($isHighlight) { $matchedHighlight = $true }
            $brush = if ($isHighlight) { $gold } else { $white }
            $g.DrawString($word, $font, $shadow, ($x + 3), ($baselineY + 3))
            $g.DrawString($word, $font, $brush, $x, $baselineY)
            $x += $wordW + $spaceW
        }
        if ($Highlight -and -not $matchedHighlight) {
            Write-Warning ("Highlight word '{0}' did not match any word in the caption; nothing drawn in gold." -f $Highlight)
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
    if ($img) { $img.Dispose() }
}
