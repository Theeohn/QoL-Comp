-- QoL Comp / pcrename: RENAME in the PC as well as the party menu.
--
-- With RENAME on, the menu a Pokemon opens in the PC gets a RENAME row just
-- above CANCEL, on every game, and picks the same naming screen and rules
-- as the party menu's (lib/gen1/2/3.lua A.rename).  None of the three PCs
-- builds that menu through a hook, so each is met where it is assembled:
--
--   Gen 1  BoxMenu's per-mon submenu (WITHDRAW or DEPOSIT / STATS / CANCEL)
--          is a Menu.new over the PC's box list; recognised by that list's
--          kind, and given a fourth row and a box two rows taller
--   Gen 2  BoxMenu:submenuRows (MOVE / WITHDRAW / DEPOSIT, STATS, RELEASE,
--          CANCEL); a list of five rows outgrows the cart's fixed box, so
--          the box is drawn two rows taller and the rows lifted to match
--   Gen 3  box_storage_ui's action menu (the FRLG and RSE PC, and Ruby /
--          Sapphire's own skin); the result is shown in the PC's own message
--          line, so it is never hidden behind the storage screen
--
-- Eggs get no row.  RENAME off leaves every PC exactly as it was.

local V = ...
local C = V.core

local M = {}

local function on() return C.on("rename") end

local function req(name)
  local ok, m = pcall(require, name)
  return ok and type(m) == "table" and m or nil
end

local function isEgg(A, mon)
  return type(mon) ~= "table" or mon.isEgg == true or mon.egg == true
    or (A.isEgg and A.isEgg(mon)) or false
end

-- a failed rename tells the player, never breaks the PC
local function run(A, game, mon, opts)
  local ok, err = pcall(A.rename, game, mon, opts)
  if not ok then
    C.warn("pcrename", err)
    if opts and opts.say then pcall(opts.say, "RENAME isn't available here.") end
  end
end

-- ------- Gen 1

local function installGen1(A)
  local Menu = req("src.ui.Menu")
  local Boxes = req("src.pokemon.Boxes")
  if not (Menu and Boxes) then return end
  local KINDS = { pc_box_withdraw = "box", pc_box_deposit = "party" }
  C.patch(Menu, "new", function(orig, game, items, opts)
    if on() and type(items) == "table" and #items == 3 and type(items[2]) == "table"
        and items[2].keepOpen and type(opts) == "table" and opts.tx == 9 and opts.ty == 10
        and type(game) == "table" and game.stack and game.save then
      local list = game.stack:top()
      local from = type(list) == "table" and KINDS[list.kind]
      if from then
        local src = from == "box" and Boxes.active(game.save) or game.save.party
        local mon = src and src[list.index]
        local row = list.items and list.items[list.index]
        if mon and not isEgg(A, mon) then
          items = { items[1], items[2], {
            label = A.label("RENAME"),
            keepOpen = true,
            onSelect = function()
              run(A, game, mon, { after = function()
                -- the box list printed its names when it opened
                if type(row) == "table" and mon.nickname then row.label = mon.nickname end
              end })
            end,
          }, items[3] }
          local grown = {}
          for k, v in pairs(opts) do grown[k] = v end
          grown.ty, grown.th = 8, 10
          opts = grown
        end
      end
    end
    return orig(game, items, opts)
  end)
end

-- ------- Gen 2

