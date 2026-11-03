-- PDF outline handling through pdftk's metadata dump format.
local platform = require("bm_platform")

local M = {}

-- Titles go into a line-based format: no control characters, trimmed.
function M.clean_title(title)
  return (tostring(title or ""):gsub("[%z\1-\31\127]", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- pdftk "BookmarkBegin" records for a list of {page, title[, level]}.
function M.bookmark_records(bookmarks)
  local out = {}
  for _, b in ipairs(bookmarks) do
    local title = M.clean_title(b.title)
    if title == "" then title = "Page " .. b.page end
    out[#out + 1] = "BookmarkBegin\n"
    out[#out + 1] = "BookmarkTitle: " .. title .. "\n"
    out[#out + 1] = "BookmarkLevel: " .. (b.level or 1) .. "\n"
    out[#out + 1] = "BookmarkPageNumber: " .. b.page .. "\n"
  end
  return table.concat(out)
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_file(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

-- Writes `dst` = `src` with the given bookmarks added to its outline.
-- Uses the *_utf8 variants of pdftk's commands so titles are plain UTF-8
-- (the non-utf8 variants need XML entities and mis-handle '&').
-- Returns true, or false and an error message.
function M.add_bookmarks(src, dst, bookmarks)
  local data = platform.temp_path(".txt")
  if not platform.execute({"pdftk", src, "dump_data_utf8", "output", data}) then
    os.remove(data)
    return false, "Failed to read PDF metadata with pdftk."
  end
  local dump = read_file(data)
  if not dump then
    os.remove(data)
    return false, "Failed to read temporary metadata file."
  end
  if not write_file(data, dump .. M.bookmark_records(bookmarks)) then
    os.remove(data)
    return false, "Failed to write temporary metadata file."
  end
  local ok = platform.execute({"pdftk", src, "update_info_utf8", data, "output", dst})
  os.remove(data)
  if not ok then return false, "Failed to create PDF with bookmarks using pdftk." end
  return true
end

return M
