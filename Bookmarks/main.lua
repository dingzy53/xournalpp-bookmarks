local platform = require("bm_platform")
local model = require("bm_model")
local ui = require("bm_ui")
local pdf = require("bm_pdf")
local doc = require("bm_doc")

local IS_WINDOWS = platform.IS_WINDOWS

-- Default export path suggestion
local DEFAULT_EXPORT_PATH = IS_WINDOWS and ((os.getenv("TEMP") or "C:\\Temp") .. "\\temp") or "/tmp/temp"

local function show_msg(msg, is_error)
  doc.message(msg, is_error)
end

-- Parse the "page_layer" ID returned by the bookmark list
local function parse_bookmark_id(selected_id)
  local p, l = selected_id:match("^(%d+)_(%d+)$")
  return tonumber(p), tonumber(l)
end

local function edit_bookmark_zenity(title, defaultPage, defaultName, numPages)
  local newPageStr = ui.entry(title, "Page Number (1-" .. numPages .. "):", tostring(defaultPage))
  if newPageStr == nil then return nil end -- Cancelled

  local newPage = tonumber(newPageStr)
  if not newPage or newPage < 1 or newPage > numPages then
    show_msg("Invalid page number. Edit cancelled.", true)
    return nil
  end

  local newName = ui.entry(title, "Bookmark Name:", defaultName)
  if newName == nil then return nil end -- Cancelled
  -- Characters that cannot be passed to zenity are replaced in the pre-filled
  -- text; keep the original name when the user did not change it.
  if newName == platform.sanitize_arg(defaultName) then newName = defaultName end

  return newPage, newName
end

--------------------------------------------------------------------------------
-- Public Plugin Callbacks (Registered with Xournal++)
--------------------------------------------------------------------------------

function initUi()
  app.registerUi({menu="Previous Bookmark", toolbarId="CUSTOM_PREVIOUS_BOOKMARK", callback="search_bookmark", mode=-1, iconName="go-previous"})
  app.registerUi({menu="New Bookmark", toolbarId="CUSTOM_NEW_BOOKMARK", callback="dialog_new_bookmark", iconName="bookmark-new-symbolic"})
  app.registerUi({menu="New Bookmark (No dialog)", toolbarId="CUSTOM_NEW_BOOKMARK_NO_DIALOG", callback="new_bookmark", iconName="bookmark-new-symbolic"})
  app.registerUi({menu="Next Bookmark", toolbarId="CUSTOM_NEXT_BOOKMARK", callback="search_bookmark", mode=1, iconName="go-next"})
  app.registerUi({menu="View Bookmarks", toolbarId="CUSTOM_VIEW_BOOKMARKS", callback="view_bookmarks", iconName="user-bookmarks-symbolic"})
  app.registerUi({menu="Export to PDF with Bookmarks", toolbarId="CUSTOM_EXPORT_WITH_BOOKMARKS", callback="export_with_bookmarks", iconName="xopp-document-export-pdf"})
end

function new_bookmark(name)
  if type(name) ~= "string" then name = "" end
  -- Strip any newlines that would break pdftk syntax
  name = name:gsub("[\r\n]", " ")
  doc.add_bookmark(app.getDocumentStructure().currentPage, name)
end

function dialog_new_bookmark()
  local name = ui.entry("New Bookmark", "Enter bookmark name:")
  if name ~= nil then
    new_bookmark(name)
  end
end

-- mode = -1 for searching backwards, or 1 for searching forwards
function search_bookmark(mode)
  local structure = app.getDocumentStructure()
  local numPages = #structure.pages
  if numPages == 0 then return end

  local currentPage = structure.currentPage
  local page = currentPage
  local nextBookmark = nil

  repeat
    page = page + mode
    if page > numPages then page = 1 end
    if page < 1 then page = numPages end
    if #model.collect_page(structure, page) > 0 then
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

