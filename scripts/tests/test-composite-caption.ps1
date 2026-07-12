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
