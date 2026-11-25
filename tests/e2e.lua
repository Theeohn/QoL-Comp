-- QoL Comp end-to-end checks for RENAME and RELEARN MOVES.
--
-- Unlike the unit checks in run.lua, these drive each generation's REAL
-- screens with button presses, the way a player does: the game's own party
-- menu, its own submenu, its own naming screen and its own move-learning
-- flow.  A check passes only when the name or the move is actually on the
-- party member afterwards.  Fixture data stands in for a ROM, so a few
-- ROM-only lookups (Gen 3 text, names and learnsets) are stubbed; the
-- screens, the hooks and the mod's code are the real ones.
--
-- Run by tests/run.lua as its last section (it stubs engine modules, so it
-- goes after everything else).

local ctx = ...
local check, eq, MOD = ctx.check, ctx.eq, ctx.MOD
local Sdk = require("tests.modkit.sdk")

local function newInput()
  local input = { pressed = {} }
  function input:wasPressed(b) return self.pressed[b] == true end
  function input:isDown() return false end
  return input
end

local function moveIds(mon)
  local out = {}
  for _, m in ipairs(mon.moves or {}) do
    out[#out + 1] = tostring(type(m) == "table" and m.id or m)
  end
  return table.concat(out, ",")
end


-- What an API 3 mod hooking the party submenu does to every row added below
-- it (src/mods/UnifiedCallbacks.lua menuSelections): the row's callback is
-- handed a COPY of the Pokemon, and edits are copied back only while the
-- callback runs.  RENAME / RELEARN finish later, so before 0.1.3 their
-- edits landed on the copy -- every step ran, nothing changed.  This stand-in
-- reproduces that, so a pass below means the edit reached the real party.
local function addApi3Neighbour(r)
  r.loader.hooks:wrap("ui.party.submenu", function(next, ...)
    local list = next(...)
    if type(list) ~= "table" then return list end
    local out = {}
    for i, row in ipairs(list) do
      if type(row) == "table" and type(row.onSelect) == "function" and not row.action then
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        local inner = row.onSelect
        copy.onSelect = function(mon, game)
          local view = {}
          for k, v in pairs(mon) do view[k] = type(v) == "table" and {} or v end
          for k, v in pairs(mon) do
            if type(v) == "table" then for kk, vv in pairs(v) do view[k][kk] = vv end end
          end
          return inner(view, game)
        end
        out[i] = copy
      else
        out[i] = row
      end
    end
    return out
  end, 1000, "api3_neighbour")
end

-- ======================================================== Gen 1 (R/B/Y)

do
  local r = Sdk.loadMod(MOD, { generation = 1 })
  local I = r.loader.exports.qol_comp._internal
  addApi3Neighbour(r)
  local DATA = r.data
  local text = dofile("tests/fixture_data/text.lua")
  DATA.text = setmetatable(DATA.text or {}, { __index = function(_, k)
    return text[k] or ("TEXT " .. tostring(k)) end })
  local species
  local ids = {}
  for id in pairs(DATA.pokemon) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local def = DATA.pokemon[id]
    if type(def) == "table" and def.learnset and #def.learnset > 1 then species = id break end
  end
  local StateStack = require("src.core.StateStack")
  local PartyMenu = require("src.ui.PartyMenu")
  local Pokemon = require("src.pokemon.Pokemon")
  local input = newInput()
  local game = { input = input, data = DATA }
  game.stack = setmetatable({}, { __index = StateStack })
  game.stack:init()
  local mon = Pokemon.new(DATA, species, 40)
  mon.moves = { mon.moves[#mon.moves] }
  local knownBefore = moveIds(mon)
  game.save = { party = { mon }, inventory = {}, player = { name = "RED" } }
  local Game = require("src.core.Game")
  Game.data, Game.save, Game.stack, Game.input = DATA, game.save, game.stack, input
  I.V.game = game
  I.core.opts.rename, I.core.opts.relearn_moves = true, true
  I.core.refresh()

  local function frame(b)
    input.pressed = {}
    if b then input.pressed[b] = true end
    local top = game.stack:top()
    if top and top.update then pcall(top.update, top, 1 / 60) end
    input.pressed = {}
  end
  local pm = PartyMenu.new(game, {})
  game.stack:push(pm)
  local function choose(id)
    if not pm.submenu then frame("a") end
    for i, it in ipairs(pm.subItems or {}) do if it.id == id then pm.subIndex = i end end
    frame("a")
  end
  local function backToParty()
    for i = 1, 2000 do
      if game.stack:top() == pm then return true end
      frame(i % 3 == 0 and "a" or nil)
    end
    return false
  end

  choose("QOL_RENAME")
  local ns = game.stack:top()
  eq(ns and ns.screenId, "NamingScreen", "e2e gen1 RENAME opens the naming screen")
  eq(ns and #(ns.glyphs or {}), 0, "e2e gen1 the keyboard opens empty, like the Name Rater's")
  frame("a"); frame("right"); frame("a")     -- type two letters
  frame("start"); frame("a")                  -- END
  check(type(mon.nickname) == "string" and #mon.nickname == 2,
    "e2e gen1 the typed name is on the Pokemon (" .. tostring(mon.nickname) .. ")")
  local box = game.stack:top()
  check(box ~= pm and box ~= ns, "e2e gen1 and the player is told")
  local named = mon.nickname
  check(backToParty(), "e2e gen1 and is back on the party menu")
  -- END with nothing typed keeps the name
  choose("QOL_RENAME")
  frame("start"); frame("a")
  eq(mon.nickname, named, "e2e gen1 an empty name keeps the old one")
  backToParty()

  choose("QOL_RELEARN")
  local list = game.stack:top()
  check(list and list.qolCompScreen, "e2e gen1 RELEARN opens the move list")
  frame("a")
  backToParty()
  check(moveIds(mon) ~= knownBefore, "e2e gen1 the picked move is learned (" .. moveIds(mon) .. ")")

  -- SHOP BAG COUNT on Red's real buy list: "×N in bag" on the clerk box's
  -- free second line
  do
    local ListMenu = require("src.ui.ListMenu")
    local Font = require("src.render.Font")
    local drawn = {}
    local realDraw = Font.draw
    Font.draw = function(text, x, y, ...)
      drawn[#drawn + 1] = { text = tostring(text), x = x, y = y }
      return realDraw(text, x, y, ...)
    end
    local itemId
    for id, def in pairs(DATA.items or {}) do
      if type(def) == "table" and def.name then itemId = id break end
    end
    itemId = itemId or "POTION"
    game.save.inventory = { [itemId] = 6 }
    game.save.money = 3000
    local list = ListMenu.new(game, nil, {
      { label = "POTION", value = itemId, price = "\xc2\xa5300" },
      { cancel = true, label = "CANCEL" },
    }, { dialogue = true, itemBox = true, money = function() return 3000 end,
         footer = "Take your time.{DONE}" })
    local okDraw, errDraw = pcall(list.drawItemBox, list)
    check(okDraw, "e2e gen1 the buy list draws (" .. tostring(errDraw) .. ")")
    local hit
    for _, d in ipairs(drawn) do if d.text:find("in bag", 1, true) then hit = d end end
    eq(hit and hit.text, "\xc3\x976 in bag", "e2e gen1 the shop says x6 in bag")
    eq(hit and hit.y, 128, "e2e gen1 on the clerk box's second line")
    -- a two-line clerk text keeps the box to itself
    drawn = {}
    list.footer = "POTION?\nThat will be\vY300. OK?"
    pcall(list.drawItemBox, list)
    hit = nil
    for _, d in ipairs(drawn) do if d.text:find("in bag", 1, true) then hit = d end end
    eq(hit, nil, "e2e gen1 not over a two-line clerk text")
    Font.draw = realDraw
    game.save.inventory = {}
  end

  -- FIELD MOVES in context: Red's own refusals decide, the HM's badge too
  do
    local A, K = I.arm.A, I.common
    local hm = { CUT = "HM01_TEST", FLASH = "HM05_TEST" }
    for move, item in pairs(hm) do
      DATA.items[item] = { id = item, name = item, machine = { kind = "HM", move = move } }
    end
    local def = DATA.pokemon[species]
    def.tmhm = { "CUT", "FLASH" }
    local ow = { map = { def = { tileset = "OVERWORLD" }, id = "ROUTE_1" },
      player = { facingCell = function() return 1, 1 end }, dark = false, cut = "nothing" }
    function ow:useCutFieldMove() return self.cut end
    function ow:useSurfFieldMove() return "no_water" end
    game.overworld = ow
    local function offered()
      local set = {}
      for _, id in ipairs(K.learnableFieldMoves(A, game, mon)) do set[id] = true end
      return set
    end
    game.save.inventory = { [hm.CUT] = 1, [hm.FLASH] = 1 }
    local FieldDefaults = require("src.world.FieldDefaults")
    local gates = FieldDefaults.constant(DATA, "hmBadges") or {}
    local cutBadge = gates.CUT and gates.CUT.badge
    if cutBadge then
      eq(offered().CUT, nil, "e2e gen1 no CUT row without its badge")
      game.save.inventory[cutBadge] = 1
    end
    local flashBadge = gates.FLASH and gates.FLASH.badge
    if flashBadge then game.save.inventory[flashBadge] = 1 end
    eq(offered().CUT, nil, "e2e gen1 no CUT row with nothing to cut")
    ow.cut = "ok"
    eq(offered().CUT, true, "e2e gen1 CUT facing a cuttable tree")
    eq(offered().FLASH, nil, "e2e gen1 no FLASH where it is light")
    ow.dark = true
    eq(offered().FLASH, true, "e2e gen1 FLASH in a dark cave")
    game.save.inventory = {}
    eq(offered().FLASH, nil, "e2e gen1 and only with the HM in the bag")
    game.overworld = nil
  end
  r.release()
end

-- ======================================================== Gen 2 (G/S/C)

do
  local DATA = {
    pokemon = {
      growthRates = { GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5,
        squared = -15, linear = 100, constant = 140 } },
      CYNDAQUIL = { id = "CYNDAQUIL", name = "CYNDAQUIL", dex = 155, index = 155,
        growthRate = "GROWTH_MEDIUM_SLOW", types = { "FIRE", "FIRE" },
        baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
          specialAttack = 60, specialDefense = 50 },
        levelMoves = { { level = 1, move = "TACKLE" }, { level = 1, move = "LEER" },
          { level = 6, move = "SMOKESCREEN" }, { level = 12, move = "EMBER" } } },
    },
    moves = {
      TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 }, LEER = { id = "LEER", name = "LEER", pp = 30 },
      SMOKESCREEN = { id = "SMOKESCREEN", name = "SMOKESCREEN", pp = 20 },
      EMBER = { id = "EMBER", name = "EMBER", pp = 25 }, SCRATCH = { id = "SCRATCH", name = "SCRATCH", pp = 35 },
      GROWL = { id = "GROWL", name = "GROWL", pp = 40 }, CUT = { id = "CUT", name = "CUT", pp = 30 },
    },
    items = {},
    gen2MenuGfx = { border = "x.png", middleLine = "x.png", underLine = "x.png", cursor = "x.png" },
    gen2Diploma = { bgPalette = { { 1, 1, 1 }, { 1, 1, 1 }, { 1, 1, 1 }, { 1, 1, 1 } } },
    gen2Icons = { species = {}, icons = {} },
  }
  local fixture = require("tests.fixture_data.gen2_rom_text_s7_e")
  DATA.text = setmetatable({}, { __index = function(_, k)
    local v = fixture[k]
    if v ~= nil then return v end
    if tostring(k):find("NameInput") then return "A B C D E F G H I" end
    return "TEXT " .. tostring(k)
  end })
  local r = Sdk.loadMod(MOD, { generation = 2, data = DATA })
  local I = r.loader.exports.qol_comp._internal
  addApi3Neighbour(r)
  local Mon = require("src.battle.gen2.Mon")
  local World = require("src.world.gen2.World")
  local Game2 = require("src.core.Game2")
  local StateStack = require("src.core.StateStack")
  local input = newInput()
  local game = setmetatable({ input = input, data = DATA }, { __index = Game2 })
  game.stack = setmetatable({}, { __index = StateStack })
  game.stack:init()
  local mon = Mon.new(DATA, "CYNDAQUIL", 14, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  -- a full moveset: RELEARN has to go through "forget a move?"
  mon.moves = { { id = "TACKLE", pp = 35 }, { id = "SCRATCH", pp = 35 },
    { id = "GROWL", pp = 40 }, { id = "CUT", pp = 30 } }
  game.save = { party = { mon }, player = { name = "KRIS" } }
  game.world = setmetatable({ game = game }, { __index = World })
  I.core.opts.rename, I.core.opts.relearn_moves = true, true
  I.core.refresh()

  local function frame(b)
    input.pressed = {}
    if b then input.pressed[b] = true end
    local top = game.stack:top()
    if top and top.update then pcall(top.update, top, 1 / 60) end
    input.pressed = {}
  end
  -- the field party menu exactly as the START menu opens it
  game:pushStartMenuItem("pokemon")
  local pm = game.stack:top()
  eq(pm and pm.screenId, "Gen2PartyMenu", "e2e gen2 START > POKEMON opens Gold's party menu")
  local function choose(id)
    if not pm.submenu then frame("a") end
    local at
    for i, it in ipairs(pm.submenu.items) do if it.id == id then at = i end end
    for _ = 1, (at or 1) - 1 do frame("down") end
    frame("a")
  end
  local function backToParty()
    for i = 1, 4000 do
      if game.stack:top() == pm then return true end
      frame(i % 3 == 0 and "a" or nil)
    end
    return false
  end

  choose("QOL_RENAME")
  local ns = game.stack:top()
  eq(ns and ns.screenId, "Gen2NamingScreen", "e2e gen2 RENAME opens the Name Rater's screen")
  eq(ns and ns.text, "", "e2e gen2 the keyboard opens empty, like the Name Rater's")
  frame("a"); frame("right"); frame("a")
  frame("start"); frame("a")
  eq(mon.nickname, "AB", "e2e gen2 the typed name is on the Pokemon")
  check(game.stack:top() ~= pm, "e2e gen2 and the player is told")
  check(backToParty(), "e2e gen2 and is back on the party menu")
  choose("QOL_RENAME")
  frame("start"); frame("a")
  eq(mon.nickname, "AB", "e2e gen2 an empty name keeps the old one")
  backToParty()

  choose("QOL_RELEARN")
  local list = game.stack:top()
  eq(list and list.screenId, "QolCompRelearn", "e2e gen2 RELEARN opens the move list")
  check(list and list.list and #list.list.items == 3, "e2e gen2 it lists the three moves not known")
  check(list and pcall(list.draw, list), "e2e gen2 the list draws with Gold's menu pieces")
  frame("down")    -- SMOKESCREEN
  frame("a")
  check(backToParty(), "e2e gen2 the teach flow returns to the party menu")
  check(moveIds(mon):find("SMOKESCREEN", 1, true) ~= nil,
    "e2e gen2 the picked move replaced a forgotten one (" .. moveIds(mon) .. ")")
  eq(#mon.moves, 4, "e2e gen2 still four moves")

  -- SHOP BAG COUNT: "×N in bag" under the highlighted item, clear of the
  -- price, on Gold's real mart list
  do
    local MartMenu = require("src.ui.gen2.MartMenu")
    local Chrome = require("src.ui.gen2.Chrome")
    local printed = {}
    local realPrint = Chrome.print
    Chrome.print = function(text, tx, ty, ...)
      printed[#printed + 1] = { text = tostring(text), tx = tx, ty = ty }
      return realPrint(text, tx, ty, ...)
    end
    local mart = setmetatable({ game = game, scroll = 0,
      entries = { { id = "POTION", name = "POTION", price = 300 },
                  { id = "ULTRA_BALL", name = "ULTRA BALL", price = 1200 } },
      save = { inventory = { POTION = 6, ULTRA_BALL = 12 } } }, { __index = MartMenu })
    local function line(index)
      printed = {}
      mart.index = index
      pcall(MartMenu.drawBuyList, mart)
      for _, p in ipairs(printed) do
        if p.text:find("in bag", 1, true) or p.text:find("^\xc3\x97") then return p end
      end
    end
    local a = line(1)
    eq(a and a.text, "\xc3\x976 in bag", "e2e gen2 the shop says x6 in bag")
    eq(a and a.tx, 2, "e2e gen2 under the item name")
    eq(a and a.ty, 5, "e2e gen2 on the row under the highlighted item")
    local b = line(2)
    eq(b and b.text, "\xc3\x9712 in bag", "e2e gen2 x12 in bag beside a four-digit price")
    check(b and b.tx + #"x12 in bag" - 1 < 12, "e2e gen2 and clear of the price")
    Chrome.print = realPrint
  end

  -- FIELD MOVES in context: the row shows only where Gold's own check says
  -- the move works, and only with its TM/HM in the pack
  do
    local A, K = I.arm.A, I.common
    local Permissions = require("src.world.gen2.Permissions")
    local water
    for c = 0, 255 do if Permissions.isWater(c) then water = c break end end
    DATA.items.TM_HEADBUTT = { id = "TM_HEADBUTT", teaches = "HEADBUTT" }
    DATA.items.TM_TELEPORT = { id = "TM_TELEPORT", teaches = "TELEPORT" }
    DATA.pokemon.CYNDAQUIL.tmhm = { "HEADBUTT", "TELEPORT" }
    local here = { facingColl = 0, playerColl = 0, environment = "ROUTE",
      save = game.save, party = game.save.party, facing = "up" }
    local realWorld = game.world
    game.world = { map = {}, player = {}, fieldContext = function(_, m)
      local ctx = {}
      for k, v in pairs(here) do ctx[k] = v end
      ctx.mon = m
      return ctx
    end }
    local function offered()
      local set = {}
      for _, id in ipairs(K.learnableFieldMoves(A, game, mon)) do set[id] = true end
      return set
    end
    game.save.inventory = {}
    here.facingColl = 0x15     -- a Headbutt tree
    eq(offered().HEADBUTT, nil, "e2e gen2 no HEADBUTT row without the TM")
    game.save.inventory.TM_HEADBUTT = 1
    eq(offered().HEADBUTT, true, "e2e gen2 HEADBUTT facing a Headbutt tree with the TM")
    here.facingColl = 0
    eq(offered().HEADBUTT, nil, "e2e gen2 no HEADBUTT facing open ground")
    game.save.inventory.TM_TELEPORT = 1
    here.environment = "ROUTE"
    eq(offered().TELEPORT, true, "e2e gen2 TELEPORT outdoors")
    here.environment = "CAVE"
    eq(offered().TELEPORT, nil, "e2e gen2 no TELEPORT in a cave")
    check(water ~= nil, "e2e gen2 found a water collision to test with")
    game.world = realWorld
    game.save.inventory = {}
  end
  r.release()
end

-- ======================================================== Gen 3 (R/S/E, FR/LG)

for _, family in ipairs({ "frlg", "rse" }) do
  local r = Sdk.loadMod(MOD, { generation = 3, data = Sdk.gen3Data() })
  local I = r.loader.exports.qol_comp._internal
  I.core.opts.rename, I.core.opts.relearn_moves = true, true
  I.core.refresh()
  -- ROM-only lookups a fixture cannot answer
  local RomText = require("src.core.game3.rom_text")
  local P = require("src.core.game3.pokemon")
  local Profile = require("src.core.game3.profile")
  local saved = { mt = getmetatable(RomText.overrides), moveName = P.moveName,
    displayMonName = P.displayMonName, movePp = P.movePp, learnset = P.learnset,
    family = Profile.family }
  setmetatable(RomText.overrides, { __index = function(_, k)
    return { { t = "text", s = "T" .. tostring(k):gsub("[^%w]", ""):sub(1, 6) } }
  end })
  P.moveName = function(id) return "MOVE" .. tostring(id) end
  P.displayMonName = function(m) return m and m.nickname or "MON" end
  P.movePp = function() return 20 end
  P.learnset = function() return { { 1, 10 }, { 7, 52 }, { 13, 43 } } end
  Profile.family = function() return family end

  local PartyMenu = require("src.ui.game3.party_menu")
  local Stack = require("src.ui.game3.stack")
  local Naming = require("src.ui.game3.naming")
  Stack.clear()
  local input = newInput()
  local mon = { species = 4, speciesId = 4, level = 20, hp = 30, maxHp = 30,
    moves = { 10, 0, 0, 0 }, personality = 1, otId = 1 }
  local session = { party = { mon }, bag = {} }
  pcall(PartyMenu.show, session.party, nil, { session = session })
  local function frame(b)
    input.pressed = {}
    if b then input.pressed[b] = true end
    -- what the HUD does: the top layer gets the input
    local top = Stack.top()
    if top and top.mod and top.mod.handleInput then pcall(top.mod.handleInput, input) end
    if top and top.mod and top.mod.update then pcall(top.mod.update, 1 / 60) end
    input.pressed = {}
  end
  local function choose(label)
    if PartyMenu.mode ~= "action" then frame("a") end
    for i, a in ipairs(PartyMenu.ACTIONS or {}) do
      if type(a) == "table" and a.label == label then PartyMenu.actionCursor = i end
    end
    frame("a")
  end
  local tag = "e2e gen3 " .. family .. " "

  choose("RENAME")
  eq(Stack.top() and Stack.top().id, "naming", tag .. "RENAME opens the naming screen")
  local st = Naming._state
  eq(st and st.template, "NICKNAME", tag .. "with the Name Rater's template")
  eq(st and st.name, "", tag .. "and an empty keyboard")
  if st then st.name = "SPARKY" end
  frame("start"); frame("a")
  for _ = 1, 20 do frame() end
  eq(mon.nickname, "SPARKY", tag .. "the typed name is on the Pokemon")
  eq(PartyMenu.mode, "message", tag .. "and the party menu says so")
  frame("a")
  eq(PartyMenu.mode, "list", tag .. "and goes back to the list")

  choose("RELEARN")
  local top = Stack.top()
  eq(top and top.id, "move_relearner", tag .. "RELEARN opens the Move Relearner")
  local want = (family == "rse") and require("src.ui.game3.rse.move_relearner")
    or require("src.ui.game3.move_relearner")
  check(top and top.mod == want, tag .. "the one this game's relearner NPC opens")
  frame("a")   -- the first move
  frame("a")   -- YES
  for i = 1, 10 do frame(i % 2 == 0 and "a" or nil) end
  check(moveIds(mon):find("52", 1, true) ~= nil, tag .. "the picked move is learned (" .. moveIds(mon) .. ")")

  -- FIELD MOVES in context: the cart's own SetUpFieldMove check, with the
  -- context the party menu gives it
  if family == "frlg" then
    local A = I.arm.A
    local FM = require("src.core.game3.field_moves")
    local Player = require("src.core.game3.player")
    local Collision = require("src.core.game3.collision")
    local realBadge, realWater = FM.hasBadge, Collision.isWater
    local px, py, pf = Player.cellX, Player.cellY, Player.facing
    FM.hasBadge = function() return true end
    Player.cellX, Player.cellY, Player.facing, Player.surfing = 5, 5, "up", false
    local waterAt = {}
    Collision.isWater = function(x, y) return waterAt[x .. "," .. y] == true end
    eq(A.fieldMoveUsableHere(nil, mon, "SURF"), false, tag .. "no SURF facing land")
    waterAt["5,4"] = true
    eq(A.fieldMoveUsableHere(nil, mon, "SURF"), true, tag .. "SURF facing water")
    Player.facing = "down"
    eq(A.fieldMoveUsableHere(nil, mon, "SURF"), false, tag .. "not with the water behind you")
    mon.maxHp, mon.hp = 30, 5
    eq(A.fieldMoveUsableHere(nil, mon, "SOFTBOILED"), false, tag .. "no SOFTBOILED on low HP")
    mon.hp = 30
    eq(A.fieldMoveUsableHere(nil, mon, "SOFTBOILED"), true, tag .. "SOFTBOILED with HP to give")
    FM.hasBadge, Collision.isWater = realBadge, realWater
    Player.cellX, Player.cellY, Player.facing = px, py, pf
  end

  Stack.clear()
  pcall(PartyMenu.close)
  setmetatable(RomText.overrides, saved.mt)
  P.moveName, P.displayMonName, P.movePp, P.learnset = saved.moveName,
    saved.displayMonName, saved.movePp, saved.learnset
  Profile.family = saved.family
  r.release()
end

-- a row that fails says what failed and why
do
  local r = Sdk.loadMod(MOD, { generation = 1 })
  local K = r.loader.exports.qol_comp._internal.common
  local msg = K.failText("RENAME", "./src/ui/x.lua:12: the naming screen did not open")
  check(msg:find("RENAME failed", 1, true) == 1, "a failed row names the action")
  check(msg:find("naming screen", 1, true) ~= nil, "and gives the reason")
  check(not msg:find("x.lua", 1, true), "without the engine's file name")
  for line in (msg .. "\n"):gmatch("([^\n\f]*)[\n\f]") do
    check(#line <= 18, ("and fits the text box (%q)"):format(line))
  end
  r.release()
end
