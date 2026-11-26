-- QoL Comp / gen3: Ruby, Sapphire, Emerald, FireRed and LeafGreen.
--
-- Gen 3 is its own engine (src/core/game3, src/ui/game3): numeric species
-- and move ids, a session instead of a save table, a UI stack of layers,
-- and the cart's own script bytecode for every NPC.  Required from
-- install() alone, which main.lua calls on a Gen 3 boot.
--
-- Not here, on purpose: CENTER CAMERA (the GBA field is already centred),
-- the Gen 1 EXP bar / caught icon / Gen 2 bag (Gen 3 has all three).
-- RUNNING SHOES here is the game's own Running Shoes run, unlocked early
-- (see Player.canDash below), not the Game Boy 1.7x step.
--
-- Gen 3 only: FULL SCREEN MENUS (adapted from Panduino's Gen3-Full-Height-
-- Menus), which scales a menu that covers the whole screen up to the
-- window's height.

local V = ...
local C, K, UI, D = V.core, V.common, V.ui, V.decap

local A = {}
local G = { A = A }

-- Engine modules, looked up once.  A mod's require goes through the
-- loader's sandbox checks (about half a microsecond and a small table a
-- call), and the hot paths here ask several times a frame.  The cache is
-- dropped on every game.ready, so a new session never sees a module table
-- from the last one.
local reqCache = {}

local function req(name)
  local m = reqCache[name]
  if m then return m end
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then
    reqCache[name] = mod
    return mod
  end
  return nil
end

G._clearReqCache = function() for k in pairs(reqCache) do reqCache[k] = nil end end

local function session()
  local Runtime = req("src.core.game3.runtime")
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function bagOf(s)
  s = s or session()
  return s and (s.bag or s.inventory)
end

local function store()
  local Space = req("src.core.game3.scripting.space")
  if Space and Space.getStore then
    local ok, st = pcall(Space.getStore)
    if ok and st then return st, Space end
  end
  return Space and Space.store, Space
end

local function versionId()
  local GV = req("src.core.GameVersion")
  if not (GV and GV.get) then return "" end
  local ok, id = pcall(GV.get)
  return ok and tostring(id or ""):lower() or ""
end

local function isRs()
  local id = versionId()
  return id == "ruby" or id == "sapphire"
end

local function isRse()
  local id = versionId()
  return id == "ruby" or id == "sapphire" or id == "emerald"
end

-- ------------------------------------------------------------ adapter

local function FieldMoves() return req("src.core.game3.field_moves") end
local function Pokemon() return req("src.core.game3.pokemon") end

local FIELD_LIST = { "CUT", "FLY", "SURF", "STRENGTH", "FLASH", "ROCK_SMASH",
  "WATERFALL", "DIVE", "DIG", "TELEPORT", "SOFTBOILED", "MILK_DRINK",
  "SWEET_SCENT", "SECRET_POWER" }

function A.fieldMoveList()
  local out = {}
  for _, name in ipairs(FIELD_LIST) do
    -- DIVE and SECRET POWER only exist in Hoenn's field menu
    if (name ~= "DIVE" and name ~= "SECRET_POWER") or isRse() then out[#out + 1] = name end
  end
  return out
end

local function moveNum(name)
  local FM = FieldMoves()
  if type(name) == "number" then return name end
  return FM and FM.MOVES[tostring(name):upper():gsub(" ", "_")] or nil
end

function A.normalizeMove(id)
  if type(id) == "number" then
    local FM = FieldMoves()
    return FM and FM.MOVE_NAME_BY_ID[id] or tostring(id)
  end
  return (tostring(id or ""):upper():gsub("^MOVE_", ""):gsub(" ", "_"))
end

local function speciesOf(mon)
  local P = Pokemon()
  if P and P.speciesOf then
    local ok, sp = pcall(P.speciesOf, mon)
    if ok and sp then return tonumber(sp) end
  end
  return tonumber(mon.species)
end

function A.knows(mon, name)
  local P = Pokemon()
  local id = moveNum(name)
  return P ~= nil and id ~= nil and P.knowsMove(mon, id) == true
end

function A.canLearnLevel(_, mon, name)
  local P = Pokemon()
  local id = moveNum(name)
  if not (P and id) then return false end
  for _, e in ipairs(P.learnset(speciesOf(mon)) or {}) do
    if tonumber(e[2] or e.move) == id then return true end
  end
  return false
end

-- the TM/HM item (289..346) whose machine teaches this move.  Walked once
-- per boot and kept: the walk is 58 lookups and the answer never changes.
local tmByMove = nil

local function machineItem(name)
  local P = Pokemon()
  local id = moveNum(name)
  if not (P and id) then return nil end
  if not tmByMove then
    tmByMove = {}
    for i = 0, 57 do
      local ok, move = pcall(P.moveFromTmItem, 289 + i)
      if ok and move then tmByMove[move] = { 289 + i, i } end
    end
  end
  local hit = tmByMove[id]
  if not hit then return nil end
  return hit[1], hit[2]
end

local function resetTmCache() tmByMove = nil end

function A.canLearnMachine(_, mon, name)
  local P = Pokemon()
  local item, index = machineItem(name)
  return P ~= nil and item ~= nil and P.canLearnTmIndex(speciesOf(mon), index) == true
end

function A.holdsMachineFor(_, name)
  local item = machineItem(name)
  local Bag = req("src.core.game3.bag")
  local bag = bagOf()
  if not (item and Bag and bag) then return false end
  local ok, has = pcall(Bag.has, bag, item, 1)
  return ok and has == true
end

function A.isEgg(mon)
  local P = Pokemon()
  return P ~= nil and P.isEgg(mon) == true
end

function A.rowIsCancel(row)
  return type(row) == "table" and (row.action == "CANCEL" or row.action == "CANCEL2")
end

local NON_FIELD = { SUMMARY = true, SWITCH = true, CANCEL = true, ITEM = true,
  GIVE = true, TAKE = true, MAIL = true, TAKE_MAIL = true, READ = true,
  CANCEL2 = true, SHIFT = true, ["SEND OUT"] = true, ENTER = true,
  ["NO ENTRY"] = true, STORE = true }

function A.rowIsFieldMove(row)
  if type(row) ~= "table" then return false end
  if row.move ~= nil and row.onSelect == nil then return true end
  return type(row.action) == "string" and not NON_FIELD[row.action] and row.onSelect == nil
end

-- the engine labels the row itself (and drops a move this cart's menu has
-- no slot for), so only the move is handed down
-- The cart's own SetUpFieldMove_* checks (src/core/game3/field_moves.lua
-- fromMenu), with the context the party menu builds for them
-- (party_menu.lua): true only where the move would work now.  DIVE and
-- SECRET POWER's own checks also SET things up (the dive warp, the secret
-- base script), so their "can I?" half is asked here instead.
local function mapFlag(def, key) return def ~= nil and (tonumber(def[key]) or 0) ~= 0 end

