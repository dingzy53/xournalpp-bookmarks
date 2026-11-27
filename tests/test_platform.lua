-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2026 Ding Zheng Yuan

local NASTY = {
  [[plain]],
  [[it's]],
  [[a" & calc & "]],
  [[%PATH% and %%]],
  [[back\slash\]],
  [[trailing\\]],
  [[$(touch /tmp/pwned) `id` ; | < > ^ !x! *]],
  "tab\tand\nnewline",
  "日本語 ü 🙂",
}

-- Minimal model of how cmd.exe scans a batch-file line: a double quote toggles
-- "quoted" state; outside quotes & | < > ^ ( ) are special. Returns true when
-- every special character lies inside a quoted region and no stray % remains.
local function cmd_safe(line)
  local quoted = false
  local i = 1
  while i <= #line do
    local c = line:sub(i, i)
    if c == '"' then
      quoted = not quoted
    elseif c == "%" then
      if line:sub(i + 1, i + 1) ~= "%" then return false, "single % at " .. i end
      i = i + 1
    elseif not quoted and c:match("[&|<>^()]") then
      return false, "unquoted " .. c .. " at " .. i
    end
    i = i + 1
  end
  return not quoted, "unbalanced quotes"
end

-- How cmd.exe (batch) then the CRT/Go parse one quoted argument back.
local function cmd_unquote(arg)
  local inner = arg:sub(2, -2):gsub("%%%%", "%%")
  return (inner:gsub("\\\\$", "\\"):gsub("\\\\$", "\\"))
end

return {
  {"POSIX quoting round-trips through a real shell", function(T)
    local platform = require("bm_platform")
    if platform.IS_WINDOWS then return end
    for _, s in ipairs(NASTY) do
      local out = platform.exec("printf '%s' " .. platform.quote_posix(s))
      T.eq(out, platform.sanitize_arg(s), "round trip of " .. s)
    end
  end},

  {"Windows quoting keeps specials inside one quoted region", function(T)
    local platform = require("bm_platform")
    local saved = platform.IS_WINDOWS
    platform.IS_WINDOWS = true
    for _, s in ipairs(NASTY) do
      local q = platform.quote_windows(s)
      local ok, why = cmd_safe("zenity --entry " .. q .. " " .. q)
      T.truthy(ok, "unsafe quoting for " .. s .. ": " .. q .. " (" .. tostring(why) .. ")")
      T.truthy(not q:sub(2, -2):find('"'), "embedded quote in " .. q)
    end
    T.eq(platform.quote_windows([[C:\dir\]]), [["C:\dir\\"]])
    T.eq(cmd_unquote(platform.quote_windows([[C:\dir\]])), [[C:\dir\]])
    T.eq(platform.quote_windows("50%"), [["50%%"]])
    T.eq(platform.quote_windows('say "hi"'), [["say ''hi''"]])
    platform.IS_WINDOWS = saved
  end},

  {"Windows script switches to UTF-8 and restores the code page", function(T)
    local platform = require("bm_platform")
    local s = platform.windows_script('"zenity" "--entry"')
    T.truthy(s:find("chcp 65001 >NUL", 1, true))
    T.truthy(s:find("DisableDelayedExpansion", 1, true))
    T.truthy(s:find("exit /b %BM_RC%", 1, true))
    T.truthy(s:find("\r\n", 1, true), "batch files need CRLF")
  end},

  {"run returns output and exit status", function(T)
    local platform = require("bm_platform")
    if platform.IS_WINDOWS then return end
    local out, ok = platform.run({"printf", "%s", "a b"})
    T.eq(out, "a b")
    T.eq(ok, true)
    local _, ok2 = platform.run({"false"})
    T.eq(ok2, false)
    T.eq(platform.run_zenity({"false"}), nil, "non-zero exit means cancelled")
  end},

  {"long lists are paginated under the command-line limit", function(T)
    local platform = require("bm_platform")
    package.loaded.bm_ui = nil
    local ui = require("bm_ui")
    local saved = platform.MAX_COMMAND_LENGTH
    platform.MAX_COMMAND_LENGTH = 300
    local items = {}
    for i = 1, 50 do items[i] = string.format("[%d_1] Page %d: Bookmark number %d", i, i, i) end
    local pages = ui.paginate({"zenity", "--list"}, items)
    T.truthy(#pages > 1, "expected several pages")
    local seen = 0
    for _, p in ipairs(pages) do
      local argv = {"zenity", "--list", "« Previous page", "» Next page"}
      for _, i in ipairs(p) do argv[#argv + 1] = items[i] end
      T.truthy(#platform.command_line(argv) <= 300, "page too long")
      seen = seen + #p
    end
    T.eq(seen, 50)

    -- navigate: next page, then pick the first item there
    local calls = {}
    platform.run_zenity = function(argv)
      calls[#calls + 1] = argv
      if #calls == 1 then return "» Next page" end
      return argv[7] -- base has 5 args, then "« Previous page", then first item
    end
    local idx = ui.choose("t", "x", "c", items)
    T.eq(#calls, 2)
    T.eq(calls[2][6], "« Previous page")
    T.eq(items[idx], calls[2][7])
    T.truthy(idx > 1)
    platform.MAX_COMMAND_LENGTH = saved
    package.loaded.bm_platform = nil
    package.loaded.bm_ui = nil
  end},

  {"find_tool searches PATH and Homebrew locations", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    if platform.IS_WINDOWS then return end
    T.truthy(platform.find_tool("sh"), "sh should be found")
    T.eq(platform.find_tool("definitely-not-a-tool-xyz"), nil)
    local dirs = table.concat(platform.search_dirs(), ":")
    T.truthy(dirs:find("/opt/homebrew/bin", 1, true), "Homebrew (Apple Silicon) searched")
    T.truthy(dirs:find("/usr/local/bin", 1, true), "Homebrew (Intel) searched")
    local home = os.getenv("HOME")
    if home then T.truthy(dirs:find(home .. "/.local/bin", 1, true), "~/.local/bin searched") end
    package.loaded.bm_platform = nil
  end},

  {"install_hint mentions no-Xcode fallback on macOS and keeps Linux hints", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    platform.IS_WINDOWS = false
    platform.IS_FLATPAK = false

    platform.is_mac = function() return true end
    local mac_pdftk = platform.install_hint("pdftk")
    T.truthy(mac_pdftk:find("brew install pdftk-java", 1, true), mac_pdftk)
    T.truthy(mac_pdftk:find("brew install --cask temurin", 1, true), mac_pdftk)
    T.truthy(mac_pdftk:find("pdftk-all.jar", 1, true), mac_pdftk)
    local hint_line = mac_pdftk:match("Install it with:\n  (.+)$")
    T.truthy(hint_line and not hint_line:find("\n", 1, true), "macOS hint should be one short line")

    local mac_zenity = platform.install_hint("zenity")
    T.truthy(mac_zenity:find("brew install zenity", 1, true), mac_zenity)
    T.truthy(not mac_zenity:find("ncruces/tap/zenity", 1, true), mac_zenity)

    platform.is_mac = function() return false end
    local linux_pdftk = platform.install_hint("pdftk")
    T.truthy(linux_pdftk:find("sudo dnf install pdftk-java / sudo apt install pdftk-java / sudo pacman -S pdftk",
      1, true), linux_pdftk)
    package.loaded.bm_platform = nil
  end},

  {"zenity flavor detection", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    platform.run = function() return "zenity v0.10.14 darwin/arm64\n", true end
    T.eq(platform.zenity_flavor(), "ncruces")
    package.loaded.bm_platform = nil
    platform = require("bm_platform")
    platform.run = function() return "4.2.2\n", true end
    T.eq(platform.zenity_flavor(), "gnome")
    package.loaded.bm_platform = nil
  end},

  {"Flatpak: host tools run through flatpak-spawn --host", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    if platform.IS_WINDOWS then return end
    platform.IS_FLATPAK = true
    platform.locate = function(name)
      if name == "pdftk" then return {path = "/usr/bin/pdftk", host = true} end
      if name == "flatpak-spawn" then return {path = "/usr/bin/flatpak-spawn", host = false} end
      return {path = "/usr/bin/" .. name, host = false}
    end
    platform.find_tool = function(n) return platform.locate(n).path end
    local cmds = {}
    platform.exec = function(cmd) cmds[#cmds + 1] = cmd return "", true end
    platform.run({"pdftk", "a b.pdf", "dump_data_utf8"})
    platform.run({"zenity", "--entry"})
    T.eq(cmds[1], "'/usr/bin/flatpak-spawn' '--host' '/usr/bin/pdftk' 'a b.pdf' 'dump_data_utf8' 2>/dev/null")
    T.eq(cmds[2], "'/usr/bin/zenity' '--entry' 2>/dev/null")
    package.loaded.bm_platform = nil
  end},

  {"Flatpak: temp files go to a host-visible directory", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    if platform.IS_WINDOWS then return end
    platform.IS_FLATPAK = true
    local saved_app = _G.app
    _G.app = nil
    local cache = os.getenv("XDG_CACHE_HOME")
    if cache and cache ~= "" then
      T.eq(platform.temp_dir(), cache)
    else
      T.eq(platform.temp_dir(), os.getenv("HOME"), "falls back to the (shared) home directory")
    end
    _G.app = {getFolder = function() return "/home/u/.var/app/x/.local/state/plugin-state/Bookmarks" end}
    if not (cache and cache ~= "") then
      T.eq(platform.temp_dir(), "/home/u/.var/app/x/.local/state/plugin-state/Bookmarks")
    end
    _G.app = saved_app
    package.loaded.bm_platform = nil
  end},

  {"Windows runs the batch file with cmd-safe quoting", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    platform.IS_WINDOWS = true
    platform.find_tool = function(n) return "C:\\scoop\\shims\\" .. n .. ".exe" end
    platform.locate = function(n) return {path = platform.find_tool(n), host = false} end
    local tmp = os.tmpname()
    os.remove(tmp)
    platform.temp_path = function(suffix) return tmp .. suffix end
    local script_text, popen_cmd
    platform.exec = function(cmd)
      popen_cmd = cmd
      local path = cmd:match('^""(.*)""$')
      local f = io.open(path, "rb")
      script_text = f:read("*a")
      f:close()
      return "picked\r\n", true
    end
    T.eq(platform.run_zenity({"zenity", "--entry", "--entry-text=a\" & calc & \"%x%"}), "picked")
    T.truthy(popen_cmd:match('^"".*%.cmd""$'), popen_cmd)
    T.truthy(script_text:find('"C:\\scoop\\shims\\zenity.exe" "--entry" "--entry-text=a\'\' & calc & \'\'%%x%%" 2>NUL', 1, true),
      script_text)
    T.eq(io.open(popen_cmd:match('^""(.*)""$'), "rb"), nil, "batch file removed")
    package.loaded.bm_platform = nil
  end},

  {"needs_temp_copy skips native POSIX paths and copies Windows non-ASCII or Flatpak host", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    platform.IS_WINDOWS = false
    platform.IS_FLATPAK = false
    T.eq(platform.needs_temp_copy("/home/u/日本語.pdf", "pdftk"), false)

    platform.IS_FLATPAK = true
    platform.locate = function() return {path = "/usr/bin/pdftk", host = true} end
    T.eq(platform.needs_temp_copy("/home/u/notes.pdf", "pdftk"), true)

    platform.IS_FLATPAK = false
    platform.IS_WINDOWS = true
    T.eq(platform.needs_temp_copy("C:\\Users\\u\\notes.pdf", "pdftk"), false)
    T.eq(platform.needs_temp_copy("C:\\Users\\u\\日本語.pdf", "pdftk"), true)
    package.loaded.bm_platform = nil
  end},

  {"macOS with ncruces zenity passes --modal=false to avoid deadlock", function(T)
    package.loaded.bm_platform = nil
    local platform = require("bm_platform")
    local calls = {}
    platform.run = function(argv) calls[#calls + 1] = argv return "ok\n", true end

    local orig_argv = {"zenity", "--entry", "--title=T"}
    platform.is_mac = function() return true end
    platform.zenity_flavor = function() return "ncruces" end
    T.eq(platform.run_zenity(orig_argv), "ok")
    T.list_eq(calls[1], {"zenity", "--modal=false", "--entry", "--title=T"})
    T.list_eq(orig_argv, {"zenity", "--entry", "--title=T"}, "caller argv must not be mutated")

    platform.run_zenity({"false"})
    T.list_eq(calls[2], {"false"})

    platform.zenity_flavor = function() return "gnome" end
    platform.run_zenity({"zenity", "--entry", "--title=T"})
    T.list_eq(calls[3], {"zenity", "--entry", "--title=T"})

    platform.is_mac = function() return false end
    platform.zenity_flavor = function() return "ncruces" end
    platform.run_zenity({"zenity", "--entry", "--title=T"})
    T.list_eq(calls[4], {"zenity", "--entry", "--title=T"})
    package.loaded.bm_platform = nil
  end},
}
