-- QoL Comp / expshare: EXP SHARE -- OFF / ON (GEN2) / ON (GEN6).
--
-- Every game hands its "who gets EXP for this KO" step to the
-- battle.exp_award hook with the same ctx on all three generations:
-- ctx.battle, ctx.participants (the count), ctx.alive (the participants
-- still standing) and ctx.applyShare(mon, split, announce), which pays one
-- Pokemon through the game's own routine -- EXP, stat exp / EVs, the
-- "gained" line, level-ups, new moves, all as the game does them.  So one
-- module covers all eleven games; only the few things the generations
-- disagree on (the party list, eggs, Gen 3's EVs and level 100) are
-- looked up per generation below.
--
-- ON (GEN2)  The game's own award runs first, untouched.  Then, for each
--            Pokemon that fought and is still standing, the NEXT Pokemon
--            after it in the party -- the first one down the list (wrapping
--            to the top) that is not fainted, not an egg and did not fight
--            itself -- gets half of that EXP and half of those EVs / stat
--            exp.  Each Pokemon is paid this way at most once per KO.
--
-- ON (GEN6)  Replaces the game's award.  Every party Pokemon that is not
--            fainted and not an egg gets EXP: the ones that fought get the
--            full amount each (not split between them), the rest get 50%.
--            Every one of them gets the full EVs / stat exp -- a level-100
--            Pokemon included.  A wild Pokemon that is caught pays out the
--            same way a KO does.  A held EXP. SHARE (Gen 2 / Gen 3) no longer
--            halves anything.  The Pokemon that fought print their "gained"
--            line; the rest are paid quietly (their level-ups still show).
--
-- https://bulbapedia.bulbagarden.net/wiki/Exp._Share

local V = ...
local C = V.core

local M = {}
local unpack = table.unpack or unpack

M.MODES = { off = true, gen2 = true, gen6 = true }

local function mode()
  local m = C.opt("exp_share")
  if M.MODES[m] then return m end
  return "off"
end

local function req(name)
  local ok, m = pcall(require, name)
  return ok and type(m) == "table" and m or nil
end

-- ------- per generation

-- the player's party, in party order
local function partyOf(battle)
  if type(battle) ~= "table" then return {} end
  if V.generation == 1 then
    if type(battle.playerPartyView) == "function" then
      local ok, list = pcall(battle.playerPartyView, battle)
      if ok and type(list) == "table" then return list end
    end
    local save = battle.game and battle.game.save
    return (save and save.party) or {}
  elseif V.generation == 2 then
    return battle.party or {}
  end
  return battle.playerParty or {}
end

local function isEgg(mon)
  if type(mon) ~= "table" then return true end
  if mon.isEgg == true or mon.egg == true then return true end
  if V.generation == 3 then
    local P = req("src.core.game3.pokemon")
    if P and P.isEgg then
      local ok, egg = pcall(P.isEgg, mon)
      if ok then return egg end
    end
  end
  return false
end

local function eligible(mon)
  return type(mon) == "table" and not isEgg(mon) and (tonumber(mon.hp) or 0) > 0
    and (tonumber(mon.species or mon.speciesId) or 1) ~= 0
end

-- ------- Gen 3's EVs
--
-- Gen 3 pays EVs in whole points and never divides them, and its award
-- skips a level-100 Pokemon outright (EVs included).  So on Gen 3 this
-- module halves the EVs itself for ON (GEN2), and pays a level-100
-- Pokemon's EVs itself for ON (GEN6).

local function g3()
  if V.generation ~= 3 then return nil end
  local P = req("src.core.game3.pokemon")
  local X = req("src.core.game3.battle.experience")
  if not (P and P.evsOf and P.gainEVs) then return nil end
  return P, X
end

local function snapshotEVs(mon)
  local P = g3()
  if not P then return nil end
  local evs = P.evsOf(mon)
  local copy = {}
  for k, v in pairs(evs) do copy[k] = tonumber(v) or 0 end
  return copy
end

-- what this award added, halved (rounded down)
local function halveSince(mon, before)
  local P = g3()
  if not (P and before) then return end
  local evs = P.evsOf(mon)
  for k, v in pairs(evs) do
    local was = before[k] or 0
    local now = tonumber(v) or 0
    if now > was then evs[k] = was + math.floor((now - was) / 2) end
  end
end

local function maxLevel(mon)
  local _, X = g3()
  local cap = (X and X.MAX_LEVEL) or 100
  return (tonumber(mon.level) or 1) >= cap
end

local function foeSpecies(ctx)
  local loser = ctx.loser
  if type(loser) ~= "table" then return nil end
  return loser.species or (type(loser.mon) == "table" and (loser.mon.species or loser.mon.speciesId))
end

-- Gen 3 only: EVs for a level-100 Pokemon the game's award skips
local function evsOnly(ctx, mon, half)
  local P = g3()
  local species = foeSpecies(ctx)
  if not (P and species) then return end
  local before = half and snapshotEVs(mon) or nil
  pcall(P.gainEVs, mon, species)
  if half then halveSince(mon, before) end
end

-- ------- the award

-- Set while this module pays a KO, for the exp.gain link below:
-- bench[mon] -> pay 50% (ON (GEN6)), undoHalved -> undo a held EXP. SHARE.
local active = nil

local function payGen2(ctx, party)
  local fought = {}
  for _, mon in ipairs(ctx.alive or {}) do fought[mon] = true end
  local split = math.max(1, tonumber(ctx.participants) or 1) * 2
  local paid = {}
  local n = #party
  for _, mon in ipairs(ctx.alive or {}) do
    local at = nil
    for i = 1, n do if party[i] == mon then at = i break end end
    if at then
      for step = 1, n - 1 do
        local other = party[(at - 1 + step) % n + 1]
        if eligible(other) and not fought[other] then
          if not paid[other] then
            paid[other] = true
            if V.generation == 3 and maxLevel(other) then
              evsOnly(ctx, other, true)
            else
              local before = snapshotEVs(other)
              ctx.applyShare(other, split, true)
              halveSince(other, before)
            end
          end
          break
        end
      end
    end
  end
end

-- Gen 2: a held EXP. SHARE halves the stat exp inside the game's award,
-- where no hook reaches.  ON (GEN6) puts the halved stat exp back and pays
-- the full amount through the game's own Mon.gainStatExp (Pokerus included).
local function fullStatExp(ctx, mon, pay)
  if not (V.generation == 2 and ctx.halved == true) then return pay() end
  local Mon = req("src.battle.gen2.Mon")
  local Pokerus = req("src.core.gen2.Pokerus")
  local battle = ctx.battle
  local def = Mon and battle and type(battle.speciesDef) == "function"
    and select(2, pcall(battle.speciesDef, battle, ctx.loser)) or nil
  if not (Mon and Mon.gainStatExp and type(def) == "table") then return pay() end
  mon.statExp = mon.statExp or (Mon.newStatExp and Mon.newStatExp()) or {}
  local before = {}
  for k, v in pairs(mon.statExp) do before[k] = v end
  pay()
  for k in pairs(mon.statExp) do mon.statExp[k] = before[k] or 0 end
  local doubled = Pokerus and Pokerus.doublesStatExp and Pokerus.doublesStatExp(mon) or false
  Mon.gainStatExp(mon, def, 1, doubled, false)
end

local function payGen6(ctx, party)
  local fought = {}
  for _, mon in ipairs(ctx.alive or {}) do fought[mon] = true end
  active = { bench = {}, undoHalved = ctx.halved == true }
  local ok, err = pcall(function()
    for _, mon in ipairs(party) do
      if eligible(mon) then
        if V.generation == 3 and maxLevel(mon) then
          evsOnly(ctx, mon, false)
        elseif fought[mon] then
          fullStatExp(ctx, mon, function() ctx.applyShare(mon, 1, true) end)
        else
          active.bench[mon] = true
          fullStatExp(ctx, mon, function() ctx.applyShare(mon, 1, nil) end)
          active.bench[mon] = nil
        end
      end
    end
  end)
  active = nil
  if not ok then error(err, 0) end
end

local function award(next, ctx)
  local m = mode()
  if m == "off" or type(ctx) ~= "table" or type(ctx.applyShare) ~= "function" then
    return next(ctx)
  end
  local party = partyOf(ctx.battle)
  if m == "gen2" then
    local r = { next(ctx) }
    C.try("expshare.gen2", payGen2, ctx, party)
    return unpack(r)
  end
  -- gen6: the whole award is ours.  A failure is logged, never retried
  -- through the game's own award -- that could pay a Pokemon twice.
  local ok, err = pcall(payGen6, ctx, party)
  if not ok then C.warnOnce("expshare.gen6", err) end
end

-- the EXP one Pokemon is paid, while ON (GEN6) is paying a KO
local function gain(next, c)
  if not active or type(c) ~= "table" then return next(c) end
  -- a held EXP. SHARE halves the whole pool on Gen 2 / Gen 3; ON (GEN6)
  -- has no use for it
  if V.generation == 2 and c.halved then c.halved = false end
  local amount = tonumber(next(c)) or 0
  if V.generation == 3 and active.undoHalved then amount = amount * 2 end
  if active.bench[c.mon] then amount = math.max(1, math.floor(amount / 2)) end
  return amount
end

function M.install(mod)
  mod.hooks:wrap("battle.exp_award", award)
  mod.hooks:wrap("exp.gain", gain)
  -- ON (GEN6): a catch pays out like a KO (vanilla never does, on any of
  -- the eleven games)
  mod.hooks:wrap("battle.catch_exp", function(next, ctx)
    if mode() == "gen6" then return true end
    return next(ctx)
  end)
end

M.mode = mode
M._partyOf, M._eligible = partyOf, eligible

return M
