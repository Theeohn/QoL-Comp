-- QoL Comp / gen1: Red, Blue and Yellow.
--
-- Every seam here is a Gen 1 module (src/world/OverworldController,
-- src/battle/BattleState, src/ui/PartyMenu, ...).  They are required only
-- from inside install(), which main.lua calls on a Gen 1 boot alone, so a
-- Gen 2 or Gen 3 boot never names one (the loader refuses cross-generation
-- requires).

local V = ...
local C, K, UI, D = V.core, V.common, V.ui, V.decap

local A = {}
local G = { A = A }

local Strings = require("src.core.Strings")

-- ------------------------------------------------------------ adapter

local FIELD_MOVES = { "CUT", "FLY", "SURF", "STRENGTH", "FLASH",
                      "DIG", "TELEPORT", "SOFTBOILED" }
local FIELD_ACTIONS = { cut = true, fly = true, surf = true, strength = true,
                        flash = true, softboiled = true, escape = true }

local function data(game) return (game and game.data) or V.data() end

local function speciesDef(game, mon)
  local d = data(game)
  return mon and d and d.pokemon and d.pokemon[mon.species]
end

function A.fieldMoveList() return FIELD_MOVES end

function A.normalizeMove(id)
  return (tostring(id or ""):upper():gsub("^MOVE_", ""))
end

-- the open party menu on the game's stack (lib/common.lua K.liveMon reads
-- the picked Pokemon from it: party[index])
function A.isPartyMenu(state)
  local ok, PartyMenu = pcall(require, "src.ui.PartyMenu")
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
  if not def then return false end
  for _, m in ipairs(def.level1Moves or {}) do if m == id then return true end end
  for _, e in ipairs(def.learnset or {}) do if e.move == id then return true end end
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
      if type(def) == "table" and type(def.machine) == "table" and def.machine.move then
        machineFor[def.machine.move] = itemId
      end
    end
  end
  return machineFor[moveId]
end

function A.holdsMachineFor(game, moveId)
  local item = machineItem(game, moveId)
  local inv = game and game.save and game.save.inventory
  return item ~= nil and inv ~= nil and (tonumber(inv[item]) or 0) > 0
end

function A.isEgg() return false end

function A.rowIsCancel(row) return type(row) == "table" and row.action == "cancel" end

function A.rowIsFieldMove(row)
  return type(row) == "table" and (FIELD_ACTIONS[row.action] == true
    or (row.action == nil and row.move ~= nil and row.onSelect == nil))
end

-- the HM's badge (FieldDefaults hmBadges, the table partyKnows reads)
function A.badgeOk(game, id)
  local ok, FieldDefaults = pcall(require, "src.world.FieldDefaults")
  if not ok then return true end
  local gates = FieldDefaults.constant(data(game), "hmBadges") or {}
  local badge = gates[id] and gates[id].badge
  if not badge then return true end
  local inv = game and game.save and game.save.inventory or {}
  return (tonumber(inv[badge]) or (inv[badge] and 1) or 0) > 0
end

-- engine/menus/start_sub_menus.asm's own refusals, as the party menu runs
-- them (src/ui/PartyMenu.lua): true only where the move would work now
local DIG_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true,
                       FACILITY = true, INTERIOR = true }

function A.fieldMoveUsableHere(game, mon, id)
  local ow = game and game.overworld
  if not (ow and ow.map and ow.map.def and ow.player) then return false end
  if id == "CUT" then
    return ow:useCutFieldMove() == "ok"
  elseif id == "SURF" then
    local r = ow:useSurfFieldMove()
    return r == "ok" or r == "dismount"
  elseif id == "FLASH" then
    return ow.dark == true
  elseif id == "FLY" or id == "TELEPORT" then
    local Map = require("src.world.Map")
    local FieldDefaults = require("src.world.FieldDefaults")
    return Map.isOutside(ow.map.def, FieldDefaults.field(data(game), "outsideTilesets")) == true
  elseif id == "DIG" then
    return DIG_TILESETS[ow.map.def.tileset] == true and ow.map.id ~= "AGATHAS_ROOM"
  elseif id == "STRENGTH" then
    if ow.strengthActive then return false end
    local fx, fy = ow.player:facingCell()
    return ow.pushableAtCell ~= nil and ow:pushableAtCell(fx, fy) ~= nil
  elseif id == "SOFTBOILED" then
    local maxHp = mon.stats and mon.stats.hp or mon.maxHp or 0
    return (mon.hp or 0) > math.floor(maxHp / 5)
  end
  return false
end

