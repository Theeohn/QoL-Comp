-- QoL Comp / gen2: Gold, Silver and Crystal.
--
-- Gen 2 modules only (src/world/gen2, src/ui/gen2, src/core/Game2), plus the
-- two render modules both Game Boy generations share (TextBox, Camera).
-- Required from install() alone, which main.lua calls on a Gen 2 boot.

local V = ...
local C, K, UI, D = V.core, V.common, V.ui, V.decap

local A = {}
local G = { A = A }

local Strings = require("src.core.Strings")

local function data(game) return (game and game.data) or V.data() end

local function speciesDef(game, mon)
  local d = data(game)
  return mon and d and d.pokemon and d.pokemon[mon.species]
end

-- ------------------------------------------------------------ adapter

local fieldList = nil
function A.fieldMoveList()
  if not fieldList then
    local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
    fieldList = (ok and PartyMenu.FIELD_MOVES) or { "CUT", "FLY", "SURF", "STRENGTH",
      "FLASH", "WATERFALL", "WHIRLPOOL", "DIG", "TELEPORT", "SOFTBOILED",
      "HEADBUTT", "ROCK_SMASH", "MILK_DRINK", "SWEET_SCENT" }
  end
  return fieldList
end

function A.normalizeMove(id)
  return (tostring(id or ""):upper():gsub("^MOVE_", ""):gsub(" ", "_"))
end

-- the open party menu on the game's stack (lib/common.lua K.liveMon reads
-- the picked Pokemon from it: party[index])
function A.isPartyMenu(state)
  local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
  if not ok or type(PartyMenu) ~= "table" then return false end
  return getmetatable(state) == PartyMenu
end

function A.knows(mon, id)
  for _, mv in ipairs(mon.moves or {}) do
    if (type(mv) == "table" and mv.id or mv) == id then return true end
  end
  return false
end

function A.canLearnLevel(game, mon, id)
  local def = speciesDef(game, mon)
  for _, e in ipairs(def and def.levelMoves or {}) do
    if e.move == id then return true end
  end
  return false
end

function A.canLearnMachine(game, mon, id)
  local def = speciesDef(game, mon)
  for _, m in ipairs(def and def.tmhm or {}) do if m == id then return true end end
  return false
end

local machineFor = nil
local function machineItem(game, moveId)
  if not machineFor then
    machineFor = {}
    for itemId, def in pairs(data(game).items or {}) do
      if type(def) == "table" and def.teaches then machineFor[def.teaches] = itemId end
    end
  end
  return machineFor[moveId]
end

function A.holdsMachineFor(game, moveId)
  local item = machineItem(game, moveId)
  local inv = game and game.save and game.save.inventory
  return item ~= nil and inv ~= nil and (tonumber(inv[item]) or 0) > 0
end

function A.isEgg(mon) return mon.isEgg == true or mon.egg == true or mon.species == "EGG" end

function A.rowIsCancel(row) return type(row) == "table" and row.id == "CANCEL" end

function A.rowIsFieldMove(row)
  return type(row) == "table" and (row.fieldMove == true or (row.move ~= nil and row.onSelect == nil))
end

-- Gold's own party-menu verdicts (src/world/gen2/FieldMoves.lua fromMenu,
-- the function World:useFieldMove asks): true only where the move would
-- work now -- CUT / HEADBUTT / ROCK SMASH / WHIRLPOOL facing their tree,
-- rock or whirlpool, SURF facing water, WATERFALL facing one, FLASH in a
-- dark cave, FLY / TELEPORT outdoors, DIG in a cave, with the badges.
-- STRENGTH (which vanilla lets you switch on anywhere) shows facing a
-- boulder, SWEET SCENT where wild Pokemon live.
local SPRITEMOVEDATA_STRENGTH_BOULDER = 0x19

function A.fieldMoveUsableHere(game, mon, id)
  local world = game and game.world
  if not (world and world.map and world.player and world.fieldContext) then return false end
  local FM = require("src.world.gen2.FieldMoves")
  local ctx = world:fieldContext(mon)
  -- FLASH's Aerodactyl-chamber check SETS the wall flag; never from here
  ctx.openAerodactylWall = nil
  if id == "STRENGTH" then
    if ctx.strengthActive then return false end
    local def = ctx.facingObject and ctx.facingObject.def
    if not (def and def.movement == SPRITEMOVEDATA_STRENGTH_BOULDER) then return false end
  elseif id == "SWEET_SCENT" then
    if not FM.canEncounterWildMon(ctx.environment, ctx.playerColl) then return false end
  end
  local res = FM.fromMenu(id, ctx)
  return type(res) == "table" and res.ok == true
