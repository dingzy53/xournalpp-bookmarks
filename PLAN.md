# PLAN — Review fixes & hierarchical bookmarks

Status: Part 1 implemented (branch `fix/review-and-cross-platform`), Part 2 not started · Date: 2026-11-03 · Target: plugin v0.3

> **Progress.** F1–F13 are done, plus macOS and Flatpak support, with one commit each. Two changes from the original plan:
> - F1 uses a UTF-8 batch file with escaping plus pagination, because the ncruces Windows zenity only takes list rows as arguments, not on stdin.
> - F8 moves names into the dialog title, because GNOME zenity parses `--text` as markup while ncruces shows it raw.
>
> The module layout from §2.4 exists as `bm_platform`, `bm_ui`, `bm_doc`, `bm_model`, `bm_pdf`, with tests in `tests/`. F14 (README) is done. F15 (accelerators) is still open.

This plan has two parts:

1. **Review** of the current plugin (`Bookmarks/main.lua`, `utf8_to_html.lua`, `plugin.ini`) against the latest Xournal++ Lua plugin API (release **v1.3.8**, 2026-09-26, plus `master`), with a prioritized fix list.
2. **Design and implementation plan for hierarchical (nested) bookmarks**, e.g. Chapter → Section → Subsection, exported as a nested PDF outline.

---

## Part 1 — Review against the current Xournal++ API

### 1.1 What was checked

| Source | Notes |
|---|---|
| `plugins/luapi_application.def.lua` (master) | Official API stubs, including deprecation notices |
| `src/core/plugin/luapi_application.h` at v1.2.0, v1.3.0, v1.3.4, v1.3.8, master | What each function actually does, and which versions have it |
| `src/core/pdf/base/XojCairoPdfExport.cpp` | Whether the exported PDF already includes an outline |

API availability by version (from the C++ sources):

| API | 1.2.x | 1.3.0–1.3.8 | master |
|---|---|---|---|
| `app.openDialog` | – | ✔ | ✔ |
| `app.msgbox` | ✔ | ✔ (deprecated) | ✔ (deprecated) |
| `app.activateAction` / `changeActionState` | – | ✔ | ✔ |
| `app.layerAction` | ✔ | ✔ (deprecated) | ✔ (deprecated, "Todo(gtk4) remove") |
| `app.saveAs` (blocking) | ✔ | ✔ (deprecated) | ✔ (deprecated, "Todo(gtk4) remove") |
| `app.fileDialogSave(cb, name)` (async) | – | ✔ | ✔ |
| `app.getFolder("config"/"state"/"data")` | – | ✔ | ✔ |
| `app.registerPlaceholder` / `setPlaceholderValue` | – | ✔ | ✔ |
| `registerUi{parentPath=…}` (submenus) | – | – | ✔ (unreleased) |
| `export{backend="cairo"/"qpdf"}` | – | – | ✔ (unreleased) |
| `layers[i].name` in `getDocumentStructure()` | ✔ | ✔ | ✔ (*not documented* in the `.def.lua`, but set in C++) |

Conclusions:
- The plugin uses two calls marked **deprecated and scheduled for removal in the GTK4 port**: `app.layerAction("ACTION_NEW_LAYER" / "ACTION_DELETE_LAYER")` and `app.saveAs()`. They still work in 1.3.8, but the plugin should switch to `activateAction("layer-new-above-current" / "layer-delete")` and `fileDialogSave`, keeping the old calls as fallbacks.
- The plugin depends on `layers[i].name`. This field exists in every version but is not documented. Note this in the README; it is a small risk.

### 1.2 Findings and fixes (by priority)

#### P0 — Security / correctness

