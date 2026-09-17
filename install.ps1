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

.PARAMETER SkipPackages
    Skip ALL package installation: winget, scoop, the Nerd Font, PSReadLine,
    and the extras (Thide, GlazeWM AutoTile, Flow Launcher, Windhawk). Only
    configuration files are deployed.

.PARAMETER SkipFonts
    Do not install the JetBrainsMono Nerd Font. Implied by -SkipPackages.

.PARAMETER SkipTerminal
    Do not touch Windows Terminal's settings.json.

.PARAMETER DryRun
    Print what would happen without installing or changing anything.

.PARAMETER Yes
    Assume "yes" for confirmation prompts (non-interactive install).

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
    [switch]$Yes
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
$AssetRoot  = Join-Path $RepoRoot 'assets'

$HomeDir        = $env:USERPROFILE
$DocumentsDir   = [Environment]::GetFolderPath('MyDocuments')
$PwshProfileDir = Join-Path $DocumentsDir 'PowerShell'
$PwshProfilePath= Join-Path $PwshProfileDir 'Microsoft.PowerShell_profile.ps1'

$YasbDir       = Join-Path $HomeDir '.config\yasb'
$GlazeWmDir    = Join-Path $HomeDir '.glzr\glazewm'
$CavaDir       = Join-Path $HomeDir '.config\cava'
$FastfetchDir  = Join-Path $HomeDir '.config\fastfetch'
$WallpaperDir  = Join-Path $HomeDir 'Pictures\Windows-Rice'
$BackupRoot    = Join-Path $HomeDir '.windows-rice-backup'
$ManifestPath  = Join-Path $BackupRoot 'manifest.json'

# -SkipPackages also disables the font install and the PSReadLine install.
if ($SkipPackages) { $SkipFonts = $true }
$SkipPSReadLineInstall = [bool]$SkipPackages

# In-memory manifest state (see Register-ManifestPackage / Save-Manifest).
$script:Manifest      = $null

# ================================================================== LOGGING

$script:Sep = '─' * 60

function Write-Separator {
    Write-Host $script:Sep -ForegroundColor Cyan
}

