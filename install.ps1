<#
.SYNOPSIS
    Windows-Rice installer for Windows 10 / 11.

.DESCRIPTION
    Installs the software required by the Windows-Rice dotfiles and deploys the
    repository's configuration files to their per-user locations.

    Safe to run repeatedly. Existing configuration files are backed up before
    being replaced or merged. Backups are written under
    %USERPROFILE%\.windows-rice-backup\<component>\ with timestamped names.

    An installation manifest is written to
    %USERPROFILE%\.windows-rice-backup\manifest.json recording exactly which
    packages this installer installed (as opposed to found already present).
    uninstall.ps1 uses this manifest to avoid removing packages it did not
    install.

    Windows Terminal's settings.json is merged (not overwritten) so unrelated
    profiles / schemes / keybindings survive.

    THEMES
    ------
    'mocha' is a reserved name. It refers to the base config set in configs\
    — there is no themes\mocha\ folder. Passing -Theme mocha is equivalent to
    passing no theme at all: both use the base configs.

    Every other theme lives under themes\<name>\, mirroring the layout of
    configs\. Files present in the theme folder override the corresponding
    base file; files absent fall through to configs\. Theme folders may
    include their own wallpapers\ subfolder, which replaces the base
    wallpaper set entirely.

    Adding a new theme requires no installer changes: drop a folder under
    themes\ and pass -Theme <name>.

    To swap themes quickly without touching packages:
        .\install.ps1 -Theme kanagawa -SkipPackages -SkipFonts

    The active theme is recorded in the manifest, so a plain .\install.ps1
    afterward keeps using the last chosen theme.

    UPDATES
    -------
    -Update pulls the latest commit from the repository's origin using git
    --ff-only (no merge commits). Combine with -SkipPackages -SkipFonts for a
    fast "get the latest configs and redeploy" pass.

.PARAMETER SkipPackages
    Skip ALL package installation: winget, scoop, the Nerd Font, PSReadLine,
    and the extras. Only configuration files are deployed.

.PARAMETER SkipFonts
    Do not install the JetBrainsMono Nerd Font. Implied by -SkipPackages.

.PARAMETER SkipTerminal
    Do not touch Windows Terminal's settings.json.

.PARAMETER DryRun
    Print what would happen without installing or changing anything.

.PARAMETER Yes
    Assume "yes" for confirmation prompts (non-interactive install).

.PARAMETER Theme
    Theme name. 'mocha' (the default) refers to the base configs. Any other
    value must match a folder under themes\. If omitted, the last theme
    recorded in the manifest is used, or 'mocha' on a fresh install.

.PARAMETER Update
    Run `git pull --ff-only` in the repository before continuing.

.NOTES
    Repository:  Windows-Rice
    Requires:    PowerShell 5.1+ (Windows 10 / 11)
    No hardcoded usernames, machine names, or clone paths.
#>

[CmdletBinding()]
param(
    [switch]$SkipPackages,
    [switch]$SkipFonts,
    [switch]$SkipTerminal,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$Theme,
    [switch]$Update
)

#Requires -Version 5.1

$ErrorActionPreference = 'Continue'

# UTF-8 output so the block and box-drawing characters render correctly.
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

# ============================================================ INITIALIZATION

$RepoRoot   = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ConfigRoot = Join-Path $RepoRoot 'configs'
$ThemeRoot  = Join-Path $RepoRoot 'themes'
$AssetRoot  = Join-Path $RepoRoot 'assets'

$HomeDir        = $env:USERPROFILE
$DocumentsDir   = [Environment]::GetFolderPath('MyDocuments')
$AppDataDir     = [Environment]::GetFolderPath('ApplicationData')
$PwshProfileDir = Join-Path $DocumentsDir 'PowerShell'
$PwshProfilePath= Join-Path $PwshProfileDir 'Microsoft.PowerShell_profile.ps1'

$YasbDir       = Join-Path $HomeDir '.config\yasb'
$GlazeWmDir    = Join-Path $HomeDir '.glzr\glazewm'
$CavaDir       = Join-Path $HomeDir '.config\cava'
$FastfetchDir  = Join-Path $HomeDir '.config\fastfetch'
$BtopDir       = Join-Path $HomeDir '.config\btop'

# Starship reads a single file directly inside .config\, not a folder.
# The repo stores it at configs\starship\starship.toml (theme overrides at
# themes\<name>\starship\starship.toml) for symmetry with every other
# component; only the destination differs.
$StarshipConfigPath = Join-Path $HomeDir '.config\starship.toml'

# ChronoTerm reads %APPDATA%\chronoterm\config.toml on first run. We resolve
# %APPDATA% through the Windows API rather than $env:APPDATA so it stays
# correct on machines where the shell environment is unusual.
$ChronoTermDir = Join-Path $AppDataDir 'chronoterm'

# Resolve the effective Pictures folder via the Windows API so this works
# on both local accounts and Microsoft accounts with OneDrive redirection.
$PicturesDir   = [Environment]::GetFolderPath('MyPictures')
$WallpaperDir  = Join-Path $PicturesDir 'Windows-Rice'

$BackupRoot    = Join-Path $HomeDir '.windows-rice-backup'
$ManifestPath  = Join-Path $BackupRoot 'manifest.json'

# The launcher shim lives at ~/.local/bin/win-rice.cmd and dispatches to
# rice.ps1 in the repo root. ~/.local/bin/ is on user PATH (added by
# Deploy-RiceLauncher), so `win-rice` works from any shell and from Win+R.
$LocalBinDir   = Join-Path $HomeDir '.local\bin'
$LauncherPath  = Join-Path $LocalBinDir 'win-rice.cmd'
$RiceScript    = Join-Path $RepoRoot 'rice.ps1'

# -SkipPackages also disables the font install and the PSReadLine install.
if ($SkipPackages) { $SkipFonts = $true }
$SkipPSReadLineInstall = [bool]$SkipPackages

# In-memory manifest state (see Register-ManifestPackage / Save-Manifest).
$script:Manifest      = $null

# Cached output of `winget list`, populated on first use. Cuts ~15 redundant
# winget invocations from a typical run.
$script:WingetListCache = $null

# ================================================================== LOGGING
#
# Presentation layer only. Every function here keeps its original name and
# parameter contract (a single positional/[string] message, or the same
# named params as before) so none of the ~60 call sites elsewhere in the
# script need to change. Only what gets printed and how it's colored has
# been redesigned.

$script:BoxWidth    = 56                   # interior width of boxed section headers
$script:BannerWidth = 58                   # width of the WINDOWS block art, verified via figlet
$script:Sep         = '─' * ($script:BoxWidth + 4)

function Write-Separator {
    Write-Host $script:Sep -ForegroundColor DarkCyan
}

function Write-Banner {
    <#
        The block art spells WINDOWS only (figlet, ansi_shadow font — every
        line verified at exactly 58 columns). "-RICE" is intentionally not
        forced into the same block font: fitting the full hyphenated name
        into ansi_shadow runs to 75+ columns and wraps badly on an 80-column
        terminal. Instead it appears as a right-aligned accent line directly
        under the art, echoing the app's Cyan (used for section headers
        elsewhere) so the banner reads as one connected wordmark rather than
        an isolated Magenta block.
    #>
    param([string]$Subtitle = '')
    Write-Host ''
    Write-Host '██╗    ██╗██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗' -ForegroundColor Magenta
    Write-Host '██║    ██║██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝' -ForegroundColor Magenta
    Write-Host '██║ █╗ ██║██║██╔██╗ ██║██║  ██║██║   ██║██║ █╗ ██║███████╗' -ForegroundColor Magenta
    Write-Host '██║███╗██║██║██║╚██╗██║██║  ██║██║   ██║██║███╗██║╚════██║' -ForegroundColor Magenta
    Write-Host '╚███╔███╔╝██║██║ ╚████║██████╔╝╚██████╔╝╚███╔███╔╝███████║' -ForegroundColor Magenta
    Write-Host ' ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚══════╝' -ForegroundColor Magenta
    Write-Host '                                              ──── R I C E' -ForegroundColor Cyan
    Write-Host ''
    if ($Subtitle) {
        Write-Host "  $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host ('─' * $script:BannerWidth) -ForegroundColor DarkMagenta
    Write-Host ''
}

function Write-Section {
    <#
        Renders the section title inside a light box instead of the plain
        rule-title-rule it used to be. Still takes exactly one positional
        string, so every existing `Write-Section 'Foo'` call is untouched.
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

function Write-EnvBlock {
    param([string]$ActiveTheme = '')

    $rows = @(
        @{ Label = 'Home';       Value = $HomeDir }
        @{ Label = 'Repository'; Value = $RepoRoot }
    )
    if ($ActiveTheme) { $rows += @{ Label = 'Theme'; Value = $ActiveTheme } }
    $rows += @{ Label = 'Dry Run'; Value = $(if ($DryRun) { 'YES — no changes will be made' } else { 'No' }) }

    Write-Host '  Environment' -ForegroundColor Cyan
    foreach ($r in $rows) {
        $valueColor = if ($r.Label -eq 'Dry Run' -and $DryRun) { 'Yellow' } else { 'Gray' }
        Write-Host ('    ┃ ' + $r.Label.PadRight(11)) -NoNewline -ForegroundColor DarkGray
        Write-Host $r.Value -ForegroundColor $valueColor
    }
    Write-Host ''
}

function Write-Ok {
    param([string]$m)
    Write-Host '  ✓ ' -NoNewline -ForegroundColor Green
    Write-Host $m -ForegroundColor Gray
}
function Write-Skip {
    param([string]$m)
    Write-Host '  · ' -NoNewline -ForegroundColor DarkGray
    Write-Host $m -ForegroundColor DarkGray
}
function Write-WarnLine {
    param([string]$m)
    Write-Host '  ▲ ' -NoNewline -ForegroundColor Yellow
    Write-Host $m -ForegroundColor Yellow
}
function Write-FailLine {
    param([string]$m)
    Write-Host '  ✗ ' -NoNewline -ForegroundColor Red
    Write-Host $m -ForegroundColor Red
}
function Write-Info {
    param([string]$m)
    Write-Host '  › ' -NoNewline -ForegroundColor DarkCyan
    Write-Host $m -ForegroundColor Gray
}

# ================================================================== SUMMARY

$script:Summary = [ordered]@{
    'Installed'        = New-Object System.Collections.ArrayList
    'AlreadyInstalled' = New-Object System.Collections.ArrayList
    'Configured'       = New-Object System.Collections.ArrayList
    'Skipped'          = New-Object System.Collections.ArrayList
    'Warnings'         = New-Object System.Collections.ArrayList
    'Failed'           = New-Object System.Collections.ArrayList
}

function Add-Summary {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Message
    )
    if ($script:Summary.Contains($Category)) {
        [void]$script:Summary[$Category].Add($Message)
    }
}

