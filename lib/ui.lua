-- QoL Comp / ui: one small list screen, drawn natively on every generation.
--
-- The QoL Comp's own screens (EDIT START MENU, the RELEARN list) are a titled
-- list with a cursor, an optional value column on the right and a small
-- option box (MOVE / HIDE / SHOW) that pops over it.  One model, two
-- renderers: Gen 1/2 draw with the cart's own tile font and box border into
-- the 160x144 screen and live on game.stack; Gen 3 draws with the FRLG font
-- and window chrome into the 240x160 GBA frame and live on the game3 UI
-- stack.  Neither renderer copies another mod's look; both are just the
-- engine's own menu primitives.
--
-- ListScreen.open(game, spec) where spec is
--   title          string, drawn on the top row
--   rows()         function returning { { label, right, onSelect(screen, i) } }
--   onClose()      optional, after B closes the screen
--   onMove(i, d)   optional; when screen.moving is set, up/down call this
--                  instead of moving the cursor (the start-menu MOVE mode)
--   hint           optional bottom-line text
--
-- A row may also carry onStep(screen, i, dir): LEFT / RIGHT call it with
-- dir -1 / 1 (the toggles page uses it to step a value either way).

local V = ...
local C = V.core

local L = {}

local function clampIndex(i, n)
  if n < 1 then return 1 end
  if i < 1 then return n end
  if i > n then return 1 end
  return i
end

-- ------- the model (generation-free)

local Screen = {}
Screen.__index = Screen

function Screen:refresh()
  local ok, rows = pcall(self.spec.rows)
  self.items = (ok and type(rows) == "table") and rows or {}
  if self.index > #self.items then self.index = math.max(1, #self.items) end
end

-- a small option box over the list: options = { "MOVE", "HIDE" }
function Screen:ask(options, cb)
  self.box = { options = options, index = 1, cb = cb }
end

