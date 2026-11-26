-- QoL Comp / startmenu: EDIT START MENU.
--
-- The START menu of every generation is assembled by the engine and handed
-- through ui.start_menu.items, so one wrap reorders and hides rows on all
-- eleven games.  Each row is known by a stable key -- Gen 3's `id`, Gen 2's
-- `value`, Gen 1's label -- and the layout is stored per generation in the
-- mod's installation cache (it is a preference, not part of any one save).
--
-- The editor lists the rows the START menu last showed.  A on a row offers
-- MOVE and HIDE (or SHOW for a hidden row); MOVE lifts the row so UP/DOWN
-- carry it, and A or B sets it down.  The MODS row can be moved but never
-- hidden, so the mod manager can always be reached from the menu.

local V = ...
local C = V.core
local UI = V.ui

local M = {}

local STORE = "startmenu"

local function genKey() return "gen" .. tostring(V.generation) end

local function clean(s)
  return (tostring(s or ""):gsub("[,|=\n\r]", "_"))
end

-- One stable key per row.  Gen 3 tags rows with `id`, Gen 2 with `value`,
-- Gen 1 has only the label -- and a label-derived key is upper-cased with
-- its accents folded so DECAPITALIZATION (which rewrites what is drawn)
-- cannot turn one row into two.
local ACCENTS = { ["\195\169"] = "E", ["\195\137"] = "E" }

