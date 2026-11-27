-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- In-app self test. Runs inside a real Xournal++ against the real `app` API.
local pluginDir = assert(os.getenv("BM_PLUGIN_DIR"), "BM_PLUGIN_DIR not set")
package.path = pluginDir .. "/?.lua;" .. package.path

local out = assert(io.open(assert(os.getenv("BM_OUT")), "w"))
local failures = 0
local function log(s) out:write(s, "\n"); out:flush() end
local function check(cond, msg)
  log((cond and "ok   " or "FAIL ") .. msg)
  if not cond then failures = failures + 1 end
end

local function steps()
  local doc = require("bm_doc")
  local model = require("bm_model")
  local pdf = require("bm_pdf")
  local tmp = assert(os.getenv("BM_TMP"))

  check(app.openFile(os.getenv("BM_DOC"), 1, true), "openFile fixture")
  coroutine.yield()

  local s0 = app.getDocumentStructure()
  check(#s0.pages == 2, "fixture has 2 pages")

  -- 1. Batch add across pages while preserving current page and layer
  local added = doc.add_bookmarks({
    {page = 1, title = "Intro & Plan", level = 1},
    {page = 2, title = "Details", level = 2},
    {page = 2, title = "Temp", level = 2},
  })
  check(added == 3, "add_bookmarks added 3")
  coroutine.yield()

  local s1 = app.getDocumentStructure()
  check(s1.currentPage == 1, "currentPage preserved")
  check(s1.pages[1].layers[s1.pages[1].currentLayer].name == "Layer 1", "page 1 active layer preserved")
  check(s1.pages[2].layers[s1.pages[2].currentLayer].name == "Layer 1", "page 2 active layer preserved")
  check(s1.pages[1].layers[1].name == "Bookmark::Intro & Plan" and s1.pages[1].layers[2].name == "Layer 1",
    "bookmark layer placed below user layer")
  local list = model.collect(s1)
  check(#list == 3 and list[2].eff == 2, "model.collect sees 3 bookmarks")

  -- 2. Rename and delete
  check(doc.rename_bookmark(1, list[1].layer, "Intro <1> & Plan", 1), "rename_bookmark")
  check(doc.delete_bookmark(2, list[3].layer), "delete_bookmark")
  coroutine.yield()

  local list2 = model.collect(app.getDocumentStructure())
  check(#list2 == 2 and list2[1].title == "Intro <1> & Plan", "2 bookmarks remain after delete")

  -- 3. Export PDF + pdftk outline round-trip
  local basePdf = tmp .. "/base.pdf"
  local outPdf = tmp .. "/out.pdf"
  app.export({outputFile = basePdf})
  local dump = pdf.read_dump(basePdf)
  check(dump ~= nil, "pdftk read_dump on exported PDF")
  if dump then
    local ok = pdf.write_outline(basePdf, outPdf, dump, list2)
    check(ok, "pdftk write_outline")
    local outDump = pdf.read_dump(outPdf)
    local parsed = outDump and pdf.parse_outline(outDump) or {}
    check(#parsed == 2 and parsed[1].title == "Intro <1> & Plan" and parsed[2].level == 2,
      "exported PDF outline matches")
  end

  -- 4. Save .xopp so selftest.sh can inspect persisted bookmark layers
  app.activateAction("save")
  coroutine.yield("wait")

  -- 5. Reopen saved .xopp: active layer must be the user layer ("Layer 1"), not a bookmark layer
  check(app.openFile(os.getenv("BM_DOC"), 1, true), "reopen saved fixture")
  coroutine.yield("wait")
  local s2 = app.getDocumentStructure()
  check(s2.pages[1].layers[s2.pages[1].currentLayer].name == "Layer 1", "reopen page 1 activates user layer")
  check(s2.pages[2].layers[s2.pages[2].currentLayer].name == "Layer 1", "reopen page 2 activates user layer")
  log("DONE failures=" .. failures)
end

local co = coroutine.create(steps)

local function tick()
  local ok, res = coroutine.resume(co)
  if not ok then
    log("FAIL error: " .. tostring(res))
    log("DONE failures=" .. (failures + 1))
    out:close()
    app.activateAction("quit")
    return
  end
  if coroutine.status(co) == "dead" then
    out:close()
    app.activateAction("quit")
    return
  end
  return res
end

function initUi()
  local okLgi, lgi = pcall(require, "lgi")
  if not okLgi then okLgi, lgi = pcall(require, "LuaGObject") end
  if not okLgi then
    log("FAIL selftest needs lgi to schedule steps: " .. tostring(lgi))
    log("DONE failures=1")
    out:close()
    return
  end
  local GLib = lgi.GLib
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1500, function()
    local function loop()
      local res = tick()
      if coroutine.status(co) ~= "dead" then
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, res == "wait" and 500 or 100, function() loop() return false end)
      end
    end
    loop()
    return false
  end)
end
