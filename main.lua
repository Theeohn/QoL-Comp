-- QoL Comp: one quality-of-life compilation for all eleven games of the
-- Gen1Recomp Deluxe project -- Red, Blue, Yellow, Gold, Silver, Crystal,
-- Ruby, Sapphire, Emerald, FireRed and LeafGreen.
--
-- Every option lives in this mod's own MOD OPTIONS list (Mod Manager -> QoL
-- Comp -> OPTIONS); nothing is added to the START menu.  EDIT START MENU is
-- pinned to the top of that list, the toggles follow in alphabetical order,
-- and every toggle ships OFF, so installing the mod changes nothing until a
-- toggle is turned on.  The always-on changes (shop bag count, SELECT party
-- switch, bigger bag; on Red/Blue/Yellow the EXP bar, caught icon and the
-- Gen 2 bag) apply from the first boot.
--
-- Layout:
--   lib/core.lua       options cache, reload-safe patching, tiny store
--   lib/decap.lua      the DECAPITALIZATION text engine (pure)
--   lib/scroll.lua     SCROLLING (hold the d-pad in menus)
--   lib/ui.lua         the list screen the mod's own menus use
--   lib/startmenu.lua  EDIT START MENU
--   lib/optionsrow.lua a QOL COMP row in each game's own OPTIONS screen
--   lib/common.lua     toggles whose seam is one hook on every generation
--   lib/gen1.lua       Red / Blue / Yellow seams
--   lib/gen2.lua       Gold / Silver / Crystal seams
--   lib/gen3.lua       Ruby / Sapphire / Emerald / FireRed / LeafGreen seams
--   lib/bag999.lua     the engine's Bag module with a 999 stack (Gen 1/2)
--
-- Each generation file requires only that generation's engine modules, and
-- only on that generation's boot: the loader refuses a cross-generation
-- require, and a lazy, branch-local require is what keeps one entry file
-- loading everywhere.

local mod = ...

local V = { mod = mod }

-- ------- module loader (mod:read + load: a mod folder is not on package.path)

