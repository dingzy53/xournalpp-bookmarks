# Xournal++ Bookmarks (Zenity Version)

[![Release](https://img.shields.io/github/v/release/dingzy53/xournalpp-bookmarks)](https://github.com/dingzy53/xournalpp-bookmarks/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/dingzy53/xournalpp-bookmarks/total)](https://github.com/dingzy53/xournalpp-bookmarks/releases)
[![Xournal++ 1.3+](https://img.shields.io/badge/Xournal%2B%2B-1.3%2B-1e88e5)](https://xournalpp.github.io)
[![License: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-blue)](LICENSE)

Add nested bookmarks to Xournal++ documents, and export the PDF with a matching outline.

This is a fork of [Bookmarks plugin by Jereyes](https://github.com/jereyes4/xournalpp-bookmarks). It replaces the `lgi` dependency with **Zenity** dialogs, so one codebase works on Linux (native packages and Flatpak), macOS and Windows. See [License](#license).

<!-- Screenshot: docs/images/hero.png -->

## Features

- **Add bookmarks** with a name dialog (`## ` prefix creates sub-bookmarks), or silently with *Quick Add*
- **Nested bookmarks** (chapters > sections > subsections, up to 9 levels)
- **Navigate** between bookmarks (*Previous* / *Next*)
- **Bookmark manager** with an indented outline: jump to, rename, move to another page, promote/demote (with sub-bookmarks), delete (only the bookmark, or with its sub-bookmarks)
- **Import** the background PDF's table of contents as bookmarks (requires pdftk)
- **Export to PDF** with an embedded, nested outline (requires pdftk). Titles are written as UTF-8, so any language, emoji and characters like `&` work. If the background PDF already has an outline, you can replace it or keep it.

## Requirements

No Lua modules required.

- Xournal++ 1.3+ (tested with 1.3.7 / 1.3.8)
- [Zenity](https://gitlab.gnome.org/GNOME/zenity), or its cross-platform port [ncruces/zenity](https://github.com/ncruces/zenity), for the dialogs
- [pdftk](https://gitlab.com/pdftk-java/pdftk) (only for *Import PDF Outline* and *Export PDF*)

The plugin looks for these tools on your `PATH` and in the usual install locations (Homebrew, MacPorts, `~/.local/bin`, scoop). If a tool is missing, the plugin shows how to install it.

### Linux

| Distribution | Command |
|---|---|
| Arch Linux | `sudo pacman -S --needed zenity pdftk` |
| Fedora | `sudo dnf install zenity pdftk-java` |
| Ubuntu / Debian | `sudo apt install zenity pdftk-java` |

### Linux, Flatpak (Xournal++ from Flathub)

The Flatpak runtime already contains zenity, so dialogs work out of the box. The PDF export needs pdftk, which has to be installed **on your system** (see the table above). Xournal++ also needs permission to start it outside the sandbox:

```bash
flatpak override --user --talk-name=org.freedesktop.Flatpak com.github.xournalpp.xournalpp
```

Restart Xournal++ afterwards. Be aware that this permission lets Xournal++ (and its plugins) run any program on your system, so it effectively disables the sandbox. Skip it if you don't need the export. To undo it later, run `flatpak override --user --reset com.github.xournalpp.xournalpp`.

### macOS

```bash
brew install zenity pdftk-java
```

`brew install ncruces/tap/zenity` is a lighter alternative to GNOME zenity, with native macOS dialogs.

**Without Xcode (macOS 14 Sonoma, older macOS, or Intel Macs):** Homebrew's `openjdk` formula only has bottles for Apple Silicon on macOS 15+. On older versions or Intel Macs, `brew install pdftk-java` tries to build OpenJDK from source, which needs full Xcode (Command Line Tools alone are not enough). Instead, install zenity and [Eclipse Temurin](https://adoptium.net/), then wrap `pdftk-all.jar` from [pdftk-java releases](https://gitlab.com/pdftk-java/pdftk/-/releases) in `~/.local/bin/pdftk`:

```bash
brew install zenity
brew install --cask temurin
mkdir -p ~/.local/share/pdftk ~/.local/bin
curl -fL -o ~/.local/share/pdftk/pdftk-all.jar \
  https://gitlab.com/api/v4/projects/5024297/packages/generic/pdftk-java/v3.3.3/pdftk-all.jar
cat <<'EOF' > ~/.local/bin/pdftk
#!/bin/sh
exec java -jar "$HOME/.local/share/pdftk/pdftk-all.jar" "$@"
EOF
chmod +x ~/.local/bin/pdftk
~/.local/bin/pdftk --version
```

### Windows 11

```powershell
scoop install https://ncruces.github.io/scoop/zenity.json pdftk
```

## Installation

1. Install the [requirements](#requirements) for your system.
2. Download `Bookmarks.zip` from the [latest release](https://github.com/dingzy53/xournalpp-bookmarks/releases/latest) and unzip it. You get a folder named `Bookmarks`.
3. Move that folder into the Xournal++ plugins folder, so that you have `plugins/Bookmarks/plugin.ini`. Create the `plugins` folder if it doesn't exist.

   | System | Plugins folder |
   |---|---|
   | Linux, macOS | `~/.config/xournalpp/plugins/` |
   | Linux, Flatpak | `~/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/` |
   | Windows | `%LOCALAPPDATA%\xournalpp\plugins\` |

4. Restart Xournal++. The plugin is enabled by default. If its entries are missing from the **Plugin** menu, enable **Bookmarks** in **Plugin → Plugin Manager** and restart again.

**Update or remove:** replace the `Bookmarks` folder with the new one, or delete it.

## Usage

Everything is in the **Plugin** menu:

- **Bookmarks: New…** — add a bookmark on the current page (pre-filled with the previous bookmark's level prefix)
- **Bookmarks: Quick Add** — add an untitled sibling bookmark without opening a dialog
- **Bookmarks: Manage…** — open the Bookmark Manager (*Jump To*, *Rename…*, *Move to Page…*, *Promote*, *Demote*, *Delete*)
- **Bookmarks: Previous** / **Bookmarks: Next** — jump to the previous or next bookmarked page
- **Bookmarks: Import PDF Outline** — import the background PDF's table of contents
- **Bookmarks: Export PDF…** — export the document as a PDF with an embedded outline

### Levels

Type the level in front of the name, as in Markdown headings:

| You type | Result |
|---|---|
| `Introduction` | level 1 |
| `## Background` | level 2 |
| `### Prior work` | level 3 |
| `# ## Not a heading` | level 1, titled `## Not a heading` |

*Bookmarks: New…* is pre-filled with the previous bookmark's prefix, so typing a name and pressing Enter creates a sibling bookmark. Add another `#` to create a sub-bookmark.

A bookmark can be at most one level deeper than the bookmark before it. If a level skips (for example after a delete), the manager shows `⚠` and the export uses the nearest valid level.

### Toolbar buttons

All actions can be added to a toolbar (**View → Toolbars → Customize**) as `Plugin::CUSTOM_NEW_BOOKMARK`, `CUSTOM_NEW_BOOKMARK_NO_DIALOG`, `CUSTOM_VIEW_BOOKMARKS`, `CUSTOM_PREVIOUS_BOOKMARK`, `CUSTOM_NEXT_BOOKMARK`, `CUSTOM_IMPORT_PDF_OUTLINE` and `CUSTOM_EXPORT_WITH_BOOKMARKS`.

## How bookmarks are stored

Each bookmark is a hidden layer on its page, named `Bookmark::<title>`, or `Bookmark::## <title>` for level 2, and so on. Bookmarks are saved inside the `.xopp` file and move with their page. You can see and rename them in the Layer sidebar. The outline order is page order, then layer order within a page, and new bookmarks are added on top. To reorder bookmarks on one page, move their layers.

Older versions of this plugin (and the original upstream plugin) still see nested bookmarks. They show them flat, with the `##` prefix as part of the title.

## Privacy and security

- **Running programs:** `zenity` for dialogs and `pdftk` for PDF import and export (on Windows, started through `cmd.exe`). Bookmark names are quoted before they reach these programs.
- **Temporary files:** written to the system temp folder (under Flatpak, the app's cache folder, so that the host's pdftk can reach them) and deleted afterwards.
- **Your files:** bookmarks are stored in the `.xopp` file. An exported PDF is written only where you choose.
- **Network:** none.

## Limitations

- Xournal++ may briefly show "Not Responding" while a Zenity dialog is open. The plugin API only offers blocking calls to external programs.
- On Windows, a console window may flash briefly when a dialog opens.
- On Windows, double quotes in bookmark names are shown as `''` in dialogs, because `cmd.exe` cannot pass them safely. The stored name stays unchanged unless you edit it.
- Each layer change (for example promoting a bookmark with 3 sub-bookmarks) is a separate undo step.
- Duplicating a page also duplicates its bookmarks.

## Development

The plugin is split into small modules:

| Module | Role |
|---|---|
| `main.lua` | Menu and toolbar callbacks |
| `bm_platform.lua` | OS, Flatpak and tool detection, safe command execution |
| `bm_ui.lua` | Zenity dialogs |
| `bm_doc.lua` | Layer operations and Xournal++ 1.3+ API adapter |
| `bm_model.lua` | Bookmark names, levels and the outline tree |
| `bm_pdf.lua` | pdftk outline handling |

Run the tests from the repository root:

```bash
lua tests/run.lua      # offline unit + pdftk integration tests (Lua 5.3+)
scripts/selftest.sh    # in-app self test inside real Xournal++
```

### Releasing

1. Set `version=` in `Bookmarks/plugin.ini` and commit.
2. Tag that commit with the same version, without a `v`, and push both: `git tag 0.3.0 && git push origin main 0.3.0`.

The Release workflow runs the tests and publishes `Bookmarks.zip`.

## License

GNU General Public License v2 (GPLv2) — see [LICENSE](LICENSE).

- Copyright (C) 2024–2025 Javier Reyes and contributors: the original [xournalpp-bookmarks](https://github.com/jereyes4/xournalpp-bookmarks).
- Copyright (C) 2026 Ding Zheng Yuan: the zenity port and later changes.

This is a modified version of the original plugin. The main changes: the `lgi`/Glade UI was replaced by zenity dialogs, the code was split into modules (`bm_*.lua`), and nested bookmarks, import, navigation and cross-platform support were added. The git history records every change.
