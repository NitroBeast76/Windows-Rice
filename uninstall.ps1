<#
.SYNOPSIS
    Reverts changes made by the Windows-Rice installer.

.DESCRIPTION
    Restores per-user configuration files (including bundled wallpapers) from
    the timestamped backups created by install.ps1, and (optionally) uninstalls
    the packages that install.ps1 actually installed.

    Package removal is driven by
    %USERPROFILE%\.windows-rice-backup\manifest.json, which install.ps1 writes
    only for packages it installed on the current machine. Packages that were
    already present before the rice installer ran are NOT removed.

    Three categories of package are tracked:
    - winget   — installed via winget (GlazeWM, YASB, Cava, and the CLI tools)
    - scoop    — installed via scoop  (Fastfetch, Nerd Font, Flow Launcher)
    - direct   — installed by the rice itself from a pinned source
                 (Thide and GlazeWM AutoTiler, both from GitHub releases)

    PowerShell 7 and Windows Terminal are never removed, even if the manifest
    records them. Removing PowerShell 7 breaks Windows Terminal, which is
    configured to launch it as the default profile. Remove those two manually
    with `winget uninstall` if you want them gone.

    Windows Terminal's settings.json is restored from its backup. If no backup
    exists, the file is left untouched.

.PARAMETER RemovePackages
    Also uninstall the packages recorded in the installation manifest.
    PowerShell 7 and Windows Terminal are intentionally NOT removed.

.PARAMETER Purge
    After restoring, delete the entire backup directory
    (~/.windows-rice-backup), including the installation manifest. This
    removes all restore points.

.PARAMETER DryRun
    Print what would happen without changing anything.

.PARAMETER Yes
    Assume "yes" for confirmation prompts.

.NOTES
    Repository:  Windows-Rice
    Requires:    PowerShell 5.1+ (Windows 10 / 11)
    No hardcoded usernames, machine names, or clone paths.
#>

