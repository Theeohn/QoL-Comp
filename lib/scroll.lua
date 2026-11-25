-- QoL Comp / scroll: the SCROLLING toggle (hold the d-pad in a menu and the
-- cursor keeps moving).
--
-- Adapted from WizzStar's G123R HoldToScroll Mod v3.0.2 (MIT licence, its
-- notice below), which already solved the hard part: telling a
-- MENU apart from the overworld, a battle command box, a YES/NO prompt or a
-- minigame on all three generations.
--
-- Two speeds:
--   FAST    14 frames held before the repeat starts, then one step every 8
--   NORMAL  35% slower than FAST: 19 frames, then one step every 11
--
-- Frames are REAL frames: fast-forward runs several logic steps per frame,
-- and input.step fires on each of them, so each step counts 1/N of a frame.

-- ---------------------------------------------------------------------
-- HoldToScroll's licence, which covers the code adapted from it:
--
-- MIT License
--
-- Copyright (c) 2026 WizzStar
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
-- ---------------------------------------------------------------------

local V = ...
local C = V.core

local S = {}

S.SPEEDS = {
  fast = { hold = 14, rate = 8 },
  -- 35% slower, rounded to whole frames: 14 * 1.35 = 18.9, 8 * 1.35 = 10.8
  normal = { hold = 19, rate = 11 },
}

-- the active pair, or nil when SCROLLING is OFF
function S.speed()
  local mode = C.opt("scrolling")
  if mode == true or mode == "on" then mode = "fast" end
  return S.SPEEDS[mode]
end

-- what the older code read; kept for the suite and other mods
S.HOLD_DELAY = S.SPEEDS.fast.hold
S.REPEAT_RATE = S.SPEEDS.fast.rate

local DENY_SCREEN_IDS = {
  -- Gen 1 / Gen 2
  SlotMachine = true, SurfingMinigame = true, BattleMoveSelect = true,
  BattleMoves = true, BattleFight = true, MoveSelect = true,
  UnownPuzzle = true, CardFlip = true,
  -- Gen 3 minigames and d-pad-driven scenes
  slot_machine = true, rse_slot_machine = true, rse_roulette = true,
  rse_roulette_entry = true, rse_berry_blender = true, rs_berry_blender = true,
  rse_contest = true, rse_contest_results = true, whiteout_rush = true,
  cable_car = true, rayquaza_scene = true, trade_scene = true,
  evolution_scene = true, egg_hatch = true, hall_of_fame = true,
  credits = true, rse_credits = true,
}

local GEN3_BATTLE_LIST_MODES = { bag = true, party = true }
local GEN3_BOOT_MENU_PHASES = { menu = true, mystery_gift = true, controls = true }

local function isPromptState(v)
  return type(v) == "string" and (v == "yesno" or v:find("confirm", 1, true) ~= nil)
end

local function isYesNo(obj)
  if type(obj) ~= "table" then return false end
  return obj.kind == "yesno" or isPromptState(obj.mode) or isPromptState(obj.state)
end

local function optedOut(obj)
  return type(obj) == "table" and (obj.noDpadRepeat == true or obj.dpadRepeat == false)
end

-- ------- Gen 3: the field has no StateStack; its UI is engine modules

local g3cache, g3owner = {}, nil

local function g3(game, name)
  if g3owner ~= game then g3cache, g3owner = {}, game end
  local m = g3cache[name]
  if m == nil then
    local ok, res = pcall(require, name)
    m = (ok and type(res) == "table") and res or false
    g3cache[name] = m
  end
  return m or nil
end

local function callBool(t, fname)
  local fn = t and t[fname]
  if type(fn) ~= "function" then return false end
  local ok, res = pcall(fn)
  return ok and res == true
end

local function gen3MenuContext(game)
  if game.phase == "arena" or game.phase == "quest_log" then return false end
  local Choice = g3(game, "src.ui.game3.choice")
  if Choice and callBool(Choice, "isOpen") and Choice.kind == "yesno" then return false end
  if callBool(g3(game, "src.core.game3.minigames.common"), "isActive") then return false end
  local Stack = g3(game, "src.ui.game3.stack")
  local layer = Stack and Stack.top and Stack.top()
  if type(layer) == "table" then
    if layer.id and DENY_SCREEN_IDS[layer.id] then return false end
    if optedOut(layer) or optedOut(layer.mod) or isYesNo(layer.mod) then return false end
    return true
  end
  if callBool(g3(game, "src.core.game3.battle"), "isActive") then
    local Ui = g3(game, "src.core.game3.battle.ui")
    if not Ui or callBool(Ui, "yesNoPending") then return false end
    if not GEN3_BATTLE_LIST_MODES[Ui._mode] then return false end
    if Ui._mode == "party" and isYesNo(g3(game, "src.ui.game3.party_menu")) then return false end
    return true
  end
  if Choice and callBool(Choice, "isOpen") then return true end
  if game.phase == "boot" then
    local boot = game.boot
    return type(boot) == "table" and GEN3_BOOT_MENU_PHASES[boot.phase] == true
  end
  return false
