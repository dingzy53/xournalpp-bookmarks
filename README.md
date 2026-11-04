# Xournal++ Bookmarks (Zenity Version)

This is a fork of [Bookmarks plugin by Jereyes](https://github.com/jereyes4/xournalpp-bookmarks).

This fork entirely removes the `lgi` dependency and replaces all user interface elements with **Zenity**.

**Cross-platform**: one codebase for Linux (native packages and Flatpak), macOS and Windows.

## Prerequisites

No Lua modules required.

- Xournal++ 1.3.x (tested with 1.3.7 / 1.3.8; 1.2.x still works through compatibility fallbacks)
- [Zenity](https://gitlab.gnome.org/GNOME/zenity), or its cross-platform port [ncruces/zenity](https://github.com/ncruces/zenity), for the dialogs
- [pdftk](https://gitlab.com/pdftk-java/pdftk) (only for *Export to PDF with Bookmarks*)

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

### Windows 11

```powershell
scoop install https://ncruces.github.io/scoop/zenity.json pdftk
```

## Installation

1. Clone or download this repository.
2. Copy the `Bookmarks` folder into your Xournal++ plugins directory:

   | Platform | Plugins directory |
   |---|---|
   | Linux / macOS | `~/.config/xournalpp/plugins/` |
   | Linux, Flatpak | `~/.var/app/com.github.xournalpp.xournalpp/config/xournalpp/plugins/` |
   | Windows | `%LOCALAPPDATA%\xournalpp\plugins\` |

3. Open Xournal++.
4. Go to *Plugin > Plugin Manager* and enable the Bookmarks plugin, then restart Xournal++.

## Features

- **Add bookmarks** with a name dialog, silently (no dialog), or as a **sub-bookmark** of the previous one
- **Nested bookmarks** (chapters > sections > subsections, up to 9 levels)
- **Navigate** between bookmarks (previous/next), or between **top-level** bookmarks only (chapter to chapter)
- **Bookmark manager** with the outline shown indented: jump to, edit, move to another page, promote/demote (with sub-bookmarks), delete (only the bookmark, or with its sub-bookmarks)
- **Import** the background PDF's table of contents as bookmarks (requires pdftk)
- **Export to PDF** with an embedded, nested outline (requires pdftk). Titles are written as UTF-8, so any language, emoji and characters like `&` work. If the background PDF already has an outline, you can replace it or keep it.

### Levels

Type the level in front of the name, as in Markdown headings:

| You type | Result |
|---|---|
| `Introduction` | level 1 |
| `## Background` | level 2 |
| `### Prior work` | level 3 |
| `# ## Not a heading` | level 1, titled `## Not a heading` |

*New Bookmark* is pre-filled with the previous bookmark's prefix, so typing a name and pressing Enter creates a bookmark at the same level. *New Sub-Bookmark* is pre-filled one level deeper.

A bookmark can be at most one level deeper than the bookmark before it. If a level skips (for example after a delete), the manager shows `⚠` and the export uses the nearest valid level.

### Toolbar buttons

All actions are in the *Plugin* menu. They can also be added to a toolbar (*View > Toolbars > Customize*) as `Plugin::CUSTOM_PREVIOUS_BOOKMARK`, `CUSTOM_NEXT_BOOKMARK`, `CUSTOM_PREVIOUS_TOP_BOOKMARK`, `CUSTOM_NEXT_TOP_BOOKMARK`, `CUSTOM_NEW_BOOKMARK`, `CUSTOM_NEW_SUB_BOOKMARK`, `CUSTOM_NEW_BOOKMARK_NO_DIALOG`, `CUSTOM_VIEW_BOOKMARKS`, `CUSTOM_IMPORT_PDF_OUTLINE` and `CUSTOM_EXPORT_WITH_BOOKMARKS`.

## How bookmarks are stored

Each bookmark is a hidden layer on its page, named `Bookmark::<title>`, or `Bookmark::## <title>` for level 2, and so on. Bookmarks are saved inside the `.xopp` file and move with their page. You can see and rename them in the Layer sidebar. The outline order is page order, then layer order within a page, and new bookmarks are added on top. To reorder bookmarks on one page, move their layers.

Older versions of this plugin (and the original upstream plugin) still see nested bookmarks. They show them flat, with the `##` prefix as part of the title.

## Known behaviors

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
| `bm_doc.lua` | Layer operations and Xournal++ API compatibility |
| `bm_model.lua` | Bookmark names, levels and the outline tree |
| `bm_pdf.lua` | pdftk outline handling |

Run the tests with Lua 5.3+ from the repository root:

```bash
lua tests/run.lua
```

The tests use an in-memory fake of the Xournal++ API. The export tests run the real `pdftk` when it is installed.

## License

GNU General Public License v2 (GPLv2) — see [LICENSE](LICENSE).

- Copyright (C) 2024–2025 Javier Reyes and contributors: the original [xournalpp-bookmarks](https://github.com/jereyes4/xournalpp-bookmarks).
- Copyright (C) 2026 Ding Zheng Yuan: the zenity port and later changes.

This is a modified version of the original plugin. The main changes: the `lgi`/Glade UI was replaced by zenity dialogs, the code was split into modules (`bm_*.lua`), and nested bookmarks, import, navigation and cross-platform support were added. The git history records every change.