function A.makeFieldRow(game, id)
  local mdef = data(game).moves and data(game).moves[id]
  return { label = (mdef and mdef.name) or Strings(id), move = id }
end

function A.label(s) return Strings(s) end

function A.say(game, text, onDone)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game, text, onDone))
end

local function monName(game, mon)
  local def = speciesDef(game, mon)
  return mon.nickname or (def and def.name) or tostring(mon.species)
end

-- RENAME: the naming screen the catch prompt uses.  It opens empty, as the
-- Name Rater's does; END with nothing typed, or the same name again, keeps
-- the old name.  The new name is written onto the party member and the
-- player is told which happened.
-- opts (the PC's RENAME row): say(text) reports in the caller's own message
-- line instead of A.say, and after() runs once the name is decided.
function A.rename(game, mon, opts)
  opts = opts or {}
  local say = opts.say or function(text) A.say(game, text) end
  local Screens = require("src.ui.Screens")
  if not (game and game.stack) then error("there is no screen to open the naming screen on", 0) end
  local before = monName(game, mon)
  Screens.push(game, "NamingScreen", {
    title = Strings("NICKNAME?"),
    maxLen = 10,
    mon = mon,
    onDone = function(name)
      if type(name) ~= "string" or name:match("^%s*$") or name == before then
        say(before .. " kept\nits name.")
        if opts.after then opts.after(false) end
        return
      end
      mon.nickname = name
      say(before .. " is now\nnamed " .. name .. "!")
      if opts.after then opts.after(true) end
    end,
  })
end

-- RELEARN: every level-up move at or below the mon's level (and its
-- level-1 moves) that it does not know right now, read from the live
-- species record, so a mod that rewrote the learnset is honoured
function A.relearnable(game, mon)
  local def = speciesDef(game, mon)
  local out, seen = {}, {}
  local function add(move, level)
    if move and not seen[move] and not A.knows(mon, move) then
      seen[move] = true
      out[#out + 1] = { move = move, level = level }
    end
  end
  for _, m in ipairs(def and def.level1Moves or {}) do add(m, 1) end
  for _, e in ipairs(def and def.learnset or {}) do
    if (tonumber(e.level) or 1) <= (mon.level or 1) then add(e.move, e.level) end
  end
  return out
end

local function teach(game, mon, moveId, after)
  local TextBox = require("src.render.TextBox")
  local romText = require("src.core.RomText")
  local mdef = data(game).moves[moveId]
  if not mdef then return after and after(false) end
  if #mon.moves < 4 then
    table.insert(mon.moves, { id = moveId, pp = mdef.pp })
    game.stack:push(TextBox.new(game,
      romText(game.data, "_LearnedMove1Text", nil, monName(game, mon), mdef.name),
      function() if after then after(true) end end,
      TextBox.soundOpts(game, "Get_Item1")))
  else
    require("src.ui.Screens").push(game, "MoveLearnMenu", mon, moveId,
      function(learned) if after then after(learned) end end)
  end
end

function A.relearn(game, mon)
  local moves = A.relearnable(game, mon)
  if #moves == 0 then
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, monName(game, mon) .. "\nhas no moves to\vrelearn."))
    return
  end
  local screen
  screen = UI.open(game, {
    title = "RELEARN WHICH?",
    hint = "A:TEACH  B:BACK",
    rows = function()
      local rows = {}
      for _, m in ipairs(A.relearnable(game, mon)) do
        local mdef = data(game).moves[m.move]
        rows[#rows + 1] = { label = (mdef and mdef.name) or m.move,
          right = "Lv" .. tostring(m.level or 1),
          onSelect = function(scr)
            scr:close()
            teach(game, mon, m.move)
          end }
      end
      return rows
    end,
  })
end

-- CHOOSE PKMN -- see K.chooseWanted.  The pick happens inside the battle's
-- own intro queue, after the opponent is out and immediately before the
-- player's send-out, and it rebinds only the provisional lead: the party is
-- never reordered and this is not a switch.  (Seam from ZyranCZ's
-- Trainers-Let-You-Choose-Lead-Pokemon.)

local function healthy(mon)
  return type(mon) == "table" and (tonumber(mon.hp) or 0) > 0
end

G.healthy = healthy

