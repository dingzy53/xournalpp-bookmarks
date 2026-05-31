# Xournal++ Bookmarks (Zenity Version)

This is a fork of [Bookmarks plugin by Jereyes](https://github.com/jereyes4/xournalpp-bookmarks). 

This fork entirely removes the `lgi` dependency and replaces all user interface elements with **Zenity**.

**Cross-platform**: A single codebase that auto-detects Linux/Windows and adapts accordingly.

## Prerequisites
No Lua modules required.

- Xournal++ (Tested on v1.3.4)
- Zenity: Handles the popup dialogs
- pdftk

**Arch Linux**:
```bash
sudo pacman -S --needed zenity pdftk
```

**Windows 11**:
```bash
scoop install https://ncruces.github.io/scoop/zenity.json pdftk
```

## Installation

1. Clone or download this repository.
2. Move the `Bookmarks` folder into your local Xournal++ plugins directory:
    - **Linux**: `~/.config/xournalpp/plugins/`
    - **Windows**: `%LOCALAPPDATA%\xournalpp\plugins\`
3. Open Xournal++
4. Go to Plugin > Plugin Manager > Enable Bookmarks plugin

## Features

- **Add bookmarks** via Zenity dialog or silently (no dialog)
- **Navigate** between bookmarks (previous/next)
- **View & manage** all bookmarks in a list (jump to, edit, or delete)
- **Export to PDF** with embedded bookmarks (requires pdftk)

## Known Behaviors

Xournal++ may briefly show a "Not Responding" label while a Zenity dialog is open.

## License

GNU General Public License v2 (GPLv2) — see [LICENSE](LICENSE).
