-- Integration tests for the export pipeline. They run the real `pdftk`
-- (skipped when it is not installed) on a generated PDF.
local Fake = require("fake_app")

-- Minimal valid PDF with `n` empty pages and, optionally, an existing outline.
local function make_pdf(path, n, outline_titles)
  local objs = {}
  local kids = {}
  objs[1] = "<< /Type /Catalog /Pages 2 0 R" .. (outline_titles and " /Outlines 3 0 R" or "") .. " >>"
  local first_page = 4
  for i = 1, n do kids[i] = (first_page + i - 1) .. " 0 R" end
  objs[2] = "<< /Type /Pages /Count " .. n .. " /Kids [" .. table.concat(kids, " ") .. "] >>"
  for i = 1, n do
    objs[first_page + i - 1] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>"
  end
  if outline_titles then
    local first = first_page + n
    local m = #outline_titles
    objs[3] = string.format("<< /Type /Outlines /First %d 0 R /Last %d 0 R /Count %d >>", first, first + m - 1, m)
    for i, t in ipairs(outline_titles) do
      local o = {"/Title (" .. t .. ")", "/Parent 3 0 R", "/Dest [" .. kids[1] .. " /Fit]"}
      if i > 1 then o[#o + 1] = "/Prev " .. (first + i - 2) .. " 0 R" end
      if i < m then o[#o + 1] = "/Next " .. (first + i) .. " 0 R" end
      objs[first + i - 1] = "<< " .. table.concat(o, " ") .. " >>"
    end
  else
    objs[3] = "<< >>"
  end
  local parts, offsets = {"%PDF-1.4\n"}, {}
  local pos = #parts[1]
  for i = 1, #objs do
    offsets[i] = pos
    local s = i .. " 0 obj\n" .. objs[i] .. "\nendobj\n"
    parts[#parts + 1] = s
    pos = pos + #s
  end
  local xref = {"xref\n0 " .. (#objs + 1) .. "\n0000000000 65535 f \n"}
  for i = 1, #objs do xref[#xref + 1] = string.format("%010d 00000 n \n", offsets[i]) end
  parts[#parts + 1] = table.concat(xref)
  parts[#parts + 1] = "trailer\n<< /Size " .. (#objs + 1) .. " /Root 1 0 R >>\nstartxref\n" .. pos .. "\n%%EOF\n"
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(parts))
  f:close()
end

local function have_pdftk()
  local platform = require("bm_platform")
  return platform.execute({"pdftk", "--version"})
end

local function outline_of(path)
  local platform = require("bm_platform")
  local out = platform.run({"pdftk", path, "dump_data_utf8"})
  local list = {}
  for title, level, page in out:gmatch("BookmarkTitle: ([^\n]*)\nBookmarkLevel: (%d+)\nBookmarkPageNumber: (%d+)") do
    list[#list + 1] = title .. "@" .. level .. ":" .. page
  end
  return list
end

local function copy_file(from, to)
  local i = assert(io.open(from, "rb"))
  local o = assert(io.open(to, "wb"))
  o:write(i:read("*a"))
  i:close()
  o:close()
end

local function setup(T, opts)
  local platform = require("bm_platform")
  local src = platform.temp_path("_src.pdf")
  local out = platform.temp_path("_out.pdf")
  make_pdf(src, 3, opts.outline)
  local f = Fake.new({pages = opts.pages, saveAsResult = out, xoppFilename = "/home/u/notes.xopp"})
  f.on_export = function(o) copy_file(src, o.outputFile) end
  local p = T.load_plugin(f)
  return f, p, src, out
end

local function leftover_temp_files(platform, before)
  local list = {}
  local dir = platform.temp_dir()
  local h = io.popen("ls -1 " .. platform.quote(dir) .. " 2>/dev/null")
  for name in h:lines() do
    if name:match("^xopp_bookmarks_") and not before[name] then list[#list + 1] = name end
  end
  h:close()
  return list
end

local function temp_snapshot(platform)
  local set = {}
  local h = io.popen("ls -1 " .. platform.quote(platform.temp_dir()) .. " 2>/dev/null")
  for name in h:lines() do set[name] = true end
  h:close()
  return set
end

return {
  {"export writes UTF-8 titles, '&' and empty names", function(T)
    if not have_pdftk() then print("  (skipped: pdftk not found)") return end
    local f, platform, src, out = setup(T, {pages = {
      {layers = {{name = "Layer 1"}, {name = "Bookmark::R&D <draft> &#65;"}}},
      {layers = {{name = "Layer 1"}, {name = "Bookmark::日本語 ü 🙂"}, {name = "Bookmark::"}}},
      {layers = {{name = "Layer 1"}, {name = "Bookmark::  tab\there  "}}},
    }})
    export_with_bookmarks()
    T.list_eq(outline_of(out), {"R&D <draft> &#65;@1:1", "日本語 ü 🙂@1:2", "Page 2@1:2", "tab here@1:3"})
    T.eq(f.messages[#f.messages].error, false, f.messages[#f.messages].msg)
    os.remove(src)
    os.remove(out)
  end},
}
