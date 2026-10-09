<#
.SYNOPSIS
    Windows-Rice TUI.

.DESCRIPTION
    Menu-driven front-end for install.ps1 and uninstall.ps1. Reads state
    from the manifest, dispatches to the appropriate script as a child
    process, and returns to the menu after each action.

    Deliberately minimal: no business logic, no git commands of its own
    (except calling install.ps1 -Update), no dependencies beyond what
    Windows ships with.

    Compatible with PowerShell 5.1 and 7+. ASCII output only.

.NOTES
    First-time use: run this from the repo root with .\rice.ps1.
    After install.ps1 has run once, the win-rice shim can be created to
    launch this from any shell.
#>

#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ============================================================ INITIALIZATION

$RepoRoot        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ThemeRoot       = Join-Path $RepoRoot 'themes'
$ConfigRoot      = Join-Path $RepoRoot 'configs'
$InstallScript   = Join-Path $RepoRoot 'install.ps1'
$UninstallScript = Join-Path $RepoRoot 'uninstall.ps1'
$HomeDir         = $env:USERPROFILE
$BackupRoot      = Join-Path $HomeDir '.windows-rice-backup'
$ManifestPath    = Join-Path $BackupRoot 'manifest.json'

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

# ================================================================== HELPERS

function Write-Header {
    param([string]$Title)
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * ($Title.Length))) -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-Hint {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [!] $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "  [x] $Text" -ForegroundColor Red
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  [ok] $Text" -ForegroundColor Green
}

function Read-Choice {
    param([string]$Prompt = 'Choice')
    Write-Host ''
    Write-Host "  $Prompt (or 0 to cancel): " -NoNewline -ForegroundColor Gray
    return (Read-Host).Trim()
}

function Confirm-Yes {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    Write-Host ''
    Write-Host "  $Prompt $suffix " -NoNewline -ForegroundColor Gray
    $answer = (Read-Host).Trim()
    if ([string]::IsNullOrEmpty($answer)) { return $Default }
    return ($answer -match '^(y|yes)$')
}

function Wait-ForEnter {
    Write-Host ''
    Write-Host '  Press Enter to return to the menu...' -ForegroundColor DarkGray
    [void](Read-Host)
}

# ========================================================== REPO LAYOUT CHECK

function Assert-RepoLayout {
    $missing = @()
    if (-not (Test-Path -LiteralPath $InstallScript))   { $missing += 'install.ps1' }
    if (-not (Test-Path -LiteralPath $UninstallScript)) { $missing += 'uninstall.ps1' }
    if (-not (Test-Path -LiteralPath $ThemeRoot))       { $missing += 'themes\' }
    if (-not (Test-Path -LiteralPath $ConfigRoot))      { $missing += 'configs\' }

    if ($missing.Count -gt 0) {
        Write-Host ''
        Write-Err 'Repository is incomplete. Missing:'
        foreach ($m in $missing) { Write-Host "        - $m" -ForegroundColor Red }
        Write-Host ''
        Write-Hint 'Run this from the repo root, or re-clone:'
        Write-Host '        git clone https://github.com/NitroBeast76/Windows-Rice.git' -ForegroundColor Gray
        Write-Host ''
        exit 1
    }
}

# =========================================================== STATE FROM DISK

function Get-RiceState {
    $state = [PSCustomObject]@{
        Installed   = $false
        Theme       = ''
        LastUpdated = ''
        ManifestOk  = $true
    }

    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $state }

    try {
        $raw  = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $state.ManifestOk = $false
        return $state
    }

    $state.Installed = $true

    if ($json.preferences -and $json.preferences.theme) {
        $state.Theme = $json.preferences.theme
    }
    if (-not $state.Theme) { $state.Theme = 'mocha' }

    if ($json.updated) {
        try {
            $dt = [datetime]::Parse($json.updated).ToLocalTime()
            $state.LastUpdated = $dt.ToString('yyyy-MM-dd HH:mm')
        } catch {
            $state.LastUpdated = $json.updated
        }
    }

    return $state
}

# ============================================================ THEME HELPERS

function Get-ThemeDescription {
    param([string]$Name)

    $map = @{
        'mocha'       = 'Catppuccin Mocha (default)'
        'ayu-dark'    = 'Deep navy, orange accents'
        'dracula'     = 'Purple and pink on near-black'
        'everforest'  = 'Muted greens, feels like a cabin'
        'gruvbox'     = 'Retro warm browns and oranges'
        'kanagawa'    = 'Hokusai colors, blue and gold'
        'monochrome'  = 'Black and white, semantic collapse'
        'nord'        = 'Cool arctic blues and greys'
        'rose-pine'   = 'Soft purples and pinks'
        'tokyo-night' = 'Neon blue-purple with cyan'
    }
    if ($map.ContainsKey($Name)) { return $map[$Name] }
    return ''
}

function Get-ThemeList {
    $themes = New-Object System.Collections.ArrayList

    [void]$themes.Add([PSCustomObject]@{
        Name        = 'mocha'
        Description = Get-ThemeDescription -Name 'mocha'
        IsBase      = $true
    })

    if (Test-Path -LiteralPath $ThemeRoot) {
        $dirs = @(Get-ChildItem -LiteralPath $ThemeRoot -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name)
        foreach ($d in $dirs) {
            [void]$themes.Add([PSCustomObject]@{
                Name        = $d.Name
                Description = Get-ThemeDescription -Name $d.Name
                IsBase      = $false
            })
        }
    }

    return $themes.ToArray()
}

# ==================================================== CHILD SCRIPT DISPATCH

function Get-PowerShellCommand {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) { return 'pwsh' }
    return 'powershell'
}