function A.fieldMoveUsableHere(_, mon, name)
  local FM = FieldMoves()
  local P = req("src.core.game3.player")
  local Collision = req("src.core.game3.collision")
  local Objects = req("src.core.game3.objects")
  local Map = req("src.core.game3.map")
  local Space = req("src.core.game3.scripting.space")
  local PartyMenu = req("src.ui.game3.party_menu")
  if not (FM and P and Collision and Map and P.cellX) then return false end
  if name == "SOFTBOILED" or name == "MILK_DRINK" then
    local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
    local cost = math.floor(maxHp / 5)
    return cost > 0 and (mon.hp or 0) > cost
  end
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local d = DELTA[P.facing or "down"] or DELTA.down
  local fx, fy = P.cellX + d[1], P.cellY + d[2]
  local s = (PartyMenu and PartyMenu._session) or session()
  local mapDef = Map.currentDef and Map.currentDef()
  if name == "DIVE" then
    if not FM.hasBadge({ store = Space and Space.store, session = s }, "DIVE") then return false end
    local Dive = req("src.core.game3.dive")
    if not (Dive and Collision.behavior) then return false end
    local beh = Collision.behavior(P.cellX, P.cellY)
    if Dive.isUnderwaterMap(mapDef) then return not Dive.isUnableToEmerge(beh) end
    return Dive.isDiveable(beh) == true
  elseif name == "SECRET_POWER" then
    local SB = req("src.core.game3.rse.secret_base")
    if not (SB and Collision.behavior) then return false end
    if SB.playerHasBase and SB.playerHasBase(s) then return false end
    if P.facing ~= "up" then return false end
    local beh = Collision.behavior(fx, fy)
    return (SB.isCave(beh) or SB.isTree(beh) or SB.isShrub(beh)) == true
  end
  local function grass3x3()
    if not Collision.isGrass then return false end
    local elev = P.elevation
    for y = P.cellY - 1, P.cellY + 1 do
      for x = P.cellX - 1, P.cellX + 1 do
        local e = Collision.elevationAt and Collision.elevationAt(x, y)
        if (elev == nil or e == elev) and Collision.isGrass(x, y) then return true end
      end
    end
    return false
  end
  local facingBeh = Collision.behavior and Collision.behavior(fx, fy)
  local ctx = {
    party = (PartyMenu and PartyMenu._party) or (s and s.party),
    mon = mon,
    store = Space and Space.store,
    session = s,
    facingObject = Objects and Objects.at and Objects.at(fx, fy) or nil,
    isFacingWater = Collision.isWater and Collision.isWater(fx, fy),
    isFacingWaterfall = FM.isWaterfallBehavior(facingBeh),
    facing = P.facing,
    isSurfing = P.surfing == true,
    hasCuttableGrass = grass3x3(),
    mapType = mapDef and mapDef.mapType,
    isCave = mapFlag(mapDef, "cave"),
    canEscapeRope = mapFlag(mapDef, "allowEscaping"),
    escapeWarp = s and s.escapeWarp,
  }
  local res = FM.fromMenu(name, ctx)
  return type(res) == "table" and res.ok == true
end

function A.makeFieldRow(_, name)
  return { move = name }
end

-- Gen 3 menu labels are mixed case on the cart's own menus
local LABELS = { RENAME = "RENAME", RELEARN = "RELEARN" }
function A.label(s) return LABELS[s] or s end

-- A message to the player.  Over the party menu it goes in the party
-- menu's own message box: the field's message box is drawn UNDER a
-- full-screen menu, so a line put there is never seen.
function A.say(game, text, onDone)
  local PartyMenu = req("src.ui.game3.party_menu")
  if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() and PartyMenu.showMessage then
    local ok = pcall(PartyMenu.showMessage, text, function()
      PartyMenu.mode = "list"
      if onDone then onDone() end
    end)
    if ok then return end
  end
  local Message = req("src.ui.game3.message")
  if Message and Message.show then pcall(Message.show, text, onDone or function() end) end
end

local function speciesName(species)
  local P = Pokemon()
  if not (P and P.name) then return nil end
  local ok, name = pcall(P.name, species)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

local function monName(mon)
  local P = Pokemon()
  if P and P.displayName then
    local ok, name = pcall(P.displayName, mon)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return mon.nickname or speciesName(speciesOf(mon)) or "?"
