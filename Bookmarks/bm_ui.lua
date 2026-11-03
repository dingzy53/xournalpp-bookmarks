-- Zenity dialog helpers.
local platform = require("bm_platform")

local M = {}

local PREV_PAGE = "« Previous page"
local NEXT_PAGE = "» Next page"

-- Text entry. Returns the entered string ("" allowed) or nil when cancelled.
function M.entry(title, text, default)
  local argv = {"zenity", "--entry", "--title=" .. title, "--text=" .. text}
  if default ~= nil then table.insert(argv, "--entry-text=" .. tostring(default)) end
  return platform.run_zenity(argv)
end

-- Split items into pages so that no generated command exceeds the platform
-- command-line limit (cmd.exe: 8191 characters).
function M.paginate(base_argv, items)
  local base_len = #platform.command_line(base_argv) + 2 * (#platform.quote(PREV_PAGE) + 1)
  local pages, current, len = {}, {}, base_len
  for i, item in ipairs(items) do
    local l = #platform.quote(item) + 1
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

-- Single-column list. Returns the 1-based index of the chosen item, or nil.
-- Items should be unique (prefix them with a number if needed).
function M.choose(title, text, column, items, opts)
  opts = opts or {}
  local base = {"zenity", "--list", "--title=" .. title, "--text=" .. text, "--column=" .. column}
  if opts.width then table.insert(base, "--width=" .. opts.width) end
  if opts.height then table.insert(base, "--height=" .. opts.height) end

  local pages = M.paginate(base, items)
  local page = 1
  while pages[page] do
    local argv = {}
    for _, a in ipairs(base) do argv[#argv + 1] = a end
    if page > 1 then argv[#argv + 1] = PREV_PAGE end
    for _, i in ipairs(pages[page]) do argv[#argv + 1] = items[i] end
    if page < #pages then argv[#argv + 1] = NEXT_PAGE end

    local picked = platform.run_zenity(argv)
    if picked == nil or picked == "" then return nil end
    if picked == PREV_PAGE then
      page = page - 1
    elseif picked == NEXT_PAGE then
      page = page + 1
    else
      for _, i in ipairs(pages[page]) do
        if platform.sanitize_arg(items[i]) == picked then return i end
      end
      return nil
    end
  end
  return nil
end

return M
