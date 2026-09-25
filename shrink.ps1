# shrink.ps1
# Shrinks every JPG/JPEG/PNG in the repo. Caps width at 1920px, strips metadata.

$ErrorActionPreference = 'Stop'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Host 'ImageMagick (magick) is not on PATH.' -ForegroundColor Red
    Write-Host 'Install: winget install --id ImageMagick.ImageMagick --exact' -ForegroundColor Gray
    exit 1
}

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Write-Host "Scanning: $root"
Write-Host ''

$exts = @('.jpg', '.jpeg', '.png')
$files = Get-ChildItem -LiteralPath $root -File -Recurse |
         Where-Object { $exts -contains $_.Extension.ToLower() }

if ($files.Count -eq 0) {
    Write-Host 'No JPG or PNG files found.' -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($files.Count) image(s)."
Write-Host ''

$before = 0
$after  = 0
$ok     = 0
$fail   = 0

foreach ($f in $files) {
    $sizeBefore = $f.Length
    $before += $sizeBefore

    try {
        magick mogrify -resize 1920x -strip $f.FullName

        if ($LASTEXITCODE -ne 0) { throw "magick exited $LASTEXITCODE" }

        $sizeAfter = (Get-Item -LiteralPath $f.FullName).Length
        $after += $sizeAfter
        $ok += 1

        $kbBefore = [int]($sizeBefore / 1KB)
        $kbAfter  = [int]($sizeAfter / 1KB)
        Write-Host ("  OK  {0}  ({1} KB -> {2} KB)" -f $f.Name, $kbBefore, $kbAfter) -ForegroundColor Green
    } catch {
        $after += $sizeBefore
        $fail += 1
        Write-Host ("  FAIL  {0}  -  {1}" -f $f.Name, $_) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Done. Shrunk: $ok   Failed: $fail" -ForegroundColor Cyan
if ($before -gt 0) {
    $savedMb = [math]::Round(($before - $after) / 1MB, 1)
    $beforeMb = [math]::Round($before / 1MB, 1)
    $afterMb  = [math]::Round($after / 1MB, 1)
    Write-Host ("Total: {0} MB -> {1} MB   (saved {2} MB)" -f $beforeMb, $afterMb, $savedMb) -ForegroundColor Cyan
}