[CmdletBinding()]
param(
    [switch]$RemovePackages,
    [switch]$Purge,
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

$HomeDir        = $env:USERPROFILE
$DocumentsDir   = [Environment]::GetFolderPath('MyDocuments')
$PwshProfilePath= Join-Path $DocumentsDir 'PowerShell\Microsoft.PowerShell_profile.ps1'

$YasbConfigPath      = Join-Path $HomeDir '.config\yasb\config.yaml'
$YasbStylesPath      = Join-Path $HomeDir '.config\yasb\styles.css'
$GlazeWmConfigPath   = Join-Path $HomeDir '.glzr\glazewm\config.yaml'
$CavaConfigPath      = Join-Path $HomeDir '.config\cava\config'
$FastfetchConfigPath = Join-Path $HomeDir '.config\fastfetch\config.jsonc'
$FastfetchAsciiPath  = Join-Path $HomeDir '.config\fastfetch\ascii.txt'

# Pictures folder resolution must match install.ps1 exactly, so that on a
# Microsoft-account machine (OneDrive redirection) the uninstaller looks in
# the same place the installer wrote to.
$PicturesDir         = [Environment]::GetFolderPath('MyPictures')
$WallpaperDir        = Join-Path $PicturesDir 'Windows-Rice'

# Direct install locations (must match install.ps1).
$ThideDir      = Join-Path $HomeDir '.local\bin\thide'
$AutoTilerDir  = Join-Path $HomeDir '.local\bin\glaze-autotiler'

$BackupRoot = Join-Path $HomeDir '.windows-rice-backup'
$ManifestPath = Join-Path $BackupRoot 'manifest.json'

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
    Write-Host ('    ' + 'Backup'.PadRight(11) + $BackupRoot) -ForegroundColor Gray
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
    'Restored'    = New-Object System.Collections.ArrayList
    'Removed'     = New-Object System.Collections.ArrayList
    'Uninstalled' = New-Object System.Collections.ArrayList
    'Skipped'     = New-Object System.Collections.ArrayList
    'Warnings'    = New-Object System.Collections.ArrayList
    'Failed'      = New-Object System.Collections.ArrayList
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

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-PathFromRegistry {
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
    if ($merged.Count -gt 0) { $env:Path = ($merged -join ';') }
}

function Find-LatestBackup {
    param(
        [Parameter(Mandatory)][string]$BackupSubdir,
        [Parameter(Mandatory)][string]$FileName
    )
    $dir = Join-Path $BackupRoot $BackupSubdir
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    $latest = Get-ChildItem -LiteralPath $dir -File `
                  -Filter "$FileName.backup-*" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

function Restore-FromBackup {
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$BackupSubdir,
        [Parameter(Mandatory)][string]$Label
    )

    $fileName = Split-Path -Leaf $Destination
    $backup = Find-LatestBackup -BackupSubdir $BackupSubdir -FileName $fileName

    if (-not $backup) {
        if (Test-Path -LiteralPath $Destination) {
            Write-Skip "$Label — no backup found; deployed file left in place"
            Add-Summary 'Skipped' "$Label (no backup)"
        } else {
            Write-Skip "$Label — no backup and no deployed file"
        }
        return
    }

    if ($DryRun) {
        Write-Skip "would restore $Label from $backup"
        Add-Summary 'Restored' "$Label (dry run)"
        return
    }

    try {
        $destDir = Split-Path -Parent $Destination
        if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $backup -Destination $Destination -Force -ErrorAction Stop
        Write-Ok "restored: $Label"
        Add-Summary 'Restored' "$Label"
    } catch {
        Write-FailLine "$Label — $_"
        Add-Summary 'Failed' "$Label ($_)"
    }
}

# ---------------------------------------------------- installation manifest

function Read-Manifest {
    <#
        Read the installation manifest. Returns $null when the manifest is
        missing or unreadable, so the caller can decide what to do.
    #>
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-WarnLine "Could not parse manifest at $ManifestPath — $_"
        return $null
    }
    if (-not $obj.installed) { return $null }

    $result = [ordered]@{
        winget = if ($obj.installed.winget) { @($obj.installed.winget) } else { @() }
        scoop  = if ($obj.installed.scoop)  { @($obj.installed.scoop)  } else { @() }
        direct = if ($obj.installed.direct) { @($obj.installed.direct) } else { @() }
    }
    return $result
}

function Write-ManifestBlock {
    param($Manifest)

    if (-not $Manifest) {
        Write-Host '  Installation manifest' -ForegroundColor Cyan
        Write-Host '    [WARN] Installation manifest unavailable' -ForegroundColor Yellow
        Write-Host '           Package removal has been skipped.' -ForegroundColor Yellow
        Write-Host ''
        return
    }

    $wingetCount = @($Manifest.winget).Count
    $scoopCount  = @($Manifest.scoop).Count
    $directCount = @($Manifest.direct).Count

    $fonts = @($Manifest.scoop | Where-Object { $_ -match 'NF' -or $_ -match 'NerdFont' })
    $fontCount = $fonts.Count

    Write-Host '  Installation manifest' -ForegroundColor Cyan
    Write-Host ('    ' + 'Winget packages'.PadRight(20) + $wingetCount) -ForegroundColor Gray
    Write-Host ('    ' + 'Scoop packages'.PadRight(20) + $scoopCount) -ForegroundColor Gray
    if ($fontCount -gt 0) {
        Write-Host ('    ' + 'Nerd Fonts'.PadRight(20) + $fontCount) -ForegroundColor Gray
    }
    if ($directCount -gt 0) {
        Write-Host ('    ' + 'Direct installs'.PadRight(20) + $directCount) -ForegroundColor Gray
    }
    Write-Host ''
}

# ---------------------------------------------------------- Windows Terminal

function Get-WindowsTerminalSettingsPath {
    $pkg = $null
    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -ErrorAction Stop |
                Select-Object -First 1
    } catch { $pkg = $null }

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
            Write-WarnLine 'Multiple Windows Terminal package folders detected — refusing to guess.'
        }
    }
    return $null
}

# ------------------------------------------------------------- package removal

function Test-WingetAvailable {
    return (Test-CommandExists 'winget')
}

function Uninstall-WingetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name
    )

    if ($DryRun) {
        Write-Skip "would uninstall $Name ($Id)"
        Add-Summary 'Uninstalled' "$Name (dry run)"
        return $true
    }

    Write-Info "uninstalling $Name ($Id)..."
    try {
        $out = (& winget uninstall --id $Id --exact --silent `
                    --accept-source-agreements 2>&1 | Out-String)
    } catch {
        Write-FailLine "$Name — $_"
        Add-Summary 'Failed' "$Name ($_)"
        return $false
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "removed: $Name"
        Add-Summary 'Uninstalled' $Name
        return $true
    }

    if ($out -match 'No installed package' -or $out -match 'not found') {
        Write-Skip "$Name was not installed"
        Add-Summary 'Skipped' "$Name (not installed)"
        return $true
    }

    Write-FailLine "$Name — winget exit $LASTEXITCODE"
    Add-Summary 'Failed' "$Name (winget exit $LASTEXITCODE)"
    return $false
}