**F1. Command injection on Windows through bookmark names.** `sh_escape` on Windows wraps the string in `"…"` and turns `"` into `\"`. `cmd.exe` does not treat `\"` as an escape, so a quote in a name ends the quoted string, and anything after it (`&`, `|`, `>`, `%VAR%`) is run by the shell. Layer names come from the `.xopp` file, so **opening a crafted document and clicking "View Bookmarks" can run arbitrary commands** on Windows. The POSIX single-quote escaping is correct.
- Fix (preferred): do not put document strings on the command line at all. Write the list rows to a temp file and run `zenity --list … < rows.txt`. GNOME zenity reads list rows from stdin, one cell per line. **To verify:** whether the ncruces Windows port of zenity also reads stdin.
- Fallback if stdin is not supported on Windows: sanitise strings before building the command (remove or replace `"`, `%`, `^`, `!`, control characters). Display only; the stored name is not changed.
- Side benefit: this also avoids the `cmd.exe` 8191-character command-line limit, which documents with many bookmarks currently hit (the view dialog silently fails).

**F2. Export breaks on any non-UTF-8 byte and does not escape `&`.** `utf8_to_html` raises `error()` on invalid UTF-8, which aborts the export with a Lua traceback. It also leaves `&`, `<` and `>` unchanged, so pdftk's entity decoder can misread a title such as `R&D &#x41;`.
- Fix: switch to `pdftk … dump_data_utf8` and `update_info_utf8`. Both pdftk and pdftk-java support them, they take raw UTF-8, and no entity encoding is needed. Delete `utf8_to_html.lua`. Before writing, normalise titles: replace CR/LF/TAB with spaces and trim.

**F3. Exported PDF may already have an outline, which results in duplicate or mixed bookmarks.** Xournal++'s Cairo PDF export copies the *background PDF's* outline (`populatePdfOutline()`). `dump_data` then includes those `BookmarkBegin` blocks, and the plugin appends its own at level 1, after all of them. With hierarchy this gets worse, because a level-1 entry appended after a deep level is valid but appears in the wrong order.
- Fix: parse the dump and strip existing `BookmarkBegin…` blocks by default. If any were present, ask once: *Replace* (default) / *Keep background outline and append*. A later option: *Merge sorted by page*.

#### P1 — Robustness

**F4. Deprecated API usage.** Add small compatibility shims, so the plugin keeps working after the GTK4 port while 1.2.x still works:
```lua
local function act(new_name, old_name)
  if app.activateAction then app.activateAction(new_name) else app.layerAction(old_name) end
end
-- act("layer-new-above-current", "ACTION_NEW_LAYER")
-- act("layer-delete",            "ACTION_DELETE_LAYER")
```
Rewrite `export_with_bookmarks` in two phases: `export_with_bookmarks()` calls `app.fileDialogSave("bm_export_cb", suggested)`, and the global `bm_export_cb(path)` does the work (an empty path means the user cancelled). Fall back to `app.saveAs` when `fileDialogSave` is missing.

**F5. `app.setCurrentLayer` raises a Lua error** (`luaL_error`) when the index is out of range. The plugin calls it with indices taken from a structure snapshot that is stale after a layer add or delete. Wrap these calls in `pcall`, re-read `getDocumentStructure()` after every mutation, and centralise the logic in one helper (see `with_layer` in §2.6).

**F6. Batch layer deletes shift indices.** Deleting layer *k* renumbers every layer above *k* on that page. Single deletes are fine today, but subtree delete and outline import (Part 2) need to **mutate in descending (page, layer) order**.

**F7. Temp file leaks and an unchecked export.** On POSIX, `os.tmpname()` *creates* the file `tempBase`, which is never removed. Also, `app.export` failing is not detected; pdftk then fails with a confusing message. Fix: `os.remove(tempBase)` and check that `tempPdf` exists before calling pdftk. Prefer `app.getFolder("state")` (1.3+) or `TMPDIR`/`TEMP` as the temp directory.

**F8. Zenity Pango markup.** `--text` is parsed as Pango markup, so a bookmark named `a < b & c` makes the "Action for: …" prompt fail or show empty. Escape `& < >` in every `--text`, or put the name in the title instead.

**F9. Windows `2>&1` in `run_zenity`.** Merging stderr into the result means any warning text becomes the "selection". Use `2>NUL` instead. Check the exit status where possible.

#### P2 — Quality and UX

