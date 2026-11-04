-- Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
-- Copyright (C) 2024-2025 Javier Reyes and contributors (original Bookmarks plugin)
-- Copyright (C) 2026 Ding Zheng Yuan (zenity port and later changes)
-- Modified by Ding Zheng Yuan in 2026; see README.md and the git history.
--
-- Pure bookmark model: no calls into Xournal++ or the shell.
--
-- A bookmark is a hidden layer named "Bookmark::<text>". The outline level is
-- encoded Markdown-style at the start of <text>:
--   "Bookmark::Intro"          level 1 (also every bookmark from older versions)
--   "Bookmark::## Background"  level 2
--   "Bookmark::### Prior work" level 3
--   "Bookmark::# ## literal"   level 1 titled "## literal" (explicit level 1)
--   "Bookmark::#hashtag"       level 1 titled "#hashtag" (no space after #)
-- The same syntax is used when typing a name into the dialogs.
local M = {}

M.PREFIX = "Bookmark::"
M.MAX_LEVEL = 9
local PREFIX_LEN = #M.PREFIX

-- Returns the raw text after the prefix if `name` is a bookmark layer name.
function M.title_of(name)
  if type(name) == "string" and name:sub(1, PREFIX_LEN) == M.PREFIX then
    return name:sub(PREFIX_LEN + 1)
  end
  return nil
end

local function clamp_level(level)
  level = math.floor(tonumber(level) or 1)
  if level < 1 then return 1 end
  if level > M.MAX_LEVEL then return M.MAX_LEVEL end
  return level
end
M.clamp_level = clamp_level

-- "## Title" -> 2, "Title"
function M.parse_title(text)
  text = text or ""
  local hashes, rest = text:match("^(#+) (.*)$")
  if hashes then return clamp_level(#hashes), rest end
  return 1, text
end

-- (2, "Title") -> "## Title"
function M.format_title(level, title)
  level = clamp_level(level)
  title = title or ""
  if level >= 2 then return string.rep("#", level) .. " " .. title end
  if title:match("^#+ ") then return "# " .. title end
  return title
end

-- Prefix shown in name dialogs for a given level ("" for level 1).
function M.level_prefix(level)
  level = clamp_level(level)
  if level == 1 then return "" end
  return string.rep("#", level) .. " "
end

function M.layer_name(title, level)
  return M.PREFIX .. M.format_title(level or 1, title)
end

-- Fill b.eff for each bookmark: the level actually used for display/export.
-- Stored levels may skip (1 -> 3) after edits or deletes; a bookmark can be
-- at most one level deeper than the one before it, and the first is level 1.
-- Stored levels are never rewritten implicitly.
function M.normalize(list)
  local prev = 0
  for _, b in ipairs(list) do
    b.eff = math.min(b.level, prev + 1)
    prev = b.eff
  end
  return list
end

-- Collect bookmarks of a single page, in layer order (not normalized).
function M.collect_page(structure, page)
  local list = {}
  local pageInfo = structure.pages[page]
  if not pageInfo then return list end
  -- Layer 0 is the page background; its "name" is the background name.
  for i = 1, #pageInfo.layers do
    local v = pageInfo.layers[i]
    local raw = v and M.title_of(v.name)
    if raw then
      local level, title = M.parse_title(raw)
      table.insert(list, {page = page, layer = i, level = level, title = title, raw = raw})
    end
  end
  return list
end

-- Collect all bookmarks in document order (page, then layer), normalized.
function M.collect(structure)
  local list = {}
  for page = 1, #structure.pages do
    for _, b in ipairs(M.collect_page(structure, page)) do
      table.insert(list, b)
    end
  end
  return M.normalize(list)
end

-- Index of the last descendant of list[i] (i itself when it has none).
function M.subtree_end(list, i)
  local j = i
  while list[j + 1] and list[j + 1].eff > list[i].eff do j = j + 1 end
  return j
end

-- Effective level of the last bookmark at or before `page` (nil if none).
-- New bookmarks are appended at the end of their page, so this is the
-- bookmark a new one on `page` would follow.
function M.previous_level(list, page)
  local level
  for _, b in ipairs(list) do
    if b.page <= page then level = b.eff else break end
  end
  return level
end

-- Can list[i] (with its subtree) move one level deeper / shallower?
function M.can_demote(list, i)
  if i <= 1 then return false end
  if list[i].eff > list[i - 1].eff then return false end
  for j = i, M.subtree_end(list, i) do
    if list[j].eff >= M.MAX_LEVEL then return false end
  end
  return true
end

function M.can_promote(list, i)
  return list[i].eff > 1
end

function M.display_title(title)
  if title == nil or title == "" then return "(No name)" end
  return title
end

-- Title indented by level, for single-line list entries.
local INDENT = "\u{2003}\u{2003}" -- em spaces: not trimmed or collapsed by list widgets
function M.outline_label(b)
  local label = M.display_title(b.title)
  if b.eff > 1 then label = string.rep(INDENT, b.eff - 1) .. "↳ " .. label end
  if b.eff ~= b.level then label = label .. "  ⚠" end
  return label
end

return M
