-- Platform helpers: OS detection, argument quoting and running external tools.
local M = {}

-- "\\" = Windows, "/" = Linux/macOS
M.IS_WINDOWS = (package.config:sub(1, 1) == "\\")

-- Quote a single argument for the shell used by io.popen / os.execute.
function M.quote(str)
  str = tostring(str or "")
  if M.IS_WINDOWS then
    return '"' .. string.gsub(str, '"', '\\"') .. '"'
  else
    -- POSIX shell: single quotes; escape inner single quotes
    return "'" .. string.gsub(str, "'", "'\\''") .. "'"
  end
end

-- Build a command line from an argv list.
function M.command_line(argv)
  local parts = {}
  for i, a in ipairs(argv) do parts[i] = M.quote(a) end
  return table.concat(parts, " ")
end

-- Low-level runner (overridable in tests): returns output, success.
function M.exec(cmd)
  local handle = io.popen(cmd)
  if not handle then return nil, false end
  local out = handle:read("*a")
  local ok = handle:close()
  return out, ok
end

-- Run a zenity dialog. Returns the trimmed output, or nil when cancelled.
function M.run_zenity(argv)
  local cmd = M.command_line(argv)
  if M.IS_WINDOWS then cmd = cmd .. " 2>&1" end
  local result, success = M.exec(cmd)
  if not result then return nil end
  -- Strip both \r and \n so Windows CRLF does not break string equality comparisons
  result = string.gsub(result, "[\r\n]", "")
  if M.IS_WINDOWS then
    if result == "" then return nil end
  else
    if not success and result == "" then return nil end
  end
  return result
end

-- Run a command for its exit status only.
function M.execute(argv, null_output)
  local cmd = M.command_line(argv)
  if null_output then
    cmd = cmd .. (M.IS_WINDOWS and " > NUL 2>&1" or " > /dev/null 2>&1")
  end
  local ok = os.execute(cmd)
  return ok == true or ok == 0
end

return M