# ================================================================== HELPERS

function Write-Utf8NoBom {
    <#
        Write text to a file as UTF-8 without a BOM. Under PowerShell 5.1,
        `Set-Content -Encoding UTF8` emits a BOM; that breaks tools which
        treat the leading bytes as content (some YAML parsers, winget config
        readers). Use this instead for any file where the BOM would be
        unwanted.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Update-PathFromRegistry {
    <#
        Append newly-installed package paths from the registry (Machine + User)
        onto the existing process PATH, without dropping process-level entries
        added by the caller (scoop shims, conda, build tools, ...).
        Order of existing process entries is preserved; new entries are appended.
    #>
    $currentParts = @($env:Path -split ';' | Where-Object { $_ -ne '' })
    $machineParts = @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' |
                        Where-Object { $_ -ne '' })
    $userParts    = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' |
                        Where-Object { $_ -ne '' })

    $seen   = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $merged = New-Object 'System.Collections.Generic.List[string]'

    foreach ($p in $currentParts) { if ($seen.Add($p)) { $merged.Add($p) } }
    foreach ($p in $machineParts) { if ($seen.Add($p)) { $merged.Add($p) } }
    foreach ($p in $userParts)    { if ($seen.Add($p)) { $merged.Add($p) } }

    if ($merged.Count -gt 0) {
        $env:Path = ($merged -join ';')
    }
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Confirm-Action {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    if ($Yes) { return $true }
    $suffix = if ($Default) { '(Y/n)' } else { '(y/N)' }
    $answer = Read-Host "    $Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return ($answer -match '^(y|yes)$')
}

function New-Timestamp {
    return (Get-Date -Format 'yyyy-MM-dd-HHmmss')
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Invoke-GlazeWmReload {
    <#
        GlazeWM loads its config once at startup and does not watch the file
        for changes. After the installer deploys a new glazewm config (theme
        swap, manual edit, whatever), the running instance still has the old
        one loaded until told to re-read it.

        `wm-reload-config` re-parses the config file and applies the changes
        live. It does NOT re-run startup_commands — YASB and AutoTiler are
        not relaunched. Safe to call whether GlazeWM is running or not.
    #>
    if (-not (Test-CommandExists 'glazewm')) {
        return
    }

    $proc = Get-Process -Name 'glazewm' -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Info 'GlazeWM not running — config applies on next start.'
        return
    }

    if ($DryRun) {
        Write-Skip 'would tell GlazeWM to reload its config'
        return
    }

    try {
        & glazewm command wm-reload-config 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'GlazeWM config reloaded'
        } else {
            Write-WarnLine "GlazeWM reload exited $LASTEXITCODE"
        }
    } catch {
        Write-WarnLine "GlazeWM reload failed: $_"
    }
}

function Backup-And-Deploy {
    <#
        Copy a repository config to its destination, backing up any existing
        file (when it differs) first. Idempotent: if the destination already
        has identical content, nothing is done.

        Backups go under $BackupRoot\<BackupSubdir>\<filename>.backup-<timestamp>.
    #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Label        = $Destination,
        [string]$BackupSubdir = 'misc'
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        Write-FailLine "$Label — source missing: $Source"
        Add-Summary 'Failed' "$Label (source missing)"
        return $false
    }

    $destDir = Split-Path -Parent $Destination
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        if ($DryRun) {
            Write-Skip "would create directory $destDir"
        } else {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
    }

    if (Test-Path -LiteralPath $Destination) {
        $srcHash = Get-FileSha256 -Path $Source
        $dstHash = Get-FileSha256 -Path $Destination
        if ($srcHash -and $dstHash -and $srcHash -eq $dstHash) {
            Write-Skip "$Label already up to date"
            Add-Summary 'AlreadyInstalled' "$Label (config)"
            return $true
        }

        $backupDir  = Join-Path $BackupRoot $BackupSubdir
        $backupName = (Split-Path -Leaf $Destination) + '.backup-' + (New-Timestamp)
        $backupPath = Join-Path $backupDir $backupName

        if ($DryRun) {
            Write-Skip "would back up $Destination → $backupPath"
        } else {
            if (-not (Test-Path -LiteralPath $backupDir)) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $Destination -Destination $backupPath -Force
            Write-Info "backup: $backupPath"
        }
    }

    if ($DryRun) {
        Write-Skip "would deploy $Label"
        Add-Summary 'Configured' "$Label (dry run)"
        return $true
    }

    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
        Write-Ok "$Label"
        Add-Summary 'Configured' $Label
        return $true
    } catch {
        Write-FailLine "$Label — $_"
        Add-Summary 'Failed' "$Label ($_)"
        return $false
    }
}

# ===================================================== THEME RESOLUTION

function Resolve-ThemeFile {
    <#
        Return the path to deploy from for a given config file. Prefers the
        theme-specific override at themes\<theme>\<relpath>; falls back to
        the base file at configs\<relpath>.

        If $ThemeName is empty (mocha / base theme), returns the base path.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ThemeName,
        [Parameter(Mandatory)][string]$RelPath
    )

    if ($ThemeName) {
        $themeFile = Join-Path (Join-Path $ThemeRoot $ThemeName) $RelPath
        if (Test-Path -LiteralPath $themeFile) {
            return $themeFile
        }
    }
    return (Join-Path $ConfigRoot $RelPath)
}

function Get-ThemeMarker {
    <#
        Return a short suffix for display, indicating whether a file came
        from the active theme or fell through to the base config.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ThemeName,
        [Parameter(Mandatory)][string]$RelPath
    )

    if ($ThemeName) {
        $themeFile = Join-Path (Join-Path $ThemeRoot $ThemeName) $RelPath
        if (Test-Path -LiteralPath $themeFile) {
            return " [$ThemeName]"
        }
    }
    return ''
}

# ======================================================== INSTALL MANIFEST

function Get-Manifest {
    <#
        Read the installation manifest, or return a fresh empty one.
        Never throws: on parse failure, warns and starts fresh.
    #>
    $empty = [ordered]@{
        version     = 1
        created     = (Get-Date).ToUniversalTime().ToString('o')
        updated     = (Get-Date).ToUniversalTime().ToString('o')
        installed   = [ordered]@{
            winget = @()
            scoop  = @()
            direct = @()
        }
        preferences = [ordered]@{}
    }

    if (-not (Test-Path -LiteralPath $ManifestPath)) { return $empty }

    try {
        $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-WarnLine "Could not parse existing manifest at $ManifestPath — starting fresh."
        return $empty
    }

    $result = [ordered]@{
        version     = 1
        created     = (Get-Date).ToUniversalTime().ToString('o')
        updated     = (Get-Date).ToUniversalTime().ToString('o')
        installed   = [ordered]@{
            winget = @()
            scoop  = @()
            direct = @()
        }
        preferences = [ordered]@{}
    }
    if ($obj.version) { $result.version = $obj.version }
    if ($obj.created) { $result.created = $obj.created }
    if ($obj.installed) {
        if ($obj.installed.winget) { $result.installed.winget = @($obj.installed.winget) }
        if ($obj.installed.scoop)  { $result.installed.scoop  = @($obj.installed.scoop) }
        if ($obj.installed.direct) { $result.installed.direct = @($obj.installed.direct) }
    }
    if ($obj.preferences) {
        foreach ($k in $obj.preferences.PSObject.Properties.Name) {
            $result.preferences[$k] = $obj.preferences.$k
        }
    }
    return $result
}

function Save-Manifest {
    param([Parameter(Mandatory)]$Manifest)

    if ($DryRun) { return }

    $dir = Split-Path -Parent $ManifestPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Manifest.updated = (Get-Date).ToUniversalTime().ToString('o')

    try {
        $json = $Manifest | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $ManifestPath -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-WarnLine "Could not write manifest: $_"
    }
}

function Register-ManifestPackage {
    <#
        Record that this installer actually installed a package. Called only
        on the success path, and only when the package was NOT already present
        before this run. Idempotent across runs (no duplicates).
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('winget','scoop','direct')][string]$Manager,
        [Parameter(Mandatory)][string]$Id
    )

    if (-not $script:Manifest) {
        $script:Manifest = Get-Manifest
    }

    $list = @($script:Manifest.installed.$Manager)
    if ($list -notcontains $Id) {
        $script:Manifest.installed.$Manager = @($list + $Id)
        Save-Manifest -Manifest $script:Manifest
    }
}

# ====================================================== PACKAGE MANAGER BITS

function Test-WingetAvailable {
    return (Test-CommandExists 'winget')
}

function Get-WingetList {
    <#
        Return the raw output of `winget list` for the current user. Cached
        for the duration of the run so per-package checks don't re-invoke
        winget each time. The cache is populated once, on first use.
    #>
    if ($null -ne $script:WingetListCache) {
        return $script:WingetListCache
    }

    try {
        $script:WingetListCache = (& winget list --accept-source-agreements 2>&1 | Out-String)
    } catch {
        $script:WingetListCache = ''
    }
    return $script:WingetListCache
}

