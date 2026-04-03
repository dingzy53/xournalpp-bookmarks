utf8_to_html = require("utf8_to_html")

DEFAULT_EXPORT_PATH = "/tmp/temp"

-- Helper to safely escape strings for bash commands
function bash_escape(str)
  if not str then return "''" end
  return "'" .. string.gsub(str, "'", "'\\''") .. "'"
end

-- Helper to run zenity and cleanly handle user cancellations
function run_zenity(cmd)
  local handle = io.popen(cmd)
  local result = handle:read("*a")
  local success = handle:close()
  if result then result = string.gsub(result, "\n", "") end
  -- If not successful (e.g., Cancel clicked) and no text returned, return nil
  if not success and result == "" then return nil end
  return result
end

-- Register Toolbar
function initUi()
  app.registerUi({menu="Previous Bookmark", toolbarId="CUSTOM_PREVIOUS_BOOKMARK", callback="search_bookmark", mode=-1, iconName="go-previous"})
  app.registerUi({menu="New Bookmark", toolbarId="CUSTOM_NEW_BOOKMARK", callback="dialog_new_bookmark", iconName="bookmark-new-symbolic"})
  app.registerUi({menu="New Bookmark (No dialog)", toolbarId="CUSTOM_NEW_BOOKMARK_NO_DIALOG", callback="new_bookmark", iconName="bookmark-new-symbolic"})
  app.registerUi({menu="Next Bookmark", toolbarId="CUSTOM_NEXT_BOOKMARK", callback="search_bookmark", mode=1, iconName="go-next"})
  app.registerUi({menu="View Bookmarks", toolbarId="CUSTOM_VIEW_BOOKMARKS", callback = "view_bookmarks", iconName="user-bookmarks-symbolic"})
  app.registerUi({menu="Export to PDF with Bookmarks", toolbarId="CUSTOM_EXPORT_WITH_BOOKMARKS", callback="export", iconName="xopp-document-export-pdf"})

  sep = package.config:sub(1,1)
  sourcePath = debug.getinfo(1).source:match("@?(.*" .. sep .. ")")
  if sep == "\\" then
    DEFAULT_EXPORT_PATH = "%TEMP%\\temp"
  end
end

function new_bookmark(name)
  local structure = app.getDocumentStructure()
  local currentPage = structure.currentPage
  local currentLayerID = structure.pages[currentPage].currentLayer

  app.layerAction("ACTION_NEW_LAYER")
  if type(name) == "string" then
    app.setCurrentLayerName("Bookmark::" .. name)
  else
    app.setCurrentLayerName("Bookmark::")
  end
  app.setLayerVisibility(false)
  app.setCurrentLayer(currentLayerID)
end

function delete_layer(page, layerID)
  local structure = app.getDocumentStructure()

  app.setCurrentPage(page)
  local currentLayerID = structure.pages[page].currentLayer
  app.setCurrentLayer(layerID)
  app.layerAction("ACTION_DELETE_LAYER")
  if currentLayerID > layerID then
    app.setCurrentLayer(currentLayerID - 1)
  else
    app.setCurrentLayer(currentLayerID)
  end
end

-- mode = -1 for searching backwards, or 1 for searching forwards
function search_bookmark(mode)
  local structure = app.getDocumentStructure()
  local currentPage = structure.currentPage
  local numPages = #structure.pages
  local page = currentPage
  local nextBookmark

  repeat
    page = page + mode
    if page == numPages + 1 then page = 1 end
    if page == 0 then page = numPages end
    for u,v in pairs(structure.pages[page].layers) do
      if v.name:sub(1,10) == "Bookmark::" then
        nextBookmark = page
        break
      end
    end
    if nextBookmark ~= nil then break end
  until page == currentPage

  if nextBookmark == nil then
    app.msgbox("No bookmark found.", {[1] = "Ok"})
    return
  end

  app.setCurrentPage(nextBookmark)
  app.scrollToPage(nextBookmark)
end

function dialog_new_bookmark()
  local cmd = 'zenity --entry --title="New Bookmark" --text="Enter bookmark name:"'
  local name = run_zenity(cmd)
  
  -- If the user didn't hit cancel
  if name ~= nil then
    new_bookmark(name)
  end
end

