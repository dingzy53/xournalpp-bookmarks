local utf8_to_html = require("utf8_to_html")

-- Detect OS: "\\" = Windows, "/" = Linux/Mac
local IS_WINDOWS = (package.config:sub(1,1) == "\\")

-- Default export path suggestion
local DEFAULT_EXPORT_PATH = IS_WINDOWS and ((os.getenv("TEMP") or "C:\\Temp") .. "\\temp") or "/tmp/temp"

-- Helper to safely escape strings for shell commands (Bash or Windows cmd)
local function sh_escape(str)
  str = tostring(str or "")
  if IS_WINDOWS then
    -- Windows cmd: double quotes; escape inner double quotes
    return '"' .. string.gsub(str, '"', '\\"') .. '"'
  else
    -- POSIX shell: single quotes; escape inner single quotes
    return "'" .. string.gsub(str, "'", "'\\''") .. "'"
  end
end

-- Helper to run zenity and cleanly handle user cancellations
local function run_zenity(cmd)
  if IS_WINDOWS then
    cmd = cmd .. " 2>&1"
  end
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  local success = handle:close()

  if not result then return nil end
  -- Strip both \r and \n so Windows CRLF does not break string equality comparisons
  result = string.gsub(result, "[\r\n]", "")

  if IS_WINDOWS then
    if result == "" then return nil end
  else
    -- If not successful (e.g., Cancel clicked) and no text returned, return nil
    if not success and result == "" then return nil end
  end
  return result
end

-- Wrapper for message dialogs (compatible across Xournal++ versions and platforms)
local function show_msg(msg, is_error)
  if app.openDialog then
    app.openDialog(msg, {"OK"}, "", is_error or false)
  elseif app.msgbox then
    app.msgbox(msg, {[1] = "OK"})
  else
    local flag = is_error and "--error" or "--info"
    os.execute(string.format("zenity %s --text=%s", flag, sh_escape(msg)))
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

-- Replaces the LGI edit_bookmark function using Zenity
local function edit_bookmark_zenity(title, defaultPage, defaultName, numPages)
  -- Ask for Page (pre-filled)
  local page_cmd = string.format('zenity --entry --title=%s --text="Page Number (1-%d):" --entry-text=%s',
    sh_escape(title), numPages, sh_escape(tostring(defaultPage)))
  local newPageStr = run_zenity(page_cmd)
  if newPageStr == nil then return nil end -- Cancelled

  local newPage = tonumber(newPageStr)
  if not newPage or newPage < 1 or newPage > numPages then
    show_msg("Invalid page number. Edit cancelled.", true)
    return nil
  end

  -- Ask for Name (pre-filled)
  local name_cmd = string.format('zenity --entry --title=%s --text="Bookmark Name:" --entry-text=%s',
    sh_escape(title), sh_escape(defaultName))
  local newName = run_zenity(name_cmd)
  if newName == nil then return nil end -- Cancelled

  return newPage, newName
end

--------------------------------------------------------------------------------
-- Public Plugin Callbacks (Registered with Xournal++)
--------------------------------------------------------------------------------

-- Register Toolbar & Menu
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
    local cleanName = name:gsub("[\r\n]", " ")
    app.setCurrentLayerName("Bookmark::" .. cleanName)
  else
    app.setCurrentLayerName("Bookmark::")
  end
  app.setLayerVisibility(false)
  app.setCurrentLayer(currentLayerID)
end

