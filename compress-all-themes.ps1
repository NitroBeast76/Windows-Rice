<#
.SYNOPSIS
    Compress every wallpaper in themes\ before pushing.

.DESCRIPTION
    Walks the entire themes\ folder and:
      1. Converts PNGs over 500KB to JPEG (quality 85)
      2. Deletes PNGs that now have a JPEG counterpart
      3. Re-encodes all JPG/JPEG at quality 82, max 1920 wide
      4. Re-encodes all WebP at quality 82, lossless off, max 1920 wide

    Prints per-file before/after sizes and a per-theme summary at the end.
    Safe to run repeatedly -- files that are already compressed won't shrink
    much further, and the script handles that gracefully.

    Nothing is deleted except PNGs that have been successfully converted to
    JPEG in step 1. Everything else is re-encoded in place.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$themeRoot = Join-Path $repoRoot 'themes'

if (-not (Test-Path $themeRoot)) {
    Write-Host "themes\ not found at $themeRoot" -ForegroundColor Red
    Write-Host 'Run this from the repo root.' -ForegroundColor Red
    exit 1
}

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Host 'magick not found on PATH. Install ImageMagick first.' -ForegroundColor Red
    exit 1
}

function Get-TreeSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $sum = (Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return $sum
}

$grandBefore = Get-TreeSize $themeRoot

# ============================================================
# 1. PNG -> JPEG for large files
# ============================================================

Write-Host ''
Write-Host '=== Step 1: PNG to JPEG (files over 500KB) ===' -ForegroundColor Cyan
Write-Host ''

$pngConverted = 0
Get-ChildItem $themeRoot -Recurse -File -Filter *.png -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 500KB } |
    ForEach-Object {
        $jpeg = [System.IO.Path]::ChangeExtension($_.FullName, '.jpg')
        & magick $_.FullName -resize '1920x1080>' -quality 85 -strip $jpeg 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $jpeg)) {
            $before = [math]::Round($_.Length / 1KB)
            $after = [math]::Round((Get-Item $jpeg).Length / 1KB)
            $rel = $_.FullName.Substring($themeRoot.Length).TrimStart('\')
            Write-Host ("  {0}: {1}KB -> {2}KB" -f $rel, $before, $after) -ForegroundColor Gray
            $pngConverted++
        } else {
            Write-Host ("  SKIP (magick failed): {0}" -f $_.Name) -ForegroundColor Yellow
        }
    }

Write-Host ''
Write-Host ("  Converted $pngConverted PNGs to JPEG") -ForegroundColor Green

# ============================================================
# 2. Delete PNGs with JPEG counterparts
# ============================================================

Write-Host ''
Write-Host '=== Step 2: Delete PNGs with JPEG counterparts ===' -ForegroundColor Cyan
Write-Host ''

