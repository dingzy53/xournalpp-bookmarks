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
}