function Uninstall-ScoopPackage {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Display = $Name
    )

    if (-not (Test-CommandExists 'scoop')) {
        Write-Skip "scoop not available — cannot uninstall $Display"
        Add-Summary 'Skipped' "$Display (scoop unavailable)"
        return
    }

    if ($DryRun) {
        Write-Skip "would scoop uninstall $Name"
        Add-Summary 'Uninstalled' "$Display (dry run)"
        return
    }

    try {
        $out = (& scoop uninstall $Name 2>&1 | Out-String)
    } catch {
        Write-FailLine "$Display — $_"
        Add-Summary 'Failed' "$Display ($_)"
        return
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "removed: $Display"
        Add-Summary 'Uninstalled' $Display
        return
    }

    if ($out -match "isn't installed" -or $out -match 'not installed') {
        Write-Skip "$Display was not installed"
        Add-Summary 'Skipped' "$Display (not installed)"
        return
    }

    Write-FailLine "$Display — scoop exit $LASTEXITCODE"
    Add-Summary 'Failed' "$Display (scoop exit $LASTEXITCODE)"
}

function Uninstall-DirectPackage {
    <#
        Removes packages the rice installed from pinned sources (Thide,
        GlazeWM AutoTiler). Each entry in the manifest's `installed.direct`
        array has its own cleanup routine because the shape of "uninstall"
        depends on how the thing was installed.

        Adding a new direct install requires:
        1. Registering it in install.ps1's Install-Extras
        2. Adding a case for its Id here
    #>
    param(
        [Parameter(Mandatory)][string]$Id
    )

    switch ($Id) {
        'thide' {
            if ($DryRun) {
                Write-Skip 'would remove Thide'
                Add-Summary 'Uninstalled' 'Thide (dry run)'
                return
            }

            $exe = Join-Path $ThideDir 'thide.exe'
            if (Test-Path -LiteralPath $exe) {
                try {
                    & $exe disable-autostart 2>&1 | Out-Null
                    & $exe stop              2>&1 | Out-Null
                } catch {
                    # Best effort — if the CLI refuses, keep going.
                }
            }

            if (Test-Path -LiteralPath $ThideDir) {
                try {
                    Remove-Item -LiteralPath $ThideDir -Recurse -Force -ErrorAction Stop
                } catch {
                    Write-FailLine "Thide — could not remove $ThideDir — $_"
                    Add-Summary 'Failed' "Thide ($_)"
                    return
                }
            }

            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if ($userPath -like "*$ThideDir*") {
                $parts = @($userPath -split ';' |
                            Where-Object { $_ -ne '' -and $_ -ine $ThideDir })
                [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
                Write-Info "Removed $ThideDir from user PATH"
            }

            Write-Ok 'removed: Thide'
            Add-Summary 'Uninstalled' 'Thide'
        }
        'glaze-autotiler' {
            if ($DryRun) {
                Write-Skip 'would remove GlazeWM AutoTiler'
                Add-Summary 'Uninstalled' 'GlazeWM AutoTiler (dry run)'
                return
            }

            # Kill any running tray instance so the exe isn't locked when
            # we try to remove the folder.
            Get-Process -Name 'glaze-autotiler' -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue

            if (Test-Path -LiteralPath $AutoTilerDir) {
                try {
                    Remove-Item -LiteralPath $AutoTilerDir -Recurse -Force -ErrorAction Stop
                } catch {
                    Write-FailLine "GlazeWM AutoTiler — could not remove $AutoTilerDir — $_"
                    Add-Summary 'Failed' "GlazeWM AutoTiler ($_)"
                    return
                }
            }

            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if ($userPath -like "*$AutoTilerDir*") {
                $parts = @($userPath -split ';' |
                            Where-Object { $_ -ne '' -and $_ -ine $AutoTilerDir })
                [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
                Write-Info "Removed $AutoTilerDir from user PATH"
            }

            Write-Ok 'removed: GlazeWM AutoTiler'
            Add-Summary 'Uninstalled' 'GlazeWM AutoTiler'
        }
        default {
            Write-WarnLine "No uninstall handler for direct package '$Id' — skipping"
            Add-Summary 'Warnings' "$Id (no uninstall handler)"
        }
    }
}

# ================================================================== SECTIONS

function Restore-AllConfigs {
    Write-Section 'Restoring configurations'

    Restore-FromBackup -Destination $YasbConfigPath `
                       -BackupSubdir 'yasb' `
                       -Label '~/.config/yasb/config.yaml'

    Restore-FromBackup -Destination $YasbStylesPath `
                       -BackupSubdir 'yasb' `
                       -Label '~/.config/yasb/styles.css'

    Restore-FromBackup -Destination $GlazeWmConfigPath `
                       -BackupSubdir 'glazewm' `
                       -Label '~/.glzr/glazewm/config.yaml'

    Restore-FromBackup -Destination $CavaConfigPath `
                       -BackupSubdir 'cava' `
                       -Label '~/.config/cava/config'

    Restore-FromBackup -Destination $FastfetchConfigPath `
                       -BackupSubdir 'fastfetch' `
                       -Label '~/.config/fastfetch/config.jsonc'

    Restore-FromBackup -Destination $FastfetchAsciiPath `
                       -BackupSubdir 'fastfetch' `
                       -Label '~/.config/fastfetch/ascii.txt'

    Restore-FromBackup -Destination $PwshProfilePath `
                       -BackupSubdir 'powershell' `
                       -Label 'PowerShell profile'
}

function Restore-Wallpapers {
    <#
        Restore every wallpaper backup created by install.ps1.

        install.ps1 backs up existing files at each wallpaper's destination
        path (per-file), storing the backup with a filename of the form
        <name>.backup-<timestamp>, under a backup subdir that mirrors the
        wallpaper's relative path under assets/wallpapers/ (e.g.
        wallpapers/dark/). This function reverses that mapping.

        Wallpapers that were deployed fresh (no pre-existing file, so no
        backup) are left in place - consistent with how fresh config files
        are handled.
    #>
    Write-Section 'Restoring wallpapers'

    $backupDir = Join-Path $BackupRoot 'wallpapers'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        Write-Skip 'No wallpaper backups found'
        return
    }

    $backups = @(Get-ChildItem -LiteralPath $backupDir -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '\.backup-\d{4}-\d{2}-\d{2}-\d{6}$' })

    if ($backups.Count -eq 0) {
        Write-Skip 'No wallpaper backups found'
        return
    }

    foreach ($b in $backups) {
        $origName = $b.Name -replace '\.backup-\d{4}-\d{2}-\d{2}-\d{6}$', ''
        if (-not $origName) { continue }

        $relDir = $b.DirectoryName.Substring($backupDir.Length).TrimStart('\', '/')
        $destDir = if ($relDir) { Join-Path $WallpaperDir $relDir } else { $WallpaperDir }
        $destPath = Join-Path $destDir $origName

        if ($DryRun) {
            Write-Skip "would restore $destPath"
            Add-Summary 'Restored' "$destPath (dry run)"
            continue
        }

        try {
            if (-not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $b.FullName -Destination $destPath -Force -ErrorAction Stop
            Write-Ok "restored: $destPath"
            Add-Summary 'Restored' $destPath
        } catch {
            Write-FailLine "$destPath — $_"
            Add-Summary 'Failed' "$destPath ($_)"
        }
    }
}

function Restore-WindowsTerminal {
    Write-Section 'Windows Terminal'

    $wtSettingsPath = Get-WindowsTerminalSettingsPath
    if (-not $wtSettingsPath) {
        Write-WarnLine 'Could not determine the Windows Terminal settings location.'
        Add-Summary 'Skipped' 'Windows Terminal (settings location undetermined)'
        return
    }

    if (-not (Test-Path -LiteralPath $wtSettingsPath)) {
        Write-Skip 'Windows Terminal settings.json does not exist'
        Add-Summary 'Skipped' 'Windows Terminal (no settings.json)'
        return
    }

    Restore-FromBackup -Destination $wtSettingsPath `
                       -BackupSubdir 'terminal' `
                       -Label 'Windows Terminal settings.json'
}

function Remove-WallpaperDirectory {
    Write-Section 'Wallpaper directory'

    if (-not (Test-Path -LiteralPath $WallpaperDir)) {
        Write-Skip 'Wallpaper directory does not exist'
        return
    }

    $items = @(Get-ChildItem -LiteralPath $WallpaperDir -Force -ErrorAction SilentlyContinue)
    if ($items.Count -gt 0) {
        Write-Skip "$WallpaperDir is not empty — left in place"
        Add-Summary 'Skipped' 'Wallpaper directory (not empty)'
        return
    }

    if ($DryRun) {
        Write-Skip "would remove empty $WallpaperDir"
        Add-Summary 'Removed' "$WallpaperDir (dry run)"
        return
    }

    try {
        Remove-Item -LiteralPath $WallpaperDir -Force -ErrorAction Stop
        Write-Ok "removed empty directory: $WallpaperDir"
        Add-Summary 'Removed' $WallpaperDir
    } catch {
        Write-WarnLine "Could not remove $WallpaperDir — $_"
        Add-Summary 'Warnings' "$WallpaperDir ($_)"
    }
}

function Uninstall-AllPackages {
    Write-Section 'Removing packages'

    $manifest = Read-Manifest
    Write-ManifestBlock -Manifest $manifest

    if (-not $manifest) {
        Write-WarnLine 'No readable installation manifest — package removal skipped.'
        Add-Summary 'Skipped' 'All packages (no manifest)'
        return
    }

    # -------- winget ------------------------------------------------------
    #
    # Some packages are never removed, even if the manifest records that the
    # installer put them there. These are general-purpose tools users are
    # likely to keep, and removing PowerShell 7 in particular leaves Windows
    # Terminal without its default profile (pwsh.exe), which breaks every
    # attempt to open a terminal until PowerShell is reinstalled.
    #
    # To force-remove one of these, do it manually:
    #   winget uninstall --id <Id> --exact
    $wingetKeep = @(
        'Microsoft.PowerShell',
        'Microsoft.WindowsTerminal'
    )

    $wingetIds = @($manifest.winget)
    if ($wingetIds.Count -eq 0) {
        Write-Skip 'No winget packages recorded in manifest'
    } elseif (-not (Test-WingetAvailable)) {
        Write-WarnLine 'winget is not available — skipping winget package removal.'
        Add-Summary 'Warnings' 'winget not available (package removal skipped)'
    } else {
        foreach ($id in $wingetIds) {
            if ($wingetKeep -contains $id) {
                Write-Skip "$id — kept intentionally (general-purpose tool)"
                Add-Summary 'Skipped' "$id (kept intentionally)"
                continue
            }
            Uninstall-WingetPackage -Id $id -Name $id
        }
    }

    # -------- scoop -------------------------------------------------------
    Write-Host ''
    Write-Info 'Scoop packages'

    $scoopIds = @($manifest.scoop)
    if ($scoopIds.Count -eq 0) {
        Write-Skip 'No scoop packages recorded in manifest'
    } else {
        foreach ($id in $scoopIds) {
            Uninstall-ScoopPackage -Name $id -Display $id
        }
    }

    # -------- direct (Thide, AutoTiler) -----------------------------------
    $directIds = @($manifest.direct)
    if ($directIds.Count -eq 0) {
        Write-Host ''
        Write-Skip 'No direct installs recorded in manifest'
    } else {
        Write-Host ''
        Write-Info 'Direct installs'
        foreach ($id in $directIds) {
            Uninstall-DirectPackage -Id $id
        }
    }
}

function Remove-BackupDirectory {
    Write-Section 'Cleanup'

    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        Write-Skip 'No backup directory to purge'
        return
    }

    if (-not $DryRun) {
        if (-not (Confirm-Action -Prompt "Delete $BackupRoot (including manifest)?" -Default $false)) {
            Write-Skip 'Backup directory kept'
            Add-Summary 'Skipped' 'Backup directory (kept by user choice)'
            return
        }
    }

    if ($DryRun) {
        Write-Skip "would remove $BackupRoot"
        Add-Summary 'Removed' "$BackupRoot (dry run)"
        return
    }

    try {
        Remove-Item -LiteralPath $BackupRoot -Recurse -Force -ErrorAction Stop
        Write-Ok "removed: $BackupRoot"
        Add-Summary 'Removed' $BackupRoot
    } catch {
        Write-FailLine "Could not remove $BackupRoot — $_"
        Add-Summary 'Failed' "$BackupRoot ($_)"
    }
}