function Test-WingetPackageInstalled {
    param([string]$Id)
    $list = Get-WingetList
    if ([string]::IsNullOrWhiteSpace($list)) { return $false }
    return ($list -match [regex]::Escape($Id))
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name
    )

    if (Test-WingetPackageInstalled -Id $Id) {
        Write-Skip "$Name already installed"
        Add-Summary 'AlreadyInstalled' $Name
        return $true
    }

    if ($DryRun) {
        Write-Skip "would install $Name ($Id)"
        Add-Summary 'Installed' "$Name (dry run)"
        return $true
    }

    Write-Info "installing $Name ($Id)..."
    try {
        $out = (& winget install --id $Id --exact `
                    --disable-interactivity `
                    --accept-package-agreements --accept-source-agreements 2>&1 |
                Out-String)
    } catch {
        Write-FailLine "$Name — $_"
        Add-Summary 'Failed' "$Name ($_)"
        return $false
    }

    # Exit code 0 = success. We already verified the package was absent at
    # the top of this function, so a clean exit here means a real install.
    if ($LASTEXITCODE -eq 0) {
        Write-Ok $Name
        Add-Summary 'Installed' $Name
        Register-ManifestPackage -Manager 'winget' -Id $Id
        return $true
    }

    # 0x8A150061 (-1978335135) = APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED.
    # The initial check missed it (rare race, or the user installed it between
    # the check and now), so don't register it in the manifest.
    if ($LASTEXITCODE -eq -1978335135) {
        Write-Skip "$Name already installed"
        Add-Summary 'AlreadyInstalled' $Name
        return $true
    }

    Write-FailLine "$Name — winget exit $LASTEXITCODE"
    Add-Summary 'Failed' "$Name (winget exit $LASTEXITCODE)"
    return $false
}

function Ensure-Scoop {
    if (Test-CommandExists 'scoop') {
        Write-Ok 'Scoop present'
        return $true
    }

    Write-WarnLine 'Scoop is not installed.'

    if ($DryRun) {
        Write-Skip 'would install Scoop for the current user'
        Add-Summary 'Skipped' 'Scoop (dry run)'
        return $false
    }

    if (-not (Confirm-Action -Prompt 'Install Scoop for the current user?' -Default $true)) {
        Write-Skip 'Scoop installation declined by user'
        Add-Summary 'Skipped' 'Scoop (declined)'
        return $false
    }

    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        # This is the upstream-supported bootstrap. It downloads and runs the
        # Scoop installer in-process. No checksum is available; the trust
        # decision is implicit in installing Scoop at all.
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    } catch {
        Write-FailLine "Scoop installation failed: $_"
        Add-Summary 'Failed' "Scoop ($_)"
        return $false
    }

    Update-PathFromRegistry

    if (-not (Test-CommandExists 'scoop')) {
        Write-FailLine 'Scoop still not on PATH after install'
        Add-Summary 'Failed' 'Scoop (not on PATH)'
        return $false
    }

    Write-Ok 'Scoop installed'
    Add-Summary 'Installed' 'Scoop'
    return $true
}

function Add-ScoopBucket {
    param([Parameter(Mandatory)][string]$Bucket)

    if ($DryRun) {
        Write-Skip "would ensure scoop bucket '$Bucket'"
        return
    }

    # Attempt the add first — scoop returns exit code 2 with a "bucket
    # already exists" message when it's present, and 0 when it was added.
    # Both are success for our purposes; anything else is a genuine problem.
    try {
        $out = (& scoop bucket add $Bucket 2>&1 | Out-String)
    } catch {
        Write-WarnLine "scoop bucket add $Bucket — $_"
        Add-Summary 'Warnings' "scoop bucket $Bucket ($_)"
        return
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "scoop bucket '$Bucket' added"
        return
    }

    if ($LASTEXITCODE -eq 2 -or $out -match 'already') {
        Write-Skip "scoop bucket '$Bucket' already present"
        return
    }

    Write-WarnLine "scoop bucket add $Bucket exit $LASTEXITCODE"
    Add-Summary 'Warnings' "scoop bucket $Bucket (exit $LASTEXITCODE)"
}

function Install-ScoopPackage {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Display = $Name
    )

    if ($DryRun) {
        Write-Skip "would scoop install $Name"
        Add-Summary 'Installed' "$Display (dry run)"
        return $true
    }

    try {
        $out = (& scoop install $Name 2>&1 | Out-String)
    } catch {
        Write-FailLine "$Display — $_"
        Add-Summary 'Failed' "$Display ($_)"
        return $false
    }

    # scoop exits 0 whether the package was freshly installed or already
    # present. Detect the latter from its output text; scoop's message is
    # not localized (upstream ships English-only).
    if ($out -match 'already installed') {
        Write-Skip "$Display already installed"
        Add-Summary 'AlreadyInstalled' $Display
        return $true
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Ok $Display
        Add-Summary 'Installed' $Display
        Register-ManifestPackage -Manager 'scoop' -Id $Name
        return $true
    }

    Write-FailLine "$Display — scoop exit $LASTEXITCODE"
    Add-Summary 'Failed' "$Display (scoop exit $LASTEXITCODE)"
    return $false
}

# ==================================================== PACKAGE INSTALLATION

function Install-AllPackages {

    Write-Section 'Winget packages'

    $wingetOk = Test-WingetAvailable
    if (-not $wingetOk) {
        Write-WarnLine 'winget is not available on this system.'
        Write-WarnLine 'Install "App Installer" from the Microsoft Store, then re-run.'
        Add-Summary 'Warnings' 'winget not available'
    }

    if ($wingetOk) {
        # Prime the cache with a single `winget list` call so per-package
        # checks don't re-invoke winget fifteen times.
        [void](Get-WingetList)

        # Core rice components (winget).
        Install-WingetPackage -Id 'Microsoft.PowerShell'      -Name 'PowerShell 7'      | Out-Null
        Install-WingetPackage -Id 'Microsoft.WindowsTerminal' -Name 'Windows Terminal'  | Out-Null
        Install-WingetPackage -Id 'glzr-io.glazewm'           -Name 'GlazeWM'           | Out-Null
        Install-WingetPackage -Id 'AmN.yasb'                  -Name 'YASB'              | Out-Null
        Install-WingetPackage -Id 'karlstav.cava'             -Name 'Cava'              | Out-Null

        # CLI tooling (winget).
        Install-WingetPackage -Id 'aristocratos.btop4win'     -Name 'btop4win'          | Out-Null
        Install-WingetPackage -Id 'sharkdp.fd'                -Name 'fd'                | Out-Null
        Install-WingetPackage -Id 'junegunn.fzf'              -Name 'fzf'               | Out-Null
        Install-WingetPackage -Id 'BurntSushi.ripgrep.MSVC'   -Name 'ripgrep'           | Out-Null
        Install-WingetPackage -Id 'yt-dlp.yt-dlp'             -Name 'yt-dlp'            | Out-Null
        Install-WingetPackage -Id 'Starship.Starship'         -Name 'Starship'          | Out-Null

        # Yazi + supporting dependencies (winget).
        Install-WingetPackage -Id 'sxyazi.yazi'               -Name 'Yazi'              | Out-Null
        Install-WingetPackage -Id 'Gyan.FFmpeg'               -Name 'FFmpeg'            | Out-Null
        Install-WingetPackage -Id '7zip.7zip'                 -Name '7-Zip'             | Out-Null
        Install-WingetPackage -Id 'jqlang.jq'                 -Name 'jq'                | Out-Null
        Install-WingetPackage -Id 'ajeetdsouza.zoxide'        -Name 'zoxide'            | Out-Null
        Install-WingetPackage -Id 'ImageMagick.ImageMagick'   -Name 'ImageMagick'       | Out-Null
    }

    Write-Section 'Scoop packages'

    $scoopOk = Ensure-Scoop
    if ($scoopOk) {
        Add-ScoopBucket -Bucket 'extras'
        Add-ScoopBucket -Bucket 'nerd-fonts'
        Install-ScoopPackage -Name 'fastfetch' -Display 'Fastfetch' | Out-Null
    } else {
        Write-WarnLine 'Skipping Scoop-based installs (Fastfetch).'
        Add-Summary 'Skipped' 'Fastfetch (Scoop unavailable)'
    }

    # Ensure winget's portable-package links folder is on the user PATH.
    # winget doesn't always add this on first portable install, which is why
    # "btop" may not resolve even though "btop4win" does.
    $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    if (Test-Path -LiteralPath $links) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';' | Where-Object { $_ -ne '' }) -notcontains $links) {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$links", 'User')
            Write-Info "Added winget Links folder to user PATH"
        }
    }
}

# ================================================================== FONTS

function Install-RiceFont {
    if (-not (Test-CommandExists 'scoop')) {
        Write-WarnLine 'Scoop unavailable — cannot install JetBrainsMono Nerd Font.'
        Write-WarnLine 'Install manually: https://www.nerdfonts.com/font-downloads'
        Add-Summary 'Skipped' 'JetBrainsMono Nerd Font (Scoop unavailable)'
        return
    }

    $primary  = 'JetBrainsMono-NF-Mono'
    $fallback = 'JetBrainsMono-NF'

    if ($DryRun) {
        Write-Skip "would scoop install $primary"
        Add-Summary 'Installed' "$primary (dry run)"
        return
    }

    Write-Info "installing $primary..."
    $out = (& scoop install $primary 2>&1 | Out-String)

    if ($LASTEXITCODE -eq 0) {
        if ($out -match 'already installed') {
            Write-Skip "$primary already installed"
            Add-Summary 'AlreadyInstalled' $primary
        } else {
            Write-Ok $primary
            Add-Summary 'Installed' $primary
            Register-ManifestPackage -Manager 'scoop' -Id $primary
        }
        return
    }

    Write-WarnLine "$primary failed — trying $fallback..."
    $out2 = (& scoop install $fallback 2>&1 | Out-String)

    if ($LASTEXITCODE -eq 0) {
        if ($out2 -match 'already installed') {
            Write-Skip "$fallback already installed"
            Add-Summary 'AlreadyInstalled' "$fallback (fallback)"
        } else {
            Write-Ok $fallback
            Add-Summary 'Installed' "$fallback (fallback)"
            Register-ManifestPackage -Manager 'scoop' -Id $fallback
        }
        return
    }

    Write-FailLine 'JetBrainsMono Nerd Font installation failed.'
    Add-Summary 'Failed' 'JetBrainsMono Nerd Font'
}

