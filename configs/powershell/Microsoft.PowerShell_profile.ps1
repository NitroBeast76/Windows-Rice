# Minimal PowerShell profile for Windows-Rice.
# Sets UTF-8 I/O, runs Fastfetch on shell start, then hands the prompt
# over to Starship.
#
# Order matters: Fastfetch must run before Starship initializes so the
# fetch output isn't overwritten by prompt redraws, and the Starship
# init line must be last so nothing after it can clobber the prompt
# function it installs.

# UTF-8 for PowerShell's own I/O. No chcp here: spawning chcp.com costs
# ~80-150ms on a VM and only matters for legacy console apps, none of
# which the rice uses. [Console]::OutputEncoding is sufficient.
try {
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

Clear-Host

# Run Fastfetch with the rice's config on every shell start.
# --detect-version false skips upstream version probing (~30-50% off).
# --disk-folders C:\ limits disk enumeration to the only volume that
# matters and avoids stalling on read-only or external mounts.
if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch -c "$HOME\.config\fastfetch\config.jsonc" --detect-version false --disk-folders C:\
}

# Starship prompt. Must be the last line in this file: it replaces the
# global prompt function, and anything appended afterward would fight it.
# Guarded so a -SkipPackages install (or a machine without Starship yet)
# doesn't throw on every shell start.
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}