- **F10. Better default export name.** If the `.xopp` file is unsaved but `pdfBackgroundFilename` is set, use `<pdf base>_export.pdf` instead of `/tmp/temp_export.pdf`.
- **F11. Background layer.** All three loops iterate `pairs(layers)`, which includes the background `[0]` (its `name` is the background name; `type(u)=="number"` does not exclude it). Iterate `for i = 1, #layers` everywhere.
- **F12. Duplicated code.** The "collect bookmarks" loop appears three times (view on Windows, view on Linux, export). Extract a single `collect_bookmarks(structure)` (see §2.4).
- **F13. Order within a page is unstable.** `new_bookmark` inserts the layer *above the current layer*, so the order of several bookmarks on one page depends on which layer happened to be active. This is harmless for flat bookmarks but **matters for hierarchy** (Chapter must come before its Section on the same page). Fix: always append the new bookmark layer *on top of the page's existing bookmark layers*: select the highest bookmark layer, or the top layer, then add the new layer above it.
- **F14. README.** Update "Tested on" to 1.3.8. Document `update_info_utf8`. Document that the bookmark layers are named `Bookmark::…`, are hidden, and can be reordered manually in the Layer sidebar.
- **F15. Optional accelerators.** `registerUi{accelerator=…}` is supported. Consider defaults for Previous/Next (for example `<Alt>Page_Up` / `<Alt>Page_Down`), and check them against Xournal++'s built-in shortcuts first.

---

## Part 2 — Hierarchical bookmarks

### 2.1 Goals / non-goals

**Goals**
- Each bookmark has a **level** (1 = top). The outline is the document-ordered list of bookmarks plus their levels, which is the same model as PDF outlines and pdftk's `BookmarkLevel`.
- Existing documents keep working unchanged (every old bookmark is level 1).
- Documents that use hierarchy stay readable by the original upstream plugin (they degrade to flat bookmarks with a visible `## ` prefix).
- The UI works with what zenity can do on Linux and Windows. No new dependencies.
- Export produces a correctly nested PDF outline.

**Non-goals (for now)**
- Bookmarks that point to a position on the page. pdftk's `BookmarkPageNumber` only targets a page.
- A real tree widget. zenity has none; we use indentation in a list.
- Collapsed/open state of outline nodes in the PDF.

### 2.2 Storage format (layer name)

Bookmarks stay **hidden layers** whose names start with `Bookmark::`. The level is encoded Markdown-style, at the start of the title:

```
Bookmark::Introduction            → level 1, "Introduction"    (legacy form, still written for level 1)
Bookmark::## Background           → level 2, "Background"
Bookmark::### Prior work          → level 3, "Prior work"
Bookmark::# ## not a heading      → level 1, "## not a heading" (explicit level 1 to protect a literal title)
Bookmark::#hashtag                → level 1, "#hashtag"         (no space after #'s → literal)
```

Parse rule: `title = name:sub(11)`. If `title` matches `^(#+) (.*)$`, then `level = #hashes` and `title = rest`. Otherwise `level = 1` and the title is unchanged.

Serialise rule: if level ≥ 2, write `string.rep("#", level) .. " " .. title`. If level = 1, write `title` as-is, unless it matches `^#+ `, in which case write `"# " .. title`.

Limits: `MAX_LEVEL = 9`. Clamp on parse.

Why this format:
- **Backward compatible:** every existing `Bookmark::Title` parses as level 1.
- **Forward degradation:** the old plugin still recognises the `Bookmark::` prefix and shows or exports `## Background`, which is still readable.
- **The same syntax is used for input** (§2.5): users type `## Background` in the name dialog. One syntax to learn, and no escape characters except the rare `# ` case.
- It is visible and editable by hand in Xournal++'s Layer sidebar.

Alternatives considered:
- `Bookmark:2:Title`: the old plugin cannot see it.
- Side-car JSON file: it gets out of sync when pages move, it is not saved inside the `.xopp`, and it adds file-handling complexity.
- Storing the level in the layer's position: not robust, because users reorder layers.