-- The queue row the player's send-out waits on: the "Go! X!" line, and then
-- the BATTLE_START_SENDOUT wait just before it.  An intro whose shape this
-- does not recognise is left alone.
local function findSeam(battle)
  local queue = battle.queue
  if type(queue) ~= "table" then return nil end
  local goText = battle:sendOutText(battle.player.name)
  local goIndex
  for i = #queue, 1, -1 do
    if queue[i].text == goText then goIndex = i break end
  end
  if not goIndex then return nil end
  local Timing = require("src.core.Timing")
  local insertAt = goIndex
  for i = goIndex - 1, 1, -1 do
    if queue[i].wait == Timing.BATTLE_START_SENDOUT then insertAt = i break end
  end
  return insertAt, queue[goIndex]
end

G.findSeam = findSeam

local openPicker

local function sendOut(battle, mon, goRow)
  if mon == battle.player.mon then return end
  local makeBattler = battle.makeBattler
  if type(makeBattler) ~= "function" then return end
  local replacement = makeBattler(battle.data, mon, true, battle.game.save)
  if not replacement then return end
  local before = battle.player.mon
  if battle.participants then battle.participants[before] = nil end
  battle.player = replacement
  battle:syncSides()
  battle:markParticipant()
  goRow.text = battle:sendOutText(battle.player.name)
end

openPicker = function(battle, goRow)
  return battle:buildScreen("PartyMenu", {
    battle = battle,
    forceSwitch = true,
    onSwitch = function(mon)
      if healthy(mon) then
        sendOut(battle, mon, goRow)
      else
        -- a fainted pick is refused the way the cart refuses one, and the
        -- list comes back up
        battle.nextInsert = 0
        battle:sayNext(battle:romText("_NoWillText", "There's no will\nto fight!"))
        battle:uiNext(function() return openPicker(battle, goRow) end)
      end
    end,
  })
end

local function wantsPicker(battle)
  if type(battle) ~= "table" then return false end
  if battle.safari or battle.demo or battle.ghost or battle.kind == "link" then return false end
  if not (battle.player and battle.player.mon and battle.game and battle.game.save) then
    return false
  end
  if not K.chooseWanted(battle.kind) then return false end
  return K.enoughLeads(battle.game.save.party, healthy)
end

function G.installChooseLead(mod)
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not wantsPicker(battle) then return end
    local insertAt, goRow = findSeam(battle)
    if not insertAt then
      C.warnOnce("choose_pkmn.seam", "the intro's send-out row was not found")
      return
    end
    table.insert(battle.queue, insertAt,
      { ui = function() return openPicker(battle, goRow) end })
  end)
end

local function badgeCount(game)
  local n = 0
  for id, v in pairs(game.save and game.save.inventory or {}) do
    if type(id) == "string" and id:find("BADGE", 1, true) and v then n = n + 1 end
  end
  return n
end