end

function A.makeFieldRow(game, id)
  local mdef = data(game).moves and data(game).moves[id]
  return { label = (mdef and mdef.name) or Strings(id), move = id }
end

function A.label(s) return Strings(s) end

-- A message over the party menu.  Gold's own text box (Game2:say) when the
-- game has one, the shared TextBox otherwise.
function A.say(game, text, onDone)
  if game and type(game.say) == "function" then
    local ok = pcall(game.say, game, text, onDone)
    if ok then return end
  end
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, onDone))
end

local function monName(game, mon)
  local def = speciesDef(game, mon)
  return mon.nickname or mon.name or (def and def.name) or tostring(mon.species)
end

-- RENAME: the Name Rater's own screen (World:renameMon) and its rules.
--
--   * the keyboard opens EMPTY, as the Name Rater's does on the cart, so
--     every letter pressed is typed (a ten-letter name pre-filled into a
--     ten-letter field left no room, and pressing letters seemed to do
--     nothing);
--   * END with nothing typed, or the same name again, keeps the old name;
--   * renameMon only hands the typed name back -- the Name Rater script is
--     what writes it (src/script/gen2/Specials.lua H.NameRater) -- so this
--     writes it onto the party member, then says so.
function A.rename(game, mon)
  local world = game and game.world
  if not (world and type(world.renameMon) == "function") then
    error("the naming screen is not available here", 0)
  end
  local before = monName(game, mon)
  local opened = world:renameMon(mon, function(name)
    if type(name) ~= "string" or name:match("^%s*$") or name == before then
      A.say(game, before .. " kept\nits name.")
      return
    end
    mon.nickname = name
    A.say(game, before .. " is now\nnamed " .. name .. "!")
  end, { blank = true })
  if opened == false then error("the naming screen did not open", 0) end
end

function A.relearnable(game, mon)
  local def = speciesDef(game, mon)
  local out, seen = {}, {}
  for _, e in ipairs(def and def.levelMoves or {}) do
    if (tonumber(e.level) or 1) <= (mon.level or 1) and not seen[e.move]
        and not A.knows(mon, e.move) then
      seen[e.move] = true
      out[#out + 1] = { move = e.move, level = e.level }
    end
  end
  return out
end

-- The RELEARN list, drawn with Gold's own menu pieces (src/ui/gen2/Chrome:
-- the palette box, the scrolling List and its cursor) so it looks and reads
-- like every other Gold menu: moves in a box, their level on the right, the
-- prompt in the text box below.  A teaches, B backs out.
local VISIBLE_MOVES = 5

