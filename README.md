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

- **Add bookmarks** with a name dialog, or silently (no dialog)
- **Navigate** between bookmarks (previous/next)
- **View & manage** all bookmarks in a list (jump to, edit, move to another page, delete)
- **Export to PDF** with an embedded outline (requires pdftk). Titles are written as UTF-8, so any language, emoji and characters like `&` work. If the document's background PDF already has an outline, you can choose to replace it or keep it.

## How bookmarks are stored

Each bookmark is a hidden layer named `Bookmark::<title>` on its page, so bookmarks are saved inside the `.xopp` file and move with their page. You can see and rename them in the Layer sidebar. Bookmarks on the same page are ordered by layer, and new ones are added on top. To reorder bookmarks on one page, move their layers.

## Known behaviors

- Xournal++ may briefly show "Not Responding" while a Zenity dialog is open. The plugin API only offers blocking calls to external programs.
- On Windows, a console window may flash briefly when a dialog opens.
- On Windows, double quotes in bookmark names are shown as `''` in dialogs, because `cmd.exe` cannot pass them safely. The stored name stays unchanged unless you edit it.

## Development

The plugin is split into small modules:

| Module | Role |
|---|---|
| `main.lua` | Menu and toolbar callbacks |
| `bm_platform.lua` | OS, Flatpak and tool detection, safe command execution |
| `bm_ui.lua` | Zenity dialogs |
| `bm_doc.lua` | Layer operations and Xournal++ API compatibility |
| `bm_model.lua` | Bookmark parsing and collection |
| `bm_pdf.lua` | pdftk outline handling |

Run the tests with Lua 5.3+ from the repository root:

```bash
lua tests/run.lua
```

The tests use an in-memory fake of the Xournal++ API. The export tests run the real `pdftk` when it is installed.

## License

GNU General Public License v2 (GPLv2) — see [LICENSE](LICENSE).