local function partyLevels(game)
  local out = {}
  for _, mon in ipairs(game.save and game.save.party or {}) do out[#out + 1] = mon.level end
  return out
end

-- trainer.party hands Gen 1 the class's own data rows: never edit them,
-- return copies at the scaled levels
function A.scaleTrainerParty(rows, pending)
  local levels = {}
  for i, row in ipairs(rows) do levels[i] = row.level end
  local scaled = K.scaleLevels(levels, pending.anchor)
  local out = {}
  for i, row in ipairs(rows) do
    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    copy.level = scaled[i]
    out[i] = copy
  end
  return out
end

-- ------------------------------------------------------------ helpers

-- a state that shows nothing and finishes on the next frame: the stand-in
-- for a nurse text box FAST/NOW skips
local function skipState(game, finish)
  local st = { isOpaque = false, qolCompSkip = true }
  function st.update(s)
    if game.stack:top() == s then game.stack:pop() end
    if finish then finish() end
  end
  function st.draw() end
  return st
end

-- After a heal that skipped its text, face the player away from the nurse
-- so the next step does not re-trigger the counter.
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

-- FAST shows the nurse's first line only.  A first visit appends "SHALL WE
-- HEAL YOUR POKéMON?" as a second page (the \f page break), and that page is
-- the question the mode is removing, so it is dropped with it.
function G.greetingPage(text)
  text = tostring(text or "")
  return text:match("^(.-)\f") or text
end

function G.turnPlayerAround(ow)
  local player = ow and ow.player
  if type(player) ~= "table" then return end
  local away = OPPOSITE[player.facing]
  if away then player.facing = away end
end

local DARK = { 0.2, 0.2, 0.2 }

local function drawSparkle(x, y)
  local r = K.sparkleRadius()
  if r then K.drawSparkleAt(x, y, r, 1, DARK) end
end
G.drawSparkle = drawSparkle

-- the save's hiddenTaken key for an item, built once per item
local takenKeys = setmetatable({}, { __mode = "k" })

-- the ground-pass sparkles (no closure, no graphics push: only the colour
-- is touched, and it is put back)
local function drawShine(Game, self, camX, camY)
  local r = K.sparkleRadius()
  if not r then return end
  local hidden = Game.data.field and Game.data.field.hiddenItems
  local mapId = self.map.id
  local list = hidden and hidden[mapId]
  if not list or #list == 0 then return end
  local taken = Game.save.hiddenTaken or {}
  local ox, oy = -math.floor(camX), -math.floor(camY)
  local g = love.graphics
  local cr, cg, cb, ca = g.getColor()
  for i = 1, #list do
    local item = list[i]
    local key = takenKeys[item]
    if not key or key[1] ~= mapId then
      key = { mapId, mapId .. "_" .. item.x .. "_" .. item.y }
      takenKeys[item] = key
    end
    if not taken[key[2]] then
      K.drawSparkleAt(item.x * 16 + ox + 8, item.y * 16 + oy + 8, r, 1, DARK)
    end
  end
  g.setColor(cr, cg, cb, ca)
end

-- ------------------------------------------------------------ install

function G.install(mod)
  local Game = require("src.core.Game")
  local TextBox = require("src.render.TextBox")
  local OW = require("src.world.OverworldController")
  local BattleState = require("src.battle.BattleState")
  local PartyMenu = require("src.ui.PartyMenu")
  local ListMenu = require("src.ui.ListMenu")
  local Font = require("src.render.Font")

  K.install(mod, A)
  -- the Game Boy font draws "#" as POKé; DECAPITALIZATION spells it out
  D.pokeMacro = true

  -- DECAPITALIZATION, in two places on purpose.
  --
  -- TextBox.substitute sees a WHOLE message before the box wraps it, which
  -- is the only place the sentence rule can be applied correctly: a row
  -- that begins mid-sentence must not get a capital, and only the whole
  -- string shows where the sentences are.
  --
  -- Font.encode is the catch-all underneath, and it is what makes the
  -- toggle work everywhere -- menu labels, battle lines, the shop, the
  -- status screen, any text that never passed through a text box.  Every
  -- drawn, measured and counted string funnels through encode (Font.width
  -- and Font.draw both route through it once it is replaced), so the
  -- glyphs, the widths and the wrapping all see the same text.  Converting
  -- is idempotent, so a message the seam above already converted passes
  -- through here unchanged and keeps its sentence capitals.
  C.patch(TextBox, "substitute", function(orig, game, text)
    local out = orig(game, text)
    if C.on("decap") and type(out) == "string" then
      local ok, conv = pcall(D.convert, out)
      if ok then return conv end
    end
    return out
  end)
  -- installed only while the toggle is on: replacing encode makes the engine
  -- measure text uncached from then on, so an off toggle costs nothing
  K.installDecapFont(Font, D)

  -- KEEP TMS: "learn" is the result that spends the TM; "learnkept" is the
  -- HM's.  Every teach path (free slot, forget screen, battle) reads it.
  local ItemEffects = require("src.inventory.ItemEffects")
  C.patch(ItemEffects, "use", function(orig, ...)
    local r, p, e = orig(...)
    if r == "learn" and C.on("keep_tms") then r = "learnkept" end
    return r, p, e
  end)

  -- FAST POKECENTER.
  --
  -- The nurse is the overworld's own nurseHeal, a chain of text boxes with
  -- the HEAL/CANCEL prompt on the first one.  While a session is open the
  -- boxes it does not want are swapped for a state that draws nothing and
  -- finishes on the next frame, so the rest of the cart's sequence (the
  -- party heal, the ball machine, the follower beats) runs untouched.
  --
  --   FAST  the greeting is shown, and nothing else -- answering it starts
  --         the heal, so no HEAL/CANCEL prompt is drawn at all
  --   NOW   no text at all; talking to her starts the heal
  --
  -- Afterwards the player turns around, so walking away does not step
  -- straight back into her.
  local nurse = nil
  C.patch(OW, "nurseHeal", function(orig, self, onDone, npc)
    local mode = C.opt("fast_pokecenter")
    if (mode ~= "fast" and mode ~= "now")
        or (self.map and self.map.id == "PEWTER_POKECENTER" and self.pikachuPewterSleepScene) then
      nurse = nil
      return orig(self, onDone, npc)
    end
    local session = { mode = mode, ow = self, greeted = false }
    nurse = session
    return orig(self, function(...)
      if nurse == session then nurse = nil end
      G.turnPlayerAround(self)
      if onDone then return onDone(...) end
    end, npc)
  end)
  C.patch(TextBox, "new", function(orig, game, text, onDone, opts)
    local s = nurse
    if not s then return orig(game, text, onDone, opts) end
    local choice = type(opts) == "table" and opts.choice or nil
    if choice and not s.greeted then
      s.greeted = true
      if s.mode == "now" then
        -- nothing shown: answer HEAL on the next frame
        return skipState(game, function() choice(true) end)
      end
      -- FAST: the greeting alone, no prompt.  Reading it IS the answer.
      local head = G.greetingPage(text)
      local plain = {}
      if type(opts) == "table" then
        for k, v in pairs(opts) do plain[k] = v end
      end
      plain.choice, plain.choiceLabels, plain.choiceBox = nil, nil, nil
      return orig(game, head, function() choice(true) end, plain)
    end
    if choice then
      -- any later prompt in the sequence answers itself
      return skipState(game, function() choice(true) end)
    end
    if s.greeted or s.mode == "now" then return skipState(game, onDone) end
    return orig(game, text, onDone, opts)
  end)
  mod.events:on("map.entered", function() nurse = nil end)

  -- RUNNING SHOES: the leg cadence keeps pace with the shorter step
  local Player = require("src.world.Player")
  C.patch(Player, "update", function(orig, self, ...)
    local r1, r2 = orig(self, ...)
    if self.moving and self.qolCompRun then
      local len = tonumber(self.stepFramesCur or self.stepFrames) or 16
      if len > 0 and len < 16 then
        self.animClock = (self.animClock or 0) + (16 / len - 1)
      end
    end
    return r1, r2
  end)

  -- REMATCH: A on a beaten trainer asks first; NO is the ordinary talk
  local function startRematch(ow, npc, training)
    local game = Game
    local d = npc.def
    local header = game.data:trainerHeader(ow.map.def.label, d.index)
    local wonText = header and header.won and game.data.text[header.won]
    local function startBattle(options)
      if training then
        K.pendingRematch = { training = true,
          anchor = K.trainingAnchor(K.STORY_LEVELS[1], badgeCount(game), partyLevels(game)) }
      end
      local ok, battle = pcall(BattleState.newTrainer, game, d.trainerClass, d.trainerParty, options)
      K.pendingRematch = nil
      if not ok or not battle then
        C.warnOnce("rematch.gen1", battle)
        npc.frozen = false
        return
      end
      battle.endBattleText = wonText and TextBox.substitute(game, wonText) or nil
      battle.onFinish = function(result)
        ow:afterBattle(result, battle)
        npc.frozen = false
      end
      pcall(ow.playTrainerMusic, ow, d.trainerClass)
      pcall(OW.prepareTrainerBattleMusic, game.data, d.trainerClass, d.trainerParty)
      ow:pushBattle(battle, npc)
    end
    OW.prepareTrainerBattle(game, { trainerClass = d.trainerClass,
      partyIndex = d.trainerParty or 1, mapId = ow.map.id, npcId = npc.id },
      startBattle, function() npc.frozen = false end)
  end

  mod.hooks:wrap("world.talk", function(next, ow, npc)
    local mode = C.opt("rematch")
    if mode ~= "normal" and mode ~= "training" then return next(ow, npc) end
    if not (type(npc) == "table" and npc.def and npc.def.trainerClass
        and type(ow) == "table" and ow.trainerDefeated) then
      return next(ow, npc)
    end
    local ok, beaten = pcall(ow.trainerDefeated, ow, npc)
    if not (ok and beaten) then return next(ow, npc) end
    npc.frozen = true
    pcall(ow.makeNpcFacePlayer, ow, npc)
    Game.stack:push(TextBox.new(Game, "Would you like a\nrematch?", nil, {
      choice = function(yes)
        if yes then
          startRematch(ow, npc, mode == "training")
        else
          npc.frozen = false
          ow:talkTo(npc)
        end
      end }))
  end)

  -- HIDDEN ITEM SHINE: drawn on the ground pass, under the sprites
  C.patch(OW, "drawShipAnim", function(orig, self, camX, camY)
    local r = orig(self, camX, camY)
    if C.on("hidden_shine") and self.map then
      pcall(drawShine, Game, self, camX, camY)
    end
    return r
  end)

  -- GAMBLE ODDS (LUCKY): a losing spin's luck roll gets a second draw,
  -- which doubles the chance a spin can pay out
  local okSlots, SlotMachine = pcall(require, "src.ui.SlotMachine")
  if okSlots and SlotMachine then
    C.patch(SlotMachine, "setFlags", function(orig, self)
      local r = orig(self)
      if C.opt("gamble_odds") == "lucky" and not self.canWin and not self.sevenBar
          and (self.allowMatchesCounter or 0) == 0 then
        r = orig(self)
      end
      return r
    end)
  end

  -- ---------------------------------------------- always on

  -- CAUGHT ICON: Gen 1 draws the owned ball when asked to
  mod.hooks:wrap("battle.caught_marker_visible", function(next, battle)
    next(battle)
    return true
  end)

  G.installChooseLead(mod)
  G.installExpBar(BattleState, PartyMenu)
  G.installPartySelect(PartyMenu)
  G.installShopCount(ListMenu, Font)
  G.installBag(mod, ListMenu)
