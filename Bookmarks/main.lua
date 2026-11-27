-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2024-2025 Javier Reyes and contributors (original Bookmarks plugin)
-- Copyright (C) 2026 Ding Zheng Yuan (zenity port and later changes)
-- Modified by Ding Zheng Yuan in 2026; see README.md and the git history.

local platform = require("bm_platform")
local model = require("bm_model")
local ui = require("bm_ui")
local pdf = require("bm_pdf")
local doc = require("bm_doc")

local function show_msg(msg, is_error)
  doc.message(msg, is_error)
end

-- Check that an external tool is installed; explain how to install it if not.
local function need(tool)
  if platform.find_tool(tool) then return true end
  show_msg(platform.install_hint(tool), true)
  return false
end

--------------------------------------------------------------------------------
-- Public Plugin Callbacks (Registered with Xournal++)
--------------------------------------------------------------------------------

function initUi()
  local parent = {"Bookmarks"}
  app.registerUi({menu = "Bookmarks: New…", parentPath = parent, toolbarId = "CUSTOM_NEW_BOOKMARK",
    callback = "dialog_new_bookmark", iconName = "bookmark-new-symbolic"})
  app.registerUi({menu = "Bookmarks: Quick Add", parentPath = parent, toolbarId = "CUSTOM_NEW_BOOKMARK_NO_DIALOG",
    callback = "new_bookmark", iconName = "bookmark-new-symbolic"})
  app.registerUi({menu = "Bookmarks: Manage…", parentPath = parent, toolbarId = "CUSTOM_VIEW_BOOKMARKS",
    callback = "view_bookmarks", iconName = "user-bookmarks-symbolic"})
  app.registerUi({menu = "Bookmarks: Previous", parentPath = parent, toolbarId = "CUSTOM_PREVIOUS_BOOKMARK",
    callback = "search_bookmark", mode = -1, iconName = "go-previous"})
  app.registerUi({menu = "Bookmarks: Next", parentPath = parent, toolbarId = "CUSTOM_NEXT_BOOKMARK",
    callback = "search_bookmark", mode = 1, iconName = "go-next"})
  app.registerUi({menu = "Bookmarks: Import PDF Outline", parentPath = parent, toolbarId = "CUSTOM_IMPORT_PDF_OUTLINE",
    callback = "import_pdf_outline", iconName = "document-import"})
  app.registerUi({menu = "Bookmarks: Export PDF…", parentPath = parent, toolbarId = "CUSTOM_EXPORT_WITH_BOOKMARKS",
    callback = "export_with_bookmarks", iconName = "xopp-document-export-pdf"})
end

-- Clean a name typed by the user and split off its "## " level prefix.
local function parse_input(text)
  -- Strip any newlines that would break pdftk syntax
  text = (text or ""):gsub("[\r\n]", " ")
  return model.parse_title(text)
end

-- Level a new bookmark on the current page gets by default: the same level
-- as the bookmark it follows in the outline (a sibling), else 1.
local function sibling_level()
  local structure = app.getDocumentStructure()
  return model.previous_level(model.collect(structure), structure.currentPage) or 1
end

-- "Bookmarks: Quick Add": an untitled sibling of the previous bookmark.
function new_bookmark(name)
  local page = app.getDocumentStructure().currentPage
  if type(name) == "string" and name ~= "" then
    local level, title = parse_input(name)
    doc.add_bookmark(page, title, level)
  else
    doc.add_bookmark(page, "", sibling_level())
  end
end

function dialog_new_bookmark()
  if not need("zenity") then return end
  local text = ui.entry("New Bookmark",
    "Bookmark name (\"## Name\" = level 2, \"### Name\" = level 3):", model.level_prefix(sibling_level()))
  if text == nil then return end -- Cancelled
  local lvl, title = parse_input(text)
  doc.add_bookmark(app.getDocumentStructure().currentPage, title, lvl)
end