local modules = {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local source = mod:read("lib/" .. name .. ".lua")
  if not source then
    error("qol_comp: lib/" .. name .. ".lua is missing -- reinstall the mod", 0)
  end
  local chunk, err = load(source, "=qol_comp/lib/" .. name)
  if not chunk then
    error("qol_comp: lib/" .. name .. " did not compile: " .. tostring(err), 0)
  end
  local value = chunk(V)
  modules[name] = value
  return value
end


-- ------- which generation is this boot?

local function generation()
  -- the loader stamps the boot's generation on the mod object; GameVersion
  -- is the older answer for engines that predate the field
  local n = tonumber(mod.generation)
  if n == 1 or n == 2 or n == 3 then return n end
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and GameVersion and type(GameVersion.generation) == "function" then
    local n = GameVersion.generation()
    if n == 2 or n == 3 then return n end
  end
  return 1
end

V.generation = generation()
V.game = nil

-- ------- options: EDIT START MENU on top, then A-Z, every toggle OFF
--
-- Gen 3's manager cuts a row's value at eight characters.  Its value column
-- has room for about twelve, so the two LOW HP BEEP labels that are longer
-- are drawn whole by lib/gen3.lua (see LONG_VALUES there); every other
-- choice label is eight or fewer.

local OPEN_HINT = (V.generation == 3) and "OPEN" or "A TO OPEN"

V.SCHEMA = {
  { key = "edit_start_menu", label = "EDIT START MENU", type = "choice",
    default = "open", choices = { { OPEN_HINT, "open" } } },
  -- Gen 1 / Gen 2 only (spliced out below on a Gen 3 boot: the GBA field
  -- is already centred)
  { key = "center_camera", label = "CENTER CAMERA", type = "toggle", default = false },
  { key = "choose_pkmn", label = "CHOOSE PKMN", type = "choice", default = "off",
    choices = { { "OFF", "off" }, { "TRAINER", "trainer" }, { "T+WILD", "both" } } },
  { key = "decap", label = "DECAPITALIZATION", type = "toggle", default = false },
  { key = "fast_pokecenter", label = "FAST POKECENTER", type = "choice", default = "off",
    choices = { { "OFF", "off" }, { "FAST", "fast" }, { "NOW", "now" } } },
  { key = "field_moves", label = "FIELD MOVES", type = "toggle", default = false },
  -- Gen 3 only (spliced out below on a Game Boy boot): full-screen menus
  -- scaled up to the window's height
  { key = "full_screen_menus", label = "FULL SCREEN MENUS", type = "toggle", default = false },
  { key = "gamble_odds", label = "GAMBLE ODDS", type = "choice", default = "normal",
    choices = { { "NORMAL", "normal" }, { "LUCKY", "lucky" } } },
  { key = "hidden_shine", label = "HIDDEN ITEM SHINE", type = "toggle", default = false },
  { key = "keep_tms", label = "KEEP TMS", type = "toggle", default = false },
  -- the one row whose default is not "off": ON (BEEPS) is the normal game
  { key = "low_hp_beep", label = "LOW HP BEEP", type = "choice", default = "on",
    choices = { { "ON (BEEPS)", "on" }, { "OFF (MUTED)", "mute" } } },
  { key = "relearn_moves", label = "RELEARN MOVES", type = "toggle", default = false },
  { key = "rematch", label = "REMATCH", type = "choice", default = "off",
    choices = { { "OFF", "off" }, { "NORMAL", "normal" }, { "TRAINING", "training" } } },
  { key = "rename", label = "RENAME", type = "toggle", default = false },
  { key = "running_shoes", label = "RUNNING SHOES", type = "choice", default = "off",
    choices = { { "OFF", "off" }, { "B TO RUN", "b" } } },
  { key = "scrolling", label = "SCROLLING", type = "choice", default = "off",
    choices = { { "OFF", "off" }, { "NORMAL", "normal" }, { "FAST", "fast" } } },
}

-- rows that only one kind of screen has
local ONLY = { center_camera = "gb", full_screen_menus = "gba" }
for i = #V.SCHEMA, 1, -1 do
  local only = ONLY[V.SCHEMA[i].key]
  if (only == "gb" and V.generation == 3) or (only == "gba" and V.generation ~= 3) then
    table.remove(V.SCHEMA, i)
  end
end
mod.options:define(V.SCHEMA)

function V.data() return V.game and V.game.data end

V.core = V.require("core")
V.core.refresh()
V.decap = V.require("decap")
V.ui = V.require("ui")
V.common = V.require("common")
V.startmenu = V.require("startmenu")
V.scroll = V.require("scroll")
V.optionsrow = V.require("optionsrow")

local C = V.core

mod.events:on("game.ready", function(ev)
  if ev and ev.game then V.game = ev.game end
  C.refresh()
end)

-- ------- EDIT START MENU: the row's A press arrives as an options change.
-- RESET DEFAULTS and a profile load rewrite every row in one go, so the
-- editor only opens when edit_start_menu is the ONLY key that changed this
-- frame.  (The layout itself is reset from inside the editor.)

local pendingEditor, changedThisFrame = false, 0

mod.events:on("mod.options_changed", function(ev)
  if not ev or ev.mod ~= mod.id then return end
  C.refresh()
  changedThisFrame = changedThisFrame + 1
  if ev.key == "edit_start_menu" then pendingEditor = true end
end)

local frame = 0
V.frame = 0

-- the mod's ONLY input.step wrapper: SCROLLING's repeat and the Gen 3
-- title-screen input fallback run from here (C.onFrame), not as wrappers
-- of their own
mod.hooks:wrap("input.step", function(next, game, dt)
  if game then V.game = V.game or game end
  frame = frame + 1
  V.frame = frame
  C.newFrame(frame, game, dt)
  if changedThisFrame > 0 then
    local open = pendingEditor and changedThisFrame == 1
    pendingEditor, changedThisFrame = false, 0
    if open then C.try("startmenu.editor", V.startmenu.openEditor, game or V.game) end
  end
  return next(game, dt)
end, 10)

-- ------- install: shared hooks, then this generation's arm

C.try("scroll.install", V.scroll.install, mod)
C.try("startmenu.install", V.startmenu.install, mod)
C.try("optionsrow.install", V.optionsrow.install, mod)

local armName = (V.generation == 3 and "gen3") or (V.generation == 2 and "gen2") or "gen1"
local okArm, arm = pcall(V.require, armName)
if okArm and arm then
  V.arm = arm
  local ok, err = pcall(arm.install, mod)
  if not ok then C.warnOnce(armName .. ".install", err) end
else
  C.warnOnce(armName .. ".load", arm)
end

-- ------- exports, for other mods and the headless suite

mod.exports.version = "1.4"
mod.exports.generation = V.generation
mod.exports.option = function(key) return C.opt(key) end
mod.exports._internal = {
  core = C, decap = V.decap, common = V.common, startmenu = V.startmenu,
  ui = V.ui, scroll = V.scroll, arm = V.arm, optionsrow = V.optionsrow, V = V,
}