end

-- ------------------------------------------------------------ EXP bar

local function computeExpFraction(game, mon)
  local d = data(game)
  local def = d.pokemon and d.pokemon[mon.species]
  local cap = (d.constants and d.constants.levelCap) or 100
  local level = mon.level or 1
  if level >= cap then return 1 end
  local Growth = require("src.pokemon.Growth")
  local rate = (def and def.growthRate) or "MEDIUM_FAST"
  local ok, lo = pcall(Growth.expForLevel, rate, level, d.growth_rates)
  local ok2, hi = pcall(Growth.expForLevel, rate, level + 1, d.growth_rates)
  if not (ok and ok2) or not lo or not hi or hi <= lo then return 0 end
  return C.clamp(((mon.exp or lo) - lo) / (hi - lo), 0, 1)
end
-- The bars are drawn every frame on the battle screen and the party menu,
-- but a mon's fraction only moves when its exp, level or species does: the
-- answer is kept per mon (weakly, so a released mon is not held) with the
-- values it was worked out from, and worked out again when any changes.
local expMemo = setmetatable({}, { __mode = "k" })

local function expFraction(game, mon)
  local m = expMemo[mon]
  local d = data(game)
  if m and m.exp == mon.exp and m.level == mon.level and m.species == mon.species
      and m.data == d then
    return m.f
  end
  local f = computeExpFraction(game, mon)
  if not m then m = {}; expMemo[mon] = m end
  m.exp, m.level, m.species, m.data, m.f = mon.exp, mon.level, mon.species, d, f
  return f
