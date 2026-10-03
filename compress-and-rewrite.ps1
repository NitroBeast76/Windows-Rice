<#
.SYNOPSIS
    Compress wallpapers/screenshots and rewrite git history to shrink the repo.
#>

$ErrorActionPreference = 'Stop'

function Write-Phase {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host ''
}

function Confirm-Phase {
    param([string]$Message)
    $answer = Read-Host "$Message [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host 'Aborted by user.' -ForegroundColor Yellow
        exit 0
    }
}

# ============================================================
# PHASE 1: Verify location and tooling
# ============================================================

Write-Phase 'Phase 1: Verification'

$repoRoot = (Get-Location).Path
if ($repoRoot -notmatch 'Windows-Rice') {
    Write-Host "Not in a Windows-Rice repo. Current: $repoRoot" -ForegroundColor Red
    exit 1
}
Write-Host "Repo root: $repoRoot" -ForegroundColor Gray

if (-not (Test-Path 'themes/rose-pine/wallpapers')) {
    Write-Host 'themes/rose-pine/wallpapers missing - this looks like the broken clone.' -ForegroundColor Red
    exit 1
}
$wpCount = (Get-ChildItem themes/rose-pine/wallpapers -File | Measure-Object).Count
if ($wpCount -lt 10) {
    Write-Host "themes/rose-pine/wallpapers has only $wpCount files - expected ~25." -ForegroundColor Red
    Write-Host 'This looks like the broken clone. Re-clone before running.' -ForegroundColor Red
    exit 1
}
Write-Host "rose-pine wallpapers: $wpCount files (looks like a fresh clone)" -ForegroundColor Green

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Host 'magick not found on PATH. Install ImageMagick first.' -ForegroundColor Red
    exit 1
}
Write-Host 'magick: OK' -ForegroundColor Green

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'git not found on PATH.' -ForegroundColor Red
    exit 1
}
Write-Host 'git: OK' -ForegroundColor Green

$pyCheck = & python -c "import git_filter_repo; print('ok')" 2>&1
if ($pyCheck -notmatch 'ok') {
    Write-Host 'python git_filter_repo module not available.' -ForegroundColor Red
    Write-Host 'Run: pip install git-filter-repo' -ForegroundColor Yellow
    exit 1
}
Write-Host 'git-filter-repo: OK' -ForegroundColor Green

$baseline = (Get-ChildItem -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host ("Working tree baseline: {0:N2} MB" -f $baseline) -ForegroundColor Gray

Write-Host ''
Confirm-Phase 'Proceed to compression?'

# ============================================================
# PHASE 2: Compress images
# ============================================================

Write-Phase 'Phase 2: Compressing images'

Write-Host '--- PNG to JPEG (large files only) ---' -ForegroundColor Gray
Get-ChildItem themes, assets -Recurse -File -Include *.png |
    Where-Object { $_.Length -gt 500KB } |
    ForEach-Object {
        $jpeg = [System.IO.Path]::ChangeExtension($_.FullName, '.jpg')
        & magick $_.FullName -resize '1920x1080>' -quality 85 -strip $jpeg 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $before = [math]::Round($_.Length/1KB)
            $after = [math]::Round((Get-Item $jpeg).Length/1KB)
            Write-Host ("  {0}: {1}KB -> {2}KB" -f $_.Name, $before, $after) -ForegroundColor DarkGray
        } else {
            Write-Host ("  SKIP: {0}" -f $_.Name) -ForegroundColor Yellow
        }
    }

Write-Host '--- Deleting PNGs with JPEG counterparts ---' -ForegroundColor Gray
Get-ChildItem themes, assets -Recurse -File -Include *.png | Where-Object {
    (Test-Path ([System.IO.Path]::ChangeExtension($_.FullName, '.jpg'))) -or
    (Test-Path ([System.IO.Path]::ChangeExtension($_.FullName, '.jpeg')))
} | ForEach-Object {
    Write-Host ("  rm {0}" -f $_.Name) -ForegroundColor DarkGray
    Remove-Item -Force $_.FullName
}

