# Xournal++ Bookmarks (Zenity Version)

This is a fork of [Bookmarks plugin by Jereyes](https://github.com/jereyes4/xournalpp-bookmarks). 

This fork entirely removes the `lgi` dependency and replaces all user interface elements with **Zenity**.

## Prerequisites
No Lua modules required.

- Xournal++ (Tested on v1.3.4)
- Zenity: Handles the popup dialogs
- pdftk

**archlinux**:
```bash
sudo pacman -S --needed zenity pdftk
```

**Windows 11**:
```bash
scoop install https://ncruces.github.io/scoop/zenity.json pdftk
```

## Installation

1. Clone or download this repository.
2. Move the folder into your local Xournal++ plugins directory.
    - `~/.config/xournalpp/plugins/` on linux
    - `%LOCALAPPDATA%\xournalpp\plugins\` on Windows 11
3. Open Xournal++
4. Go to Plugin > Plugin Manager > Enable Bookmarks plugin

## Known Behaviors
Xournal++ may briefly show a "Not Responding" label while a Zenity dialog is open.
