-- QoL Comp / common: the toggles whose engine seam is the same hook on every
-- generation.  What differs per game (move ids, learnsets, which row is
-- CANCEL, how a naming screen opens) comes from the active arm, `A`, which
-- the generation file fills in before install() runs.
--
--   LOW HP BEEP      battle.low_health_alarm (all three generations)
--   RUNNING SHOES    movement.speed (Gen 1 / Gen 2; Gen 3 is in lib/gen3.lua)
--   FIELD MOVES      ui.party.submenu + fieldmove.eligibility
--   RENAME           ui.party.submenu
--   RELEARN MOVES    ui.party.submenu
--   CHOOSE PKMN      policy only; each arm owns its intro seam
--   REMATCH          trainer.party (the TRAINING level scaling)

local V = ...
local C = V.core

local K = {}

-- The party submenu box holds eight rows on every cart.
K.MAX_SUBMENU_ROWS = 8

-- 16-frame walk / 1.7 = 9.4; the engine counts whole frames, and 9 is the
-- closest whole number (10 would be 1.6x).  See README "Running Shoes".
K.RUN_DIVISOR = 1.7

-- ------------------------------------------------------------ LOW HP BEEP
--
-- Two settings: ON (BEEPS) is the normal game, OFF (MUTED) never lets the
-- low-HP siren start.  (0.1.2's REDUCED is gone.)

-- anything but "mute" is the normal game (older options files said "off"
-- or "reduced")
function K.lowHpMode()
  return C.opt("low_hp_beep") == "mute" and "mute" or "on"
end

local function lowHp(next, ctx)
  if K.lowHpMode() == "mute" and type(ctx) == "table" then ctx.on = false end
  return next(ctx)
end

-- ------------------------------------------------------------ RUNNING SHOES

local function runFrames(next, frames, ctx)
  local out = next(frames, ctx)
  local player = ctx and ctx.player
  local running = false
  if C.opt("running_shoes") == "b" and type(ctx) == "table" and not ctx.onBike
      and not ctx.surfing and not ctx.slope and not ctx.downhill then
    local input = ctx.input
    local ok, held = false, false
    if type(input) == "table" and input.isDown then ok, held = pcall(input.isDown, input, "b") end
    if ok and held then
      local n = tonumber(out) or 16
      out = math.max(1, math.floor(n / K.RUN_DIVISOR))
      running = true
    end
  end
  if type(player) == "table" then player.qolCompRun = running or nil end
  return out
end

-- ------------------------------------------------------------ PARTY SUBMENU

local function isEgg(A, mon)
  return type(mon) ~= "table" or mon.isEgg or mon.egg or (A.isEgg and A.isEgg(mon))
end

-- FIELD MOVES' one rule, the same on every game: a Pokemon may use a field
-- move it does not know only when the player HOLDS the TM or HM that
-- teaches it, and the Pokemon could learn that move (by level or by that
-- machine).  A move no TM/HM teaches (TELEPORT, SOFTBOILED, MILK DRINK...)
-- is only ever usable by a Pokemon that knows it -- vanilla.
--
-- (v0.1.2 let a move the species learns by level-up through with no bag
-- check at all, so DEOXYS offered TELEPORT and every Bulbasaur line CUT
-- before any TM or HM was found.)
function K.canUseUnknown(A, game, mon, id)
  if not A.holdsMachineFor(game, id) then return false end
  -- the badge an HM needs, where the game checks it with the party
  -- (Gen 1); the other games gate the badge in the move's own check
  if A.badgeOk and not A.badgeOk(game, id) then return false end
  return A.canLearnMachine(game, mon, id) or A.canLearnLevel(game, mon, id)
end

-- ...and its row only appears where the move would actually work right
-- now: SURF facing water, FLASH in a dark cave, CUT / HEADBUTT / ROCK SMASH
-- facing the tree or rock, STRENGTH facing a boulder, FLY / TELEPORT
-- outdoors, DIG in a cave, and so on.  Each game's own "can I use that
-- here?" check decides (A.fieldMoveUsableHere in the arms), so a row never
-- shows for a move the game would refuse.
function K.usableHere(A, game, mon, id)
  if not A.fieldMoveUsableHere then return true end
  local ok, usable = pcall(A.fieldMoveUsableHere, game, mon, id)
  if not ok then
    C.warnOnce("field_moves.context." .. tostring(id), usable)
    return false
  end
  return usable == true
end

function K.learnableFieldMoves(A, game, mon)
  local out = {}
  if isEgg(A, mon) then return out end
  for _, id in ipairs(A.fieldMoveList(game)) do
    if not A.knows(mon, id) and K.canUseUnknown(A, game, mon, id)
        and K.usableHere(A, game, mon, id) then
      out[#out + 1] = id
    end
  end
  return out
end

-- a party member that may run `moveId` outside battle: one that knows it,
-- else (FIELD MOVES on) one that could learn it under the same rule
function K.eligibleMon(A, game, party, moveId)
  for _, mon in ipairs(party or {}) do
    if not isEgg(A, mon) and A.knows(mon, moveId) then return mon end
  end
  for _, mon in ipairs(party or {}) do
    if not isEgg(A, mon) and K.canUseUnknown(A, game, mon, moveId) then
      return mon
    end
  end
  return nil
end

local function fieldRowAfter(A, list)
  local at = 0
  for i, row in ipairs(list) do
    if A.rowIsFieldMove(row) then at = i end
  end
  if at == 0 and A.fieldRowsFirst then return 1 end
  if at == 0 then
    -- Gen 2 puts field moves before STATS; with none, they open the list
    return 1
  end
  return at + 1
end

-- The REAL party member a submenu row was chosen for.
--
-- The Pokemon handed to a row's callback is not always the party's own
-- table: when any mod on the engine's API 3 also hooks the party submenu,
-- the engine wraps every row below it and hands it a COPY, copying edits
-- back only for as long as the callback is running
-- (src/mods/UnifiedCallbacks.lua menuSelections).  RENAME and RELEARN
-- finish later -- after the naming or move screen closes -- so their edits
-- landed on that copy and the party never changed.  The party menu itself
-- is the authority: the open menu's party[index] is the Pokemon the player
-- picked.
function K.liveMon(A, game, given)
  local stack = type(game) == "table" and game.stack or nil
  local states = type(stack) == "table" and stack.states or nil
  if A.isPartyMenu and type(states) == "table" then
    for i = #states, 1, -1 do
      local s = states[i]
      if type(s) == "table" and A.isPartyMenu(s) then
        local party = s.party or (game.save and game.save.party)
        local idx = tonumber(s.index)
        local m = type(party) == "table" and idx and party[idx] or nil
        if type(m) == "table" then return m end
        break
      end
    end
  end
  local party = type(game) == "table" and game.save and game.save.party or nil
  if type(party) == "table" then
    for _, m in ipairs(party) do
      if m == given then return m end
    end
  end
  return given
end

-- the whole submenu rewrite, after the rest of the chain has run
function K.submenu(A, game, list, mon, ctx)
  if type(list) ~= "table" then return list end
  if (ctx and ctx.battle) or isEgg(A, mon) then return list end
  local phantom = {}
  if C.on("field_moves") then
    local ok, learnable = pcall(K.learnableFieldMoves, A, game, mon)
    if ok then
      local at = fieldRowAfter(A, list)
      for _, id in ipairs(learnable) do
        local row = A.makeFieldRow(game, id)
        if row then
          row.qolCompPhantom = true
          table.insert(list, at, row)
          phantom[row] = true
          at = at + 1
        end
      end
    else
      C.warnOnce("field_moves.submenu", learnable)
    end
  end
  local extras = {}
  -- the row's callback: whatever goes wrong, the player is told what
  local function runner(what, label, key)
    return function(m, g)
      g, m = g or game, m or mon
      local ok, err = pcall(function()
        return A[key](g, K.liveMon(A, g, m))
      end)
      if not ok then
        C.warn(what, err)
        K.refuse(A, g, K.failText(label, err))
      end
    end
  end
  if C.on("rename") and A.rename then
    extras[#extras + 1] = { id = "QOL_RENAME", label = A.label("RENAME"),
      onSelect = runner("rename", "RENAME", "rename") }
  end
  if C.on("relearn_moves") and A.relearn then
    extras[#extras + 1] = { id = "QOL_RELEARN", label = A.label("RELEARN"),
      onSelect = runner("relearn", "RELEARN", "relearn") }
  end
  -- the eight-row cap: CANCEL goes first (B still backs out), then the
  -- added field-move rows from the end, then any field-move row
  local function overflow() return #list + #extras > K.MAX_SUBMENU_ROWS end
  if overflow() then
    for i = #list, 1, -1 do
      if A.rowIsCancel(list[i]) then table.remove(list, i) break end
    end
  end
  while overflow() do
    local dropped = false
    for i = #list, 1, -1 do
      if phantom[list[i]] then table.remove(list, i); dropped = true; break end
    end
    if not dropped then
      for i = #list, 1, -1 do
        if A.rowIsFieldMove(list[i]) then table.remove(list, i); dropped = true; break end
      end
    end
    if not dropped then break end
  end
  -- extra rows sit just above CANCEL when it is still there
  local cancelAt
  for i = #list, 1, -1 do
    if A.rowIsCancel(list[i]) then cancelAt = i break end
  end
  for _, row in ipairs(extras) do
    if #list >= K.MAX_SUBMENU_ROWS then break end
    if cancelAt then
      table.insert(list, cancelAt, row)
      cancelAt = cancelAt + 1
    else
      list[#list + 1] = row
    end
  end
  for row in pairs(phantom) do row.qolCompPhantom = nil end
  return list
end

-- The message for a row that failed: what failed and why, in the text
-- box's 18 columns, at most four lines.  The engine's "file.lua:123: "
-- prefix is dropped; the reason itself is what the player can report.
function K.failText(label, err)
  local reason = tostring(err or "unknown error")
  reason = reason:gsub("^[^\n]-%.lua:%d+:%s*", "")
  reason = reason:gsub("%s+", " ")
  local lines = { tostring(label) .. " failed:" }
  local line = ""
  for word in reason:gmatch("%S+") do
    if #word > 18 then word = word:sub(1, 18) end
    if line == "" then
      line = word
    elseif #line + 1 + #word <= 18 then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
    if #lines >= 4 then break end
  end
  if line ~= "" and #lines < 4 then lines[#lines + 1] = line end
  -- two lines a page: "\n" inside a page, "\f" between pages
  local out = {}
  for i, l in ipairs(lines) do
    if i > 1 then out[#out + 1] = (i % 2 == 0) and "\n" or "\f" end
    out[#out + 1] = l
  end
  return table.concat(out)
end

-- A party-submenu action that cannot run says so on screen.  A row that
-- silently does nothing is indistinguishable from a broken mod, and this is
-- the one thing the player can report back.
function K.refuse(A, game, text)
  if A.say then C.try("refuse", A.say, game, text) end
end

-- ------------------------------------------------------------ CHOOSE PKMN
--
-- The pick belongs AFTER the opponent is on screen and immediately before
-- the player's own send-out, never before the battle starts: that is where
-- the cart would have asked, and it is the only point at which the lead can
-- be rebound without touching the party or counting as a switch.  Each arm
-- owns its generation's intro seam; this is just the shared policy.
-- (Seam idea from ZyranCZ's Trainers-Let-You-Choose-Lead-Pokemon.)

function K.chooseWanted(kind)
  local mode = C.opt("choose_pkmn")
  if mode == "trainer" then return kind == "trainer" end
  if mode == "both" then return kind == "trainer" or kind == "wild" end
  return false
end

-- at least two members could lead, or there is nothing to ask
function K.enoughLeads(party, legal)
  local n = 0
  for _, mon in ipairs(party or {}) do
    if legal(mon) then n = n + 1 end
  end
  return n >= 2
end

-- ------------------------------------------------------------ REMATCH (TRAINING)

-- The level a TRAINING rematch fights at: the story's level for the badges
-- the player holds, or the player's own team when that is higher, so a
-- rematch always lands in the range the player is currently playing at.
-- The curves are each region's next gym leader ace, then the League.
K.STORY_LEVELS = {
  [1] = { 14, 21, 24, 29, 43, 43, 47, 50, 62 },
  [2] = { 9, 16, 20, 25, 30, 35, 31, 40, 47, 48, 50, 52, 54, 56, 58, 60, 62 },
  rse = { 15, 18, 21, 27, 31, 33, 42, 46, 55 },
  frlg = { 14, 21, 24, 29, 43, 43, 47, 50, 63 },
}

function K.trainingAnchor(curve, badges, partyLevels)
  curve = curve or K.STORY_LEVELS[1]
  local story = curve[C.clamp((badges or 0) + 1, 1, #curve)]
  local sum, n = 0, 0
  for _, lv in ipairs(partyLevels or {}) do
    lv = tonumber(lv)
    if lv and lv > 0 then sum, n = sum + lv, n + 1 end
  end
  local team = n > 0 and C.round(sum / n) or story
  return math.max(story, team)
end

-- the trainer keeps its own spread: its strongest mon lands on the anchor
-- and the rest stay the same number of levels below it
function K.scaleLevels(levels, anchor)
  local top = 0
  for _, lv in ipairs(levels) do
    if (tonumber(lv) or 0) > top then top = tonumber(lv) end
  end
  local out = {}
  for i, lv in ipairs(levels) do
    out[i] = C.clamp(anchor - (top - (tonumber(lv) or top)), 2, 100)
  end
  return out
end

-- set by the arm while it starts a rematch; read by trainer.party
K.pendingRematch = nil

-- ------------------------------------------------------------ CENTER CAMERA

-- Gen 1 / Gen 2 only.  The Game Boy field is 10 tiles wide, an even count
-- with no middle column, so the cart parks the player in column 4: the
-- player's tile centre sits at x 72 on a 160-pixel screen whose centre is
-- 80.  src/render/Camera.lua carries that framing to every view size
-- (zoom, tilt, phone fill) as the same flat 8 pixels, so one constant after
-- the engine's own follow puts the player on the true centre everywhere.
-- Rows are 9, an odd count, so the vertical framing was already true.
-- Idea and analysis from Nezara's gen1recomp-centered-camera.
K.CENTER_SHIFT_X = 8

function K.installCenterCamera()
  local ok, Camera = pcall(require, "src.render.Camera")
  if not ok or type(Camera) ~= "table" then return end
  C.patch(Camera, "follow", function(orig, self, ...)
    local r1, r2 = orig(self, ...)
    if C.on("center_camera") and type(self.x) == "number" then
      self.x = self.x - K.CENTER_SHIFT_X
    end
    return r1, r2
  end)
end

-- ------------------------------------------------------------ install

-- ------- HIDDEN ITEM SHINE, shared by the three games
--
-- The sparkle shows for 0.45 s of every 1.2 s.  The ground-pass wrappers
-- ask K.sparkleRadius() first and do nothing at all the rest of the time
-- (no list, no flag lookups, no graphics state), which is most frames.
function K.sparkleRadius()
  local t = (love.timer and love.timer.getTime() or 0) % 1.2
  if t > 0.45 then return nil end
  return (t < 0.22) and 1 or 2
end

-- one sparkle around (x, y): r from K.sparkleRadius, s the pixel scale,
-- dark the outline colour {r, g, b}.  The caller puts its colour back.
function K.drawSparkleAt(x, y, r, s, dark)
  local g = love.graphics
  s = s or 1
  g.setColor(dark[1], dark[2], dark[3], 1)
  g.rectangle("fill", x + (-r - 1) * s, y, (2 * r + 3) * s, s)
  g.rectangle("fill", x, y + (-r - 1) * s, s, (2 * r + 3) * s)
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x - r * s, y, (2 * r + 1) * s, s)
  g.rectangle("fill", x, y - r * s, s, (2 * r + 1) * s)
end

-- DECAP on the Game Boy font (Gen 1 and 2).  Replacing Font.encode is what
-- reaches every string, but the engine only uses its glyph and width caches
-- while encode is the stock one, and the stock encode hands back a fresh
-- copy of the codes every call -- so with the toggle on, every label on
-- screen was re-encoded and re-measured from scratch each frame.  Font.draw
-- and Font.width (the two calls made every frame) are wrapped too: they
-- convert the text once (D.cached) and run the engine's own cached path
-- with the stock encode put back for the length of the call.  Everything
-- else that encodes (wrapping, the typewriter) still goes through the
-- converting encode.  All three are on only while DECAP is.
function K.installDecapFont(Font, D)
  if type(Font) ~= "table" then return end
  local function convertingEncode(orig, text, ...)
    if type(text) == "string" then text = D.cached(text) end
    return orig(text, ...)
  end
  C.togglePatch(Font, "encode", "decap", convertingEncode)
  local entry = C._toggled[#C._toggled]
  local function fast(orig, text, ...)
    if type(text) ~= "string" then return orig(text, ...) end
    text = D.cached(text)
    local live = Font.encode
    -- only when ours is the encode on top: a mod wrapping it after us
    -- keeps its say
    if not (entry and live == entry.installed) then return orig(text, ...) end
    Font.encode = C.original(Font, "encode")
    local ok, a, b = pcall(orig, text, ...)
    Font.encode = live
    if not ok then error(a, 0) end
    return a, b
  end
  if Font.draw then C.togglePatch(Font, "draw", "decap", fast) end
  if Font.width then C.togglePatch(Font, "width", "decap", fast) end
end

function K.install(mod, A)
  mod.hooks:wrap("battle.low_health_alarm", lowHp)
  if V.generation ~= 3 then
    mod.hooks:wrap("movement.speed", runFrames)
    K.installCenterCamera()
  end

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local list = next(game, items, mon, ctx)
    if type(list) ~= "table" then return list end
    local ok, out = pcall(K.submenu, A, game, list, mon, ctx)
    if ok and type(out) == "table" then return out end
    if not ok then C.warnOnce("ui.party.submenu", out) end
    return list
  end)

  mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
    local mon = next(moveId, ctx)
    if mon or not C.on("field_moves") or type(ctx) ~= "table" then return mon end
    local game = ctx.game or V.game
    local ok, found = pcall(K.eligibleMon, A, game, ctx.party, A.normalizeMove(moveId))
    if ok then return found end
    C.warnOnce("fieldmove.eligibility", found)
    return mon
  end)

  -- REMATCH (TRAINING): only the battle a rematch started is touched
  mod.hooks:wrap("trainer.party", function(next, class, index, party)
    local out = next(class, index, party)
    local pending = K.pendingRematch
    if not (pending and pending.training) or type(out) ~= "table" then return out end
    K.pendingRematch = nil
    local ok, scaled = pcall(A.scaleTrainerParty, out, pending)
    if not ok then
      C.warnOnce("rematch.scale", scaled)
      return out
    end
    return scaled or out
  end)
end

return K
