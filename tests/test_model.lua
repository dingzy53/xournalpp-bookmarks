local model = require("bm_model")

return {
  {"title_of recognises bookmark layers", function(T)
    T.eq(model.title_of("Bookmark::Intro"), "Intro")
    T.eq(model.title_of("Bookmark::"), "")
    T.eq(model.title_of("Layer 1"), nil)
    T.eq(model.title_of(nil), nil)
  end},

  {"collect returns document order and skips non-bookmarks", function(T)
    local s = {pages = {
      {layers = {[0] = {name = "bg"}, {name = "Layer 1"}, {name = "Bookmark::B"}}},
      {layers = {[0] = {name = "bg"}, {name = "Bookmark::C"}, {name = "Bookmark::D"}}},
    }}
    local got = {}
    for _, b in ipairs(model.collect(s)) do got[#got + 1] = b.page .. ":" .. b.layer .. ":" .. b.title end
    T.list_eq(got, {"1:2:B", "2:1:C", "2:2:D"})
  end},

  {"parse/format level prefixes", function(T)
    local cases = {
      {"Intro", 1, "Intro"},
      {"## Background", 2, "Background"},
      {"### Prior work", 3, "Prior work"},
      {"# ## not a heading", 1, "## not a heading"},
      {"#hashtag", 1, "#hashtag"},
      {"## ", 2, ""},
      {"############ deep", 9, "deep"},
      {"", 1, ""},
    }
    for _, c in ipairs(cases) do
      local level, title = model.parse_title(c[1])
      T.eq(level, c[2], "level of " .. c[1])
      T.eq(title, c[3], "title of " .. c[1])
    end
    -- round trips
    for _, c in ipairs({{1, "Intro"}, {2, "B"}, {1, "## literal"}, {1, "# x"}, {3, ""}, {1, "#tag"}}) do
      local level, title = model.parse_title(model.format_title(c[1], c[2]))
      T.eq(level, c[1], "round trip level " .. c[2])
      T.eq(title, c[2], "round trip title " .. c[2])
    end
    T.eq(model.format_title(1, "Intro"), "Intro", "level 1 stays in the legacy format")
    T.eq(model.layer_name("Sec", 2), "Bookmark::## Sec")
  end},

  {"normalize clamps level jumps without rewriting stored levels", function(T)
    local function eff(levels)
      local list = {}
      for i, l in ipairs(levels) do list[i] = {level = l} end
      model.normalize(list)
      local out = {}
      for i, b in ipairs(list) do out[i] = tostring(b.eff) end
      return out
    end
    T.list_eq(eff({2, 1}), {"1", "1"})
    T.list_eq(eff({1, 3, 3, 2}), {"1", "2", "3", "2"})
    T.list_eq(eff({1, 1, 4}), {"1", "1", "2"})
    T.list_eq(eff({1, 2, 3, 1, 2}), {"1", "2", "3", "1", "2"})
    T.list_eq(eff({}), {})
  end},

  {"subtree, previous level, promote/demote rules", function(T)
    local list = model.normalize({
      {page = 1, level = 1}, {page = 1, level = 2}, {page = 2, level = 3}, {page = 3, level = 2},
      {page = 5, level = 1},
    })
    T.eq(model.subtree_end(list, 1), 4)
    T.eq(model.subtree_end(list, 2), 3)
    T.eq(model.subtree_end(list, 4), 4)
    T.eq(model.subtree_end(list, 5), 5)
    T.eq(model.previous_level(list, 1), 2)
    T.eq(model.previous_level(list, 4), 2)
    T.eq(model.previous_level(list, 9), 1)
    T.eq(model.previous_level({}, 1), nil)
    T.eq(model.can_demote(list, 1), false, "first bookmark has no parent")
    T.eq(model.can_demote(list, 2), false, "already a child of the previous one")
    T.eq(model.can_demote(list, 4), true)
    T.eq(model.can_demote(list, 5), true)
    T.eq(model.can_promote(list, 1), false)
    T.eq(model.can_promote(list, 3), true)
  end},

  {"collect parses levels; legacy bookmarks are level 1", function(T)
    local s = {pages = {
      {layers = {[0] = {name = "bg"}, {name = "Bookmark::Old"}, {name = "Bookmark::## Child"}}},
      {layers = {[0] = {name = "bg"}, {name = "Bookmark::#### Deep"}}},
    }}
    local got = {}
    for _, b in ipairs(model.collect(s)) do got[#got + 1] = b.title .. ":" .. b.level .. "/" .. b.eff end
    T.list_eq(got, {"Old:1/1", "Child:2/2", "Deep:4/3"})
  end},

  {"outline labels indent and flag normalized levels", function(T)
    T.eq(model.outline_label({title = "A", level = 1, eff = 1}), "A")
    T.eq(model.outline_label({title = "", level = 2, eff = 2}), "\u{2003}\u{2003}↳ (No name)")
    T.truthy(model.outline_label({title = "D", level = 4, eff = 3}):find("⚠", 1, true))
  end},
}
