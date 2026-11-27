# PLAN: Review & Simplification (`xournalpp-bookmarks` v0.3.0)

> Reviewed against Xournal++ 1.3.8 (`luapi_application.h`, `Plugin.cpp`), upcoming 1.4 (`parentPath`), and `dingzy53` repo standards.
>
> Baseline on this machine (Lua 5.4.8, `pdftk-java` installed): `luac -p Bookmarks/*.lua tests/*.lua` clean; `lua tests/run.lua` passes `57 passed, 0 failed`.
>
> **Status:** Code, tests, CI, selftest, and README implemented locally on `main` (unpushed). Version bump/tag and `docs/images/hero.png` wait on Mac computer-use verification.

---

## Decisions Resolved

1. [x] **Trim Plugin menu entries (`Bookmarks/main.lua`):** Trimmed 10 flat items to 7 ordered `Bookmarks: …` items with `parentPath = {"Bookmarks"}`, keeping existing `CUSTOM_*` toolbar IDs.
2. [x] **Target Xournal++ `1.3+`:** Dropped deprecated 1.2 fallbacks in `Bookmarks/bm_doc.lua` and unused `export()` alias in `Bookmarks/main.lua`.
3. [x] **Default enabled state:** Set `enabled=true` in `Bookmarks/plugin.ini`.
4. [x] **GitHub repo description:** Updated via `gh repo edit`.

---

## 1. Bug Fix (Xournal++ API)

- **Escape Pango markup in `app.openDialog` (`Bookmarks/bm_doc.lua:115-121`):**
  Xournal++ `applib_openDialog` (`luapi_application.h:426`) calls `XojMsgBox::askQuestionWithMarkup` and parses `msg` as Pango markup. `Bookmarks/main.lua:332` and `Bookmarks/bm_platform.lua:184` pass raw file paths into `doc.message`. Any path containing `&`, `<`, or `>` breaks markup parsing. Escape `&`, `<`, and `>` in `bm_doc.message` before calling `app.openDialog`.

## 2. Interface & UX Simplification

- **Menu structure (`Bookmarks/main.lua:49-60`):**
  Group creation, management, navigation, and PDF import/export in a clean `Bookmarks: …` order. Rename `View Bookmarks` to `Bookmarks: Manage…` to match `"Bookmark Manager"`. Add `parentPath = {"Bookmarks"}` to `app.registerUi` calls (ignored on Xournal++ 1.3.x; creates a submenu on 1.4+).
- **Single-dialog editing (`Bookmarks/main.lua:24-43, 187-231`):**
  `Edit` currently forces two sequential Zenity dialogs (Page Number, then Name) even to fix a typo. Split `Edit` in `manage_bookmark` into `Rename…` (1 dialog for title/level) and `Move to Page…` (1 dialog for page number).
- **Actionable empty state (`Bookmarks/main.lua:245-248`):**
  When a document has no bookmarks, offer `New Bookmark…` (and `Import from PDF Outline` if `pdfBackgroundFilename ~= ""`) instead of showing `"No bookmarks exist"` and exiting.

## 3. Code & Performance Simplification

- **Batch layer operations (`Bookmarks/bm_doc.lua:49-112`, `Bookmarks/main.lua:380-389`):**
  `import_pdf_outline` calls `doc.add_bookmark` in a loop. Each call runs `app.getDocumentStructure()` up to 4 times and switches back to `origPage` every iteration. `doc.delete_bookmarks` also restores `origPage` on every item. Add batch helpers that read `getDocumentStructure()` once, group operations by page, restore each visited page's layer once, and restore `origPage` once at the end.
- **Avoid copying large background PDFs unnecessarily (`Bookmarks/main.lua:348-350`):**
  `import_pdf_outline` copies the whole background PDF to a temp file on every OS. Only copy when needed (`IS_WINDOWS` with non-ASCII path, or `IS_FLATPAK` when `pdftk` runs on the host).
- **Small cleanups:**
  - Read `platform.file_size(tempPdf)` once instead of twice (`Bookmarks/main.lua:286`).
  - Keep zero external settings files (bookmarks stay in `.xopp` layers) and keep Zenity as the single UI backend.
  - Consolidate small file read/write helpers between `bm_pdf.lua` and `bm_platform.lua`.
- **Docs & repo hygiene:**
  - Take `docs/images/hero.png` and replace the placeholder in `README.md:12` (screenshot work tracked separately).
  - Prune merged remote branches (`fix/lua55-compat`, `fix/pdftk-macos-hint`) if approved.

## 4. Test Suite Review & Additions

**Assessment:** Current offline coverage is solid for pure logic, quoting, and `pdftk` round-trips (`57 passed` on Lua 5.4 and 5.5), **but not yet enough to make the plugin robust**:
- `initUi()` is never executed in tests.
- `tests/fake_app.lua` does not validate Pango markup in `app.openDialog` or negative layer IDs in `app.setCurrentLayer`.
- Several edge paths are untested (special characters in export paths, 0/1-page `search_bookmark`, `import_pdf_outline` cancel/keep-existing branches, batch layer restoration).
- CI runs `tests/run.lua` on Lua 5.4 without `luac5.4 -p`, and there is no real-Xournal++ self-test script.

**Planned test additions:**
1. **Test `initUi()` (`tests/test_main.lua`):** verify `app.registerUi` is only called during `initUi`, every `menu` is non-empty, `toolbarId` values are unique, and every `callback` exists as a global function.
2. **Harden `tests/fake_app.lua`:** validate Pango markup in `app.openDialog` (fail on unescaped `&`/`<`/`>`), reject negative layer IDs in `app.setCurrentLayer`, and match `luapi_application.h` error behavior.
3. **Add edge-case tests (`tests/test_main.lua`, `tests/test_export.lua`):**
   - Paths containing `&` and `<` in export success and error dialogs.
   - `Rename…` vs `Move to Page…` flows.
   - `sanitize_arg` unchanged-name preservation on Windows (`Bookmarks/main.lua:40`).
   - `search_bookmark` on 0-page and 1-page documents.
   - `import_pdf_outline` when user cancels or chooses `"Keep existing"`.
   - Batch `add_bookmarks` / `delete_bookmarks` preserving active layers across multiple pages.
4. **CI & local in-app test:** run `luac5.4 -p Bookmarks/*.lua tests/*.lua` in `.github/workflows/ci.yml`, and add `scripts/selftest.sh` using a throwaway `XDG_CONFIG_HOME` against real `xournalpp`.
