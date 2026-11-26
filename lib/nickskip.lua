-- QoL Comp / nickskip: with RENAME on, no "Give a nickname?" question.
--
-- RENAME puts a rename on the party menu, so being asked for a name the
-- moment a Pokemon arrives is only a box to dismiss.  With the option on,
-- every way a Pokemon joins you skips the question and keeps the species
-- name, exactly as answering NO does; RENAME can name it any time after.
--
--   catches, every game        the engine's catch.nickname hook (false =
--                              keep the species name, no prompt)
--   gifts, Gen 1 / Gen 2       pokemon.before_give: an empty gift.nickname
--                              skips AskName and names nothing
--   Bug-Catching Contest, Gen 2  Specials.askNickname
--   eggs, Gen 2                the hatch's "Give a nickname to X?" yes/no
--   eggs, Gen 3                both hatch scenes (FRLG/Emerald, Ruby/Sapphire)
--   gifts, Gen 3               the cart's own script asks (msgbox YESNO); the
--                              question is recognised by its text and
--                              answered NO before it is shown
--
-- A trade, or a gift the game names itself (Shuckie, a traded Pokemon),
-- never asked in the first place, and is untouched.

local V = ...
local C = V.core

local M = {}

local function on() return C.on("rename") end

local function req(name)
  local ok, m = pcall(require, name)
  return ok and type(m) == "table" and m or nil
end

-- ------- every generation

local function installShared(mod)
  mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
    if on() then return false end
    return next(mon, ctx)
  end)
  mod.events:on("pokemon.before_give", function(gift)
    if not on() or type(gift) ~= "table" or gift.isEgg then return end
    -- a name the game or another mod already gave stays
    if gift.nickname == nil then gift.nickname = "" end
  end)
end

-- ------- Gen 2

