<#
.SYNOPSIS
    Scaffold one or more new theme folders matching the existing theme structure.

.DESCRIPTION
    Creates themes\<name>\ with the same folder layout every existing theme uses:
        cava\config
        chronoterm\config.toml
        fastfetch\ascii.txt
        fastfetch\config.jsonc
        glazewm\default_glazewm_config.yaml
        starship\starship.toml
        terminal\settings.json
        yasb\default_yasb_config.yaml
        yasb\styles.css
        wallpapers\   (empty, you drop files in)

    Each file is seeded from configs\ (the base/mocha versions). You then edit
    them to match the theme's palette.

.PARAMETER Names
    One or more theme names. Each becomes a folder under themes\.

.EXAMPLE
    .\scaffold-theme.ps1 -Names gruvbox, nord, dracula, tokyo-night, catppuccin-latte
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string[]]$Names
)

$ErrorActionPreference = 'Stop'

$repoRoot  = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$configDir = Join-Path $repoRoot 'configs'
$themeRoot = Join-Path $repoRoot 'themes'

if (-not (Test-Path $configDir)) {
    Write-Host "configs\ not found at $configDir" -ForegroundColor Red
    exit 1
}

# The full file layout every existing theme has. Order matches the tree.
$fileSlots = @(
    'cava\config',
    'chronoterm\config.toml',
    'fastfetch\ascii.txt',
    'fastfetch\config.jsonc',
    'glazewm\default_glazewm_config.yaml',
    'starship\starship.toml',
    'terminal\settings.json',
    'yasb\default_yasb_config.yaml',
    'yasb\styles.css'
)

foreach ($name in $Names) {
    Write-Host ''
    Write-Host "=== $name ===" -ForegroundColor Cyan

    $themeDir = Join-Path $themeRoot $name

    if (Test-Path $themeDir) {
        Write-Host "  already exists, skipping" -ForegroundColor Yellow
        continue
    }

    New-Item -ItemType Directory -Path $themeDir -Force | Out-Null

    foreach ($rel in $fileSlots) {
        $src = Join-Path $configDir $rel
        $dst = Join-Path $themeDir $rel

        if (-not (Test-Path $src)) {
            Write-Host "  MISSING in configs: $rel" -ForegroundColor Red
            continue
        }

        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Host "  seeded $rel" -ForegroundColor Gray
    }

    # Empty wallpapers folder
    $wpDir = Join-Path $themeDir 'wallpapers'
    New-Item -ItemType Directory -Path $wpDir -Force | Out-Null
    Write-Host "  created wallpapers\  (drop default.* and gallery files here)" -ForegroundColor DarkGray

    Write-Host "  done: $themeDir" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Next steps for each theme:' -ForegroundColor Cyan
Write-Host '  1. Drop wallpapers into themes\<name>\wallpapers\' -ForegroundColor Gray
Write-Host '     - at least one named default.* (jpg/png/webp)' -ForegroundColor DarkGray
Write-Host '  2. Edit yasb\styles.css      -> replace colors with the theme palette' -ForegroundColor Gray
Write-Host '  3. Edit starship\starship.toml -> set palette = "<name>" and add the palette block' -ForegroundColor Gray
Write-Host '  4. Edit terminal\settings.json -> point to the theme color scheme' -ForegroundColor Gray
Write-Host '  5. Edit chronoterm\config.toml -> update the accent color' -ForegroundColor Gray
Write-Host '  6. Edit fastfetch\ascii.txt   -> optional, only if the logo differs' -ForegroundColor Gray
Write-Host '  7. Edit cava\config          -> optional, only if the gradient differs' -ForegroundColor Gray
Write-Host '  8. Edit glazewm\...yaml      -> optional, only if layout differs' -ForegroundColor Gray
Write-Host '  9. Edit fastfetch\config.jsonc -> optional, only if modules differ' -ForegroundColor Gray
Write-Host ' 10. Edit yasb\default_yasb_config.yaml -> optional, only if layout differs' -ForegroundColor Gray
Write-Host ''
Write-Host 'Files 6-10 ship as identical copies of the base. Delete them if the theme does not need them.' -ForegroundColor DarkGray
Write-Host ''