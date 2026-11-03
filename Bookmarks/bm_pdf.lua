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

-- Read pdftk's metadata dump of `pdf`. Returns the text or nil, error.
function M.read_dump(pdf)
  local data = platform.temp_path(".txt")
  local ok = platform.execute({"pdftk", pdf, "dump_data_utf8", "output", data})
  local dump = ok and read_file(data)
  os.remove(data)
  if not dump then return nil, "Failed to read PDF metadata with pdftk." end
  return dump
end

-- Remove all outline records from a dump. Returns the new dump and the
-- number of removed bookmarks.
function M.strip_outline(dump)
  local out, removed, skipping = {}, 0, false
  for line in (dump .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^BookmarkBegin%s*$") then
      skipping = true
      removed = removed + 1
    elseif skipping and line:match("^Bookmark%w+:") then
      -- part of the current bookmark record
    else
      skipping = false
      out[#out + 1] = line
    end
  end
  while out[#out] == "" do out[#out] = nil end
  return table.concat(out, "\n") .. "\n", removed
end

function M.count_outline(dump)
  local n = 0
  for _ in dump:gmatch("BookmarkBegin") do n = n + 1 end
  return n
end

-- Writes `dst` = `src` with its outline set to `bookmarks`.
-- `dump` is src's metadata (from read_dump). Unless opts.keep_existing is
-- set, an outline already present in src (e.g. copied from the background
-- PDF by Xournal++'s exporter) is replaced instead of being mixed with ours.
-- Uses the *_utf8 variants of pdftk's commands so titles are plain UTF-8
-- (the non-utf8 variants need XML entities and mis-handle '&').
-- Returns true, or false and an error message.
function M.write_outline(src, dst, dump, bookmarks, opts)
  opts = opts or {}
  if not opts.keep_existing then dump = M.strip_outline(dump) end
  local data = platform.temp_path(".txt")
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
