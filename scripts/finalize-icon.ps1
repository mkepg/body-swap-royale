<#
Finalize the Experience Icon: center-crop to square, downscale to 512x512 PNG.
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/finalize-icon.ps1 -Source candidates\gemini-v2-1.png [-Out docs\marketing\experience-icon\final\icon-512.png]
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Out = "docs/marketing/experience-icon/final/icon-512.png",
    [int]$Size = 512
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$srcPath = (Resolve-Path $Source).Path
$img = [System.Drawing.Image]::FromFile($srcPath)
try {
    $side = [Math]::Min($img.Width, $img.Height)
    $cropX = [int](($img.Width - $side) / 2)
    $cropY = [int](($img.Height - $side) / 2)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $srcRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $side, $side)
        $dstRect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
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
    Write-Output ("Wrote {0} ({1}x{1}, cropped from {2}x{3})" -f $Out, $Size, $img.Width, $img.Height)
} finally {
    if ($bmp) { $bmp.Dispose() }
    $img.Dispose()
}
