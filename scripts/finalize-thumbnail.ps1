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
