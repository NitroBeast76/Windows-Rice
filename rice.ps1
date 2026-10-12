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

$script:RiceVersion = '1.4'

$RepoRoot        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ThemeRoot       = Join-Path $RepoRoot 'themes'
$ConfigRoot      = Join-Path $RepoRoot 'configs'
$InstallScript   = Join-Path $RepoRoot 'install.ps1'
$UninstallScript = Join-Path $RepoRoot 'uninstall.ps1'
$HomeDir         = $env:USERPROFILE
$BackupRoot      = Join-Path $HomeDir '.windows-rice-backup'
$ManifestPath    = Join-Path $BackupRoot 'manifest.json'
$LauncherPath    = Join-Path $HomeDir '.local\bin\win-rice.cmd'

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

# ================================================================== LOGGING

$script:BoxWidth = 56

function Write-Banner {
    <#
        Block art spells WINDOWS (figlet ansi_shadow, 58 cols). RICE is a
        right-aligned accent line beneath, colored Cyan to match section
        labels. Below that, a magenta rule and a one-line tagline.

        Kept identical to install.ps1's banner so the two scripts read as
        parts of one product rather than two unrelated tools.
    #>
    $art = @(
        '██╗    ██╗██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗',
        '██║    ██║██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝',
        '██║ █╗ ██║██║██╔██╗ ██║██║  ██║██║   ██║██║ █╗ ██║███████╗',
        '██║███╗██║██║██║╚██╗██║██║  ██║██║   ██║██║███╗██║╚════██║',
        '╚███╔███╔╝██║██║ ╚████║██████╔╝╚██████╔╝╚███╔███╔╝███████║',
        ' ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚══════╝'
    )

    Write-Host ''
    foreach ($line in $art) {
        Write-Host $line -ForegroundColor Magenta
    }

    $riceLine = '──── R I C E  v' + $script:RiceVersion
    $padding  = 58 - $riceLine.Length
    if ($padding -lt 0) { $padding = 0 }
    Write-Host ((' ' * $padding) + $riceLine) -ForegroundColor Cyan

    Write-Host ''
    Write-Host ('─' * 62) -ForegroundColor DarkMagenta
    Write-Host '  A Windows 10/11 rice, installed and managed in one place.' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-SectionBox {
    <#
        Two-row section header matching install.ps1's Write-Section.
        Rounded box, title in Cyan, borders in DarkCyan.
    #>
    param([string]$Title)

    $label = " $($Title.ToUpper()) "
    $pad   = $script:BoxWidth - $label.Length
    if ($pad -lt 0) { $pad = 0 }

    Write-Host ''
    Write-Host ('  ╭' + ('─' * $script:BoxWidth) + '╮') -ForegroundColor DarkCyan
    Write-Host '  │' -NoNewline -ForegroundColor DarkCyan
    Write-Host ($label + (' ' * $pad)) -NoNewline -ForegroundColor Cyan
    Write-Host '│' -ForegroundColor DarkCyan
    Write-Host ('  ╰' + ('─' * $script:BoxWidth) + '╯') -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-KeyValue {
    param(
        [string]$Key,
        [string]$Value,
        [int]$KeyWidth = 14,
        [string]$ValueColor = 'Gray'
    )
    Write-Host '    ' -NoNewline
    Write-Host $Key.PadRight($KeyWidth) -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $ValueColor
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

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Gray
}

# ================================================================ INPUT

function Read-Choice {
    param([string]$Prompt = 'Choice')
    Write-Host ''
    Write-Host "  $Prompt > " -NoNewline -ForegroundColor Cyan
    return (Read-Host).Trim()
}

function Confirm-Yes {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    Write-Host ''
    Write-Host "  $Prompt " -NoNewline -ForegroundColor Gray
    Write-Host $suffix -NoNewline -ForegroundColor DarkGray
    Write-Host ' ' -NoNewline
    $answer = (Read-Host).Trim()
    if ([string]::IsNullOrEmpty($answer)) { return $Default }
    return ($answer -match '^(y|yes)$')
}

function Wait-ForEnter {
    param([string]$Message = 'Press Enter to return to the menu')
    Write-Host ''
    Write-Host "  $Message..." -ForegroundColor DarkGray
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
        Clear-Host
        Write-Banner
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
        Installed      = $false
        Theme          = ''
        Created        = ''
        LastUpdated    = ''
        ManifestOk     = $true
        ManifestSizeKB = 0
    }

    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $state }

    try {
        $fileInfo = Get-Item -LiteralPath $ManifestPath -ErrorAction Stop
        $state.ManifestSizeKB = [math]::Round($fileInfo.Length / 1KB, 1)

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

    if ($json.created) {
        try {
            $dt = [datetime]::Parse($json.created).ToLocalTime()
            $state.Created = $dt.ToString('yyyy-MM-dd')
        } catch {
            $state.Created = ''
        }
    }

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
    <#
        Run a child PowerShell script and return its exit code.

        The `| Out-Host` on the invocation is load-bearing. Without it, every
        line the child script prints flows into this function's return value,
        and the function returns an array: [line1, line2, ..., exitCode].
        Callers do `if ($exit -eq 0)`, and PowerShell's -eq against an array
        filters instead of compares, which returns an empty array (falsy) when
        0 isn't among the elements. The result is a false failure report that
        prints the entire child output as the error message.

        Out-Host writes directly to the console host instead of the pipeline,
        so the child's output still streams live and the return value is a
        clean integer.
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ScriptArgs = @()
    )

    $shell = Get-PowerShellCommand

    Push-Location $RepoRoot
    try {
        & $shell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @ScriptArgs | Out-Host
        return $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

# ================================================================== RENDERING

function Show-MainMenu {
    param([Parameter(Mandatory)]$State)

    Clear-Host
    Write-Banner

    if (-not $State.ManifestOk -and (Test-Path -LiteralPath $ManifestPath)) {
        Write-Warn 'Manifest exists but could not be read. Treating as not installed.'
        Write-Host ''
    }

    if ($State.Installed) {
        Write-KeyValue -Key 'Repository' -Value $RepoRoot -KeyWidth 14
        Write-KeyValue -Key 'Theme'      -Value $State.Theme -KeyWidth 14 -ValueColor 'Cyan'
        if ($State.LastUpdated) {
            Write-KeyValue -Key 'Updated' -Value $State.LastUpdated -KeyWidth 14
        }

        Write-SectionBox 'Menu'

        Write-Host '    1  ' -NoNewline -ForegroundColor Cyan
        Write-Host 'Change theme' -NoNewline -ForegroundColor White
        Write-Host '          Switch to a different look' -ForegroundColor DarkGray

        Write-Host '    2  ' -NoNewline -ForegroundColor Cyan
        Write-Host 'Update' -NoNewline -ForegroundColor White
        Write-Host '                Pull latest and redeploy' -ForegroundColor DarkGray

        Write-Host '    3  ' -NoNewline -ForegroundColor Cyan
        Write-Host 'Status' -NoNewline -ForegroundColor White
        Write-Host '                Show what''s installed' -ForegroundColor DarkGray

        Write-Host '    4  ' -NoNewline -ForegroundColor Cyan
        Write-Host 'Create a new theme' -NoNewline -ForegroundColor White
        Write-Host '    Scaffold a theme folder' -ForegroundColor DarkGray

        Write-Host '    5  ' -NoNewline -ForegroundColor Cyan
        Write-Host 'Uninstall' -NoNewline -ForegroundColor White
        Write-Host '             Restore configs, remove packages' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host '    0  ' -NoNewline -ForegroundColor DarkGray
        Write-Host 'Exit' -ForegroundColor DarkGray
    } else {
        Write-KeyValue -Key 'Repository' -Value $RepoRoot -KeyWidth 14

        Write-SectionBox 'Menu'

        Write-Host '    1  ' -NoNewline -ForegroundColor Cyan
        Write-Host 'Install' -NoNewline -ForegroundColor White
        Write-Host '    Set up Windows-Rice for the first time' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host '    0  ' -NoNewline -ForegroundColor DarkGray
        Write-Host 'Exit' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Show-ThemePicker {
    param(
        [Parameter(Mandatory)]$Themes,
        [string]$CurrentTheme = '',
        [string]$Title = 'Pick a theme'
    )

    Clear-Host
    Write-SectionBox $Title

    $i = 1
    foreach ($t in $Themes) {
        $isCurrent = $CurrentTheme -and $t.Name -eq $CurrentTheme
        $numColor  = if ($isCurrent) { 'Green' } else { 'Cyan' }
        $nameColor = if ($isCurrent) { 'Green' } else { 'White' }

        Write-Host ('    ' + $i.ToString().PadRight(4)) -NoNewline -ForegroundColor $numColor
        Write-Host $t.Name.PadRight(14) -NoNewline -ForegroundColor $nameColor
        Write-Host $t.Description -NoNewline -ForegroundColor DarkGray

        if ($isCurrent) {
            Write-Host '  (current)' -ForegroundColor Green
        } else {
            Write-Host ''
        }
        $i++
    }

    Write-Host ''
    Write-Host '    0  ' -NoNewline -ForegroundColor DarkGray
    Write-Host 'Cancel' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-Status {
    param([Parameter(Mandatory)]$State)

    Clear-Host
    Write-Banner

    if (-not $State.Installed) {
        Write-SectionBox 'Status'
        Write-Host '    Windows-Rice is not installed on this machine.' -ForegroundColor Yellow
        Write-Host ''
        Write-Hint 'Run "Install" from the main menu to set it up.'
        Write-Host ''
        return
    }

    # ---- Overview --------------------------------------------------------
    Write-SectionBox 'Overview'
    Write-KeyValue -Key 'Theme'          -Value $State.Theme -KeyWidth 16 -ValueColor 'Cyan'
    if ($State.Created)     { Write-KeyValue -Key 'Installed'   -Value $State.Created -KeyWidth 16 }
    if ($State.LastUpdated) { Write-KeyValue -Key 'Last updated' -Value $State.LastUpdated -KeyWidth 16 }
    Write-KeyValue -Key 'Repository'     -Value $RepoRoot -KeyWidth 16

    # ---- Deployed configs ------------------------------------------------
    $docsDir = [Environment]::GetFolderPath('MyDocuments')

    $paths = @(
        @{ Label = 'YASB config';        Path = (Join-Path $HomeDir '.config\yasb\config.yaml');             Display = '~/.config/yasb/config.yaml' }
        @{ Label = 'YASB styles';        Path = (Join-Path $HomeDir '.config\yasb\styles.css');              Display = '~/.config/yasb/styles.css' }
        @{ Label = 'GlazeWM config';     Path = (Join-Path $HomeDir '.glzr\glazewm\config.yaml');           Display = '~/.glzr/glazewm/config.yaml' }
        @{ Label = 'Cava config';        Path = (Join-Path $HomeDir '.config\cava\config');                  Display = '~/.config/cava/config' }
        @{ Label = 'Fastfetch config';   Path = (Join-Path $HomeDir '.config\fastfetch\config.jsonc');      Display = '~/.config/fastfetch/config.jsonc' }
        @{ Label = 'Starship config';    Path = (Join-Path $HomeDir '.config\starship.toml');                Display = '~/.config/starship.toml' }
        @{ Label = 'PowerShell profile'; Path = (Join-Path $docsDir 'PowerShell\Microsoft.PowerShell_profile.ps1'); Display = '~/Documents/PowerShell/...' }
    )

    Write-SectionBox 'Deployed configs'
    foreach ($p in $paths) {
        $exists = Test-Path -LiteralPath $p.Path
        $mark   = if ($exists) { '[ok]' } else { '[  ]' }
        $markColor = if ($exists) { 'Green' } else { 'DarkGray' }
        $labelColor = if ($exists) { 'Gray' } else { 'DarkGray' }

        Write-Host '    ' -NoNewline
        Write-Host $mark.PadRight(7) -NoNewline -ForegroundColor $markColor
        Write-Host $p.Label.PadRight(22) -NoNewline -ForegroundColor $labelColor
        Write-Host $p.Display -ForegroundColor DarkGray
    }

    # ---- Installation ----------------------------------------------------
    Write-SectionBox 'Installation'

    $backupSizeMB = 0
    if (Test-Path -LiteralPath $BackupRoot) {
        try {
            $sum = (Get-ChildItem -LiteralPath $BackupRoot -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
            if ($sum) { $backupSizeMB = [math]::Round($sum / 1MB, 1) }
        } catch {}
    }

    Write-KeyValue -Key 'Backup root' -Value ("$BackupRoot  ($backupSizeMB MB)") -KeyWidth 16
    Write-KeyValue -Key 'Manifest'    -Value ("manifest.json  ($($State.ManifestSizeKB) KB)") -KeyWidth 16

    $launcherExists = Test-Path -LiteralPath $LauncherPath
    $launcherValue  = if ($launcherExists) { "$LauncherPath  [ok]" } else { "$LauncherPath  [missing]" }
    $launcherColor  = if ($launcherExists) { 'Gray' } else { 'Yellow' }
    Write-KeyValue -Key 'Launcher' -Value $launcherValue -KeyWidth 16 -ValueColor $launcherColor

    # ---- Environment -----------------------------------------------------
    Write-SectionBox 'Environment'

    $psVersion = $PSVersionTable.PSVersion.ToString()
    $edition = if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }
    Write-KeyValue -Key 'PowerShell' -Value "$psVersion  ($edition)" -KeyWidth 16

    $shellPath = (Get-Command (Get-PowerShellCommand) -ErrorAction SilentlyContinue).Source
    if ($shellPath) {
        Write-KeyValue -Key 'Shell' -Value $shellPath -KeyWidth 16
    }

    Write-KeyValue -Key 'Rice' -Value "v$script:RiceVersion" -KeyWidth 16 -ValueColor 'Cyan'
}

# ============================================================ ACTIONS

function Select-ThemeFromPicker {
    param(
        [Parameter(Mandatory)]$Themes,
        [string]$CurrentTheme = '',
        [string]$Title = 'Pick a theme'
    )

    Show-ThemePicker -Themes $Themes -CurrentTheme $CurrentTheme -Title $Title
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
    $picked = Select-ThemeFromPicker -Themes $themes -Title 'Install — pick a theme'
    if ($null -eq $picked) { return }

    $theme = $picked.Name

    Clear-Host
    Write-SectionBox 'Install'
    Write-Info "Theme: $theme"
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

    $picked = Select-ThemeFromPicker -Themes $themes -CurrentTheme $state.Theme -Title 'Change theme'
    if ($null -eq $picked) { return }

    $theme = $picked.Name
    if ($theme -eq $state.Theme) {
        Clear-Host
        Write-SectionBox 'Change theme'
        Write-Host "    '$theme' is already the active theme." -ForegroundColor Gray
        Wait-ForEnter
        return
    }

    Clear-Host
    Write-SectionBox 'Change theme'
    Write-Info "Switching to: $theme"
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
    Write-SectionBox 'Update'
    Write-Info 'Pulling latest from origin and redeploying configs...'
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
    $themes = Get-ThemeList

    $sourceInfo = Select-ThemeFromPicker -Themes $themes -Title 'Create theme — pick a source'
    if ($null -eq $sourceInfo) { return }

    $source = $sourceInfo.Name

    Clear-Host
    Write-SectionBox 'Create theme'
    Write-Info "Source: $source"
    Write-Host ''
    Write-Host '    New theme name ' -NoNewline -ForegroundColor DarkGray
    Write-Host '(lowercase, digits, hyphens, underscores)' -ForegroundColor DarkGray
    Write-Host '    > ' -NoNewline -ForegroundColor Cyan
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
    Write-Info "Creating themes\$newName\ from $source..."

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
    Write-SectionBox 'Theme created'
    Write-Host ''
    Write-Ok $newName
    Write-Host ''
    Write-KeyValue -Key 'Location' -Value $newDir -KeyWidth 12

    Write-SectionBox 'Colors — start here'
    Write-Host '    yasb\styles.css              Bar colors, spacing, fonts' -ForegroundColor Gray
    Write-Host '    starship\starship.toml       Set the palette and add a block' -ForegroundColor Gray
    Write-Host '    terminal\settings.json       Point to a Windows Terminal scheme' -ForegroundColor Gray
    Write-Host '    chronoterm\config.toml       Clock accent color' -ForegroundColor Gray

    Write-SectionBox 'Optional'
    Write-Host '    cava\config                  Visualizer gradient' -ForegroundColor Gray
    Write-Host '    fastfetch\ascii.txt          ASCII logo' -ForegroundColor Gray
    if ($copyWallpapers) {
        Write-Host '    wallpapers\                  Copied from source theme' -ForegroundColor Gray
    } else {
        Write-Host '    wallpapers\                  Empty — add a default.jpg (or .png / .webp)' -ForegroundColor Gray
    }

    Write-SectionBox 'Rarely needs editing'
    Write-Host '    glazewm\default_glazewm_config.yaml' -ForegroundColor DarkGray
    Write-Host '    fastfetch\config.jsonc' -ForegroundColor DarkGray
    Write-Host '    yasb\default_yasb_config.yaml' -ForegroundColor DarkGray

    Write-Host ''
    Write-Hint 'Tip: search styles.css for a hex from the source theme and replace each match.'
    Write-Host ''
    Write-Hint 'When you''re ready to use it, pick "Change theme" from the menu.'

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
    Write-SectionBox 'Uninstall'
    Write-Host '    This restores your config files from backups and optionally' -ForegroundColor Gray
    Write-Host '    removes packages that this installer added.' -ForegroundColor Gray

    if (-not (Confirm-Yes -Prompt 'Continue?' -Default $false)) { return }

    $removePackages = Confirm-Yes -Prompt 'Also remove packages the installer added?' -Default $false
    $purge          = Confirm-Yes -Prompt 'Also delete all backups and the manifest?' -Default $false

    $uninstallArgs = @()
    if ($removePackages) { $uninstallArgs += '-RemovePackages' }
    if ($purge)          { $uninstallArgs += '-Purge' }

    Clear-Host
    Write-SectionBox 'Uninstall'
    Write-Info 'Uninstalling...'
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

try {
    while ($true) {
        $state = Get-RiceState
        Show-MainMenu -State $state

        $choice = Read-Choice -Prompt 'Choice'

        if ($state.Installed) {
            switch ($choice) {
                '0' { break }
                '1' { Invoke-ChangeTheme }
                '2' { Invoke-Update }
                '3' { Invoke-Status }
                '4' { Invoke-CreateTheme }
                '5' { Invoke-Uninstall }
                default {
                    if ($choice -ne '') {
                        Write-Warn 'Unknown option.'
                        Start-Sleep -Seconds 1
                    }
                }
            }
        } else {
            switch ($choice) {
                '0' { break }
                '1' { Invoke-Install }
                default {
                    if ($choice -ne '') {
                        Write-Warn 'Unknown option.'
                        Start-Sleep -Seconds 1
                    }
                }
            }
        }
    }
} finally {
    Write-Host ''
    Write-Host '  Goodbye.' -ForegroundColor DarkGray
    Write-Host ''
}