local function fold(text)
  text = tostring(text or "")
  for from, to in pairs(ACCENTS) do text = text:gsub(from, to) end
  return (text:upper():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function keyOf(item)
  if type(item) ~= "table" then return nil end
  for _, field in ipairs({ "id", "value" }) do
    local v = item[field]
    if type(v) == "string" and v ~= "" then return clean(fold(v)) end
  end
  if item.label == nil then return nil end
  return clean(fold(item.label))
end

local function isMods(key, label)
  local k = tostring(key or ""):upper()
  local l = tostring(label or ""):upper()
  return k == "MODS" or l == "MODS"
end

local function split(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do out[#out + 1] = part end
  return out
end

-- ------- persisted layout
--
-- The layout is ONE column: `order`, every row this generation's START menu
-- has ever shown, top to bottom in the player's order, plus a `hidden` set.
--
--   the editor     lists `order`, keeping only the rows the START menu has
--                  right now (`seen`); MOVE swaps two neighbours in it
--   the START menu is its rows sorted by their place in `order`, hidden
--                  ones dropped (never MODS, so the manager stays reachable)
--   a new row      (POKEDEX unlocking, a mod installed since) goes into
--                  `order` once, just above the row below it in the game's
--                  own menu -- and stays wherever the player then puts it
--
-- Both views read the same column, so the list being edited is the menu
-- being built; nothing is re-ranked behind the player's back.  (v1.4-1.52
-- kept a partial order plus "the rest" rules, and the two views could
-- disagree.)

local state = nil
local save

-- a row's identity as the player reads it: the folded label
local function labelKey(label) return clean(fold(label)) end

local function indexOf(list, key)
  for i, k in ipairs(list) do if k == key then return i end end
  return nil
end

-- One row, one key.  An older store could hold the same row twice -- under
-- its id and under its label -- which listed it twice.  A label-derived key
-- whose label matches an id-keyed row is folded into that row.
local function collapse(s)
  local idByLabel = {}
  for _, k in ipairs(s.order) do
    local label = s.labels[k]
    if label and k ~= labelKey(label) then
      idByLabel[labelKey(label)] = idByLabel[labelKey(label)] or k
    end
  end
  local changed = false
  local out, have = {}, {}
  for _, k in ipairs(s.order) do
    local to = k
    if s.labels[k] and k == labelKey(s.labels[k]) and idByLabel[k] then to = idByLabel[k] end
    if to ~= k then
      changed = true
      if s.hidden[k] then s.hidden[to] = true end
      s.hidden[k] = nil
    end
    if not have[to] then out[#out + 1] = to; have[to] = true else changed = true end
  end
  s.order = out
  local seen, seenHave = {}, {}
  for _, k in ipairs(s.seen) do
    local to = (s.labels[k] and k == labelKey(s.labels[k]) and idByLabel[k]) or k
    if not seenHave[to] then seen[#seen + 1] = to; seenHave[to] = true end
  end
  s.seen = seen
  return changed
end

local function load()
  if state then return state end
  local raw = C.loadStore(STORE)
  local g = genKey()
  state = { order = {}, hidden = {}, labels = {}, seen = split(raw[g .. ".seen"]), raw = raw }
  local have = {}
  local function add(k)
    if k and k ~= "" and not have[k] then state.order[#state.order + 1] = k; have[k] = true end
  end
  for _, k in ipairs(split(raw[g .. ".order"])) do add(k) end
  -- every row ever learned belongs in the column (an older store kept only
  -- the rows the player had moved in `order`)
  for _, pair in ipairs(split(raw[g .. ".known"])) do
    local k, label = pair:match("^(.-)|(.*)$")
    if k then
      state.labels[k] = label
      add(k)
    end
  end
  for _, k in ipairs(split(raw[g .. ".hidden"])) do state.hidden[k] = true end
  if collapse(state) then save() end
  return state
end

function save()
  local s = load()
  local raw = s.raw or {}
  local g = genKey()
  raw[g .. ".order"] = table.concat(s.order, ",")
  local hidden = {}
  for k in pairs(s.hidden) do hidden[#hidden + 1] = k end
  table.sort(hidden)
  raw[g .. ".hidden"] = table.concat(hidden, ",")
  local known = {}
  for _, k in ipairs(s.order) do
    known[#known + 1] = k .. "|" .. clean(s.labels[k] or k)
  end
  raw[g .. ".known"] = table.concat(known, ",")
  raw[g .. ".seen"] = table.concat(s.seen or {}, ",")
  s.raw = raw
  C.saveStore(STORE, raw)
end

-- The key a row is stored under: its id (Gen 3) or value (Gen 2), else its
-- folded label (Gen 1) -- unless an id-keyed row already reads the same, in
-- which case it IS that row.
local function canonical(s, item)
  local k = keyOf(item)
  if not k then return nil end
  local lk = item.label ~= nil and labelKey(item.label) or nil
  if lk and k == lk then
    for _, other in ipairs(s.order) do
      local label = s.labels[other]
      if label and other ~= lk and labelKey(label) == lk then return other end
    end
  end
  return k
end

-- Take in the rows the START menu is offering (game order).  A row the
-- column has never had goes just above the nearest row BELOW it in the
-- game's menu (Crystal's POKEDEX above POKEMON, POKEGEAR above the player's
-- card), or at the bottom if nothing follows it (QUIT, a mod's row added at
-- the end).  Returns each item's key.
local function learn(items)
  local s = load()
  local changed = false
  local keys = {}
  for i, item in ipairs(items) do keys[i] = canonical(s, item) end
  for i, item in ipairs(items) do
    local k = keys[i]
    if k then
      local label = tostring(item.label or k)
      if s.labels[k] ~= label then s.labels[k] = label; changed = true end
      if not indexOf(s.order, k) then
        local at = nil
        for j = i + 1, #items do
          local p = keys[j] and indexOf(s.order, keys[j])
          if p then at = p break end
        end
        table.insert(s.order, at or (#s.order + 1), k)
        changed = true
      end
    end
  end
  local seenNow, dup = {}, {}
  for _, k in ipairs(keys) do
    if k and not dup[k] then dup[k] = true; seenNow[#seenNow + 1] = k end
  end
  if table.concat(seenNow, ",") ~= table.concat(s.seen or {}, ",") then
    s.seen = seenNow
    changed = true
  end
  if changed then save() end
  return keys
end

-- the column, keeping only the rows the START menu has right now (all of
-- it before the menu has been seen), as { key, label } rows
local function orderedKnown()
  local s = load()
  local current = nil
  if s.seen and #s.seen > 0 then
    current = {}
    for _, k in ipairs(s.seen) do current[k] = true end
  end
  local out = {}
  for _, k in ipairs(s.order) do
    if not current or current[k] then out[#out + 1] = { key = k, label = s.labels[k] or k } end
  end
  return out
end

-- ------- applying the layout

function M.apply(items)
  if type(items) ~= "table" then return items end
  local keys = learn(items)
  local s = load()
  local place = {}
  for i, k in ipairs(s.order) do place[k] = i end
  local rows = {}
  for i, item in ipairs(items) do
    rows[i] = { item = item, key = keys[i], at = (keys[i] and place[keys[i]]) or math.huge, game = i }
  end
  table.sort(rows, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.game < b.game
  end)
  local out = {}
  for _, r in ipairs(rows) do
    local k = r.key
    if not (k and s.hidden[k]) or isMods(k, r.item.label) then out[#out + 1] = r.item end
  end
  if #out == 0 then return items end
  return out
end

-- ------- the editor

-- The START menu the editor was reached from is usually still open under
-- it: Crystal's START -> OPTION -> QOL COMP, Gen 3's START -> OPTION or
-- MODS.  Those games re-show that same menu when you back out, built before
-- the edit, so after each change the open menu is rebuilt in place from the
-- rows it was given (M._raw, kept by the hook below).
local refreshOpen

-- MOVE: swap two neighbouring rows of the editor's list, in the column
local function swap(a, b)
  local s = load()
  local i, j = indexOf(s.order, a), indexOf(s.order, b)
  if not (i and j) then return false end
  s.order[i], s.order[j] = s.order[j], s.order[i]
  save()
  refreshOpen()
  return true
end

function M.openEditor(game)
  if not game then return false end
  M._editorGame = game
  if #load().order == 0 then
    UI.notice(game, "OPEN START MENU ONCE FIRST")
    return true
  end
  local screen
  screen = UI.open(game, {
    title = "EDIT START MENU",
    hint = "A:EDIT  B:DONE",
    rows = function()
      local s = load()
      local out = {}
      for _, row in ipairs(orderedKnown()) do
        local hidden = s.hidden[row.key] and not isMods(row.key, row.label)
        out[#out + 1] = {
          label = row.label,
          right = hidden and "HIDDEN" or nil,
          key = row.key,
          onSelect = function(scr, i)
            local options = { "MOVE" }
            if not isMods(row.key, row.label) then
              options[2] = hidden and "SHOW" or "HIDE"
            end
            scr:ask(options, function(choice)
              local st = load()
              if choice == "MOVE" then
                scr.moving = true
                scr.index = i
              elseif choice == "HIDE" then
                st.hidden[row.key] = true
                save()
                refreshOpen()
              elseif choice == "SHOW" then
                st.hidden[row.key] = nil
                save()
                refreshOpen()
              end
            end)
          end,
        }
      end
      out[#out + 1] = {
        label = "RESET LAYOUT",
        onSelect = function(scr)
          scr:ask({ "RESET", "KEEP" }, function(choice)
            if choice == "RESET" then M.reset() end
          end)
        end,
      }
      return out
    end,
    onMove = function(i, d)
      local rows = orderedKnown()
      local j = i + d
      if j < 1 or j > #rows then return end
      if swap(rows[i].key, rows[j].key) and screen then screen.index = j end
    end,
  })
  M._lastEditor = screen
  return true
end

-- RESET LAYOUT (the editor's last row): the game's own order, nothing
-- hidden.  The column starts again from the menu last seen, in its order;
-- rows not in that menu follow, so a later menu slots them back in.
function M.reset()
  local s = load()
  local order, have = {}, {}
  for _, k in ipairs(s.seen or {}) do
    if not have[k] then order[#order + 1] = k; have[k] = true end
  end
  for _, k in ipairs(s.order) do
    if not have[k] then order[#order + 1] = k; have[k] = true end
  end
  s.order, s.hidden = order, {}
  save()
  refreshOpen()
end

-- A menu the game builds for one scene only (the catching tutorial, the
-- Safari stats list) is not the START menu: leave those alone.
local function scenic(game)
  if V.generation ~= 3 then return false end
  local SM = C.engine("src.ui.game3.start_menu")
  if type(SM) ~= "table" then return false end
  return SM._tutorial == true or SM._kind == "safari"
end

-- the rows the last real START menu was built from, after every other
-- mod's link and before this mod's layout
M._raw = nil

local function relist(menu, rows)
  -- Crystal's START menu (src/ui/gen2/StartMenu.lua): items + its Chrome.List
  menu.items = rows
  local list = menu.list
  if type(list) == "table" and type(list.items) == "table" then
    list.items = rows
    list.rows = math.min(8, #rows)
    if (list.index or 1) > #rows then list.index = math.max(1, #rows) end
    if type(list.ensureVisible) == "function" then pcall(list.ensureVisible, list) end
  elseif (menu.index or 1) > #rows then
    menu.index = math.max(1, #rows)
  end
end

function refreshOpen()
  local raw = M._raw
  if type(raw) ~= "table" then return end
  local ok, rows = pcall(M.apply, C.copy(raw))
  if not ok or type(rows) ~= "table" or #rows == 0 then return end
  if V.generation == 3 then
    local SM = C.engine("src.ui.game3.start_menu")
    if type(SM) == "table" and SM.open and not scenic() then
      SM.ENTRIES = rows
      if (SM.cursor or 1) > #rows then SM.cursor = #rows end
      if type(SM.clampScroll) == "function" then pcall(SM.clampScroll) end
    end
    return
  end
  -- Gen 1 needs nothing: its START menu closes when a row is picked and is
  -- rebuilt (RedisplayStartMenu) when you come back, so it is never stale
  if V.generation ~= 2 then return end
  local game = M._editorGame or V.game
  local states = game and game.stack and game.stack.states
  if type(states) ~= "table" then return end
  for _, st in ipairs(states) do
    if type(st) == "table" and st.screenId == "Gen2StartMenu" and type(st.items) == "table" then
      pcall(relist, st, rows)
    end
  end
end
M._refreshOpen = function() return refreshOpen() end

function M.install(mod)
  -- Priority 100000 puts this link OUTERMOST, so next() has already run
  -- every other mod's link and the list it hands back is the final one --
  -- rows from Gameshark (priority 500), Highlander and anything else
  -- included.  Without it the editor only ever sees the game's own rows.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then out = items end
    if scenic(game) then return out end
    M._raw = C.copy(out)
    local ok, applied = pcall(M.apply, out)
    if ok and type(applied) == "table" then return applied end
    if not ok then C.warnOnce("startmenu.apply", applied) end
    return out
  end, 100000)
end

M.keyOf = keyOf

-- for the headless suite: the editor's rows, the store, and stores as
-- older versions left them
function M._editorRows() return orderedKnown() end
function M._state() return load() end
function M._setKnown(rows, seen)
  local st = load()
  st.order, st.labels, st.hidden = {}, {}, {}
  for _, row in ipairs(rows or {}) do
    st.labels[row[1]] = row[2]
    if not indexOf(st.order, row[1]) then st.order[#st.order + 1] = row[1] end
  end
  st.seen = seen or {}
  collapse(st)
  save()
end

-- for the headless suite: set a layout without driving the editor (keys
-- not named keep their relative order, after the named ones)
function M._setLayout(order, hidden)
  local st = load()
  local out, have = {}, {}
  for _, k in ipairs(order or {}) do
    if not have[k] then out[#out + 1] = k; have[k] = true end
  end
  for _, k in ipairs(st.order) do
    if not have[k] then out[#out + 1] = k; have[k] = true end
  end
  st.order = out
  st.hidden = {}
  for _, k in ipairs(hidden or {}) do st.hidden[k] = true end
  save()
end

return M
