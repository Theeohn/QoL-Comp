-- QoL Comp headless suite.
--
-- Runs inside a gen1recomp checkout with the mod at mods/qol_comp:
--
--   luajit mods/qol_comp/tests/run.lua
--
-- It boots the mod on all three generations through the engine's own modkit
-- loader (fixture data, no ROMs), checks that every engine seam it patches
-- was found, and drives the generation-free logic (decapitalization, start
-- menu layout, the eight-row submenu cap, rematch level scaling) directly.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local Sdk = require("tests.modkit.sdk")

local MOD = "mods/qol_comp"
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else
    failed = failed + 1
    print("FAIL  " .. label)
  end
end
local function eq(a, b, label)
  check(a == b, label .. "  (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- the mod reads its options live, with a one-frame memo; a test that writes
-- an option has to drop that memo the way the frame tick would
local function setOpt(I, key, value)
  I.core.opts[key] = value
  I.core.refresh()
end

local function boot(gen)
  local opts = { generation = gen }
  if gen == 3 then opts.data = Sdk.gen3Data() end
  local r = Sdk.loadMod(MOD, opts)
  for _, e in ipairs(r.errors or {}) do print("LOAD ERROR", gen, e) end
  local ex = r.loader.exports.qol_comp
  return r, ex
end

-- a wrapper is live when the table's function is not the original we stored
local function patched(modName, fn)
  local m = package.loaded[modName]
  if type(m) ~= "table" then return false end
  local orig = rawget(m, "__qol_comp_orig_" .. fn)
  if orig == nil then return false end
  return m[fn] ~= orig
end

-- ---------------------------------------------------------------- per gen

local EXPECT = {
  [1] = {
    { "src.render.TextBox", "substitute" }, { "src.render.TextBox", "new" },
    { "src.battle.BattleState", "drawHUDs" },
    { "src.inventory.ItemEffects", "use" }, { "src.world.OverworldController", "nurseHeal" },
    { "src.world.OverworldController", "drawShipAnim" }, { "src.world.Player", "update" },
    { "src.ui.PartyMenu", "update" }, { "src.ui.PartyMenu", "draw" },
    { "src.ui.ListMenu", "drawItemBox" }, { "src.render.Camera", "follow" },
    { "src.ui.SlotMachine", "setFlags" },
  },
  [2] = {
    { "src.render.TextBox", "substitute" },
    { "src.core.Game2", "consumeItem" },
    { "src.ui.gen2.BattleState", "consumeItem" },
    { "src.world.gen2.Player", "update" }, { "src.world.gen2.World", "drawGround" },
    { "src.ui.gen2.SlotMachine", "initBias" }, { "src.ui.gen2.CardFlip", "flip" },
    { "src.ui.gen2.PartyMenu", "update" }, { "src.ui.gen2.MartMenu", "drawBuyList" },
    { "src.render.Camera", "follow" },
  },
  [3] = {
    { "src.core.game3.item_use", "useTm" }, { "src.core.game3.items_data", "slotMax" },
    { "src.ui.game3.hud", "update" },
    { "src.ui.game3.boot", "draw" }, { "src.ui.game3.quest_log", "draw" },
    { "src.ui.game3.mod_manager", "draw" },
    { "src.core.game3.field_effects", "drawBehind" }, { "src.core.game3.slot_machine", "calcBias" },
    { "src.core.game3.rse.slot_machine", "trySelectBiasRegular" },
    { "src.core.game3.battle.intro_seq", "begin" },
    { "src.core.game3.battle.intro_seq", "update" },
    { "src.ui.game3.party_menu", "handleInput" }, { "src.ui.game3.shop_menu", "draw" },
  },
}

for gen = 1, 3 do
  local r, ex = boot(gen)
  check(ex ~= nil, "gen" .. gen .. " loads")
  if ex then
    eq(ex.generation, gen, "gen" .. gen .. " detects its generation")
    local I = ex._internal
    check(I.arm ~= nil, "gen" .. gen .. " arm installed")
    for _, w in ipairs(I.core.warnings) do print("WARN", gen, w) end
    eq(#I.core.warnings, 0, "gen" .. gen .. " installs without warnings")
    for _, pair in ipairs(EXPECT[gen]) do
      check(patched(pair[1], pair[2]), ("gen%d patches %s.%s"):format(gen, pair[1], pair[2]))
    end

    -- the schema: EDIT START MENU first, the rest A-Z, every toggle OFF
    local schema = I.V.SCHEMA
    eq(schema[1].key, "edit_start_menu", "gen" .. gen .. " EDIT START MENU is first")
    eq(schema[1].choices[1][1]:find("OPEN") ~= nil, true,
      "gen" .. gen .. " the editor row says how to open it")
    check(not schema[1].choices[1][1]:find("[<>]"),
      "gen" .. gen .. " the editor row has no arrows in its text")
    for i = 3, #schema do
      check(schema[i - 1].label < schema[i].label,
        ("gen%d %s sorts before %s"):format(gen, schema[i - 1].label, schema[i].label))
    end
    local hasCam, hasFull = false, false
    local whole = {}
    for _, v in ipairs((gen == 3 and I.arm.LONG_VALUES) or {}) do whole[v] = true end
    for i = 2, #schema do
      local row = schema[i]
      if row.key == "center_camera" then hasCam = true end
      if row.key == "full_screen_menus" then hasFull = true end
      -- every toggle changes nothing until it is turned on; LOW HP BEEP's
      -- first value is the normal game, which it says in its label
      local offish = row.default == false or row.default == "off" or row.default == "normal"
        or (row.key == "low_hp_beep" and row.default == "on")
      check(offish, ("gen%d %s defaults to the normal game"):format(gen, row.key))
      for _, choice in ipairs(row.choices or {}) do
        if gen == 3 then
          -- Gen 3's manager cuts a value at eight characters unless the
          -- arm draws it whole
          check(#choice[1] <= 8 or whole[choice[1]],
            ("gen%d %s value %q fits the GBA column"):format(gen, row.key, choice[1]))
        else
          -- the Game Boy options box fits sixteen
          check(#choice[1] <= 16,
            ("gen%d %s value %q fits the options box"):format(gen, row.key, choice[1]))
        end
      end
    end
    eq(hasCam, gen ~= 3, "gen" .. gen .. " CENTER CAMERA row only on Game Boy games")
    eq(hasFull, gen == 3, "gen" .. gen .. " FULL SCREEN MENUS row only on GBA games")

    -- LOW HP BEEP reads ON (BEEPS), OFF (MUTED): two settings
    for _, row in ipairs(schema) do
      if row.key == "low_hp_beep" then
        eq(row.default, "on", "gen" .. gen .. " LOW HP BEEP defaults to the normal beeps")
        eq(row.choices[1][1], "ON (BEEPS)", "gen" .. gen .. " LOW HP BEEP starts at ON (BEEPS)")
        eq(row.choices[1][2], "on", "gen" .. gen .. " which is the normal game")
        eq(#row.choices, 2, "gen" .. gen .. " LOW HP BEEP has two settings")
        eq(row.choices[2][1], "OFF (MUTED)", "gen" .. gen .. " then OFF (MUTED)")
        eq(row.choices[2][2], "mute", "gen" .. gen .. " which mutes it")
      end
      if row.key == "scrolling" then
        eq(#row.choices, 3, "gen" .. gen .. " SCROLLING has three speeds")
        eq(row.choices[2][2], "normal", "gen" .. gen .. " SCROLLING NORMAL is the middle one")
      end
    end
    local hasRun = false
    for _, row in ipairs(schema) do if row.key == "running_shoes" then hasRun = true end end
    eq(hasRun, true, "gen" .. gen .. " has the RUNNING SHOES row")

    -- the QOL COMP row in the game's own OPTIONS screen
    do
      local Runtime = require("src.mods.Runtime")
      local okRows, rows = pcall(Runtime.call, "ui.options.rows",
        function(_, r) return r end, nil, { { id = "sound", label = "SOUND" } })
      local found
      for _, row in ipairs(okRows and type(rows) == "table" and rows or {}) do
        if row.id == "qol_comp" then found = row end
      end
      check(found ~= nil, "gen" .. gen .. " adds a QOL COMP row to OPTIONS")
      if found then
        eq(type(found.activate), "function", "gen" .. gen .. " the OPTIONS row opens on A")
        check(tostring(found.value()):find("OPTIONS") ~= nil,
          "gen" .. gen .. " the OPTIONS row counts this mod's rows")
      end
      -- a second pass must not add it twice
      local _, again = pcall(Runtime.call, "ui.options.rows",
        function(_, r) return r end, nil, rows)
      local n = 0
      for _, row in ipairs(type(again) == "table" and again or {}) do
        if row.id == "qol_comp" then n = n + 1 end
      end
      eq(n, 1, "gen" .. gen .. " the OPTIONS row is added once")
    end

    -- DECAPITALIZATION really reaches the glyphs.  The conversion is tested
    -- on its own further down; this checks the engine's own drawing path
    -- hands the FONT the converted text, which is the thing that was
    -- missing when the toggle looked like it did nothing.
    do
      local seen
      local fontMods = (gen == 3)
        and { { "src.ui.game3.frlg_font", "draw" }, { "src.ui.game3.frlg_font", "measure" },
              { "src.ui.game3.frlg_font", "wrap" } }
        or { { "src.render.Font", "encode" } }
      -- off: the font is the engine's own, so nothing is measured uncached
      setOpt(I, "decap", false)
      for _, pair in ipairs(fontMods) do
        check(not patched(pair[1], pair[2]),
          ("gen%d %s.%s is untouched while DECAPITALIZATION is off")
            :format(gen, pair[1], pair[2]))
      end
      setOpt(I, "decap", true)
      for _, pair in ipairs(fontMods) do
        check(patched(pair[1], pair[2]),
          ("gen%d %s.%s is wrapped while it is on"):format(gen, pair[1], pair[2]))
      end
      setOpt(I, "decap", false)
      if gen == 3 then
        local FrlgFont = require("src.ui.game3.frlg_font")
        local origScan = FrlgFont.scanTokens
        FrlgFont.scanTokens = function(text, ...)
          seen = text
          return origScan(text, ...)
        end
        setOpt(I, "decap", true)
        pcall(FrlgFont.measure, "RED got a POTION!")
        local hot = seen
        setOpt(I, "decap", false)
        pcall(FrlgFont.measure, "RED got a POTION!")
        FrlgFont.scanTokens = origScan
        eq(hot, "Red got a Potion!", "gen3 the font measures the decapitalised text")
        eq(seen, "RED got a POTION!", "gen3 and the cart's own text with the toggle off")
      else
        local Font = require("src.render.Font")
        local origSplit = Font.split
        Font.split = function(text, ...)
          seen = text
          return origSplit(text, ...)
        end
        setOpt(I, "decap", true)
        pcall(Font.encode, "RED got a POTION!")
        local hot = seen
        setOpt(I, "decap", false)
        pcall(Font.encode, "RED got a POTION!")
        Font.split = origSplit
        eq(hot, "Red got a Potion!",
          ("gen%d the font encodes the decapitalised text"):format(gen))
        eq(seen, "RED got a POTION!",
          ("gen%d and the cart's own text with the toggle off"):format(gen))
      end
    end

    -- the party submenu's own rows exist AND fire.  A row that is drawn but
    -- does nothing is the failure this covers.
    do
      local fired = {}
      local arm = I.arm
      local realRename, realRelearn = arm.A.rename, arm.A.relearn
      arm.A.rename = function() fired.rename = true end
      arm.A.relearn = function() fired.relearn = true end
      setOpt(I, "rename", true)
      setOpt(I, "relearn_moves", true)
      local mon = { species = (gen == 3) and 1 or "PIKACHU", level = 20, hp = 10,
        maxHp = 10, moves = (gen == 3) and { 33 } or { { id = "TACKLE" } } }
      -- the hook edits the list it is handed, so each call gets a fresh one
      local function base()
        return { { label = "STATS", action = (gen == 3) and "SUMMARY" or "stats" },
                 { label = "CANCEL", action = (gen == 3) and "CANCEL" or "cancel" } }
      end
      local Runtime = require("src.mods.Runtime")
      local okRows, rows = pcall(Runtime.call, "ui.party.submenu",
        function(_, items) return items end, { data = r.data }, base(), mon, { battle = false })
      local rename, relearn
      for _, row in ipairs(okRows and type(rows) == "table" and rows or {}) do
        if row.id == "QOL_RENAME" then rename = row end
        if row.id == "QOL_RELEARN" then relearn = row end
      end
      check(rename ~= nil, ("gen%d the party submenu gets a RENAME row"):format(gen))
      check(relearn ~= nil, ("gen%d the party submenu gets a RELEARN row"):format(gen))
      if rename then rename.onSelect(mon, { data = r.data }) end
      if relearn then relearn.onSelect(mon, { data = r.data }) end
      eq(fired.rename, true, ("gen%d A on RENAME runs it"):format(gen))
      eq(fired.relearn, true, ("gen%d A on RELEARN runs it"):format(gen))
      -- and a row whose action throws tells the player instead of doing nothing
      local said
      local realSay = arm.A.say
      arm.A.say = function(_, text) said = text end
      arm.A.rename = function() error("boom", 0) end
      local _, rows2 = pcall(Runtime.call, "ui.party.submenu",
        function(_, items) return items end, { data = r.data }, base(), mon, { battle = false })
      for _, row in ipairs(type(rows2) == "table" and rows2 or {}) do
        if row.id == "QOL_RENAME" then row.onSelect(mon, { data = r.data }) end
      end
      check(type(said) == "string" and said ~= "",
        ("gen%d a row that cannot run says so"):format(gen))
      arm.A.rename, arm.A.relearn, arm.A.say = realRename, realRelearn, realSay
      setOpt(I, "rename", false)
      setOpt(I, "relearn_moves", false)
      -- nothing is added inside a battle
      local _, rows3 = pcall(Runtime.call, "ui.party.submenu",
        function(_, items) return items end, { data = r.data }, base(), mon, { battle = true })
      eq(#(type(rows3) == "table" and rows3 or {}), 2,
        ("gen%d the battle list is left alone"):format(gen))
    end

    -- FAST POKECENTER: FAST keeps the greeting and drops the question page
    if gen == 1 then
      eq(I.arm.greetingPage("Welcome!\fSHALL WE HEAL?"), "Welcome!",
        "gen1 FAST shows the greeting and not the question")
      eq(I.arm.greetingPage("Welcome!"), "Welcome!",
        "gen1 a later visit has only the greeting")
    end

    -- the lead pick's seam, per generation
    if gen == 2 then
      local screen = { queue = { { kind = "message" }, { kind = "sendout" } } }
      local at, row = I.arm.findSendout(screen)
      eq(at, 2, "gen2 the pick goes on the native send-out row")
      eq(row and row.kind, "sendout", "gen2 and it owns that row")
      eq(I.arm.findSendout({ queue = { { kind = "message" } } }), nil,
        "gen2 a screen with no send-out row is left alone")
      eq(I.arm.legalLead({ hp = 0 }), false, "gen2 a fainted mon cannot lead")
      eq(I.arm.legalLead({ hp = 5, isEgg = true }), false, "gen2 nor an egg")
      eq(I.arm.legalLead({ hp = 5 }), true, "gen2 a healthy one can")
    end
    if gen == 3 then
      local steps = {
        { kind = "msg", data = { text = "wants to battle!" } },
        { kind = "opponent_sendout", data = {} },
        { kind = "healthbox", data = { side = "enemy" } },
        { kind = "msg", data = { text = "GOLINE" } },
        { kind = "player_throw", data = {} },
      }
      local st = { player = { mon = {} } }
      local IntroSeq = require("src.core.game3.battle.intro_seq")
      local realText = IntroSeq.sendOutText
      IntroSeq.sendOutText = function(_, side)
        return side == "player" and "GOLINE" or "foe"
      end
      local at, step = I.arm.introSendOutIndex(steps, st)
      IntroSeq.sendOutText = realText
      eq(at, 4, "gen3 the pick goes just before the player's Go! message")
      eq(step and step.data.text, "GOLINE", "gen3 and it owns that message")
      -- a reworded line still anchors on the throw itself
      local at2 = I.arm.introSendOutIndex({ { kind = "player_throw", data = {} } }, st)
      eq(at2, 1, "gen3 the throw is the fallback anchor")
      eq(I.arm.introSendOutIndex({ { kind = "msg", data = {} } }, st), nil,
        "gen3 an intro with neither is left alone")
    end

    -- LOW HP BEEP: OFF (MUTED) keeps the siren from starting, ON (BEEPS)
    -- leaves it alone, and an old saved REDUCED / OFF reads as ON (BEEPS)
    do
      local Runtime = require("src.mods.Runtime")
      local started = 0
      local vanilla = function(ctx) if ctx.on then started = started + 1 end end
      setOpt(I, "low_hp_beep", "on")
      pcall(Runtime.call, "battle.low_health_alarm", vanilla, { on = true, battle = {} })
      eq(started, 1, ("gen%d ON (BEEPS) lets the siren start"):format(gen))
      setOpt(I, "low_hp_beep", "mute")
      started = 0
      pcall(Runtime.call, "battle.low_health_alarm", vanilla, { on = true, battle = {} })
      eq(started, 0, ("gen%d OFF (MUTED) never starts the siren"):format(gen))
      for _, old in ipairs({ "reduced", "off" }) do
        setOpt(I, "low_hp_beep", old)
        eq(I.common.lowHpMode(), "on", ("gen%d an old %s setting means the normal beeps"):format(gen, old))
      end
      setOpt(I, "low_hp_beep", "on")
    end

    -- RENAME writes the new name, keeps the old one on an empty or unchanged
    -- answer.  The bug this covers: the screen opened, but the name typed
    -- into it was never written to the Pokemon.
    do
      local A = I.arm.A
      local mon = { species = (gen == 3) and 4 or "CHARMANDER", level = 10, hp = 10,
        nickname = nil, name = (gen == 2) and "CHARMANDER" or nil }
      local opened
      local game = { data = r.data, stack = { push = function() end, pop = function() end } }
      local restore
      if gen == 1 then
        local Screens = require("src.ui.Screens")
        local real = Screens.push
        Screens.push = function(_, id, opts) opened = { id = id, opts = opts } return {} end
        restore = function() Screens.push = real end
      elseif gen == 2 then
        game.world = { renameMon = function(_, m, cb)
          opened = { id = "Gen2NamingScreen", opts = { onDone = cb } }
          return true
        end }
      else
        local Naming = require("src.ui.game3.naming")
        local real = Naming.open
        Naming.open = function(opts) opened = { id = "naming", opts = opts } return {} end
        restore = function() Naming.open = real end
      end
      local ok, err = pcall(A.rename, game, mon)
      check(ok, ("gen%d RENAME opens without error (%s)"):format(gen, tostring(err)))
      check(opened ~= nil, ("gen%d RENAME opens the naming screen"):format(gen))
      if gen == 3 and opened then
        eq(opened.opts.template, "NICKNAME", "gen3 RENAME uses the Name Rater's template")
        eq(opened.opts.maxLen, 10, "gen3 RENAME allows ten characters")
      end
      local done = opened and opened.opts and opened.opts.onDone
      if done then
        done("SPARKY")
        eq(mon.nickname, "SPARKY", ("gen%d the new name is written to the Pokemon"):format(gen))
        done("")
        eq(mon.nickname, "SPARKY", ("gen%d an empty answer keeps the name"):format(gen))
        done(nil)
        eq(mon.nickname, "SPARKY", ("gen%d backing out keeps the name"):format(gen))
      end
      if restore then restore() end
    end

    if gen == 3 then
      -- RELEARN opens the relearner the cart's NPC opens for this game
      local A = I.arm.A
      local Profile = require("src.core.game3.profile")
      local MoveLearn = require("src.core.game3.move_learn")
      local Rse = require("src.ui.game3.rse.move_relearner")
      local Frlg = require("src.ui.game3.move_relearner")
      local realFamily, realMoves = Profile.family, MoveLearn.relearnableMoves
      local realRse, realFrlg = Rse.show, Frlg.show
      local shown
      Rse.show = function(mon) shown = "rse" end
      Frlg.show = function(mon) shown = "frlg" end
      MoveLearn.relearnableMoves = function() return { 33 } end
      Profile.family = function() return "rse" end
      pcall(A.relearn, {}, { species = 4 })
      eq(shown, "rse", "gen3 RELEARN on Ruby/Sapphire/Emerald opens their relearner")
      Profile.family = function() return "frlg" end
      shown = nil
      pcall(A.relearn, {}, { species = 4 })
      eq(shown, "frlg", "gen3 RELEARN on FireRed/LeafGreen opens theirs")
      -- nothing to relearn: said on screen, no empty screen
      local said
      local realSay = A.say
      A.say = function(_, text) said = text end
      MoveLearn.relearnableMoves = function() return {} end
      shown = nil
      pcall(A.relearn, {}, { species = 4 })
      eq(shown, nil, "gen3 RELEARN with nothing to relearn opens no screen")
      check(type(said) == "string", "gen3 and says so instead")
      A.say = realSay
      Profile.family, MoveLearn.relearnableMoves = realFamily, realMoves
      Rse.show, Frlg.show = realRse, realFrlg

      -- RUNNING SHOES (B TO RUN) answers the game's own run check yes
      -- anywhere you can walk (no shoes flag, no "no running here"); the
      -- step itself is never touched
      -- (0.1.2 rebuilt the step, and Emerald's sprite flickered)
      local Player = require("src.core.game3.player")
      check(rawget(Player, "__qol_comp_orig_ordinaryStepFrames") == nil,
        "gen3 the run step and its animation are the game's own")
      local Space = require("src.core.game3.scripting.space")
      local realStore = Space.getStore
      Space.getStore = function() return {} end
      local realDisallowed = Player.runningDisallowed
      local blocked = false
      Player.runningDisallowed = function() return blocked end
      setOpt(I, "running_shoes", "off")
      eq(Player.canDash(), false, "gen3 OFF: no shoes, no run (vanilla)")
      setOpt(I, "running_shoes", "b")
      eq(Player.canDash(), true, "gen3 B TO RUN: runs without the shoes")
      blocked = true
      eq(Player.canDash(), true, "gen3 B TO RUN: runs where the game forbids running (indoors, long grass...)")
      setOpt(I, "running_shoes", "off")
      eq(Player.canDash(), false, "gen3 OFF: the game's own rules there")
      setOpt(I, "running_shoes", "b")
      blocked = false
      Player.underwater = true
      eq(Player.canDash(), false, "gen3 not underwater")
      Player.underwater = false
      Player.biking = true
      eq(Player.canDash(), false, "gen3 not on a bike")
      Player.biking = false
      Player.surfing = true
      eq(Player.canDash(), false, "gen3 not while surfing")
      Player.surfing = false
      Space.getStore = function() return nil end
      eq(Player.canDash(), false, "gen3 not before the field is up")
      Space.getStore, Player.runningDisallowed = realStore, realDisallowed
      setOpt(I, "running_shoes", "off")

      -- the mod's own screens take each press once.  The bug this covers:
      -- the HUD and the mod both drove the screen, a frame apart.
      local UI = I.ui
      local Stack = require("src.ui.game3.stack")
      local presses = {}
      local fakeInput = { wasPressed = function(_, b) return presses[b] == true end,
        isDown = function() return false end }
      local screen = UI.open({ input = fakeInput }, { title = "T", rows = function()
        return { { label = "ONE" }, { label = "TWO" }, { label = "THREE" } } end })
      local top = Stack.top()
      check(top and top.mod and top.mod.qolCompScreen, "gen3 the list screen is on the UI stack")
      I.V.frame = 1000
      presses.down = true
      top.mod.handleInput(fakeInput)
      top.mod.handleInput(fakeInput)
      eq(screen.index, 2, "gen3 a press reaches the mod's screen once per frame")
      I.V.frame = 1001
      top.mod.handleInput(fakeInput)
      eq(screen.index, 3, "gen3 and the next frame's press is taken")
      presses.down = nil
      screen:close()

      -- the long LOW HP BEEP values are drawn whole on this mod's page of
      -- the Gen 3 manager, and other pages keep the manager's own cut
      do
        local MM = require("src.ui.game3.mod_manager")
        local FrlgFont = require("src.ui.game3.frlg_font")
        local seen = {}
        local realDraw = FrlgFont.draw
        FrlgFont.draw = function(text) seen[text] = true return 0 end
        local wasOpen, wasMgr = MM.open, MM._mgr
        MM.open = true
        MM._mgr = { screen = "options", cursor = 1, tab = 1, optionRows = {
          { id = "edit_start_menu", label = "EDIT START MENU", value = function() return "OPEN" end },
          { id = "low_hp_beep", label = "LOW HP BEEP", value = function() return "OFF (MUTED)" end },
        } }
        pcall(MM.draw)
        eq(seen["OFF (MUTED)"], true, "gen3 OFF (MUTED) is drawn whole in the manager")
        seen = {}
        MM._mgr = { screen = "options", cursor = 1, tab = 1, optionRows = {
          { id = "other", label = "OTHER MOD", value = function() return "OFF (MUTED)" end },
        } }
        pcall(MM.draw)
        eq(seen["OFF (MUT"], true, "gen3 another mod's page is cut as before")
        MM.open, MM._mgr = wasOpen, wasMgr
        FrlgFont.draw = realDraw
      end

      -- in a game the HUD drives the mod's screens; the mod's own pass only
      -- runs when the HUD has not (the title screen's manager)
      do
        local Hud = require("src.ui.game3.hud")
        local hudRan = I.arm._hudFrame
        I.V.frame = 5000
        pcall(Hud.update, nil, 1 / 60)
        eq(hudRan(), 5000, "gen3 the HUD's frame is noted")
      end

      -- FULL SCREEN MENUS: a menu that covers the field is scaled, the
      -- START menu over the field is not
      Stack.push("bag_menu", {}, { isMenu = true, hideBelow = true })
      eq(I.arm.fullScreenMenuUp(), true, "gen3 a full-screen menu is scaled")
      Stack.pop("bag_menu")
      Stack.push("start_menu", {}, { isMenu = true, hideBelow = true })
      eq(I.arm.fullScreenMenuUp(), false, "gen3 the START menu is left alone")
      Stack.pop("start_menu")
      -- the frame-composite hook only goes in once the option is first on
      setOpt(I, "full_screen_menus", false)
      eq(r.loader.hooks.chains["render.compose"], nil,
        "gen3 FULL SCREEN MENUS adds no frame hook while never turned on")
      setOpt(I, "full_screen_menus", true)
      local chain = r.loader.hooks.chains["render.compose"]
      check(chain ~= nil and #chain >= 1, "gen3 FULL SCREEN MENUS hooks the frame composite")
      setOpt(I, "full_screen_menus", false)
      setOpt(I, "full_screen_menus", true)
      eq(#(r.loader.hooks.chains["render.compose"] or {}), 1,
        "gen3 and turning it on again does not hook it twice")
      local drew = false
      local Runtime = require("src.mods.Runtime")
      local canvas = { getDimensions = function() return 240, 160 end, setFilter = function() end }
      local realDraw = love.graphics.draw
      love.graphics.draw = function() drew = true end
      Stack.push("bag_menu", {}, { isMenu = true, hideBelow = true })
      setOpt(I, "full_screen_menus", false)
      local _, off = pcall(Runtime.call, "render.compose", function() return false end, {},
        { uiCanvas = canvas, ww = 1280, wh = 720 })
      eq(off == true, false, "gen3 FULL SCREEN MENUS OFF leaves the frame to the engine")
      setOpt(I, "full_screen_menus", true)
      local _, on = pcall(Runtime.call, "render.compose", function() return false end, {},
        { uiCanvas = canvas, ww = 1280, wh = 720 })
      eq(on, true, "gen3 FULL SCREEN MENUS ON draws the menu scaled")
      check(drew, "gen3 and the scaled menu is drawn")
      setOpt(I, "full_screen_menus", false)
      Stack.pop("bag_menu")
      love.graphics.draw = realDraw

      -- LONG VALUES: Window.printPx (all GBA text) is only wrapped while
      -- this mod's own options page draws, and is put back afterwards
      local Window = require("src.ui.game3.window")
      local MM = require("src.ui.game3.mod_manager")
      eq(rawget(Window, "__qol_comp_orig_printPx"), nil,
        "gen3 Window.printPx is not patched outside the options page")
      local livePx = Window.printPx
      local printed = {}
      local stubPx = function(text, px) printed[#printed + 1] = { text, px } end
      Window.printPx = stubPx
      local saveMgr = MM._mgr
      MM._mgr = { screen = "options", optionRows = { { id = "edit_start_menu" } } }
      local okDraw, errDraw = pcall(MM.draw)
      eq(Window.printPx, stubPx, "gen3 printPx is put back after the options page draws")
      MM._mgr = saveMgr
      Window.printPx = livePx
    end

    -- PERFORMANCE (0.1.32): option values are kept between frames, and
    -- re-read on an options change or every 120 frames at the latest
    do
      local C = I.core
      setOpt(I, "hidden_shine", false)
      eq(C.opt("hidden_shine"), false, "gen" .. gen .. " option read")
      C.opts.hidden_shine = true -- changed behind the mod's back, no event
      local f0 = (I.V.frame or 0) + 1000000
      C.newFrame(f0)
      C.newFrame(f0 + 1)
      eq(C.opt("hidden_shine"), true, "gen" .. gen .. " a quiet option change is picked up on the safety re-read")
      C.opts.hidden_shine = false
      C.newFrame(f0 + 2)
      eq(C.opt("hidden_shine"), true, "gen" .. gen .. " and kept between frames until then")
      C.newFrame(f0 + 2 + 120)
      eq(C.opt("hidden_shine"), false, "gen" .. gen .. " and re-read within 120 frames")
      C.opts.hidden_shine = true
      C.refresh()
      eq(C.opt("hidden_shine"), true, "gen" .. gen .. " an options change re-reads at once")
      setOpt(I, "hidden_shine", false)
    end

    -- v1.5: with RENAME on, a Pokemon arrives without a nickname question
    do
      local tag = "gen" .. gen .. " "
      local Runtime = require("src.mods.Runtime")
      rawset(I.core.opts, "rename", nil)
      local function rename(v)
        r.loader.modOptions.qol_comp = r.loader.modOptions.qol_comp or {}
        r.loader.modOptions.qol_comp.rename = v
        I.core.refresh()
      end
      local alwaysAsk = function() return true end
      rename(false)
      local _, asked = pcall(Runtime.call, "catch.nickname", alwaysAsk, { species = 1 }, {})
      eq(asked, true, tag .. "RENAME off: a catch still asks for a nickname")
      rename(true)
      local _, skipped = pcall(Runtime.call, "catch.nickname", alwaysAsk, { species = 1 }, {})
      eq(skipped, false, tag .. "RENAME on: a catch keeps the species name, no question")
      local gift = { species = 1, level = 5, isEgg = false }
      pcall(Runtime.emit, "pokemon.before_give", gift)
      eq(gift.nickname, "", tag .. "RENAME on: a gift skips the question")
      local named = { species = 1, level = 5, nickname = "SHUCKIE" }
      pcall(Runtime.emit, "pokemon.before_give", named)
      eq(named.nickname, "SHUCKIE", tag .. "a name the game gives is kept")
      local egg = { species = 1, level = 5, isEgg = true }
      pcall(Runtime.emit, "pokemon.before_give", egg)
      eq(egg.nickname, nil, tag .. "an egg is left alone")
      rename(false)
      local plain = { species = 1, level = 5 }
      pcall(Runtime.emit, "pokemon.before_give", plain)
      eq(plain.nickname, nil, tag .. "RENAME off: a gift asks as normal")

      if gen == 2 then
        local NS = I.nickskip
        local CommonText = require("src.core.gen2.CommonText")
        local World = require("src.world.gen2.World")
        local realGet = CommonText.get
        CommonText.get = function(_, key)
          if key == "_BreedAskNicknameText" then return "Give a nickname to\n{STRBUF}?" end
          return realGet(_, key)
        end
        local w = setmetatable({ lastText = "Give a nickname to\nTOGEPI?", text = {} }, { __index = World })
        eq(NS._isHatchQuestion(w), true, tag .. "the hatch question is recognised")
        local other = setmetatable({ lastText = "Want to SAVE?", text = {} }, { __index = World })
        eq(NS._isHatchQuestion(other), false, tag .. "and no other question is")
        rename(true)
        local answer
        World.askYesNo(w, function(yes) answer = yes end)
        eq(answer, false, tag .. "RENAME on: the hatch question is answered NO unseen")
        rename(false)
        CommonText.get = realGet
        check(patched("src.script.gen2.Specials", "askNickname"),
          tag .. "the Bug-Catching Contest question is covered")
      end

      if gen == 3 then
        local NS = I.nickskip
        check(patched("src.ui.game3.egg_hatch", "update"), tag .. "the FRLG/Emerald hatch question is covered")
        check(patched("src.ui.game3.rs.egg_hatch", "update"), tag .. "the Ruby/Sapphire hatch question is covered")
        local EggHatch = require("src.ui.game3.egg_hatch")
        local savedState, savedTimer = EggHatch._state, EggHatch._timer
        rename(true)
        EggHatch._state = "nickname_msg"
        NS._afterHatchUpdate()
        eq(EggHatch._state, "fade_out", tag .. "RENAME on: the hatched Pokemon is not asked for a name")
        EggHatch._state, EggHatch._timer = savedState, savedTimer
        rename(false)

        local RomText = require("src.core.game3.rom_text")
        local TextIR = require("src.core.game3.scripting.text_ir")
        local Q = "Text_GiveNicknameToThisMon"
        local was = RomText.overrides[Q]
        local ir = TextIR.fromAscii("Do you want to give a\nnickname to this BULBASAUR?")
        RomText.overrides[Q] = ir
        local vm = { ctx = { stringVars = {}, data = {} },
          getText = function(_, k) if k == "g3:00001234" then return ir end end }
        eq(NS._isGiftQuestion(vm, { ptr = 0x1234 }), true, tag .. "a gift's nickname question is recognised")
        local vm2 = { ctx = { stringVars = {}, data = {} },
          getText = function() return TextIR.fromAscii("Here, take this.") end }
        eq(NS._isGiftQuestion(vm2, { ptr = 0x9999 }), false, tag .. "and an ordinary line is not")
        rename(true)
        local reached = {}
        local vanilla = function(_, op) reached[#reached + 1] = op return false end
        for _, op in ipairs({ "message", "waitmessage", "yesnobox" }) do
          pcall(Runtime.call, "script.command", vanilla, { vm = vm }, op, { ptr = 0x1234, op = op })
        end
        eq(#reached, 0, tag .. "RENAME on: the gift question and its YES/NO never show")
        pcall(Runtime.call, "script.command", vanilla, { vm = vm2 }, "message", { ptr = 0x9999 })
        eq(reached[1], "message", tag .. "and the script's next line shows as normal")
        rename(false)
        reached = {}
        pcall(Runtime.call, "script.command", vanilla, { vm = vm }, "message", { ptr = 0x1234 })
        eq(reached[1], "message", tag .. "RENAME off: the gift question shows")
        RomText.overrides[Q] = was
      end
    end

    -- v1.52: the editor's list IS the START menu's order -- including rows
    -- that unlock after the menu was first learned (Crystal's POKEDEX and
    -- POKEGEAR), a layout never edited, and a row moved after that
    if gen == 2 then
      local tag = "gen2 "
      local SM = I.startmenu
      local Runtime = require("src.mods.Runtime")
      SM.reset(); SM._setKnown({}, {})
      local function build(rows)
        local items = {}
        for i, id in ipairs(rows) do items[i] = { value = id, label = id:upper() } end
        local _, out = pcall(Runtime.call, "ui.start_menu.items", function(_, x) return x end, nil, items)
        local o = {}
        for i, it in ipairs(out) do o[i] = SM.keyOf(it) end
        return table.concat(o, ",")
      end
      local function editor()
        local o = {}
        for i, row in ipairs(SM._editorRows()) do o[i] = row.key end
        return table.concat(o, ",")
      end
      local early = { "pokemon", "pack", "status", "save", "option", "mods", "quit" }
      local later = { "pokedex", "pokemon", "pack", "pokegear", "status", "save", "option", "mods", "quit" }
      build(early)
      eq(build(later), "POKEDEX,POKEMON,PACK,POKEGEAR,STATUS,SAVE,OPTION,MODS,QUIT",
        tag .. "rows unlocked later keep the game's order")
      eq(editor(), "POKEDEX,POKEMON,PACK,POKEGEAR,STATUS,SAVE,OPTION,MODS,QUIT",
        tag .. "and the editor lists them in that same order")
      -- a layout set BEFORE POKEDEX and POKEGEAR unlock, then they unlock
      SM.reset(); SM._setKnown({}, {})
      build(early)
      SM._setLayout({ "SAVE", "POKEMON", "PACK", "STATUS", "OPTION", "MODS", "QUIT" }, {})
      eq(build(early), "SAVE,POKEMON,PACK,STATUS,OPTION,MODS,QUIT", tag .. "the layout as set")
      eq(build(later), "SAVE,POKEDEX,POKEMON,PACK,POKEGEAR,STATUS,OPTION,MODS,QUIT",
        tag .. "an unlocked row goes just above the row below it in the game's menu")
      eq(editor(), "SAVE,POKEDEX,POKEMON,PACK,POKEGEAR,STATUS,OPTION,MODS,QUIT",
        tag .. "and the editor shows it right there")
      -- and once placed, it stays where it is put
      SM._setLayout({ "QUIT", "POKEGEAR", "SAVE", "POKEDEX", "POKEMON", "PACK", "STATUS", "OPTION", "MODS" }, {})
      build(early)
      eq(build(later), "QUIT,POKEGEAR,SAVE,POKEDEX,POKEMON,PACK,STATUS,OPTION,MODS",
        tag .. "every row stays exactly where it was put")
      eq(editor(), "QUIT,POKEGEAR,SAVE,POKEDEX,POKEMON,PACK,STATUS,OPTION,MODS",
        tag .. "the editor is that same column")
      SM.reset(); SM._setKnown({}, {})
    end

    -- v1.53: every edit lands exactly where the player steered it, and
    -- stays there.  The test keeps its own model of the column (MOVE swaps
    -- neighbours, an unlocked row goes just above the row below it in the
    -- game's menu) and Crystal's real START menu must match it after every
    -- edit, in the menu still open behind the editor and in fresh ones.
    if gen == 2 then
      local tag = "gen2 "
      local SM = I.startmenu
      SM.reset(); SM._setKnown({}, {})
      local Start2 = require("src.ui.gen2.StartMenu")
      local realText = r.data.text
      r.data.text = setmetatable({}, { __index = function(_, k)
        local n = tostring(k):match("^StartMenu%.(.-)String$")
        return n and n:upper() or "TXT"
      end })
      local GAME = { "pokedex", "pokemon", "pack", "pokegear", "status", "save", "option", "mods", "quit" }
      local states, presses = {}, {}
      local input = { wasPressed = function(_, b) return presses[b] == true end,
        isDown = function() return false end }
      local game = { data = r.data, input = input, modStatus = { available = { {} } },
        save = { player = { name = "KRIS" }, party = { {} }, options = {} },
        stack = { states = states,
          push = function(_, st) states[#states + 1] = st end,
          pop = function() return table.remove(states) end,
          top = function() return states[#states] end } }
      local unlocked = { mods = true, pokedex = false, party = true, pack = true, pokegear = false }
      local function open()
        local m = Start2.new(game, { save = game.save, unlocked = unlocked })
        m.screenId = "Gen2StartMenu"
        return m
      end
      local function ids(m) local o = {} for i, it in ipairs(m.items) do o[i] = it.value end return table.concat(o, ",") end
      local model, hidden = {}, {}
      for v in ids(open()):gmatch("[^,]+") do model[#model + 1] = v end
      local function unlock(id)
        if unlocked[id] then return end
        unlocked[id] = true
        local gi
        for i, g in ipairs(GAME) do if g == id then gi = i end end
        local at
        for j = gi + 1, #GAME do
          for p, m in ipairs(model) do if m == GAME[j] then at = p break end end
          if at then break end
        end
        table.insert(model, at or (#model + 1), id)
      end
      local function want()
        local o = {}
        for _, id in ipairs(model) do if not hidden[id] or id == "mods" then o[#o + 1] = id end end
        return table.concat(o, ",")
      end
      local seed = 1
      local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return seed % n + 1 end
      local bad, firstBad = 0, nil
      for step = 1, 160 do
        if step == 40 then unlock("pokedex") end
        if step == 90 then unlock("pokegear") end
        for i = #states, 1, -1 do states[i] = nil end
        local menu = open()
        states[1] = menu
        SM.openEditor(game)
        local ed = states[#states]
        local function press(b)
          for k in pairs(presses) do presses[k] = nil end
          presses[b] = true; ed:update(); presses[b] = nil
        end
        local at = rnd(#model)
        SM._lastEditor.index = at
        local act = rnd(10)
        press("a")
        if act <= 7 then
          press("a")
          local pos = at
          for _ = 1, rnd(5) do
            local d = rnd(2) == 1 and -1 or 1
            press(d < 0 and "up" or "down")
            local j = pos + d
            if j >= 1 and j <= #model then model[pos], model[j] = model[j], model[pos]; pos = j end
          end
          press("a")
        elseif act <= 9 and model[at] ~= "mods" then
          press("down"); press("a"); hidden[model[at]] = not hidden[model[at]]
        else
          press("b")
        end
        press("b")
        local w = want()
        if ids(menu) ~= w or ids(open()) ~= w or ids(open()) ~= w then
          bad = bad + 1
          firstBad = firstBad or ("step " .. step .. ": want " .. w .. " got " .. ids(open()))
        end
      end
      eq(bad, 0, tag .. "160 random edits: the START menu is always exactly the column as edited"
        .. (firstBad and (" (" .. firstBad .. ")") or ""))
      SM.reset(); SM._setKnown({}, {})
      r.data.text = realText
    end

    -- v1.51: a layout edited while the START menu is still open under the
    -- editor (START -> OPTION -> QOL COMP -> EDIT START MENU) shows the
    -- moment you back out to it, not only after START is reopened
    if gen == 2 then
      local tag = "gen2 "
      local SM = I.startmenu
      SM.reset(); SM._setKnown({}, {})
      local Start2 = require("src.ui.gen2.StartMenu")
      local realText = r.data.text
      r.data.text = setmetatable({}, { __index = function(_, k)
        local n = tostring(k):match("^StartMenu%.(.-)String$")
        return n and n:upper() or "TXT"
      end })
      local states, presses = {}, {}
      local input = { wasPressed = function(_, b) return presses[b] == true end,
        isDown = function() return false end }
      local game = { data = r.data, input = input, modStatus = { available = { {} } },
        save = { player = { name = "KRIS" }, party = { {} }, options = {} },
        stack = { states = states,
          push = function(_, st) states[#states + 1] = st end,
          pop = function() return table.remove(states) end,
          top = function() return states[#states] end } }
      local unlocked = { mods = true, pokedex = true, party = true, pack = true, pokegear = true }
      local start = Start2.new(game, { save = game.save, unlocked = unlocked })
      start.screenId = "Gen2StartMenu"
      states[#states + 1] = start
      local function order(menu)
        local o = {}
        for i, it in ipairs(menu.items) do o[i] = tostring(it.value) end
        return table.concat(o, ",")
      end
      eq(order(start), "pokedex,pokemon,pack,pokegear,status,save,option,mods,quit",
        tag .. "Crystal's START menu as built")
      SM.openEditor(game)
      local ed = states[#states]
      local function press(b)
        for k in pairs(presses) do presses[k] = nil end
        presses[b] = true; ed:update(); presses[b] = nil
      end
      ed.index = 5                         -- the player's card
      press("a"); press("a")               -- A, MOVE
      for _ = 1, 4 do press("up") end
      press("a")                           -- set it down
      press("b")                           -- leave the editor
      eq(states[#states], start, tag .. "backing out lands on the START menu that was open")
      eq(order(start), "status,pokedex,pokemon,pack,pokegear,save,option,mods,quit",
        tag .. "and it already shows the new order")
      eq(tostring(start.list.items[1].value), "status", tag .. "the cursor list matches it")
      local fresh = Start2.new(game, { save = game.save, unlocked = unlocked })
      eq(order(fresh), "status,pokedex,pokemon,pack,pokegear,save,option,mods,quit",
        tag .. "and so does the next START menu")
      -- HIDE applies to the open menu too
      states[#states + 1] = ed; ed.open = true
      ed.index = 3
      press("a"); press("down"); press("a") -- A, HIDE
      check(not order(start):find("pokemon", 1, true), tag .. "a hidden row leaves the open menu")
      SM.reset()
      eq(order(start), "pokedex,pokemon,pack,pokegear,status,save,option,mods,quit",
        tag .. "and RESET LAYOUT restores it there too")
      SM._setKnown({}, {})
      r.data.text = realText
    elseif gen == 3 then
      local tag = "gen3 "
      local SM = I.startmenu
      SM.reset(); SM._setKnown({}, {})
      local SM3 = require("src.ui.game3.start_menu")
      local Runtime = require("src.mods.Runtime")
      local wasOpen, wasEntries, wasCursor = SM3.open, SM3.ENTRIES, SM3.cursor
      local wasTut, wasKind = SM3._tutorial, SM3._kind
      SM3._tutorial, SM3._kind = false, "normal"
      local entries = { { id = "pokedex", label = "POKeDEX" }, { id = "pokemon", label = "POKeMON" },
        { id = "bag", label = "BAG" }, { id = "trainer", label = "RED" }, { id = "save", label = "SAVE" },
        { id = "option", label = "OPTION" }, { id = "exit", label = "EXIT" } }
      local _, built = pcall(Runtime.call, "ui.start_menu.items", function(_, i) return i end, nil, entries)
      SM3.ENTRIES, SM3.open, SM3.cursor = built, true, 1
      SM._setLayout({ "TRAINER", "POKEDEX", "POKEMON", "BAG", "SAVE", "OPTION", "EXIT" }, { "BAG" })
      SM._refreshOpen()
      local o = {}
      for i, e in ipairs(SM3.ENTRIES) do o[i] = e.id end
      eq(table.concat(o, ","), "trainer,pokedex,pokemon,save,option,exit",
        tag .. "an open START menu takes a layout change at once")
      SM.reset()
      o = {}
      for i, e in ipairs(SM3.ENTRIES) do o[i] = e.id end
      eq(table.concat(o, ","), "pokedex,pokemon,bag,trainer,save,option,exit",
        tag .. "and RESET LAYOUT gives the hidden row back")
      SM3.open, SM3.ENTRIES, SM3.cursor, SM3._tutorial, SM3._kind = wasOpen, wasEntries, wasCursor, wasTut, wasKind
      SM._setKnown({}, {})
    end

    -- v1.5: RENAME in the PC's per-Pokemon menu
    do
      local tag = "gen" .. gen .. " "
      local A = I.arm.A
      local realRename = A.rename
      local renamed, renameOpts
      A.rename = function(_, m, opts) renamed, renameOpts = m, opts or {} end
      rawset(I.core.opts, "rename", nil)
      local function rename(v)
        r.loader.modOptions.qol_comp = r.loader.modOptions.qol_comp or {}
        r.loader.modOptions.qol_comp.rename = v
        I.core.refresh()
      end
      if gen == 1 then
        local Menu = require("src.ui.Menu")
        local mon = { species = "PIDGEY", level = 5 }
        local row = { label = "PIDGEY", value = 1 }
        local list = { kind = "pc_box_withdraw", index = 1, items = { row } }
        local game = { save = { boxes = { { mon } }, currentBox = 1, party = {} },
          stack = { top = function() return list end, push = function() end } }
        local Boxes = require("src.pokemon.Boxes")
        local realActive = Boxes.active
        Boxes.active = function() return game.save.boxes[1] end
        local function submenu()
          return Menu.new(game, { { label = "WITHDRAW" }, { label = "STATS", keepOpen = true },
            { label = "CANCEL" } }, { tx = 9, ty = 10, tw = 11, th = 8, noSound = true })
        end
        rename(false)
        eq(#submenu().items, 3, tag .. "RENAME off: the PC submenu is the cart's")
        rename(true)
        local m = submenu()
        eq(#m.items, 4, tag .. "RENAME on: the PC submenu gets a row")
        eq(m.items[3].label, "RENAME", tag .. "RENAME sits just above CANCEL")
        eq(m.ty .. "," .. m.th, "8,10", tag .. "and the box grows to hold it")
        m.items[3].onSelect()
        eq(renamed, mon, tag .. "RENAME names the Pokemon in the box")
        mon.nickname = "BIRDY"
        renameOpts.after(true)
        eq(row.label, "BIRDY", tag .. "and the box list shows the new name")
        list.kind = "party_menu"
        eq(#submenu().items, 3, tag .. "a menu that is not the PC's is untouched")
        Boxes.active = realActive
      elseif gen == 2 then
        local BoxMenu = require("src.ui.gen2.BoxMenu")
        local Chrome = require("src.ui.gen2.Chrome")
        local Boxes2 = require("src.core.gen2.Boxes")
        local mon = { species = "PIDGEY", level = 5, nickname = "PIDGEY" }
        local save = { boxes = { { mon } }, currentBox = 1, boxNames = { "BOX1" },
          party = { { species = "CYNDAQUIL", level = 5 } } }
        local realText = r.data.text
        r.data.text = setmetatable({}, { __index = function(_, k)
          local n = tonumber(tostring(k):match("#(%d)$"))
          return n and ({ "WITHDRAW", "STATS", "RELEASE", "CANCEL" })[n] or "TXT"
        end })
        local game = { data = r.data, save = save,
          stack = { push = function() end, pop = function() end, top = function() end } }
        local okNew, bm = pcall(BoxMenu.new, game, { mode = "withdraw", save = save })
        check(okNew, tag .. "the PC box screen opens headless")
        if okNew then
          bm.phase = "submenu"
          rename(false)
          eq(#bm:submenuRows(), 4, tag .. "RENAME off: the PC submenu is the cart's")
          rename(true)
          local rows = bm:submenuRows()
          local ids = {}
          for i, row in ipairs(rows) do ids[i] = row.id end
          eq(table.concat(ids, ","), "WITHDRAW,STATS,RELEASE,QOL_RENAME,CANCEL",
            tag .. "RENAME on: RENAME sits just above CANCEL")
          eq(bm:rom("QOL_RENAME"), "RENAME", tag .. "and reads RENAME")
          local boxes, prints = {}, {}
          local liveBox, livePrint = Chrome.box, Chrome.print
          Chrome.box = function(x, y, w, h, ...) boxes[#boxes + 1] = x .. "," .. y .. "," .. w .. "," .. h return liveBox(x, y, w, h, ...) end
          Chrome.print = function(t, x, y, ...) prints[tostring(t)] = x .. "," .. y return livePrint(t, x, y, ...) end
          local okDraw, errDraw = pcall(bm.drawPanel, bm)
          Chrome.box, Chrome.print = liveBox, livePrint
          check(okDraw, tag .. "the five-row submenu draws (" .. tostring(errDraw) .. ")")
          eq(boxes[#boxes], "9,2,11,12", tag .. "in a box two rows taller")
          eq(prints.WITHDRAW .. " " .. prints.CANCEL, "11,4 11,12", tag .. "with every row inside it")
          eq(Chrome.box, liveBox, tag .. "and Chrome is put back after the draw")
          bm.submenuIndex = 4
          bm:chooseSubmenu()
          eq(renamed, mon, tag .. "RENAME names the Pokemon in the box")
          eq(bm.phase, nil, tag .. "and the submenu closes for the naming screen")
          mon.isEgg = true
          bm.phase = "submenu"
          eq(#bm:submenuRows(), 4, tag .. "an EGG gets no RENAME row")
          mon.isEgg = nil
        end
        r.data.text = realText
      else
        local UI = require("src.ui.game3.box_storage_ui")
        local Window = require("src.ui.game3.window")
        local mon = { species = 16, level = 5, nickname = "PIDGEY" }
        local saved = { UI.mode, UI.subMode, UI._activeActions, UI._actionTarget, UI._actionSource,
          UI.actionCursor, UI._status, UI.drawerOpen }
        local function menu(sub)
          UI.mode, UI.subMode = "action_menu", sub
          UI._activeActions = { "WITHDRAW", "SUMMARY", "RELEASE", "CANCEL" }
          UI._actionTarget = { mon = mon, loc = "box", boxId = 1, slot = 1 }
          UI._actionSource, UI.drawerOpen = "box", false
          I.pcrename._augment()
          return table.concat(UI._activeActions, ",")
        end
        rename(false)
        eq(menu("withdraw"), "WITHDRAW,SUMMARY,RELEASE,CANCEL", tag .. "RENAME off: the PC's action menu is the cart's")
        rename(true)
        eq(menu("withdraw"), "WITHDRAW,SUMMARY,RELEASE,RENAME,CANCEL", tag .. "RENAME on: RENAME sits just above CANCEL")
        I.pcrename._augment()
        eq(table.concat(UI._activeActions, ","), "WITHDRAW,SUMMARY,RELEASE,RENAME,CANCEL", tag .. "and is added once")
        eq(menu("move_items"), "WITHDRAW,SUMMARY,RELEASE,CANCEL", tag .. "MOVE ITEMS gets no RENAME")
        mon.isEgg = true
        eq(menu("withdraw"), "WITHDRAW,SUMMARY,RELEASE,CANCEL", tag .. "an EGG gets no RENAME")
        mon.isEgg = nil
        -- the label: drawn by the engine's own loop (box_storage_ui's popup)
        menu("withdraw")
        local printed = {}
        local livePx = Window.printPx
        Window.printPx = function(t, x, y) printed[#printed + 1] = tostring(t) .. "@" .. x .. "," .. y end
        I.pcrename._drawWith(function()
          for i, act in ipairs(UI._activeActions) do
            Window.printPx(act, 114, (5 * 8 + 2) + (i - 1) * 16)
          end
        end)
        Window.printPx = livePx
        eq(table.concat(printed, " "), "WITHDRAW@114,42 SUMMARY@114,58 RELEASE@114,74 RENAME@114,90 CANCEL@114,106",
          tag .. "RENAME is printed in its own row")
        eq(UI._activeActions[4], "RENAME", tag .. "and the action list is left as it was")
        UI.actionCursor = 4
        UI.handleInput({ wasPressed = function(_, b) return b == "a" end, isDown = function() return false end })
        eq(renamed, mon, tag .. "A on RENAME names the Pokemon in the box")
        renameOpts.say("PIDGEY kept its name.")
        eq(UI.mode .. "|" .. tostring(UI._status), "message|PIDGEY kept its name.",
          tag .. "and the result shows in the PC's own message line")
        local Rs = require("src.ui.game3.rs.storage_policy")
        local okRs, label = pcall(Rs.menuText, "RENAME")
        eq(okRs and label, "RENAME", tag .. "Ruby/Sapphire's PC reads RENAME too")
        UI.mode, UI.subMode, UI._activeActions, UI._actionTarget, UI._actionSource,
          UI.actionCursor, UI._status, UI.drawerOpen = unpack(saved, 1, 8)
      end
      rename(false)
      A.rename = realRename
    end

    -- v1.5: the OPTIONS screen's QOL COMP row opens this mod's own toggles
    -- page (not the Mod Manager), and a change there is the same change the
    -- manager would make
    do
      local tag = "gen" .. gen .. " "
      -- earlier checks pin values straight onto the opts cache; let these
      -- rows read the loader again
      for _, k in ipairs({ "low_hp_beep", "scrolling", "rename" }) do rawset(I.core.opts, k, nil) end
      I.core.refresh()
      local presses = {}
      local input = { wasPressed = function(_, b) return presses[b] == true end,
        isDown = function() return false end }
      local states = {}
      local stack = {
        push = function(_, st) states[#states + 1] = st end,
        pop = function() return table.remove(states) end,
        top = function() return states[#states] end,
      }
      local wrote = 0
      local game = { mods = r.loader, save = { options = {} }, stack = stack, input = input,
        writeOptions = function() wrote = wrote + 1 end }
      local Stack3 = gen == 3 and require("src.ui.game3.stack") or nil
      local function topScreen()
        if gen == 3 then
          local t = Stack3.top()
          return t and t.mod
        end
        return states[#states]
      end
      local function press(btn)
        for k in pairs(presses) do presses[k] = nil end
        presses[btn] = true
        I.V.frame = (I.V.frame or 0) + 1
        local t = topScreen()
        if gen == 3 then t.handleInput(input) else t:update() end
        presses[btn] = nil
      end
      local before = gen == 3 and #Stack3._layers or #states
      I.optionsrow.open(game)
      local t = topScreen()
      check(t and t.qolCompScreen, tag .. "the QOL COMP row opens the mod's own page")
      eq(gen == 3 and #Stack3._layers or #states, before + 1, tag .. "and only that page, not the manager")
      -- find a row's index on the page
      local screen = I.optionsrow._lastScreen
      local function indexOf(key)
        for i, row in ipairs(screen.items) do if row.key == key then return i end end
      end
      eq(screen.items[1].label, "EDIT START MENU", tag .. "EDIT START MENU is the first row")
      eq(screen.items[#screen.items].label, "RESET DEFAULTS", tag .. "RESET DEFAULTS is the last")
      screen.index = indexOf("low_hp_beep")
      press("a")
      eq(r.loader.modOptions.qol_comp.low_hp_beep, "mute", tag .. "A steps a value in the loader")
      eq(game.save.options.modOptions.qol_comp.low_hp_beep, "mute", tag .. "and in the save's options")
      eq(I.core.opt("low_hp_beep"), "mute", tag .. "and the mod reads it at once")
      check(wrote > 0, tag .. "and the options file is written")
      eq(screen.items[screen.index].right, "OFF (MUTED)", tag .. "the row shows the new value")
      screen.index = indexOf("scrolling")
      press("right")
      eq(I.core.opt("scrolling"), "normal", tag .. "RIGHT steps forward")
      press("left"); press("left")
      eq(I.core.opt("scrolling"), "fast", tag .. "LEFT steps back and wraps")
      screen.index = indexOf("rename")
      press("a")
      eq(I.core.on("rename"), true, tag .. "A flips a toggle")
      screen.index = #screen.items
      press("a"); press("a")   -- RESET DEFAULTS, then RESET
      eq(I.core.opt("low_hp_beep"), "on", tag .. "RESET DEFAULTS restores every row")
      eq(I.core.on("rename"), false, tag .. "toggles included")
      press("b")
      eq(gen == 3 and #Stack3._layers or #states, before, tag .. "B closes the page")
    end

    -- DECAP keeps the engine's cached font path (Gen 1 and 2)
    if gen ~= 3 then
      local Font = require("src.render.Font")
      local D = I.decap
      local text = "PIDGEY used TACKLE! " .. gen
      setOpt(I, "decap", false)
      local stock = Font.encode
      local want = Font.width(D.convert(text))
      setOpt(I, "decap", true)
      check(Font.encode ~= stock, "gen" .. gen .. " DECAP converts through Font.encode")
      eq(Font.width(text), want, "gen" .. gen .. " DECAP Font.width measures the converted text")
      local converting = Font.encode
      local duringStock, codes = 0, 0
      local realCode = Font.drawCode
      Font.drawCode = function() codes = codes + 1; if Font.encode == stock then duringStock = duringStock + 1 end end
      Font.draw(text, 0, 0)
      Font.drawCode = realCode
      check(codes > 0 and duringStock == codes,
        "gen" .. gen .. " DECAP Font.draw runs the engine's cached (stock encode) path")
      eq(Font.encode, converting, "gen" .. gen .. " and the converting encode is back after the draw")
      local enc = Font.encode(text)
      local expect = stock(D.convert(text))
      eq(#enc, #expect, "gen" .. gen .. " DECAP Font.encode still converts")
      setOpt(I, "decap", false)
      eq(Font.encode, stock, "gen" .. gen .. " DECAP off puts the stock encode back")
    end

    -- EXP bar fraction (Gen 1): kept per mon, worked out again when the
    -- mon's exp or level moves
    if gen == 1 then
      local d = r.data
      local species = next(d.pokemon)
      local Growth = require("src.pokemon.Growth")
      local rate = d.pokemon[species].growthRate or "MEDIUM_FAST"
      local lo = Growth.expForLevel(rate, 10, d.growth_rates)
      local hi = Growth.expForLevel(rate, 11, d.growth_rates)
      local mon = { species = species, level = 10, exp = lo }
      local game = { data = d }
      eq(I.arm.expFraction(game, mon), 0, "gen1 EXP bar empty at the level's start")
      mon.exp = lo + math.floor((hi - lo) / 2)
      local half = I.arm.expFraction(game, mon)
      check(half > 0.4 and half < 0.6, "gen1 EXP bar follows a gain")
      mon.level, mon.exp = 11, hi
      eq(I.arm.expFraction(game, mon), 0, "gen1 EXP bar resets on a level up")
    end

    -- HIDDEN ITEM SHINE does nothing in the sparkle's off phase
    do
      local K = I.common
      local realTimer = love.timer
      love.timer = { getTime = function() return 0.1 end }
      eq(K.sparkleRadius(), 1, "gen" .. gen .. " sparkle small at the start of its blink")
      love.timer = { getTime = function() return 0.3 end }
      eq(K.sparkleRadius(), 2, "gen" .. gen .. " sparkle large mid-blink")
      love.timer = { getTime = function() return 0.9 end }
      eq(K.sparkleRadius(), nil, "gen" .. gen .. " sparkle hidden off-phase")
      love.timer = realTimer
    end

    -- CENTER CAMERA on the Game Boy camera
    if gen ~= 3 then
      local Camera = require("src.render.Camera")
      local cam = Camera.new()
      setOpt(I, "center_camera", false)
      cam:follow(100, 100, 160, 144)
      local vanilla = cam.x
      setOpt(I, "center_camera", true)
      cam:follow(100, 100, 160, 144)
      eq(cam.x, vanilla - 8, "gen" .. gen .. " CENTER CAMERA shifts 8px")
      setOpt(I, "center_camera", false)

      -- BIGGER BAG: one 150 stack, a 255-row pocket
      local Bag = require("src.inventory.Bag")
      local save = { inventory = {}, order = {} }
      local data = r.data
      data.constants = data.constants or {}
      data.constants.bagSize = 255
      local okAdd = Bag.add(save, "POTION", 150, data)
      check(okAdd ~= false, "gen" .. gen .. " bag takes 150 of one item")
      local rows = Bag.rows(save, data)
      eq(#rows, 1, "gen" .. gen .. " 150 potions is one stack")
    end
  end
  r.release()
end

-- ---------------------------------------------------------------- pure logic

local r, ex = boot(1)
local I = ex._internal
local D, K, SM = I.decap, I.common, I.startmenu

local DECAP = {
  { "Hello there! Welcome to the world of POKéMON!", "Hello there! Welcome to the world of Pokémon!" },
  { "RED got a POTION!", "Red got a Potion!" },
  { "Enemy PIDGEY used TACKLE!", "Enemy Pidgey used Tackle!" },
  { "BILL'S HOUSE is on ROUTE 25.", "Bill's House is on Route 25." },
  { "Welcome to the HALL OF FAME!", "Welcome to the Hall of Fame!" },
  { "WHAT?! You beat my\nPIDGEOTTO!", "What?! You beat my\nPidgeotto!" },
  { "Teach TM01 to\nCHARMANDER? HP and PP!", "Teach TM01 to\nCharmander? HP and PP!" },
  { "PROF. OAK is in\nPALLET TOWN.", "Prof. Oak is in\nPallet Town." },
  { "S.S.ANNE docked.", "S.S.Anne docked." },
  { "HO-OH appeared!", "Ho-Oh appeared!" },
  { "{PLAYER} got\nHM05!{PROMPT}", "{PLAYER} got\nHM05!{PROMPT}" },
  { "Got 3 TMS.", "Got 3 TMs." },
  { "Press A to go.", "Press A to go." },
  { "It's the\nOF course.", "It's the\nof course." },
  { "Thanks!\\pTHE END", "Thanks!\\pThe End" },
  { "<PLAYER> and <RIVAL>", "<PLAYER> and <RIVAL>" },
  -- menus and names: no common-English lowercasing inside a name
  { "FIGHT <PK><MN>\nITEM  RUN", "Fight <PK><MN>\nItem  Run" },
  { "RUN", "Run" },
  { "QUICK ATTACK", "Quick Attack" },
  { "MAY", "May" },
  { "PP UP", "PP Up" },
  { "OLD ROD", "Old Rod" },
  { "NEW BARK TOWN", "New Bark Town" },
  { "ONE ISLAND", "One Island" },
  { "ELITE FOUR WILL", "Elite Four Will" },
  { "SAND-ATTACK", "Sand-Attack" },
  { "X ATTACK", "X Attack" },
  { "B1F", "B1F" },
  { "TM/HM", "TM/HM" },
  { "NEW GAME\nCONTINUE\nOPTION", "New Game\nContinue\nOption" },
  { "BATTLE ANIMATION\n ON       OFF", "Battle Animation\n On       Off" },
  { "HOW TO CATCH POK\195\169MON", "How to Catch Pok\195\169mon" },
  { "Go to THE GAME CORNER", "Go to the Game Corner" },
  -- a lowercase 's after a name no longer keeps the name in capitals
  { "BILL's PC", "Bill's PC" },
  { "RED's house", "Red's house" },
  -- an ALL-CAPS sentence gets sentence case
  { "WHAT IS IT?", "What is it?" },
  { "MAY I HELP YOU?", "May I help you?" },
}
for _, c in ipairs(DECAP) do
  local once = D.convert(c[1])
  eq(once, c[2], "decap " .. c[1]:gsub("\n", "/"))
  eq(D.convert(once), once, "decap twice changes nothing: " .. c[1]:gsub("\n", "/"))
end
-- the Game Boy "#" (POKé) is spelled out, glyph count unchanged
do
  local was = D.pokeMacro
  D.pokeMacro = true
  eq(D.convert("#MON CENTER"), "Pok\195\169mon Center", "decap #MON")
  eq(D.convert("Got a #DEX!"), "Got a Pok\195\169dex!", "decap #DEX")
  D.pokeMacro = was
end

-- start menu layout: reorder, hide, MODS never hidden, unknown rows keep place
do
  local function items(...) local t = {} for i, k in ipairs({ ... }) do t[i] = { id = k, label = k } end return t end
  local st = { order = {}, hidden = {}, known = {} }
  -- reach the module's state through apply's own learning
  SM.reset()
  local base = items("POKEDEX", "POKEMON", "BAG", "MODS", "SAVE")
  local out = SM.apply(base)
  eq(#out, 5, "start menu untouched with no layout")
  SM._setLayout({ "SAVE", "BAG", "POKEMON", "POKEDEX", "MODS" }, { "POKEDEX", "MODS" })
  out = SM.apply(items("POKEDEX", "POKEMON", "BAG", "MODS", "SAVE"))
  local keys = {}
  for i, it in ipairs(out) do keys[i] = it.id end
  eq(table.concat(keys, ","), "SAVE,BAG,POKEMON,MODS", "start menu reordered, hidden row gone, MODS kept")
  out = SM.apply(items("POKEDEX", "OPTION", "POKEMON", "BAG", "MODS", "SAVE"))
  keys = {}
  for i, it in ipairs(out) do keys[i] = it.id end
  eq(table.concat(keys, ","), "SAVE,BAG,OPTION,POKEMON,MODS",
    "a row the layout never saw goes just above the row below it in the game's menu")
  out = SM.apply(items("POKEDEX", "POKEMON", "BAG", "MODS", "SAVE", "QUIT"))
  keys = {}
  for i, it in ipairs(out) do keys[i] = it.id end
  eq(keys[#keys], "QUIT", "a trailing QUIT stays last")
  SM.reset()
  eq(#SM.apply(base), 5, "RESET LAYOUT restores the game's menu")
end

-- the eight-row submenu cap: CANCEL first, then added field moves, RENAME stays
do
  local A = {
    fieldMoveList = function() return { "CUT", "FLY", "SURF", "STRENGTH", "FLASH", "DIG" } end,
    knows = function() return false end,
    canLearnLevel = function() return true end,
    canLearnMachine = function() return false end,
    holdsMachineFor = function() return true end,
    isEgg = function() return false end,
    rowIsCancel = function(row) return row.action == "cancel" end,
    rowIsFieldMove = function(row) return row.move ~= nil or row.action == "fly" end,
    makeFieldRow = function(_, id) return { label = id, move = id } end,
    label = function(s) return s end,
    rename = function() end, relearn = function() end,
  }
  I.core.opts.field_moves, I.core.opts.rename, I.core.opts.relearn_moves = true, true, false
  local list = { { label = "STATS", action = "stats" }, { label = "SWITCH", action = "switch" },
                 { label = "CANCEL", action = "cancel" } }
  local out = K.submenu(A, {}, list, { species = "X" }, {})
  eq(#out, 8, "submenu capped at eight rows")
  local hasCancel, hasRename = false, false
  for _, row in ipairs(out) do
    if row.action == "cancel" then hasCancel = true end
    if row.id == "QOL_RENAME" then hasRename = true end
  end
  check(not hasCancel, "CANCEL dropped first when full")
  check(hasRename, "RENAME always visible")
  local inBattle = K.submenu(A, {}, { { label = "STATS" } }, { species = "X" }, { battle = true })
  eq(#inBattle, 1, "nothing added in battle")

  -- FIELD MOVES: a move the Pokemon does not know needs its TM/HM in the
  -- bag, even when the species learns it by level-up (DEOXYS / TELEPORT).
  -- The bug this covers: level-up moves were offered with no bag check.
  local held = {}
  A.fieldMoveList = function() return { "CUT", "TELEPORT" } end
  A.knows = function(_, id) return id == "KNOWN" end
  A.canLearnLevel = function(_, _, id) return id == "TELEPORT" or id == "CUT" end
  A.canLearnMachine = function(_, _, id) return id == "CUT" end
  A.holdsMachineFor = function(_, id) return held[id] == true end
  eq(#K.learnableFieldMoves(A, {}, { species = "X" }), 0,
    "FIELD MOVES offers nothing without a TM/HM in the bag")
  eq(K.eligibleMon(A, {}, { { species = "X" } }, "TELEPORT"), nil,
    "a level-up field move with no machine held cannot be used")
  held.CUT = true
  local got = K.learnableFieldMoves(A, {}, { species = "X" })
  eq(#got, 1, "holding HM CUT offers CUT")
  eq(got[1], "CUT", "and only CUT")
  A.knows = function(_, id) return id == "TELEPORT" end
  check(K.eligibleMon(A, {}, { { species = "X" } }, "TELEPORT") ~= nil,
    "a Pokemon that knows the move can always use it")
  I.core.opts.field_moves, I.core.opts.rename = false, false
end

-- CHOOSE PKMN sits at the right moment: inside the battle intro, after the
-- opponent is on screen and immediately before the player's send-out.  The
-- bug this covers is asking before the battle has begun.
do
  local Timing = require("src.core.Timing")
  local battle = {
    kind = "trainer",
    player = { name = "PIKACHU", mon = { hp = 10 } },
    game = { save = { party = { { hp = 10 }, { hp = 10 } } } },
    queue = {
      { text = "wants to battle!" },
      { text = "sent out ONIX!" },
      { wait = Timing.BATTLE_START_SENDOUT },
      { text = "Go! PIKACHU!" },
    },
    sendOutText = function(_, name) return "Go! " .. name .. "!" end,
  }
  local at, goRow = I.arm.findSeam(battle)
  eq(at, 3, "gen1 the pick goes on the send-out wait, not before the battle")
  eq(goRow and goRow.text, "Go! PIKACHU!", "gen1 and it owns the Go! row")
  battle.queue[4].text = "something else"
  eq(I.arm.findSeam(battle), nil, "gen1 an intro it does not recognise is left alone")
  eq(I.common.chooseWanted("wild"), false, "CHOOSE PKMN off asks for nothing")
  local loader = r.loader
  loader.modOptions = loader.modOptions or {}
  loader.modOptions.qol_comp = loader.modOptions.qol_comp or {}
  loader.modOptions.qol_comp.choose_pkmn = "trainer"
  I.core.refresh()
  eq(I.common.chooseWanted("trainer"), true, "TRAINER asks for trainer battles")
  eq(I.common.chooseWanted("wild"), false, "TRAINER leaves wild battles alone")
  loader.modOptions.qol_comp.choose_pkmn = "both"
  I.core.refresh()
  eq(I.common.chooseWanted("wild"), true, "T+WILD asks for wild battles too")
  loader.modOptions.qol_comp.choose_pkmn = "off"
  I.core.refresh()
  local one = { { hp = 10 }, { hp = 0 } }
  eq(I.common.enoughLeads(one, I.arm.healthy), false, "one able battler, nothing to ask")
  eq(I.common.enoughLeads({ { hp = 10 }, { hp = 4 } }, I.arm.healthy), true, "two can be asked")
end

-- EDIT START MENU sees the rows other mods add.  A mod that wraps the hook
-- with a priority of its own (Gameshark uses 500) must still be inside this
-- mod's link, or the editor never lists it.
do
  local hooks = r.loader.hooks
  local remove = hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    items = nextFn(game, items) or items
    items[#items + 1] = { id = "gameshark", label = "GAMESHARK" }
    return items
  end, 500, "other_mod")
  local Runtime = require("src.mods.Runtime")
  SM.reset()
  local okCall, out = pcall(Runtime.call, "ui.start_menu.items",
    function(_, items) return items end, nil,
    { { id = "pokedex", label = "POKEDEX" }, { id = "save", label = "SAVE" } })
  check(okCall, "the start-menu chain runs")
  local sawShark = false
  for _, row in ipairs(type(out) == "table" and out or {}) do
    if row.id == "gameshark" then sawShark = true end
  end
  eq(sawShark, true, "another mod's row survives this mod's link")
  -- and the editor now knows about it
  SM._setLayout({ "GAMESHARK", "SAVE", "POKEDEX" }, {})
  local _, sorted = pcall(Runtime.call, "ui.start_menu.items",
    function(_, items) return items end, nil,
    { { id = "pokedex", label = "POKEDEX" }, { id = "save", label = "SAVE" } })
  local keys = {}
  for i, row in ipairs(type(sorted) == "table" and sorted or {}) do keys[i] = row.id end
  eq(table.concat(keys, ","), "gameshark,save,pokedex",
    "and the layout can move another mod's row")
  remove()
  SM.reset()
end

-- v1.5: one row, one editor entry.  The same row offered once with its id
-- and once by label alone (or a v1.4 store holding both) is listed once,
-- and rows the menu no longer shows are not listed at all.
do
  local function editorKeys()
    local out = {}
    for i, row in ipairs(SM._editorRows()) do out[i] = row.key end
    return table.concat(out, ",")
  end
  SM.reset()
  SM._setKnown({}, {})
  SM.apply({ { id = "pokedex", label = "POKEDEX" }, { id = "bag", label = "BAG" },
    { id = "save", label = "SAVE" } })
  SM._setLayout({ "SAVE", "BAG", "POKEDEX" }, {})
  -- the same menu, built without ids
  local out = SM.apply({ { label = "POKEDEX" }, { label = "BAG" }, { label = "SAVE" } })
  eq(#SM._editorRows(), 3, "a row seen by id and by label is listed once")
  eq(editorKeys(), "SAVE,BAG,POKEDEX", "and in the player's order")
  eq(out[1].label .. "," .. out[3].label, "SAVE,POKEDEX", "the label-only menu takes the layout too")
  -- a v1.4 store that learned every row twice
  SM._setKnown({ { "POKEDEX", "POKEDEX" }, { "BAG", "BAG" }, { "SAVE", "SAVE" },
    { "pokedex_id", "POKEDEX" }, { "bag_id", "BAG" }, { "save_id", "SAVE" } },
    { "POKEDEX", "BAG", "SAVE", "pokedex_id", "bag_id", "save_id" })
  eq(#SM._editorRows(), 3, "a doubled v1.4 store collapses to one row each")
  -- a row learned once (a removed mod's) is kept but not listed
  SM._setKnown({ { "POKEDEX", "POKEDEX" }, { "GAMESHARK", "GAMESHARK" }, { "SAVE", "SAVE" } }, {})
  SM.apply({ { id = "pokedex", label = "POKEDEX" }, { id = "save", label = "SAVE" } })
  eq(editorKeys(), "POKEDEX,SAVE", "a row the START menu no longer shows is not listed")
  SM.reset()
  SM._setKnown({}, {})
end

-- the row key is stable whatever DECAPITALIZATION does to the label it draws
do
  eq(SM.keyOf({ label = "POK\195\169DEX" }), SM.keyOf({ label = "Pok\195\169dex" }),
    "a decapitalised label is still the same row")
  eq(SM.keyOf({ label = "SAVE" }), SM.keyOf({ label = "Save" }), "and so is SAVE")
end

-- options are read live: a value written into the loader is seen without any
-- event, which is what keeps a toggle from looking broken after a change the
-- mod was not told about
do
  local loader = r.loader
  loader.modOptions = loader.modOptions or {}
  loader.modOptions.qol_comp = loader.modOptions.qol_comp or {}
  loader.modOptions.qol_comp.decap = true
  I.core.refresh()
  eq(I.core.on("decap"), true, "an option change is read live from the loader")
  loader.modOptions.qol_comp.decap = false
  I.core.refresh()
  eq(I.core.on("decap"), false, "and so is changing it back")
end

-- SCROLLING: NORMAL is 35% slower than FAST
do
  local S = I.scroll
  eq(S.SPEEDS.fast.hold, 14, "FAST holds 14 frames")
  eq(S.SPEEDS.fast.rate, 8, "FAST repeats every 8")
  eq(S.SPEEDS.normal.hold, 19, "NORMAL holds 19 frames (14 x 1.35)")
  eq(S.SPEEDS.normal.rate, 11, "NORMAL repeats every 11 (8 x 1.35)")
end

-- REMATCH (TRAINING)
eq(K.trainingAnchor(K.STORY_LEVELS[1], 3, { 20, 22 }), 29, "story level wins when the team is lower")
eq(K.trainingAnchor(K.STORY_LEVELS[1], 1, { 60, 62 }), 61, "team level wins when higher")
local scaled = K.scaleLevels({ 10, 12, 14 }, 40)
eq(table.concat(scaled, ","), "36,38,40", "scaled trainer keeps its spread")
eq(K.scaleLevels({ 5 }, 1)[1], 2, "scaled level never below 2")

r.release()

-- RENAME and RELEARN MOVES, end to end on each generation's real screens
-- (last: it stubs a few ROM-only engine lookups)
local e2e = assert(loadfile(MOD .. "/tests/e2e.lua"))
e2e({ check = check, eq = eq, MOD = MOD })

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