Write-Host '--- Re-resizing JPEGs at quality 82 ---' -ForegroundColor Gray
Get-ChildItem themes, assets -Recurse -File -Include *.jpg, *.jpeg | ForEach-Object {
    $before = (Get-Item $_.FullName).Length
    $tmp = "$($_.FullName).tmp.$($_.Extension.TrimStart('.'))"
    & magick $_.FullName -resize '1920x1080>' -quality 82 -strip $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
        Move-Item -Force $tmp $_.FullName
        $after = (Get-Item $_.FullName).Length
        if ($before -ne $after) {
            Write-Host ("  {0}: {1}KB -> {2}KB" -f $_.Name, [math]::Round($before/1KB), [math]::Round($after/1KB)) -ForegroundColor DarkGray
        }
    } else {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        Write-Host ("  SKIP: {0}" -f $_.Name) -ForegroundColor Yellow
    }
}

Write-Host '--- Resizing WebPs ---' -ForegroundColor Gray
Get-ChildItem themes, assets -Recurse -File -Include *.webp | ForEach-Object {
    $before = (Get-Item $_.FullName).Length
    $tmp = "$($_.FullName).tmp"
    & magick $_.FullName -resize '1920x1080>' -quality 82 -define webp:lossless=false -strip $tmp 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
        Move-Item -Force $tmp $_.FullName
        $after = (Get-Item $_.FullName).Length
        Write-Host ("  {0}: {1}KB -> {2}KB" -f $_.Name, [math]::Round($before/1KB), [math]::Round($after/1KB)) -ForegroundColor DarkGray
    } else {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        Write-Host ("  SKIP: {0}" -f $_.Name) -ForegroundColor Yellow
    }
}

Write-Host '--- Screenshots: PNG to WebP ---' -ForegroundColor Gray
if (Test-Path assets\screenshots) {
    Get-ChildItem assets\screenshots -Recurse -File -Include *.png | ForEach-Object {
        $webp = [System.IO.Path]::ChangeExtension($_.FullName, '.webp')
        & magick $_.FullName -resize '1600x900>' -quality 90 -define webp:lossless=false -strip $webp 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host ("  {0} -> {1}: {2}KB -> {3}KB" -f $_.Name, (Split-Path $webp -Leaf), [math]::Round($_.Length/1KB), [math]::Round((Get-Item $webp).Length/1KB)) -ForegroundColor DarkGray
        }
    }
    Get-ChildItem assets\screenshots -Recurse -File -Include *.png | Where-Object {
        Test-Path ([System.IO.Path]::ChangeExtension($_.FullName, '.webp'))
    } | Remove-Item -Force
}

Write-Host '--- Updating README image references ---' -ForegroundColor Gray
if (Test-Path README.md) {
    (Get-Content README.md -Raw) -replace 'assets/screenshots/([^)]+)\.png', 'assets/screenshots/$1.webp' |
        Set-Content README.md -NoNewline
}