function view_bookmarks()
  local structure = app.getDocumentStructure()
  local numPages = #structure.pages
  
  local cmd = 'zenity --list --title="Bookmark Manager" --width=500 --height=400 --text="Select a bookmark to manage:" --column="ID" --column="Page" --column="Name" --hide-column=1'
  local hasBookmarks = false

  for page=1, numPages do
    for u,v in pairs(structure.pages[page].layers) do
      if v.name:sub(1,10) == "Bookmark::" then
        hasBookmarks = true
        local display_name = v.name:sub(11)
        if display_name == "" then display_name = "(No name)" end
        
        -- ID is formatted as "Page_LayerID" so we know exactly which one to modify
        local unique_id = tostring(page) .. "_" .. tostring(u)
        cmd = cmd .. string.format(" %s %s %s", bash_escape(unique_id), bash_escape(tostring(page)), bash_escape(display_name))
      end
    end
  end

  if not hasBookmarks then
    app.msgbox("No bookmarks exist in this document.", {[1]="OK"})
    return
  end

  -- 1. Get the selected bookmark
  local selected_id = run_zenity(cmd)
  if selected_id == nil or selected_id == "" then return end -- Cancelled

  local page_str, layer_str = selected_id:match("(%d+)_(%d+)")
  local oldPage = tonumber(page_str)
  local oldLayerID = tonumber(layer_str)

  -- Get old name directly from structure
  local oldName = ""
  for u,v in pairs(structure.pages[oldPage].layers) do
    if u == oldLayerID then
      oldName = v.name:sub(11)
      break
    end
  end

  -- 2. Ask what to do with it
  local action_cmd = 'zenity --list --title="Bookmark Action" --text="Action for: ' .. bash_escape(oldName) .. '" --column="Action" "Jump To" "Edit" "Delete"'
  local action = run_zenity(action_cmd)

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
        app.setCurrentLayerName("Bookmark::" .. newName)
        app.setCurrentLayer(currentLayerID)
      else
        delete_layer(oldPage, oldLayerID)
        app.setCurrentPage(newPage)
        new_bookmark(newName)
      end
    end
  end
end

-- Replaces the LGI edit_bookmark function
function edit_bookmark_zenity(title, defaultPage, defaultName, numPages)
  -- Ask for Page (pre-filled)
  local page_cmd = string.format('zenity --entry --title=%s --text="Page Number (1-%d):" --entry-text=%s', bash_escape(title), numPages, bash_escape(tostring(defaultPage)))
  local newPageStr = run_zenity(page_cmd)
  if newPageStr == nil then return nil end -- Cancelled
  
  local newPage = tonumber(newPageStr)
  if not newPage or newPage < 1 or newPage > numPages then
    os.execute('zenity --error --text="Invalid page number. Edit cancelled."')
    return nil
  end

  -- Ask for Name (pre-filled)
  local name_cmd = string.format('zenity --entry --title=%s --text="Bookmark Name:" --entry-text=%s', bash_escape(title), bash_escape(defaultName))
  local newName = run_zenity(name_cmd)
  if newName == nil then return nil end -- Cancelled

  return newPage, newName
end

function export()
  if not os.execute("pdftk --version > /dev/null 2>&1") then
    app.msgbox("pdftk is missing.", {[1] = "OK"})
    return
  end
  local structure = app.getDocumentStructure()

  local defaultName = DEFAULT_EXPORT_PATH
  local xopp_name = structure.xoppFilename
  if xopp_name ~= nil and xopp_name ~= "" then
    defaultName = xopp_name:match("(.+)%..+$")
  end
  defaultName = defaultName .. "_export.pdf"
  local path = app.saveAs(defaultName)
  if path == nil then return end

  local tempData = os.tmpname()
  if sep == "\\" then tempData = tempData:sub(2) end 
  local tempPdf = tempData .. "_1337__.pdf" 

  app.export({outputFile = tempPdf})

  os.execute("pdftk \"" .. tempPdf .. "\" dump_data output \"" .. tempData .. "\"")

  local file = io.open(tempData,"a+")
  local bookmarkTable = {}
  local numPages = #structure.pages
  for page=1, numPages do
    for u,v in pairs(structure.pages[page].layers) do
      if v.name:sub(1,10) == "Bookmark::" then
        table.insert(bookmarkTable,{page = page, name = utf8_to_html(v.name:sub(11))})
      end
    end
  end
  for u, bookmark in pairs(bookmarkTable) do
    file:write("BookmarkBegin\n")
    file:write("BookmarkTitle: " .. bookmark.name .. "\n")
    file:write("BookmarkLevel: 1\n")
    file:write("BookmarkPageNumber: " .. bookmark.page .. "\n")
  end
  file:close()

  os.execute("pdftk \"" .. tempPdf .. "\" update_info \"" .. tempData .. "\" output \"" .. path .."\"")

  os.remove(tempData)
  os.remove(tempPdf)
end