function Remove-WallpaperFiles {
    <#
        Only runs when -Purge is set. Wipes the deployed wallpaper set
        entirely, including files that were deployed fresh (and therefore
        have no backup to restore from). Without -Purge, wallpaper files
        that replaced nothing on disk are left in place, matching the
        behaviour for freshly-deployed config files.

        Wired into the summary so the outcome is visible.
    #>
    if (-not $Purge) { return }

    Write-Section 'Wallpaper files'

    if (-not (Test-Path -LiteralPath $WallpaperDir)) {
        Write-Skip 'Wallpaper directory does not exist'
        return
    }

    if ($DryRun) {
        Write-Skip "would remove $WallpaperDir"
        Add-Summary 'Removed' "$WallpaperDir (dry run)"
        return
    }

    try {
        Remove-Item -LiteralPath $WallpaperDir -Recurse -Force -ErrorAction Stop
        Write-Ok "removed: $WallpaperDir"
        Add-Summary 'Removed' $WallpaperDir
    } catch {
        Write-WarnLine "Could not remove $WallpaperDir — $_"
        Add-Summary 'Warnings' "$WallpaperDir ($_)"
    }
}

# =============================================================== SUMMARY

function Write-FinalSummary {
    Write-Section 'Complete'

    $restored    = $script:Summary['Restored'].Count
    $removed     = $script:Summary['Removed'].Count
    $uninstalled = $script:Summary['Uninstalled'].Count
    $skipped     = $script:Summary['Skipped'].Count
    $warnings    = $script:Summary['Warnings'].Count
    $failed      = $script:Summary['Failed'].Count

    $rows = @(
        @{ Label = 'Restored';    Value = $restored },
        @{ Label = 'Removed';     Value = $removed },
        @{ Label = 'Uninstalled'; Value = $uninstalled },
        @{ Label = 'Skipped';     Value = $skipped },
        @{ Label = 'Warnings';    Value = $warnings },
        @{ Label = 'Failed';      Value = $failed }
    )

    foreach ($r in $rows) {
        Write-Host ('  ' + $r.Label.PadRight(16) + $r.Value) -ForegroundColor Gray
    }

    Write-Host ''

    if ($failed -gt 0) {
        Write-Host '  [FAIL] Uninstallation completed with errors.' -ForegroundColor Red
    } elseif ($warnings -gt 0) {
        Write-Host '  [WARN] Uninstallation completed with warnings.' -ForegroundColor Yellow
    } else {
        Write-Host '  Windows-Rice has been removed safely.' -ForegroundColor Green
    }

    Write-Host ''

    if (Test-Path -LiteralPath $BackupRoot) {
        Write-Host '  Backups preserved' -ForegroundColor Cyan
        Write-Host "    $BackupRoot" -ForegroundColor Gray
        Write-Host ''
    }

    Write-Host '  Next steps' -ForegroundColor Cyan
    Write-Host '    1. Close and reopen your terminal.' -ForegroundColor Gray
    Write-Host '    2. Restart GlazeWM if it was running.' -ForegroundColor Gray
    Write-Host '    3. Restart Windows Terminal if it was open.' -ForegroundColor Gray
    Write-Host ''

    Write-Separator
    Write-Host ''
}

