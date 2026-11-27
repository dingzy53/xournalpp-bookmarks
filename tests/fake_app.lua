-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2026 Ding Zheng Yuan
--
-- In-memory stand-in for the Xournal++ 1.3+ `app` Lua API, modelled on
-- src/core/plugin/luapi_application.h and Plugin.cpp.
local Fake = {}
Fake.__index = Fake

local function check_pango(msg)
  local stripped = tostring(msg or "")
    :gsub("&amp;", ""):gsub("&lt;", ""):gsub("&gt;", "")
    :gsub("&quot;", ""):gsub("&apos;", "")
    :gsub("&#%d+;", ""):gsub("&#x%x+;", "")
  if stripped:find("[&<>]") then
    error("invalid Pango markup in app.openDialog: " .. tostring(msg))
  end
end

-- pages: list of { layers = { {name=..., visible=...}, ... } }
function Fake.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Fake)
  self.pages = {}
  for i, p in ipairs(opts.pages or {{}}) do
    local layers = {}
    for j, l in ipairs(p.layers or {{name = "Layer 1"}}) do
      layers[j] = {name = l.name or ("Layer " .. j), visible = l.visible ~= false}
    end
    self.pages[i] = {layers = layers, current = p.current or #layers, pdfPage = p.pdfPage or 0}
  end
  self.currentPage = opts.currentPage or 1
  self.xoppFilename = opts.xoppFilename or ""
  self.pdfBackgroundFilename = opts.pdfBackgroundFilename or ""
  self.log = {}
  self.messages = {}
  self.registered = {}
  self.in_init_ui = false
  self.structure_calls = 0
  self.saveAsResult = opts.saveAsResult
  self.async_save = opts.async_save or false
  self.pending_save = nil
  self.exported = {}
  return self
end

function Fake:page() return self.pages[self.currentPage] end

-- Simulate Xournal++'s initUi() call window.
function Fake:run_init_ui()
  self.in_init_ui = true
  local ok, err = pcall(_G.initUi)
  self.in_init_ui = false
  if not ok then error(err, 2) end
end

-- Build the `app` table bound to this fake document.
function Fake:install()
  local s = self
  local app = {}

  function app.getDocumentStructure()
    s.structure_calls = s.structure_calls + 1
    local pages = {}
    for i, p in ipairs(s.pages) do
      local layers = {[0] = {isVisible = true, name = "Background"}}
      for j, l in ipairs(p.layers) do
        layers[j] = {name = l.name, isVisible = l.visible, isAnnotated = false}
      end
      pages[i] = {layers = layers, currentLayer = p.current, pdfBackgroundPageNo = p.pdfPage}
    end
    return {pages = pages, currentPage = s.currentPage, xoppFilename = s.xoppFilename,
      pdfBackgroundFilename = s.pdfBackgroundFilename}
  end

  function app.setCurrentPage(n)
    if n < 1 then n = 1 end
    if n > #s.pages then n = #s.pages end
    s.currentPage = n
  end

  function app.scrollToPage(n) table.insert(s.log, "scroll:" .. n) end

  function app.setCurrentLayer(id)
    local p = s:page()
    if id < 0 or id > #p.layers then error("No layer with layer ID " .. id) end
    p.current = id
  end

  function app.setCurrentLayerName(name)
    local p = s:page()
    p.layers[p.current].name = name
  end

  function app.setLayerVisibility(v)
    local p = s:page()
    p.layers[p.current].visible = v
  end

  local function new_layer_above()
    local p = s:page()
    local pos = p.current -- insert after current (0-based index == current id)
    table.insert(p.layers, pos + 1, {name = "", visible = true})
    p.current = pos + 1
  end

  local function delete_current_layer()
    local p = s:page()
    if p.current == 0 then return end
    table.remove(p.layers, p.current)
    if #p.layers == 0 then p.layers[1] = {name = "", visible = true} end
    p.current = #p.layers -- XojPage::removeLayer resets to npos == top layer
  end

  function app.activateAction(a)
    table.insert(s.log, "activateAction:" .. a)
    if a == "layer-new-above-current" then new_layer_above()
    elseif a == "layer-delete" then delete_current_layer()
    else error("unknown action " .. a) end
  end

  function app.openDialog(msg, buttons, cb, isError)
    check_pango(msg)
    table.insert(s.messages, {msg = msg, error = isError})
  end

  function app.fileDialogSave(cb, suggested)
    s.suggested = suggested
    local function finish(path) _G[cb](path or "") end
    if s.async_save then
      s.pending_save = finish
    else
      finish(s.saveAsResult)
    end
  end

  function app.getFolder(kind)
    return s.folder or os.getenv("TMPDIR") or "/tmp"
  end

  function app.export(opts)
    table.insert(s.exported, opts)
    if s.on_export then s.on_export(opts) end
  end

  function app.glib_rename(from, to)
    local ok, err = os.rename(from, to)
    if ok then return 1 end
    return nil, err
  end

  function app.registerUi(opts)
    if not s.in_init_ui then
      error("registerUi needs to be called within initUi()")
    end
    if type(opts) ~= "table" or type(opts.callback) ~= "string" or opts.callback == "" then
      error("Missing callback function!")
    end
    table.insert(s.registered, opts)
    return {menuId = #s.registered}
  end

  _G.app = app
  return app
end

-- Convenience: list of layer names on a page.
function Fake:names(page)
  local out = {}
  for i, l in ipairs(self.pages[page].layers) do out[i] = l.name end
  return out
end

return Fake
