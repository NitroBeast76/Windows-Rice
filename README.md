# Windows-Rice

A Windows 10/11 rice you install once. GlazeWM, YASB, and a curated pile of CLI tools, deployed by a PowerShell script that knows how to say sorry.

**One command to install. One command to undo. Zero "well, actually, you'll need to manually edit the registry."**

```powershell
git clone https://github.com/NitroBeast76/Windows-Rice.git
cd Windows-Rice
.\install.ps1
```

That's it. Really. If this README were a mile longer, you'd still only need those three lines.

![Windows-Rice — tiled workspace with cava, btop, and Fastfetch](assets/screenshots/tiling.png)

<details>
<summary>More screenshots (click if you're on the fence)</summary>

![Windows-Rice desktop — YASB bar and wallpaper](assets/screenshots/desktop.png)

![Installer — package installation phase](assets/screenshots/installer-1.png)

![Installer — completion summary](assets/screenshots/installer-2.png)

</details>

---

## Why this exists

Windows ricing is stuck in the "here's my dotfiles, figure it out" era. You find someone's gorgeous desktop, clone their repo, and discover that it assumes you:

- Already have PowerShell 7, Scoop, and three CLI tools you've never heard of
- Know where each config file is *supposed* to live
- Are okay with their script silently overwriting your existing setup
- Somehow also want to become a system administrator

Windows-Rice tries to be what those repos aren't: an actual installer. It backs things up. It tells you what it's about to do. It has an uninstaller, which is the rarest creature in the ricing ecosystem.

It also has themes now, which means you can change how it looks without becoming a CSS archaeologist.

---

## What you actually get

### Desktop / UI

| Component | Role |
|---|---|
| **GlazeWM** | Tiling window manager. Your windows will line up like they mean it. |
| **YASB** | Status bar at the top. Shows time, music, CPU, and whether your RAM is as sad as your wallet. |
| **CAVA** | Audio visualizer, embedded in the bar. Yes, it will pulse when the bass drops. |
| **Fastfetch** | System info printed on shell start. Runs on every new terminal because vanity is a valid use case. |
| **Windows Terminal** | The terminal host. Yes, the one Microsoft makes. No, we're not switching to Wezterm today. |
| **PowerShell 7** | The shell. The one that actually works. |

### CLI tools

`btop` (resource monitor), `fd` (`find` that isn't stuck in 1985), `fzf` (fuzzy finder), `ripgrep` (`grep` but it's fast enough to finish before you do), `yazi` (terminal file manager with previews), `yt-dlp` (the internet's favorite "save that video" tool), `ffmpeg`, `7-Zip`, `jq`, `zoxide`, `ImageMagick`.

If you don't know what half of those do, install and find out. That's the fun part.

### New in 1.2

| Component | Role |
|---|---|
| **ChronoTerm** | A terminal clock. Yes, a clock. In your terminal. With a config file. Ricing is about joy, not utility. |
| **rmatrix** | The falling green code from The Matrix, for Windows. Rust port, because the original cmatrix only runs on Windows via MSYS2, which is nobody's idea of a good time. |
| **btop config** | `color_theme = "TTY"`, so btop follows your terminal palette automatically. Change the theme, btop changes too. |
| **Themes** | Full theme system. See below. |

### Fonts

The canonical font is **JetBrainsMono Nerd Font Mono**. The installer grabs it from Scoop's `nerd-fonts` bucket. If the exact Mono variant can't be resolved it falls back to the non-Mono variant so nothing actually breaks.

Other Nerd Fonts (Fira Code, Hack, Caskaydia Cove, Meslo, Victor Mono) live in the same bucket if you want them, but the rice's own configs only reference JetBrainsMono. Mixing fonts across the rice is how you end up with tofu boxes in your status bar.

### PowerShell

The PowerShell profile is deliberately boring:

- Sets UTF-8 I/O encoding
- Runs Fastfetch

No prompt framework. No Oh My Posh. No Starship. No "but have you tried this custom prompt written in Rust that compiles on first launch." Fast, minimal, done.

---

## Themes

The rice ships with five themes. One is the base config, four are overrides.

| Theme | Notes |
|---|---|
| `mocha` | The default. Catppuccin Mocha. Lives in `configs/`, not in `themes/`. Yes, we know that's inconsistent. It works. |
| `everforest` | Muted greens. Feels like a cabin. |
| `monochrome` | Black and white. Semantic colors collapse into each other. On purpose. Aesthetic. |
| `kanagawa` | Hokusai colors. Blue and gold. Elegant. |
| `rose-pine` | Soft purples and pinks. The "it's 11 PM and I'm still coding" theme. |

### Switching themes

```powershell
.\install.ps1 -Theme kanagawa -SkipPackages -SkipFonts
```

The `-SkipPackages -SkipFonts` tells the installer to skip the boring bits and just swap the config. Takes five seconds. Your terminal, YASB bar, Cava gradient, Fastfetch logo, and wallpapers all swap at once.

### How themes actually work

Each theme is a folder under `themes/<name>/` that mirrors `configs/`. Files present in the theme folder override the base. Files absent fall through.

```
themes/kanagawa/
├── yasb/styles.css
├── yasb/default_yasb_config.yaml   (optional — only if layout differs)
├── glazewm/default_glazewm_config.yaml (optional)
├── cava/config
├── fastfetch/config.jsonc
├── fastfetch/ascii.txt
├── terminal/settings.json
├── chronoterm/config.toml
└── wallpapers/
    ├── default.png
    └── ... your wallpapers
```

**`mocha` is a reserved name.** It refers to the base configs in `configs/` — there is no `themes/mocha/` folder. Running `-Theme mocha` is the same as running with no theme at all. Both deploy the base configs.

The active theme is recorded in the manifest. A plain `.\install.ps1` afterward respects your last choice. No "wait, why did my bar turn magenta again."

### Adding your own theme

Drop a folder under `themes/<your-name>/` with whatever files you want to override. Run `.\install.ps1 -Theme <your-name>`. No installer changes needed. No PRs to this repo needed. Just ship it.

---

## Repository structure

```text
Windows-Rice/
├── install.ps1
├── uninstall.ps1
├── README.md
├── LICENSE
├── configs/                     # base configs = the "mocha" theme
│   ├── yasb/
│   │   ├── default_yasb_config.yaml
│   │   └── styles.css
│   ├── glazewm/
│   │   └── default_glazewm_config.yaml
│   ├── cava/
│   │   └── config
│   ├── fastfetch/
│   │   ├── ascii.txt
│   │   └── config.jsonc
│   ├── btop/
│   │   └── btop.conf
│   ├── chronoterm/
│   │   └── config.toml
│   ├── powershell/
│   │   └── Microsoft.PowerShell_profile.ps1
│   └── terminal/
│       └── settings.json
├── themes/                      # override themes
│   ├── everforest/
│   ├── monochrome/
│   ├── kanagawa/
│   └── rose-pine/
├── assets/
│   ├── icons/
│   ├── wallpapers/
│   └── screenshots/
└── scripts/
```

| Path | What it is |
|---|---|
| `install.ps1` | The installer. Also the config deployer, the theme swapper, the updater, and the backup system. |
| `uninstall.ps1` | The uninstaller. Restores your old configs and removes only the packages this installer actually installed. |
| `configs/` | Base config templates. This is `mocha`. |
| `themes/` | Per-theme overrides. Folder names are theme names. |
| `assets/wallpapers/` | Base wallpapers, used when a theme doesn't provide its own. |
| `assets/screenshots/` | README images. Not deployed. |
| `scripts/` | Empty. Reserved for the future. It's been reserved for a while. |

---

## Requirements

- Windows 10 or Windows 11.
- PowerShell 5.1 or later to *run* the installer (the installer will install PowerShell 7 for the rice).
- `winget` (App Installer from the Microsoft Store).
- `git` if you're cloning. If you downloaded a ZIP, no `git` needed — but also, no `-Update` for you. That's the trade-off.

**No administrator privileges required.** Everything installs per-user. Scoop goes into your profile, configs go into your home directory, nothing touches Program Files.

If you *want* to run it as admin, you can. It won't change anything — but the rice won't be visible in your normal user session. Don't do that.

---

## Installation

```powershell
git clone https://github.com/NitroBeast76/Windows-Rice.git
cd Windows-Rice
.\install.ps1
```

### If Windows says "no"

Windows ships with an execution policy that blocks scripts downloaded from the internet. This is, in order of commonness, either:

1. Genuine security feature
2. Mild inconvenience
3. A personal attack on your afternoon

If `.\install.ps1` fails with `UnauthorizedAccess`, either:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\install.ps1
```

which bypasses the policy for one invocation, or:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

which sets it once for your user account. `RemoteSigned` means "scripts signed by a trusted publisher, or written locally, are fine." For a repo you cloned yourself, this is a reasonable long-term setting.

### What the installer does

In order:

1. Figures out where the repository lives (from the location of `install.ps1`).
2. Resolves your home directory, Documents folder, and per-user config paths. Uses the Windows API where needed — which matters because OneDrive likes to move things around without telling you.
3. Installs packages via `winget` and Scoop (unless `-SkipPackages`).
4. Installs the Nerd Font (unless `-SkipFonts` or `-SkipPackages`).
5. Deploys configuration files.
6. Deploys wallpapers.
7. Ensures PSReadLine is present (skipped under `-SkipPackages`).
8. Merges your Windows Terminal `settings.json` (unless `-SkipTerminal`).
9. Writes an installation manifest.
10. Verifies the result.
11. Prints a summary.

Everything in steps 3–9 is backed up before it overwrites anything. Everything.

---

## Installer options

| Option | Effect |
|---|---|
| `-Theme <name>` | Use a specific theme. `mocha` refers to the base configs. |
| `-Update` | Run `git pull --ff-only` before doing anything else. |
| `-SkipPackages` | Skip all package installation. Implies `-SkipFonts`. Config deployment still runs. |
| `-SkipFonts` | Skip the Nerd Font install. |
| `-SkipTerminal` | Don't touch Windows Terminal settings. |
| `-DryRun` | Show what would happen. Change nothing. |
| `-Yes` | Auto-yes to prompts. For unattended runs. |

### Examples that will actually help you

```powershell
# Preview the install. Changes nothing. Perfect for "do I trust this repo."
.\install.ps1 -DryRun

# Deploy configs only, leave Windows Terminal alone
.\install.ps1 -SkipTerminal

# Deploy configs but don't install anything
.\install.ps1 -SkipPackages -SkipFonts

# Swap to Kanagawa (fast — assumes packages are already installed)
.\install.ps1 -Theme kanagawa -SkipPackages -SkipFonts

# Pull the latest from GitHub, then reinstall
.\install.ps1 -Update

# Pull, redeploy, swap theme, all in one
.\install.ps1 -Update -Theme rose-pine -SkipPackages -SkipFonts
```

### About `-SkipPackages`

`-SkipPackages` is the "do not install anything" switch. It's the nuclear option for when you just want the config files swapped.

- It **does** skip: winget, Scoop, the Nerd Font, PSReadLine, Thide, GlazeWM AutoTiler, Flow Launcher, Windhawk, ChronoTerm, rmatrix.
- It **does not** skip: config deployment, wallpaper deployment, WT merge.

If you want a fast theme swap, use `-SkipPackages -SkipFonts`. The install finishes in seconds because there's nothing left to install.

---

## After the install

The installer puts everything on disk. But three components need a first launch before they do anything useful. This is the part most READMEs gloss over, and then you get issues on GitHub saying "the bar isn't showing."

### 1. Open a new terminal

Close the one you ran the installer in and open a fresh one. This loads the updated PATH and picks up the Nerd Font. If you skip this step, commands will be "not recognized" and the font will look wrong, and you'll open an issue, and we'll both be sad.

### 2. Start GlazeWM

```powershell
glazewm
```

GlazeWM reads its config on startup and launches two things for you:

- **YASB** — the status bar
- **GlazeWM AutoTiler** — the tiling helper

The bar should appear at the top of your screen within a second or two. The AutoTiler tray icon shows up in the notification area (bottom-right, possibly behind the `^` arrow).

**Keybindings to know:**

| Keys | Action |
|---|---|
| `Alt + H/J/K/L` | Focus windows (vim style) |
| `Alt + Shift + H/J/K/L` | Move windows |
| `Alt + 1..9` | Switch workspaces |
| `Alt + Shift + Q` | Close window |
| `Alt + F` | Fullscreen |
| `Alt + V` | Open Windows Terminal |
| `Alt + W` | Wallpaper gallery |
| `Alt + Space` | Flow Launcher |
| `Alt + Shift + E` | Exit GlazeWM |
| `Alt + Shift + R` | Reload config |

### 3. Configure Flow Launcher

Open **Flow Launcher** from the Start Menu (there's no `flow` CLI shim, don't try to type it). First run walks you through theme and indexing. Once done, `Alt+Space` opens it.

Since Thide hides the taskbar, Flow Launcher is your primary "launch programs by name" tool. It replaces the Start menu search you no longer have.

### 4. Configure Windhawk

Open **Windhawk** from the Start Menu. **No mods are installed by default** — the installer only puts the platform in place.

Windhawk runs mods *inside* Windows system processes. A bad mod can crash Explorer. Install them one at a time and test between each. Good starters:

- `explorer-frame-styler` — subtle Explorer theming
- `start-menu-styler` — Start menu theming

Taskbar mods are useless here because Thide hides the taskbar.

### 5. Log out if something is still stale

Fonts and some shell extensions refresh only on login. If your terminal font still looks wrong after step 1, log out and back in. This is the correct answer approximately 95% of the time when ricing breaks in a way that makes no sense.

---

## CLI tools cheat sheet

None of these require configuration. They work from any shell once PATH is refreshed.

| Tool | What it does | Try it |
|---|---|---|
| `fastfetch` | System info on shell start | `fastfetch` |
| `btop` | Resource monitor | `btop` |
| `fd` | `find`, but modern | `fd config` |
| `rg` | `grep`, but fast | `rg "TODO" .` |
| `fzf` | Fuzzy finder | `ls \| fzf` |
| `zoxide` | Smart `cd` | `z project` (after `cd`-ing once) |
| `yazi` | Terminal file manager | `yazi` |
| `yt-dlp` | Media downloader | `yt-dlp <url>` |
| `ffmpeg` | Media conversion | `ffmpeg -i in.mp4 out.mkv` |
| `7z` | Archives | `7z x archive.zip` |
| `jq` | JSON processor | `curl ... \| jq .` |
| `magick` | Image manipulation | `magick input.png -resize 50% out.png` |
| `cava` | Audio visualizer | (runs inside YASB) |
| `thide` | Hide/show taskbar | `thide hide` / `thide show` |
| `chronoterm` | Clock in your terminal | `chronoterm` |
| `rmatrix` | Falling code | `rmatrix` |

### A few that change how you work

**`zoxide`** learns from where you `cd`. After a few days, `z proj` jumps to whatever project directory you visit most. Enable tab completion with `zoxide init powershell | Out-String | Invoke-Expression` in your profile.

**`fzf`** is at its best piped. `git branch | fzf` picks a branch. `cat file | fzf` searches inside it. Bare `fzf` opens a file selector in the current directory.

**`yazi`** is a full file manager with previews, archives, and batch ops. Vim keybinds: `hjkl` to move, `Enter` to open, `y` to yank, `p` to paste. Press `~` for the cheat sheet.

**`magick`** is what the rice uses to resize wallpapers before deploying. If you want to prep your own:

```powershell
magick input.jpg -resize 1920x -strip "$HOME\Pictures\Windows-Rice\my-wallpaper.jpg"
```

Caps width at 1920, preserves aspect ratio, strips metadata. Same command the shrink script uses.

**`chronoterm`** and **`rmatrix`** are "just because you can." There's no productivity gain. There is, however, a clock and a Matrix effect. That's the point.

### When a command says "not recognized"

Close and reopen the terminal. This fixes it 90% of the time because PATH changes only apply to new shells.

If it still doesn't work:

```powershell
winget list --id sharkdp.fd --exact   # replace with whichever tool
```

If the package shows as installed but the command isn't found, see *Current Limitations* — btop is the notorious one.

---

## Configuration locations

Everything deploys under your home directory. The installer resolves `~` from `$env:USERPROFILE`, so no usernames are hardcoded anywhere.

| Source | Destination |
|---|---|
| `configs/yasb/default_yasb_config.yaml` | `~/.config/yasb/config.yaml` |
| `configs/yasb/styles.css` | `~/.config/yasb/styles.css` |
| `configs/glazewm/default_glazewm_config.yaml` | `~/.glzr/glazewm/config.yaml` |
| `configs/cava/config` | `~/.config/cava/config` |
| `configs/fastfetch/config.jsonc` | `~/.config/fastfetch/config.jsonc` |
| `configs/fastfetch/ascii.txt` | `~/.config/fastfetch/ascii.txt` |
| `configs/btop/btop.conf` | `~/.config/btop/btop.conf` |
| `configs/chronoterm/config.toml` | `%APPDATA%\chronoterm\config.toml` |
| `configs/powershell/Microsoft.PowerShell_profile.ps1` | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` |
| `configs/terminal/settings.json` | Merged into Windows Terminal's user `settings.json` |
| `assets/wallpapers/**` | `~/Pictures/Windows-Rice/**` |
| Backups and manifest | `~/.windows-rice-backup/` |

**Fastfetch uses one location:** `~/.config/fastfetch/`. Not two, not three. Not `%APPDATA%`. One.

**OneDrive users, listen up.** On a machine signed in with a Microsoft account, `~/Documents/` often resolves to `~/OneDrive/Documents/`. The installer uses the Windows API to resolve the *effective* Documents folder, so the profile lands wherever PowerShell 7 actually looks. You don't need to do anything. But if you ever wonder why your `~/Documents/PowerShell` folder is empty, that's why.

Same story for `~/Pictures/Windows-Rice/` — resolved via the API so it lands in whatever Pictures folder Windows is using.

---

## Startup chain

GlazeWM launches YASB from its own config. One mechanism, no duplicate launches.

```
Windows logon
      │
      ▼
GlazeWM starts
      │
      ▼
GlazeWM startup_commands → shell-exec → yasb.exe
      │
      ▼
YASB loads ~/.config/yasb/config.yaml + styles.css
```

`shell-exec` is required because GlazeWM parses each entry as one of its own subcommands, not as a raw shell string. You can't just put `yasb.exe` and hope. Well, you can hope. It won't work.

On cold boot, YASB may briefly show its "GlazeWM is offline" message before the IPC pipe is ready. It reconnects within seconds. This is not a bug, it's a race condition that everyone loses gracefully.

---

## Windows Terminal

Windows Terminal's `settings.json` is **merged**, not overwritten. This is a hard design choice, not a "we'll get around to it."

The installer:

- finds the file via the installed `Microsoft.WindowsTerminal` AppX package identity;
- only falls back to a folder scan when exactly one candidate exists;
- reads and parses your existing file;
- reads the repo's `configs/terminal/settings.json` as a patch;
- merges by stable key:
  - `profiles.list` — by `guid` (your custom profiles are preserved)
  - `schemes` — by `name`
  - `actions` and `keybindings` — replaced by `id` for entries the rice owns, so rerunning doesn't duplicate them
  - top-level scalars (`defaultProfile`, `tabWidthMode`, `useAcrylicInTabRow`) — rice wins
- writes a timestamped backup of the original;
- validates the merged JSON before writing.

**If your settings.json is unparseable** — for example because it has JSONC comments that PowerShell 5.1's `ConvertFrom-Json` can't read — the installer leaves the file untouched and reports the WT step as skipped. It does not corrupt your file to force the merge through.

The merge preserves unrelated WSL, SSH, and custom profiles, unrelated schemes, and unrelated keybindings. It is not a general-purpose conflict resolver. It's a "don't break the user's terminal" merger. There's a difference.

---

## Backups & Safety

The installer does not blindly overwrite things. Here's exactly what it does:

Before replacing any file that already exists:

1. Compares source and destination with SHA256.
2. If identical, does nothing. No copy. No backup. No busywork.
3. If different, writes a timestamped backup first.

Backups live under `~/.windows-rice-backup/`, in a layout that mirrors the component:

```text
.windows-rice-backup/
├── manifest.json
├── yasb/
├── glazewm/
├── cava/
├── fastfetch/
├── btop/
├── chronoterm/
├── powershell/
├── terminal/
└── wallpapers/
```

Backup filenames include a timestamp:

```text
config.yaml.backup-2026-09-15-203000
```

**The backup system only touches files this project manages.** It's not a system-wide backup tool. It's not a Time Machine. It doesn't care about your photos.

---

## Installation manifest

`install.ps1` records the packages it *actually installed* in:

```text
~/.windows-rice-backup/manifest.json
```

Packages that were already present before the installer ran are marked `AlreadyInstalled` and are **not** added to the manifest. This is the manifest's entire purpose.

`uninstall.ps1 -RemovePackages` reads the manifest. If a package isn't in it, that package isn't touched. Ever. This means:

- You had GlazeWM before running the rice? Uninstaller leaves it.
- You had PowerShell 7 before running the rice? Uninstaller leaves it.
- You had YASB before running the rice? Well, you had good taste, and uninstaller leaves it.

If the manifest is missing or unreadable, package removal is skipped entirely with a warning. Restoring configs still runs. Conservative by design — we'd rather leave software installed than uninstall something you didn't ask us to uninstall.

**The manifest is a record of what this installer did.** It is not a full inventory of your machine. Don't use it as one.

---

## Uninstallation

```powershell
.\uninstall.ps1
```

Default behaviour restores config files from backups where backups exist. Files that were deployed fresh (no prior version on disk) are left in place.

### Options

| Option | What it does |
|---|---|
| `-RemovePackages` | Uninstall the packages recorded in the manifest. PowerShell 7 and Windows Terminal are deliberately kept. |
| `-Purge` | Also delete `~/.windows-rice-backup/` and everything in it. Prompts for confirmation. |
| `-DryRun` | Show what would happen. Change nothing. |
| `-Yes` | Auto-yes. For unattended runs. |

### Examples

```powershell
# Restore configs. Keep the packages.
.\uninstall.ps1

# Restore configs and uninstall rice-installed packages.
.\uninstall.ps1 -RemovePackages

# Restore, uninstall, and delete all backups too.
.\uninstall.ps1 -RemovePackages -Purge
```

`-RemovePackages` and `-Purge` do different things:

- **`-RemovePackages`** uninstalls only packages the manifest records as installed by Windows-Rice.
- **`-Purge`** removes the backup and manifest data itself, once restoration is done.

If no manifest exists, `-RemovePackages` prints a warning and performs no removal. This is intentional. It means you can't accidentally run the rice uninstaller on a machine that has never had the rice installed and have it start deleting things.

---

## Wallpapers

Wallpapers live in two places:

- `assets/wallpapers/` — the base set, used when a theme doesn't provide its own
- `themes/<name>/wallpapers/` — theme-specific wallpapers, which **replace** the base set entirely for that theme

The installer deploys them to `~/Pictures/Windows-Rice/` (resolved via the API, so OneDrive-safe) and sets `default.*` as your desktop wallpaper on first install.

YASB's wallpaper widget points at that folder, so everything shows up in the gallery (`Alt+W`).

Each wallpaper goes through the same backup path as every other managed file. If a same-named file already exists in the destination, it's backed up before being replaced. Uninstall restores backed-up originals.

### Current limitation

Wallpapers deployed fresh — meaning they replaced nothing because no file of that name existed before — are left in place after uninstall. The backup system can only restore files that had a previous version to back up. Same rule applies to fresh config files.

The empty `~/Pictures/Windows-Rice/` directory is removed by uninstall only when empty. If you've added your own wallpapers to it, they stay.

### Want more wallpapers?

The bundled set is intentionally small — enough to get started, not enough to bloat a git repo. For bigger collections:

- [SleepyCatHey/CozyPixels](https://github.com/SleepyCatHey/CozyPixels/tree/main/Catppuccin) — hundreds of Catppuccin-compatible wallpapers, sorted by category
- [AEON-mod/My-Visuals](https://github.com/AEON-mod/My-Visuals) — themed collections; `dark_amoled` and `cozy_cold` fit this rice best

To add your own, drop files into `assets/wallpapers/` before running `install.ps1`, or copy them into `~/Pictures/Windows-Rice/` after install. YASB picks up new files automatically.

---

## Customization

Edit files under `configs/`, rerun `install.ps1`, done. That's the workflow.

| Path | What it controls |
|---|---|
| `configs/yasb/default_yasb_config.yaml` | Bar layout, widget list, widget behaviour |
| `configs/yasb/styles.css` | Colours, spacing, fonts |
| `configs/glazewm/default_glazewm_config.yaml` | Tiling layout, gaps, keybindings |
| `configs/cava/config` | Audio visualizer |
| `configs/fastfetch/config.jsonc` | Fastfetch modules and colours |
| `configs/fastfetch/ascii.txt` | ASCII logo |
| `configs/btop/btop.conf` | btop settings |
| `configs/chronoterm/config.toml` | ChronoTerm clock |
| `configs/powershell/Microsoft.PowerShell_profile.ps1` | Shell startup |
| `configs/terminal/settings.json` | Rice-owned Terminal settings |
| `themes/<name>/` | Per-theme overrides of any of the above |

**YASB live-reloads.** `watch_stylesheet: true` and `watch_config: true` mean edits to the YASB YAML and CSS take effect without restarting the bar. Everything else needs a rerun of the installer or a manual reload.

**Deployed files are not synced back.** If you edit `~/.config/yasb/config.yaml` directly, then rerun the installer, your edits get backed up and replaced. To keep changes, edit the files under `configs/` and re-run.

The backup system makes this recoverable, but it's easier to just do it the right way.

---

## Updating the rice

```powershell
.\install.ps1 -Update
```

This runs `git pull --ff-only` first, then continues with the normal install. Use `--ff-only` specifically so your local commits don't create merge weirdness. If you've made local changes, `git pull` will refuse and print a message telling you to commit or stash.

For a fast "I just want the latest configs":

```powershell
.\install.ps1 -Update -SkipPackages -SkipFonts
```

That pulls, redeploys configs, redeploys wallpapers, merges WT, and skips all the package-checking work. Takes seconds.

---

## Current limitations

**Weather widget.** YASB's weather widget requires an API key and a location, which this repo does not ship. If you want it, edit `api_key` and `location` in the deployed `~/.config/yasb/config.yaml`. The installer won't create an account or embed a key on your behalf. That would be weird.

**btop on PATH.** Winget installs `btop4win` as a portable package and adds its own package folder to PATH — but not the shared `Links` folder that holds the `btop.exe` alias. So `btop4win` may be callable while `btop` isn't. Close and reopen your terminal first. If it still fails, manually add `%LOCALAPPDATA%\Microsoft\WinGet\Links` to your user PATH.

**Freshly deployed files aren't removed by uninstall.** Files deployed by the installer that had no prior version on disk are left in place. Only files that replaced an existing version can be restored. Same rule applies to wallpapers.

**JSONC in Windows Terminal settings.** If your existing `settings.json` has comments that PowerShell's `ConvertFrom-Json` can't parse, the merge is skipped. The installer doesn't strip comments or modify the file. It leaves it alone.

**PowerShell 5.1 execution policy.** Windows ships with a policy that blocks scripts. If `.\install.ps1` fails with `UnauthorizedAccess`, use `PowerShell -ExecutionPolicy Bypass -File .\install.ps1` or set `RemoteSigned` for the current user.

**Flow Launcher and Windhawk don't install CLI shims.** Launch from the Start Menu. Yes, this is slightly annoying. No, we can't fix it without hacking the installer for those specific tools.

---

## Design philosophy

**Automate the boring parts without treating the user's existing Windows setup as disposable.**

In practice:

- **Reproducible.** Same repo, same result on any Windows 10/11 machine. No hardcoded paths, no hardcoded usernames, no "works on my machine."
- **Safe.** Existing config is compared, backed up, and preserved where possible. Nothing is blindly overwritten.
- **Reversible.** Backups and the manifest let `uninstall.ps1` restore files and remove only what this installer put there.
- **Organised.** Configuration lives under predictable per-user locations.
- **Transparent.** The installer prints what it's doing. `-DryRun` shows the plan before anything changes.

**The installer is not zero-risk.** It modifies files under your home directory. It installs software. The backup and manifest systems exist to make those changes recoverable — not to make them disappear.

If you don't like what it did, `.\uninstall.ps1 -RemovePackages -Purge` puts things back.

---

## Credits

Windows-Rice configures software made by other people. Upstream projects include:

- **GlazeWM** — tiling window manager for Windows
- **YASB** — status bar
- **CAVA** — audio visualizer
- **Fastfetch** — system information
- **Windows Terminal**, **PowerShell** — Microsoft
- **btop**, **fd**, **fzf**, **ripgrep**, **yazi**, **yt-dlp**, **FFmpeg**, **7-Zip**, **jq**, **zoxide**, **ImageMagick** — the CLI power tools that make a shell worth using
- **ChronoTerm**, **rmatrix**, **Thide**, **GlazeWM AutoTiler**, **Flow Launcher**, **Windhawk** — the extras that make it fun
- **JetBrains Mono** and the **Nerd Fonts** project for the font
- **Catppuccin**, **Everforest**, **Kanagawa**, **Rosé Pine** for the palettes

Upstream URLs are intentionally omitted here until they're verified for this repository.

---

## License

Windows-Rice is released under the MIT License. See [`LICENSE`](LICENSE) for the full text.

The MIT License covers the PowerShell scripts, YAML/CSS/JSON configuration files, and other original content in this repository. It does not relicense third-party software that Windows-Rice installs or configures, nor the color palettes, fonts, or ASCII art sourced from other projects — those remain under their own licenses and are acknowledged in [Credits](#credits) above.

If you fork this, remix it, and ship something cool, you don't have to credit us. But it would be nice if you did.