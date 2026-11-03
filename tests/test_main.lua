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
    T.script_dialogs(platform, {"1", "Delete"})
    view_bookmarks()
    T.list_eq(f:names(2), {"Layer 1"})
    T.eq(f.currentPage, 1)
  end},

  {"view_bookmarks edit renames in place", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    T.script_dialogs(platform, {"1", "Edit", "2", "Renamed"})
    view_bookmarks()
    T.list_eq(f:names(2), {"Layer 1", "Bookmark::Renamed"})
  end},

  {"view_bookmarks edit moves to another page", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    T.script_dialogs(platform, {"1", "Edit", "3", "Moved"})
    view_bookmarks()
    T.list_eq(f:names(2), {"Layer 1"})
    T.list_eq(f:names(3), {"Layer 1", "Bookmark::Moved"})
  end},

  {"uses non-deprecated actions on Xournal++ 1.3", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    new_bookmark("A")
    T.script_dialogs(platform, {"1", "Delete"})
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
    platform.find_tool = function(n) return "/usr/bin/" .. n end
    export_with_bookmarks() -- cancelled save dialog (saveAs returns "")
    T.eq(f.suggested, os.getenv("HOME") .. "/bookmarks_export.pdf")
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

  {"bookmark names never reach zenity --text", function(T)
    local f = Fake.new({pages = {{layers = {{name = "L"}, {name = "Bookmark::a <b> & c"}}}}})
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"1", "Edit", "1", "x"})
    view_bookmarks()
    for _, argv in ipairs(calls) do
      for _, a in ipairs(argv) do
        T.truthy(not (a:find("^%-%-text=") and a:find("<b>", 1, true)), "name in --text: " .. a)
      end
    end
  end},

  {"bookmark list on ncruces zenity uses one column", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    platform.zenity_flavor = function() return "ncruces" end
    local calls = T.script_dialogs(platform, {"Page 2  —  Two", "Jump To"})
    view_bookmarks()
    T.eq(f.currentPage, 2)
    local argv = calls[1]
    T.eq(argv[#argv], "Page 2  —  Two")
    for _, a in ipairs(argv) do T.truthy(a ~= "--hide-column=1", "ncruces has no --hide-column") end
  end},

  {"bookmark list on GNOME zenity uses a hidden index column", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"1|", "Jump To"})
    view_bookmarks()
    T.eq(f.currentPage, 2)
    local joined = table.concat(calls[1], " ")
    T.truthy(joined:find("--hide-column=1 --print-column=1 1 Page 2 Two", 1, true), joined)
  end},

  {"missing zenity shows an install hint instead of failing silently", function(T)
    local f = doc()
    local platform = T.load_plugin(f)
    platform.find_tool = function() return nil end
    dialog_new_bookmark()
    T.eq(#f.messages, 1)
    T.truthy(f.messages[1].msg:find("zenity", 1, true))
    T.eq(f.messages[1].error, true)
  end},

  {"default export path", function(T)
    local platform = require("bm_platform")
    T.eq(platform.default_export_path("/home/u/notes.xopp", ""), "/home/u/notes_export.pdf")
    T.eq(platform.default_export_path("/home/u/my.dir/notes", ""), "/home/u/my.dir/notes_export.pdf")
    T.eq(platform.default_export_path("", "/home/u/paper.pdf"), "/home/u/paper_annotated.pdf")
    T.eq(platform.default_export_path("", ""), os.getenv("HOME") .. "/bookmarks_export.pdf")
  end},

  {"new bookmark dialog is pre-filled with the sibling level", function(T)
    local f = Fake.new({pages = {
      {layers = {{name = "L"}, {name = "Bookmark::Ch"}, {name = "Bookmark::## Sec"}}},
      {layers = {{name = "L"}}},
    }, currentPage = 2})
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"## Next sec"})
    dialog_new_bookmark()
    T.eq(calls[1][#calls[1]], "--entry-text=## ")
    T.list_eq(f:names(2), {"L", "Bookmark::## Next sec"})
  end},

  {"no-dialog bookmark becomes a sibling of the previous one", function(T)
    local f = Fake.new({pages = {{layers = {{name = "L"}, {name = "Bookmark::Ch"}, {name = "Bookmark::### Deep"}}}, {}},
      currentPage = 2})
    T.load_plugin(f)
    new_bookmark()
    T.list_eq(f:names(2), {"Layer 1", "Bookmark::## "}, "eff level of '### Deep' after normalization is 2")
  end},

  {"edit keeps the level and can change it", function(T)
    local f = Fake.new({pages = {{layers = {{name = "L"}, {name = "Bookmark::A"}, {name = "Bookmark::## B"}}}, {}}})
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"2", "Edit", "1", "## B renamed"})
    view_bookmarks()
    T.eq(calls[4][#calls[4]], "--entry-text=## B", "name dialog shows the level prefix")
    T.list_eq(f:names(1), {"L", "Bookmark::A", "Bookmark::## B renamed"})
    T.script_dialogs(platform, {"2", "Edit", "2", "## B renamed"})
    view_bookmarks()
    T.list_eq(f:names(2), {"Layer 1", "Bookmark::## B renamed"}, "moved with its level")
  end},

  {"new sub-bookmark is one level below the previous bookmark", function(T)
    local f = Fake.new({pages = {{layers = {{name = "L"}, {name = "Bookmark::Ch"}, {name = "Bookmark::## Sec"}}}, {}}, currentPage = 2})
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"### Sub"})
    dialog_new_sub_bookmark()
    T.eq(calls[1][#calls[1]], "--entry-text=### ")
    T.list_eq(f:names(2), {"Layer 1", "Bookmark::### Sub"})
  end},

  {"manager: demote and promote move the whole subtree", function(T)
    local f = Fake.new({pages = {
      {layers = {{name = "L"}, {name = "Bookmark::A"}, {name = "Bookmark::B"}, {name = "Bookmark::## B.1"}}},
      {layers = {{name = "L"}, {name = "Bookmark::C"}}},
    }})
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"2", "Demote (one level down, with its sub-bookmarks)"})
    view_bookmarks()
    T.list_eq(f:names(1), {"L", "Bookmark::A", "Bookmark::## B", "Bookmark::### B.1"})
    T.list_eq(f:names(2), {"L", "Bookmark::C"}, "following sibling untouched")
    T.eq(#calls, 3, "list shown again after the change")
    -- the reopened list shows the indentation
    T.truthy(table.concat(calls[3], "|"):find("\u{2003}\u{2003}\u{2003}\u{2003}↳ B.1", 1, true))

    T.script_dialogs(platform, {"2", "Promote (one level up, with its sub-bookmarks)"})
    view_bookmarks()
    T.list_eq(f:names(1), {"L", "Bookmark::A", "Bookmark::B", "Bookmark::## B.1"})
  end},

  {"manager: actions offered depend on position", function(T)
    local f = Fake.new({pages = {{layers = {{name = "L"}, {name = "Bookmark::A"}, {name = "Bookmark::## A.1"}}}}})
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"1", false, "2", false})
    view_bookmarks()
    local first = table.concat(calls[2], "|")
    T.truthy(not first:find("Promote", 1, true) and not first:find("Demote", 1, true), first)
    local second = table.concat(calls[4], "|")
    T.truthy(second:find("Promote", 1, true) and not second:find("Demote", 1, true), second)
  end},

  {"manager: delete only the parent promotes its children", function(T)
    local f = Fake.new({pages = {
      {layers = {{name = "L"}, {name = "Bookmark::A"}, {name = "Bookmark::## A.1"}}},
      {layers = {{name = "Bookmark::### A.1.1"}, {name = "L"}, {name = "Bookmark::B"}}},
    }})
    local platform = T.load_plugin(f)
    T.script_dialogs(platform, {"1", "Delete", "Delete only this bookmark (its sub-bookmarks move up one level)"})
    view_bookmarks()
    T.list_eq(f:names(1), {"L", "Bookmark::A.1"})
    T.list_eq(f:names(2), {"Bookmark::## A.1.1", "L", "Bookmark::B"})
  end},

  {"manager: delete with sub-bookmarks", function(T)
    local f = Fake.new({pages = {
      {layers = {{name = "L"}, {name = "Bookmark::A"}, {name = "Bookmark::## A.1"}}},
      {layers = {{name = "Bookmark::### A.1.1"}, {name = "L"}, {name = "Bookmark::B"}}},
    }})
    local platform = T.load_plugin(f)
    local calls = T.script_dialogs(platform, {"1", "Delete", "Delete it with its 2 sub-bookmarks"})
    view_bookmarks()
    T.list_eq(f:names(1), {"L"})
    T.list_eq(f:names(2), {"L", "Bookmark::B"})
  end},
}
