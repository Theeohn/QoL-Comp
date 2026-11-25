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

local state = nil

local function load()
  if state then return state end
  local raw = C.loadStore(STORE)
  local g = genKey()
  state = { order = split(raw[g .. ".order"]), hidden = {}, known = {} }
  for _, k in ipairs(split(raw[g .. ".hidden"])) do state.hidden[k] = true end
  for _, pair in ipairs(split(raw[g .. ".known"])) do
    local k, label = pair:match("^(.-)|(.*)$")
    if k then state.known[#state.known + 1] = { key = k, label = label } end
  end
  state.raw = raw
  return state
end

local function save()
  local s = load()
  local raw = s.raw or {}
  local g = genKey()
  raw[g .. ".order"] = table.concat(s.order, ",")
  local hidden = {}
  for k in pairs(s.hidden) do hidden[#hidden + 1] = k end
  table.sort(hidden)
  raw[g .. ".hidden"] = table.concat(hidden, ",")
  local known = {}
  for _, row in ipairs(s.known) do known[#known + 1] = row.key .. "|" .. clean(row.label) end
  raw[g .. ".known"] = table.concat(known, ",")
  s.raw = raw
  C.saveStore(STORE, raw)
end

-- the known rows, in the player's order (order first, the rest after)
local function orderedKnown()
  local s = load()
  local byKey, out, seen = {}, {}, {}
  for _, row in ipairs(s.known) do byKey[row.key] = row end
  for _, k in ipairs(s.order) do
    if byKey[k] and not seen[k] then out[#out + 1] = byKey[k]; seen[k] = true end
  end
  for _, row in ipairs(s.known) do
    if not seen[row.key] then out[#out + 1] = row; seen[row.key] = true end
  end
  return out
end

-- remember the rows the engine offered, so the editor can list them
local function learn(items)
  local s = load()
  local changed = false
  local index = {}
  for i, row in ipairs(s.known) do index[row.key] = i end
  for _, item in ipairs(items) do
    local k = keyOf(item)
    if k then
      local label = tostring(item.label or k)
      if not index[k] then
        s.known[#s.known + 1] = { key = k, label = label }
        index[k] = #s.known
        changed = true
      elseif s.known[index[k]].label ~= label then
        s.known[index[k]].label = label
        changed = true
      end
    end
  end
  if changed then save() end
end

-- ------- applying the layout

function M.apply(items)
  if type(items) ~= "table" then return items end
  learn(items)
  local s = load()
  if #s.order == 0 and next(s.hidden) == nil then return items end
  local rank = {}
  for i, k in ipairs(s.order) do rank[k] = i end
  local ordered, rest = {}, {}
  for _, item in ipairs(items) do
    local k = keyOf(item)
    if k and rank[k] then
      ordered[#ordered + 1] = item
    else
      rest[#rest + 1] = item
    end
  end
  table.sort(ordered, function(a, b) return rank[keyOf(a)] < rank[keyOf(b)] end)
  -- A row the layout has never seen (a mod installed since) goes on the end,
  -- where the editor can find it -- but under a trailing QUIT/EXIT, so that
  -- stays the last row until the player moves it.
  local tail = nil
  local lastKey = ordered[#ordered] and keyOf(ordered[#ordered])
  if lastKey == "QUIT" or lastKey == "EXIT" then tail = table.remove(ordered) end
  for _, item in ipairs(rest) do ordered[#ordered + 1] = item end
  if tail then ordered[#ordered + 1] = tail end
  local out = {}
  for _, item in ipairs(ordered) do
    local k = keyOf(item)
    if not (k and s.hidden[k]) or isMods(k, item.label) then out[#out + 1] = item end
  end
  if #out == 0 then return items end
  return out
end

-- ------- the editor

local function commitOrder(rows)
  local s = load()
  s.order = {}
  for i, row in ipairs(rows) do s.order[i] = row.key end
  save()
end

function M.openEditor(game)
  if not game then return false end
  if #load().known == 0 then
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
                commitOrder(orderedKnown())
                scr.moving = true
                scr.index = i
              elseif choice == "HIDE" then
                st.hidden[row.key] = true
                save()
              elseif choice == "SHOW" then
                st.hidden[row.key] = nil
                save()
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
      rows[i], rows[j] = rows[j], rows[i]
      commitOrder(rows)
      if screen then screen.index = j end
    end,
  })
  return true
end

-- RESET LAYOUT (the editor's last row): back to the game's own order
function M.reset()
  local s = load()
  s.order, s.hidden = {}, {}
  save()
end

-- A menu the game builds for one scene only (the catching tutorial, the
-- Safari stats list) is not the START menu: leave those alone.
local function scenic(game)
  if V.generation ~= 3 then return false end
  local SM = C.engine("src.ui.game3.start_menu")
  if type(SM) ~= "table" then return false end
  return SM._tutorial == true or SM._kind == "safari"
end

function M.install(mod)
  -- Priority 100000 puts this link OUTERMOST, so next() has already run
  -- every other mod's link and the list it hands back is the final one --
  -- rows from Gameshark (priority 500), Highlander and anything else
  -- included.  Without it the editor only ever sees the game's own rows.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then out = items end
    if scenic(game) then return out end
    local ok, applied = pcall(M.apply, out)
    if ok and type(applied) == "table" then return applied end
    if not ok then C.warnOnce("startmenu.apply", applied) end
    return out
  end, 100000)
end

M.keyOf = keyOf

-- for the headless suite: set a layout without driving the editor
function M._setLayout(order, hidden)
  local st = load()
  st.order = order or {}
  st.hidden = {}
  for _, k in ipairs(hidden or {}) do st.hidden[k] = true end
  save()
end

return M
