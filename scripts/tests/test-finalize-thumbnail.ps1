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
