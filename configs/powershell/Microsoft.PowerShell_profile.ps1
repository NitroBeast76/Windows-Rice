# Minimal PowerShell profile for Windows-Rice.
# Sets UTF-8 I/O, runs Fastfetch on shell start, then hands the prompt
# over to Starship.
#
# Order matters: Fastfetch must run before Starship initializes so the
# fetch output isn't overwritten by prompt redraws, and the Starship
# init line must be last so nothing after it can clobber the prompt
# function it installs.

try {
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    chcp 65001 > $null
} catch {}

Clear-Host

# Run Fastfetch with the rice's config on every shell start.
if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch -c "$HOME\.config\fastfetch\config.jsonc"
}

# Starship prompt. Must be the last line in this file: it replaces the
# global prompt function, and anything appended afterward would fight it.
# Guarded so a -SkipPackages install (or a machine without Starship yet)
# doesn't throw on every shell start.
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}