function view_bookmarks()
  local structure = app.getDocumentStructure()
  local numPages = #structure.pages
  if numPages == 0 then
    show_msg("Document has no pages.", false)
    return
  end

  local bookmarks = model.collect(structure)
  if #bookmarks == 0 then
    show_msg("No bookmarks exist in this document.", false)
    return
  end

  -- 1. Get the selected bookmark
  local oldPage, oldLayerID
  if IS_WINDOWS then
    -- Windows (ncruces zenity): single column only; paginated for cmd.exe's length limit
    local items = {}
    for i, b in ipairs(bookmarks) do
      items[i] = string.format("[%d_%d] Page %d: %s", b.page, b.layer, b.page, model.display_title(b.title))
    end
    local idx = ui.choose("Bookmark Manager", "Select a bookmark to manage:", "Bookmarks", items,
      {width = 500, height = 400})
    if not idx then return end -- Cancelled
    oldPage, oldLayerID = bookmarks[idx].page, bookmarks[idx].layer
  else
    -- Linux: multi-column list with a hidden ID column
    local argv = {"zenity", "--list", "--title=Bookmark Manager", "--width=500", "--height=400",
      "--text=Select a bookmark to manage:", "--column=ID", "--column=Page", "--column=Name", "--hide-column=1"}
    for _, b in ipairs(bookmarks) do
      table.insert(argv, b.page .. "_" .. b.layer)
      table.insert(argv, tostring(b.page))
      table.insert(argv, model.display_title(b.title))
    end
    local selected_id = platform.run_zenity(argv)
    if not selected_id or selected_id == "" then return end -- Cancelled
    oldPage, oldLayerID = parse_bookmark_id(selected_id)
    if not oldPage or not oldLayerID then return end
  end

  local targetLayer = structure.pages[oldPage] and structure.pages[oldPage].layers[oldLayerID]
  local oldName = targetLayer and model.title_of(targetLayer.name) or ""

  -- 2. Ask what to do with it
  local actions = {"Jump To", "Edit", "Delete"}
  -- The name goes into the window title: zenity parses --text as Pango
  -- markup (GNOME) or shows it raw (ncruces), so no escaping fits both.
  local actionIdx = ui.choose("Bookmark: " .. model.display_title(oldName), "Choose an action:", "Action", actions)
  if not actionIdx then return end -- Cancelled
  local action = actions[actionIdx]

  if action == "Jump To" then
    app.setCurrentPage(oldPage)
    app.scrollToPage(oldPage)
  elseif action == "Delete" then
    doc.delete_bookmark(oldPage, oldLayerID)
  elseif action == "Edit" then
    local newPage, newName = edit_bookmark_zenity("Edit Bookmark", oldPage, oldName, numPages)
    if newPage ~= nil then
      newName = newName:gsub("[\r\n]", " ")
      if oldPage == newPage then
        doc.rename_bookmark(oldPage, oldLayerID, newName)
      else
        doc.delete_bookmark(oldPage, oldLayerID)
        doc.add_bookmark(newPage, newName)
        app.setCurrentPage(newPage)
        app.scrollToPage(newPage)
      end
    end
  end
end

-- Backward compatibility alias in case old UI / shortcuts reference "export"
function export()
  export_with_bookmarks()
end

function export_with_bookmarks()
  if not platform.execute({"pdftk", "--version"}) then
    show_msg("pdftk is missing or not in system PATH.", true)
    return
  end

  local structure = app.getDocumentStructure()

  local defaultName = DEFAULT_EXPORT_PATH
  local xopp_name = structure.xoppFilename
  if xopp_name ~= nil and xopp_name ~= "" then
    local base = xopp_name:match("(.+)%..+$")
    if base and base ~= "" then
      defaultName = base
    end
  end
  defaultName = defaultName .. "_export.pdf"

  doc.save_dialog("bookmarks_export_to", defaultName)
end

-- Second half of the export, called with the path chosen in the save dialog.
function bookmarks_export_to(path)
  if not path or path == "" then return end -- Cancelled
  local structure = app.getDocumentStructure()

  -- Export the base PDF from Xournal++ into a temporary file
  local tempPdf = platform.temp_path(".pdf")
  app.export({outputFile = tempPdf})
  if not platform.file_size(tempPdf) or platform.file_size(tempPdf) == 0 then
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
  if existing > 0 and #bookmarks > 0 then
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