function G.openRelearnList(game, mon, moves, onPick)
  local Chrome = require("src.ui.gen2.Chrome")
  local items = {}
  for _, m in ipairs(moves) do
    local mdef = data(game).moves and data(game).moves[m.move]
    items[#items + 1] = { label = (mdef and mdef.name) or tostring(m.move),
      value = m, right = "Lv" .. tostring(m.level or 1) }
  end
  local screen = { isOpaque = true, isMenu = true, qolCompScreen = true,
    screenId = "QolCompRelearn", game = game }
  local function close()
    if game.stack:top() == screen then game.stack:pop() end
  end
  screen.list = Chrome.List.new({
    items = items, x = 2, y = 2, spacing = 2,
    rows = math.min(VISIBLE_MOVES, #items), wrap = false,
    onChoose = function(value)
      close()
      if onPick then onPick(value) end
    end,
    onCancel = close,
  })
  function screen.wantsFillScale() return true end
  function screen.update(s)
    local input = game.input
    if input then s.list:update(input) end
  end
  function screen.draw(s)
    local list = s.list
    Chrome.clear()
    Chrome.box(0, 0, 20, 12)
    list:draw()
    for row = 1, list.rows do
      local item = list.items[row + list.scroll]
      if item then Chrome.printRight(item.right, 19, list.y + (row - 1) * 2) end
    end
    Chrome.box(0, 12, 20, 6)
    Chrome.print("Teach which move", 1, 14)
    Chrome.print("to " .. monName(game, mon) .. "?", 1, 16)
    love.graphics.setColor(1, 1, 1, 1)
  end
  game.stack:push(screen)
  return screen
end

-- RELEARN: pick from the list, then Gold's own teaching flow
-- (Game2:learnMoveOn, the one TMs and level-ups use: a free slot learns
-- straight away, a full moveset asks which move to forget).
function A.relearn(game, mon)
  if not (game and type(game.learnMoveOn) == "function") then
    error("the move-learning screen is not available here", 0)
  end
  local moves = A.relearnable(game, mon)
  if #moves == 0 then
    A.say(game, monName(game, mon) .. " has no\nmoves to relearn.")
    return
  end
  G.openRelearnList(game, mon, moves, function(m)
    game:learnMoveOn(mon, m.move, function() end)
  end)
end

local function legalLead(mon)
  return type(mon) == "table" and not A.isEgg(mon) and (tonumber(mon.hp) or 0) > 0
end

G.legalLead = legalLead

local MARKER = "qol_comp_choose_lead"

local function findSendout(screen)
  local queue = screen and screen.queue
  if type(queue) ~= "table" then return nil end
  for i, row in ipairs(queue) do
    if type(row) == "table" and row.kind == "sendout" then return i, row end
  end
  return nil
end

G.findSendout = findSendout

local function indexOf(party, mon)
  for i, candidate in ipairs(party or {}) do
    if candidate == mon then return i end
  end
  return nil
end

-- Rebind the provisional initial lead.  Everything the screen cached about
-- the old one is replaced, and the Amulet Coin latch is re-taken, because
-- the battle has not had its first real send-out yet.
local function commitLead(screen, index, mon, sendoutRow)
  local battle = screen.battle
  if not (battle and type(battle.party) == "table") then return false end
  if battle.party[index] ~= mon then return false end
  if battle.player == mon then return true end
  if battle.turn and battle.turn ~= 0 then return false end
  if type(battle.syncSides) ~= "function" then return false end
  local oldIndex = battle.playerIndex or indexOf(battle.party, battle.player)
  if not oldIndex then return false end
  battle.participants = battle.participants or {}
  battle.participants[oldIndex] = nil
  battle.playerIndex = index
  battle.player = mon
  battle.participants[index] = true
  battle:syncSides()
  if type(battle.checkAmuletCoin) == "function" then
    battle.amuletCoin = false
    battle:checkAmuletCoin(mon)
  end
  screen.shownMon = screen.shownMon or {}
  screen.shownMon.player = mon
  screen.shownHp = screen.shownHp or {}
  screen.shownHp.player = mon.hp or 0
  screen.shownLevel = mon.level or 1
  if type(screen.expPixels) == "function" then
    screen.shownExp = screen:expPixels(mon, mon.level, mon.experience)
  end
  if screen.hpAnim and screen.hpAnim.side == "player" then screen.hpAnim = nil end
  screen.expAnim = nil
  if type(screen.name) == "function" then
    sendoutRow.text = "Go! " .. screen:name(mon) .. "!"
  end
  return true
end

function G.installChooseLead(mod)
  local Screens = require("src.ui.Screens")
  local pending = setmetatable({}, { __mode = "k" })
  local attached = setmetatable({}, { __mode = "k" })

  local function kindOf(ev, battle)
    if ev and ev.kind then return ev.kind end
    if battle and battle.wild ~= nil then return battle.wild and "wild" or "trainer" end
    return battle and battle.kind or nil
  end

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if type(battle) ~= "table" or type(battle.party) ~= "table" then return end
    if battle.link then return end
    if not K.chooseWanted(kindOf(ev, battle)) then return end
    if not K.enoughLeads(battle.party, legalLead) then return end
    pending[battle] = true
  end)
  mod.events:on("battle.ended", function(ev)
    if ev and ev.battle then pending[ev.battle] = nil end
  end)

  local function openPicker(screen, ctx)
    local battle = screen.battle
    local game = screen.game or V.game
    if not (battle and game and game.stack) then
      screen.phase = ctx.resumePhase
      return screen:advanceQueue()
    end
    ctx.resumePhase = screen.phase or ctx.resumePhase or "intro"
    screen.phase = "submenu"
    local function resume()
      screen.phase = ctx.resumePhase
      return screen:advanceQueue()
    end
    local function closeAndResume()
      if game.stack:top() == ctx.picker then game.stack:pop() end
      return resume()
    end
    -- a refused pick is told why and asked again, the way the cart does
    local function refuse(text)
      if game.stack:top() == ctx.picker then game.stack:pop() end
      table.insert(screen.queue, 1, { kind = MARKER })
      table.insert(screen.queue, 1, { kind = "message", text = text })
      return resume()
    end
    ctx.picker = Screens.push(game, "Gen2PartyMenu", {
      party = battle.party,
      prompt = "choose",
      onCancel = closeAndResume,
      onChoose = function(index, mon)
        mon = mon or battle.party[index]
        if not mon or battle.party[index] ~= mon then return closeAndResume() end
        if A.isEgg(mon) then return refuse("An EGG can't battle!") end
        if (tonumber(mon.hp) or 0) <= 0 then return refuse("There's no will to battle!") end
        commitLead(screen, index, mon, ctx.sendoutRow)
        return closeAndResume()
      end,
    })
    return ctx.picker
  end

  mod.events:on("screen.pushed", function(ev)
    local screen = ev and ev.state
    local battle = screen and screen.battle
    if not (battle and pending[battle]) then return end
    pending[battle] = nil
    if attached[screen] or screen.tutorial or screen.contest then return end
    if screen.phase and screen.phase ~= "intro" then return end
    if battle.turn and battle.turn ~= 0 then return end
    local index, sendoutRow = findSendout(screen)
    local originalAdvance = screen.advanceQueue
    if not index or type(originalAdvance) ~= "function" then
      C.warnOnce("choose_pkmn.seam", "the Gen 2 send-out row was not found")
      return
    end
    local ctx = { sendoutRow = sendoutRow, resumePhase = screen.phase or "intro" }
    table.insert(screen.queue, index, { kind = MARKER })
    -- only this screen is patched, and only to peek for our own marker
    screen.advanceQueue = function(self, ...)
      local row = self.queue and self.queue[1]
      if type(row) == "table" and row.kind == MARKER then
        table.remove(self.queue, 1)
        return openPicker(self, ctx)
      end
      return originalAdvance(self, ...)
    end
    attached[screen] = true
  end)