-- mode = -1 / 1: previous / next page with a bookmark.
function search_bookmark(mode)
  local structure = app.getDocumentStructure()
  local numPages = #structure.pages
  if numPages == 0 then return end
  mode = mode or 1
  local step = mode < 0 and -1 or 1

  local has_bookmark = {}
  for _, b in ipairs(model.collect(structure)) do
    has_bookmark[b.page] = true
  end

  local currentPage = structure.currentPage
  local page = currentPage
  local nextBookmark = nil
  repeat
    page = page + step
    if page > numPages then page = 1 end
    if page < 1 then page = numPages end
    if has_bookmark[page] then
      nextBookmark = page
      break
    end
  until page == currentPage

  if nextBookmark == nil then
    show_msg("No bookmark found.", false)
    return
  end

  app.setCurrentPage(nextBookmark)
  app.scrollToPage(nextBookmark)
end

local ACTION_JUMP = "Jump To"
local ACTION_RENAME = "Rename…"
local ACTION_MOVE = "Move to Page…"
local ACTION_PROMOTE = "Promote (one level up, with its sub-bookmarks)"
local ACTION_DEMOTE = "Demote (one level down, with its sub-bookmarks)"
local ACTION_DELETE = "Delete"

-- Change the level of list[i] and its sub-bookmarks by `delta`.
local function shift_subtree(list, i, delta)
  local edits = {}
  for j = i, model.subtree_end(list, i) do
    local b = list[j]
    edits[#edits + 1] = {page = b.page, layer = b.layer, title = b.title, level = b.eff + delta}
  end
  doc.rename_bookmarks(edits)
end

local function warn_preserved(preserved)
  if preserved and preserved > 0 then
    ui.info("Annotations Preserved",
      string.format("%d bookmark layer%s had drawing content and %s kept visible as a normal layer.",
        preserved, preserved == 1 and "" or "s", preserved == 1 and "was" or "were"))
  end
end

local function delete_with_choice(list, i)
  local last = model.subtree_end(list, i)
  if last == i then
    local _, preserved = doc.delete_bookmark(list[i].page, list[i].layer)
    warn_preserved(preserved)
    return
  end
  local n = last - i
  local choices = {
    "Delete only this bookmark (its sub-bookmarks move up one level)",
    string.format("Delete it with its %d sub-bookmark%s", n, n == 1 and "" or "s"),
  }
  local c = ui.choose("Delete: " .. model.display_title(list[i].title), "This bookmark has sub-bookmarks.",
    "Delete", choices)
  if c == 1 then
    -- renaming keeps layer indices, so do it before deleting
    local edits = {}
    for j = i + 1, last do
      local b = list[j]
      edits[#edits + 1] = {page = b.page, layer = b.layer, title = b.title, level = b.eff - 1}
    end
    doc.rename_bookmarks(edits)
    local _, preserved = doc.delete_bookmark(list[i].page, list[i].layer)
    warn_preserved(preserved)
  elseif c == 2 then
    local doomed = {}
    for j = i, last do doomed[#doomed + 1] = list[j] end
    local _, preserved = doc.delete_bookmarks(doomed)
    warn_preserved(preserved)
  end
end

local function rename_bookmark_dialog(b)
  local defaultName = model.format_title(b.eff, b.title)
  local newName = ui.entry("Rename Bookmark",
    "Bookmark name (\"## Name\" = level 2, \"### Name\" = level 3):", defaultName)
  if newName == nil then return end
  -- Keep characters stripped by Windows quoting when the user leaves the name unchanged.
  if newName == platform.sanitize_arg(defaultName) then newName = defaultName end
  local newLevel, title = parse_input(newName)
  doc.rename_bookmark(b.page, b.layer, title, newLevel)
end

local function move_bookmark_dialog(b, numPages)
  local newPageStr = ui.entry("Move Bookmark", "Page Number (1-" .. numPages .. "):", tostring(b.page))
  if newPageStr == nil then return end
  local newPage = tonumber(newPageStr)
  if not newPage or newPage ~= math.floor(newPage) or newPage < 1 or newPage > numPages then
    ui.error("Move Bookmark", "Invalid page number. Enter a whole number from 1 to " .. numPages .. ".")
    return
  end
  if newPage == b.page then return end
  local _, preserved = doc.delete_bookmark(b.page, b.layer)
  doc.add_bookmark(newPage, b.title, b.eff)
  app.setCurrentPage(newPage)
  app.scrollToPage(newPage)
  warn_preserved(preserved)
end

-- Ask what to do with list[i]. Returns true when the manager should close.
local function manage_bookmark(list, i, numPages)
  local b = list[i]
  local actions = {ACTION_JUMP, ACTION_RENAME, ACTION_MOVE}
  if model.can_promote(list, i) then actions[#actions + 1] = ACTION_PROMOTE end
  if model.can_demote(list, i) then actions[#actions + 1] = ACTION_DEMOTE end
  actions[#actions + 1] = ACTION_DELETE

  -- The name goes into the window title: zenity parses --text as Pango
  -- markup (GNOME) or shows it raw (ncruces), so no escaping fits both.
  local idx = ui.choose("Bookmark: " .. model.display_title(b.title), "Choose an action:", "Action", actions,
    {height = 300})
  local action = idx and actions[idx]
  if not action then return false end -- back to the list

  if action == ACTION_JUMP then
    app.setCurrentPage(b.page)
    app.scrollToPage(b.page)
    return true
  elseif action == ACTION_RENAME then
    rename_bookmark_dialog(b)
  elseif action == ACTION_MOVE then
    move_bookmark_dialog(b, numPages)
  elseif action == ACTION_PROMOTE then
    shift_subtree(list, i, -1)
  elseif action == ACTION_DEMOTE then
    shift_subtree(list, i, 1)
  elseif action == ACTION_DELETE then
    delete_with_choice(list, i)
  end
  return false
end

-- Bookmark manager: the outline as an indented list. After each change the
-- list is shown again, until it is closed or "Jump To" is chosen.
function view_bookmarks()
  local first = true
  while true do
    local structure = app.getDocumentStructure()
    local numPages = #structure.pages
    if numPages == 0 then
      show_msg("Document has no pages.", false)
      return
    end
    local bookmarks = model.collect(structure)
    if #bookmarks == 0 then
      if not first or not need("zenity") then return end
      first = false
      local choices = {"New Bookmark…"}
      if structure.pdfBackgroundFilename and structure.pdfBackgroundFilename ~= "" then
        choices[2] = "Import from PDF Outline"
      end
      local c = ui.choose("Bookmark Manager", "This document has no bookmarks yet.", "Action", choices)
      if c == 1 then
        dialog_new_bookmark()
      elseif c == 2 then
        import_pdf_outline()
        return
      else
        return
      end
    else
      if first and not need("zenity") then return end
      first = false

      local rows = {}
      for i, b in ipairs(bookmarks) do
        rows[i] = {"Page " .. b.page, model.outline_label(b)}
      end
      local idx = ui.choose_rows("Bookmark Manager", "Select a bookmark to manage:", {"Page", "Bookmark"}, rows,
        {width = 600, height = 500})
      if not idx or not bookmarks[idx] then return end -- Closed

      if manage_bookmark(bookmarks, idx, numPages) then return end
    end
  end
end

function export_with_bookmarks()
  if not need("pdftk") then return end

  local structure = app.getDocumentStructure()
  local defaultName = platform.default_export_path(structure.xoppFilename, structure.pdfBackgroundFilename)
  doc.save_dialog("bookmarks_export_to", defaultName)
end

-- Second half of the export, called with the path chosen in the save dialog.
function bookmarks_export_to(path)
  if not path or path == "" then return end -- Cancelled
  local structure = app.getDocumentStructure()

  -- Export the base PDF from Xournal++ into a temporary file
  local tempPdf = platform.temp_path(".pdf")
  app.export({outputFile = tempPdf})
  local size = platform.file_size(tempPdf)
  if not size or size == 0 then
    os.remove(tempPdf)
    show_msg("Xournal++ could not export the document to PDF.", true)
    return
  end

  local dump, err = pdf.read_dump(tempPdf)
  if not dump then
    os.remove(tempPdf)
    show_msg(err, true)
    return
  end

  -- The exported PDF may already carry the background PDF's outline.
  local bookmarks = model.collect(structure)
  local keep_existing = false
  local existing = pdf.count_outline(dump)
  if existing > 0 and #bookmarks > 0 and platform.find_tool("zenity") then
    local choices = {"Replace it with the plugin bookmarks", "Keep it and append the plugin bookmarks"}
    local idx = ui.choose("Export to PDF with Bookmarks",
      "The exported PDF already has an outline with " .. existing .. " entries (from the background PDF).",
      "Existing outline", choices)
    if not idx then
      os.remove(tempPdf)
      return
    end
    keep_existing = (idx == 2)
  elseif #bookmarks == 0 then
    keep_existing = true
  end

  -- pdftk writes to a temporary file that is then moved into place:
  -- GLib copes with non-ASCII paths on Windows and with paths that only
  -- exist inside the Flatpak sandbox, which pdftk might not.
  local tempOut = platform.temp_path(".pdf")
  local ok
  ok, err = pdf.write_outline(tempPdf, tempOut, dump, bookmarks, {keep_existing = keep_existing})
  os.remove(tempPdf)
  if ok then
    ok, err = platform.move_file(tempOut, path)
  end
  os.remove(tempOut)

  if not ok then
    show_msg(err, true)
  else
    show_msg("Successfully exported PDF with bookmarks:\n" .. path, false)
  end
end

-- Create bookmarks from the outline (table of contents) of the background PDF.
function import_pdf_outline()
  local structure = app.getDocumentStructure()
  local background = structure.pdfBackgroundFilename
  if not background or background == "" then
    show_msg("This document has no background PDF to import an outline from.", false)
    return
  end
  if not need("pdftk") then return end

  -- Copy only when pdftk may not reach the original path (Windows non-ASCII or Flatpak host).
  local source, temp_copy = background, nil
  if platform.needs_temp_copy(background, "pdftk") then
    local candidate = platform.temp_path(".pdf")
    if platform.copy_file(background, candidate) then
      temp_copy = candidate
      source = candidate
    end
  end
  local dump, err = pdf.read_dump(source)
  if temp_copy then os.remove(temp_copy) end
  if not dump then
    show_msg(err, true)
    return
  end
  local entries = pdf.parse_outline(dump)
  if #entries == 0 then
    show_msg("The background PDF has no outline (table of contents).", false)
    return
  end

  -- PDF page -> first document page showing it (pages can be inserted,
  -- removed or reordered in Xournal++).
  local page_of = {}
  for i, p in ipairs(structure.pages) do
    local n = p.pdfBackgroundPageNo
    if n and n > 0 and not page_of[n] then page_of[n] = i end
  end

  local existing = model.collect(structure)
  local preserved = 0
  if #existing > 0 then
    if not need("zenity") then return end
    local choices = {"Replace all existing bookmarks", "Keep existing bookmarks and add the imported ones"}
    local c = ui.choose("Import Bookmarks from PDF Outline",
      "This document already has bookmarks.", "Existing bookmarks", choices)
    if not c then return end
    if c == 1 then
      local _, p = doc.delete_bookmarks(existing)
      preserved = p or 0
    end
  end

  local to_add, skipped = {}, 0
  for _, e in ipairs(entries) do
    local page = page_of[e.page]
    if page then
      to_add[#to_add + 1] = {page = page, title = e.title, level = model.clamp_level(e.level)}
    else
      skipped = skipped + 1
    end
  end
  local imported = doc.add_bookmarks(to_add)

  local msg = string.format("Imported %d bookmark%s from the PDF outline.", imported, imported == 1 and "" or "s")
  if skipped > 0 then
    msg = msg .. string.format("\n%d entr%s skipped: their PDF page is not in this document.", skipped,
      skipped == 1 and "y was" or "ies were")
  end
  if preserved > 0 then
    msg = msg .. string.format("\n%d bookmark layer%s with drawing content %s kept visible as a normal layer.",
      preserved, preserved == 1 and "" or "s", preserved == 1 and "was" or "were")
  end
  show_msg(msg, false)
end