# ======================================================== EXTRAS

function Install-Thide {
    <#
        Thide — taskbar hide/show. Portable ZIP from GitHub releases.
        Pinned to a specific version. To update, change $version below to
        match the release tag on https://github.com/amnweb/thide/releases
        and adjust the asset filename if the naming convention changes.
    #>
    $thideDir = Join-Path $HomeDir '.local\bin\thide'
    $thideExe = Join-Path $thideDir 'thide.exe'
    $version  = '0.1.3'

    Write-Section 'Thide'

    if (Test-Path -LiteralPath $thideExe) {
        Write-Skip 'Thide already installed'
        Add-Summary 'AlreadyInstalled' 'Thide'
        return
    }

    if ($DryRun) {
        Write-Skip "would download Thide v$version (portable) and enable autostart"
        Add-Summary 'Installed' 'Thide (dry run)'
        return
    }

    $url = "https://github.com/amnweb/thide/releases/download/v$version/thide-$version-x64-portable.zip"
    $zip = Join-Path $env:TEMP 'thide-portable.zip'

    try {
        Write-Info "downloading Thide v$version..."
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -ErrorAction Stop

        New-Item -ItemType Directory -Path $thideDir -Force | Out-Null
        Expand-Archive -Path $zip -DestinationPath $thideDir -Force -ErrorAction Stop
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';' | Where-Object { $_ -ne '' }) -notcontains $thideDir) {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$thideDir", 'User')
            Write-Info "Added $thideDir to user PATH"
        }

        # Register autostart so the taskbar stays hidden across reboots.
        # If this fails the taskbar will come back on next login — loud
        # warning rather than silent success.
        if (Test-Path -LiteralPath $thideExe) {
            $autostartOut = (& $thideExe enable-autostart 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0) {
                Write-WarnLine "Thide autostart setup exited $LASTEXITCODE — taskbar may reappear on next login."
                Write-WarnLine "Run '$thideExe enable-autostart' manually to retry."
                Add-Summary 'Warnings' 'Thide (autostart setup failed)'
            }
        }

        Write-Ok 'Thide installed'
        Add-Summary 'Installed' 'Thide'
        Register-ManifestPackage -Manager 'direct' -Id 'thide'
    } catch {
        Write-FailLine "Thide — $_"
        Add-Summary 'Failed' "Thide ($_)"
    }
}

function Install-GlazeAutoTiler {
    <#
        GlazeWM AutoTiler — tray application. Pre-built .exe from GitHub
        releases. Config lives at ~/.config/glaze-autotiler/ and is created
        by the app on first run.
    #>
    $autotilerDir = Join-Path $HomeDir '.local\bin\glaze-autotiler'
    $autotilerExe = Join-Path $autotilerDir 'glaze-autotiler.exe'
    $version      = '1.0.4'

    Write-Section 'GlazeWM AutoTiler'

    if (Test-Path -LiteralPath $autotilerExe) {
        Write-Skip 'GlazeWM AutoTiler already installed'
        Add-Summary 'AlreadyInstalled' 'GlazeWM AutoTiler'
        return
    }

    if ($DryRun) {
        Write-Skip "would download GlazeWM AutoTiler v$version and add to PATH"
        Add-Summary 'Installed' 'GlazeWM AutoTiler (dry run)'
        return
    }

    $url = "https://github.com/orbi-tal/glaze-autotiler/releases/download/v$version/glaze-autotiler-$version.exe"

    try {
        Write-Info "downloading GlazeWM AutoTiler v$version..."
        New-Item -ItemType Directory -Path $autotilerDir -Force | Out-Null
        Invoke-WebRequest -Uri $url -OutFile $autotilerExe -UseBasicParsing -ErrorAction Stop

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';' | Where-Object { $_ -ne '' }) -notcontains $autotilerDir) {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$autotilerDir", 'User')
            Write-Info "Added $autotilerDir to user PATH"
        }

        Write-Ok 'GlazeWM AutoTiler installed'
        Add-Summary 'Installed' 'GlazeWM AutoTiler'
        Register-ManifestPackage -Manager 'direct' -Id 'glaze-autotiler'
    } catch {
        Write-FailLine "GlazeWM AutoTiler — $_"
        Add-Summary 'Failed' "GlazeWM AutoTiler ($_)"
    }
}

function Install-ChronoTerm {
    <#
        ChronoTerm — terminal clock / countdown. Pre-build .exe from GitHub
        releases. Writes its own config to %APPDATA%\chronoterm\config.toml
        on first run; our configs override that file with the theme-aware
        version deployed by Deploy-AllConfigs.
    #>
    $dir     = Join-Path $HomeDir '.local\bin\chronoterm'
    $exe     = Join-Path $dir 'chronoterm.exe'
    $version = '1.0.2'

    Write-Section 'ChronoTerm'

    if (Test-Path -LiteralPath $exe) {
        Write-Skip 'ChronoTerm already installed'
        Add-Summary 'AlreadyInstalled' 'ChronoTerm'
        return
    }

    if ($DryRun) {
        Write-Skip "would download ChronoTerm v$version and add to PATH"
        Add-Summary 'Installed' 'ChronoTerm (dry run)'
        return
    }

    $url = "https://github.com/cumulus13/chronoterm/releases/download/v$version/chronoterm-windows-x86_64.exe"

    try {
        Write-Info "downloading ChronoTerm v$version..."
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing -ErrorAction Stop

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';' | Where-Object { $_ -ne '' }) -notcontains $dir) {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$dir", 'User')
            Write-Info "Added $dir to user PATH"
        }

        Write-Ok 'ChronoTerm installed'
        Add-Summary 'Installed' 'ChronoTerm'
        Register-ManifestPackage -Manager 'direct' -Id 'chronoterm'
    } catch {
        Write-FailLine "ChronoTerm — $_"
        Add-Summary 'Failed' "ChronoTerm ($_)"
    }
}

function Install-CMatrixWin {
    <#
        cmatrix-win — native Windows port of cmatrix. Single C file, no
        ncurses / MSYS / Cygwin dependencies. Distributed as a pre-built
        cmatrix.exe on GitHub releases.

        Uses the "latest release" download URL so this never needs updating
        when upstream cuts a new version. The asset is always named
        cmatrix.exe (confirmed in the upstream README).

        Replaces the previous rmatrix scoop package, which doesn't actually
        exist in any bucket. See https://github.com/nxstynate/cmatrix-win
    #>
    $dir = Join-Path $HomeDir '.local\bin\cmatrix-win'
    $exe = Join-Path $dir 'cmatrix.exe'

    Write-Section 'cmatrix'

    if (Test-Path -LiteralPath $exe) {
        Write-Skip 'cmatrix already installed'
        Add-Summary 'AlreadyInstalled' 'cmatrix'
        return
    }

    if ($DryRun) {
        Write-Skip "would download cmatrix.exe (latest release) and add to PATH"
        Add-Summary 'Installed' 'cmatrix (dry run)'
        return
    }

    $url = "https://github.com/nxstynate/cmatrix-win/releases/latest/download/cmatrix.exe"

    try {
        Write-Info "downloading cmatrix.exe (latest release)..."
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing -ErrorAction Stop

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';' | Where-Object { $_ -ne '' }) -notcontains $dir) {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$dir", 'User')
            Write-Info "Added $dir to user PATH"
        }

        Write-Ok 'cmatrix installed'
        Add-Summary 'Installed' 'cmatrix'
        Register-ManifestPackage -Manager 'direct' -Id 'cmatrix-win'
    } catch {
        Write-FailLine "cmatrix — $_"
        Add-Summary 'Failed' "cmatrix ($_)"
    }
}

function Install-FlowLauncher {
    if (-not (Test-CommandExists 'scoop')) {
        Write-Skip 'Scoop unavailable — cannot install Flow Launcher'
        Add-Summary 'Skipped' 'Flow Launcher (Scoop unavailable)'
        return
    }
    Install-ScoopPackage -Name 'flow-launcher' -Display 'Flow Launcher' | Out-Null
}

function Install-Windhawk {
    Install-WingetPackage -Id 'RamenSoftware.Windhawk' -Name 'Windhawk' | Out-Null
    if (-not $DryRun) {
        Write-Info 'Windhawk installed. No mods are installed by default.'
        Write-Info 'Open Windhawk to browse and install mods manually.'
    }
}

function Install-Extras {
    Install-Thide
    Install-GlazeAutoTiler
    Install-FlowLauncher
    Install-Windhawk
    Install-ChronoTerm
    Install-CMatrixWin
}

# ======================================================= CONFIG DEPLOYMENT