end

local function badgeCount(game)
  local save = game.save or {}
  local n = 0
  for _, list in ipairs({ save.johtoBadges, save.kantoBadges, save.badges }) do
    if type(list) == "table" then
      for _, v in pairs(list) do if v then n = n + 1 end end
    end
  end
  if n == 0 then
    for id, v in pairs(save.events or {}) do
      if type(id) == "string" and id:find("^ENGINE_.*BADGE$") and v then n = n + 1 end
    end
  end
  return n
end

local function partyLevels(game)
  local out = {}
  for _, mon in ipairs(game.save and game.save.party or {}) do out[#out + 1] = mon.level end
  return out
end

-- trainer.party hands Gen 2 freshly built Mon records; refreshStats runs on
-- each one after the hook, so a new level (and a cleared HP) is enough
function A.scaleTrainerParty(party, pending)
  local levels = {}
  for i, mon in ipairs(party) do levels[i] = mon.level end
  local scaled = K.scaleLevels(levels, pending.anchor)
  for i, mon in ipairs(party) do
    if scaled[i] ~= mon.level then
      mon.level = scaled[i]
      mon.hp = nil
    end
  end
  return party
end

-- ------------------------------------------------------------ install

function G.install(mod)
  local TextBox = require("src.render.TextBox")
  local Game2 = require("src.core.Game2")
  local World = require("src.world.gen2.World")
  local PartyMenu = require("src.ui.gen2.PartyMenu")
  local BattleState = require("src.ui.gen2.BattleState")

  K.install(mod, A)
  -- the Game Boy font draws "#" as POKé; DECAPITALIZATION spells it out
  D.pokeMacro = true

  -- DECAPITALIZATION, in two places -- see lib/gen1.lua for why.
  -- TextBox.substitute gives the sentence rule a whole message to work on;
  -- Font.encode underneath is what makes the toggle reach everything else
  -- (the PACK, the battle screen, the Pokegear, the mart), and running the
  -- conversion twice is harmless.
  local Font = require("src.render.Font")
  C.patch(TextBox, "substitute", function(orig, game, text)
    local out = orig(game, text)
    if C.on("decap") and type(out) == "string" then
      local ok, conv = pcall(D.convert, out)
      if ok then return conv end
    end
    return out
  end)
  K.installDecapFont(Font, D)

  -- KEEP TMS: every teach path spends the TM through consumeItem
  local function keeps(game, itemId)
    if not C.on("keep_tms") then return false end
    local def = data(game).items and data(game).items[itemId]
    return def ~= nil and def.teaches ~= nil and not tostring(itemId):find("^HM")
  end
  C.patch(Game2, "consumeItem", function(orig, self, itemId, ...)
    if keeps(self, itemId) then return end
    return orig(self, itemId, ...)
  end)
  C.patch(BattleState, "consumeItem", function(orig, self, itemId, ...)
    if keeps(self.game, itemId) then return end
    return orig(self, itemId, ...)
  end)

  -- FAST POKECENTER.  The nurse is the cart's own PokecenterNurseScript, so
  -- the seam is script.command: the text the mode does not want is dropped
  -- and the HEAL/CANCEL question is answered for the player.
  --
  --   FAST  the first line is shown, then the box closes and the heal runs
  --   NOW   nothing is shown at all
  --
  -- Afterwards the player turns around, so the next step does not walk back
  -- into the counter.
  local nurse = nil
  local TEXT_OPS = { writetext = true, farwritetext = true, rawtext = true,
                     repeattext = true, promptbutton = true, waitbutton = true }

  local function isNurse(npc)
    local def = npc and npc.def
    if type(def) ~= "table" then return false end
    local sprite = tostring(def.sprite or def.spriteName or def.spriteId or ""):upper()
    local script = tostring(def.scriptKey or def.script or ""):lower()
    return sprite:find("NURSE", 1, true) ~= nil or script:find("pokecenternurse", 1, true) ~= nil
  end

  mod.hooks:wrap("script.command", function(next, ctx, name, args, cmd)
    local s = nurse
    if not s then return next(ctx, name, args, cmd) end
    local vm = ctx and (ctx.vm or ctx.runner)
    -- the question never reaches the player: answer HEAL
    if name == "yesorno" then
      if vm then vm.scriptVar = 1 end
      return nil
    end
    if TEXT_OPS[name] then
      if s.mode == "fast" and not s.shown then
        -- the greeting, and only the greeting
        s.shown = true
        return next(ctx, name, args, cmd)
      end
      return nil
    end
    if name == "opentext" then
      if s.mode == "now" then return nil end
      if s.shown then return nil end
      return next(ctx, name, args, cmd)
    end
    if name == "closetext" then
      if s.mode == "now" then return nil end
      if s.closed then return nil end
      s.closed = true
      return next(ctx, name, args, cmd)
    end
    return next(ctx, name, args, cmd)
  end)

  local function endNurse(world)
    if not nurse then return end
    nurse = nil
    G.turnPlayerAround(world or (V.game and V.game.world))
  end
  mod.events:on("script.ended", function()
    endNurse(nurse and nurse.world)
  end)
  mod.events:on("map.entered", function() nurse = nil end)

  -- REMATCH and the nurse session both start from the talk
  mod.hooks:wrap("world.talk", function(next, world, npc)
    local fast = C.opt("fast_pokecenter")
    if (fast == "fast" or fast == "now") and isNurse(npc) then
      nurse = { mode = fast, world = world, shown = false, closed = false }
      return next(world, npc)
    end
    local mode = C.opt("rematch")
    local rec = npc and npc.def and npc.def.trainer
    if (mode ~= "normal" and mode ~= "training") or type(rec) ~= "table"
        or not (world and world.trainerBeaten) then
      return next(world, npc)
    end
    local ok, beaten = pcall(world.trainerBeaten, world, rec)
    if not (ok and beaten) then return next(world, npc) end
    local game = world.game or V.game
    game.stack:push(TextBox.new(game, "Would you like a\nrematch?", nil, {
      choice = function(yes)
        if not yes then
          world:talkObject(npc)
          return
        end
        local record = rec
        if world.vm and world.vm.lookupTrainer then
          local okL, looked = pcall(world.vm.lookupTrainer, world.vm, rec.class, rec.member)
          if okL and type(looked) == "table" then
            record = {}
            for k, v in pairs(looked) do record[k] = v end
            record.event = rec.event
          end
        end
        if mode == "training" then
          K.pendingRematch = { training = true,
            anchor = K.trainingAnchor(K.STORY_LEVELS[2], badgeCount(game), partyLevels(game)) }
        end
        local okB, err = pcall(world.startScriptedBattle, world, record, nil,
          function() K.pendingRematch = nil end)
        if not okB then
          K.pendingRematch = nil
          C.warnOnce("rematch.gen2", err)
        end
      end }))
  end)

  -- CHOOSE PKMN.  Gen 2's battle object emits battle.started before its
  -- screen (and so its intro queue) exists, so an eligible battle is only
  -- marked here; the marker goes into the queue when the screen is pushed,
  -- immediately before the one native player send-out.  Choosing rebinds
  -- the provisional lead only -- not Battle:switch, no party reorder.
  -- (Two-stage seam from ZyranCZ's Trainers-Let-You-Choose-Lead-Pokemon.)
  G.installChooseLead(mod)

  -- RUNNING SHOES: the leg cadence keeps pace with the shorter step
  local Player = require("src.world.gen2.Player")
  C.patch(Player, "update", function(orig, self, ...)
    local r1, r2 = orig(self, ...)
    if self.moving and self.qolCompRun then
      local len = tonumber(self.stepFrames) or 16
      if len > 0 and len < 16 then
        self.animClock = (self.animClock or 0) + (16 / len - 1)
      end
    end
    return r1, r2
  end)

  -- HIDDEN ITEM SHINE: on the ground pass (Gold draws at window scale s)
  local okH, HiddenItems = pcall(require, "src.world.gen2.HiddenItems")
  C.patch(World, "drawGround", function(orig, self, s, ...)
    local r1, r2 = orig(self, s, ...)
    if okH and C.on("hidden_shine") and self.map and self.camera then
      pcall(drawShine, HiddenItems, self, s)
    end
    return r1, r2
  end)

  -- GAMBLE ODDS (LUCKY): a spin that drew no bias draws once more; a card
  -- flip that would lose takes the hand's other card when that one wins
  local okS, Slots = pcall(require, "src.ui.gen2.SlotMachine")
  if okS and Slots then
    C.patch(Slots, "initBias", function(orig, current, lucky, random, ...)
      local b = orig(current, lucky, random, ...)
      if C.opt("gamble_odds") == "lucky" and b == Slots.NO_BIAS then
        b = orig(current, lucky, random, ...)
      end
      return b
    end)
  end
  local okF, CardFlip = pcall(require, "src.ui.gen2.CardFlip")
  if okF and CardFlip then
    C.patch(CardFlip, "flip", function(orig, self, ...)
      if C.opt("gamble_odds") == "lucky" and type(self.deck) == "table" then
        pcall(function()
          local played, which = self.played or 0, self.which or 0
          local here = played * 2 + which + 1
          local there = played * 2 + (1 - which) + 1
          local mine, other = self.deck[here], self.deck[there]
          if mine and other
              and CardFlip.payout(self.cursorX, self.cursorY, mine) == 0
              and CardFlip.payout(self.cursorX, self.cursorY, other) > 0 then
            self.deck[here], self.deck[there] = other, mine
          end
        end)
      end
      return orig(self, ...)
    end)
  end

  -- ---------------------------------------------- always on

  -- SELECT quick switch, on the field party menu only
  C.patch(PartyMenu, "update", function(orig, self, dt)
    local input = self.game and self.game.input
    if input and self.wantsSubmenu and not self.battle and not self.submenu
        and not self.itemResult and not self.softboiledFrom
        and input:wasPressed("select") and #self.party > 1 and not self:isCancel() then
      if self.switchFrom then
        self:finishSwitch()
      else
        self:beginSwitch(self.index)
        pcall(self.playSfx, self, "Sfx_Read_Text_2")
      end
      return
    end
    return orig(self, dt)
  end)

  -- SHOP BAG COUNT: under the highlighted item, "×N in bag", on the row the
  -- price sits on.  The price is right-aligned in its 7-column field from
  -- column 10, so the line starts under the name (column 2), or one column
  -- left when a long price needs the room; a price too wide for either gets
  -- the bare "×N".
  local okM, MartMenu = pcall(require, "src.ui.gen2.MartMenu")
  if okM and MartMenu then
    local Chrome = require("src.ui.gen2.Chrome")
    local PRICE_X = 10
    C.patch(MartMenu, "drawBuyList", function(orig, self, ...)
      local r1, r2 = orig(self, ...)
      pcall(function()
        local entry = self.entries and self.entries[self.index]
        if not (entry and entry.id) then return end
        local row = self.index - (self.scroll or 0)
        if row < 1 or row > 4 then return end
        local inv = (self.save and self.save.inventory) or {}
        local n = tonumber(inv[entry.id]) or 0
        local count = "\xc3\x97" .. tostring(n)
        local full = count .. " in bag"
        -- the price's first printed column
        local priceAt = PRICE_X
        if MartMenu.moneyText and entry.price then
          local spaces = MartMenu.moneyText(entry.price):match("^( *)") or ""
          priceAt = PRICE_X + #spaces
        end
        local len = #tostring(n) + 1 + #" in bag"  -- × is one glyph
        local ty = 4 + (row - 1) * 2 + 1
        if 2 + len <= priceAt - 1 then
          Chrome.print(full, 2, ty)
        elseif 1 + len <= priceAt - 1 then
          Chrome.print(full, 1, ty)
        else
          Chrome.print(count, 2, ty)
        end
      end)
      return r1, r2
    end)
  end

  -- BIGGER BAG: the shared Bag with a 999 stack, and a 255-row ITEM pocket
  local Bag = require("src.inventory.Bag")
  local okLoad, Fresh = pcall(function()
    local src = assert(mod:read("lib/bag999.lua"))
    return assert(load(src, "=qol_comp/lib/bag999"))()
  end)
  if okLoad and type(Fresh) == "table" then
    for k, v in pairs(Fresh) do if type(v) == "function" then Bag[k] = v end end
  else
    C.warnOnce("bag999", Fresh)
  end
  mod.events:on("game.ready", function(ev)
    local d = ev and ev.game and ev.game.data
    if d then
      d.constants = d.constants or {}
      if (tonumber(d.constants.bagSize) or 20) < 255 then d.constants.bagSize = 255 end
    end
  end)
end

-- After a heal that skipped its text, face the player away from the nurse.
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

function G.turnPlayerAround(world)
  local player = world and world.player
  if type(player) ~= "table" then return end
  local away = OPPOSITE[player.facing]
  if away then player.facing = away end
end

-- the sparkle, in local pixels around (x, y)
local DARK = { 0.2, 0.2, 0.2 }

function G.drawSparkle(x, y)
  local r = K.sparkleRadius()
  if r then K.drawSparkleAt(x, y, r, 1, DARK) end
end

-- The unfound list for the map on screen, rebuilt at most every 8 frames
-- (and at once on a new map): HiddenItems.unfound walks the map's events
-- and checks a flag for each, which the old shine did every frame.  An
-- item picked up stops sparkling within 8 frames, while its item-found
-- box is still opening.
local shineList, shineDef, shineEvents, shineFrame = nil, nil, nil, -1000

local function unfound(HiddenItems, self)
  local def, events, frame = self.map.def, self.events, V.frame or 0
  if shineList == nil or def ~= shineDef or events ~= shineEvents
      or frame - shineFrame >= 8 or frame < shineFrame then
    shineList = HiddenItems.unfound(def, events) or {}
    shineDef, shineEvents, shineFrame = def, events, frame
  end
  return shineList
end

local function drawShine(HiddenItems, self, s)
  local r = K.sparkleRadius()
  if not r then return end
  local list = unfound(HiddenItems, self)
  if #list == 0 then return end
  local scale = tonumber(s) or 1
  local cam = self.camera
  local g = love.graphics
  local cr, cg, cb, ca = g.getColor()
  for i = 1, #list do
    local item = list[i]
    K.drawSparkleAt(math.floor((item.x * 16 + 8 - cam.x) * scale),
      math.floor((item.y * 16 + 8 - cam.y) * scale), r, scale, DARK)
  end
  g.setColor(cr, cg, cb, ca)
end

return G
