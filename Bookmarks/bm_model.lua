-- Pure bookmark model: no calls into Xournal++ or the shell.
local M = {}

M.PREFIX = "Bookmark::"
local PREFIX_LEN = #M.PREFIX

-- Returns the bookmark title if `name` is a bookmark layer name, else nil.
function M.title_of(name)
  if type(name) == "string" and name:sub(1, PREFIX_LEN) == M.PREFIX then
    return name:sub(PREFIX_LEN + 1)
  end
  return nil
end

function M.layer_name(title)
  return M.PREFIX .. (title or "")
end

-- Collect bookmarks of a single page, in layer order.
function M.collect_page(structure, page)
  local list = {}
  local pageInfo = structure.pages[page]
  if not pageInfo then return list end
  -- Layer 0 is the page background; its "name" is the background name.
  for i = 1, #pageInfo.layers do
    local v = pageInfo.layers[i]
    local title = v and M.title_of(v.name)
    if title then
      table.insert(list, {page = page, layer = i, title = title})
    end
  end
  return list
end

-- Collect all bookmarks in document order (page, then layer).
function M.collect(structure)
  local list = {}
  for page = 1, #structure.pages do
    for _, b in ipairs(M.collect_page(structure, page)) do
      table.insert(list, b)
    end
  end
  return list
end

function M.display_title(title)
  if title == nil or title == "" then return "(No name)" end
  return title
end

return M
