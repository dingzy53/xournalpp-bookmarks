-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2024-2025 Javier Reyes and contributors (original Bookmarks plugin)
-- Copyright (C) 2026 Ding Zheng Yuan (zenity port and later changes)
-- Modified by Ding Zheng Yuan in 2026; see README.md and the git history.
--
-- PDF outline handling through pdftk's metadata dump format.
local platform = require("bm_platform")

local M = {}

-- Titles go into a line-based format: no control characters, trimmed.
function M.clean_title(title)
  return (tostring(title or ""):gsub("[%z\1-\31\127]", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- pdftk "BookmarkBegin" records for a list of {page, title[, eff|level]}.
function M.bookmark_records(bookmarks)
  local out = {}
  for _, b in ipairs(bookmarks) do
    local title = M.clean_title(b.title)
    if title == "" then title = "Page " .. b.page end
    out[#out + 1] = "BookmarkBegin\n"
    out[#out + 1] = "BookmarkTitle: " .. title .. "\n"
    -- eff: normalised level, so each entry is at most one level deeper than
    -- the previous one (pdftk builds a wrong tree otherwise)
    out[#out + 1] = "BookmarkLevel: " .. (b.eff or b.level or 1) .. "\n"
    out[#out + 1] = "BookmarkPageNumber: " .. b.page .. "\n"
  end
  return table.concat(out)
end

-- Read pdftk's metadata dump of `pdf`. Returns the text or nil, error.
function M.read_dump(pdf)
  local data = platform.temp_path(".txt")
  local ok = platform.execute({"pdftk", pdf, "dump_data_utf8", "output", data})
  local dump = ok and platform.read_file(data)
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

-- Outline entries of a dump, in order: {title, level, page}.
function M.parse_outline(dump)
  local list, cur = {}, nil
  for raw_line in (dump .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw_line:gsub("\r$", "")
    if line:match("^BookmarkBegin%s*$") then
      cur = {title = "", level = 1, page = 0}
      list[#list + 1] = cur
    elseif cur then
      local key, value = line:match("^Bookmark(%w+): ?(.*)$")
      if key == "Title" then cur.title = M.clean_title(value)
      elseif key == "Level" then cur.level = tonumber(value) or 1
      elseif key == "PageNumber" then cur.page = tonumber(value) or 0
      elseif not key then cur = nil end
    end
  end
  return list
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
  if not platform.write_file(data, dump .. M.bookmark_records(bookmarks)) then
    os.remove(data)
    return false, "Failed to write temporary metadata file."
  end
  local ok = platform.execute({"pdftk", src, "update_info_utf8", data, "output", dst})
  if not ok then
    os.remove(dst)
    -- Xournal++ 1.3.8 QPDF exports write a direct /Info dictionary that crashes
    -- pdftk-java update_info_utf8; rewriting with `cat` converts it to an indirect object.
    local norm = platform.temp_path(".pdf")
    if platform.execute({"pdftk", src, "cat", "output", norm}) then
      ok = platform.execute({"pdftk", norm, "update_info_utf8", data, "output", dst})
    end
    os.remove(norm)
    if not ok then os.remove(dst) end
  end
  os.remove(data)
  if not ok then return false, "Failed to create PDF with bookmarks using pdftk." end
  return true
end

return M
