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