local function installGen2()
  local Specials = req("src.script.gen2.Specials")
  if Specials then
    C.patch(Specials, "askNickname", function(orig, vm, mon)
      if on() then return end
      return orig(vm, mon)
    end)
  end

  -- World:hatchEggs sets lastText to _BreedAskNicknameText and calls
  -- askYesNo, which re-shows that line under a YES/NO box.  The question is
  -- recognised by the line itself, and answered NO before anything is drawn.
  local World = req("src.world.gen2.World")
  local CommonText = req("src.core.gen2.CommonText")
  if not (World and CommonText) then return end
  local function isHatchQuestion(world)
    local text = world and world.lastText
    if type(text) ~= "string" then return false end
    local ok, template = pcall(CommonText.get, world.text, "_BreedAskNicknameText")
    if not ok or type(template) ~= "string" then return false end
    local at = template:find("{STRBUF}", 1, true)
    if not at then return text == template end
    local head, tail = template:sub(1, at - 1), template:sub(at + #"{STRBUF}")
    return #text >= #head + #tail and text:sub(1, #head) == head
      and (tail == "" or text:sub(-#tail) == tail)
  end
  C.patch(World, "askYesNo", function(orig, self, onChoose)
    if on() and not self.stayedTextBox and isHatchQuestion(self) then
      self.choicebox = nil
      if onChoose then onChoose(false) end
      return
    end
    return orig(self, onChoose)
  end)
  M._isHatchQuestion = isHatchQuestion
end

-- ------- Gen 3

-- The nickname questions a gift script asks, by the cart's text label.
-- Whichever of these this game has is used; the rest are skipped.
local GIFT_QUESTIONS = {
  "Text_GiveNicknameToReceivedMon",   -- FireRed / LeafGreen
  "Text_GiveNicknameToThisMon",       -- FireRed / LeafGreen
  "gText_NicknameThisPokemon",        -- Emerald
  "gText_NicknameReceivedPokemon",    -- Ruby / Sapphire
  "LittlerootTown_ProfessorBirchsLab_Text_WhyNotGiveNicknameToMon",
}

local function norm(s)
  return (tostring(s or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function installGen3(mod)
  -- the two hatch scenes
  local EggHatch = req("src.ui.game3.egg_hatch")
  if EggHatch then
    -- FRLG / Emerald: the scene moves to "nickname_msg" as it shows the
    -- question; that same frame, before anything is drawn, it is closed and
    -- the scene goes on to its fade as a NO would
    local function afterUpdate()
      if on() and EggHatch._state == "nickname_msg" then
        local Message = req("src.ui.game3.message")
        if Message and Message.close then pcall(Message.close) end
        EggHatch._state = "fade_out"
        EggHatch._timer = 0
      end
    end
    C.patch(EggHatch, "update", function(orig, ...)
      local a, b = orig(...)
      afterUpdate()
      return a, b
    end)
    M._afterHatchUpdate = afterUpdate
  end
  local RsHatch = req("src.ui.game3.rs.egg_hatch")
  if RsHatch then
    -- Ruby / Sapphire: state 7 prints the question; 10 is NO's fade
    C.patch(RsHatch, "update", function(orig, ...)
      local scene = RsHatch._scene
      if on() and type(scene) == "table" and scene.state == 7 then scene.state = 10 end
      return orig(...)
    end)
  end

  -- gift scripts
  local TextIR = req("src.core.game3.scripting.text_ir")
  local Opcodes = req("src.core.game3.scripting.opcodes")
  local RomText = req("src.core.game3.rom_text")
  local Flags = req("src.core.game3.scripting.flags")
  local CtxM = req("src.core.game3.scripting.ctx")
  local VAR_RESULT = (CtxM and CtxM.VAR_RESULT) or 0x800D
  if not (TextIR and Opcodes and RomText) then return end

  local function view(vm)
    return { stringVars = vm.ctx and vm.ctx.stringVars or {} }
  end

  -- the message a `message` row would show, as plain text
  local function shownText(vm, row)
    if type(vm) ~= "table" or type(vm.getText) ~= "function" then return nil end
    local ptr = row and (row.ptr or row[1])
    if ptr == 0 or ptr == nil then ptr = vm.ctx and vm.ctx.data and vm.ctx.data[0] end
    if ptr == nil then return nil end
    local ok, ir = pcall(function()
      if type(ptr) == "string" then return vm:getText(ptr) end
      return vm:getText(Opcodes.key(ptr)) or vm:getText(ptr)
    end)
    if not ok or type(ir) ~= "table" then return nil end
    local okT, text = pcall(TextIR.toTextBox, ir, view(vm))
    return okT and norm(text) or nil
  end

  local function isGiftQuestion(vm, row)
    local text = shownText(vm, row)
    if not text or text == "" then return false end
    for _, key in ipairs(GIFT_QUESTIONS) do
      local okH, has = pcall(RomText.has, key)
      if okH and has then
        local okB, body = pcall(RomText.box, key, view(vm))
        if okB and norm(body) == text then return true end
      end
    end
    return false
  end

  -- one question at a time: set on the question's message, spent on its
  -- yes/no, and dropped when the script ends
  local skipping = false
  mod.events:on("script.ended", function() skipping = false end)
  mod.hooks:wrap("script.command", function(next, ctx, op, row)
    if not on() then return next(ctx, op, row) end
    local vm = ctx and (ctx.vm or ctx.runner)
    if op == "message" then
      if isGiftQuestion(vm, row) then
        skipping = true
        return false
      end
      skipping = false
      return next(ctx, op, row)
    end
    if skipping and (op == "waitmessage" or op == "waitbuttonpress") then
      return false
    end
    if skipping and op == "yesnobox" then
      skipping = false
      if Flags and vm and vm.store then
        pcall(Flags.setVar, vm.store, vm.ctx, VAR_RESULT, 0)
      end
      return false
    end
    return next(ctx, op, row)
  end)
  M._isGiftQuestion = isGiftQuestion
end

function M.install(mod)
  C.try("nickskip.shared", installShared, mod)
  if V.generation == 2 then C.try("nickskip.gen2", installGen2)
  elseif V.generation == 3 then C.try("nickskip.gen3", installGen3, mod) end
end

M.GIFT_QUESTIONS = GIFT_QUESTIONS

return M
