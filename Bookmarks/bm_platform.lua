-- Platform helpers: OS detection, argument quoting and running external tools.
--
-- Security note: bookmark names come from the .xopp document, so every string
-- that reaches a command line must be treated as untrusted. Never build command
-- lines by hand; always pass an argv list to M.run / M.run_zenity / M.execute.
local M = {}

-- "\\" = Windows, "/" = Linux/macOS
M.IS_WINDOWS = (package.config:sub(1, 1) == "\\")

-- Longest command line we generate. cmd.exe rejects lines over 8191 characters
-- (after expansion), so stay well below that on Windows.
M.MAX_COMMAND_LENGTH = M.IS_WINDOWS and 7000 or 1000000

--------------------------------------------------------------------------------
-- Quoting
--------------------------------------------------------------------------------

-- Lossy, display-only cleanup of characters that cannot be passed safely.
-- POSIX: only control characters. Windows: also double quotes, which cmd.exe
-- treats as quote toggles no matter how they are escaped.
function M.sanitize_arg(str)
  str = tostring(str or ""):gsub("[%z\1-\31]", " ")
  if M.IS_WINDOWS then
    str = str:gsub('"', "''")
  end
  return str
end

-- POSIX shell: single quotes; escape inner single quotes.
function M.quote_posix(str)
  str = M.sanitize_arg(str)
  return "'" .. str:gsub("'", "'\\''") .. "'"
end

-- Windows, for a line inside a .cmd batch file that cmd.exe will run:
--  * double quotes are replaced (sanitize_arg), so the argument is one quoted
--    region in which & | < > ^ are literal;
--  * % is doubled, which is how a batch file spells a literal percent sign
--    (delayed expansion is disabled, so ! is literal);
--  * trailing backslashes are doubled so they do not escape the closing quote
--    (MSVCRT / Go CommandLineToArgv rules).
function M.quote_windows(str)
  str = M.sanitize_arg(str):gsub("%%", "%%%%")
  local body, slashes = str:match("^(.-)(\\*)$")
  return '"' .. body .. slashes .. slashes .. '"'
end

function M.quote(str)
  if M.IS_WINDOWS then return M.quote_windows(str) end
  return M.quote_posix(str)
end

-- Build a command line from an argv list.
function M.command_line(argv)
  local parts = {}
  for i, a in ipairs(argv) do parts[i] = M.quote(a) end
  return table.concat(parts, " ")
end

--------------------------------------------------------------------------------
-- Temporary files
--------------------------------------------------------------------------------

function M.temp_dir()
  if M.IS_WINDOWS then
    return os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
  end
  return os.getenv("TMPDIR") or "/tmp"
end

local counter = 0
-- A fresh path in the temp dir. Only ASCII is added to the directory name.
function M.temp_path(suffix)
  counter = counter + 1
  local sep = M.IS_WINDOWS and "\\" or "/"
  local dir = M.temp_dir():gsub("[/\\]+$", "")
  local name = string.format("xopp_bookmarks_%d_%d_%d%s", os.time(), math.random(100000, 999999), counter,
    suffix or "")
  return dir .. sep .. name
end

--------------------------------------------------------------------------------
-- Running commands
--------------------------------------------------------------------------------

-- Low-level runner (overridable in tests): returns output, success.
function M.exec(cmd)
  local handle = io.popen(cmd)
  if not handle then return nil, false end
  local out = handle:read("*a")
  local ok = handle:close()
  return out, ok == true or ok == 0
end

-- Windows: write the command into a UTF-8 batch file and run that.
--  * `chcp 65001` makes cmd.exe decode the following lines as UTF-8, so
--    non-ASCII bookmark names reach the program intact (io.popen alone would
--    re-encode the command with the ANSI code page);
--  * the original code page is restored afterwards and the program's exit
--    code is passed through.
function M.windows_script(command)
  return table.concat({
    "@echo off",
    "setlocal DisableDelayedExpansion",
    "for /f \"tokens=2 delims=:.\" %%c in ('chcp') do set /a BM_CP=%%c >NUL 2>&1",
    "chcp 65001 >NUL",
    command,
    "set BM_RC=%ERRORLEVEL%",
    "if defined BM_CP chcp %BM_CP% >NUL",
    "exit /b %BM_RC%",
    "",
  }, "\r\n")
end

-- Run argv and capture stdout. stderr is discarded.
-- Returns output (string, possibly empty), success (exit code 0).
function M.run(argv)
  local command = M.command_line(argv)
  if not M.IS_WINDOWS then
    return M.exec(command .. " 2>/dev/null")
  end
  local script = M.temp_path(".cmd")
  local f = io.open(script, "wb")
  if not f then return nil, false end
  f:write(M.windows_script(command .. " 2>NUL"))
  f:close()
  local out, ok = M.exec('"' .. script .. '"')
  os.remove(script)
  return out, ok
end

-- Run a zenity dialog. Returns the output without line breaks, or nil when
-- the dialog was cancelled or failed.
function M.run_zenity(argv)
  local result, success = M.run(argv)
  if not result or not success then return nil end
  -- Strip both \r and \n so Windows CRLF does not break string equality comparisons
  return (result:gsub("[\r\n]", ""))
end

-- Run a command for its exit status only.
function M.execute(argv)
  local _, ok = M.run(argv)
  return ok
end

return M
