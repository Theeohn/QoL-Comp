-- QoL Comp / optionsrow: a QOL COMP row in each game's own OPTIONS screen,
-- so the mod is reachable from where a player looks for settings and not
-- only from the mod list.
--
-- The engine runs every game's OPTIONS list through ui.options.rows, so one
-- wrap covers all eleven.  The row's A press opens QoL Comp's OWN toggles
-- page: EDIT START MENU, every toggle, RESET DEFAULTS.  B there comes back to
-- OPTIONS.
--
-- v1.4 opened the Mod Manager and asked it to turn to this mod's page; on
-- some builds the manager came up on its mod list instead, and either way it
-- was the manager rather than the mod's settings.  The page here is drawn by
-- lib/ui (the same screen EDIT START MENU uses) and writes each value the
-- way the manager's own options page does, so the two always agree: a
-- change made in one is what the other shows.
--
-- The row goes on the END of the list: the engine's own ORDER table names
-- the rows it groups and places, and anything it does not name keeps the
-- flat order, which puts a mod's row under MODS at the bottom.

local V = ...
local C = V.core
local UI = V.ui

local M = {}

local LABEL = "QOL COMP"

local function req(name)
  local ok, m = pcall(require, name)
  return ok and type(m) == "table" and m or nil
end

-- how many rows the page has, drawn as the row's value ("15 OPTIONS")
local function value()
  local n = 0
  for _, row in ipairs(V.SCHEMA or {}) do
    if row.key ~= "edit_start_menu" then n = n + 1 end
  end
  if n == 0 then return "OPTIONS" end
  return n .. " OPTIONS"
end

-- ------- reading and writing an option

local function current(row)
  local v = C.opts[row.key]
  if v == nil then v = row.default end
  return v
end

-- The manager's setOption, step for step (src/mods/ManagerState.lua): the
-- loader's live table (what mod.options:get reads), the save's options (what
-- the next boot reads), the options file on disk, then mod.options_changed
-- so every listener -- this mod's own included -- hears about it.
local function write(game, key, v)
  local id = V.mod.id
  local loader = game and game.mods
  if type(loader) ~= "table" then return false end
  loader.modOptions = loader.modOptions or {}
  loader.modOptions[id] = loader.modOptions[id] or {}
  loader.modOptions[id][key] = v
  local save = game.save
  if type(save) == "table" and type(save.options) == "table" then
    save.options.modOptions = save.options.modOptions or {}
    local t = save.options.modOptions
    t[id] = t[id] or {}
    t[id][key] = v
  end
  if type(game.writeOptions) == "function" then
    C.try("optionsrow.persist", game.writeOptions, game)
  end
  local events = loader.events
  if type(events) == "table" and type(events.emit) == "function" then
    C.try("optionsrow.emit", events.emit, events, "mod.options_changed",
      { mod = id, key = key, value = v })
  end
  C.refresh()
  return true
end

-- the value a row shows, and the next one either way
local function shown(row)
  local v = current(row)
  if row.type == "toggle" then
    return (v == true or v == "on" or v == "true") and "ON" or "OFF"
  end
  for _, choice in ipairs(row.choices or {}) do
    if choice[2] == v then return choice[1] end
  end
  return tostring(v)
end

local function stepped(row, dir)
  local v = current(row)
  if row.type == "toggle" then
    return not (v == true or v == "on" or v == "true")
  end
  local list = row.choices or {}
  if #list == 0 then return v end
  local at = 1
  for i, choice in ipairs(list) do
    if choice[2] == v then at = i end
  end
  at = ((at - 1 + dir) % #list) + 1
  return list[at][2]
end

-- ------- the page

local function openPage(game)
  local screen = UI.open(game, {
    title = "QOL COMP",
    hint = "A:CHANGE  B:DONE",
    rows = function()
      local out = {}
      for _, row in ipairs(V.SCHEMA or {}) do
        if row.key == "edit_start_menu" then
          out[#out + 1] = {
            label = row.label,
            onSelect = function() C.try("optionsrow.editor", V.startmenu.openEditor, game) end,
          }
        else
          local function step(_, _, dir) write(game, row.key, stepped(row, dir)) end
          out[#out + 1] = {
            label = row.label,
            right = shown(row),
            key = row.key,
            onSelect = function(scr, i) step(scr, i, 1) end,
            onStep = step,
          }
        end
      end
      out[#out + 1] = {
        label = "RESET DEFAULTS",
        onSelect = function(scr)
          scr:ask({ "RESET", "KEEP" }, function(choice)
            if choice ~= "RESET" then return end
            for _, row in ipairs(V.SCHEMA or {}) do
              if row.key ~= "edit_start_menu" then write(game, row.key, row.default) end
            end
          end)
        end,
      }
      return out
    end,
  })
  M._lastScreen = screen
  return screen
end

-- The Mod Manager, opened on this mod's options page: v1.4's route, kept
-- only for a build whose game object has no loader to write options to.
local function openManager(game)
  local manager
  if V.generation == 3 then
    local MM = req("src.ui.game3.mod_manager")
    if MM and MM.show then
      MM.show({ game = game })
      manager = MM._mgr
    end
  else
    local Screens = req("src.ui.Screens")
    if Screens and Screens.push then
      manager = Screens.push(game, "ManagerState")
    end
  end
  if not (manager and manager.openOptions) then
    C.warnOnce("optionsrow.manager", "the mod manager did not open")
    return
  end
  local entry = manager.byId and manager.byId[V.mod.id]
  if not entry then return end
  manager:openOptions(entry)
  if manager.screen == "options" then manager.backStack = {} end
end

local function open(game)
  game = game or V.game
  if type(game) ~= "table" then return end
  if type(game.mods) == "table" then
    openPage(game)
  else
    openManager(game)
  end
end

function M.install(mod)
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    for _, row in ipairs(out) do
      if type(row) == "table" and row.id == mod.id then return out end
    end
    out[#out + 1] = {
      id = mod.id,
      label = LABEL,
      value = function() return value() end,
      activate = function(g) C.try("optionsrow.open", open, g) end,
    }
    return out
  end)
end

M.LABEL = LABEL
M.value = value
M.open = open
-- for the headless suite
M._write, M._stepped, M._shown = write, stepped, shown

return M
