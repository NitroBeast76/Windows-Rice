# Making a Windows-Rice theme

A complete guide to creating, editing, and using your own Windows-Rice theme. Written for the person who cloned this repo, saw ten themes they liked, and thought *"I want one in my own colors."*

Everything here is optional. You can run Windows-Rice forever without ever opening this file. But if you want a theme that isn't on the list — a palette you already love, a monochrome version of an existing theme, something that matches your wallpaper — this is the path.

It's your rice. Do whatever you want with it.

---

## Contents

- [Making a Windows-Rice theme](#making-a-windows-rice-theme)
  - [Contents](#contents)
  - [Before you start](#before-you-start)
  - [What a theme actually is](#what-a-theme-actually-is)
    - [The pattern that runs through every file](#the-pattern-that-runs-through-every-file)
    - [What happens when you switch themes](#what-happens-when-you-switch-themes)
  - [Quick path — the TUI](#quick-path--the-tui)
  - [Manual path — copy and edit](#manual-path--copy-and-edit)
  - [Which files do I actually need to touch?](#which-files-do-i-actually-need-to-touch)
  - [File reference](#file-reference)
    - [`yasb/styles.css` — the bar](#yasbstylescss--the-bar)
    - [`starship/starship.toml` — the prompt](#starshipstarshiptoml--the-prompt)
    - [`terminal/settings.json` — Windows Terminal](#terminalsettingsjson--windows-terminal)
    - [`chronoterm/config.toml` — the clock](#chronotermconfigtoml--the-clock)
    - [`cava/config` — the visualizer](#cavaconfig--the-visualizer)
    - [`fastfetch/ascii.txt` — the logo](#fastfetchasciitxt--the-logo)
    - [`wallpapers/` — the wallpaper set](#wallpapers--the-wallpaper-set)
    - [`glazewm/default_glazewm_config.yaml` — rarely needed](#glazewmdefault_glazewm_configyaml--rarely-needed)
  - [Worked example: making gruvbox-dark](#worked-example-making-gruvbox-dark)
  - [Testing your theme](#testing-your-theme)
  - [Sharing your theme](#sharing-your-theme)
  - [Reference](#reference)
    - [YASB color slots](#yasb-color-slots)
    - [Starship palette slots](#starship-palette-slots)
    - [Wallpaper format guidance](#wallpaper-format-guidance)
    - [Useful tools](#useful-tools)
    - [Color resources](#color-resources)
  - [Getting unstuck](#getting-unstuck)

---

## Before you start

**You need:**

- The repo cloned on the machine you want to theme
- Windows-Rice installed at least once (so `win-rice` works and the TUI is available)
- A text editor. VS Code is the obvious choice; it color-codes CSS, TOML, JSON, and YAML out of the box, and it shows a color swatch next to any `#rrggbb` value you hover over.

**You don't need:**

- To know PowerShell. The TUI does the work; the commands in this guide are copy-paste.
- To know CSS. Every color in the YASB stylesheet lives in a block of ten named values at the top of the file. Everything below that block is boilerplate you never touch.
- To ask permission. The repo is a template. Fork it, rip it apart, delete the themes you don't use. Nothing about it is sacred.

**Time expectations:**

- **Fork an existing theme and change its palette:** 20–40 minutes for something good.
- **Build from base configs:** 1–2 hours, mostly deciding on colors.
- **Add a wallpaper set:** 15 minutes if you have the images, longer if you're curating.

**What "done" looks like:**

- Your theme shows up in `win-rice` → Change theme
- Every screen — bar, prompt, terminal, clock, wallpaper — uses your palette
- Nothing is unreadable. The most common theme bug is a color that looked fine in the config file but has no contrast against the bar background.

---

## What a theme actually is

A Windows-Rice theme is a **folder** under `themes/<name>/` that mirrors the layout of `configs/`. Only the files you include in the theme folder get deployed. Everything else falls through to the base configs.

Concretely:

```
configs/                          ← the base configs (aka "mocha")
├── yasb/
│   ├── default_yasb_config.yaml
│   └── styles.css
├── glazewm/
│   └── default_glazewm_config.yaml
├── cava/
│   └── config
├── fastfetch/
│   ├── ascii.txt
│   └── config.jsonc
├── starship/
│   └── starship.toml
├── terminal/
│   └── settings.json
├── chronoterm/
│   └── config.toml
└── powershell/
    └── Microsoft.PowerShell_profile.ps1

themes/kanagawa/                  ← a theme folder
├── yasb/
│   ├── default_yasb_config.yaml
│   └── styles.css                 ← overrides configs/yasb/styles.css
├── glazewm/
│   └── default_glazewm_config.yaml
├── cava/
│   └── config
├── fastfetch/
│   ├── ascii.txt
│   └── config.jsonc
├── starship/
│   └── starship.toml
├── terminal/
│   └── settings.json
├── chronoterm/
│   └── config.toml
└── wallpapers/
    └── default.jpg
```

When you run `win-rice` → Change theme → kanagawa, the installer resolves each file by trying `themes/kanagawa/<path>` first and falling back to `configs/<path>` if the theme folder doesn't have it. The resolved files get deployed to their usual per-user locations:

| Theme file | Deploys to |
|---|---|
| `yasb/styles.css` | `~/.config/yasb/styles.css` |
| `yasb/default_yasb_config.yaml` | `~/.config/yasb/config.yaml` |
| `starship/starship.toml` | `~/.config/starship.toml` |
| `terminal/settings.json` | Merged into Windows Terminal's user `settings.json` |
| `chronoterm/config.toml` | `%APPDATA%\chronoterm\config.toml` |
| `cava/config` | `~/.config/cava/config` |
| `fastfetch/ascii.txt` | `~/.config/fastfetch/ascii.txt` |
| `fastfetch/config.jsonc` | `~/.config/fastfetch/config.jsonc` |
| `glazewm/default_glazewm_config.yaml` | `~/.glzr/glazewm/config.yaml` |
| `wallpapers/**` | `~/Pictures/Windows-Rice/<name>/**` |

Three consequences worth internalizing:

**You don't need every file.** If your theme uses the same GlazeWM layout as the base, don't include a GlazeWM config. It falls through to `configs/`. Less to maintain, less to break.

**Files that ARE present override entirely.** There's no merge between a theme file and a base file. If you include `yasb/styles.css`, it replaces the base stylesheet completely.

**`mocha` is reserved.** It refers to `configs/` directly. There is no `themes/mocha/`. If you pass `-Theme mocha`, the installer uses the base configs, same as passing no theme at all. Don't name your theme `mocha`.

### The pattern that runs through every file

YASB, Starship, Windows Terminal, and ChronoTerm were written by four different people. But their configs are organized the same way, because it's the only shape that works:

**A small block of named slots at the top, and everything else references those slots.**

- **YASB** — `yasb/styles.css` opens with a `:root` block. It defines CSS custom properties — `--accent`, `--background`, `--text`, and about a dozen others — and every widget rule below uses `var(--accent)` rather than a literal hex value. Change the block, the whole bar changes. **All ten colors live in ten lines.**
- **Starship** — `starship/starship.toml` ends with `[palettes.<name>]` blocks. Each block defines named colors. The format string at the top of the file references them by name (`fg:red`, `bg:sapphire`).
- **Windows Terminal** — `terminal/settings.json` uses fixed key names (`background`, `foreground`, `red`, `brightRed`). Every field is one hex value.
- **ChronoTerm** — `chronoterm/config.toml` is one hex value. The "theme" for this component is a single color.

Same idea, four tools. Once you see it, the workflow for every one of them is the same: **find the block of named values, change the values, save.** You are not hunting for scattered hexes. You are editing a small, concentrated definition and letting everything that references it follow.

This is the mental model for every file in the rest of this guide.

### What happens when you switch themes

Every file the installer manages gets redeployed on a theme switch — the installer resolves each file to either the new theme's version or, if the new theme doesn't include it, the base config. There is no "leave it alone because the old theme had it" case.

Concretely: if you switch from theme A (which ships a custom `glazewm/default_glazewm_config.yaml`) to theme B (which doesn't), the GlazeWM config deployed by A gets overwritten by the base config from `configs/glazewm/`. Theme B doesn't inherit A's customizations. There are no leftovers.

The one file that behaves slightly differently is the wallpaper set. The deployed wallpaper folder for a theme is **synced** — files in the theme's source get copied in, and any file in the deployed folder that isn't in the source gets removed. So if theme A shipped 40 wallpapers and theme B ships 8, switching to B leaves exactly 8 wallpapers in `~/Pictures/Windows-Rice/<theme>/`, not 48.

The practical implication for theme authors: **you don't have to worry about cleaning up after a previous theme.** If your theme doesn't override a file, the base config takes over. If your theme ships a partial wallpaper set, the deployed folder matches what you shipped, nothing more.

---

## Quick path — the TUI

The TUI has a guided flow that scaffolds a new theme in about 30 seconds. This is the recommended path.

**1. Open the TUI.**

```powershell
win-rice
```

If you're on a fresh install and `win-rice` isn't on your PATH yet, open a shell in the repo folder and run `.\rice.ps1` instead.

**2. Pick "Create a new theme".**

```
  ╭────────────────────────────────────────────────────────╮
  │ MENU                                                   │
  ╰────────────────────────────────────────────────────────╯

    Repository    C:\Users\you\Windows-Rice
    Theme         kanagawa
    Updated       2026-10-15 14:23

    1  Change theme          Switch to a different look
    2  Update                Pull latest and redeploy
    3  Status                Show what's installed
    4  Create a new theme    Scaffold a theme folder
    5  Uninstall             Restore configs, remove packages

    0  Exit

  Choice: 4
```

**3. Pick a source theme.**

You're choosing which existing theme to fork. Every file from the source gets copied into your new theme folder, so you start from a working palette rather than a blank slate.

```
  ╭────────────────────────────────────────────────────────╮
  │ CREATE THEME — PICK A SOURCE                           │
  ╰────────────────────────────────────────────────────────╯

    1  mocha       ███ ███ ███  Catppuccin Mocha (default)
    2  ayu-dark    ███ ███ ███  Deep navy, orange accents
    3  dracula     ███ ███ ███  Purple and pink on near-black
    4  everforest  ███ ███ ███  Muted greens, feels like a cabin
    5  gruvbox     ███ ███ ███  Retro warm browns and oranges
    6  kanagawa    ███ ███ ███  Hokusai colors, blue and gold
    7  monochrome  ███ ███ ███  Black and white, semantic collapse
    8  nord        ███ ███ ███  Cool arctic blues and greys
    9  rose-pine   ███ ███ ███  Soft purples and pinks
   10  tokyo-night ███ ███ ███  Neon blue-purple with cyan

    0  Cancel

  Source theme > 5
```

Each theme shows three color swatches next to its name — those are `red`, `yellow`, and `sapphire` from the theme's own `starship.toml` palette. It's a quick visual read on what you're picking.

**How to pick a source:** match the mood, not the palette. If you want a warm dark theme, fork gruvbox or everforest. If you want cool, fork nord or kanagawa. You're going to change every hex value anyway — what you're inheriting is the *structure*.

**4. Name it.**

```
  New theme name (lowercase, digits, hyphens, underscores)
  > gruvbox-dark
```

Rules:

- Lowercase letters, digits, hyphens, underscores only
- Must start with a letter
- 2–30 characters
- Cannot be `mocha` (reserved)
- Cannot collide with an existing theme folder

**5. Decide on wallpapers.**

```
  Copy 78 wallpapers from 'gruvbox' (~16 MB)? [y/N]
  You can add your own wallpapers later either way.
```

Defaults to No. Say yes if you want a working theme immediately and don't care about wallpapers yet.

**6. Edit the theme.**

The flow finishes with a summary screen listing what it created and where:

```
  ╭────────────────────────────────────────────────────────╮
  │ THEME CREATED                                          │
  ╰────────────────────────────────────────────────────────╯

  [ok] Theme 'gruvbox-dark' created.

    Location       C:\Users\you\Windows-Rice\themes\gruvbox-dark
    Based on       gruvbox
    Configs        9 files
    Wallpapers     78 files

  ╭────────────────────────────────────────────────────────╮
  │ COLORS — START HERE                                    │
  ╰────────────────────────────────────────────────────────╯

    yasb\styles.css              Bar colors, spacing, fonts
    starship\starship.toml       Set the palette and add a block
    terminal\settings.json       Point to a Windows Terminal scheme
    chronoterm\config.toml       Clock accent color

  Open the folder now? [y/N]
```

Say yes and Explorer opens to the theme folder. Now the real work starts — see [`yasb/styles.css`](#yasbstylescss--the-bar) for the actual editing workflow.

**7. Apply it.**

Once you've made your edits, go back to the TUI:

```
  Choice: 1
  # pick your new theme from the picker
```

The change deploys in about five seconds. GlazeWM reloads itself. The bar repaints in your new palette.

**8. Iterate.**

This is where most of the time goes. The loop:

1. Edit `yasb/styles.css` in your theme folder
2. Save
3. YASB live-reloads and the bar repaints
4. Look at the bar
5. Repeat

Because YASB watches its stylesheet, you don't need to redeploy to see CSS changes. The feedback loop is: save, look. Nothing else.

For other files (Starship, Terminal, etc.), the loop is slightly slower — but the whole guide below is organized to make each one fast.

---

## Manual path — copy and edit

If you'd rather skip the TUI, or you're creating multiple themes at once, or you want to script the whole thing:

**1. Copy an existing theme.**

```powershell
cd C:\Users\you\Windows-Rice
Copy-Item themes\gruvbox themes\gruvbox-dark -Recurse
```

Pick the theme closest to what you're going for. Match the *mood*:

| If you want | Fork |
|---|---|
| Warm, dark, retro | `gruvbox` or `everforest` |
| Cool, dark, modern | `nord` or `tokyo-night` |
| Blue and gold, elegant | `kanagawa` |
| Purple and pink | `dracula` or `rose-pine` |
| Grayscale / very muted | `monochrome` |
| Minimal, single accent | `ayu-dark` |
| The default look | `mocha` (via `.\scaffold-theme.ps1`) |

**2. Or use `scaffold-theme.ps1`.**

This creates a theme folder pre-populated with **base** config files (mocha colors):

```powershell
.\scaffold-theme.ps1 -Names gruvbox-dark
```

Multiple names create multiple themes in one pass:

```powershell
.\scaffold-theme.ps1 -Names my-dark,my-light,my-monochrome
```

Useful when you're starting a family of themes that share a common base and you want them all scaffolded at once.

**3. Edit the files.**

Same workflow as the TUI path. Start with `yasb/styles.css`.

**4. Apply and test.**

```powershell
.\install.ps1 -Theme gruvbox-dark -SkipPackages -SkipFonts
```

The `-SkipPackages -SkipFonts` flags skip all the package-checking work, so the deploy is quick. This is the fast path for iterating.

---

## Which files do I actually need to touch?

Depends on how much of the rice you want to change. Here's the decision tree:

**A theme that changes only the bar colors (minimum viable theme):**

```
themes/<name>/
├── yasb/styles.css
└── wallpapers/default.jpg    (or .png / .webp)
```

Two files. This isn't a stripped-down compromise — it's what most ricers actually build. The bar is 90% of what anyone sees, and because YASB's colors live in a `:root` block of ten variables, changing them is editing **ten lines**.

The widget rules below `:root` are boilerplate. They reference the variables by name. You are not maintaining them, you're overriding the values they read from.

**What a theme fundamentally is:** a palette. Every component in this rice that has colors reads them from a small block of named slots. A theme is the set of values those slots take. Everything else — the shape of the bar, the layout of the prompt, the terminal's keybindings — is inherited from the base config and stays put unless you deliberately override it.

**A theme that changes the bar and the prompt:**

```
themes/<name>/
├── yasb/styles.css
├── starship/starship.toml
└── wallpapers/default.jpg
```

Three files. This is what most of the shipped themes look like minus the extra bits.

**A theme that changes everything user-visible:**

```
themes/<name>/
├── yasb/styles.css
├── starship/starship.toml
├── terminal/settings.json
├── chronoterm/config.toml
├── cava/config
├── fastfetch/ascii.txt
└── wallpapers/
```

Seven slots. This is the "full palette" shape — every colored surface in the rice follows your theme.

**A theme that also changes structure (rare):**

Add `yasb/default_yasb_config.yaml` (different widgets/layout) or `glazewm/default_glazewm_config.yaml` (different keybindings/gaps) or `fastfetch/config.jsonc` (different modules). See each file's section below for why you usually don't want to.

There is no "correct" number of files. Add files as you need them.

---

## File reference

Everything below is optional except `yasb/styles.css` and `wallpapers/default.*`.

---

### `yasb/styles.css` — the bar

**What it controls:** every color in the status bar, plus spacing, fonts, and some structural bits.

**The structure — and why this file is not what it looks like from the outside:**

The file is ~60 KB. If you open it expecting to find a flat list of hex values scattered across it, you're going to be confused for a while. That's not what it is.

Here's what's actually in it:

1. **A single `@import` line at the top** — `@import "yasb_colors.css";`. See below.
2. **A `:root` block** — CSS custom properties. These are the semantic color names: `--background`, `--accent`, `--text`, and so on.
3. **A catalog of commented-out palettes inside `:root`** — one commented block per popular theme.
4. **Every widget rule below `:root` references `var(--accent)` and friends** — no literal hex values in the widget rules themselves.

**The entire palette lives in a block of ten lines.** The 60 KB below `:root` is structure — which widget uses which variable, how they're spaced, where corners round. Your theme almost never touches it.

**The `:root` block, in detail:**

```css
:root {
    /* Font and size variables — leave these alone */
    --icons-font: "JetBrainsMono NFP", "JetBrainsMono Nerd Font Propo";
    --system-font: "Segoe UI Variable", "Segoe UI";
    --fontSize: 12px;
    --iconSize: 16px;
    --border-radius: 14;
    /* ... more layout variables ... */

    --yasb-icon-fg: var(--text);   /* alias — don't edit */

    /*colors*/

    /* Catppuccin Latte */
    /* --background: #eff1f5;
    --background2: #ccd0da;
    --accent: #7c7f93;
    --text: #4c4f69;
    --accentText: #eff1f5;
    --hover: #bcc0cc;
    --mutedBG: #e6e9ef;
    --border: #ccd0da;
    --redFlash: #d20f39;
    --subtext: #6c6f85; */

    /* Catppuccin Frappé */
    /* --background: #303446;
    ... */

    /* Catppuccin Mocha — active */
    --background: #1e1e2e;
    --background2: #313244;
    --accent: #9399b2;
    --text: #cdd6f4;
    --accentText: #313244;
    --hover: #45475a;
    --mutedBG: #181825;
    --border: #313244;
    --redFlash: #f38ba8;
    --subtext: #a6adc8;

    /* Gruvbox Material Dark Soft */
    /* --background: #32302F;
    ... */
}
```

Every theme block has **exactly ten variables**. That's the whole palette:

| Variable | Role |
|---|---|
| `--background` | Bar background, popup backgrounds, menu backgrounds |
| `--background2` | Secondary background — buttons, separators, stat-item boxes |
| `--accent` | Active/selected state — active workspace, selected calendar day, media buttons, accent elements |
| `--text` | Primary text everywhere |
| `--accentText` | Text on top of `--accent`. Usually a very dark color for contrast |
| `--hover` | Hover state background for menu items and buttons |
| `--mutedBG` | Deep backgrounds — checkbox indicators, low-contrast boxes |
| `--border` | Borders on popups and separators |
| `--redFlash` | Alert / danger state — critical battery, active quick-action hover, system-control hover |
| `--subtext` | Secondary text — status labels, descriptions, muted info |

Exactly one block is uncommented at a time. That's the active palette.

**What's in the catalog:**

The base `styles.css` ships with these palettes ready to uncomment, in this order top to bottom:

- Catppuccin Latte (light)
- Catppuccin Frappé
- Catppuccin Macchiato
- **Catppuccin Mocha** ← the base theme, active by default
- Gruvbox Material Dark Soft
- Your Lie In April
- Sousou no Frieren
- Everforest Dark Soft
- Monochrome
- Tokyo Night
- Monochrome Light
- MonochromeAccentDark
- MonochromeAccentLight
- Everforest Dark
- Nord
- Kanagawa
- Everforest
- Rosé Pine

That's eighteen ready-made palettes. If one of them is close to what you want, uncomment it and adjust. If none is, copy the closest one and start changing values.

The themed folders under `themes/` correspond to a subset of these — a theme's `yasb/styles.css` is typically just the base stylesheet with a different block uncommented, plus whatever adjustments that theme made.

**The `@import "yasb_colors.css"` line is dead.** It's a leftover from an earlier version of the config. The `:root` block below it redefines every variable the import would provide, so the import is shadowed — its contents, even if a `yasb_colors.css` existed, would be overridden.

**You do not need to ship a `yasb_colors.css` file in your theme folder.** Leave the import alone or delete it; it makes no difference to how the theme renders.

**The actual workflow:**

1. Open `yasb/styles.css`.
2. Look at `:root` at the top of the file.
3. Find the palette block closest to what you want.
4. Make that block active — uncomment it and comment out whatever was active.
5. Change the values that need changing. A full palette swap is typically ten hex values in one block.
6. Save. YASB live-reloads and the bar repaints.

That's the workflow. **You edit a block, you look at the bar, you edit again.** No find-replace pass. No walking through 60 KB of CSS.

**Live-reload:** YASB watches its stylesheet. Save the file and the bar updates immediately.

**Building a palette from scratch:**

If none of the cataloged palettes is close enough, copy the block for the closest one and start changing values. Keep in mind the relationships between the slots:

- `--accentText` should be a very dark version of `--background`. It's the text that sits *on* the accent color, so it needs to be near-black (for dark themes) or near-white (for light themes).
- `--background2` should be slightly lighter than `--background` (for dark themes) — one step up in luminance.
- `--hover` should be between `--background2` and `--accent` in luminance — it's the "not-yet-selected-but-interesting" state.
- `--mutedBG` should be slightly *darker* than `--background` (for dark themes) — one step down.
- `--border` should be a low-contrast color — visible but not loud.
- `--text` should be high-contrast against `--background`. Aim for WCAG AA at minimum (4.5:1).
- `--subtext` should be roughly 60–70% of the way from `--text` to `--background`. Readable but clearly secondary.
- `--redFlash` should stand out — it's the alert state. Warm and bright works.

**Testing the relationships:** change one value, save, look. The rules above are a starting point, not a formula. If a value looks wrong in context, adjust it.

**Common mistakes:**

- **More than one palette active.** If you uncomment a block without commenting out the previous one, both sets of values apply, and the last-defined wins. The bar renders with a Frankenstein palette. Keep exactly one active.
- **Renaming variables.** The widget rules below `:root` reference the variables by name (`var(--accent)`, `var(--text)`, etc.). If you rename `--accent` to `--primary`, every rule that uses `var(--accent)` breaks. **Change values, not names.**
- **Editing hex below `:root`.** There are a handful of literal hex values further down — media source colors (`#1db954` for Spotify, `#fa2b56` for Apple Music), the search loader line — that aren't part of the palette. If you find yourself editing a hex below `:root` while trying to change a widget's color, stop. The value you want is in the block.
- **Forgetting `--accentText`.** This is the most missed variable. If you change `--accent` but leave `--accentText` at its default, the active workspace label and other on-accent text becomes unreadable. Set `--accentText` to a near-black (or near-white, for light themes) color every time.

---

### `starship/starship.toml` — the prompt

**What it controls:** the shell prompt. Colors, segments, symbols.

**The structure:** a `starship.toml` has three parts that matter here.

**Part 1 — the format string.** Near the top:

```toml
format = """
[](red)\
$os\
$username\
[](bg:peach fg:red)\
$directory\
[](bg:yellow fg:peach)\
$git_branch\
$git_status\
...
"""
```

This defines the shape of the prompt. Each segment is `$name`, each powerline glyph is `[](bg:... fg:...)`. The color names in the parens refer to the active palette.

**Part 2 — the active palette selector.** Just below the format:

```toml
palette = 'catppuccin_mocha'
```

**Part 3 — the palette blocks.** At the bottom:

```toml
[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
red = "#f38ba8"
yellow = "#f9e2af"
green = "#a6e3a1"
sapphire = "#74c7ec"
...
```

**What to edit for a new theme:**

1. Change `palette = 'catppuccin_mocha'` to `palette = 'your-theme-name'`
2. Add a `[palettes.your-theme-name]` block with your colors
3. Fill in the slots that the format string references

**The slots you must define:**

The format string references these seven. If any is missing, Starship errors on load:

| Slot | Role |
|---|---|
| `red` | OS icon background, error character |
| `peach` | Directory background |
| `yellow` | Git branch background |
| `green` | Runtime version backgrounds, success character |
| `sapphire` | Conda, docker, misc segment backgrounds |
| `lavender` | Time, cmd_duration backgrounds |
| `crust` | Foreground color on colored segments |

**The slots you should define** (for consistency if you extend the format later): `blue`, `teal`, `sky`, `mauve`, `pink`, `maroon`, `text`, `subtext1`, `subtext0`, `overlay2`, `overlay1`, `overlay0`, `surface2`, `surface1`, `surface0`, `base`, `mantle`. Copy the whole base palette block and change the values.

**The three-swatch convention:**

The TUI's theme picker shows three color swatches per theme. Those come from this file: it reads the `red`, `yellow`, and `sapphire` slots from the active palette block. If `sapphire` isn't defined, it falls back to `blue`. If neither is defined, no swatches show.

So if you want your theme to have swatches in the picker, define at minimum those three slots.

**Testing:** save the file, and the next prompt in any open shell renders with the new colors. No restart needed. If the prompt doesn't recolor when you save, you have a syntax error — run `starship config` in a shell to see it.

**Common mistakes:**

- **TOML is strict.** A missing quote or a stray comma breaks the whole file. Starship will tell you: run `starship config` and it names the exact line.
- **Slot names must match exactly.** `sapphire` is not `Sapphire` is not `sapphire_blue`. TOML keys are case-sensitive.
- **The palette block header must match the `palette = ` value.** `palette = 'my-theme'` needs `[palettes.my-theme]`, not `[palettes.my_theme]`. Hyphens and underscores are not interchangeable.

---

### `terminal/settings.json` — Windows Terminal

**What it controls:** the terminal's color scheme. Which colors it uses for background, foreground, cursor, ANSI palette.

**The structure:** Windows Terminal schemes are defined under a `schemes` array. Each entry looks like:

```json
{
  "name": "Kanagawa Wave",
  "background": "#1F1F28",
  "foreground": "#DCD7BA",
  "cursorColor": "#C8C093",
  "selectionBackground": "#2D4F67",
  "black": "#16161D",
  "red": "#C34043",
  "green": "#76946A",
  "yellow": "#C0A36E",
  "blue": "#7E9CD8",
  "purple": "#957FB8",
  "cyan": "#6A9589",
  "white": "#C8C093",
  "brightBlack": "#727169",
  "brightRed": "#E82424",
  "brightGreen": "#98BB6C",
  "brightYellow": "#E6C384",
  "brightBlue": "#7FB4CA",
  "brightPurple": "#938AA9",
  "brightCyan": "#7AA89F",
  "brightWhite": "#DCD7BA"
}
```

**How the deploy works:**

The installer **merges** your theme's `terminal/settings.json` into the user's existing Windows Terminal `settings.json`. It doesn't overwrite anything. Schemes merge by **name** — a scheme with the same name replaces the existing one, new schemes are added, unrelated schemes are preserved.

**What to edit for a new theme:**

Two options:

**Option A — reuse the source theme's scheme.** If you're forking kanagawa into kanagawa-dark, and the terminal colors are close enough, leave the file alone. The scheme name stays the same.

**Option B — add a new scheme.** Replace the `schemes` array with your own, or add yours alongside the existing one. Then set `profiles.defaults.colorScheme` to match.

The simplest version of option B is to take the scheme you're forking, change the hex values, and **rename the scheme**. If you keep the same name, both themes share the same scheme slot — whichever deploys last wins. Renaming makes them coexist.

**Testing:** restart Windows Terminal (the whole app, not just the tab). Scheme changes don't live-reload.

**Common mistakes:**

- **Forgetting to update `colorScheme`.** The scheme exists but the terminal doesn't use it.
- **Missing a required field.** Windows Terminal schemes need all the fields above. Missing one causes a silent fallback.
- **Renaming without updating `profiles.defaults`.** Same as the first mistake, from the other direction.

---

### `chronoterm/config.toml` — the clock

**What it controls:** the ChronoTerm clock's accent color and a few display options.

**The structure:** small TOML file. The color-relevant part is one or two hex values.

**What to edit:**

Open it, find the hex value(s), replace with an accent color from your palette. Almost always one value.

**Picking the color:** ChronoTerm is a foreground element — text you'll read often. Pick an accent from your palette that's readable against your terminal background. The theme's `green` or `sapphire` slot usually works well; the theme's `red` usually doesn't, because it reads as an error state.

**Testing:** run `chronoterm` in a shell. The clock renders with the new color immediately.

**Common mistakes:**

- **Too bright.** The clock is a persistent element. A color that looks good as a "pop" accent will be exhausting as a permanent fixture.
- **Wrong contrast.** Same as everywhere else. Verify the clock is readable against the terminal background.

---

### `cava/config` — the visualizer

**What it controls:** the audio visualizer's gradient colors.

**The structure:** a Cava config file. The relevant part is a `[color]` section:

```
[color]
gradient = 1
gradient_color_1 = '#7E9CD8'
gradient_color_2 = '#7FB4CA'
gradient_color_3 = '#957FB8'
gradient_color_4 = '#C34043'
gradient_color_5 = '#DCA561'
gradient_color_6 = '#76946A'
gradient_color_7 = '#6A9589'
gradient_color_8 = '#E6C384'
```

The visualizer transitions from `gradient_color_1` (bottom of the bars) to `gradient_color_8` (top).

**What to edit:**

Replace the eight hex values with an ascending sequence from your palette. Best effect comes from a cool/dark at the bottom to warm/bright at the top — the visual rise mirrors the audio rise.

**How to pick eight colors:** you don't need eight unique palette colors. Two approaches:

1. **Palette extraction:** pull 8 distinct accent colors from your palette (red, orange, yellow, green, aqua, blue, purple, pink).
2. **Gradient interpolation:** pick 2 or 3 anchor colors and interpolate between them.

**Testing:** the Cava widget in the YASB bar updates when audio plays. You'll need sound playing to see it.

**Common mistakes:**

- **All eight the same color.** The gradient collapses into a flat bar and it looks broken.
- **Light at the bottom.** The bar background is dark, so light-at-bottom makes the bars disappear.
- **Colors that don't relate.** Eight random colors read as noise.

---

### `fastfetch/ascii.txt` — the logo

**What it controls:** the ASCII art Fastfetch prints at shell startup.

**The structure:** a plain text file. Whatever characters are in it get printed on the left side of Fastfetch's output.

**What to edit:** replace the entire file with your own art, or delete the file from your theme folder to fall through to the base logo.

**Sizing rules:**

- **Height:** 12–20 lines works well. Under 12 and the info column dwarfs it. Over 20 and the info ends up in the middle of the art.
- **Width:** 30–45 characters. Fastfetch's default layout puts the info block at column ~48.
- **Character set:** stick to ASCII (space through `~`) or well-supported Unicode block characters (`█`, `▓`, `░`, `─`, `│`). Avoid emoji.

**Where to find art:**

- [asciiart.eu](https://www.asciiart.eu/) — searchable, lots of styles
- [textart.io](https://textart.io/art) — large collection

**Preparing art for Fastfetch:**

1. Paste into a plain text editor (Notepad, VS Code)
2. Remove any leading/trailing blank lines
3. Replace tabs with spaces
4. Save as UTF-8 without BOM

**Testing:**

```powershell
fastfetch -c "$HOME\.config\fastfetch\config.jsonc"
```

**Common mistakes:**

- **Tab characters.** Different terminals render them at different widths, so the art looks sheared.
- **Too wide.** If the art runs over column 48, it collides with the info block.

---

### `wallpapers/` — the wallpaper set

**What it controls:** which wallpapers get deployed to `~/Pictures/Windows-Rice/<theme>/` and shown in YASB's gallery (`Alt+W`).

**The `default.*` convention:**

One file in this folder must be named `default.<ext>` where `<ext>` is `jpg`, `jpeg`, `png`, or `webp`. This is the file that gets set as your desktop wallpaper when the theme is applied.

If no `default.*` exists, the installer warns and leaves your current wallpaper untouched.

**File naming:**

Any name works for gallery wallpapers. Conventions:

- Lowercase
- Hyphens instead of spaces
- No special characters (no `(`, `)`, `'`)

**Format and size:**

The `compress-all-themes.ps1` script normalizes everything before commit:

- Max width: 1920px
- JPEG quality: 82
- Large PNGs (>500 KB) converted to JPEG
- Metadata stripped

Run it before you commit:

```powershell
.\compress-all-themes.ps1
```

A theme with 20 raw 4K wallpapers typically lands at 3–6 MB after compression.

**How many wallpapers?**

- **1 (minimum):** just `default.jpg`. Ayu-dark does this. Perfectly valid.
- **5–20 (sweet spot):** enough to browse, not so many that the folder bloats.
- **20–40 (rich):** most of the shipped themes.

**Testing:** apply the theme, then `Alt+W` in the bar opens the gallery.

**Common mistakes:**

- **No `default.*`.** Most common. Verify with:
  ```powershell
  Get-ChildItem themes\<name>\wallpapers -File | Where-Object { $_.Name -like 'default.*' }
  ```
  Should print exactly one file.
- **Uncompressed wallpapers.** 4K PNGs at 15 MB each will make the repo grow fast.
- **Filenames that break URLs.** Wallpapers with `#` or `?` in the name look fine on disk but break when YASB tries to display them.

---

### `glazewm/default_glazewm_config.yaml` — rarely needed

**What it controls:** the tiling window manager. Window rules, workspace names, gaps, keybindings.

**Why it's rarely needed:** GlazeWM's config is about *structure*, not *appearance*. Your theme's colors don't go here — they go in the YASB stylesheet.

**When you'd edit it:**

- Different workspace names
- Different gaps or padding
- Different keybindings
- Different window rules

**When you wouldn't:**

- Changing colors (that's not what this file does)
- Adding/removing widgets (that's YASB's config)

If you don't have a strong reason, **don't include this file in your theme.**

**Testing:** GlazeWM reloads its config with `Alt+Shift+R`, or the installer tells it to reload on deploy.

---

## Worked example: making gruvbox-dark

Let's walk through an actual theme from start to finish. Target: a darker version of the gruvbox theme.

**1. Scaffold the folder.**

```powershell
Copy-Item themes\gruvbox themes\gruvbox-dark -Recurse
```

Or via the TUI: `win-rice` → Create a new theme → gruvbox → name it `gruvbox-dark` → decline wallpapers for now.

**2. Pick the target palette.**

Gruvbox has a "hard contrast" variant with darker blacks. Standard gruvbox:

- Background: `#282828`
- Foreground: `#ebdbb2`
- Accent: `#d79921`

Gruvbox hard contrast:

- Background: `#1d2021`
- Foreground: `#ebdbb2` (unchanged)
- Accent: `#b57614`

Everything shifts one step darker. The foreground stays put because it's already at a comfortable contrast.

**3. Open `yasb/styles.css`. Find the `:root` block.**

The file starts with `@import "yasb_colors.css";` and then `:root {`. Inside `:root`, there's a catalog of commented-out palettes.

**4. Find the gruvbox block.**

The catalog includes a `Gruvbox Material Dark Soft` block. If it's the active palette, skip to step 5. If a different palette is active, comment it out and uncomment gruvbox:

```css
/* Gruvbox Material Dark Soft */
--background: #32302F;
--background2: #45403D;
--accent: #DDC7A1;
--text: #DDC7A1;
--accentText: #32302F;
--hover: #5A524C;
--mutedBG: #252423;
--border: #3C3836;
--redFlash: #ea6962;
--subtext: #928374;
```

Save. The bar should now use gruvbox colors.

**5. Change the ten values for the hard-contrast variant.**

The gruvbox material block uses the material palette's cream-white as its accent. Standard gruvbox uses a warm yellow. The transition isn't purely a luminance shift — it's a shift toward the classic gruvbox palette, which happens to be darker in the backgrounds and warmer in the accents. Both moves are deliberate.

Edit each value in the block:

```css
--background: #32302F  →  #1d2021
--background2: #45403D  →  #3c3836
--accent: #DDC7A1  →  #d79921
--text: #DDC7A1  →  #ebdbb2
--accentText: #32302F  →  #1d2021
--hover: #5A524C  →  #504945
--mutedBG: #252423  →  #141617
--border: #3C3836  →  #504945
--redFlash: #ea6962  →  #cc241d
--subtext: #928374  →  #a89984
```

Save. Look at the bar. The background darkened, the accents deepened toward yellow rather than cream, the `--accentText` shifted to the near-black from the new background.

**The rule of thumb:** if you can't read a widget at a glance — the workspace number, the clock, the battery percentage — the color needs more contrast. That's the whole check.

**6. Update `starship/starship.toml`.**

Change the palette selector at the top:

```toml
palette = 'gruvbox-dark'
```

Add a palette block at the bottom:

```toml
[palettes.gruvbox-dark]
red = "#cc241d"
peach = "#d65d0e"
yellow = "#d79921"
green = "#98971a"
sapphire = "#458588"
lavender = "#b16286"
crust = "#1d2021"
blue = "#458588"
```

Save. Open a new shell — the prompt uses the new colors. If not, run `starship config` to see the error.

**7. Update `terminal/settings.json`.**

Change the scheme name from `"Gruvbox Dark"` to `"Gruvbox Dark Hard"`. Change the hex values to match your new palette. Save.

Restart Windows Terminal. The terminal uses the new scheme.

**8. Update `chronoterm/config.toml`.**

Replace the color hex with `#98971a` (the theme's green, readable and muted).

Test with `chronoterm` in a shell.

**9. Update `cava/config`.**

Replace the eight gradient colors with an ascending sequence from your darker gruvbox palette:

```
gradient_color_1 = '#1d2021'
gradient_color_2 = '#427b58'
gradient_color_3 = '#79740e'
gradient_color_4 = '#b57614'
gradient_color_5 = '#d65d0e'
gradient_color_6 = '#cc241d'
gradient_color_7 = '#d79921'
gradient_color_8 = '#ebdbb2'
```

Dark at the bottom, bright at the top. Play some audio and watch the bars.

**10. Wallpapers.**

If you declined the copy in step 1, drop your own files into `themes/gruvbox-dark/wallpapers/`. Ensure at least one is `default.jpg` (or `.png`/`.webp`).

If you accepted the copy, you have gruvbox's 78 wallpapers. Decide whether to keep them or replace them. If you keep them, run `compress-all-themes.ps1` before committing.

**11. Apply and inspect.**

```powershell
win-rice
# 1 → gruvbox-dark
```

Walk through the whole rice: bar, prompt, terminal, clock, wallpaper, gallery. Fix anything that looks wrong. This step usually takes 2–3 more iterations.

**12. Commit.**

```powershell
.\compress-all-themes.ps1
git add themes/gruvbox-dark/
git commit -m "Add gruvbox-dark theme"
git push
```

Done. The theme is yours.

**Total time:** ~45 minutes if you have a clear target palette.

---

## Testing your theme

**The fast loop:**

```powershell
win-rice
# 1 → pick your theme
```

~5 seconds per iteration for non-CSS files. For CSS-only changes, the loop is even faster — YASB live-reloads, so saving `yasb/styles.css` updates the bar immediately without any TUI interaction.

**What to check:**

| Element | How | What to look for |
|---|---|---|
| Bar background | Look at the bar | Should match your `--background` |
| Bar foreground | Read the clock, battery %, volume % | Should be readable against the background |
| Workspace labels | Hover and click between them | Active and inactive states both visible |
| Media widget | Play a track | Title and controls readable |
| Audio visualizer | Play audio | Gradient visible from bottom to top |
| Volume popup | Click the volume widget | Popup background and text readable |
| Calendar | Click the clock | Calendar background and grid lines visible |
| Quick actions | Open the control center | Active/inactive quick actions distinguish |
| Prompt | Open a fresh shell | Every segment colored correctly |
| Prompt symbols | Navigate to a git repo | Git branch and status symbols visible |
| Terminal background | Look at a terminal | Matches the theme's background |
| Terminal ANSI colors | Run `ls` in a colorful directory | File types distinguished |
| Clock | Run `chronoterm` | Accent color matches |
| Wallpaper | Look at your desktop | The theme's `default.*` is applied |

**Common visual bugs:**

- **Low contrast** — a color that's too close to the background. Most common theme bug.
- **Vibrating accents** — two adjacent segments with similar luminance.
- **Ghost widgets** — a widget is technically rendering but invisible because its color matches the background.
- **Wrong `--accentText`** — active workspace label unreadable because the on-accent text didn't get updated.

---

## Sharing your theme

Themes are just folders. There's no submission process, no approval queue, no upstream. It's your theme and it lives in your copy of the repo.

**If you want to share it anyway, three options:**

**1. Post about it.**

Take a screenshot of the bar and the desktop. Post on r/unixporn, r/desktopthemes, or wherever. Include the palette name and a link to your repo if you want people to try it.

The format that works well: one screenshot, the palette name in the title, the source (e.g. "gruvbox palette, custom dark variant") in a comment.

**2. Push it to your fork.**

If you forked the repo to your own GitHub account, your theme is already online at `github.com/yourname/Windows-Rice`. Anyone can clone your fork to get it.

```powershell
git remote -v
# If you see your own username, you're pushing to your fork already
```

**3. Share the folder directly.**

The theme folder is self-contained. You can zip `themes/my-theme/` and send it to someone. They unzip it into their own `themes/` folder and it just works.

```powershell
Compress-Archive -Path themes\my-theme -DestinationPath my-theme.zip
```

The 5–10 MB zip is easy to send over Discord, email, or dropbox.

**What about contributing to the main repo?**

You can open a PR, but the repo is a personal rice with a curated theme set. There's no expectation that outside themes get merged. If you have a theme you think belongs in the shipped set, open a PR and mention it — but don't be surprised if the answer is "no, but it's great, keep it in your fork."

The default assumption is: **your theme is yours, the repo is a template, do whatever you want.**

---

## Reference

### YASB color slots

Every palette block in `yasb/styles.css` defines these ten variables. Same names across every theme — only the values change.

| Variable | Role | Typical relationship |
|---|---|---|
| `--background` | Bar background, popup backgrounds | Base color |
| `--background2` | Secondary background — buttons, separators | One step lighter than `--background` |
| `--accent` | Active/selected state | High contrast against `--background` |
| `--text` | Primary text | Very high contrast against `--background` |
| `--accentText` | Text on top of `--accent` | Very dark (near-black), or very light for light themes |
| `--hover` | Hover state background | Between `--background2` and `--accent` |
| `--mutedBG` | Deep backgrounds, checkbox indicators | One step darker than `--background` |
| `--border` | Borders on popups and separators | Low contrast against `--background` |
| `--redFlash` | Alert / danger state | Warm and bright |
| `--subtext` | Secondary text — status labels, descriptions | 60–70% of `--text` toward `--background` |

Do not rename these. The widget rules below `:root` reference them by name.

### Starship palette slots

The base palette defines these slots. The format string references the ones marked ✓ and they must exist.

| Slot | Required | Role |
|---|---|---|
| `red` | ✓ | OS icon background, error character |
| `peach` | ✓ | Directory background |
| `yellow` | ✓ | Git branch background |
| `green` | ✓ | Runtime version backgrounds, success character |
| `sapphire` | ✓ | Conda, docker, misc segment backgrounds |
| `lavender` | ✓ | Time, cmd_duration backgrounds |
| `crust` | ✓ | Foreground color on colored segments |
| `rosewater` | | Optional |
| `flamingo` | | Optional |
| `pink` | | Optional |
| `mauve` | | Optional |
| `maroon` | | Optional |
| `teal` | | Optional |
| `sky` | | Optional |
| `blue` | | Optional |
| `text` | | Optional |
| `subtext1` | | Optional |
| `subtext0` | | Optional |
| `overlay2` | | Optional |
| `overlay1` | | Optional |
| `overlay0` | | Optional |
| `surface2` | | Optional |
| `surface1` | | Optional |
| `surface0` | | Optional |
| `base` | | Optional |
| `mantle` | | Optional |

### Wallpaper format guidance

| Concern | Recommendation |
|---|---|
| Format | JPEG for photos, WebP for screenshots, PNG only for line art with transparency |
| Max width | 1920 px |
| Quality | 82 for JPEG, 82 (lossy) for WebP |
| Metadata | Strip everything |
| File size target | Under 500 KB per wallpaper, ideally under 300 KB |
| Total theme size | 3–8 MB for a 20-wallpaper theme |

### Useful tools

| Tool | What it does |
|---|---|
| `starship config` | Validates the active `starship.toml` and shows errors with line numbers |
| `yasbc logs` | Streams YASB's log output live (requires YASB running) |
| `yasbc reload` | Tells the running YASB instance to re-read its config |
| `fastfetch -c <config>` | Renders a config file without deploying |
| `magick identify <file>` | Checks a wallpaper's dimensions, format, quality |
| `.\compress-all-themes.ps1` | Compresses every wallpaper in every theme |
| `.\scaffold-theme.ps1 -Names <n>` | Creates a new theme folder |

### Color resources

If you're building a palette from scratch:

- [Coolors](https://coolors.co/) — palette generator with hex export
- [Color Hunt](https://colorhunt.co/) — curated palettes, filterable by mood
- [Lospec](https://lospec.com/palette-list) — retro and pixel-art palettes, good for high-contrast themes

If you're adapting an existing palette, most have official specs:

- [Catppuccin](https://github.com/catppuccin/catppuccin) — the base palette
- [Rose Pine](https://rosepinetheme.com/palette) — the rose-pine palette
- [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) — the tokyo-night palette
- [Kanagawa](https://github.com/rebelot/kanagawa.nvim) — the kanagawa palette
- [Gruvbox](https://github.com/morhetz/gruvbox) — the gruvbox palette
- [Nord](https://www.nordtheme.com/docs/colors-and-palettes) — the nord palette

---

## Getting unstuck

**"I don't see my theme in the picker."**

```powershell
Test-Path themes\<name>
```

Should print True. If False, the folder isn't where the TUI looks. Confirm you created it under the repo root's `themes/` folder.

**"The theme applies but nothing looks different."**

You forked a theme and didn't edit anything yet. The new theme is a byte-for-byte copy of the source. Open `yasb/styles.css`, find the active palette block in `:root`, and change some values.

**"The bar shows the wrong colors."**

The colors live in the `:root` block at the top of `yasb/styles.css`. If the bar looks wrong, the values in that block are wrong.

The most common cause is more than one palette block being active. Open the file, check that exactly one block is uncommented, and confirm the values in it match your intent. If two blocks are active, the second one wins, and the bar's colors will look like a mix.

**"Active workspace label is unreadable."**

You changed `--accent` but not `--accentText`. The active workspace uses `--accent` as its background and `--accentText` for the label. If `--accentText` is close to `--accent` in brightness, the label disappears.

Set `--accentText` to a very dark color (for dark themes) — near the same darkness as `--background`. This gives the label maximum contrast against the accent background.

**"Starship errors on load."**

```powershell
starship config
```

Prints the exact error with a line number. Most common causes:

- A missing quote in a hex value
- A slot name that doesn't exist in your palette block
- The palette block header doesn't match the `palette = ` value

**"The wallpaper didn't change."**

Check `default.*` exists in your theme's `wallpapers/` folder:

```powershell
Get-ChildItem themes\<name>\wallpapers -File | Where-Object { $_.Name -like 'default.*' }
```

If it returns nothing, the installer warns and leaves your desktop alone. Rename one of your wallpapers to `default.jpg` (or `.png`/`.webp`) and redeploy.

**"The wallpaper gallery shows old wallpapers."**

The theme's deployed wallpaper folder is synced on every deploy. Files that aren't in the source get removed. If old wallpapers persist, the sync didn't run. Re-run the installer:

```powershell
win-rice
# 1 → your theme
```

If old wallpapers still persist, check whether they're in `themes/<name>/wallpapers/` — if they are, they're legitimately part of your source set. Remove them from the source folder and redeploy.

**"My theme got huge in git."**

```powershell
.\compress-all-themes.ps1
```

Run before committing. If you've already committed and pushed, the uncompressed wallpapers are in the git history. Fixing that requires a history rewrite.

For new themes, the lesson is: always compress before commit.

**"I want to add a wallpaper but don't have a `default.jpg`."**

Copy any wallpaper to `default.jpg`:

```powershell
Copy-Item themes\<name>\wallpapers\some-wallpaper.jpg themes\<name>\wallpapers\default.jpg
```

Or generate a solid-color one:

```powershell
magick -size 1920x1080 xc:'#1d2021' themes\<name>\wallpapers\default.jpg
```

Replace `#1d2021` with your theme's `--background`. A solid-color wallpaper is a perfectly reasonable default if you don't have a real one yet.

**"Can I delete a shipped theme I don't use?"**

Yes. Delete the folder:

```powershell
Remove-Item themes\<name> -Recurse -Force
```

The next time the TUI draws, the theme is gone from the picker. If it was your active theme, pick a different one first.

**"Can I rename a theme after creating it?"**

Rename the folder:

```powershell
Rename-Item themes\old-name themes\new-name
```

But also update the `palette = '...'` line and the `[palettes....]` block header in `starship/starship.toml` to match. Easiest fix is to leave the palette name as-is and only change the folder name — your call.

**"Can I have more than 10 themes?"**

Yes. The TUI reads `themes/` on every draw. Add as many folders as you want. The picker list scrolls.

The only cost is repo size. Compress religiously and consider pruning themes you don't use.

**"Something else is broken."**

Run the TUI's Status screen:

```powershell
win-rice
# 3 → Status
```

It reports which configs are deployed, whether the launcher is present, and the current theme.

For deeper diagnostics:

- **YASB:** `yasbc logs` or `~/.config/yasb/yasb.log`
- **Starship:** `starship config` or `starship timings`
- **GlazeWM:** check its console output or `~/.glzr/glazewm/`

If the issue is with the theme itself and you can't figure out which file, temporarily delete files from the theme folder one at a time — each deletion makes that file fall through to the base. When the problem goes away, you've found the culprit.
