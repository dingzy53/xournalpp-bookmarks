-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- Offline test runner. Usage (from the repository root):  lua tests/run.lua
package.path = "Bookmarks/?.lua;tests/?.lua;" .. package.path

local T = {passed = 0, failed = 0}

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s\n  expected: %s\n  actual:   %s", msg or "values differ",
      tostring(expected), tostring(actual)), 2)
  end
end

function T.truthy(v, msg)
  if not v then error(msg or "expected truthy value", 2) end
end

function T.list_eq(actual, expected, msg)
  local a = table.concat(actual, " | ")
  local e = table.concat(expected, " | ")
  if a ~= e then
    error(string.format("%s\n  expected: %s\n  actual:   %s", msg or "lists differ", e, a), 2)
  end
end

-- Fresh plugin environment: reloads modules so stubs do not leak between tests.
function T.load_plugin(fake)
  for _, m in ipairs({"bm_platform", "bm_model", "bm_ui", "bm_doc", "bm_pdf", "main"}) do
    package.loaded[m] = nil
  end
  fake:install()
  local platform = require("bm_platform")
  platform.zenity_flavor = function() return "gnome" end
  -- Dialogs are scripted (T.script_dialogs), so zenity need not be installed.
  -- Other tools (pdftk) are still looked up for real.
  local find_tool = platform.find_tool
  platform.find_tool = function(name)
    if name == "zenity" then return "/usr/bin/zenity" end
    return find_tool(name)
  end
  dofile("Bookmarks/main.lua")
  return platform
end

-- Script zenity answers: each call pops the next answer (string, or false for cancel).
function T.script_dialogs(platform, answers)
  local calls = {}
  platform.run_zenity = function(argv)
    table.insert(calls, argv)
    local a = table.remove(answers, 1)
    if a == false or a == nil then return nil end
    return a
  end
  return calls
end

local files = arg[1] and {arg[1]} or {"tests/test_model.lua", "tests/test_main.lua", "tests/test_platform.lua",
  "tests/test_export.lua"}

for _, f in ipairs(files) do
  local fh = io.open(f, "r")
  if fh then
    fh:close()
    local suite = dofile(f)
    for _, case in ipairs(suite) do
      local ok, err = pcall(case[2], T)
      if ok then
        T.passed = T.passed + 1
      else
        T.failed = T.failed + 1
        print("FAIL " .. f .. " :: " .. case[1] .. "\n  " .. tostring(err))
      end
    end
  end
end

print(string.format("%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