function Invoke-ChildScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ScriptArgs = @()
    )

    $shell = Get-PowerShellCommand

    Push-Location $RepoRoot
    try {
        & $shell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ScriptArgs
        return $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

# ================================================================== RENDERING

function Show-MainMenu {
    param([Parameter(Mandatory)]$State)

    Clear-Host
    Write-Host ''
    Write-Host '  Windows-Rice' -ForegroundColor Magenta
    Write-Host '  ============' -ForegroundColor Magenta
    Write-Host ''

    if (-not $State.ManifestOk -and (Test-Path -LiteralPath $ManifestPath)) {
        Write-Warn 'Manifest exists but could not be read. Treating as not installed.'
        Write-Host ''
    }

    if ($State.Installed) {
        Write-Host "  Current theme: $($State.Theme)" -ForegroundColor Gray
        if ($State.LastUpdated) {
            Write-Host "  Last updated:  $($State.LastUpdated)" -ForegroundColor Gray
        }
        Write-Host ''
        Write-Host '  1  Change theme'        -ForegroundColor White
        Write-Host '  2  Update'              -ForegroundColor White
        Write-Host '  3  Status'              -ForegroundColor White
        Write-Host '  4  Create a new theme'  -ForegroundColor White
        Write-Host '  5  Uninstall'           -ForegroundColor White
        Write-Host '  0  Exit'                -ForegroundColor DarkGray
    } else {
        Write-Host '  Ready to install for the first time.' -ForegroundColor Gray
        Write-Host ''
        Write-Host '  1  Install' -ForegroundColor White
        Write-Host '  0  Exit'    -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Show-ThemePicker {
    param(
        [Parameter(Mandatory)]$Themes,
        [string]$CurrentTheme = ''
    )

    Clear-Host
    Write-Host ''
    Write-Host '  Pick a theme' -ForegroundColor Cyan
    Write-Host '  ------------' -ForegroundColor Cyan
    Write-Host ''

    $i = 1
    foreach ($t in $Themes) {
        $marker = ''
        if ($CurrentTheme -and $t.Name -eq $CurrentTheme) { $marker = ' (current)' }

        Write-Host ("  {0,3}  {1,-14}  {2}{3}" -f $i, $t.Name, $t.Description, $marker) -ForegroundColor Gray
        $i++
    }

    Write-Host ''
    Write-Host '   0  Cancel' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Status {
    param([Parameter(Mandatory)]$State)

    Clear-Host
    Write-Host ''
    Write-Host '  Status' -ForegroundColor Cyan
    Write-Host '  ------' -ForegroundColor Cyan
    Write-Host ''

    if (-not $State.Installed) {
        Write-Host '  Not installed.' -ForegroundColor Yellow
        Write-Host ''
        Write-Hint 'Run "Install" from the main menu to set up Windows-Rice.'
        return
    }

    Write-Host ("  Theme:          {0}" -f $State.Theme) -ForegroundColor Gray
    if ($State.LastUpdated) {
        Write-Host ("  Last updated:   {0}" -f $State.LastUpdated) -ForegroundColor Gray
    }
    Write-Host ("  Backup root:    {0}" -f $BackupRoot) -ForegroundColor Gray
    Write-Host ("  Manifest:       {0}" -f $ManifestPath) -ForegroundColor Gray
    Write-Host ''

    $docsDir = [Environment]::GetFolderPath('MyDocuments')

    $paths = @(
        @{ Label = 'YASB config';        Path = (Join-Path $HomeDir '.config\yasb\config.yaml') }
        @{ Label = 'YASB styles';        Path = (Join-Path $HomeDir '.config\yasb\styles.css') }
        @{ Label = 'GlazeWM config';     Path = (Join-Path $HomeDir '.glzr\glazewm\config.yaml') }
        @{ Label = 'Cava config';        Path = (Join-Path $HomeDir '.config\cava\config') }
        @{ Label = 'Fastfetch config';   Path = (Join-Path $HomeDir '.config\fastfetch\config.jsonc') }
        @{ Label = 'Starship config';    Path = (Join-Path $HomeDir '.config\starship.toml') }
        @{ Label = 'PowerShell profile'; Path = (Join-Path $docsDir 'PowerShell\Microsoft.PowerShell_profile.ps1') }
    )

    Write-Host '  Deployed configs:' -ForegroundColor Cyan
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p.Path) {
            Write-Host ("    [ok]  {0}" -f $p.Label) -ForegroundColor Green
        } else {
            Write-Host ("    [ ]   {0}" -f $p.Label) -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Hint "Config paths resolved from the current user's home directory."
}

# ============================================================ ACTIONS

function Select-ThemeFromPicker {
    param(
        [Parameter(Mandatory)]$Themes,
        [string]$CurrentTheme = ''
    )

    Show-ThemePicker -Themes $Themes -CurrentTheme $CurrentTheme
    $choice = Read-Choice -Prompt 'Theme'
    if ($choice -eq '0' -or $choice -eq '') { return $null }

    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx)) {
        Write-Warn 'Not a number.'
        Start-Sleep -Seconds 1
        return $null
    }
    if ($idx -lt 1 -or $idx -gt $Themes.Count) {
        Write-Warn 'Out of range.'
        Start-Sleep -Seconds 1
        return $null
    }

    return $Themes[$idx - 1]
}

function Invoke-Install {
    $themes = Get-ThemeList
    $picked = Select-ThemeFromPicker -Themes $themes
    if ($null -eq $picked) { return }

    $theme = $picked.Name

    Clear-Host
    Write-Host ''
    Write-Host "  Installing Windows-Rice with theme: $theme" -ForegroundColor Cyan
    Write-Host ''
    Write-Warn 'Do not close this window until the installer finishes.'
    Write-Host ''

    $exit = Invoke-ChildScript -ScriptPath $InstallScript -ScriptArgs @('-Theme', $theme)

    Write-Host ''
    if ($exit -eq 0) {
        Write-Ok 'Install completed.'
    } else {
        Write-Err "Install exited with code $exit. Review the output above."
    }
    Wait-ForEnter
}

function Invoke-ChangeTheme {
    $state  = Get-RiceState
    $themes = Get-ThemeList

    $picked = Select-ThemeFromPicker -Themes $themes -CurrentTheme $state.Theme
    if ($null -eq $picked) { return }

    $theme = $picked.Name
    if ($theme -eq $state.Theme) {
        Write-Host ''
        Write-Host "  '$theme' is already the active theme." -ForegroundColor Gray
        Wait-ForEnter
        return
    }

    Clear-Host
    Write-Host ''
    Write-Host "  Switching theme to: $theme" -ForegroundColor Cyan
    Write-Host ''

    $exit = Invoke-ChildScript -ScriptPath $InstallScript `
                                -ScriptArgs @('-Theme', $theme, '-SkipPackages', '-SkipFonts')

    Write-Host ''
    if ($exit -eq 0) {
        Write-Ok 'Theme switched.'
    } else {
        Write-Err "Theme switch exited with code $exit."
    }
    Wait-ForEnter
}

function Invoke-Update {
    Clear-Host
    Write-Host ''
    Write-Host '  Updating Windows-Rice' -ForegroundColor Cyan
    Write-Host ''

    $exit = Invoke-ChildScript -ScriptPath $InstallScript `
                                -ScriptArgs @('-Update', '-SkipPackages', '-SkipFonts')

    Write-Host ''
    if ($exit -eq 0) {
        Write-Ok 'Update completed.'
    } else {
        Write-Err "Update exited with code $exit."
    }
    Wait-ForEnter
}

function Invoke-Status {
    $state = Get-RiceState
    Show-Status -State $state
    Wait-ForEnter
}

function Invoke-CreateTheme {
    $state  = Get-RiceState
    $themes = Get-ThemeList

    Clear-Host
    Write-Host ''
    Write-Host '  Create a new theme' -ForegroundColor Cyan
    Write-Host '  -----------------' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Start from:' -ForegroundColor Gray
    Write-Host ''

    $i = 1
    foreach ($t in $themes) {
        Write-Host ("  {0,3}  {1,-14}  {2}" -f $i, $t.Name, $t.Description) -ForegroundColor Gray
        $i++
    }
    Write-Host ''
    Write-Host '   0  Cancel' -ForegroundColor DarkGray
    Write-Host ''

    $choice = Read-Choice -Prompt 'Source theme'
    if ($choice -eq '0' -or $choice -eq '') { return }

    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $themes.Count) {
        Write-Warn 'Invalid selection.'
        Start-Sleep -Seconds 1
        return
    }

    $sourceInfo = $themes[$idx - 1]
    $source     = $sourceInfo.Name

    Write-Host ''
    Write-Host '  New theme name (lowercase letters, digits, hyphens, underscores):' -ForegroundColor Gray
    Write-Host '  > ' -NoNewline -ForegroundColor Gray
    $newName = (Read-Host).Trim()

    if ($newName -eq '') { return }

    if ($newName -notmatch '^[a-z][a-z0-9_-]{1,29}$') {
        Write-Host ''
        Write-Warn 'Invalid name. Use lowercase letters, digits, hyphens, underscores.'
        Write-Warn 'Must start with a letter, 2-30 characters.'
        Wait-ForEnter
        return
    }
    if ($newName -eq 'mocha') {
        Write-Host ''
        Write-Warn '"mocha" is reserved for the base configs.'
        Wait-ForEnter
        return
    }

    $newDir = Join-Path $ThemeRoot $newName
    if (Test-Path -LiteralPath $newDir) {
        Write-Host ''
        Write-Warn "A theme named '$newName' already exists."
        Wait-ForEnter
        return
    }

    if ($sourceInfo.IsBase) {
        $sourceDir          = $ConfigRoot
        $sourceWallpaperDir = Join-Path $RepoRoot 'assets\wallpapers'
    } else {
        $sourceDir          = Join-Path $ThemeRoot $source
        $sourceWallpaperDir = Join-Path $sourceDir 'wallpapers'
    }

    $copyWallpapers = $false
    if (Test-Path -LiteralPath $sourceWallpaperDir) {
        $wpFiles = @(Get-ChildItem -LiteralPath $sourceWallpaperDir -File -ErrorAction SilentlyContinue)
        if ($wpFiles.Count -gt 0) {
            $wpSizeMB = [math]::Round((($wpFiles | Measure-Object Length -Sum).Sum / 1MB), 1)
            $copyWallpapers = Confirm-Yes -Prompt "Copy $($wpFiles.Count) wallpapers from '$source' (~$wpSizeMB MB)?" -Default $false
        }
    }

    Write-Host ''
    Write-Host "  Creating themes\$newName\ from $source..." -ForegroundColor Gray

    try {
        New-Item -ItemType Directory -Path $newDir -Force | Out-Null

        Get-ChildItem -LiteralPath $sourceDir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'wallpapers' } |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $newDir -Recurse -Force
            }

        $newWallpaperDir = Join-Path $newDir 'wallpapers'
        New-Item -ItemType Directory -Path $newWallpaperDir -Force | Out-Null

        if ($copyWallpapers -and (Test-Path -LiteralPath $sourceWallpaperDir)) {
            Get-ChildItem -LiteralPath $sourceWallpaperDir -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Copy-Item -LiteralPath $_.FullName -Destination $newWallpaperDir -Force
                }
        }
    } catch {
        Write-Host ''
        Write-Err "Failed to create theme: $_"
        Wait-ForEnter
        return
    }

    Clear-Host
    Write-Host ''
    Write-Ok "Theme '$newName' created."
    Write-Host ''
    Write-Host '  Location:' -ForegroundColor Cyan
    Write-Host "    $newDir" -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Files to edit to make it distinct:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Colors (this is 90% of what makes a theme)' -ForegroundColor Yellow
    Write-Host '    yasb\styles.css              Bar colors, spacing, fonts. Start here.' -ForegroundColor Gray
    Write-Host "    starship\starship.toml       Set palette = ""$newName"" at the top," -ForegroundColor Gray
    Write-Host "                                 then add a [palettes.$newName] block" -ForegroundColor Gray
    Write-Host '    terminal\settings.json       Point to a Windows Terminal scheme' -ForegroundColor Gray
    Write-Host '    chronoterm\config.toml       Clock accent color' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Optional' -ForegroundColor Yellow
    Write-Host '    cava\config                  Visualizer gradient' -ForegroundColor Gray
    Write-Host '    fastfetch\ascii.txt          ASCII logo' -ForegroundColor Gray
    if ($copyWallpapers) {
        Write-Host '    wallpapers\                  Copied from source theme' -ForegroundColor Gray
    } else {
        Write-Host '    wallpapers\                  Empty. Add at least one file named' -ForegroundColor Gray
        Write-Host '                                 default.jpg (or .png / .webp) and the' -ForegroundColor Gray
        Write-Host '                                 installer will set it as your wallpaper.' -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host '  Rarely needs editing (structure, not palette)' -ForegroundColor DarkGray
    Write-Host '    glazewm\default_glazewm_config.yaml' -ForegroundColor DarkGray
    Write-Host '    fastfetch\config.jsonc' -ForegroundColor DarkGray
    Write-Host '    yasb\default_yasb_config.yaml' -ForegroundColor DarkGray
    Write-Host ''
    Write-Hint 'Tip: styles.css is the biggest file. Search for a color hex from the'
    Write-Hint 'source theme and replace each match with your own palette.'
    Write-Host ''
    Write-Hint 'When you are ready to use it, pick "Change theme" from the menu.'

    if (Confirm-Yes -Prompt 'Open the folder now?' -Default $false) {
        try {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $newDir | Out-Null
        } catch {
            Write-Warn "Could not open Explorer: $_"
        }
    }

    Wait-ForEnter
}