$compressed = (Get-ChildItem -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host ''
Write-Host ("Working tree: {0:N2} MB -> {1:N2} MB" -f $baseline, $compressed) -ForegroundColor Green

Write-Host ''
Confirm-Phase 'Proceed to commit?'

# ============================================================
# PHASE 3: Commit compression
# ============================================================

Write-Phase 'Phase 3: Committing compression'

git add -A
git commit -m "Compress wallpapers and screenshots"
if ($LASTEXITCODE -ne 0) {
    Write-Host 'git commit failed.' -ForegroundColor Red
    exit 1
}

Write-Host ''
git log --oneline | Select-Object -First 3

Write-Host ''
Confirm-Phase 'Proceed to backup?'

# ============================================================
# PHASE 4: Back up outside the repo
# ============================================================

Write-Phase 'Phase 4: Backing up wallpapers and screenshots'

$themesBackup = Join-Path $env:TEMP 'themes-backup'
$assetsBackup = Join-Path $env:TEMP 'assets-backup'

if (Test-Path $themesBackup) { Remove-Item $themesBackup -Recurse -Force }
if (Test-Path $assetsBackup) { Remove-Item $assetsBackup -Recurse -Force }

Copy-Item themes $themesBackup -Recurse -Force
Copy-Item assets $assetsBackup -Recurse -Force

$themesCount = (Get-ChildItem $themesBackup -Recurse -File | Measure-Object).Count
$assetsCount = (Get-ChildItem $assetsBackup -Recurse -File | Measure-Object).Count

if ($themesCount -eq 0 -or $assetsCount -eq 0) {
    Write-Host 'Backup verification failed - one or both backups are empty.' -ForegroundColor Red
    exit 1
}

Write-Host "Themes backup: $themesBackup ($themesCount files)" -ForegroundColor Green
Write-Host "Assets backup: $assetsBackup ($assetsCount files)" -ForegroundColor Green

Write-Host ''
Write-Host 'If anything goes wrong from here, your files are in those folders.' -ForegroundColor Yellow
Write-Host ''
Confirm-Phase 'Proceed to HISTORY REWRITE? (this is the destructive one)'

# ============================================================
# PHASE 5: Rewrite git history
# ============================================================

Write-Phase 'Phase 5: Rewriting git history'

python -m git_filter_repo `
    --path-glob "themes/*/wallpapers/*" `
    --path-glob "assets/wallpapers/*" `
    --path-glob "assets/screenshots/*" `
    --invert-paths --force

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host 'filter-repo failed. Do not proceed.' -ForegroundColor Red
    Write-Host "Recovery: files are in $themesBackup and $assetsBackup" -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host 'History rewritten. Working tree wallpapers/screenshots were removed by filter-repo.' -ForegroundColor Yellow
Write-Host 'Restoring them from backup now...' -ForegroundColor Yellow

# ============================================================
# PHASE 6: Restore from backup
# ============================================================

Write-Phase 'Phase 6: Restoring files from backup'

Remove-Item themes, assets -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $themesBackup themes -Recurse
Copy-Item $assetsBackup assets -Recurse

$restoredThemes = (Get-ChildItem themes -Recurse -File | Measure-Object).Count
$restoredAssets = (Get-ChildItem assets -Recurse -File | Measure-Object).Count

if ($restoredThemes -eq 0 -or $restoredAssets -eq 0) {
    Write-Host 'Restore failed.' -ForegroundColor Red
    Write-Host "Manually copy from $themesBackup and $assetsBackup" -ForegroundColor Yellow
    exit 1
}

Write-Host "Restored themes: $restoredThemes files" -ForegroundColor Green
Write-Host "Restored assets: $restoredAssets files" -ForegroundColor Green

Write-Host ''
Confirm-Phase 'Proceed to push?'

# ============================================================
# PHASE 7: Re-add origin, commit, push
# ============================================================

Write-Phase 'Phase 7: Pushing rewritten history'

$remotes = git remote
if ($remotes -notmatch 'origin') {
    git remote add origin https://github.com/NitroBeast76/Windows-Rice.git
    Write-Host 'Re-added origin remote.' -ForegroundColor Gray
}

git add themes assets README.md
git commit -m "Add compressed wallpaper and screenshot sets"
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Commit failed. Nothing to push?' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Ready to force-push. This rewrites GitHub history.' -ForegroundColor Yellow
Write-Host 'Anyone else with a clone will need to re-clone.' -ForegroundColor Yellow
Write-Host ''
Confirm-Phase 'Force-push to origin/main?'

git push --force

if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host 'Push failed.' -ForegroundColor Red
    Write-Host "Files are safe in $themesBackup and $assetsBackup" -ForegroundColor Yellow
    exit 1
}

# ============================================================
# VERIFICATION
# ============================================================

Write-Phase 'Verification'

$gitSize = (Get-ChildItem -Recurse -File .git |
    Measure-Object -Property Length -Sum).Sum / 1MB
$treeSize = (Get-ChildItem -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } |
    Measure-Object -Property Length -Sum).Sum / 1MB

Write-Host ("Working tree: {0:N2} MB" -f $treeSize) -ForegroundColor Green
Write-Host ("Git folder:   {0:N2} MB" -f $gitSize) -ForegroundColor Green

if ($gitSize -gt 50) {
    Write-Host ''
    Write-Host 'Git folder still larger than expected (~30MB target).' -ForegroundColor Yellow
    Write-Host 'Try: git gc --prune=now --aggressive' -ForegroundColor Yellow
} else {
    Write-Host ''
    Write-Host 'Repo is now small enough to clone quickly.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  1. Open the repo on GitHub and verify the README renders.' -ForegroundColor Gray
Write-Host '  2. Clone to a temp folder as a sanity check.' -ForegroundColor Gray
Write-Host '  3. Delete the broken clone at ~\Projects\Windows-Rice' -ForegroundColor Gray
Write-Host "  4. Delete backups: $themesBackup, $assetsBackup" -ForegroundColor Gray
Write-Host ''