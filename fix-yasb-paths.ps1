<#
.SYNOPSIS
    Normalize image_path in every YASB config to the placeholder path.

.DESCRIPTION
    The YASB wallpapers widget has an `image_path` setting pointing at the
    folder holding your wallpapers. The rice's install.ps1 substitutes the
    string `~/Pictures/Windows-Rice` for the resolved Windows Pictures
    folder at deploy time.

    Any other value — a hardcoded `C:\Wallpapers`, a personal
    `D:\OneDrive\...` path, etc. — skips that substitution and ships a
    useless path to users who clone the repo.

    This script finds every YASB config under configs\ and themes\, and
    replaces whatever the image_path value currently is with the
    placeholder. Handles quoted values, unquoted values, and list form.

    Backs up each modified file to <file>.bak before writing.

.PARAMETER Path
    Repository root. Defaults to the script's location, or the current
    directory if run interactively.

.PARAMETER DryRun
    Report what would change without writing anything.
#>

[CmdletBinding()]
param(
    [string]$Path,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$root = if ($Path) { (Resolve-Path -LiteralPath $Path).Path }
        elseif ($PSScriptRoot) { $PSScriptRoot }
        else { (Get-Location).Path }

$placeholder = '~/Pictures/Windows-Rice'

Write-Host ''
Write-Host "  Scanning: $root" -ForegroundColor Cyan
if ($DryRun) { Write-Host '  Dry run:  YES' -ForegroundColor Yellow }
Write-Host ''

# Find every yasb config
$searchDirs = @(
    (Join-Path $root 'themes'),
    (Join-Path $root 'configs')
) | Where-Object { Test-Path -LiteralPath $_ }

$files = @()
foreach ($dir in $searchDirs) {
    $files += Get-ChildItem -LiteralPath $dir -Recurse -File `
                -Filter 'default_yasb_config.yaml' -ErrorAction SilentlyContinue
}

if ($files.Count -eq 0) {
    Write-Host '  No YASB configs found.' -ForegroundColor Yellow
    exit 0
}

$changed = 0
$clean   = 0

foreach ($f in $files) {
    $rel      = $f.FullName.Substring($root.Length).TrimStart('\', '/')
    $lines    = Get-Content -LiteralPath $f.FullName
    $newLines = New-Object System.Collections.ArrayList
    $found    = $false
    $modified = $false
    $unmatchedImagePathLines = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Case A — scalar: image_path: "value" / 'value' / bare value
        # Optional trailing comment.
        if ($line -match '^(\s*)image_path:\s*(.*?)\s*(#.*)?$') {
            $indent   = $Matches[1]
            $rawValue = $Matches[2].Trim()
            $comment  = if ($Matches[3]) { ' ' + $Matches[3].Trim() } else { '' }

            # Strip optional wrapping quotes for comparison
            $cleanValue = $rawValue.Trim('"', "'")

            if ($cleanValue -eq $placeholder) {
                [void]$newLines.Add($line)
                $found = $true
                continue
            }

            $newLine = "$indent`"$placeholder`"$comment"
            [void]$newLines.Add($newLine)
            $found = $true
            $modified = $true
            Write-Host ("  ~ {0} line {1}" -f $rel, ($i + 1)) -ForegroundColor Yellow
            Write-Host ("      before: {0}" -f $line.Trim()) -ForegroundColor DarkGray
            Write-Host ("      after:  {0}" -f $newLine.Trim()) -ForegroundColor Green
            continue
        }

        # Case B — list form: image_path: on its own line, items below
        if ($line -match '^(\s*)image_path:\s*(#.*)?$') {
            $indent  = $Matches[1]
            $comment = if ($Matches[2]) { ' ' + $Matches[2].Trim() } else { '' }

            $j = $i + 1
            $itemCount = 0
            while ($j -lt $lines.Count -and $lines[$j] -match '^\s*-\s') {
                $itemCount++
                $j++
            }

            if ($itemCount -gt 0) {
                if ($itemCount -eq 1 -and $lines[$i + 1] -match [regex]::Escape($placeholder)) {
                    [void]$newLines.Add($line)
                    for ($k = $i + 1; $k -lt $j; $k++) { [void]$newLines.Add($lines[$k]) }
                    $i = $j - 1
                    $found = $true
                    continue
                }

                $newLine = "$indent`"$placeholder`"$comment"
                [void]$newLines.Add($newLine)
                Write-Host ("  ~ {0} lines {1}-{2}" -f $rel, ($i + 1), $j) -ForegroundColor Yellow
                Write-Host ("      replacing {0}-item list with scalar placeholder" -f $itemCount) -ForegroundColor DarkGray
                $found = $true
                $modified = $true
                $i = $j - 1
                continue
            }
        }

        # Diagnostic: any line mentioning image_path that didn't match above
        if ($line -match 'image_path') {
            $unmatchedImagePathLines += ("line {0}: {1}" -f ($i + 1), $line.Trim())
        }

        [void]$newLines.Add($line)
    }

    if (-not $found) {
        if ($unmatchedImagePathLines.Count -gt 0) {
            Write-Host ("  ! {0} — image_path found but pattern did not match:" -f $rel) -ForegroundColor DarkYellow
            foreach ($u in $unmatchedImagePathLines) {
                Write-Host ("      {0}" -f $u) -ForegroundColor DarkGray
            }
        } else {
            Write-Host ("  ! {0} — no image_path setting found" -f $rel) -ForegroundColor DarkGray
        }
        continue
    }

    if (-not $modified) {
        Write-Host ("  ✓ {0} already correct" -f $rel) -ForegroundColor Green
        $clean++
        continue
    }

    if ($DryRun) {
        Write-Host '      (dry run — not written)' -ForegroundColor DarkGray
    } else {
        Copy-Item -LiteralPath $f.FullName -Destination "$($f.FullName).bak" -Force
        Set-Content -LiteralPath $f.FullName -Value $newLines -Encoding UTF8
        Write-Host ("      written; backup at {0}.bak" -f $f.Name) -ForegroundColor DarkGray
    }
    $changed++
}

Write-Host ''
if ($changed -eq 0) {
    Write-Host "  Nothing to change. $clean file(s) already correct." -ForegroundColor Green
} else {
    $verb = if ($DryRun) { 'would change' } else { 'changed' }
    Write-Host "  $verb $changed file(s). $clean already correct." -ForegroundColor Cyan
    if (-not $DryRun) {
        Write-Host ''
        Write-Host '  Backups written alongside each file with .bak suffix.' -ForegroundColor Gray
        Write-Host '  Verify with: git diff' -ForegroundColor Gray
    }
}
Write-Host ''