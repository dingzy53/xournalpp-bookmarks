# PLAN: Lua 5.5 compatibility and CI check

> Branch: `fix/lua55-compat` (from `main` at `cd28db7`) · Date: 2026-11-20 · Target: `0.3.1` · Status: Items 1 and 2 implemented (`be4b06c`, `8390bf6`); release `0.3.1` not done.
>
> The previous plan (v0.3 review fixes and hierarchical bookmarks) is finished and shipped in `0.3.0`; see git history at `cd28db7` for its text.

## Context

In hands-on GUI testing on macOS 14 with Xournal++ 1.3.8 (which bundles **Lua 5.5.1**), `xournalpp-bookmarks` 0.3.0 fails to load at startup:

```
Could not run plugin Lua file: ".../Bookmarks/main.lua", error: "error loading module 'bm_pdf' ...
bm_pdf.lua:87: attempt to assign to const variable 'line'"
```

## 1. Blocker: assignment to `for`-loop control variable in `bm_pdf.lua` — **done** (`be4b06c`)

### Symptom
Enabling Bookmarks in Xournal++ 1.3.8 (Lua 5.5.1) and restarting adds no Bookmarks entries to the Plugin menu; `main.lua` aborts while loading `bm_pdf.lua`.

### Cause (verified)
In Lua 5.5, `for`-loop control variables (both numeric and generic `for`) are read-only (`<const>`).
`Bookmarks/bm_pdf.lua:86-87` mutates the loop variable `line` in `M.parse_outline`:

```lua
  for line in (dump .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
```

### Audit of all `.lua` files in this repository
Every `.lua` file under `Bookmarks/` and `tests/` was audited for:
1. Assignments to `for`-loop control variables (`for v in ...` and `for i = ...`).
   - `Bookmarks/bm_pdf.lua:87` is the **only** loop-variable assignment in the repository (`M.strip_outline` at line 62 iterates `for line in ...` without mutating `line`, which means CRLF lines in `strip_outline` should also be checked—see below).
2. Other Lua 5.5 incompatibilities:
   - `global` as a keyword/declaration: no identifier named `global` is used anywhere in `Bookmarks/` or `tests/`.
   - `table.maxn`, `bit32`, `_ENV` changes: not used.
3. Secondary finding in `Bookmarks/bm_pdf.lua:62-66` (`M.strip_outline`):
   - `M.strip_outline` iterates `for line in (dump .. "\n"):gmatch("([^\n]*)\n") do` without stripping a trailing `\r`, whereas `M.parse_outline` (line 87) strips `\r$`. Although `line:match("^BookmarkBegin%s*$")` matches `\r` via `%s`, `line:match("^Bookmark%w+:")` followed by `out[#out + 1] = line` preserves raw `\r` on non-bookmark lines. It does not assign to `line`, so it does not fail to compile on Lua 5.5.

### Fix
In `Bookmarks/bm_pdf.lua:86-87`:
```lua
  for raw_line in (dump .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw_line:gsub("\r$", "")
```

## 2. CI: verify syntax and unit tests under Lua 5.5 as well as Lua 5.4 — **done** (`8390bf6`)

### Cause
`.github/workflows/release.yml:31-32` installs only `lua5.4` from Ubuntu apt and runs `lua5.4 tests/run.lua`. Ubuntu 24.04 (`ubuntu-latest`) does not package `lua5.5` in its default archive yet, and there is no push/PR `ci.yml` workflow—tests only run when a release tag is pushed.

### Fix
1. Add `.github/workflows/ci.yml` (on `push` to `main` and `pull_request`) and update `.github/workflows/release.yml` so both:
   - run `lua5.4 tests/run.lua` (with `pdftk-java` installed);
   - build Lua 5.5.1 from the official source tarball (`https://www.lua.org/ftp/lua-5.5.1.tar.gz`, ~360 KB, compiles in <5 seconds with `make linux`), run `luac -p Bookmarks/*.lua tests/*.lua` with Lua 5.5's `luac`, and run `tests/run.lua` under Lua 5.5's `lua` interpreter.
2. Add a regression check in `tests/` (or CI step) that `luac -p Bookmarks/*.lua` succeeds. Done as a CI step in both workflows (Lua 5.5 `luac -p Bookmarks/*.lua tests/*.lua`).

## 3. Side note from `SKILL.md` open items

- `README.md` still has the `<!-- Screenshot: docs/images/hero.png -->` placeholder and no `docs/images/hero.png`. Taking the light-theme screenshot requires a GUI session with zenity installed.

## Order of work

1. [x] `Fix Lua 5.5 load error in bm_pdf.parse_outline` (`Bookmarks/bm_pdf.lua`).
2. [x] `Run tests and luac check on Lua 5.4 and 5.5 in CI` (`.github/workflows/ci.yml`, `.github/workflows/release.yml`).
3. [ ] When ready to release `0.3.1`: bump `version=0.3.1` in `Bookmarks/plugin.ini`, commit, and tag `0.3.1`.

## Verification

- Local: `lua tests/run.lua` and `luac -p Bookmarks/*.lua tests/*.lua` (Lua 5.4.8). Passed: 56 passed, 0 failed; `luac -p` clean.
- Local container / source build: compile Lua 5.5.1 in a scratch dir and run `luac -p Bookmarks/*.lua tests/*.lua` and `lua tests/run.lua`. Not done locally (building Lua was not allowed in that session); CI covers it. A manual audit re-checked every `for` loop for control-variable assignments and found only `bm_pdf.lua:87`, and found no identifier named `global`.
- macOS / Xournal++ 1.3.8: confirmed by the test report author that this one-line patch allows the plugin to load and menu actions (**New Bookmark (No dialog)**, **Previous Bookmark**, zenity install hint) to work. Full zenity + pdftk dialog/import/export testing on macOS requires `brew install zenity pdftk-java`.

## Open questions for the owner

1. Should we add a standalone `.github/workflows/ci.yml` on push/PR in addition to the tag-triggered `release.yml`? Done: `ci.yml` added; remove it if not wanted.
2. Should we tag and release `0.3.1` immediately after the fix, or wait for the `docs/images/hero.png` screenshot?
