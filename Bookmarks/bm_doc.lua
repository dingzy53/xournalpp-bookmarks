-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2024-2025 Javier Reyes and contributors (original Bookmarks plugin)
-- Copyright (C) 2026 Ding Zheng Yuan (zenity port and later changes)
-- Modified by Ding Zheng Yuan in 2026; see README.md and the git history.
--
-- Adapter around the Xournal++ 1.3+ `app` Lua API.
local model = require("bm_model")

local M = {}

function M.new_layer_above_current()
  app.activateAction("layer-new-above-current")
end

function M.delete_current_layer()
  app.activateAction("layer-delete")
end

local function set_layer_clamped(id, max_layer)
  if id > max_layer then id = max_layer end
  if id < 0 then id = 0 end
  return pcall(app.setCurrentLayer, id)
end

local function sorted_pages(by_page, descending)
  local pages = {}
  for page in pairs(by_page) do pages[#pages + 1] = page end
  table.sort(pages, descending and function(a, b) return a > b end or nil)
  return pages
end

-- Add one or more bookmarks ({page, title, level}) in a single document scan,
-- preserving each visited page's active layer and the user's current page.
function M.add_bookmarks(entries)
  if #entries == 0 then return 0 end
  local s = app.getDocumentStructure()
  local by_page = {}
  for _, e in ipairs(entries) do
    if s.pages[e.page] then
      local bucket = by_page[e.page]
      if not bucket then
        bucket = {}
        by_page[e.page] = bucket
      end
      bucket[#bucket + 1] = e
    end
  end

  local orig_page = s.currentPage
  local cur_page = orig_page
  local added = 0
  for _, page in ipairs(sorted_pages(by_page, false)) do
    local info = s.pages[page]
    local orig_layer = info.currentLayer
    local list = by_page[page]
    if cur_page ~= page then
      app.setCurrentPage(page)
      cur_page = page
    end
    set_layer_clamped(#info.layers, #info.layers)
    for _, e in ipairs(list) do
      M.new_layer_above_current()
      app.setCurrentLayerName(model.layer_name(e.title, e.level))
      app.setLayerVisibility(false)
      added = added + 1
    end
    set_layer_clamped(orig_layer, #info.layers + #list)
  end
  if cur_page ~= orig_page then app.setCurrentPage(orig_page) end
  return added
end

-- Add a hidden bookmark layer on top of `page`.
function M.add_bookmark(page, title, level)
  return M.add_bookmarks({{page = page, title = title, level = level}}) > 0
end

local function is_bookmark_layer(info, layer)
  local l = info and info.layers[layer]
  return layer >= 1 and l ~= nil and model.title_of(l.name) ~= nil
end

-- Rename one or more bookmark layers ({page, layer, title, level}) in one scan.
function M.rename_bookmarks(edits)
  if #edits == 0 then return 0 end
  local s = app.getDocumentStructure()
  local by_page = {}
  for _, e in ipairs(edits) do
    local info = s.pages[e.page]
    if is_bookmark_layer(info, e.layer) then
      local bucket = by_page[e.page]
      if not bucket then
        bucket = {}
        by_page[e.page] = bucket
      end
      bucket[#bucket + 1] = e
    end
  end

  local orig_page = s.currentPage
  local cur_page = orig_page
  local renamed = 0
  for _, page in ipairs(sorted_pages(by_page, false)) do
    local info = s.pages[page]
    local orig_layer = info.currentLayer
    if cur_page ~= page then
      app.setCurrentPage(page)
      cur_page = page
    end
    for _, e in ipairs(by_page[page]) do
      if pcall(app.setCurrentLayer, e.layer) then
        app.setCurrentLayerName(model.layer_name(e.title, e.level))
        renamed = renamed + 1
      end
    end
    set_layer_clamped(orig_layer, #info.layers)
  end
  if cur_page ~= orig_page then app.setCurrentPage(orig_page) end
  return renamed
end

function M.rename_bookmark(page, layer, title, level)
  return M.rename_bookmarks({{page = page, layer = layer, title = title, level = level}}) > 0
end

-- Delete several bookmarks ({page, layer}). Highest (page, layer) first, because
-- deleting a layer renumbers the layers above it.
function M.delete_bookmarks(list)
  if #list == 0 then return false end
  local s = app.getDocumentStructure()
  local by_page, seen = {}, {}
  for _, b in ipairs(list) do
    local info = s.pages[b.page]
    local key = b.page .. ":" .. b.layer
    if not seen[key] and is_bookmark_layer(info, b.layer) then
      seen[key] = true
      local bucket = by_page[b.page]
      if not bucket then
        bucket = {}
        by_page[b.page] = bucket
      end
      bucket[#bucket + 1] = b.layer
    end
  end

  local orig_page = s.currentPage
  local cur_page = orig_page
  local deleted = false
  for _, page in ipairs(sorted_pages(by_page, true)) do
    local layers = by_page[page]
    table.sort(layers, function(a, b) return a > b end)
    local info = s.pages[page]
    local current = info.currentLayer
    local remaining = #info.layers
    if cur_page ~= page then
      app.setCurrentPage(page)
      cur_page = page
    end
    for _, layer in ipairs(layers) do
      if pcall(app.setCurrentLayer, layer) then
        M.delete_current_layer()
        deleted = true
        if current >= layer then current = math.max(current - 1, 1) end
        remaining = math.max(remaining - 1, 1)
      end
    end
    set_layer_clamped(current, remaining)
  end
  if cur_page ~= orig_page then app.setCurrentPage(orig_page) end
  return deleted
end

function M.delete_bookmark(page, layer)
  return M.delete_bookmarks({{page = page, layer = layer}})
end

-- app.openDialog shows its message as plain text (gtk_message_dialog_format_secondary_text),
-- not Pango markup, so do not HTML-escape `&`, `<`, or `>`.
function M.message(msg, is_error)
  app.openDialog(tostring(msg or ""), {"OK"}, "", is_error or false)
end

-- Async "Save as" dialog; calls global `callback(path)` ("" when cancelled).
function M.save_dialog(callback, suggested)
  app.fileDialogSave(callback, suggested)
end

return M