function Write-Banner {
    param([string]$Subtitle = '')
    Write-Host ''
    Write-Host '██╗    ██╗██╗███╗   ██╗██████╗  ██████╗ ██╗    ██╗███████╗' -ForegroundColor Magenta
    Write-Host '██║    ██║██║████╗  ██║██╔══██╗██╔═══██╗██║    ██║██╔════╝' -ForegroundColor Magenta
    Write-Host '██║ █╗ ██║██║██╔██╗ ██║██║  ██║██║   ██║██║ █╗ ██║███████╗' -ForegroundColor Magenta
    Write-Host '██║███╗██║██║██║╚██╗██║██║  ██║██║   ██║██║███╗██║╚════██║' -ForegroundColor Magenta
    Write-Host '╚███╔███╔╝██║██║ ╚████║██████╔╝╚██████╔╝╚███╔███╔╝███████║' -ForegroundColor Magenta
    Write-Host ' ╚══╝╚══╝ ╚═╝╚═╝  ╚════╝╚═════╝  ╚═════╝  ╚══╝╚══╝ ╚══════╝' -ForegroundColor Magenta
    Write-Host ''
    Write-Host '                    WINDOWS-RICE' -ForegroundColor Magenta
    if ($Subtitle) {
        Write-Host "              $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Separator
    Write-Host "  $($Title.ToUpper())" -ForegroundColor Cyan
    Write-Separator
    Write-Host ''
}

function Write-EnvBlock {
    Write-Host '  Environment' -ForegroundColor Cyan
    Write-Host ('    ' + 'Home'.PadRight(11) + $HomeDir) -ForegroundColor Gray
    Write-Host ('    ' + 'Repository'.PadRight(11) + $RepoRoot) -ForegroundColor Gray
    if ($DryRun) {
        Write-Host ('    ' + 'Dry Run'.PadRight(11) + 'YES — no changes will be made') -ForegroundColor Yellow
    } else {
        Write-Host ('    ' + 'Dry Run'.PadRight(11) + 'No') -ForegroundColor Gray
    }
    Write-Host ''
}

function Write-Ok       { param([string]$m) Write-Host ('  ' + '[OK]'.PadRight(6) + ' ' + $m) -ForegroundColor Green }
function Write-Skip     { param([string]$m) Write-Host ('  ' + '[SKIP]'.PadRight(6) + ' ' + $m) -ForegroundColor DarkGray }
function Write-WarnLine { param([string]$m) Write-Host ('  ' + '[WARN]'.PadRight(6) + ' ' + $m) -ForegroundColor Yellow }
function Write-FailLine { param([string]$m) Write-Host ('  ' + '[FAIL]'.PadRight(6) + ' ' + $m) -ForegroundColor Red }
function Write-Info     { param([string]$m) Write-Host ('  ' + '[INFO]'.PadRight(6) + ' ' + $m) -ForegroundColor Gray }

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

function Test-WingetPackageInstalled {
    param([string]$Id)
    try {
        $out = (& winget list --id $Id --exact --accept-source-agreements 2>&1 | Out-String)
    } catch {
        return $false
    }
    return ($out -match [regex]::Escape($Id))
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
        $out = (& winget install --id $Id --exact --silent `
                    --accept-package-agreements --accept-source-agreements 2>&1 |
                Out-String)
    } catch {
        Write-FailLine "$Name — $_"
        Add-Summary 'Failed' "$Name ($_)"
        return $false
    }

    if ($LASTEXITCODE -eq 0) {
        if ($out -match 'already installed') {
            Write-Skip "$Name already installed"
            Add-Summary 'AlreadyInstalled' $Name
        } else {
            Write-Ok $Name
            Add-Summary 'Installed' $Name
            Register-ManifestPackage -Manager 'winget' -Id $Id
        }
        return $true
    }

    # 0x8A150061 (-1978335135) = winget "no applicable upgrade".
    if ($out -match 'already installed' -or $LASTEXITCODE -eq -1978335135) {
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

    try {
        $out = (& scoop bucket add $Bucket 2>&1 | Out-String)
    } catch {
        Write-WarnLine "scoop bucket add $Bucket — $_"
        Add-Summary 'Warnings' "scoop bucket $Bucket ($_)"
        return
    }

    if ($out -match 'already exists') {
        Write-Skip "scoop bucket '$Bucket' already present"
        return
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "scoop bucket '$Bucket' added"
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
        # Core rice components (winget).
        Install-WingetPackage -Id 'Microsoft.PowerShell'      -Name 'PowerShell 7'
        Install-WingetPackage -Id 'Microsoft.WindowsTerminal' -Name 'Windows Terminal'
        Install-WingetPackage -Id 'glzr-io.glazewm'           -Name 'GlazeWM'
        Install-WingetPackage -Id 'AmN.yasb'                  -Name 'YASB'
        Install-WingetPackage -Id 'karlstav.cava'             -Name 'Cava'

        # CLI tooling (winget).
        Install-WingetPackage -Id 'aristocratos.btop4win'     -Name 'btop4win'
        Install-WingetPackage -Id 'sharkdp.fd'                -Name 'fd'
        Install-WingetPackage -Id 'junegunn.fzf'              -Name 'fzf'
        Install-WingetPackage -Id 'BurntSushi.ripgrep.MSVC'   -Name 'ripgrep'
        Install-WingetPackage -Id 'yt-dlp.yt-dlp'             -Name 'yt-dlp'

        # Yazi + supporting dependencies (winget).
        Install-WingetPackage -Id 'sxyazi.yazi'               -Name 'Yazi'
        Install-WingetPackage -Id 'Gyan.FFmpeg'               -Name 'FFmpeg'
        Install-WingetPackage -Id '7zip.7zip'                 -Name '7-Zip'
        Install-WingetPackage -Id 'jqlang.jq'                 -Name 'jq'
        Install-WingetPackage -Id 'ajeetdsouza.zoxide'        -Name 'zoxide'
        Install-WingetPackage -Id 'ImageMagick.ImageMagick'   -Name 'ImageMagick'
    }

    Write-Section 'Scoop packages'

    $scoopOk = Ensure-Scoop
    if ($scoopOk) {
        Add-ScoopBucket -Bucket 'extras'
        Add-ScoopBucket -Bucket 'nerd-fonts'
        Install-ScoopPackage -Name 'fastfetch' -Display 'Fastfetch'
    } else {
        Write-WarnLine 'Skipping Scoop-based installs (Fastfetch).'
        Add-Summary 'Skipped' 'Fastfetch (Scoop unavailable)'
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

    # Canonical: JetBrainsMono Nerd Font Mono. Fallback: non-Mono variant.
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

# ======================================================== EXTRAS (1.1)

function Install-Thide {
    <#
        Thide — taskbar hide/show. Not on winget or scoop. Downloads the
        pinned portable ZIP from GitHub releases and extracts to
        ~/.local/bin/thide/. Enables autostart so the taskbar stays hidden
        across logins.

        To update: change $version below to match the release tag on
        https://github.com/amnweb/thide/releases, and adjust the asset
        filename if the naming convention changes.
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
        if ($userPath -notlike "*$thideDir*") {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$thideDir", 'User')
            Write-Info "Added $thideDir to user PATH"
        }

        # Register autostart so the taskbar stays hidden across reboots.
        if (Test-Path -LiteralPath $thideExe) {
            & $thideExe enable-autostart 2>&1 | Out-Null
        }

        Write-Ok 'Thide installed'
        Add-Summary 'Installed' 'Thide'
        Register-ManifestPackage -Manager 'direct' -Id 'thide'
    } catch {
        Write-FailLine "Thide — $_"
        Add-Summary 'Failed' "Thide ($_)"
    }
}

function Install-GlazeAutoTile {
    <#
        GlazeWM AutoTile — Python script that connects to GlazeWM's IPC
        WebSocket and picks smarter split directions than the default row
        behavior. Cloned from GitHub and run inside a dedicated venv.

        Requires:
        - git on PATH (used to clone the repo)
        - Python 3.10+ on PATH (used to create the venv and install deps)
        - GlazeWM IPC enabled (the config we ship already has this)

        The entry point is assumed to be `glaze_autotile.py`. If the upstream
        repo renames it, update $autotileEntry below.
    #>
    $autotileDir   = Join-Path $HomeDir '.local\share\glaze-autotile'
    $venvDir       = Join-Path $autotileDir '.venv'
    $autotileEntry = 'glaze_autotile.py'
    $autotilePy    = Join-Path $autotileDir $autotileEntry
    $pythonw       = Join-Path $venvDir 'Scripts\pythonw.exe'

    Write-Section 'GlazeWM AutoTile'

    if ((Test-Path -LiteralPath $autotilePy) -and (Test-Path -LiteralPath $pythonw)) {
        Write-Skip 'GlazeWM AutoTile already installed'
        Add-Summary 'AlreadyInstalled' 'GlazeWM AutoTile'
        return
    }

    if (-not (Test-CommandExists 'git')) {
        Write-WarnLine 'git not found — skipping GlazeWM AutoTile.'
        Write-WarnLine 'Install git, then re-run this script.'
        Add-Summary 'Skipped' 'GlazeWM AutoTile (git not found)'
        return
    }

    if (-not (Test-CommandExists 'python')) {
        Write-WarnLine 'Python not found — skipping GlazeWM AutoTile.'
        Write-WarnLine 'Install Python 3.10+ and re-run to enable AutoTile.'
        Add-Summary 'Skipped' 'GlazeWM AutoTile (Python not found)'
        return
    }

    if ($DryRun) {
        Write-Skip 'would clone AutoTile, create venv, install websockets'
        Add-Summary 'Installed' 'GlazeWM AutoTile (dry run)'
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $autotileDir)) {
            New-Item -ItemType Directory -Path $autotileDir -Force | Out-Null
        }

        # Clone into a temp location, then move contents (so re-running on a
        # partial install doesn't fail because the dir isn't empty).
        $tmpClone = Join-Path $env:TEMP "glaze-autotile-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        Write-Info 'cloning AutoTile...'
        & git clone --depth 1 https://github.com/aka-phrankie/GlazeWM_AutoTile.git $tmpClone 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git clone exited $LASTEXITCODE" }

        Copy-Item -Path (Join-Path $tmpClone '*') -Destination $autotileDir -Recurse -Force
        Remove-Item -LiteralPath $tmpClone -Recurse -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path -LiteralPath $autotilePy)) {
            throw "entry point '$autotileEntry' not found after clone"
        }

        Write-Info 'creating virtual environment...'
        & python -m venv $venvDir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "python -m venv exited $LASTEXITCODE" }

        Write-Info 'installing websockets...'
        $pip = Join-Path $venvDir 'Scripts\pip.exe'
        & $pip install --quiet --upgrade pip 2>&1 | Out-Null
        & $pip install --quiet websockets 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "pip install websockets exited $LASTEXITCODE" }

        Write-Ok 'GlazeWM AutoTile installed'
        Add-Summary 'Installed' 'GlazeWM AutoTile'
        Register-ManifestPackage -Manager 'direct' -Id 'glaze-autotile'
    } catch {
        Write-FailLine "GlazeWM AutoTile — $_"
        Add-Summary 'Failed' "GlazeWM AutoTile ($_)"
    }
}

function Install-FlowLauncher {
    if (-not (Test-CommandExists 'scoop')) {
        Write-Skip 'Scoop unavailable — cannot install Flow Launcher'
        Add-Summary 'Skipped' 'Flow Launcher (Scoop unavailable)'
        return
    }
    Install-ScoopPackage -Name 'flow-launcher' -Display 'Flow Launcher'
}

function Install-Windhawk {
    <#
        Windhawk — mod platform for Windows shell components.
        Installs the platform only. No mods are auto-installed; see README
        for the reasoning (mods run in-process and can crash Explorer).
    #>
    Install-WingetPackage -Id 'RamenSoftware.Windhawk' -Name 'Windhawk'
    Write-Info 'Windhawk installed. No mods are installed by default.'
    Write-Info 'Open Windhawk to browse and install mods manually.'
}

function Install-Extras {
    Install-Thide
    Install-GlazeAutoTile
    Install-FlowLauncher
    Install-Windhawk
}

# ======================================================= CONFIG DEPLOYMENT

function Deploy-AllConfigs {

    Write-Section 'Deploying configurations'

    # YASB
    Backup-And-Deploy `
        -Source       (Join-Path $ConfigRoot 'yasb\default_yasb_config.yaml') `
        -Destination  (Join-Path $YasbDir   'config.yaml') `
        -Label        '~/.config/yasb/config.yaml' `
        -BackupSubdir 'yasb'

    Backup-And-Deploy `
        -Source       (Join-Path $ConfigRoot 'yasb\styles.css') `
        -Destination  (Join-Path $YasbDir   'styles.css') `
        -Label        '~/.config/yasb/styles.css' `
        -BackupSubdir 'yasb'

    # GlazeWM
    Backup-And-Deploy `
        -Source       (Join-Path $ConfigRoot 'glazewm\default_glazewm_config.yaml') `
        -Destination  (Join-Path $GlazeWmDir 'config.yaml') `
        -Label        '~/.glzr/glazewm/config.yaml' `
        -BackupSubdir 'glazewm'

    # Cava — path confirmed: ~/.config/cava/config is read by karlstav.cava
    # on Windows as well as on Linux.
    Backup-And-Deploy `
        -Source       (Join-Path $ConfigRoot 'cava\config') `
        -Destination  (Join-Path $CavaDir    'config') `
        -Label        '~/.config/cava/config' `
        -BackupSubdir 'cava'

    # Fastfetch — canonical location is ~/.config/fastfetch only.
    Backup-And-Deploy `
        -Source       (Join-Path $ConfigRoot 'fastfetch\config.jsonc') `
        -Destination  (Join-Path $FastfetchDir 'config.jsonc') `
        -Label        '~/.config/fastfetch/config.jsonc' `
        -BackupSubdir 'fastfetch'

    Backup-And-Deploy `
        -Source       (Join-Path $ConfigRoot 'fastfetch\ascii.txt') `
        -Destination  (Join-Path $FastfetchDir 'ascii.txt') `
        -Label        '~/.config/fastfetch/ascii.txt' `
        -BackupSubdir 'fastfetch'

    # PowerShell profile
    if (-not (Test-Path -LiteralPath $PwshProfileDir)) {
        if ($DryRun) {
            Write-Skip "would create $PwshProfileDir"
        } else {
            New-Item -ItemType Directory -Path $PwshProfileDir -Force | Out-Null
        }
    }

    Backup-And-Deploy `
        -Source       (Join-Path $ConfigRoot 'powershell\Microsoft.PowerShell_profile.ps1') `
        -Destination  $PwshProfilePath `
        -Label        'PowerShell profile' `
        -BackupSubdir 'powershell'
}

function Set-DefaultWallpaper {
    <#
        Sets the desktop wallpaper once, on the first run. Subsequent runs
        respect whatever the user has chosen since.

        Uses SystemParametersInfo (the Win32 API) rather than RUNDLL32,
        because RUNDLL32 is unreliable on Windows 10/11 and doesn't always
        commit the change to the registry.
    #>
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)]$Manifest
    )

        if ($Manifest.preferences -and $Manifest.preferences.default_wallpaper_set) {
        Write-Skip 'Default wallpaper already applied on a previous run'
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
            $Manifest.preferences.default_wallpaper_set = $true
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
        Deploy bundled wallpapers one file at a time via Backup-And-Deploy so
        each file gets the same backup protection as other config files.
        Backup subdir mirrors the wallpaper's relative path under
        assets/wallpapers/, e.g. assets/wallpapers/dark/x.jpg →
        ~/.windows-rice-backup/wallpapers/dark/x.jpg.backup-<ts>.

        After deployment, a file named `default.*` (any image extension) is
        set as the desktop wallpaper on first run.
    #>
    Write-Section 'Wallpapers'

    $src = Join-Path $AssetRoot 'wallpapers'
    $files = @()
    if (Test-Path -LiteralPath $src) {
        $files = @(Get-ChildItem -LiteralPath $src -File -Recurse -ErrorAction SilentlyContinue)
    }

    if ($files.Count -eq 0) {
        Write-Skip 'No wallpapers bundled in the repository yet.'
        Add-Summary 'Skipped' 'Wallpapers (no files in repo)'
        if (-not $DryRun -and -not (Test-Path -LiteralPath $WallpaperDir)) {
            New-Item -ItemType Directory -Path $WallpaperDir -Force | Out-Null
        }
        return
    }

    foreach ($f in $files) {
        $relative = $f.FullName.Substring($src.Length).TrimStart('\', '/')
        $destination = Join-Path $WallpaperDir $relative

        $relativeDir = Split-Path -Parent $relative
        $backupSubdir = if ($relativeDir) { Join-Path 'wallpapers' $relativeDir } else { 'wallpapers' }

        Backup-And-Deploy `
            -Source       $f.FullName `
            -Destination  $destination `
            -Label        "Wallpaper: $relative" `
            -BackupSubdir $backupSubdir | Out-Null
    }

    # Set a default wallpaper on first run.
    $manifest = if ($script:Manifest) { $script:Manifest } else { Get-Manifest }
    $script:Manifest = $manifest

    $default = Get-ChildItem -LiteralPath $src -File `
                    -Filter 'default.*' -ErrorAction SilentlyContinue |
                Select-Object -First 1

    if ($default) {
        Set-DefaultWallpaper -ImagePath (Join-Path $WallpaperDir $default.Name) `
                             -Manifest $manifest
    }
}

# ===================================================== WINDOWS TERMINAL

function ConvertTo-DeepHashtable {
    <#
        ConvertFrom-Json on PS 5.1 returns PSCustomObject, which is painful to
        mutate. Convert recursively into ordered dictionaries so merging by key
        is straightforward.
    #>
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
    <#
        Merge two arrays of dictionaries keyed by a single property.
        Base items are kept. Patch items whose key matches a base item merge
        their fields onto the base item (patch wins). Patch items without a
        match are appended. Idempotent.
    #>
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
    <#
        Deterministic replacement of rice-owned entries.
        Any base entry whose KeyName value appears in the patch array is
        removed entirely, then all patch entries are appended. Base entries
        with keys not present in the patch are preserved untouched.
    #>
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
    <#
        Determine the settings.json path for the installed Windows Terminal
        package. Prefer the AppxPackage identity (PackageFamilyName) which is
        the authoritative source. Fall back to a folder scan only when the
        Appx API is unavailable, and only when exactly one candidate exists.
    #>
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
                Write-Host "        - $($c.FullName)" -ForegroundColor DarkGray
            }
            Write-WarnLine 'Refusing to guess. Windows Terminal settings left untouched.'
        }
    }

    return $null
}

function Update-WindowsTerminalConfig {
    param([Parameter(Mandatory)][string]$RepoSettingsPath)

    Write-Section 'Windows Terminal'

    if (-not (Test-Path -LiteralPath $RepoSettingsPath)) {
        Write-WarnLine "repo settings.json missing: $RepoSettingsPath"
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

    # Fresh install of Windows Terminal: no existing settings.json.
    if (-not (Test-Path -LiteralPath $wtSettingsPath)) {
        Write-Info 'No existing settings.json — deploying repo settings verbatim.'
        Backup-And-Deploy -Source $RepoSettingsPath -Destination $wtSettingsPath `
                          -Label 'Windows Terminal settings.json' `
                          -BackupSubdir 'terminal'
        return
    }

    try {
        $userRaw = Get-Content -LiteralPath $wtSettingsPath -Raw -ErrorAction Stop
        $repoRaw = Get-Content -LiteralPath $RepoSettingsPath -Raw -ErrorAction Stop
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

    # ---- profiles ---------------------------------------------------------
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

    # ---- schemes ----------------------------------------------------------
    if ($repo.Contains('schemes')) {
        if (-not $user.Contains('schemes')) { $user['schemes'] = @() }
        $user['schemes'] = Merge-ArrayByKey `
            -BaseArray  @($user['schemes']) `
            -PatchArray @($repo['schemes']) `
            -KeyName    'name'
    }

    # ---- actions ----------------------------------------------------------
    if ($repo.Contains('actions')) {
        if (-not $user.Contains('actions')) { $user['actions'] = @() }
        $user['actions'] = Replace-ArrayEntriesByKey `
            -BaseArray  @($user['actions']) `
            -PatchArray @($repo['actions']) `
            -KeyName    'id'
    }

    # ---- keybindings ------------------------------------------------------
    if ($repo.Contains('keybindings')) {
        if (-not $user.Contains('keybindings')) { $user['keybindings'] = @() }
        $user['keybindings'] = Replace-ArrayEntriesByKey `
            -BaseArray  @($user['keybindings']) `
            -PatchArray @($repo['keybindings']) `
            -KeyName    'id'
    }

    # ---- top-level scalars (rice wins) -----------------------------------
    foreach ($k in @('defaultProfile', 'tabWidthMode', 'useAcrylicInTabRow')) {
        if ($repo.Contains($k)) { $user[$k] = $repo[$k] }
    }

    # ---- serialize + validate --------------------------------------------
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
        Write-Skip 'would merge rice settings into Windows Terminal settings.json'
        Add-Summary 'Configured' 'Windows Terminal settings.json (dry run)'
        return
    }

    # ---- backup under $BackupRoot\terminal\ ------------------------------
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
        Set-Content -LiteralPath $wtSettingsPath -Value $json -Encoding UTF8 -ErrorAction Stop
        Write-Ok 'Windows Terminal settings.json merged'
        Add-Summary 'Configured' 'Windows Terminal settings.json'
    } catch {
        Write-FailLine "Failed to write Windows Terminal settings: $_"
        Add-Summary 'Failed' 'Windows Terminal (write error)'
    }
}