function Invoke-Uninstall {
    Clear-Host
    Write-Host ''
    Write-Host '  Uninstall Windows-Rice' -ForegroundColor Cyan
    Write-Host '  ---------------------' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  This restores your config files from backups and optionally' -ForegroundColor Gray
    Write-Host '  removes packages that this installer added.' -ForegroundColor Gray
    Write-Host ''

    if (-not (Confirm-Yes -Prompt 'Continue?' -Default $false)) { return }

    $removePackages = Confirm-Yes -Prompt 'Also remove packages the installer added?' -Default $false
    $purge          = Confirm-Yes -Prompt 'Also delete all backups and the manifest?' -Default $false

    $uninstallArgs = @()
    if ($removePackages) { $uninstallArgs += '-RemovePackages' }
    if ($purge)          { $uninstallArgs += '-Purge' }

    Clear-Host
    Write-Host ''
    Write-Host '  Uninstalling...' -ForegroundColor Cyan
    Write-Host ''

    $exit = Invoke-ChildScript -ScriptPath $UninstallScript -ScriptArgs $uninstallArgs

    Write-Host ''
    if ($exit -eq 0) {
        Write-Ok 'Uninstall completed.'
    } else {
        Write-Err "Uninstall exited with code $exit."
    }
    Wait-ForEnter
}

# ================================================================== MAIN LOOP

Assert-RepoLayout

while ($true) {
    $state = Get-RiceState
    Show-MainMenu -State $state

    Write-Host '  Choice: ' -NoNewline -ForegroundColor Gray
    $choice = (Read-Host).Trim()

    if ($state.Installed) {
        switch ($choice) {
            '0' { exit 0 }
            '1' { Invoke-ChangeTheme }
            '2' { Invoke-Update }
            '3' { Invoke-Status }
            '4' { Invoke-CreateTheme }
            '5' { Invoke-Uninstall }
        }
    } else {
        switch ($choice) {
            '0' { exit 0 }
            '1' { Invoke-Install }
        }
    }
}