function dialog_new_bookmark()
  local cmd = 'zenity --entry --title="New Bookmark" --text="Enter bookmark name:"'
  local name = run_zenity(cmd)

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

    local layers = structure.pages[page].layers
    for u, v in pairs(layers) do
      if v and v.name and v.name:sub(1, 10) == "Bookmark::" then
        nextBookmark = page
        break
      end
    end
    if nextBookmark ~= nil then break end
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

  local cmd, hasBookmarks

  if IS_WINDOWS then
    -- Windows: single-column list with combined text
    cmd = 'zenity --list --title="Bookmark Manager" --width=500 --height=400 --text="Select a bookmark to manage:" --column="Bookmarks"'
    hasBookmarks = false

    for page = 1, numPages do
      local bookmarkLayers = {}
      for u, v in pairs(structure.pages[page].layers) do
        if type(u) == "number" and v and v.name and v.name:sub(1, 10) == "Bookmark::" then
          table.insert(bookmarkLayers, {id = u, layer = v})
        end
      end
      table.sort(bookmarkLayers, function(a, b) return a.id < b.id end)

      for _, item in ipairs(bookmarkLayers) do
        hasBookmarks = true
        local display_name = item.layer.name:sub(11)
        if display_name == "" then display_name = "(No name)" end

        local unique_id = tostring(page) .. "_" .. tostring(item.id)
        local combined_text = string.format("[%s] Page %s: %s", unique_id, tostring(page), display_name)
        cmd = cmd .. " " .. sh_escape(combined_text)
      end
    end
  else
    -- Linux: multi-column list
    cmd = 'zenity --list --title="Bookmark Manager" --width=500 --height=400 --text="Select a bookmark to manage:" --column="ID" --column="Page" --column="Name" --hide-column=1'
    hasBookmarks = false

    for page = 1, numPages do
      local bookmarkLayers = {}
      for u, v in pairs(structure.pages[page].layers) do
        if type(u) == "number" and v and v.name and v.name:sub(1, 10) == "Bookmark::" then
          table.insert(bookmarkLayers, {id = u, layer = v})
        end
      end
      table.sort(bookmarkLayers, function(a, b) return a.id < b.id end)

      for _, item in ipairs(bookmarkLayers) do
        hasBookmarks = true
        local display_name = item.layer.name:sub(11)
        if display_name == "" then display_name = "(No name)" end

        local unique_id = tostring(page) .. "_" .. tostring(item.id)
        cmd = cmd .. string.format(" %s %s %s", sh_escape(unique_id), sh_escape(tostring(page)), sh_escape(display_name))
      end
    end
  end

  if not hasBookmarks then
    show_msg("No bookmarks exist in this document.", false)
    return
  end

  -- 1. Get the selected bookmark
  local selected_id = run_zenity(cmd)
  if not selected_id or selected_id == "" then return end -- Cancelled

  local oldPage, oldLayerID = parse_bookmark_id(selected_id)
  if not oldPage or not oldLayerID then return end

  -- Get old name directly from structure
  local oldName = ""
  local targetLayer = structure.pages[oldPage] and structure.pages[oldPage].layers[oldLayerID]
  if targetLayer and targetLayer.name then
    oldName = targetLayer.name:sub(11)
  end

  -- 2. Ask what to do with it
  local action_prompt = "Action for: " .. (oldName ~= "" and oldName or "(No name)")
  local action_cmd = string.format('zenity --list --title="Bookmark Action" --text=%s --column="Action" "Jump To" "Edit" "Delete"',
    sh_escape(action_prompt))
  local action = run_zenity(action_cmd)
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
        app.setCurrentLayerName("Bookmark::" .. (newName or ""))
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
  -- Detect OS to use the correct null device for PATH check
  local null_device = IS_WINDOWS and "NUL" or "/dev/null"
  if not os.execute("pdftk --version > " .. null_device .. " 2>&1") then
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
  local dumpCmd = string.format("pdftk %s dump_data output %s", sh_escape(tempPdf), sh_escape(tempData))
  local dumpOk = os.execute(dumpCmd)
  if not dumpOk then
    os.remove(tempPdf)
    os.remove(tempData)
    show_msg("Failed to dump PDF metadata with pdftk.", true)
    return
  end

  -- Collect bookmarks in page and layer order
  local bookmarkTable = {}
  local numPages = #structure.pages
  for page = 1, numPages do
    local bookmarkLayers = {}
    for u, v in pairs(structure.pages[page].layers) do
      if type(u) == "number" and v and v.name and v.name:sub(1, 10) == "Bookmark::" then
        table.insert(bookmarkLayers, {id = u, layer = v})
      end
    end
    table.sort(bookmarkLayers, function(a, b) return a.id < b.id end)

    for _, item in ipairs(bookmarkLayers) do
      local rawName = item.layer.name:sub(11)
      table.insert(bookmarkTable, {page = page, name = utf8_to_html(rawName)})
    end
  end

  -- Append bookmarks to dump_data file
  local file = io.open(tempData, "a+")
  if not file then
    os.remove(tempPdf)
    os.remove(tempData)
    show_msg("Failed to open temporary metadata file.", true)
    return
  end

  for _, bookmark in ipairs(bookmarkTable) do
    file:write("BookmarkBegin\n")
    file:write("BookmarkTitle: " .. bookmark.name .. "\n")
    file:write("BookmarkLevel: 1\n")
    file:write("BookmarkPageNumber: " .. bookmark.page .. "\n")
  end
  file:close()

  -- Update PDF with new bookmarks
  local updateCmd = string.format("pdftk %s update_info %s output %s",
    sh_escape(tempPdf), sh_escape(tempData), sh_escape(path))
  local updateOk = os.execute(updateCmd)

  -- Cleanup temporary files
  os.remove(tempData)
  os.remove(tempPdf)

  if not updateOk then
    show_msg("Failed to create PDF with bookmarks using pdftk.", true)
  else
    show_msg("Successfully exported PDF with bookmarks:\n" .. path, false)
  end
end