# ==================================================== PSREADLINE (BEST EFFORT)

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

# ============================================================ VERIFICATION

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
        'thide'
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
        $PwshProfilePath
    )

    foreach ($f in $files) {
        if (Test-Path -LiteralPath $f) {
            Write-Ok $f
        } else {
            Write-FailLine "missing: $f"
            Add-Summary 'Failed' "config missing: $f"
        }
    }
}

# =============================================================== SUMMARY

function Write-FinalSummary {
    Write-Section 'Complete'

    $installed  = $script:Summary['Installed'].Count
    $already    = $script:Summary['AlreadyInstalled'].Count
    $configured = $script:Summary['Configured'].Count
    $skipped    = $script:Summary['Skipped'].Count
    $warnings   = $script:Summary['Warnings'].Count
    $failed     = $script:Summary['Failed'].Count

    $rows = @(
        @{ Label = 'Installed';       Value = $installed },
        @{ Label = 'Already present'; Value = $already },
        @{ Label = 'Configured';      Value = $configured },
        @{ Label = 'Skipped';         Value = $skipped },
        @{ Label = 'Warnings';        Value = $warnings },
        @{ Label = 'Failed';          Value = $failed }
    )

    foreach ($r in $rows) {
        Write-Host ('  ' + $r.Label.PadRight(16) + $r.Value) -ForegroundColor Gray
    }

    Write-Host ''

    if ($failed -gt 0) {
        Write-Host '  [FAIL] Installation completed with errors.' -ForegroundColor Red
    } elseif ($warnings -gt 0) {
        Write-Host '  [WARN] Installation completed with warnings.' -ForegroundColor Yellow
    } else {
        Write-Host '  Windows-Rice installation completed successfully.' -ForegroundColor Green
    }

    Write-Host ''

    if (Test-Path -LiteralPath $BackupRoot) {
        Write-Host '  Backup location' -ForegroundColor Cyan
        Write-Host "    $BackupRoot" -ForegroundColor Gray
        if (Test-Path -LiteralPath $ManifestPath) {
            Write-Host "    $ManifestPath" -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    Write-Host '  Next steps' -ForegroundColor Cyan
    Write-Host '    1. Close and reopen your terminal so PATH and font changes are loaded.' -ForegroundColor Gray
    Write-Host '    2. Start (or restart) GlazeWM.' -ForegroundColor Gray
    Write-Host '    3. YASB and GlazeWM AutoTile launch automatically through GlazeWM.' -ForegroundColor Gray
    Write-Host '    4. Thide hides the taskbar on next login.' -ForegroundColor Gray
    Write-Host '    5. If Windows Terminal was already running, restart it.' -ForegroundColor Gray
    Write-Host '    6. Log out or restart Windows only if something still does not refresh.' -ForegroundColor Gray
    Write-Host ''

    Write-Separator
    Write-Host ''
}

# ================================================================== MAIN

Write-Banner 'Installation & configuration'
Write-Section 'Windows-Rice • Install'
Write-EnvBlock

# Sanity check: repository layout -------------------------------------------
$requiredPaths = @(
    (Join-Path $ConfigRoot 'yasb\default_yasb_config.yaml'),
    (Join-Path $ConfigRoot 'yasb\styles.css'),
    (Join-Path $ConfigRoot 'glazewm\default_glazewm_config.yaml'),
    (Join-Path $ConfigRoot 'cava\config'),
    (Join-Path $ConfigRoot 'fastfetch\config.jsonc'),
    (Join-Path $ConfigRoot 'fastfetch\ascii.txt'),
    (Join-Path $ConfigRoot 'powershell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $ConfigRoot 'terminal\settings.json')
)

$missing = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -gt 0) {
    Write-FailLine 'Repository layout is incomplete. Missing:'
    foreach ($m in $missing) { Write-Host "        - $m" -ForegroundColor Red }
    Write-Host ''
    Write-WarnLine 'Run install.ps1 from the repository root, or re-clone the repository.'
    exit 1
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

# 3. Extras (Thide, AutoTile, Flow Launcher, Windhawk) ---------------------
if (-not $SkipPackages) {
    Install-Extras
} else {
    Write-Section 'Extras'
    Write-Skip 'Skipping Thide, AutoTile, Flow Launcher, Windhawk (-SkipPackages)'
    Add-Summary 'Skipped' 'Extras (Thide, AutoTile, Flow Launcher, Windhawk)'
}

# 4. Configs ----------------------------------------------------------------
Deploy-AllConfigs
Deploy-Wallpapers

# 5. PSReadLine -------------------------------------------------------------
Ensure-PSReadLine -NoInstall:$SkipPSReadLineInstall

# 6. Windows Terminal -------------------------------------------------------
if (-not $SkipTerminal) {
    Update-WindowsTerminalConfig -RepoSettingsPath (Join-Path $ConfigRoot 'terminal\settings.json')
} else {
    Write-Section 'Windows Terminal'
    Write-Skip 'Skipping Windows Terminal (-SkipTerminal)'
    Add-Summary 'Skipped' 'Windows Terminal (-SkipTerminal)'
}

# 7. Verification -----------------------------------------------------------
Invoke-Verification

# 8. Summary ----------------------------------------------------------------
Write-FinalSummary