end
G.expFraction = expFraction

local okPFX, PaletteFX = pcall(require, "src.render.PaletteFX")
if not okPFX then PaletteFX = nil end

local function drawBattleExp(self)
  local f = expFraction(self.game, self.player.mon)
  local w = math.floor(f * 67)
  if w <= 0 then return end
  local wide = self.wideLayout and self:wideLayout()
  local right = wide and 291 or 147
  local g = love.graphics
  local cr, cg, cb, ca = g.getColor()
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", right - w, 89, w, 2)
  if PaletteFX and PaletteFX.markTrueColor then
    pcall(PaletteFX.markTrueColor, right - w, 89, w, 2)
  end
  g.setColor(cr, cg, cb, ca)
end

local function drawPartyExp(self, PartyMenu)
  local party = self.party or self.game.save.party
  if type(party) ~= "table" then return end
  local g = love.graphics
  local cr, cg, cb, ca = g.getColor()
  g.setColor(0, 0, 0, 1)
  for i = 1, #party do
    local w = math.floor(expFraction(self.game, party[i]) * 48)
    if w > 0 then g.rectangle("fill", 48, PartyMenu.entryY(i) + 15, w, 1) end
  end
  g.setColor(cr, cg, cb, ca)
end

function G.installExpBar(BattleState, PartyMenu)
  C.patch(BattleState, "drawHUDs", function(orig, self, slide, ...)
    local r1, r2 = orig(self, slide, ...)
    if (slide == nil or slide == 0) and self.player and self.player.mon
        and not (self.safari or self.demo or self.showPlayerBack) then
      pcall(drawBattleExp, self)
    end
    return r1, r2
  end)
  C.patch(PartyMenu, "draw", function(orig, self, ...)
    local r1, r2 = orig(self, ...)
    if self.tmhm or self.evoStone then return r1, r2 end
    pcall(drawPartyExp, self, PartyMenu)
    return r1, r2
  end)
end

-- ------------------------------------------------------------ SELECT switch