### 2.3 Ordering and tree semantics

- **Document order** = (page ascending, layer index ascending). Fix F13 guarantees that new bookmarks on a page are appended after the existing ones. Users can reorder bookmarks on the same page by moving the layers in the Layer sidebar.
- **Tree derivation** (the standard outline rule): the parent of bookmark *i* is the nearest earlier bookmark with a smaller level.
- **Normalisation:** stored levels may be "invalid" (for example 1 → 3, or the first bookmark at level 2) after deletes, moves or hand edits. For display and export, compute
  `eff[1] = 1`, `eff[i] = min(stored[i], eff[i-1] + 1)`.
  Stored values are **never rewritten implicitly**, so a temporary gap does not destroy the user's intent. The manager shows a ⚠ marker when `eff ≠ stored`.
- **Subtree** of *i*: the following bookmarks *j > i* with `eff[j] > eff[i]`, up to the first with `eff[j] ≤ eff[i]`.

### 2.4 Code structure (refactor first)

Split `main.lua` so that the hierarchy logic is pure Lua and testable without Xournal++:

```
Bookmarks/
  main.lua          -- registerUi + global callbacks only (thin)
  model.lua         -- PURE: parse/serialize names, collect, normalize, subtree, outline→pdftk text
  doc.lua           -- Xournal++ adapter: with_layer, add/rename/delete bookmark layers, compat shims (F4/F5)
  ui.lua            -- zenity wrappers: entry, list-from-stdin (F1), radiolist, escaping (F8/F9)
  pdf.lua           -- export/import via pdftk (*_utf8), dump parsing (F2/F3)
  plugin.ini
tests/
  test_model.lua    -- plain `lua5.4 tests/test_model.lua` (no framework needed)
  test_doc.lua      -- runs doc.lua against a fake `app` table (in-memory pages/layers)
```

Note: `require` of sibling modules already works, since `utf8_to_html` is required this way. Keep module names unique (for example a `bm_` prefix) to avoid clashing with other plugins' modules in `package.loaded`.

Main data type (`model.lua`):
```lua
-- Bookmark = { page=int, layer=int, level=int, eff=int, title=string, raw=string }
model.parse_name(layerName)        -> level, title | nil (not a bookmark)
model.format_name(level, title)    -> "Bookmark::..."
model.collect(structure)           -> Bookmark[] in document order, with .eff filled in
model.normalize(list)              -- fills .eff
model.subtree(list, i)             -> i_last (inclusive range i..i_last)
model.prev_level_at(list, page)    -> level of the last bookmark at or before `page` (default for new)
model.to_pdftk(list)               -> "BookmarkBegin\nBookmarkTitle: …\nBookmarkLevel: eff\nBookmarkPageNumber: …\n"…
model.from_pdftk(dumpText)         -> {title, level, page}[]   (for import and F3 stripping)
```

### 2.5 User-facing features

**A. New bookmark (dialog)**: the existing "New Bookmark" action.
- Show the zenity entry **pre-filled with the level prefix of the previous bookmark** in document order (for example `## `). Pressing Enter after typing a name creates a sibling. Deleting a `#` creates a parent-level bookmark; adding one creates a child.
- The dialog text explains the rule: `Use "## Title" for level 2, "### Title" for level 3.`
- Linux: also consider `zenity --forms` with an entry plus a combo for "Level". **To verify** whether it is supported on Windows; if not, keep the single entry.

**B. Quick-add actions** (new menu or toolbar items, no level typing needed):
- `New Child Bookmark`: level = previous bookmark's eff + 1.
- `New Sibling Bookmark`: same level as the previous bookmark. This is what "New Bookmark (No dialog)" becomes, at the same level instead of always level 1.
- Both ask for a name via the entry (no prefix); the "No dialog" variant uses an empty title, as today.

