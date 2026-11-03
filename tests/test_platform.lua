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
}