# ================================================================== MAIN

Write-Banner 'Safe removal & restoration'
Write-Section 'Windows-Rice • Uninstall'
Write-EnvBlock

if (-not (Test-Path -LiteralPath $BackupRoot)) {
    Write-WarnLine "No backup directory found at $BackupRoot."
    Write-WarnLine 'Nothing to restore. Proceeding with optional package removal only.'
    Write-Host ''
}

# 1. Config restore ---------------------------------------------------------
if (Test-Path -LiteralPath $BackupRoot) {
    Restore-AllConfigs
    Restore-Wallpapers
    Restore-WindowsTerminal
} else {
    Write-Section 'Restoring configurations'
    Write-Skip 'No backup directory; configuration restore skipped.'
}

# 2. Wallpaper directory cleanup --------------------------------------------
Remove-WallpaperDirectory

# 3. Wallpaper files nuke (only with -Purge) --------------------------------
Remove-WallpaperFiles

# 4. Package removal (opt-in, manifest-driven) ------------------------------
if ($RemovePackages) {
    Uninstall-AllPackages
} else {
    Write-Section 'Packages'
    Write-Skip 'Skipping package removal (pass -RemovePackages to uninstall)'
    Add-Summary 'Skipped' 'All packages (remove not requested)'
}

# 5. Purge backups (opt-in) -------------------------------------------------
if ($Purge) {
    Remove-BackupDirectory
} else {
    Write-Section 'Cleanup'
    Write-Skip 'Backups and manifest preserved (pass -Purge to delete)'
}

# 6. Summary ----------------------------------------------------------------
Write-FinalSummary