**C. Bookmark manager** (View Bookmarks):
- The list shows the outline with indentation. Linux columns: `ID (hidden) | Page | Level | Title`. The title is rendered as `string.rep("    ", eff-1) .. (eff>1 and "↳ " or "") .. title`, followed by ` ⚠` when normalised. Windows (single column): `[p_l] p.12  ␣␣␣␣↳ Title`. **To verify:** that zenity or GTK keeps leading spaces in list cells. If it does not, use U+2003 EM SPACE or `│ ` guides.
- Rows are passed through stdin (F1).
- Action menu after selecting a row:

| Action | Behaviour |
|---|---|
| Jump To | As today |
| Edit | Entry pre-filled with `## Title` (level + title in one field), then the page entry. If only the title or level changed: rename in place. If the page changed: move only this bookmark (children stay), then warn when the move changes the tree (shown via ⚠) |
| Promote (← level − 1) | Applies to the bookmark **and its subtree** (keeps relative structure). Disabled at level 1 |
| Demote (→ level + 1) | Applies to the bookmark and its subtree. Allowed only if the result has eff ≤ previous eff + 1; otherwise show "Cannot demote: no parent bookmark above" |
| Delete | If it has children, ask: *Delete only this (children move up one level)* / *Delete with all sub-bookmarks* / Cancel |
| Move subtree to page… | Optional (phase 2). Moves the whole subtree, keeping each child's page offset relative to the parent and clamping to the document |

- Because zenity is modal and synchronous, return to the list after an action (loop until Cancel). This makes multiple edits much faster than reopening the manager each time.

**D. Navigation**
- `Previous/Next Bookmark`: unchanged (any level).
- New: `Previous/Next Top-level Bookmark` (mode ±2): jumps between level-1 entries only ("next chapter").
- Optional (1.3+): `registerPlaceholder("BOOKMARK_BREADCRUMB")` shows a toolbar text such as `2 Methods › 2.1 Setup`. The plugin API has **no page-change event**, so this text is refreshed only by the plugin's own navigation actions. Document this limitation, or skip the feature.

**E. Export to PDF**
- Use `collect` → `normalize` → `to_pdftk` with `BookmarkLevel: eff`.
- pdftk requires each level to be ≤ previous + 1; normalisation guarantees this.
- Use `dump_data_utf8` / `update_info_utf8` (F2). Handle an existing outline as in F3.

**F. Import outline from background PDF** (phase 2, high value for annotating textbooks or papers)
- Menu item `Import Bookmarks from PDF Outline`. Run `pdftk <pdfBackgroundFilename> dump_data_utf8` and parse with `model.from_pdftk`.
- Map PDF page → xopp page using `pages[i].pdfBackgroundPageNo`, taking the first xopp page that shows that PDF page. Skip entries whose page is not in the document, and report the count.
- If bookmarks already exist, ask *Replace all / Append / Cancel*.
- Create the layers in document order, appending per page (F13). This is O(n) layer actions; show a zenity `--progress` for large outlines if that proves necessary.

### 2.6 Layer-manipulation helpers (`doc.lua`)

Each mutation must save and restore the user's page and layer, and each must re-read the structure afterwards.

```lua
-- Runs fn() with (page, layer) active; restores the original page & layer afterwards.
doc.with_layer(page, layer, fn)

doc.add_bookmark(page, level, title)   -- appends above the topmost existing bookmark layer on `page` (F13); hidden
doc.rename_bookmark(page, layer, level, title)
doc.delete_bookmarks(list_of {page,layer})  -- sorts descending (page, layer) before deleting (F6)
```

Undo: every layer add, rename or delete is its own undo step. A subtree promote of N items needs N undos. Document this; the plugin API has no grouped undo for layer operations.

### 2.7 Edge cases to cover

- Empty title. It is shown as "(No name)". On export, use `Page N` so that PDF viewers do not show blank entries.
- First bookmark stored at level > 1: displayed and exported as level 1, with ⚠.
- Page deleted or moved in Xournal++: the bookmark moves with the page, because it is a layer on that page. The tree is recomputed automatically.
- Copying a page (`duplicate-page`) duplicates its bookmark layers. Document this; the manager shows both copies.
- Titles containing `|`, quotes, `<`, `&`, emoji, RTL text, or newlines (pasted). Covered by stdin rows, markup escaping, `_utf8` export and newline stripping.
- Very large outlines (500+ entries). Covered by stdin rows (no command-line limit) and an O(n) collect.
- Background layer named `Bookmark::…` is ignored (F11).

