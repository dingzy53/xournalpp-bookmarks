# PLAN: 2026-11-21 retest findings (xournalpp-bookmarks)

Branch: `fix/pdftk-macos-hint` (from `main` @ `3c6543f`, after PR #1).
Source: the 2026-11-21 retest on macOS 14, Xournal++ 1.3.8 (Lua 5.5.1).

PR #1 passed the retest:
- The plugin loads on Lua 5.5 (`Plugin "Bookmarks" UI initialized`).
- CI's Lua 5.5 jobs are green.
- *New Bookmark (No dialog)* works.

## Status

- [x] 1. Make the macOS pdftk install hint work without Xcode

---

## 1. The pdftk install hint fails on macOS 14 without Xcode

**Seen:**
- The plugin's hint is `brew install pdftk-java`, from `Bookmarks/bm_platform.lua:272`.
- The README says `brew install zenity pdftk-java` (README.md:54).
- On macOS 14 without Xcode, `brew install pdftk-java` fails: Homebrew builds it, or its OpenJDK dependency, from source and needs the Xcode Command Line Tools.
- The tester could not install pdftk, so *Read PDF outline* and *Export to PDF with Bookmarks* were **not tested** on macOS.

**Fix:**
1. **Confirm the right macOS install route** with Homebrew's formula page or the pdftk-java README; don't guess. Likely candidates:
   - `xcode-select --install` first (installs the Command Line Tools, no full Xcode), then `brew install pdftk-java`;
   - or the official pdftk-java release jar (`pdftk-all.jar` from https://gitlab.com/pdftk-java/pdftk/-/releases) run with a JRE, e.g. `brew install --cask temurin`, then `java -jar pdftk-all.jar`.
2. **Update the hint** in `bm_platform.lua:272` and the macOS section of `README.md` (around lines 50–57):
   - one short line in the dialog;
   - full steps in the README, including the jar and wrapper-script route if that is what works without the Command Line Tools.
3. **Optional, decide (open question):** if the jar route is documented, `bm_platform.lua` could also find `pdftk` as `java -jar <path>/pdftk-all.jar`, or allow a configurable pdftk command. Only do this if it is small and fits how `bm_platform.lua` already looks up tools. Otherwise leave it as an open question in the PR.
4. Keep the Linux hints (`bm_platform.lua:276`) unchanged.

**Tests:** if `tests/run.lua` covers the hint strings or tool lookup, update it. Keep `lua tests/run.lua` and `luac -p Bookmarks/*.lua tests/*.lua` green on the system Lua 5.4.

**Confirmed & implemented:**
- Verified against Homebrew's live formula API (`pdftk-java` 3.3.3, `openjdk` 27.0.1.1, `temurin` cask) and GitLab releases (`v3.3.3` `pdftk-all.jar`): `pdftk-java` depends on `openjdk`, which only ships bottles for Apple Silicon on macOS 15+ (`arm64_sequoia`, `arm64_tahoe`, `arm64_golden_gate`) and declares `depends_on xcode: :build # for metal` (plus `arch: :arm64`). On macOS 14 or Intel Macs, `xcode-select --install` is not enough; full Xcode is required to build `openjdk` from source.
- Updated `Bookmarks/bm_platform.lua` (one-line macOS hint; Linux hints unchanged), `README.md` (macOS no-Xcode route using `brew install --cask temurin`, official `pdftk-all.jar`, and a `~/.local/bin/pdftk` wrapper), and `tests/test_platform.lua`.
- **Open question (item 3):** left `bm_platform.lua` tool lookup unchanged. `~/.local/bin` is already searched by `M.search_dirs()`, so the 2-line wrapper works from Finder/Dock with no changes to `M.locate`/`M.run`, whereas auto-detecting `java` + `pdftk-all.jar` is brittle on macOS because `/usr/bin/java` always exists as a stub even when no JVM is installed.

**Manual follow-up (owner, on the Mac):** install pdftk with the new instructions, then test *Read PDF outline* and *Export to PDF with Bookmarks*. These were never tested on macOS.

---

## Verification
- `lua tests/run.lua` and `luac -p Bookmarks/*.lua tests/*.lua` (Lua 5.4.8): `57 passed, 0 failed`, `luac -p` clean.
- CI runs the Lua 5.5 checks.

## Commits
1. Fix the macOS pdftk install hint
2. Mark the retest plan done. PLAN.md is tracked: commit the ticked status.
