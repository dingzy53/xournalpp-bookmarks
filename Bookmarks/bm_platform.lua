-- Platform helpers: OS detection, argument quoting and running external tools.
--
-- Security note: bookmark names come from the .xopp document, so every string
-- that reaches a command line must be treated as untrusted. Never build command
-- lines by hand; always pass an argv list to M.run / M.run_zenity / M.execute.
local M = {}

-- "\\" = Windows, "/" = Linux/macOS
M.IS_WINDOWS = (package.config:sub(1, 1) == "\\")

local is_mac_cache
-- macOS is a POSIX system; tell it apart from Linux with uname.
function M.is_mac()
  if M.IS_WINDOWS then return false end
  if is_mac_cache == nil then
    local out = M.exec("uname -s 2>/dev/null")
    is_mac_cache = (out or ""):match("^Darwin") ~= nil
  end
  return is_mac_cache
end

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

math.randomseed(os.time())
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

function M.file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

local function copy_file(from, to)
  local i = io.open(from, "rb")
  if not i then return false end
  local o = io.open(to, "wb")
  if not o then i:close() return false end
  while true do
    local chunk = i:read(65536)
    if not chunk then break end
    o:write(chunk)
  end
  i:close()
  return o:close() and true or false
end

-- Move a file to its final destination (overwriting it). Prefers
-- app.glib_rename, which takes UTF-8 paths and works across file systems.
-- Returns true, or false and an error message.
function M.move_file(from, to)
  if app and app.glib_rename then
    local ok, res = pcall(app.glib_rename, from, to)
    if ok and res then return true end
  end
  if os.rename(from, to) then return true end
  if copy_file(from, to) then
    os.remove(from)
    return true
  end
  return false, "Could not write the exported PDF to:\n" .. tostring(to)
end

--------------------------------------------------------------------------------
-- Locating external tools
--------------------------------------------------------------------------------

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- Directories searched in addition to PATH. Apps started from the macOS
-- Finder/Dock get a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin) that does
-- not include Homebrew or MacPorts.
function M.search_dirs()
  local dirs, seen = {}, {}
  local function add(d)
    if d and d ~= "" and not seen[d] then seen[d] = true dirs[#dirs + 1] = d end
  end
  local sep = M.IS_WINDOWS and ";" or ":"
  for d in (os.getenv("PATH") or ""):gmatch("[^" .. sep .. "]+") do add(d) end
  if M.IS_WINDOWS then
    local home = os.getenv("USERPROFILE")
    if home then add(home .. "\\scoop\\shims") end
    local scoop = os.getenv("SCOOP")
    if scoop then add(scoop .. "\\shims") end
  else
    local home = os.getenv("HOME")
    for _, d in ipairs({"/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin", "/snap/bin"}) do
      add(d)
    end
    if home then add(home .. "/.local/bin") end
  end
  return dirs
end

local tool_cache = {}
-- Full path of an external program, or nil when it cannot be found.
function M.find_tool(name)
  if tool_cache[name] then return tool_cache[name] end
  local exts = M.IS_WINDOWS and {".exe", ".cmd", ".bat", ""} or {""}
  local sep = M.IS_WINDOWS and "\\" or "/"
  for _, d in ipairs(M.search_dirs()) do
    for _, ext in ipairs(exts) do
      local candidate = d:gsub("[/\\]+$", "") .. sep .. name .. ext
      if file_exists(candidate) then
        tool_cache[name] = candidate
        return candidate
      end
    end
  end
  return nil
end

-- How to install a missing tool on this platform.
function M.install_hint(name)
  local hints
  if M.IS_WINDOWS then
    hints = {
      zenity = "scoop install https://ncruces.github.io/scoop/zenity.json",
      pdftk = "scoop install pdftk",
    }
  elseif M.is_mac() then
    hints = {zenity = "brew install zenity   (or: brew install ncruces/tap/zenity)", pdftk = "brew install pdftk-java"}
  else
    hints = {
      zenity = "e.g. sudo dnf install zenity / sudo apt install zenity / sudo pacman -S zenity",
      pdftk = "e.g. sudo dnf install pdftk-java / sudo apt install pdftk-java / sudo pacman -S pdftk",
    }
  end
  return string.format("'%s' was not found.\n\nInstall it with:\n  %s", name, hints[name] or name)
end

local flavor_cache
-- "gnome" for GNOME zenity, "ncruces" for the Go port (Windows, optional on
-- macOS). The port supports a single list column and no --hide-column.
function M.zenity_flavor()
  if flavor_cache then return flavor_cache end
  if M.IS_WINDOWS then
    flavor_cache = "ncruces"
  else
    local out = M.run({"zenity", "--version"}) or ""
    -- ncruces prints "zenity v0.10.14 darwin/arm64", GNOME prints "4.2.2"
    flavor_cache = out:match("^zenity ") and "ncruces" or "gnome"
  end
  return flavor_cache
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
  local resolved = {}
  for i, a in ipairs(argv) do resolved[i] = a end
  resolved[1] = M.find_tool(argv[1]) or argv[1]
  local command = M.command_line(resolved)
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
