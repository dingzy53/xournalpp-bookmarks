local Fake = require("fake_app")

local function doc()
  return Fake.new({pages = {
    {layers = {{name = "Layer 1"}}},
    {layers = {{name = "Layer 1"}, {name = "Bookmark::Two", visible = false}}, current = 1},
    {layers = {{name = "Layer 1"}}},
  }, currentPage = 1})
end

return {
  {"new_bookmark adds a hidden layer and keeps the current layer", function(T)
    local f = doc()
    T.load_plugin(f)
    new_bookmark("Hello\nWorld")
    T.list_eq(f:names(1), {"Layer 1", "Bookmark::Hello World"})
    T.eq(f.pages[1].layers[2].visible, false)
    T.eq(f.pages[1].current, 1)
  end},

  {"dialog_new_bookmark cancelled does nothing", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    T.script_dialogs(platform, {false})
    dialog_new_bookmark()
    T.list_eq(f:names(1), {"Layer 1"})
  end},

  {"search_bookmark wraps around", function(T)
    local f = doc()
    f.currentPage = 3
    T.load_plugin(f)
    search_bookmark(1)
    T.eq(f.currentPage, 2)
  end},

  {"search_bookmark reports when there are no bookmarks", function(T)
    local f = Fake.new({pages = {{}, {}}})
    T.load_plugin(f)
    search_bookmark(1)
    T.eq(f.currentPage, 1)
    T.eq(#f.messages, 1)
  end},

  {"view_bookmarks delete removes the layer", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    T.script_dialogs(platform, {"2_2", "Delete"})
    view_bookmarks()
    T.list_eq(f:names(2), {"Layer 1"})
    T.eq(f.currentPage, 1)
  end},

  {"view_bookmarks edit renames in place", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    T.script_dialogs(platform, {"2_2", "Edit", "2", "Renamed"})
    view_bookmarks()
    T.list_eq(f:names(2), {"Layer 1", "Bookmark::Renamed"})
  end},

  {"view_bookmarks edit moves to another page", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    T.script_dialogs(platform, {"2_2", "Edit", "3", "Moved"})
    view_bookmarks()
    T.list_eq(f:names(2), {"Layer 1"})
    T.list_eq(f:names(3), {"Layer 1", "Bookmark::Moved"})
  end},

  {"uses non-deprecated actions on Xournal++ 1.3", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    new_bookmark("A")
    T.script_dialogs(platform, {"2_2", "Delete"})
    view_bookmarks()
    for _, l in ipairs(f.log) do T.truthy(not l:find("^layerAction"), "deprecated call: " .. l) end
    T.truthy(table.concat(f.log, ","):find("activateAction:layer-new-above-current", 1, true))
    T.truthy(table.concat(f.log, ","):find("activateAction:layer-delete", 1, true))
  end},

  {"falls back to the 1.2 API", function(T)
    local f = Fake.new({api_version = "1.2", pages = {{layers = {{name = "Layer 1"}}}}, saveAsResult = ""})
    local platform = T.load_plugin(f)
    T.eq(app.activateAction, nil)
    new_bookmark("A")
    T.list_eq(f:names(1), {"Layer 1", "Bookmark::A"})
    search_bookmark(1)
    T.eq(#f.messages, 0)
    platform.execute = function() return true end
    export_with_bookmarks() -- cancelled save dialog (saveAs returns "")
    T.eq(f.suggested, "/tmp/temp_export.pdf")
  end},

  {"new bookmarks are appended on top so same-page order is creation order", function(T)
    local f = Fake.new({pages = {{layers = {{name = "Layer 1"}, {name = "Layer 2"}}, current = 1}}})
    T.load_plugin(f)
    new_bookmark("First")
    new_bookmark("Second")
    T.list_eq(f:names(1), {"Layer 1", "Layer 2", "Bookmark::First", "Bookmark::Second"})
    T.eq(f.pages[1].current, 1, "user's layer stays selected")
  end},

  {"background layer is never treated as a bookmark", function(T)
    local model = require("bm_model")
    local s = {pages = {{layers = {[0] = {name = "Bookmark::bg"}, {name = "Layer 1"}}}}}
    T.eq(#model.collect(s), 0)
  end},

  {"stale layer index never deletes or renames user content", function(T)
    local f = Fake.new({pages = {{layers = {{name = "Layer 1"}, {name = "Bookmark::A"}}}}})
    T.load_plugin(f)
    local doc = require("bm_doc")
    doc.delete_bookmark(1, 5)  -- out of range: no error, nothing deleted
    doc.delete_bookmark(1, 1)  -- not a bookmark layer
    doc.rename_bookmark(1, 1, "x")
    T.list_eq(f:names(1), {"Layer 1", "Bookmark::A"})
  end},

  {"delete keeps the user's page and layer", function(T)
    local f = Fake.new({pages = {
      {layers = {{name = "L"}, {name = "L2"}}, current = 2},
      {layers = {{name = "Bookmark::A"}, {name = "Mine"}, {name = "Bookmark::B"}}, current = 2},
    }, currentPage = 1})
    T.load_plugin(f)
    local doc = require("bm_doc")
    doc.delete_bookmark(2, 1)
    T.eq(f.currentPage, 1)
    T.eq(f.pages[1].current, 2)
    T.list_eq(f:names(2), {"Mine", "Bookmark::B"})
    T.eq(f.pages[2].current, 1, "selected layer 'Mine' moved down to index 1")
  end},

  {"delete_bookmarks deletes highest index first", function(T)
    local f = Fake.new({pages = {{layers = {{name = "L"}, {name = "Bookmark::A"}, {name = "Bookmark::B"},
      {name = "Bookmark::C"}}}}})
    T.load_plugin(f)
    local doc = require("bm_doc")
    doc.delete_bookmarks({{page = 1, layer = 2}, {page = 1, layer = 4}})
    T.list_eq(f:names(1), {"L", "Bookmark::B"})
  end},

  {"layer index errors from Xournal++ are contained", function(T)
    local f = Fake.new({pages = {{layers = {{name = "L"}}}}})
    T.load_plugin(f)
    local real = app.setCurrentLayer
    app.setCurrentLayer = function() error("No layer with layer ID 9") end
    new_bookmark("X") -- must not raise
    app.setCurrentLayer = real
  end},
}
