-- Adapter around the Xournal++ `app` API. Uses current API calls where
-- available (Xournal++ >= 1.3) and falls back to the deprecated ones that
-- are scheduled for removal with the GTK4 port (1.2.x only has those).
local M = {}

local function action(new_name, old_name)
  if app.activateAction then
    app.activateAction(new_name)
  else
    app.layerAction(old_name)
  end
end

-- Insert a new layer above the current one and select it.
function M.new_layer_above_current()
  action("layer-new-above-current", "ACTION_NEW_LAYER")
end

-- Delete the current layer.
function M.delete_current_layer()
  action("layer-delete", "ACTION_DELETE_LAYER")
end

local model = require("bm_model")

local function layer_count(structure, page)
  local info = structure.pages[page]
  return info and #info.layers or 0
end

-- app.setCurrentLayer raises a Lua error for an out-of-range index, which
-- would abort the whole callback. Clamp to the current page and guard it.
local function set_layer(id)
  local s = app.getDocumentStructure()
  local n = layer_count(s, s.currentPage)
  if id > n then id = n end
  if id < 0 then id = 0 end
  return pcall(app.setCurrentLayer, id)
end

-- Run fn() on `page` and restore the user's page afterwards. fn receives
-- the layer that was selected on `page` and returns the layer to select
-- there when done (or nil to leave it as fn left it).
local function on_page(page, fn)
  local s = app.getDocumentStructure()
  if not s.pages[page] then return false end
  local origPage = s.currentPage
  app.setCurrentPage(page)
  local restore = fn(s.pages[page].currentLayer)
  if restore then set_layer(restore) end
  if origPage ~= page then app.setCurrentPage(origPage) end
  return true
end

-- Add a hidden bookmark layer on `page`. It is placed on top of the page's
-- layers, so bookmarks on one page keep the order in which they were
-- created (inserting above the *current* layer made the order depend on
-- which layer happened to be selected).
function M.add_bookmark(page, title, level)
  return on_page(page, function(current)
    local s = app.getDocumentStructure()
    set_layer(layer_count(s, page))
    M.new_layer_above_current()
    app.setCurrentLayerName(model.layer_name(title, level))
    app.setLayerVisibility(false)
    return current -- below the new layer, so its index is unchanged
  end)
end

-- Select exactly `layer` on the current page, only if it is a bookmark layer.
-- Never clamps: acting on a neighbouring layer would destroy user content.
local function select_bookmark_layer(page, layer)
  local info = app.getDocumentStructure().pages[page]
  local l = info and info.layers[layer]
  if layer < 1 or not l or not model.title_of(l.name) then return false end
  return pcall(app.setCurrentLayer, layer)
end

function M.rename_bookmark(page, layer, title, level)
  return on_page(page, function(current)
    if not select_bookmark_layer(page, layer) then return current end
    app.setCurrentLayerName(model.layer_name(title, level))
    return current
  end)
end

function M.delete_bookmark(page, layer)
  return on_page(page, function(current)
    if not select_bookmark_layer(page, layer) then return current end
    M.delete_current_layer()
    -- layers above the deleted one move down by one
    if current >= layer then current = math.max(current - 1, 1) end
    return current
  end)
end

-- Delete several bookmarks. Highest (page, layer) first, because deleting
-- a layer renumbers the layers above it.
function M.delete_bookmarks(list)
  local sorted = {}
  for i, b in ipairs(list) do sorted[i] = b end
  table.sort(sorted, function(a, b)
    if a.page ~= b.page then return a.page > b.page end
    return a.layer > b.layer
  end)
  for _, b in ipairs(sorted) do M.delete_bookmark(b.page, b.layer) end
end

-- Message box. Falls back to app.msgbox on Xournal++ 1.2.
function M.message(msg, is_error)
  if app.openDialog then
    app.openDialog(msg, {"OK"}, "", is_error or false)
  elseif app.msgbox then
    app.msgbox(msg, {[1] = "OK"})
  end
end

-- "Save as" dialog. Calls the global function named `callback` with the
-- chosen path ("" when cancelled). app.fileDialogSave is asynchronous; the
-- deprecated blocking app.saveAs is used on Xournal++ 1.2.
function M.save_dialog(callback, suggested)
  if app.fileDialogSave then
    app.fileDialogSave(callback, suggested)
  else
    local path = app.saveAs(suggested)
    _G[callback](path or "")
  end
end

return M