function G.installPartySelect(PartyMenu)
  C.patch(PartyMenu, "update", function(orig, self, dt)
    local input = self.game and self.game.input
    local plain = input and not (self.battle or self.pickOnly or self.tmhm or self.itemUse
      or self.evoStone or self.forceSwitch or self.submenu or self.heal
      or self.swapAnim or self.softboiledFrom)
    if plain then
      local party = self.party or self.game.save.party
      if self.swapFrom and input:wasPressed("b") then
        self.swapFrom = nil
        self.blink = 0
        return
      end
      if input:wasPressed("select") and #party > 1 then
        if not self.swapFrom then
          self.swapFrom = self.index
          pcall(function() require("src.core.Sound").play(self.game.data, "Press_AB") end)
        else
          local from = self.swapFrom
          self.swapFrom = nil
          if from ~= self.index then
            party[from], party[self.index] = party[self.index], party[from]
          end
          self.swapAnim = { blank = { [from] = true }, to = self.index, phase = 1, frames = 0 }
          pcall(function()
            self.swapAnim.src = require("src.core.Sound").play(self.game.data, "Swap")
          end)
        end
        return
      end
    end
    return orig(self, dt)
  end)
end

-- ------------------------------------------------------------ shop count

function G.installShopCount(ListMenu, Font)
  C.patch(ListMenu, "drawItemBox", function(orig, self, ...)
    -- BIGGER BAG: three-digit stacks print as one right-aligned "×999"
    local moved = {}
    for _, item in ipairs(self.items or {}) do
      if type(item.count) == "number" and item.count >= 100 and not item.right then
        item.right, item.count = "\xc3\x97" .. tostring(item.count), nil
        moved[#moved + 1] = item
      end
    end
    local r1, r2 = orig(self, ...)
    for _, item in ipairs(moved) do
      item.count = tonumber((item.right:gsub("\xc3\x97", "")))
      item.right = nil
    end
    -- SHOP BAG COUNT: "×N in bag" for the highlighted item.  Gen 1's item
    -- rows are too narrow for it beside a price, so it goes on the clerk's
    -- box below the list: the browsing line ("Take your time.") is one
    -- line long, and the count takes the second.  Any two-line text there
    -- (a price confirmation) keeps the box to itself.
    if self.money and self.dialogue then
      pcall(function()
        local item = self.items and self.items[self.index]
        if not (item and item.price and item.value) then return end
        if not G.oneLineFooter(self.footer) then return end
        local inv = self.game.save.inventory or {}
        local n = tonumber(inv[item.value]) or 0
        love.graphics.push("all")
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw("\xc3\x97" .. tostring(n) .. " in bag", 8, 128)
        love.graphics.pop()
      end)
    end
    return r1, r2
  end)
end

-- the clerk's text is one line: no line break once its {TOKENS} are gone
function G.oneLineFooter(text)
  if type(text) ~= "string" or text == "" then return false end
  local plain = text:gsub("{[^}]*}", ""):gsub("%s+$", "")
  return not plain:find("[\n\v\f\r]")
end

-- ------------------------------------------------------------ bag

-- GEN 2 BAG: with Gold, Silver or Crystal imported, the Gen 1 bag gets the
-- Gen 2 PACK's four pockets.  Each item is sorted into the pocket Gen 2
-- keeps it in (read from the imported Gen 2 data when the same item exists
-- there), and LEFT/RIGHT turns the pocket.
local POCKETS = { "ITEM", "BALL", "KEY_ITEM", "TM_HM" }
local POCKET_NAMES = { ITEM = "ITEMS", BALL = "BALLS", KEY_ITEM = "KEY ITEMS", TM_HM = "TM/HM" }

local gen2Items = nil

local function pocketFor(game, id)
  local def = data(game).items[id] or {}
  if gen2Items and gen2Items[id] then return gen2Items[id] end
  if def.machine or tostring(id):find("^TM") or tostring(id):find("^HM") then return "TM_HM" end
  if def.keyItem then return "KEY_ITEM" end
  if def.ball or tostring(id):find("BALL$") then return "BALL" end
  return "ITEM"
end

function G.detectGen2(mod)
  if not (mod.datasets and mod.datasets.open) then return false end
  for _, version in ipairs({ "crystal", "gold", "silver" }) do
    local ok, view = pcall(mod.datasets.open, mod.datasets, version)
    if ok and view and view.content and view.content.items then
      gen2Items = {}
      pcall(function()
        for id, rec in view.content.items:each() do
          if type(rec) == "table" and type(rec.pocket) == "string" then
            gen2Items[id] = rec.pocket
          end
        end
      end)
      return true
    end
  end
  return false
end

local function pocketRows(game, pocket, cancelLabel)
  local Bag = require("src.inventory.Bag")
  local rows = {}
  -- Bag.swap takes positions in the FULL row list (split stacks included),
  -- so each pocket row remembers where it sits there
  for pos, row in ipairs(Bag.rows(game.save, game.data)) do
    if pocketFor(game, row.id) == pocket then
      local def = game.data.items[row.id]
      local unsellable = (def and def.keyItem) or tostring(row.id):find("^HM_") ~= nil
      rows[#rows + 1] = { value = row.id, label = def and def.name or row.id,
        count = (not unsellable) and row.count or nil, slot = row.slot,
        stack = row.count, orderIndex = pos }
    end
  end
  rows[#rows + 1] = { cancel = true, label = cancelLabel or "CANCEL" }
  return rows
end

function G.installBag(mod, ListMenu)
  -- BIGGER BAG: a 255-row item pocket (the engine's own bagSize rule) and
  -- 999 to a stack (bag999.lua)
  local Bag = require("src.inventory.Bag")
  local okLoad, Fresh = pcall(function()
    local src = assert(mod:read("lib/bag999.lua"))
    return assert(load(src, "=qol_comp/lib/bag999"))()
  end)
  if okLoad and type(Fresh) == "table" then
    for k, v in pairs(Fresh) do
      if type(v) == "function" then Bag[k] = v end
    end
  else
    C.warnOnce("bag999", Fresh)
  end
  mod.events:on("game.ready", function(ev)
    local game = ev and ev.game
    local d = game and game.data
    if d then
      d.constants = d.constants or {}
      if (tonumber(d.constants.bagSize) or 20) < 255 then d.constants.bagSize = 255 end
    end
  end)

  local hasGen2 = G.detectGen2(mod)
  if not hasGen2 then return end

  local BagMenu = require("src.ui.BagMenu")
  local Font = require("src.render.Font")
  C.patch(BagMenu, "new", function(orig, game, opts)
    local list = orig(game, opts)
    if type(list) ~= "table" then return list end
    local cancelLabel
    for _, it in ipairs(list.items or {}) do if it.cancel then cancelLabel = it.label end end
    local pocket = game.qolCompPocket or 1
    local function rebuild()
      list.items = pocketRows(game, POCKETS[pocket], cancelLabel)
      list.qolCompItems = list.items
      if list.index > #list.items then list.index = math.max(1, #list.items) end
      if (list.scroll or 0) > math.max(0, #list.items - 1) then list.scroll = 0 end
    end
    rebuild()
    -- SELECT swaps inside the pocket by the rows' real bag positions
    list.onSelectKey = function(item, l)
      if not item or item.cancel then return end
      if not l.swapIndex then l.swapIndex = l.index return end
      local a, b = l.items[l.swapIndex], l.items[l.index]
      l.swapIndex = nil
      if a and b and a ~= b and a.orderIndex and b.orderIndex then
        Bag.swap(game.save, a.orderIndex, b.orderIndex, game.data)
        pcall(function() require("src.core.Sound").play(game.data, "Swap") end)
      end
      rebuild()
    end
    local baseUpdate = list.update
    list.update = function(self, dt)
      local input = game.input
      if game.stack:top() == self and input then
        local dir = (input:wasPressed("left") and -1) or (input:wasPressed("right") and 1) or 0
        if dir ~= 0 and not self.swapIndex then
          pocket = ((pocket - 1 + dir) % #POCKETS) + 1
          game.qolCompPocket = pocket
          self.index, self.scroll = 1, 0
          rebuild()
          pcall(function() require("src.core.Sound").play(game.data, "Press_AB") end)
          return
        end
        if self.swapIndex and input:wasPressed("a") then
          self.onSelectKey(self.items[self.index], self)
          return
        end
      end
      -- the vanilla flows rebuild the whole bag after a use or a toss
      if self.items ~= self.qolCompItems then rebuild() end
      return baseUpdate(self, dt)
    end
    local baseDraw = list.draw
    list.draw = function(self)
      baseDraw(self)
      pcall(function()
        local g = love.graphics
        g.push("all")
        g.setColor(1, 1, 1, 1)
        Font.drawBox(4, 0, 16, 3)
        g.setColor(0, 0, 0, 1)
        local name = POCKET_NAMES[POCKETS[pocket]] or ""
        local w = Font.width(name)
        Font.draw(name, 32 + math.floor((128 - w) / 2), 8)
        -- the pocket arrows are drawn, not typed: not every cart font
        -- carries a left-pointing glyph
        g.polygon("fill", 44, 11, 48, 8, 48, 14)
        g.polygon("fill", 148, 11, 144, 8, 144, 14)
        g.pop()
      end)
    end
    return list
  end)
end

return G