---

## Part 3 — Milestones

| # | Milestone | Contents | Exit criteria |
|---|---|---|---|
| M0 | Critical fixes | F1, F2, F3, F7 on the current single-file code | Windows: a name containing `" & calc & "` is shown literally and nothing runs. Export with `R&D`, `ü`, `日本`, an invalid byte works. No leftover temp files |
| M1 | Refactor | Split into `model/doc/ui/pdf`; F4, F5, F8–F13; `tests/` | Same behaviour as M0; `lua5.4 tests/test_model.lua` passes; manual smoke test on 1.3.8 |
| M2 | Hierarchy core | Storage format (§2.2), normalisation, subtree, nested export | Round trip: create a 3-level outline, export, and `pdftk out.pdf dump_data_utf8` shows the correct `BookmarkLevel`s; outline renders nested in Okular/Evince/SumatraPDF |
| M3 | Hierarchy UI | §2.5 A–D: prefix entry, child/sibling actions, indented manager, promote/demote/delete-subtree, top-level navigation | Manual checklist below passes on Linux and Windows |
| M4 | Import | §2.5 F | Import the outline of a multi-level PDF, then export again: the outline is identical (titles, levels, pages) |
| M5 | Release | README (format, features, limits), `plugin.ini` version `0.3`, changelog | Tag `v0.3` |

### Test plan

**Automated (pure Lua, no Xournal++ needed)**
- `parse_name` / `format_name` round trip for every example in §2.2, plus fuzzed titles.
- `normalize`: sequences such as `{2,1}`, `{1,3,3,2}`, `{1,1,4}`, and empty input.
- `subtree` at the start, middle and end, and at the maximum level.
- `to_pdftk` / `from_pdftk` round trip, including UTF-8 text and `&`.
- `doc.lua` against a fake `app` that models pages and layers. Assert that F6 (descending deletes) and F13 (append order) hold, and that the page and layer are restored.

**Manual (Linux GNOME zenity 4.x and Windows ncruces zenity), Xournal++ 1.3.8**
1. Old document with flat bookmarks: everything appears as level 1, and export is unchanged.
2. Create Ch1 / ## 1.1 / ## 1.2 / ### 1.2.1 / Ch2, some of them on the same page. Check the manager indentation and order.
3. Promote 1.2 with its subtree, demote it back, and check that 1.2.1 follows.
4. Delete 1.2 "only this": 1.2.1 becomes level 2. Undo it.
5. Export and inspect the outline in Okular/Evince (Linux) and SumatraPDF/Edge (Windows).
6. Background PDF with its own outline: check the Replace and Append choices (F3).
7. Import the outline from the background PDF, then export: the result matches the original.
8. Open the hierarchical document with the *original* upstream plugin: the bookmarks are visible and flat with a `##` prefix, and nothing crashes.

### Open questions (verify before M3)
- Does ncruces zenity (Windows) read `--list` rows from stdin, and does it support `--radiolist` and `--forms`?
- Does GTK zenity keep leading spaces in `--list` cells?
- Should "Move bookmark to another page" move the subtree by default? The current proposal is no, with a separate action for that.

---

## References
- Xournal++ releases: https://github.com/xournalpp/xournalpp/releases (latest v1.3.8)
- Lua API stubs: https://github.com/xournalpp/xournalpp/blob/master/plugins/luapi_application.def.lua
- Lua API implementation: https://github.com/xournalpp/xournalpp/blob/master/src/core/plugin/luapi_application.h
- Plugin docs: https://xournalpp.github.io/guide/plugins/plugins/
- pdftk `dump_data_utf8` / `update_info_utf8`: https://www.pdflabs.com/docs/pdftk-man-page/
