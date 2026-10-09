<#
.SYNOPSIS
    Fix the PATH substring-match bug in install.ps1.

.DESCRIPTION
    Replaces every instance of:

        $userPath -notlike "*$X*"

    with:

        (($userPath -split ';') | Where-Object { $_ -ne '' }) -notcontains $X

    The -notlike version matches substrings, so ~/.local/bin is considered
    "already on PATH" whenever any child folder (~/.local/bin/thide) is
    present. The -notcontains version compares whole semicolon-separated
    segments, so it correctly detects the missing parent.

    Uses [regex]::Replace with a MatchEvaluator (not -replace) so the
    replacement string is not parsed for $1 backreferences. That avoids
    the failure mode where `$$$1` doesn't expand as expected.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot    = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$installPath = Join-Path $repoRoot 'install.ps1'

if (-not (Test-Path -LiteralPath $installPath)) {
    Write-Host "install.ps1 not found at $installPath" -ForegroundColor Red
    exit 1
}

# ---- Read ----------------------------------------------------------------

$content = Get-Content -LiteralPath $installPath -Raw

# ---- Pattern -------------------------------------------------------------

$pattern = '\$userPath -notlike "\*\$(\w+)\*"'
$regex   = [regex]::new($pattern)

$matches = $regex.Matches($content)
$before  = $matches.Count

Write-Host ''
Write-Host 'Scanning install.ps1...' -ForegroundColor Cyan
Write-Host "  Found $before instance(s) of the substring-match pattern."

if ($before -eq 0) {
    Write-Host ''
    Write-Host 'Nothing to patch. Either already fixed, or the pattern changed.' -ForegroundColor Yellow
    exit 0
}

Write-Host ''
Write-Host 'Sites:' -ForegroundColor Cyan
foreach ($m in $matches) {
    Write-Host "  - `$userPath -notlike ""*`$$($m.Groups[1].Value)*""" -ForegroundColor Gray
}

# ---- Back up -------------------------------------------------------------

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = "$installPath.bak-$timestamp"
Copy-Item -LiteralPath $installPath -Destination $backupPath -Force
Write-Host ''
Write-Host "Backup: $backupPath" -ForegroundColor DarkGray

# ---- Apply via MatchEvaluator -------------------------------------------
#
# The evaluator runs in PowerShell and returns a string that is inserted
# verbatim by .NET. No `$1` backreference parsing on the replacement side,
# so no escaping surprises.

$evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
    param($match)
    $varName = $match.Groups[1].Value
    return '($userPath -split '';'' | Where-Object { $_ -ne '''' }) -notcontains $' + $varName
}

$newContent = $regex.Replace($content, $evaluator)

$after = $regex.Matches($newContent).Count
if ($after -ne 0) {
    Write-Host ''
    Write-Host "WARNING: $after match(es) remain after replace." -ForegroundColor Yellow
    Write-Host 'Showing context around the first remaining match:' -ForegroundColor Yellow

    $first = $regex.Matches($newContent)[0]
    $start = [Math]::Max(0, $first.Index - 80)
    $len   = [Math]::Min(200, $newContent.Length - $start)
    Write-Host $newContent.Substring($start, $len) -ForegroundColor DarkGray

    Write-Host ''
    Write-Host 'Aborting without writing. Backup preserved.' -ForegroundColor Yellow
    exit 1
}

# ---- Syntax check --------------------------------------------------------

$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput(
    $newContent,
    [ref]$null,
    [ref]$parseErrors
)

if ($parseErrors -and $parseErrors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Parse errors in patched content - aborting.' -ForegroundColor Red
    foreach ($e in $parseErrors) {
        Write-Host ("  Line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red
    }
    Write-Host "Backup preserved at $backupPath" -ForegroundColor Yellow
    exit 1
}

# ---- Write (UTF-8 with BOM, so PS 5.1 reads box-drawing chars) ----------

$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($installPath, $newContent, $enc)

Write-Host ''
Write-Host "Patched $before instance(s)." -ForegroundColor Green

# ---- Show a sample of the output ----------------------------------------

Write-Host ''
Write-Host 'Sample output (first patched line):' -ForegroundColor Cyan
$sampleMatch = $regex.Matches($content)[0]
$lineStart = $content.LastIndexOf("`n", $sampleMatch.Index) + 1
$lineEnd   = $content.IndexOf("`n", $sampleMatch.Index)
$origLine  = $content.Substring($lineStart, $lineEnd - $lineStart)

# Find same line in new content by looking for the value we replaced
$varName = $sampleMatch.Groups[1].Value
$newLine = ($newContent -split "`n" | Where-Object { $_ -match [regex]::Escape("-notcontains `$$varName") } | Select-Object -First 1)

Write-Host ''
Write-Host '  Before: ' -NoNewline -ForegroundColor DarkGray
Write-Host $origLine.Trim() -ForegroundColor Red
Write-Host '  After:  ' -NoNewline -ForegroundColor DarkGray
Write-Host $newLine.Trim() -ForegroundColor Green

Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  1. git diff install.ps1               # review the changes' -ForegroundColor Gray
Write-Host '  2. git add install.ps1' -ForegroundColor Gray
Write-Host '  3. git commit -m "Fix PATH substring match in installer"' -ForegroundColor Gray
Write-Host '  4. git push' -ForegroundColor Gray
Write-Host ''
Write-Host 'To revert: ' -NoNewline -ForegroundColor DarkGray
Write-Host "Copy-Item '$backupPath' '$installPath' -Force" -ForegroundColor DarkGray
Write-Host ''