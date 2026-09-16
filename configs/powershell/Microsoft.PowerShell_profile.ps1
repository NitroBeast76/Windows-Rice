# Minimal PowerShell profile for Windows-Rice.
# Sets UTF-8 I/O and runs Fastfetch on shell start.
# No prompt framework: no Oh My Posh, no Starship, no posh-git.

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