function Deploy-AllConfigs {
    <#
        Every configurable file this installer manages is listed in the
        $deployMap below. Adding a new configurable file means adding one
        entry to that map — nothing else in the installer needs to change.

        Each entry:
          Rel    — path relative to configs\ (and, if overriding, to
                   themes\<theme>\)
          Dest   — absolute destination path
          Subdir — backup subfolder under $BackupRoot
          Label  — human-readable label for logging
          Sub    — if $true, apply the substitution table to the content
                   before deploying (used for YASB's wallpaper path)

        A file is only deployed if at least one of:
          - themes\<theme>\<Rel> exists (theme override), OR
          - configs\<Rel> exists (base file)

        If neither exists, the file is silently skipped.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ThemeName
    )

    Write-Section 'Deploying configurations'

    # Substitution table for text configs. YASB's wallpaper path is the only
    # current consumer; the mechanism is generic so future configs can opt in.
    $themeSubdir = if ($ThemeName) { $ThemeName } else { 'mocha' }
    $substitutions = @{
        '~/Pictures/Windows-Rice' = (Join-Path $WallpaperDir $themeSubdir) -replace '\\', '/'
    }

    # ------------------------------------------------------------------
    # DEPLOY MAP — add a new configurable file by adding one line here.
    # ------------------------------------------------------------------
    $deployMap = @(
        @{ Rel = 'yasb\default_yasb_config.yaml';        Dest = (Join-Path $YasbDir      'config.yaml');        Subdir = 'yasb';        Label = '~/.config/yasb/config.yaml';                Sub = $true }
        @{ Rel = 'yasb\styles.css';                      Dest = (Join-Path $YasbDir      'styles.css');         Subdir = 'yasb';        Label = '~/.config/yasb/styles.css' }
        @{ Rel = 'glazewm\default_glazewm_config.yaml';  Dest = (Join-Path $GlazeWmDir   'config.yaml');        Subdir = 'glazewm';     Label = '~/.glzr/glazewm/config.yaml' }
        @{ Rel = 'cava\config';                          Dest = (Join-Path $CavaDir      'config');             Subdir = 'cava';        Label = '~/.config/cava/config' }
        @{ Rel = 'fastfetch\config.jsonc';               Dest = (Join-Path $FastfetchDir 'config.jsonc');       Subdir = 'fastfetch';   Label = '~/.config/fastfetch/config.jsonc' }
        @{ Rel = 'fastfetch\ascii.txt';                  Dest = (Join-Path $FastfetchDir 'ascii.txt');          Subdir = 'fastfetch';   Label = '~/.config/fastfetch/ascii.txt' }
        @{ Rel = 'powershell\Microsoft.PowerShell_profile.ps1'; Dest = $PwshProfilePath;                        Subdir = 'powershell';  Label = 'PowerShell profile' }
        @{ Rel = 'chronoterm\config.toml';               Dest = (Join-Path $ChronoTermDir 'config.toml');       Subdir = 'chronoterm';  Label = '%APPDATA%\chronoterm\config.toml' }
        @{ Rel = 'btop\btop.conf';                       Dest = (Join-Path $BtopDir      'btop.conf');          Subdir = 'btop';        Label = '~/.config/btop/btop.conf' }
        @{ Rel = 'starship\starship.toml';               Dest = $StarshipConfigPath;                            Subdir = 'starship';    Label = '~/.config/starship.toml' }
    )
    # ------------------------------------------------------------------

    # Pre-create the PowerShell profile directory if needed.
    if (-not (Test-Path -LiteralPath $PwshProfileDir)) {
        if ($DryRun) {
            Write-Skip "would create $PwshProfileDir"
        } else {
            New-Item -ItemType Directory -Path $PwshProfileDir -Force | Out-Null
        }
    }

    foreach ($entry in $deployMap) {
        $src    = Resolve-ThemeFile -ThemeName $ThemeName -RelPath $entry.Rel
        $marker = Get-ThemeMarker   -ThemeName $ThemeName -RelPath $entry.Rel

        if (-not (Test-Path -LiteralPath $src)) {
            Write-Skip "$($entry.Label) — no source file, skipping"
            continue
        }

        $deploySource = $src
        $tempCreated  = $false

        if ($entry.Sub) {
            $content = Get-Content -LiteralPath $src -Raw
            foreach ($find in $substitutions.Keys) {
                $content = $content -replace [regex]::Escape($find), $substitutions[$find]
            }
            $deploySource = Join-Path $env:TEMP "windows-rice-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            # No BOM: the deployed YASB config is read by Python's YAML
            # loader, which can be picky about leading bytes.
            Write-Utf8NoBom -Path $deploySource -Content $content
            $tempCreated = $true
        }

        Backup-And-Deploy `
            -Source       $deploySource `
            -Destination  $entry.Dest `
            -Label        "$($entry.Label)$marker" `
            -BackupSubdir $entry.Subdir | Out-Null

        if ($tempCreated) {
            Remove-Item -LiteralPath $deploySource -Force -ErrorAction SilentlyContinue
        }
    }
}

function Set-DefaultWallpaper {
    <#
        Applies the theme's default.* wallpaper to the desktop.

        Behaviour:
        - First install (no recorded theme): apply, remember which theme we
          applied for.
        - Re-run, same theme: skip. The user may have picked their own
          wallpaper since; don't clobber it.
        - Re-run, different theme: apply. Swapping themes is a deliberate
          action and the wallpaper should follow.

        Uses SystemParametersInfo (the Win32 API) rather than RUNDLL32,
        because RUNDLL32 is unreliable on Windows 10/11 and doesn't always
        commit the change to the registry.
    #>
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ThemeName
    )

    # Normalise: empty theme name means mocha / base configs.
    $currentTheme = if ($ThemeName) { $ThemeName } else { 'mocha' }

    # What theme did we last set the wallpaper for?
    # - If `default_wallpaper_theme` is present, that's authoritative.
    # - If it's missing but the legacy `default_wallpaper_set` flag is true,
    #   assume mocha (that's what the old code always did).
    $recordedTheme = $null
    if ($Manifest.preferences) {
        if ($Manifest.preferences.default_wallpaper_theme) {
            $recordedTheme = $Manifest.preferences.default_wallpaper_theme
        } elseif ($Manifest.preferences.default_wallpaper_set) {
            $recordedTheme = 'mocha'
        }
    }

    if ($recordedTheme -eq $currentTheme) {
        Write-Skip "Default wallpaper already applied for theme '$currentTheme'"
        return
    }

    if ($DryRun) {
        Write-Skip "would set desktop wallpaper to $(Split-Path -Leaf $ImagePath)"
        return
    }

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        Write-WarnLine "Default wallpaper not found: $ImagePath"
        return
    }

    try {
        if (-not ('WinWallpaper' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@ -ErrorAction Stop
        }

        $SPI_SETDESKWALLPAPER = 0x0014
        $SPIF_UPDATEINIFILE   = 0x01
        $SPIF_SENDCHANGE      = 0x02

        $result = [WinWallpaper]::SystemParametersInfo(
            $SPI_SETDESKWALLPAPER, 0, $ImagePath,
            ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE))

        if ($result -ne 0) {
            Write-Ok "Desktop wallpaper set: $(Split-Path -Leaf $ImagePath)"

            if (-not $Manifest.preferences) {
                $Manifest.preferences = [ordered]@{}
            }
            $Manifest.preferences.default_wallpaper_set   = $true
            $Manifest.preferences.default_wallpaper_theme = $currentTheme
            Save-Manifest -Manifest $Manifest
        } else {
            Write-WarnLine 'SystemParametersInfo returned 0 — wallpaper unchanged'
        }
    } catch {
        Write-WarnLine "Could not set wallpaper: $_"
    }
}