local function installGen2(A)
  local BoxMenu = req("src.ui.gen2.BoxMenu")
  local Chrome = req("src.ui.gen2.Chrome")
  if not (BoxMenu and Chrome) then return end
  local MARK = "QOL_RENAME"

  local function wants(self)
    if not on() then return nil end
    local ok, mon = pcall(BoxMenu.selected, self)
    if ok and mon and not isEgg(A, mon) then return mon end
    return nil
  end

  -- the cart's rows plus RENAME above CANCEL (a fresh list: the cart's own
  -- tables are shared by every PC visit and stay untouched)
  C.patch(BoxMenu, "submenuRows", function(orig, self)
    local rows = orig(self)
    if not wants(self) or type(rows) ~= "table" then return rows end
    local out = {}
    for _, row in ipairs(rows) do
      if row.id == "CANCEL" then out[#out + 1] = { id = MARK, label = MARK } end
      out[#out + 1] = row
    end
    if #out == #rows then out[#out + 1] = { id = MARK, label = MARK } end
    return out
  end)
  C.patch(BoxMenu, "rom", function(orig, self, label)
    if label == MARK then return A.label("RENAME") end
    return orig(self, label)
  end)
  C.patch(BoxMenu, "chooseSubmenu", function(orig, self)
    local ok, rows = pcall(self.submenuRows, self)
    local entry = ok and type(rows) == "table" and rows[self.submenuIndex]
    if entry and entry.id == MARK then
      local mon = wants(self)
      self.phase = nil
      if mon then run(A, self.game, mon) end
      return
    end
    return orig(self)
  end)

  -- The submenu box is `Chrome.box(9, 4, 11, 10)`: room for four rows.  With
  -- five, the box is drawn two rows taller (9, 2, 11, 12) and the rows and
  -- cursor drawn after it lifted two rows to sit inside it.
  C.patch(BoxMenu, "drawPanel", function(orig, self, ...)
    local ok, rows = pcall(self.submenuRows, self)
    if not (self.phase == "submenu" and ok and type(rows) == "table" and #rows > 4) then
      return orig(self, ...)
    end
    -- swapped in for this one draw only, so no other Gen 2 screen pays
    local box, print, cursor = Chrome.box, Chrome.print, Chrome.cursor
    local lifting = false
    Chrome.box = function(x, y, w, h, ...)
      if x == 9 and y == 4 and w == 11 and h == 10 then
        lifting = true
        return box(9, 2, 11, 12, ...)
      end
      return box(x, y, w, h, ...)
    end
    Chrome.print = function(text, x, y, ...)
      if lifting and type(y) == "number" then y = y - 2 end
      return print(text, x, y, ...)
    end
    Chrome.cursor = function(x, y, ...)
      if lifting and type(y) == "number" then y = y - 2 end
      return cursor(x, y, ...)
    end
    local r = { pcall(orig, self, ...) }
    Chrome.box, Chrome.print, Chrome.cursor = box, print, cursor
    if not r[1] then error(r[2], 0) end
  end)
end

-- ------- Gen 3

local function installGen3(A)
  local UI = req("src.ui.game3.box_storage_ui")
  if not UI then return end
  local ACT = "RENAME"
  local augmented = setmetatable({}, { __mode = "k" })

  local function target()
    local t = UI._actionTarget
    local mon = type(t) == "table" and t.mon or nil
    if mon and not isEgg(A, mon) then return mon end
    return nil
  end

  -- give a freshly opened action menu its RENAME row (once per menu)
  local function augment()
    local actions = UI._activeActions
    if UI.mode ~= "action_menu" or type(actions) ~= "table" or augmented[actions] then return end
    augmented[actions] = true
    if not on() or UI.subMode == "move_items" or not target() then return end
    for i, act in ipairs(actions) do
      if act == ACT then return end
      if act == "CANCEL" then table.insert(actions, i, ACT) return end
    end
    actions[#actions + 1] = ACT
  end

  C.patch(UI, "handleInput", function(orig, input, ...)
    local actions = UI._activeActions
    if UI.mode == "action_menu" and type(actions) == "table" and input
        and input.wasPressed and input:wasPressed("a")
        and actions[UI.actionCursor] == ACT then
      local mon = target()
      local back = (UI._actionSource == "party" or UI.drawerOpen) and "party_drawer" or "browse"
      UI.mode = back
      if mon then
        local game = V.game
        run(A, game, mon, { say = function(text)
          UI._status = text
          UI.mode = "message"
        end })
      end
      return
    end
    local a, b = orig(input, ...)
    augment()
    return a, b
  end)

  -- Ruby / Sapphire draw their labels through RsStorage.menuText
  local RsStorage = req("src.ui.game3.rs.storage_policy")
  if RsStorage and RsStorage.menuText then
    C.patch(RsStorage, "menuText", function(orig, act, ...)
      if act == ACT then return A.label and A.label("RENAME") or "RENAME" end
      return orig(act, ...)
    end)
  end

  -- FireRed / LeafGreen / Emerald look each label up in a table of the
  -- cart's own menu strings, which has no RENAME.  The row is drawn as
  -- CANCEL's string, and that one print -- at RENAME's own row -- prints
  -- RENAME instead.  Every position is the one the draw computes itself.
  local Window = req("src.ui.game3.window")
  local function drawWith(orig, ...)
    local actions = UI._activeActions
    local at = nil
    if UI.mode == "action_menu" and type(actions) == "table" then
      for i, act in ipairs(actions) do if act == ACT then at = i end end
    end
    local rs = false
    if at and RsStorage and RsStorage.matches then
      local ok, m = pcall(RsStorage.matches, UI._session)
      rs = ok and m
    end
    if not at or rs or not Window then return orig(...) end
    -- the action menu's own geometry (box_storage_ui.lua, "10. Context
    -- Action Menu Popup")
    local menuTop, textLeft = 5, 114
    if UI._actionSource == "party" or UI.drawerOpen then menuTop, textLeft = 4, 98 end
    local rx, ry = textLeft, (menuTop * 8 + 2) + (at - 1) * 16
    -- swapped in for this one draw only, so no other GBA text pays for it
    local livePx = Window.printPx
    Window.printPx = function(text, x, y, ...)
      if x == rx and y == ry then text = A.label and A.label("RENAME") or "RENAME" end
      return livePx(text, x, y, ...)
    end
    actions[at] = "CANCEL"
    local r = { pcall(orig, ...) }
    actions[at] = ACT
    Window.printPx = livePx
    if not r[1] then error(r[2], 0) end
  end
  C.patch(UI, "draw", drawWith)
  M._augment, M._drawWith = augment, drawWith
end

function M.install(A)
  if type(A) ~= "table" or type(A.rename) ~= "function" then return end
  if V.generation == 1 then C.try("pcrename.gen1", installGen1, A)
  elseif V.generation == 2 then C.try("pcrename.gen2", installGen2, A)
  else C.try("pcrename.gen3", installGen3, A) end
end

return M
