-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2024-2025 Javier Reyes and contributors (original Bookmarks plugin)
-- Copyright (C) 2026 Ding Zheng Yuan (zenity port and later changes)
-- Modified by Ding Zheng Yuan in 2026; see README.md and the git history.
--
-- Zenity dialog helpers.
local platform = require("bm_platform")

local M = {}

local PREV_PAGE = "« Previous page"
local NEXT_PAGE = "» Next page"

-- Note: `text` must be a fixed string. GNOME zenity parses --text as Pango
-- markup while the ncruces port (Windows/macOS) shows it raw, so untrusted
-- strings (bookmark names, paths) belong in the title or in list items.

-- Text entry. Returns the entered string ("" allowed) or nil when cancelled.
function M.entry(title, text, default)
  local argv = {"zenity", "--entry", "--title=" .. title, "--text=" .. text}
  if default ~= nil then table.insert(argv, "--entry-text=" .. tostring(default)) end
  return platform.run_zenity(argv)
end

-- Split items into pages so that no generated command exceeds the platform
-- command-line limit (cmd.exe: 8191 characters). `items` are lists of cells.
function M.paginate(base_argv, items)
  local function cells_len(cells)
    local l = 0
    for _, c in ipairs(cells) do l = l + #platform.quote(c) + 1 end
    return l
  end
  local nav = cells_len({PREV_PAGE, PREV_PAGE, PREV_PAGE})
  local base_len = #platform.command_line(base_argv) + 2 * nav
  local pages, current, len = {}, {}, base_len
  for i, item in ipairs(items) do
    local l = cells_len(type(item) == "table" and item or {item})
    if #current > 0 and len + l > platform.MAX_COMMAND_LENGTH then
      table.insert(pages, current)
      current, len = {}, base_len
    end
    table.insert(current, i)
    len = len + l
  end
  if #current > 0 then table.insert(pages, current) end
  return pages
end

-- List dialog. `columns` is a list of headers and each row a list of cells
-- (or a plain string for a single column). Returns the chosen row's index,
-- or nil when cancelled.
--  * GNOME zenity: real columns plus a hidden index column that is printed.
--  * ncruces zenity (Windows, optional on macOS): one column, cells joined.
function M.choose_rows(title, text, columns, rows, opts)
  opts = opts or {}
  if type(columns) == "string" then columns = {columns} end
  local multi = #columns > 1 and platform.zenity_flavor() == "gnome"

  local base = {"zenity", "--list", "--title=" .. title, "--text=" .. text}
  if opts.width then table.insert(base, "--width=" .. opts.width) end
  if opts.height then table.insert(base, "--height=" .. opts.height) end
  if multi then
    table.insert(base, "--column=#")
    for _, c in ipairs(columns) do table.insert(base, "--column=" .. c) end
    table.insert(base, "--hide-column=1")
    table.insert(base, "--print-column=1")
  else
    table.insert(base, "--column=" .. table.concat(columns, " — "))
  end

  -- cells as passed to zenity for row i (key: "i" or the label for nav rows)
  local function cells(key, row)
    if type(row) ~= "table" then row = {row} end
    if multi then
      local out = {key}
      for c = 1, #columns do out[#out + 1] = row[c] or "" end
      return out
    end
    return {table.concat(row, "  —  ")}
  end

  local items = {}
  for i, r in ipairs(rows) do items[i] = cells(tostring(i), r) end

  local pages = M.paginate(base, items)
  local page = 1
  while pages[page] do
    local argv = {}
    local function add(list) for _, a in ipairs(list) do argv[#argv + 1] = a end end
    add(base)
    if page > 1 then add(cells(PREV_PAGE, PREV_PAGE)) end
    for _, i in ipairs(pages[page]) do add(items[i]) end
    if page < #pages then add(cells(NEXT_PAGE, NEXT_PAGE)) end

    local picked = platform.run_zenity(argv)
    if picked == nil or picked == "" then return nil end
    if multi then picked = picked:gsub("|.*$", "") end
    if picked == PREV_PAGE then
      page = page - 1
    elseif picked == NEXT_PAGE then
      page = page + 1
    elseif multi then
      return tonumber(picked)
    else
      for _, i in ipairs(pages[page]) do
        if platform.sanitize_arg(items[i][1]) == picked then return i end
      end
      return nil
    end
  end
  return nil
end

-- Single-column list of strings. Returns the chosen index, or nil.
function M.choose(title, text, column, items, opts)
  return M.choose_rows(title, text, {column}, items, opts)
end

return M