function Deploy-Wallpapers {
    <#
        Wallpaper source priority:
          1. themes\<theme>\wallpapers\   (theme-specific set)
          2. assets\wallpapers\           (base set)

        If the theme folder exists, it replaces the base set entirely — a
        theme that ships its own wallpapers wants those, not a mix.

        Each wallpaper is deployed through Backup-And-Deploy, so a file
        replacing a same-named user file gets a timestamped backup.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ThemeName
    )

    Write-Section 'Wallpapers'

    $themeSubdir = if ($ThemeName) { $ThemeName } else { 'mocha' }
    $destRoot    = Join-Path $WallpaperDir $themeSubdir

    $themeWallDir = if ($ThemeName) { Join-Path (Join-Path $ThemeRoot $ThemeName) 'wallpapers' } else { $null }
    $baseWallDir  = Join-Path $AssetRoot 'wallpapers'

    if ($themeWallDir -and (Test-Path -LiteralPath $themeWallDir)) {
        $src    = $themeWallDir
        $source = "theme '$ThemeName'"
    } else {
        $src    = $baseWallDir
        $source = 'base'
    }

    $files = @()
    if (Test-Path -LiteralPath $src) {
        $files = @(Get-ChildItem -LiteralPath $src -File -Recurse -ErrorAction SilentlyContinue)
    }

    if ($files.Count -eq 0) {
        Write-Skip "No wallpapers found ($source)."
        Add-Summary 'Skipped' "Wallpapers (no files — $source)"
        if (-not $DryRun -and -not (Test-Path -LiteralPath $WallpaperDir)) {
            New-Item -ItemType Directory -Path $WallpaperDir -Force | Out-Null
        }
        return
    }

    Write-Info "using wallpaper set: $source ($($files.Count) files)"

    foreach ($f in $files) {
        $relative     = $f.FullName.Substring($src.Length).TrimStart('\', '/')
        $destination  = Join-Path $destRoot $relative
        $relativeDir  = Split-Path -Parent $relative
        $backupSubdir = if ($relativeDir) {
            Join-Path (Join-Path 'wallpapers' $themeSubdir) $relativeDir
        } else {
            Join-Path 'wallpapers' $themeSubdir
        }

        Backup-And-Deploy `
            -Source       $f.FullName `
            -Destination  $destination `
            -Label        "Wallpaper: $relative" `
            -BackupSubdir $backupSubdir | Out-Null
    }

    # Set default wallpaper on first run (or when the theme changed).
    $manifest = if ($script:Manifest) { $script:Manifest } else { Get-Manifest }
    $script:Manifest = $manifest

    $default = Get-ChildItem -LiteralPath $src -File `
                    -Filter 'default.*' -ErrorAction SilentlyContinue |
                Select-Object -First 1

    if ($default) {
        Set-DefaultWallpaper -ImagePath (Join-Path $destRoot $default.Name) `
                             -Manifest  $manifest `
                             -ThemeName $ThemeName
    } else {
        Write-WarnLine "No 'default.*' file in wallpaper set — leaving desktop wallpaper unchanged."
    }
}

# ==================================================== RICE LAUNCHER

function Deploy-RiceLauncher {
    <#
        Create the `win-rice` launcher shim that opens the TUI (rice.ps1).

        The shim is a .cmd file placed in ~/.local/bin/. Windows resolves
        .CMD files from PATH via PATHEXT, but does NOT resolve .PS1 files,
        so a .cmd wrapper is required for `win-rice` to work from a shell
        or from Win+R.

        The shim prefers pwsh and falls back to powershell.exe, so it works
        on a fresh Windows install before PowerShell 7 is present.

        The repo path is baked into the shim at install time. If the repo
        is later moved, re-run install.ps1 from the new location to refresh
        the shim.

        ~/.local/bin/ is added to the user PATH if not already present. The
        existing per-tool folders under ~/.local/bin/ (thide, cmatrix-win,
        chronoterm, glaze-autotiler) keep their own PATH entries — this
        adds a shared parent for shims like win-rice that don't need their
        own folder.
    #>
    Write-Section 'Launcher'

    if (-not (Test-Path -LiteralPath $RiceScript)) {
        Write-Skip 'rice.ps1 not present in repo root — skipping launcher'
        Add-Summary 'Skipped' 'Launcher (rice.ps1 missing)'
        return
    }

    if ($DryRun) {
        Write-Skip "would create $LauncherPath"
        Write-Skip "would ensure $LocalBinDir is on user PATH"
        Add-Summary 'Configured' 'Launcher (dry run)'
        return
    }

    if (-not (Test-Path -LiteralPath $LocalBinDir)) {
        New-Item -ItemType Directory -Path $LocalBinDir -Force | Out-Null
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';' | Where-Object { $_ -ne '' }) -notcontains $LocalBinDir) {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$LocalBinDir", 'User')
        Write-Info "Added $LocalBinDir to user PATH"
    }

    # ASCII, CRLF, no BOM. The batch interpreter is picky about BOMs.
    $shimContent = @"
@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$RiceScript" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "$RiceScript" %*
)
"@

    try {
        Set-Content -LiteralPath $LauncherPath -Value $shimContent -Encoding ASCII -ErrorAction Stop
        Write-Ok 'win-rice launcher created'
        Add-Summary 'Configured' 'win-rice launcher'
    } catch {
        Write-FailLine "Could not create launcher: $_"
        Add-Summary 'Failed' "Launcher ($_)"
    }
}

# ===================================================== WINDOWS TERMINAL

function ConvertTo-DeepHashtable {
    param($InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string]) { return $InputObject }
    if ($InputObject -is [System.ValueType]) { return $InputObject }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = [ordered]@{}
        foreach ($k in @($InputObject.Keys)) {
            $h[$k] = ConvertTo-DeepHashtable $InputObject[$k]
        }
        return $h
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            [void]$list.Add((ConvertTo-DeepHashtable $item))
        }
        return ,$list.ToArray()
    }

    $h = [ordered]@{}
    foreach ($p in $InputObject.PSObject.Properties) {
        $h[$p.Name] = ConvertTo-DeepHashtable $p.Value
    }
    return $h
}

function Merge-ArrayByKey {
    param(
        [object[]]$BaseArray,
        [object[]]$PatchArray,
        [Parameter(Mandatory)][string]$KeyName
    )

    $result = New-Object System.Collections.ArrayList
    foreach ($x in @($BaseArray)) { [void]$result.Add($x) }

    foreach ($patch in @($PatchArray)) {
        if ($null -eq $patch) { continue }
        $key = $patch[$KeyName]
        $idx = -1
        for ($i = 0; $i -lt $result.Count; $i++) {
            if ($result[$i][$KeyName] -eq $key) { $idx = $i; break }
        }
        if ($idx -ge 0) {
            foreach ($k in $patch.Keys) { $result[$idx][$k] = $patch[$k] }
        } else {
            [void]$result.Add($patch)
        }
    }

    return ,$result.ToArray()
}

function Replace-ArrayEntriesByKey {
    param(
        [object[]]$BaseArray,
        [object[]]$PatchArray,
        [Parameter(Mandatory)][string]$KeyName
    )

    $patchKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($p in @($PatchArray)) {
        if ($null -eq $p) { continue }
        $k = [string]$p[$KeyName]
        if ($k) { [void]$patchKeys.Add($k) }
    }

    $result = New-Object System.Collections.ArrayList
    foreach ($x in @($BaseArray)) {
        if ($null -eq $x) { continue }
        $k = [string]$x[$KeyName]
        if (-not $patchKeys.Contains($k)) {
            [void]$result.Add($x)
        }
    }
    foreach ($p in @($PatchArray)) {
        if ($null -ne $p) { [void]$result.Add($p) }
    }

    return ,$result.ToArray()
}

function Get-WindowsTerminalSettingsPath {
    $pkg = $null
    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -ErrorAction Stop |
                Select-Object -First 1
    } catch {
        $pkg = $null
    }

    if ($pkg -and $pkg.PackageFamilyName) {
        $localState = Join-Path $env:LOCALAPPDATA "Packages\$($pkg.PackageFamilyName)\LocalState"
        if (Test-Path -LiteralPath $localState) {
            return (Join-Path $localState 'settings.json')
        }
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        $candidates = @(Get-ChildItem -LiteralPath $packagesRoot -Directory `
                            -Filter 'Microsoft.WindowsTerminal_*' -ErrorAction SilentlyContinue)
        if ($candidates.Count -eq 1) {
            $localState = Join-Path $candidates[0].FullName 'LocalState'
            if (Test-Path -LiteralPath $localState) {
                return (Join-Path $localState 'settings.json')
            }
        }
        if ($candidates.Count -gt 1) {
            Write-WarnLine 'Multiple Windows Terminal package folders detected:'
            foreach ($c in $candidates) {
                Write-Host "        · $($c.FullName)" -ForegroundColor DarkGray
            }
            Write-WarnLine 'Refusing to guess. Windows Terminal settings left untouched.'
        }
    }

    return $null
}