end

-- ------- Gen 1 / Gen 2: StateStack

local function stackTop(game)
  local stack = game.stack
  if type(stack) == "table" and type(stack.top) == "function" then
    local ok, top = pcall(stack.top, stack)
    if ok and type(top) == "table" then return top end
  end
  return nil
end

local function stackMenuContext(game)
  local top = stackTop(game)
  if not top or top.isOverworld or optedOut(top) then return false end
  if top.isMoveSelect or top.isBattleMoveSelect then return false end
  if top.isBattle or top.isBattleState then return false end
  -- ChoiceBox YES/NO (Gen 1 and Gen 2 share it): two labels and onChoose
  if top.onChoose ~= nil and type(top.labels) == "table" and #top.labels == 2 then
    return false
  end
  local id = top.screenId or top.id
  if id and DENY_SCREEN_IDS[id] then return false end
  -- the QoL Comp's own screens step their own cursors
  if top.qolCompScreen then return false end
  return true
end

local function menuContext(game)
  if type(game) ~= "table" then return false end
  if game.generation == 3 then return gen3MenuContext(game) end
  return stackMenuContext(game)
end

local function safeMenuContext(game)
  local ok, res = pcall(menuContext, game)
  return ok and res == true
end

local function isDown(input, dir)
  local ok, down = pcall(input.isDown, input, dir)
  return ok and down == true
end

local function heldDir(input)
  local up, down = isDown(input, "up"), isDown(input, "down")
  if up and not down then return "up" end
  if down and not up then return "down" end
  local left, right = isDown(input, "left"), isDown(input, "right")
  if left and not right then return "left" end
  if right and not left then return "right" end
  return nil
end

local function logicSpeed(game)
  local fn = type(game) == "table" and game.logicSpeed
  if type(fn) ~= "function" then return 1 end
  local ok, speed = pcall(fn, game)
  speed = ok and tonumber(speed)
  if not speed or speed ~= speed or speed < 1 then return 1 end
  return math.floor(speed)
end

local function inject(input, dir)
  if type(input.press) == "function" then
    pcall(input.press, input, dir)
  elseif type(input.injectPress) == "function" then
    pcall(input.injectPress, input, dir)
  elseif type(input.pressQueue) == "table" then
    input.pressQueue[#input.pressQueue + 1] = dir
  end
end

function S.install(mod)
  local lastGame = nil

  -- Gen 1 / Gen 2 ListMenu: hand the engine's own repeat our cadence
  mod.hooks:wrap("ui.list_menu", function(next, opts, ctx)
    opts = next(opts, ctx) or opts
    local feel = S.speed()
    if not feel or type(opts) ~= "table" or optedOut(opts) then return opts end
    local id = opts.screenId or (ctx and ctx.screenId)
    if id and DENY_SCREEN_IDS[id] then return opts end
    if opts.isMoveSelect or opts.isBattleMoveSelect then return opts end
    local speed = logicSpeed(lastGame)
    opts.keyRepeat = true
    opts.repeatDelay = feel.hold * speed
    opts.repeatRate = feel.rate * speed
    opts.qolCompRepeat = true
    return opts
  end)

  local holding, frames, nextAt = nil, 0, 0
  local function reset(hold) holding, frames, nextAt = nil, 0, hold or 0 end

  -- run from main.lua's single input.step wrapper (C.onFrame), before the
  -- engine reads the buttons, exactly where the wrapper of its own ran
  C.onFrame(function(game)
    lastGame = game
    local feel = S.speed()
    if not feel then
      if holding then reset() end
      return
    end
    local input = type(game) == "table" and game.input
    if type(input) ~= "table" or type(input.isDown) ~= "function" then
      if holding then reset() end
      return
    end
    local dir = heldDir(input)
    if not dir or not safeMenuContext(game) then
      if holding then reset() end
      return
    end
    -- a ListMenu running its own repeat (tuned above) owns the hold
    if game.generation ~= 3 then
      local top = stackTop(game)
      if top and top.keyRepeat == true then
        if holding then reset() end
        return
      end
    end
    if dir ~= holding then holding, frames, nextAt = dir, 0, feel.hold end
    frames = frames + 1 / logicSpeed(game)
    if frames >= nextAt - 1e-6 then
      inject(input, dir)
      nextAt = nextAt + feel.rate
      if nextAt <= frames then nextAt = frames + feel.rate end
    end
  end)

  mod.events:on("game.ready", function() g3cache, g3owner = {}, nil; reset() end)
end

S.menuContext = safeMenuContext

return S
