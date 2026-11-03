-- In-memory stand-in for the Xournal++ `app` Lua API, modelled on
-- src/core/plugin/luapi_application.h and LayerController/XojPage semantics.
local Fake = {}
Fake.__index = Fake

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
  self.saveAsResult = opts.saveAsResult
  self.exported = {}
  self.api_version = opts.api_version or "1.3"
  return self
end

function Fake:page() return self.pages[self.currentPage] end

-- Build the `app` table bound to this fake document.
function Fake:install()
  local s = self
  local app = {}

  function app.getDocumentStructure()
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
    if id > #p.layers then error("No layer with layer ID " .. id) end
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

  function app.layerAction(a)
    table.insert(s.log, "layerAction:" .. a)
    if a == "ACTION_NEW_LAYER" then new_layer_above()
    elseif a == "ACTION_DELETE_LAYER" then delete_current_layer()
    else error("unknown layer action " .. a) end
  end

  if s.api_version ~= "1.2" then
    function app.activateAction(a)
      table.insert(s.log, "activateAction:" .. a)
      if a == "layer-new-above-current" then new_layer_above()
      elseif a == "layer-delete" then delete_current_layer()
      else error("unknown action " .. a) end
    end

    function app.openDialog(msg, buttons, cb, isError)
      table.insert(s.messages, {msg = msg, error = isError})
    end

    function app.fileDialogSave(cb, suggested)
      s.suggested = suggested
      _G[cb](s.saveAsResult or "")
    end

    function app.getFolder(kind)
      return s.folder or os.getenv("TMPDIR") or "/tmp"
    end
  else
    function app.msgbox(msg) table.insert(s.messages, {msg = msg}) end
  end

  function app.saveAs(suggested)
    s.suggested = suggested
    return s.saveAsResult
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

  function app.registerUi(opts) end

  _G.app = app
  return app
end

-- Convenience: list of bookmark layer names on a page.
function Fake:names(page)
  local out = {}
  for i, l in ipairs(self.pages[page].layers) do out[i] = l.name end
  return out
end

return Fake