function Update-WindowsTerminalConfig {
    <#
        Source resolution: prefer themes\<theme>\terminal\settings.json,
        fall back to configs\terminal\settings.json. The destination is
        always the user's live Windows Terminal settings.json.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$ThemeName
    )

    Write-Section 'Windows Terminal'

    $themeRel   = 'terminal\settings.json'
    $sourcePath = Resolve-ThemeFile -ThemeName $ThemeName -RelPath $themeRel
    $marker     = Get-ThemeMarker   -ThemeName $ThemeName -RelPath $themeRel

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        Write-WarnLine "settings.json missing: $sourcePath"
        Add-Summary 'Skipped' 'Windows Terminal (repo file missing)'
        return
    }

    $wtSettingsPath = Get-WindowsTerminalSettingsPath
    if (-not $wtSettingsPath) {
        Write-WarnLine 'Could not determine the Windows Terminal settings location.'
        Write-WarnLine 'Launch Windows Terminal once, then re-run this script.'
        Add-Summary 'Skipped' 'Windows Terminal (settings location undetermined)'
        return
    }

    $wtSettingsDir = Split-Path -Parent $wtSettingsPath
    if (-not (Test-Path -LiteralPath $wtSettingsDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $wtSettingsDir -Force | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $wtSettingsPath)) {
        Write-Info "No existing settings.json — deploying repo settings verbatim$marker."
        Backup-And-Deploy -Source $sourcePath -Destination $wtSettingsPath `
                          -Label "Windows Terminal settings.json$marker" `
                          -BackupSubdir 'terminal'
        return
    }

    try {
        $userRaw = Get-Content -LiteralPath $wtSettingsPath -Raw -ErrorAction Stop
        $repoRaw = Get-Content -LiteralPath $sourcePath -Raw -ErrorAction Stop
        $userObj = $userRaw | ConvertFrom-Json -ErrorAction Stop
        $repoObj = $repoRaw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-WarnLine 'Cannot parse Windows Terminal settings.json.'
        Write-WarnLine 'The file may contain JSONC comments that PowerShell 5.1 cannot parse.'
        Write-WarnLine "Details: $_"
        Write-WarnLine 'Your existing settings.json was left untouched.'
        Add-Summary 'Skipped' 'Windows Terminal (settings.json unparseable — left untouched)'
        return
    }

    $user = ConvertTo-DeepHashtable $userObj
    $repo = ConvertTo-DeepHashtable $repoObj

    if (-not $user.Contains('profiles')) { $user['profiles'] = [ordered]@{} }
    if (-not $user['profiles'].Contains('defaults')) {
        $user['profiles']['defaults'] = [ordered]@{}
    }
    if (-not $user['profiles'].Contains('list')) {
        $user['profiles']['list'] = @()
    }

    if ($repo.Contains('profiles') -and $repo['profiles'].Contains('defaults')) {
        foreach ($k in $repo['profiles']['defaults'].Keys) {
            $user['profiles']['defaults'][$k] = $repo['profiles']['defaults'][$k]
        }
    }

    if ($repo.Contains('profiles') -and $repo['profiles'].Contains('list')) {
        $user['profiles']['list'] = Merge-ArrayByKey `
            -BaseArray  @($user['profiles']['list']) `
            -PatchArray @($repo['profiles']['list']) `
            -KeyName    'guid'
    }

    if ($repo.Contains('schemes')) {
        if (-not $user.Contains('schemes')) { $user['schemes'] = @() }
        $user['schemes'] = Merge-ArrayByKey `
            -BaseArray  @($user['schemes']) `
            -PatchArray @($repo['schemes']) `
            -KeyName    'name'
    }

    if ($repo.Contains('actions')) {
        if (-not $user.Contains('actions')) { $user['actions'] = @() }
        $user['actions'] = Replace-ArrayEntriesByKey `
            -BaseArray  @($user['actions']) `
            -PatchArray @($repo['actions']) `
            -KeyName    'id'
    }

    if ($repo.Contains('keybindings')) {
        if (-not $user.Contains('keybindings')) { $user['keybindings'] = @() }
        $user['keybindings'] = Replace-ArrayEntriesByKey `
            -BaseArray  @($user['keybindings']) `
            -PatchArray @($repo['keybindings']) `
            -KeyName    'id'
    }

    foreach ($k in @('defaultProfile', 'tabWidthMode', 'useAcrylicInTabRow')) {
        if ($repo.Contains($k)) { $user[$k] = $repo[$k] }
    }

    $json = $user | ConvertTo-Json -Depth 100

    try {
        $null = $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-FailLine 'Generated Windows Terminal JSON failed validation.'
        Write-WarnLine 'Leaving the original settings.json in place.'
        Add-Summary 'Failed' 'Windows Terminal (merge produced invalid JSON)'
        return
    }

    if ($DryRun) {
        Write-Skip "would merge rice settings into Windows Terminal settings.json$marker"
        Add-Summary 'Configured' 'Windows Terminal settings.json (dry run)'
        return
    }

    $backupDir  = Join-Path $BackupRoot 'terminal'
    $backupPath = Join-Path $backupDir ("settings.json.backup-" + (New-Timestamp))
    try {
        if (-not (Test-Path -LiteralPath $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $wtSettingsPath -Destination $backupPath -Force -ErrorAction Stop
        Write-Info "backup: $backupPath"
    } catch {
        Write-WarnLine "Could not back up Windows Terminal settings: $_"
    }

    try {
        # No BOM: WT parses this file as strict JSON in some code paths.
        Write-Utf8NoBom -Path $wtSettingsPath -Content $json
        Write-Ok "Windows Terminal settings.json merged$marker"
        Add-Summary 'Configured' 'Windows Terminal settings.json'
    } catch {
        Write-FailLine "Failed to write Windows Terminal settings: $_"
        Add-Summary 'Failed' 'Windows Terminal (write error)'
    }
}

# ==================================================== PSREADLINE

function Ensure-PSReadLine {
    param([switch]$NoInstall)

    Write-Section 'PSReadLine'

    $module = Get-Module -ListAvailable -Name PSReadLine -ErrorAction SilentlyContinue
    if ($module) {
        Write-Ok "PSReadLine available ($($module[0].Version))"
        Add-Summary 'AlreadyInstalled' 'PSReadLine'
        return
    }

    if ($NoInstall) {
        Write-Skip 'PSReadLine missing, but installation was skipped (-SkipPackages)'
        Add-Summary 'Skipped' 'PSReadLine (install skipped)'
        return
    }

    if ($DryRun) {
        Write-Skip 'would install PSReadLine for the current user'
        return
    }

    Write-Info 'PSReadLine not found — attempting per-user install...'
    try {
        Install-Module -Name PSReadLine -Scope CurrentUser -Force `
            -AllowClobber -SkipPublisherCheck -ErrorAction Stop
        Write-Ok 'PSReadLine installed'
        Add-Summary 'Installed' 'PSReadLine'
    } catch {
        Write-WarnLine "PSReadLine install failed: $_"
        Write-WarnLine 'Not fatal: PowerShell 7 bundles PSReadLine already.'
        Add-Summary 'Warnings' 'PSReadLine (optional install failed)'
    }
}

# ==================================================== UPDATE

function Invoke-RepoUpdate {
    <#
        Bring the local checkout up to date with origin/main.

        Uses fetch + explicit merge --ff-only instead of `git pull`, because:

            - `git pull` creates a merge commit when the local branch has
            diverged from the remote, and creating a commit requires a
            configured git identity. Fresh Windows installs have none,
            so the pull fails with "Committer identity unknown".
            - `git fetch` + `git merge --ff-only` never creates a commit on a
            clean fast-forward. No identity needed.

        If the local branch has diverged from origin (for example, because
        the remote history was rewritten to purge large binary files), the
        installer offers to reset the local branch to match origin. That
        discards local commits and uncommitted changes, so it prompts first.
    #>
    Write-Section 'Update'

    if (-not (Test-CommandExists 'git')) {
        Write-WarnLine 'git not found — cannot pull updates.'
        Add-Summary 'Skipped' 'Update (git not found)'
        return
    }

    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
        Write-WarnLine 'Repository has no .git folder — not a git checkout.'
        Write-WarnLine 'If this was downloaded as a ZIP, updates must be manual.'
        Add-Summary 'Skipped' 'Update (not a git repository)'
        return
    }

    if ($DryRun) {
        Write-Skip 'would fetch origin and reconcile the local branch'
        return
    }

    # ------------------------------------------------------------------
    # Step 1: fetch. Read-only with respect to the working tree, so it is
    # always safe to run first. Needs no identity.
    # ------------------------------------------------------------------
    Write-Info 'fetching from origin...'
    $fetchOut = (& git -C $RepoRoot fetch origin 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        Write-WarnLine "git fetch exited $LASTEXITCODE."
        foreach ($line in ($fetchOut -split "`r?`n" | Where-Object { $_ -ne '' })) {
            Write-Host "        $line" -ForegroundColor DarkGray
        }
        Add-Summary 'Warnings' 'Update (git fetch failed)'
        return
    }

    # ------------------------------------------------------------------
    # Step 2: inspect state. HEAD vs origin/main.
    # ------------------------------------------------------------------
    $localHead  = (& git -C $RepoRoot rev-parse HEAD 2>$null | Out-String).Trim()
    $remoteHead = (& git -C $RepoRoot rev-parse origin/main 2>$null | Out-String).Trim()

    if ($localHead -eq $remoteHead) {
        Write-Skip 'Already up to date'
        Add-Summary 'AlreadyInstalled' 'Repository update'
        return
    }

    & git -C $RepoRoot merge-base --is-ancestor HEAD origin/main 2>$null
    $localIsBehind = ($LASTEXITCODE -eq 0)

    & git -C $RepoRoot merge-base --is-ancestor origin/main HEAD 2>$null
    $localIsAhead = ($LASTEXITCODE -eq 0)

    # ------------------------------------------------------------------
    # Case 1: local is strictly behind. Fast-forward. No commit created.
    # ------------------------------------------------------------------
    if ($localIsBehind -and -not $localIsAhead) {
        Write-Info 'local is behind origin — fast-forwarding...'
        & git -C $RepoRoot merge --ff-only origin/main 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'Repository updated'
            Add-Summary 'Installed' 'Repository update'
        } else {
            Write-WarnLine "Fast-forward exited $LASTEXITCODE."
            Add-Summary 'Warnings' 'Update (fast-forward failed)'
        }
        return
    }

    # ------------------------------------------------------------------
    # Case 2: local is ahead. Nothing to pull — the remote is behind.
    # ------------------------------------------------------------------
    if ($localIsAhead -and -not $localIsBehind) {
        Write-Skip 'Local branch is ahead of origin — nothing to pull'
        Add-Summary 'AlreadyInstalled' 'Repository update (local ahead)'
        return
    }

    # ------------------------------------------------------------------
    # Case 3: neither is an ancestor of the other. Two sub-cases:
    #   - histories share a merge base  => genuinely diverged (local commits)
    #   - no merge base                 => unrelated (remote was rewritten)
    # ------------------------------------------------------------------
    $mergeBase = (& git -C $RepoRoot merge-base HEAD origin/main 2>$null | Out-String).Trim()

    if (-not $mergeBase) {
        Write-WarnLine 'Local branch and origin/main have no common history.'
        Write-WarnLine 'This usually means the remote history was rewritten'
        Write-WarnLine '(for example, to purge large binary files from old commits).'
    } else {
        Write-WarnLine 'Local branch and origin/main have diverged.'
        Write-WarnLine 'This means you have local commits that are not on the remote.'
    }

    # Show what a reset would discard (tracked changes only; untracked files
    # survive a `git reset --hard` and are not shown).
    $status = (& git -C $RepoRoot status --porcelain 2>$null | Out-String).Trim()
    $trackedChanges = @($status -split "`r?`n" | Where-Object { $_ -ne '' -and $_ -notmatch '^\?\?' })

    if ($trackedChanges.Count -gt 0) {
        Write-Host ''
        Write-WarnLine 'You also have uncommitted changes to tracked files:'
        $shown = $trackedChanges | Select-Object -First 5
        foreach ($line in $shown) {
            Write-Host "        $line" -ForegroundColor DarkGray
        }
        if ($trackedChanges.Count -gt 5) {
            Write-Host "        ... and $($trackedChanges.Count - 5) more" -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host '  The installer can reset your local branch to match origin/main.' -ForegroundColor Gray
    Write-Host '  This discards local commits and any uncommitted changes.' -ForegroundColor Gray
    Write-Host '  If you want to keep them, abort and resolve manually.' -ForegroundColor Gray
    Write-Host ''

    if (-not (Confirm-Action -Prompt 'Reset local branch to origin/main? Local commits and changes will be lost.' -Default $false)) {
        Write-Skip 'Update aborted. Repository unchanged.'
        Add-Summary 'Skipped' 'Update (diverged — user declined reset)'
        return
    }

    & git -C $RepoRoot reset --hard origin/main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'Repository reset to origin/main'
        Add-Summary 'Installed' 'Repository update (reset)'
    } else {
        Write-FailLine "git reset --hard exited $LASTEXITCODE"
        Add-Summary 'Failed' 'Update (reset failed)'
    }
}

# ==================================================== VERIFICATION

function Invoke-Verification {
    Write-Section 'Verification'

    Update-PathFromRegistry

    $commands = @(
        'pwsh',
        'fastfetch',
        'btop',
        'fd',
        'fzf',
        'rg',
        'yazi',
        'yt-dlp',
        'cava',
        'glazewm',
        'yasb',
        'thide',
        'chronoterm',
        'starship'
    )

    foreach ($cmd in $commands) {
        if (Test-CommandExists $cmd) {
            Write-Ok "$cmd on PATH"
        } else {
            Write-WarnLine "$cmd not found on PATH (a new shell may be required)"
        }
    }

    Write-Host ''
    Write-Info 'Checking deployed configuration files...'

    $files = @(
        (Join-Path $FastfetchDir 'config.jsonc'),
        (Join-Path $FastfetchDir 'ascii.txt'),
        (Join-Path $GlazeWmDir  'config.yaml'),
        (Join-Path $YasbDir     'config.yaml'),
        (Join-Path $YasbDir     'styles.css'),
        (Join-Path $CavaDir     'config'),
        $PwshProfilePath,
        $StarshipConfigPath
    )

    foreach ($f in $files) {
        if (Test-Path -LiteralPath $f) {
            Write-Ok $f
        } else {
            Write-FailLine "missing: $f"
            Add-Summary 'Failed' "config missing: $f"
        }
    }

    Write-Host ''
    Write-Info 'Checking launcher...'

    if (Test-Path -LiteralPath $LauncherPath) {
        Write-Ok $LauncherPath
    } else {
        Write-Skip "$LauncherPath not present (rice.ps1 missing, or launcher step skipped)"
    }
}

# ==================================================== SUMMARY

function Write-FinalSummary {
    param([string]$ActiveTheme)

    Write-Section 'Complete'

    $installed  = $script:Summary['Installed'].Count
    $already    = $script:Summary['AlreadyInstalled'].Count
    $configured = $script:Summary['Configured'].Count
    $skipped    = $script:Summary['Skipped'].Count
    $warnings   = $script:Summary['Warnings'].Count
    $failed     = $script:Summary['Failed'].Count

    $rows = @(
        @{ Label = 'Installed';       Value = $installed;  Color = 'Green' }
        @{ Label = 'Already present'; Value = $already;    Color = 'Gray' }
        @{ Label = 'Configured';      Value = $configured; Color = 'Green' }
        @{ Label = 'Skipped';         Value = $skipped;    Color = 'DarkGray' }
        @{ Label = 'Warnings';        Value = $warnings;   Color = 'Yellow' }
        @{ Label = 'Failed';          Value = $failed;     Color = 'Red' }
    )

    foreach ($r in $rows) {
        $valueColor = if ($r.Value -eq 0) { 'DarkGray' } else { $r.Color }
        Write-Host ('  ' + $r.Label.PadRight(18)) -NoNewline -ForegroundColor Gray
        Write-Host $r.Value -ForegroundColor $valueColor
    }

    Write-Host ''

    if ($failed -gt 0) {
        Write-Host '  ✗ Installation completed with errors.' -ForegroundColor Red
    } elseif ($warnings -gt 0) {
        Write-Host '  ▲ Installation completed with warnings.' -ForegroundColor Yellow
    } else {
        Write-Host '  ✓ Windows-Rice installation completed successfully.' -ForegroundColor Green
    }

    Write-Host ''

    if ($ActiveTheme) {
        Write-Host '  Active theme' -ForegroundColor Cyan
        Write-Host "    $ActiveTheme" -ForegroundColor Gray
        Write-Host ''
    }

    if (Test-Path -LiteralPath $LauncherPath) {
        Write-Host '  Launcher' -ForegroundColor Cyan
        Write-Host '    win-rice' -ForegroundColor Gray
        Write-Host '    (run in a new shell, or from Win+R)' -ForegroundColor DarkGray
        Write-Host ''
    }

    if (Test-Path -LiteralPath $BackupRoot) {
        Write-Host '  Backup location' -ForegroundColor Cyan
        Write-Host "    $BackupRoot" -ForegroundColor Gray
        if (Test-Path -LiteralPath $ManifestPath) {
            Write-Host "    $ManifestPath" -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    Write-Host '  Next steps' -ForegroundColor Cyan
    $nextSteps = @(
        'Close and reopen your terminal so PATH and font changes are loaded.',
        'Start (or restart) GlazeWM.',
        'YASB and GlazeWM AutoTiler launch automatically through GlazeWM.',
        'Thide hides the taskbar on next login.',
        'If Windows Terminal was already running, restart it.',
        'Log out or restart Windows only if something still does not refresh.'
    )
    for ($i = 0; $i -lt $nextSteps.Count; $i++) {
        Write-Host ('    ' + ($i + 1) + '. ') -NoNewline -ForegroundColor DarkCyan
        Write-Host $nextSteps[$i] -ForegroundColor Gray
    }
    Write-Host ''

    Write-Separator
    Write-Host ''
}

# ================================================================== MAIN

Write-Banner 'Installation & configuration'

# Sanity check: repository layout -------------------------------------------
$requiredPaths = @(
    (Join-Path $ConfigRoot 'yasb\default_yasb_config.yaml'),
    (Join-Path $ConfigRoot 'yasb\styles.css'),
    (Join-Path $ConfigRoot 'glazewm\default_glazewm_config.yaml'),
    (Join-Path $ConfigRoot 'cava\config'),
    (Join-Path $ConfigRoot 'fastfetch\config.jsonc'),
    (Join-Path $ConfigRoot 'fastfetch\ascii.txt'),
    (Join-Path $ConfigRoot 'powershell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $ConfigRoot 'terminal\settings.json'),
    (Join-Path $ConfigRoot 'starship\starship.toml')
)

$missing = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -gt 0) {
    Write-FailLine 'Repository layout is incomplete. Missing:'
    foreach ($m in $missing) { Write-Host "        · $m" -ForegroundColor Red }
    Write-Host ''
    Write-WarnLine 'Run install.ps1 from the repository root, or re-clone the repository.'
    exit 1
}

# ------------------------------------------------------------------
# Theme resolution
#
# 'mocha' is a reserved name: it's the base config set in configs\, not a
# folder under themes\. Passing -Theme mocha is equivalent to passing no
# theme at all — both use the base configs.
#
# $ThemeFolderName is the folder under themes\ to override from. Empty
# string means "use base configs only". It's what's passed to the deploy
# functions.
#
# $ActiveTheme is the display name shown in the env block and summary, and
# is what's recorded in the manifest.
# ------------------------------------------------------------------
$manifest = Get-Manifest
$script:Manifest = $manifest

# Did the user pass -Theme at all?
$themeExplicitlyProvided = $PSBoundParameters.ContainsKey('Theme')

# Normalize 'mocha' to empty (meaning "use base configs").
$requestedFolderName = if ($themeExplicitlyProvided -and $Theme -ne 'mocha') { $Theme } else { '' }

# If a non-mocha theme was requested, verify the folder exists.
if ($themeExplicitlyProvided -and $requestedFolderName) {
    $themeFolder = Join-Path $ThemeRoot $requestedFolderName
    if (-not (Test-Path -LiteralPath $themeFolder)) {
        Write-FailLine "Theme '$requestedFolderName' not found at themes\$requestedFolderName\"
        if (Test-Path -LiteralPath $ThemeRoot) {
            $available = @(Get-ChildItem -LiteralPath $ThemeRoot -Directory -ErrorAction SilentlyContinue |
                            Select-Object -ExpandProperty Name)
            Write-Host '    Available themes:' -ForegroundColor Gray
            Write-Host '        · mocha (base configs)' -ForegroundColor Gray
            foreach ($t in $available) { Write-Host "        · $t" -ForegroundColor Gray }
        }
        Write-Host ''
        exit 1
    }
}

# Resolve the folder name to deploy from.
if ($themeExplicitlyProvided) {
    # Explicit -Theme wins over any recorded preference.
    $ThemeFolderName = $requestedFolderName
} elseif ($manifest.preferences -and $manifest.preferences.theme -and $manifest.preferences.theme -ne 'mocha') {
    # Manifest has a non-mocha theme recorded; verify the folder still exists.
    $recorded = $manifest.preferences.theme
    if (Test-Path -LiteralPath (Join-Path $ThemeRoot $recorded)) {
        $ThemeFolderName = $recorded
    } else {
        Write-WarnLine "Recorded theme '$recorded' no longer exists — falling back to mocha."
        $ThemeFolderName = ''
    }
} else {
    # No explicit flag, no recorded non-mocha preference — use base configs.
    $ThemeFolderName = ''
}

# Display name always resolves to something readable.
$ActiveTheme = if ($ThemeFolderName) { $ThemeFolderName } else { 'mocha' }

Write-Section 'Windows-Rice • Install'
Write-EnvBlock -ActiveTheme $ActiveTheme

# 0. Update (opt-in) --------------------------------------------------------
if ($Update) {
    Invoke-RepoUpdate
}

# 1. Packages ---------------------------------------------------------------
if (-not $SkipPackages) {
    Install-AllPackages
} else {
    Write-Section 'Packages'
    Write-Skip 'Skipping all package installation (-SkipPackages)'
    Add-Summary 'Skipped' 'All packages (-SkipPackages)'
}

# 2. Font -------------------------------------------------------------------
if (-not $SkipFonts) {
    Write-Section 'Fonts'
    Install-RiceFont
} else {
    Write-Section 'Fonts'
    Write-Skip 'Skipping font installation'
    Add-Summary 'Skipped' 'JetBrainsMono Nerd Font (package installation disabled)'
}

# 3. Extras -----------------------------------------------------------------
if (-not $SkipPackages) {
    Install-Extras
} else {
    Write-Section 'Extras'
    Write-Skip 'Skipping all extras (-SkipPackages)'
    Add-Summary 'Skipped' 'Extras (all skipped by -SkipPackages)'
}

# 4. Configs ----------------------------------------------------------------
Deploy-AllConfigs -ThemeName $ThemeFolderName

# Record the resolved theme in the manifest.
$manifest = if ($script:Manifest) { $script:Manifest } else { Get-Manifest }
if (-not $manifest.preferences) { $manifest.preferences = [ordered]@{} }
if ($manifest.preferences.theme -ne $ActiveTheme) {
    $manifest.preferences.theme = $ActiveTheme
    $script:Manifest = $manifest
    Save-Manifest -Manifest $manifest
}

Deploy-Wallpapers -ThemeName $ThemeFolderName

# GlazeWM needs a nudge to re-read its config after a deploy. No-op if it
# isn't running.
Invoke-GlazeWmReload

# 5. Launcher ---------------------------------------------------------------
# Creates ~/.local/bin/win-rice.cmd and ensures ~/.local/bin is on user PATH.
# Runs even with -SkipPackages so a theme swap or config-only deploy still
# installs (or refreshes) the launcher.
Deploy-RiceLauncher

# 6. PSReadLine -------------------------------------------------------------
Ensure-PSReadLine -NoInstall:$SkipPSReadLineInstall

# 7. Windows Terminal -------------------------------------------------------
if (-not $SkipTerminal) {
    Update-WindowsTerminalConfig -ThemeName $ThemeFolderName
} else {
    Write-Section 'Windows Terminal'
    Write-Skip 'Skipping Windows Terminal (-SkipTerminal)'
    Add-Summary 'Skipped' 'Windows Terminal (-SkipTerminal)'
}

# 8. Verification -----------------------------------------------------------
Invoke-Verification

# 9. Summary ----------------------------------------------------------------
Write-FinalSummary -ActiveTheme $ActiveTheme