function Screen:handle(pressed)
  if self.box then
    local box = self.box
    if pressed("up") then box.index = clampIndex(box.index - 1, #box.options)
    elseif pressed("down") then box.index = clampIndex(box.index + 1, #box.options)
    elseif pressed("b") then self.box = nil
    elseif pressed("a") then
      self.box = nil
      C.try("ui.box", box.cb, box.options[box.index], box.index)
      self:refresh()
    end
    return
  end
  local n = #self.items
  if self.moving then
    if pressed("up") then C.try("ui.move", self.spec.onMove, self.index, -1)
    elseif pressed("down") then C.try("ui.move", self.spec.onMove, self.index, 1)
    elseif pressed("a") or pressed("b") then self.moving = false end
    self:refresh()
    return
  end
  if pressed("up") then self.index = clampIndex(self.index - 1, n)
  elseif pressed("down") then self.index = clampIndex(self.index + 1, n)
  elseif pressed("b") then self:close()
  elseif pressed("left") or pressed("right") then
    local row = self.items[self.index]
    if row and row.onStep then
      C.try("ui.step", row.onStep, self, self.index, pressed("left") and -1 or 1)
      if self.open then self:refresh() end
    end
  elseif pressed("a") then
    local row = self.items[self.index]
    if row and row.onSelect then C.try("ui.select", row.onSelect, self, self.index) end
    if self.open then self:refresh() end
  end
end

function Screen:visibleRange(rows)
  local n = #self.items
  if self.index <= self.scroll then self.scroll = self.index - 1 end
  if self.index > self.scroll + rows then self.scroll = self.index - rows end
  if self.scroll < 0 then self.scroll = 0 end
  return self.scroll + 1, math.min(n, self.scroll + rows)
end

-- ------- Gen 1 / Gen 2 renderer (StateStack state)

local function open12(game, spec)
  local Font = require("src.render.Font")
  local Theme = require("src.ui.Theme")
  local self = setmetatable({ game = game, spec = spec, index = 1, scroll = 0,
    open = true, isOpaque = true, qolCompScreen = true, isMenu = true }, Screen)
  self:refresh()
  local ROWS = 7
  function self.close(s)
    if not s.open then return end
    s.open = false
    if game.stack:top() == s then game.stack:pop() end
    if spec.onClose then C.try("ui.onClose", spec.onClose) end
  end
  function self.update(s)
    local input = game.input
    if not input then return end
    s:handle(function(btn) return input:wasPressed(btn) end)
  end
  function self.draw(s)
    local g = love.graphics
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 0, 0, 160, 144)
    Font.drawBox(0, 0, 20, 18)
    g.setColor(0, 0, 0, 1)
    Font.draw(spec.title or "", 8, 8)
    local first, last = s:visibleRange(ROWS)
    for i = first, last do
      local row = s.items[i]
      local y = 24 + (i - first) * 16
      Font.draw(tostring(row.label or ""), 16, y)
      if row.right then
        local r = tostring(row.right)
        Font.draw(r, 152 - Font.width(r), y + 8)
      end
      if i == s.index then
        Font.drawCode(s.moving and Theme.cursorHollow or Theme.cursor, 8, y)
      end
    end
    if spec.hint then Font.draw(spec.hint, 8, 136 - 4) end
    if s.box then
      local box = s.box
      local h = #box.options * 2 + 1
      g.setColor(1, 1, 1, 1)
      Font.drawBox(11, 17 - h, 9, h + 1)
      g.setColor(0, 0, 0, 1)
      for i, label in ipairs(box.options) do
        local y = (17 - h + (i - 1) * 2 + 1) * 8
        Font.draw(label, 13 * 8, y)
        if i == box.index then Font.drawCode(Theme.cursor, 12 * 8, y) end
      end
    end
    g.setColor(1, 1, 1, 1)
  end
  game.stack:push(self)
  return self
end

-- ------- Gen 3 renderer (game3 UI stack layer)

local serial = 0

local function open3(game, spec)
  local Stack = require("src.ui.game3.stack")
  local Window = require("src.ui.game3.window")
  local FrlgFont = require("src.ui.game3.frlg_font")
  serial = serial + 1
  local id = "qol_comp_list_" .. serial
  local self = setmetatable({ game = game, spec = spec, index = 1, scroll = 0,
    open = true, qolCompScreen = true }, Screen)
  self:refresh()
  local ROWS = 8
  -- qolCompScreen is what the Gen 3 arm's title-screen fallback looks for
  -- (in a game the HUD drives the top layer, this one included)
  local layer = { isMenu = true, qolCompScreen = true }
  local function se(name)
    pcall(function()
      require("src.core.game3.audio").playSe(require("src.core.game3.se_ids").resolve(name))
    end)
  end
  function self.close(s)
    if not s.open then return end
    s.open = false
    Stack.pop(id)
    se("SE_SELECT")
    if spec.onClose then C.try("ui.onClose", spec.onClose) end
  end
  -- one pass per frame, whoever calls: the HUD in a game, the arm's
  -- fallback on the title screen (lib/gen3.lua installScreenInput)
  local handledFrame = nil
  function layer.handleInput(input)
    input = input or game.input
    if not input then return end
    local frame = V.frame
    if frame ~= nil then
      if handledFrame == frame then return end
      handledFrame = frame
    end
    local any = false
    self:handle(function(btn)
      local hit = input:wasPressed(btn)
      if hit then any = true end
      return hit
    end)
    if any and self.open then se("SE_SELECT") end
  end
  function layer.update() end
  function layer.draw()
    local g = love.graphics
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 0, 0, 240, 160)
    Window.stdFrame(Window.template(1, 1, 28, 18))
    local dark = FrlgFont.COLOR and FrlgFont.COLOR.NORMAL
    Window.printPx(spec.title or "", 16, 10, { colors = dark })
    local first, last = self:visibleRange(ROWS)
    for i = first, last do
      local row = self.items[i]
      local y = 28 + (i - first) * 14
      Window.printPx(tostring(row.label or ""), 24, y, { colors = dark })
      if row.right then
        local r = tostring(row.right)
        local w = (FrlgFont.measure and FrlgFont.measure(r)) or (#r * 6)
        Window.printPx(r, 224 - w, y, { colors = dark })
      end
      if i == self.index then Window.cursorPx(14, y, { colors = dark }) end
    end
    if spec.hint then Window.printPx(spec.hint, 16, 142, { colors = dark }) end
    if self.box then
      local box = self.box
      local h = #box.options * 2
      Window.stdFrame(Window.template(20, 17 - h, 8, h))
      for i, label in ipairs(box.options) do
        local y = (17 - h) * 8 + (i - 1) * 16
        Window.printPx(label, 172, y, { colors = dark })
        if i == box.index then Window.cursorPx(164, y, { colors = dark }) end
      end
    end
    g.setColor(1, 1, 1, 1)
  end
  Stack.push(id, layer, { isMenu = true, hideBelow = true, fullscreen = true })
  return self
end

function L.open(game, spec)
  if type(game) ~= "table" then return nil end
  if V.generation == 3 then return open3(game, spec) end
  if not game.stack then return nil end
  return open12(game, spec)
end

-- for the "nothing to do here" cases: a one-line notice on the same screen
function L.notice(game, text)
  return L.open(game, { title = text, rows = function() return {} end })
end

return L
