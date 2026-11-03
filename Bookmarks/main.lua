local utf8_to_html = require("utf8_to_html")
local platform = require("bm_platform")
local model = require("bm_model")

local IS_WINDOWS = platform.IS_WINDOWS

-- Default export path suggestion
local DEFAULT_EXPORT_PATH = IS_WINDOWS and ((os.getenv("TEMP") or "C:\\Temp") .. "\\temp") or "/tmp/temp"

-- Wrapper for message dialogs (compatible across Xournal++ versions and platforms)
local function show_msg(msg, is_error)
  if app.openDialog then
    app.openDialog(msg, {"OK"}, "", is_error or false)
  elseif app.msgbox then
    app.msgbox(msg, {[1] = "OK"})
  else
    platform.execute({"zenity", is_error and "--error" or "--info", "--text=" .. msg})
  end
end

-- Helper to parse unique bookmark ID from zenity output
local function parse_bookmark_id(selected_id)
  if not selected_id or selected_id == "" then return nil, nil end
  -- Windows format: "[P_L] Page P: Name"
  local p, l = selected_id:match("%[(%d+)_(%d+)%]")
  if not p then
    -- Linux format: "P_L"
    p, l = selected_id:match("^(%d+)_(%d+)$")
  end
  if not p then
    -- Generic fallback
    p, l = selected_id:match("(%d+)_(%d+)")
  end
  return tonumber(p), tonumber(l)
end

-- Delete a specific layer on a page safely
local function delete_layer(page, layerID)
  local structure = app.getDocumentStructure()
  local origPage = structure.currentPage
  local pageInfo = structure.pages[page]
  if not pageInfo then return end

  local currentLayerID = pageInfo.currentLayer
  local numLayers = #pageInfo.layers

  app.setCurrentPage(page)
  app.setCurrentLayer(layerID)
  app.layerAction("ACTION_DELETE_LAYER")

  -- Restore active layer safely:
  -- If deleted layer was active or above, shift active index down
  local remainingLayers = numLayers - 1
  if remainingLayers >= 1 then
    local targetLayer = (currentLayerID >= layerID) and (currentLayerID - 1) or currentLayerID
    if targetLayer < 1 then targetLayer = 1 end
    if targetLayer > remainingLayers then targetLayer = remainingLayers end
    app.setCurrentLayer(targetLayer)
  end

  -- Restore original page if different
  if origPage ~= page then
    app.setCurrentPage(origPage)
  end
end

local function edit_bookmark_zenity(title, defaultPage, defaultName, numPages)
  local newPageStr = platform.run_zenity({"zenity", "--entry", "--title=" .. title,
    "--text=Page Number (1-" .. numPages .. "):", "--entry-text=" .. tostring(defaultPage)})
  if newPageStr == nil then return nil end -- Cancelled

  local newPage = tonumber(newPageStr)
  if not newPage or newPage < 1 or newPage > numPages then
    show_msg("Invalid page number. Edit cancelled.", true)
    return nil
  end

  local newName = platform.run_zenity({"zenity", "--entry", "--title=" .. title,
    "--text=Bookmark Name:", "--entry-text=" .. defaultName})
  if newName == nil then return nil end -- Cancelled

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
  local structure = app.getDocumentStructure()
  local currentPage = structure.currentPage
  local currentLayerID = structure.pages[currentPage].currentLayer

  app.layerAction("ACTION_NEW_LAYER")
  if type(name) == "string" and name ~= "" then
    -- Strip any newlines that would break pdftk syntax
    app.setCurrentLayerName(model.layer_name((name:gsub("[\r\n]", " "))))
  else
    app.setCurrentLayerName(model.layer_name(""))
  end
  app.setLayerVisibility(false)
  app.setCurrentLayer(currentLayerID)
end

