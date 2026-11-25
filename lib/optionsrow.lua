-- QoL Comp / optionsrow: a QOL COMP row in each game's own OPTIONS screen,
-- so the mod is reachable from where a player looks for settings and not
-- only from the mod list.
--
-- The engine runs every game's OPTIONS list through ui.options.rows, so one
-- wrap covers all eleven.  The row's A press opens the mod manager already
-- on QoL Comp's own options page, and B there comes back to OPTIONS.
--
-- The row goes on the END of the list: the engine's own ORDER table names
-- the rows it groups and places, and anything it does not name keeps the
-- flat order, which puts a mod's row under MODS at the bottom.

local V = ...
local C = V.core

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

-- the manager, opened on this mod's options page
local function open(game)
  local manager
  if V.generation == 3 then
    local MM = req("src.ui.game3.mod_manager")
    if MM and MM.show then
      MM.show({ game = game or V.game })
      manager = MM._mgr
    end
  else
    local Screens = req("src.ui.Screens")
    if Screens and Screens.push then
      manager = Screens.push(game or V.game, "ManagerState")
    end
  end
  if not (manager and manager.openOptions) then
    C.warnOnce("optionsrow.manager", "the mod manager did not open")
    return
  end
  local entry = manager.byId and manager.byId[V.mod.id]
  if not entry then
    C.warnOnce("optionsrow.entry", "QoL Comp is not in the manager's list")
    return
  end
  manager:openOptions(entry)
  -- B leaves the manager instead of walking back through its pages, so the
  -- player lands back on OPTIONS where they pressed A
  if manager.screen == "options" then manager.backStack = {} end
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

return M
