-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2026 Ding Zheng Yuan
--
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

  {"existing background outline is replaced by default choice", function(T)
    if not have_pdftk() then return end
    local f, platform, src, out = setup(T, {outline = {"Orig1", "Orig2"}, pages = {
      {layers = {{name = "Layer 1"}, {name = "Bookmark::Mine"}}}, {}, {},
    }})
    local calls = T.script_dialogs(platform, {"Replace it with the plugin bookmarks"})
    T.list_eq(outline_of(src), {"Orig1@1:1", "Orig2@1:1"}, "fixture has an outline")
    export_with_bookmarks()
    T.eq(#calls, 1, "user was asked")
    T.list_eq(outline_of(out), {"Mine@1:1"})
    os.remove(src)
    os.remove(out)
  end},

  {"existing background outline can be kept", function(T)
    if not have_pdftk() then return end
    local f, platform, src, out = setup(T, {outline = {"Orig1", "Orig2"}, pages = {
      {}, {layers = {{name = "Layer 1"}, {name = "Bookmark::Mine"}}}, {},
    }})
    T.script_dialogs(platform, {"Keep it and append the plugin bookmarks"})
    export_with_bookmarks()
    T.list_eq(outline_of(out), {"Orig1@1:1", "Orig2@1:1", "Mine@1:2"})
    os.remove(src)
    os.remove(out)
  end},

  {"cancelling the outline question aborts the export", function(T)
    if not have_pdftk() then return end
    local f, platform, src, out = setup(T, {outline = {"Orig1"}, pages = {
      {layers = {{name = "Layer 1"}, {name = "Bookmark::Mine"}}}, {}, {},
    }})
    T.script_dialogs(platform, {false})
    export_with_bookmarks()
    T.eq(io.open(out, "rb"), nil, "no output written")
    os.remove(src)
  end},

  {"strip_outline removes only bookmark records", function(T)
    local pdf = require("bm_pdf")
    local dump = "InfoBegin\nInfoKey: Title\nInfoValue: X\nBookmarkBegin\nBookmarkTitle: A\n" ..
      "BookmarkLevel: 1\nBookmarkPageNumber: 1\nBookmarkBegin\nBookmarkTitle: B\nBookmarkLevel: 2\n" ..
      "BookmarkPageNumber: 2\nPageMediaBegin\nPageMediaNumber: 1\n"
    local stripped, n = pdf.strip_outline(dump)
    T.eq(n, 2)
    T.eq(stripped, "InfoBegin\nInfoKey: Title\nInfoValue: X\nPageMediaBegin\nPageMediaNumber: 1\n")
  end},

  {"export leaves no temporary files and handles non-ASCII destinations", function(T)
    if not have_pdftk() then return end
    local platform = require("bm_platform")
    local before = temp_snapshot(platform)
    local f, p, src, out = setup(T, {pages = {
      {layers = {{name = "Layer 1"}, {name = "Bookmark::A"}}}, {}, {},
    }})
    local dest = platform.temp_dir() .. "/bm test ü 日本 's.pdf"
    f.saveAsResult = dest
    before[src:match("[^/]+$")] = true
    export_with_bookmarks()
    T.list_eq(outline_of(dest), {"A@1:1"})
    T.list_eq(leftover_temp_files(p, before), {}, "leftover temp files")
    os.remove(dest)
    os.remove(src)
  end},

  {"export reports a failed Xournal++ export", function(T)
    local f = Fake.new({pages = {{layers = {{name = "Bookmark::A"}}}}, saveAsResult = "/nonexistent/x.pdf"})
    local p = T.load_plugin(f)
    p.find_tool = function(n) return "/usr/bin/" .. n end -- pretend pdftk exists
    f.on_export = function() end           -- writes nothing
    export_with_bookmarks()
    T.eq(f.messages[#f.messages].error, true)
    T.truthy(f.messages[#f.messages].msg:find("could not export"), f.messages[#f.messages].msg)
  end},

  {"export writes a nested outline", function(T)
    if not have_pdftk() then return end
    local f, platform, src, out = setup(T, {pages = {
      {layers = {{name = "L"}, {name = "Bookmark::Ch 1"}, {name = "Bookmark::## 1.1"}}},
      {layers = {{name = "L"}, {name = "Bookmark::### 1.1.1"}, {name = "Bookmark::#### skips to 4"},
        {name = "Bookmark::## 1.2"}}},
      {layers = {{name = "L"}, {name = "Bookmark::Ch 2"}}},
    }})
    export_with_bookmarks()
    T.list_eq(outline_of(out), {"Ch 1@1:1", "1.1@2:1", "1.1.1@3:2", "skips to 4@4:2", "1.2@2:2", "Ch 2@1:3"})
    -- check the tree pdftk actually built, via the parent/child structure qpdf reports
    local qpdf = platform.find_tool("qpdf")
    if qpdf then
      local json = platform.run({"qpdf", "--json", "--json-key=outlines", out}) or ""
      T.truthy(json:find('"title": "1.1.1"', 1, true), "nested entry present")
    end
    os.remove(src)
    os.remove(out)
  end},

  {"import background PDF outline with levels and page mapping", function(T)
    if not have_pdftk() then return end
    local platform = require("bm_platform")
    local pdf = require("bm_pdf")
    local plain = platform.temp_path("_plain.pdf")
    local bg = platform.temp_path("_bg ü.pdf")
    make_pdf(plain, 3)
    local dump = assert(pdf.read_dump(plain))
    assert(pdf.write_outline(plain, bg, dump, {
      {page = 1, title = "Ch 1 & intro", eff = 1}, {page = 2, title = "1.1 日本", eff = 2},
      {page = 3, title = "1.1.1", eff = 3}, {page = 3, title = "Ch 2", eff = 1},
    }))
    os.remove(plain)
    -- page 2 is an inserted blank page; PDF page 2 is shown on page 3
    local f = Fake.new({pdfBackgroundFilename = bg, pages = {
      {pdfPage = 1}, {pdfPage = 0}, {pdfPage = 2}, {pdfPage = 3},
    }})
    T.load_plugin(f)
    import_pdf_outline()
    T.list_eq(f:names(1), {"Layer 1", "Bookmark::Ch 1 & intro"})
    T.list_eq(f:names(2), {"Layer 1"})
    T.list_eq(f:names(3), {"Layer 1", "Bookmark::## 1.1 日本"})
    T.list_eq(f:names(4), {"Layer 1", "Bookmark::### 1.1.1", "Bookmark::Ch 2"})
    T.truthy(f.messages[#f.messages].msg:find("Imported 4 bookmarks", 1, true), f.messages[#f.messages].msg)

    -- importing again asks; "Replace" leaves exactly one copy
    local p = require("bm_platform")
    T.script_dialogs(p, {"Replace all existing bookmarks"})
    import_pdf_outline()
    T.list_eq(f:names(4), {"Layer 1", "Bookmark::### 1.1.1", "Bookmark::Ch 2"})
    T.list_eq(f:names(1), {"Layer 1", "Bookmark::Ch 1 & intro"})
    os.remove(bg)
  end},

  {"import reports missing background PDF and skipped pages", function(T)
    local f = Fake.new({pages = {{}}})
    T.load_plugin(f)
    import_pdf_outline()
    T.truthy(f.messages[1].msg:find("no background PDF", 1, true))
    local pdf = require("bm_pdf")
    local list = pdf.parse_outline("BookmarkBegin\nBookmarkTitle: A: b\nBookmarkLevel: 2\nBookmarkPageNumber: 7\n" ..
      "PageMediaBegin\nPageMediaNumber: 1\n")
    T.eq(#list, 1)
    T.eq(list[1].title, "A: b")
    T.eq(list[1].level, 2)
    T.eq(list[1].page, 7)
  end},
}