end

local function closeMessage()
  local Message = req("src.ui.game3.message")
  if Message and Message.isOpen and Message.isOpen() and Message.close then
    pcall(Message.close)
  end
end

-- RENAME: the Name Rater's own screen and rules (pokefirered
-- field_specials.c ChangePokemonNickname; natives.lua opens it the same
-- way): the NICKNAME template, ten characters, the keyboard EMPTY as the
-- Name Rater's is.  OK with nothing typed, or the same name again, keeps the
-- old name; a new one is written onto the party member and the player is
-- told which happened.
-- opts (the PC's RENAME row): say(text) reports in the caller's own message
-- line instead of A.say, and after() runs once the name is decided.
function A.rename(game, mon, opts)
  opts = opts or {}
  local say = opts.say or function(text) A.say(game, text) end
  local Naming = req("src.ui.game3.naming")
  if not (Naming and Naming.open) then error("the naming screen was not found", 0) end
  local species = speciesOf(mon)
  local before = monName(mon)
  closeMessage()
  Naming.open({
    template = "NICKNAME",
    maxLen = 10, -- pret POKEMON_NAME_LENGTH
    species = species,
    personality = mon.personality,
    gender = mon.gender,
    -- an empty OK answers the seed: the name it already has
    seed = before,
    title = Naming.monTitle and speciesName(species) and Naming.monTitle(speciesName(species)) or nil,
    session = session(),
    game = game,
    onDone = function(name)
      if type(name) ~= "string" or name:match("^%s*$") or name == before then
        say(before .. " kept its name.")
        if opts.after then opts.after(false) end
        return
      end
      mon.nickname = name
      say(before .. " is now named\n" .. name .. "!")
      if opts.after then opts.after(true) end
    end,
  })
end

-- RELEARN: the cart's own Move Relearner, exactly the screen the
-- relearner NPC opens (natives_moveteach.lua TeachMoveRelearnerMove):
-- Ruby, Sapphire and Emerald use the RSE module (Ruby/Sapphire then draw it
-- with their own Move Tutor skin), FireRed and LeafGreen the FRLG one.
--
-- (v0.1.1 opened the FireRed screen on Emerald and the Ruby/Sapphire skin
-- module directly, which is not a screen of its own.)
local function relearnerModule()
  local s = session()
  local Profile = req("src.core.game3.profile")
  local family
  if Profile and Profile.family then
    local ok, f = pcall(Profile.family, s)
    if ok then family = f end
  end
  if family == nil then family = isRse() and "rse" or "frlg" end
  if family == "rse" then
    return req("src.ui.game3.rse.move_relearner")
  end
  return req("src.ui.game3.move_relearner")
end

function A.relearn(game, mon)
  local Relearner = relearnerModule()
  if not (Relearner and Relearner.show) then error("the Move Relearner screen was not found", 0) end
  local MoveLearn = req("src.core.game3.move_learn")
  if MoveLearn and MoveLearn.relearnableMoves then
    local ok, moves = pcall(MoveLearn.relearnableMoves, mon)
    if ok and type(moves) == "table" and #moves == 0 then
      A.say(game, monName(mon) .. " has no moves\nto relearn.")
      return
    end
  end
  closeMessage()
  Relearner.show(mon, { session = session(), onDone = function() end })
end

local function legalLead(mon)
  return type(mon) == "table" and not A.isEgg(mon) and (tonumber(mon.hp) or 0) > 0
end

G.legalLead = legalLead

-- CHOOSE PKMN.
--
-- Gen 3 builds its intro as a list of steps (src/core/game3/battle/
-- intro_seq.lua): the opponent slides in, is sent out, gets its healthbox,
-- and only then comes the player's "Go! X!" message and throw.  A marker
-- step goes in immediately before that message, which is exactly where the
-- cart would have asked, and the pump is frozen on it while the party
-- screen is up.  Choosing rebinds battler 0 before the one throw happens.
--
-- The intro pump is driven from Battle.update, which does not route input
-- to the party screen during the intro, so this drives it directly.

local MARKER = "qol_comp_choose_lead"

local chooser = { open = false }

local function introSendOutIndex(steps, st)
  local IntroSeq = req("src.core.game3.battle.intro_seq")
  if not (IntroSeq and type(steps) == "table") then return nil end
  local okText, goText = pcall(IntroSeq.sendOutText, st, "player")
  for i, step in ipairs(steps) do
    if type(step) == "table" and step.kind == "msg" then
      local text = step.data and step.data.text
      if okText and text ~= nil and text == goText then return i, step end
    end
  end
  -- the throw itself is the fallback anchor when the line was reworded
  for i, step in ipairs(steps) do
    if type(step) == "table" and step.kind == "player_throw" then return i, nil end
  end
  return nil
end

-- rebind battler 0 to party slot `slot`, before any send-out has happened
G.introSendOutIndex = introSendOutIndex

local function commitLead(st, slot, goStep)
  local State = req("src.core.game3.battle.state")
  local party = st and st.playerParty
  local mon = party and party[slot]
  if not (State and mon) then return false end
  if st.player and st.player.partyIndex == slot then return true end
  local fresh = State.makeBattler(mon, "player", { partyIndex = slot, id = 0, st = st })
  if not fresh then return false end
  local before = st.player and st.player.partyIndex
  st.player = fresh
  if st.enemy and st.enemy.participants and before then
    st.enemy.participants[before] = nil
  end
  if State.trackParticipant then State.trackParticipant(st, st.enemy, slot) end
  if st.double and State.resetSentPokes then pcall(State.resetSentPokes, st) end
  if goStep and goStep.data then
    local IntroSeq = req("src.core.game3.battle.intro_seq")
    local ok, text = pcall(IntroSeq.sendOutText, st, "player")
    if ok and type(text) == "string" then goStep.data.text = text end
  end
  return true
end

local function openIntroPicker(st, goStep)
  local Ui = req("src.core.game3.battle.ui")
  local PartyMenu = req("src.ui.game3.party_menu")
  if not (Ui and Ui.openPartyMenu and PartyMenu) then return false end
  local party = st and st.playerParty or {}
  chooser.open, chooser.st = true, st
  local function finish()
    chooser.open, chooser.st = false, nil
    local IntroSeq = req("src.core.game3.battle.intro_seq")
    if IntroSeq then
      IntroSeq._waitingGen = false
      IntroSeq._i = (IntroSeq._i or 1) + 1
    end
  end
  chooser.finish = finish
  local ok = pcall(Ui.openPartyMenu, st, 0, {
    validate = function(pi)
      local mon = party[pi]
      if not mon then return "cannot" end
      if A.isEgg(mon) then return "egg" end
      if (tonumber(mon.hp) or 0) <= 0 then return "fainted" end
      return nil
    end,
    onSelect = function(slot)
      if slot then commitLead(st, slot, goStep) end
      pcall(PartyMenu.close)
      finish()
    end,
    onClose = function()
      if chooser.open then finish() end
    end,
  })
  if not ok then
    finish()
    return false
  end
  return true
end

function G.installChooseLead(mod)
  local IntroSeq = req("src.core.game3.battle.intro_seq")
  if not IntroSeq then
    C.warnOnce("choose_pkmn.gen3", "the battle intro module was not found")
    return
  end

  -- put the marker in, once the engine has built the steps
  C.patch(IntroSeq, "begin", function(orig, st, opts)
    local started = orig(st, opts)
    if started ~= true or type(st) ~= "table" then return started end
    local kind = st.wild and "wild" or "trainer"
    if st.link or st.pokedude or st.oldManTutorial or st.safari then return started end
    if not K.chooseWanted(kind) then return started end
    if not K.enoughLeads(st.playerParty, legalLead) then return started end
    local steps = IntroSeq._steps
    local at, goStep = introSendOutIndex(steps, st)
    if not at then
      C.warnOnce("choose_pkmn.gen3.seam", "the intro's send-out step was not found")
      return started
    end
    table.insert(steps, at, { kind = MARKER, data = { goStep = goStep } })
    return started
  end)

  -- freeze the pump on the marker, and drive the party screen while it is up
  C.patch(IntroSeq, "update", function(orig, ...)
    if chooser.open then
      local PartyMenu = req("src.ui.game3.party_menu")
      local game = V.game
      if PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen() and game and game.input then
        pcall(PartyMenu.handleInput, game.input)
        return false
      end
      -- the screen closed without telling us
      if chooser.finish then chooser.finish() end
    end
    local steps = IntroSeq._steps
    local step = steps and steps[IntroSeq._i or 1]
    if type(step) == "table" and step.kind == MARKER then
      local Battle = req("src.core.game3.battle")
      local st = (Battle and Battle._st) or IntroSeq._st
      IntroSeq._waitingGen = true
      if not openIntroPicker(st, step.data and step.data.goStep) then
        IntroSeq._waitingGen = false
        IntroSeq._i = (IntroSeq._i or 1) + 1
      end
      return false
    end
    return orig(...)
  end)
end

local function badgeCount()
  local Flags = req("src.core.game3.scripting.flags")
  local st = store()
  if not (Flags and st and Flags.countBadges) then return 0 end
  local ok, n = pcall(Flags.countBadges, st)
  return ok and tonumber(n) or 0
end

local function partyLevels()
  local s = session()
  local out = {}
  for _, mon in ipairs(s and s.party or {}) do out[#out + 1] = mon.level end
  return out
end

-- Gen 3 hands trainer.party copies of the cart's rows (level fields)
function A.scaleTrainerParty(rows, pending)
  local levels = {}
  for i, row in ipairs(rows) do levels[i] = row.level or row.lvl end
  local scaled = K.scaleLevels(levels, pending.anchor)
  for i, row in ipairs(rows) do
    if row.level ~= nil then row.level = scaled[i] else row.lvl = scaled[i] end
  end
  return rows
end

-- ------------------------------------------------------------ misc

-- After a heal that skipped its text, face the player away from the nurse.
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

function G.turnPlayerAround()
  local Player = req("src.core.game3.player")
  if not Player then return end
  local away = OPPOSITE[Player.facing]
  if away then Player.facing = away end
end

-- ------------------------------------------------------------ sparkle

local DARK = { 0.25, 0.25, 0.3 }

function G.drawSparkle(x, y)
  local r = K.sparkleRadius()
  if r then K.drawSparkleAt(x, y, r, 1, DARK) end
end

local function hiddenItemsNow()
  local s = session()
  local mapId = s and s.map
  if not mapId then return {} end
  local game = V.game
  local maps = game and game.data and game.data.maps
  local def = maps and maps[mapId]
  local events = def and def.bgEvents
  local st, Space = store()
  if not events then
    local ev = Space and Space.bundle and Space.bundle.events and Space.bundle.events[mapId]
    events = ev and ev.bgEvents
  end
  local Flags = req("src.core.game3.scripting.flags")
  local out = {}
  for _, ev in ipairs(events or {}) do
    if ev.type == "hidden_item" or ev.kind == 7 then
      local flag = ev.flag or (ev.hiddenItemId and (0x3E8 + ev.hiddenItemId))
      local taken = flag and Flags and st and Flags.getFlag(st, nil, flag)
      if not taken then out[#out + 1] = ev end
    end
  end
  return out
end

-- The list for the map on screen, rebuilt at most every 8 frames (and at
-- once on a new map) rather than every frame: it walks the map's events
-- and reads a flag for each.  An item picked up stops sparkling within 8
-- frames, while its item-found box is still opening.
local shineList, shineMap, shineFrame = nil, nil, -1000

local function hiddenItems()
  local s = session()
  local mapId = s and s.map
  local frame = V.frame or 0
  if shineList == nil or mapId ~= shineMap or frame - shineFrame >= 8
      or frame < shineFrame then
    shineList = hiddenItemsNow()
    shineMap, shineFrame = mapId, frame
  end
  return shineList
end

G._hiddenItemsNow = hiddenItemsNow
G._resetShine = function() shineList = nil end

local function drawShine(camX, camY)
  local r = K.sparkleRadius()
  if not r then return end
  local list = hiddenItems()
  if #list == 0 then return end
  local g = love.graphics
  local cr, cg, cb, ca = g.getColor()
  for i = 1, #list do
    local ev = list[i]
    K.drawSparkleAt(math.floor(ev.x * 16 + 8 - (camX or 0)),
      math.floor(ev.y * 16 + 8 - (camY or 0)), r, 1, DARK)
  end
  g.setColor(cr, cg, cb, ca)
end

-- ------------------------------------------------------------ install

-- Input for the mod's own list screens (EDIT START MENU, notices).
--
-- In a game, the HUD hands input to whatever layer is on top of the Gen 3
-- UI stack (src/ui/game3/hud.lua update_top_menu) -- the mod's screens
-- included -- so nothing extra is needed there.  The one place it does not
-- run is the title screen's mod manager, before a game is loaded, and that
-- is the only time this drives the screen itself.
--
-- (v0.1.1 drove its screens AND the cart's Move Relearner from input.step
-- every frame.  input.step fires before the engine reads the buttons, so
-- that pass saw the previous frame's presses: every press reached those
-- screens twice, which skipped "Teach this move?" prompts and moved the
-- editor's cursor two rows.)
local hudFrame = -10

function G.installScreenInput(mod)
  local Hud = req("src.ui.game3.hud")
  if Hud then
    C.patch(Hud, "update", function(orig, ...)
      hudFrame = V.frame or 0
      return orig(...)
    end)
  end
  -- from main.lua's single input.step wrapper (C.onFrame)
  C.onFrame(function(game, _, frame)
    if hudFrame >= frame - 1 then return end
    local Stack = req("src.ui.game3.stack")
    local top = Stack and Stack.top and Stack.top()
    local layer = type(top) == "table" and top.mod or nil
    if type(layer) == "table" and layer.qolCompScreen == true
        and type(layer.handleInput) == "function" and game and game.input then
      pcall(layer.handleInput, game.input)
    end
  end)
end

G._hudFrame = function() return hudFrame end

-- ------------------------------------------------------------ FULL SCREEN MENUS
--
-- Adapted from Panduino's Gen3-Full-Height-Menus (render.compose): when a
-- menu that covers the whole playfield is up, the frame is drawn scaled to
-- the window's height (aspect kept, black bars at the sides) instead of at
-- the normal size.  Overlays that leave the overworld visible (the START
-- menu, the save box, a yes/no) are left alone, and so is the field.
-- The title screen, the Continue / New Game menus, Oak's / Birch's intro
-- and the FireRed "Previously on your quest" replay are not on the menu
-- stack, so their draws are marked separately.

local OVERLAY_MENUS = { start = true, start_menu = true, save = true,
  save_menu = true, choice = true, yes_no = true }

local lastStandaloneDraw = -math.huge

local function markDraw()
  if love and love.timer and love.timer.getTime then
    lastStandaloneDraw = love.timer.getTime()
  end
end

function G.fullScreenMenuUp()
  local Stack = req("src.ui.game3.stack")
  local top = Stack and Stack.top and Stack.top()
  if type(top) == "table" and top.isMenu == true and not OVERLAY_MENUS[top.id]
      and top.hideBelow ~= false then
    return true
  end
  if love and love.timer and love.timer.getTime then
    -- a standalone screen drew during this render frame
    return love.timer.getTime() - lastStandaloneDraw < 0.05
  end
  return false
end

local fsQuad, fsKey = nil, {}

function G.installFullScreenMenus(mod)
  local Boot = req("src.ui.game3.boot")
  if Boot and type(Boot.draw) == "function" then
    C.patch(Boot, "draw", function(orig, state, ...)
      local r = orig(state, ...)
      if type(state) == "table" and state.phase then markDraw() end
      return r
    end)
  end
  local QuestLog = req("src.ui.game3.quest_log")
  if QuestLog and type(QuestLog.draw) == "function" then
    C.patch(QuestLog, "draw", function(orig, ...)
      local r = orig(...)
      markDraw()
      return r
    end)
  end

  -- The frame-composite hook goes in the first time the option is turned
  -- on, not at load: a render.compose wrapper costs the engine a little
  -- every frame, and most players never turn this on.
  C.onEnable("full_screen_menus", function()
  mod.hooks:wrap("render.compose", function(next, renderer, ctx)
    if not C.on("full_screen_menus") then return next(renderer, ctx) end
    if not (type(ctx) == "table" and ctx.uiCanvas and love and love.graphics) then
      return next(renderer, ctx)
    end
    if not G.fullScreenMenuUp() then return next(renderer, ctx) end
    local g = love.graphics
    local ww = tonumber(ctx.ww) or g.getWidth()
    local wh = tonumber(ctx.wh) or g.getHeight()
    local canvas = ctx.uiCanvas
    local okD, cw, ch = pcall(canvas.getDimensions, canvas)
    if not okD or not cw or ww <= 0 or wh <= 0 or cw <= 0 or ch <= 0 then
      return next(renderer, ctx)
    end
    -- the GBA screen is 240x160; a larger backing canvas is padding
    local menuW, menuH = math.min(240, cw), math.min(160, ch)
    local scale = math.min(ww / menuW, wh / menuH)
    local dw, dh = menuW * scale, menuH * scale
    -- one quad per canvas size, not a new one every frame
    if not (fsQuad and fsKey[1] == menuW and fsKey[2] == menuH and fsKey[3] == cw
        and fsKey[4] == ch) then
      if fsQuad then pcall(fsQuad.release, fsQuad) end
      fsQuad = g.newQuad(0, 0, menuW, menuH, cw, ch)
      fsKey[1], fsKey[2], fsKey[3], fsKey[4] = menuW, menuH, cw, ch
    end
    -- set each frame: the engine's own filters may change it between frames
    pcall(canvas.setFilter, canvas, "nearest", "nearest")
    g.push("all")
    g.origin()
    g.setScissor()
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.clear(0, 0, 0, 1)
    g.draw(canvas, fsQuad, (ww - dw) / 2, (wh - dh) / 2, 0, scale, scale)
    g.pop()
    return true
  end, -2500)
  end)
end

-- ------------------------------------------------------------ long values
--
-- The Gen 3 mod manager cuts every option value at eight characters, but
-- its value column (x 146 to the frame at 224) has room for about twelve.
-- LOW HP BEEP's "ON (BEEPS)" and "OFF (MUTED)" are drawn whole on this
-- mod's own options page; nothing else is touched.
local LONG_VALUES = { "ON (BEEPS)", "OFF (MUTED)", "ON (GEN2)", "ON (GEN6)" }
local VALUE_X = 16 + 0x82

function G.installLongValues()
  local MM = req("src.ui.game3.mod_manager")
  local Window = req("src.ui.game3.window")
  if not (MM and Window and MM.draw and Window.printPx) then return end
  local whole = {}
  for _, v in ipairs(LONG_VALUES) do whole[v:sub(1, 8)] = v end
  local function ourPage()
    local m = MM._mgr
    if not (m and m.screen == "options" and type(m.optionRows) == "table") then return false end
    for _, row in ipairs(m.optionRows) do
      if row.id == "edit_start_menu" then return true end
    end
    return false
  end
  -- Window.printPx (every line of text the GBA games print) is only
  -- wrapped for the length of this mod's own options page draw, and put
  -- back straight after, so no other text pays for it.
  local function expanding(orig)
    return function(text, px, py, opts, ...)
      if px == VALUE_X and whole[text] then text = whole[text] end
      return orig(text, px, py, opts, ...)
    end
  end
  C.patch(MM, "draw", function(orig, ...)
    if not ourPage() then return orig(...) end
    local live = Window.printPx
    Window.printPx = expanding(live)
    local ok, a, b = pcall(orig, ...)
    Window.printPx = live
    if not ok then error(a, 0) end
    return a, b
  end)
end

G.LONG_VALUES = LONG_VALUES

function G.install(mod)
  mod.events:on("game.ready", G._clearReqCache)
  K.install(mod, A)
  G.installScreenInput(mod)
  C.try("full_screen_menus.install", G.installFullScreenMenus, mod)
  C.try("longvalues.install", G.installLongValues)

  -- DECAPITALIZATION.
  --
  -- Gen 3's font is proportional and lays out its own wrapping, so the one
  -- correct seam is the font itself: draw, measure and wrap all have to see
  -- the same text or centred and right-aligned lines drift.  Everything the
  -- game draws goes through it, which is what makes the toggle reach the
  -- field, battle, menus and the summary screen alike.
  --
  -- The text codes (a 0xFC byte and its arguments, and {TOKEN} names) are
  -- opaque spans in the converter, Braille pages are skipped, and no word
  -- changes length, so a typed-out message stays in step.
  local FrlgFont = req("src.ui.game3.frlg_font")
  if FrlgFont then
    local function braille(opts)
      return type(opts) == "table" and opts.font == "braille"
    end
    local function conv(text, opts)
      if type(text) == "string" and not braille(opts) then return D.cached(text) end
      return text
    end
    -- all three go on and off together, so a measured width always matches
    -- what was drawn
    C.togglePatch(FrlgFont, "draw", "decap", function(orig, text, x, y, opts, ...)
      return orig(conv(text, opts), x, y, opts, ...)
    end)
    C.togglePatch(FrlgFont, "measure", "decap", function(orig, text, opts, ...)
      return orig(conv(text, opts), opts, ...)
    end)
    C.togglePatch(FrlgFont, "wrap", "decap", function(orig, text, width, opts, ...)
      return orig(conv(text, opts), width, opts, ...)
    end)
  else
    C.warnOnce("decap.gen3", "the FireRed font module was not found")
  end

  -- LOW HP BEEP lives in lib/common.lua (the siren's live source is turned
  -- down there on every generation).

  -- KEEP TMS: useTm reads ItemsData.isHm once, up front, to decide whether
  -- the machine is spent; for that one call a TM answers like an HM
  local ItemUse = req("src.core.game3.item_use")
  local ItemsData = req("src.core.game3.items_data")
  if ItemUse and ItemsData then
    C.patch(ItemUse, "useTm", function(orig, ...)
      if not C.on("keep_tms") then return orig(...) end
      local realIsHm = ItemsData.isHm
      ItemsData.isHm = function() return true end
      local res = { pcall(orig, ...) }
      ItemsData.isHm = realIsHm
      if not res[1] then error(res[2], 0) end
      return unpack(res, 2)
    end)
  end

  -- BIGGER BAG: every pocket stacks to 999 (the cart's quantity field holds
  -- it); the pocket ROW counts stay the cart's -- see README
  if ItemsData and ItemsData.slotMax then
    C.patch(ItemsData, "slotMax", function(orig, pocket)
      local n = tonumber(orig(pocket)) or 99
      return math.max(n, 999)
    end)
  end

  -- FAST POKECENTER.  The nurse is the cart's own script, so the seam is
  -- script.command.  A session opens when a script whose key names the
  -- nurse starts, and closes when that script ends.
  --
  --   FAST  the first message is shown, then the box closes and the heal
  --         runs; the HEAL/CANCEL question is answered for the player
  --   NOW   no text at all
  --
  -- Afterwards the player turns around, so the next step does not walk
  -- straight back into the counter.
  local nurse = nil
  local Flags = req("src.core.game3.scripting.flags")
  local CtxM = req("src.core.game3.scripting.ctx")
  local VAR_RESULT = (CtxM and CtxM.VAR_RESULT) or 0x800D
  local WAITS = { waitmessage = true, waitbuttonpress = true }

  local function answerYes(vm)
    if Flags and vm and vm.store then
      pcall(Flags.setVar, vm.store, vm.ctx, VAR_RESULT, 1)
    end
  end

  mod.events:on("script.started", function(ev)
    local mode = C.opt("fast_pokecenter")
    nurse = nil
    if mode ~= "fast" and mode ~= "now" then return end
    local key = tostring(ev and ev.key or ""):lower()
    if key:find("nurse", 1, true) or key:find("pokecenter", 1, true) then
      nurse = { mode = mode, shown = false, closed = false }
    end
  end)

  mod.events:on("script.ended", function()
    if not nurse then return end
    nurse = nil
    G.turnPlayerAround()
  end)

  mod.hooks:wrap("script.command", function(next, ctx, op, row)
    local s = nurse
    if not s then return next(ctx, op, row) end
    local vm = ctx and (ctx.vm or ctx.runner)
    -- the question never reaches the player
    if op == "yesnobox" then
      answerYes(vm)
      return false
    end
    if op == "message" then
      if s.mode == "fast" and not s.shown then
        s.shown = true
        return next(ctx, op, row)
      end
      if not s.closed then
        s.closed = true
        next(ctx, "closemessage", { op = "closemessage" })
      end
      return false
    end
    if WAITS[op] then
      -- the one message FAST shows still waits for its button
      if s.mode == "fast" and s.shown and not s.waited then
        s.waited = true
        return next(ctx, op, row)
      end
      return false
    end
    return next(ctx, op, row)
  end)

  -- REMATCH: a beaten trainer's flag is cleared for one talk, so the cart's
  -- own trainer script runs the battle; the flag is set again when that
  -- script ends, won or lost
  local TrainerSight = req("src.core.game3.trainer_sight")
  local restoreFlag = nil
  mod.events:on("script.ended", function()
    if restoreFlag then
      local st = store()
      if Flags and st then pcall(Flags.setFlag, st, nil, restoreFlag, true) end
      restoreFlag = nil
    end
    K.pendingRematch = nil
  end)

  mod.hooks:wrap("world.talk", function(next, game, eo)
    local mode = C.opt("rematch")
    if (mode ~= "normal" and mode ~= "training") or not (TrainerSight and Flags) then
      return next(game, eo)
    end
    local tid = TrainerSight.getTrainerId(eo)
    local st, Space = store()
    local ctx = Space and Space.vm and Space.vm.ctx
    if not tid or tonumber(tid) == 0 or not st then return next(game, eo) end
    local okD, beaten = pcall(TrainerSight.isDefeated, eo, st, ctx)
    if not (okD and beaten) then return next(game, eo) end
    local Message = req("src.ui.game3.message")
    local Choice = req("src.ui.game3.choice")
    if not (Message and Choice) then return next(game, eo) end
    -- `hold` keeps the question on screen under the YES/NO box (the field's
    -- own message + yesnobox pair); without it the line closed first and
    -- the box asked nothing
    Message.show("Would you like a rematch?", { hold = true, done = function()
      Choice.yesNo(function(yes)
        pcall(Message.close)
        if yes then
          local fid = Flags.trainerFlagId(tid)
          pcall(Flags.setFlag, st, nil, fid, false)
          restoreFlag = fid
          if mode == "training" then
            local curve = isRse() and K.STORY_LEVELS.rse or K.STORY_LEVELS.frlg
            K.pendingRematch = { training = true,
              anchor = K.trainingAnchor(curve, badgeCount(), partyLevels()) }
          end
        end
        next(game, eo)
      end)
    end })
  end)

  G.installChooseLead(mod)

  -- RUNNING SHOES (B TO RUN): the game's own Running Shoes, without having
  -- been handed them.
  --
  -- Player.canDash is the one place the GBA games decide whether holding B
  -- runs (pret field_player_avatar; player.lua Player.update asks it each
  -- step).  Vanilla it needs the Running Shoes flag, then refuses
  -- underwater and wherever running is not allowed: indoor maps (the map
  -- header's allowRunning) and Player.runningDisallowed's tiles -- long
  -- grass, hot springs, Pacifidlog's logs, Fortree's bridges, MB_NO_RUNNING.
  -- With B TO RUN it answers yes without the flag AND in all of those
  -- places, with or without the real shoes: you can run anywhere you can
  -- walk.  Only underwater, the bike and surfing still say no -- the game
  -- has no run there.  Everything after -- the run step, its speed, its
  -- animation -- is the game's own, so the sprite runs exactly as it does
  -- with the real shoes.  (Player.runningDisallowed itself is untouched: the
  -- Acro Bike's tile rules ask the bike's own copy of it.)
  --
  -- (0.1.2 rebuilt the step itself after the game had started it as a
  -- walk, which made Emerald's sprite flicker between the run and a fast
  -- walk.)
  local Player = req("src.core.game3.player")
  if Player and type(Player.canDash) == "function" then
    C.patch(Player, "canDash", function(orig, ...)
      if C.opt("running_shoes") ~= "b" then return orig(...) end
      -- the field must be up, as vanilla requires
      if not store() then return false end
      if Player.underwater or Player.biking or Player.surfing then return false end
      return true
    end)
  else
    C.warnOnce("running_shoes.gen3", "the running-shoes check was not found")
  end

  -- HIDDEN ITEM SHINE: on the ground layer, under the sprites
  local FieldEffects = req("src.core.game3.field_effects")
  if FieldEffects then
    C.patch(FieldEffects, "drawBehind", function(orig, camX, camY, ...)
      local r = orig(camX, camY, ...)
      if C.on("hidden_shine") then pcall(drawShine, camX, camY) end
      return r
    end)
  end

  -- GAMBLE ODDS (LUCKY): a spin that drew no payout bias draws once more
  local FrlgSlots = req("src.core.game3.slot_machine")
  if FrlgSlots and FrlgSlots.calcBias then
    C.patch(FrlgSlots, "calcBias", function(orig, st, ...)
      local b = orig(st, ...)
      if C.opt("gamble_odds") == "lucky" and b == 0 then b = orig(st, ...) end
      return b
    end)
  end
  local RseSlots = req("src.core.game3.rse.slot_machine")
  if RseSlots and RseSlots.trySelectBiasRegular then
    C.patch(RseSlots, "trySelectBiasRegular", function(orig, self, ...)
      local which = orig(self, ...)
      if C.opt("gamble_odds") == "lucky" and which == 5 then which = orig(self, ...) end
      return which
    end)
  end

  -- ---------------------------------------------- always on

  -- SELECT quick switch on the field party menu: SELECT starts the move,
  -- SELECT (or A) on the second mon swaps them, B cancels
  local PartyMenu = req("src.ui.game3.party_menu")
  if PartyMenu then
    C.patch(PartyMenu, "handleInput", function(orig, input, ...)
      local plain = input and not PartyMenu._battle and not PartyMenu._item
        and not PartyMenu._onChoose and not PartyMenu._onSelect
      if plain and input:wasPressed("select") then
        local party = (PartyMenu._session and PartyMenu._session.party)
          or (session() and session().party) or {}
        if PartyMenu.mode == "list" and #party > 1 and (PartyMenu.cursor or 7) <= #party then
          PartyMenu.switchFrom = PartyMenu.cursor
          PartyMenu.mode = "switch"
          pcall(function()
            require("src.core.game3.audio").playSe(require("src.core.game3.se_ids").resolve("SE_SELECT"))
          end)
          return
        end
        if PartyMenu.mode == "switch" then
          -- SELECT finishes the swap exactly as A would
          local proxy = setmetatable({
            wasPressed = function(_, b) if b == "a" then return true end
              if b == "select" then return false end
              return input:wasPressed(b) end,
          }, { __index = function(_, k)
            local v = input[k]
            if type(v) == "function" then return function(_, ...) return v(input, ...) end end
            return v
          end })
          return orig(proxy, ...)
        end
      end
      return orig(input, ...)
    end)
  end

  -- SHOP BAG COUNT: the cart shows IN BAG only once a quantity is being
  -- picked; this shows the same box while the cursor browses the list
  local ShopMenu = req("src.ui.game3.shop_menu")
  if ShopMenu and ShopMenu.draw then
    C.patch(ShopMenu, "draw", function(orig, ...)
      local r = orig(...)
      if ShopMenu.mode == "buy" then
        pcall(function()
          local items = ShopMenu._items or {}
          local entry = items[ShopMenu.cursor or 0]
          if entry == nil then return end
          local id = type(entry) == "table" and (entry.id or entry.item or entry[1]) or entry
          local Window = req("src.ui.game3.window")
          local Bag = req("src.core.game3.bag")
          local FrlgFont = req("src.ui.game3.frlg_font")
          local RomText = req("src.core.game3.rom_text")
          local s = ShopMenu._session or session()
          local n = 0
          if s and bagOf(s) then n = tonumber(Bag.get(bagOf(s), id)) or 0 end
          Window.stdFrame(Window.template(1, 11, 13, 2))
          local inBag = RomText.plain("gText_InBagVar1", { stringVars = { "\1" } })
          local label, tail = inBag:match("^(.-)%s*\1(.*)$")
          Window.printPx(label or "IN BAG:", 12, 89)
          local countStr = tostring(n) .. (tail or "")
          local cw = (FrlgFont.measure and FrlgFont.measure(countStr, { small = true })) or (6 * #countStr)
          Window.printPx(countStr, math.max(64, 106 - cw), 89, { small = true })
        end)
      end
      return r
    end)
  end
end

return G