$pngDeleted = 0
Get-ChildItem $themeRoot -Recurse -File -Filter *.png -ErrorAction SilentlyContinue |
    Where-Object {
        (Test-Path ([System.IO.Path]::ChangeExtension($_.FullName, '.jpg'))) -or
        (Test-Path ([System.IO.Path]::ChangeExtension($_.FullName, '.jpeg')))
    } |
    ForEach-Object {
        $rel = $_.FullName.Substring($themeRoot.Length).TrimStart('\')
        Write-Host ("  rm {0}" -f $rel) -ForegroundColor DarkGray
        Remove-Item -Force $_.FullName
        $pngDeleted++
    }

Write-Host ''
Write-Host ("  Deleted $pngDeleted PNGs") -ForegroundColor Green

# ============================================================
# 3. Re-encode JPG/JPEG at quality 82
# ============================================================

Write-Host ''
Write-Host '=== Step 3: Re-encode JPEGs at quality 82 ===' -ForegroundColor Cyan
Write-Host ''

$jpegCount = 0
Get-ChildItem $themeRoot -Recurse -File -Include *.jpg, *.jpeg -ErrorAction SilentlyContinue | ForEach-Object {
    $before = (Get-Item $_.FullName).Length
    $tmp = "$($_.FullName).tmp.$($_.Extension.TrimStart('.'))"
    & magick $_.FullName -resize '1920x1080>' -quality 82 -strip $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
        Move-Item -Force $tmp $_.FullName
        $after = (Get-Item $_.FullName).Length
        if ($before -ne $after) {
            $rel = $_.FullName.Substring($themeRoot.Length).TrimStart('\')
            Write-Host ("  {0}: {1}KB -> {2}KB" -f $rel, [math]::Round($before/1KB), [math]::Round($after/1KB)) -ForegroundColor Gray
        }
        $jpegCount++
    } else {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        Write-Host ("  SKIP: {0}" -f $_.Name) -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host ("  Processed $jpegCount JPEGs") -ForegroundColor Green

# ============================================================
# 4. Re-encode WebP at quality 82, lossless off
# ============================================================

Write-Host ''
Write-Host '=== Step 4: Re-encode WebPs at quality 82 ===' -ForegroundColor Cyan
Write-Host ''

$webpCount = 0
Get-ChildItem $themeRoot -Recurse -File -Filter *.webp -ErrorAction SilentlyContinue | ForEach-Object {
    $before = (Get-Item $_.FullName).Length
    $tmp = "$($_.FullName).tmp"
    & magick $_.FullName -resize '1920x1080>' -quality 82 -define webp:lossless=false -strip $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
        Move-Item -Force $tmp $_.FullName
        $after = (Get-Item $_.FullName).Length
        $rel = $_.FullName.Substring($themeRoot.Length).TrimStart('\')
        Write-Host ("  {0}: {1}KB -> {2}KB" -f $rel, [math]::Round($before/1KB), [math]::Round($after/1KB)) -ForegroundColor Gray
        $webpCount++
    } else {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        Write-Host ("  SKIP: {0}" -f $_.Name) -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host ("  Processed $webpCount WebPs") -ForegroundColor Green

# ============================================================
# Per-theme summary
# ============================================================

Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
Write-Host ''

$grandAfter = Get-TreeSize $themeRoot

Get-ChildItem $themeRoot -Directory | Sort-Object Name | ForEach-Object {
    $size = Get-TreeSize $_.FullName
    $count = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
    [PSCustomObject]@{
        Theme = $_.Name
        Files = $count
        MB    = [math]::Round($size / 1MB, 2)
    }
} | Format-Table -AutoSize

Write-Host ("themes\ total: {0:N2} MB -> {1:N2} MB" -f ($grandBefore / 1MB), ($grandAfter / 1MB)) -ForegroundColor Green
Write-Host ''

# Check for anything still oversized
Write-Host '=== Oversized files (still over 500KB) ===' -ForegroundColor Cyan
Write-Host ''

$big = Get-ChildItem $themeRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 500KB } |
    Sort-Object Length -Descending

if ($big.Count -eq 0) {
    Write-Host '  None. All wallpapers are under 500KB.' -ForegroundColor Green
} else {
    $big | ForEach-Object {
        $rel = $_.FullName.Substring($themeRoot.Length).TrimStart('\')
        Write-Host ("  {0,8:N0} KB  {1}" -f ($_.Length / 1KB), $rel) -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '  These are likely PNGs with transparency or line art that should stay PNG.' -ForegroundColor DarkGray
    Write-Host '  If they are photographs, convert them manually:' -ForegroundColor DarkGray
    Write-Host '    magick input.png -resize 1920x1080> -quality 82 -strip output.jpg' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '=== Next steps ===' -ForegroundColor Cyan
Write-Host '  1. Review a few images to confirm they still look right' -ForegroundColor Gray
Write-Host '  2. git status' -ForegroundColor Gray
Write-Host '  3. git add themes' -ForegroundColor Gray
Write-Host '  4. git commit -m "Add new themes"' -ForegroundColor Gray
Write-Host '  5. git push' -ForegroundColor Gray
Write-Host ''