function dialog_new_bookmark()
  local name = platform.run_zenity({"zenity", "--entry", "--title=New Bookmark", "--text=Enter bookmark name:"})
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

  local argv = {"zenity", "--list", "--title=Bookmark Manager", "--width=500", "--height=400",
    "--text=Select a bookmark to manage:"}
  if IS_WINDOWS then
    -- Windows: single-column list with combined text
    table.insert(argv, "--column=Bookmarks")
    for _, b in ipairs(bookmarks) do
      local unique_id = b.page .. "_" .. b.layer
      table.insert(argv, string.format("[%s] Page %d: %s", unique_id, b.page, model.display_title(b.title)))
    end
  else
    -- Linux: multi-column list
    for _, a in ipairs({"--column=ID", "--column=Page", "--column=Name", "--hide-column=1"}) do
      table.insert(argv, a)
    end
    for _, b in ipairs(bookmarks) do
      table.insert(argv, b.page .. "_" .. b.layer)
      table.insert(argv, tostring(b.page))
      table.insert(argv, model.display_title(b.title))
    end
  end

  -- 1. Get the selected bookmark
  local selected_id = platform.run_zenity(argv)
  if not selected_id or selected_id == "" then return end -- Cancelled

  local oldPage, oldLayerID = parse_bookmark_id(selected_id)
  if not oldPage or not oldLayerID then return end

  local targetLayer = structure.pages[oldPage] and structure.pages[oldPage].layers[oldLayerID]
  local oldName = targetLayer and model.title_of(targetLayer.name) or ""

  -- 2. Ask what to do with it
  local action = platform.run_zenity({"zenity", "--list", "--title=Bookmark Action",
    "--text=Action for: " .. model.display_title(oldName), "--column=Action", "Jump To", "Edit", "Delete"})
  if not action or action == "" then return end -- Cancelled

  if action == "Jump To" then
    app.setCurrentPage(oldPage)
    app.scrollToPage(oldPage)
  elseif action == "Delete" then
    delete_layer(oldPage, oldLayerID)
  elseif action == "Edit" then
    local newPage, newName = edit_bookmark_zenity("Edit Bookmark", oldPage, oldName, numPages)
    if newPage ~= nil then
      if oldPage == newPage then
        app.setCurrentPage(oldPage)
        local currentLayerID = structure.pages[oldPage].currentLayer
        app.setCurrentLayer(oldLayerID)
        app.setCurrentLayerName(model.layer_name(newName))
        app.setCurrentLayer(currentLayerID)
      else
        delete_layer(oldPage, oldLayerID)
        app.setCurrentPage(newPage)
        new_bookmark(newName)
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
  if not platform.execute({"pdftk", "--version"}, true) then
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

  local path = app.saveAs(defaultName)
  if not path or path == "" then return end -- Cancelled

  -- Determine safe temporary files in system temp directory
  local tempDir = IS_WINDOWS and (os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp") or (os.getenv("TMPDIR") or "/tmp")
  local tempBase = os.tmpname()
  if IS_WINDOWS then
    local fname = tempBase:match("[^\\]+$") or tempBase:sub(2)
    tempBase = tempDir .. "\\" .. fname
  end
  local tempData = tempBase .. ".txt"
  local tempPdf = tempBase .. "_1337__.pdf"

  -- Export base PDF from Xournal++
  app.export({outputFile = tempPdf})

  -- Dump existing PDF metadata
  if not platform.execute({"pdftk", tempPdf, "dump_data", "output", tempData}) then
    os.remove(tempPdf)
    os.remove(tempData)
    show_msg("Failed to dump PDF metadata with pdftk.", true)
    return
  end

  local file = io.open(tempData, "a+")
  if not file then
    os.remove(tempPdf)
    os.remove(tempData)
    show_msg("Failed to open temporary metadata file.", true)
    return
  end

  for _, b in ipairs(model.collect(structure)) do
    file:write("BookmarkBegin\n")
    file:write("BookmarkTitle: " .. utf8_to_html(b.title) .. "\n")
    file:write("BookmarkLevel: 1\n")
    file:write("BookmarkPageNumber: " .. b.page .. "\n")
  end
  file:close()

  -- Update PDF with new bookmarks
  local updateOk = platform.execute({"pdftk", tempPdf, "update_info", tempData, "output", path})

  -- Cleanup temporary files
  os.remove(tempData)
  os.remove(tempPdf)

  if not updateOk then
    show_msg("Failed to create PDF with bookmarks using pdftk.", true)
  else
    show_msg("Successfully exported PDF with bookmarks:\n" .. path, false)
  end
end
