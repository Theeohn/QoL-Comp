-- QoL Comp / decap: the DECAPITALIZATION toggle's text engine.
--
-- Pure Lua, no engine access, so it is the same function on every generation
-- and the test suite drives it directly.  The arms only decide WHERE text
-- passes through it (Gen 1/2 TextBox + the font, Gen 3 the font); this file
-- decides WHAT the text becomes.
--
-- What counts as a word to convert: one whose letters are ALL capitals.  A
-- word the cart already wrote in mixed case is left exactly as it is, which
-- is what makes running the pass twice harmless.  A possessive or contraction
-- tail the cart writes in lowercase does not stop the word from converting:
-- Gen 1's "BILL's PC" and "RED's" become "Bill's PC" and "Red's".
--
-- Kept as they are: abbreviations (TM, HM, PKMN, HP, PP, PC, OT, ...), single
-- letters ("press A", "S.S."), and any word with a digit in it (TM01, B1F).
--
-- Everything else is decided per RUN -- a stretch of consecutive ALL-CAPS
-- words with no mixed-case word between them:
--
--   * a NAME run is the normal case in these games: a Pokemon, a move, an
--     item, a place, a person, a menu label.  Every word is Title-case --
--     "QUICK ATTACK" -> "Quick Attack", "OLD ROD" -> "Old Rod", "MAY" ->
--     "May", "ITEM  RUN" -> "Item  Run" -- except the small joining words
--     (of, the, and, to, ...) inside the run: "HALL OF FAME" -> "Hall of
--     Fame".  A joining word that starts a run, a line, a sentence or a menu
--     column keeps its capital ("THE END" -> "The End").
--   * a PROSE run is a whole sentence typed in capitals, recognised by
--     carrying at least two pronouns / helper verbs ("WHAT IS IT?", "DO NOT
--     ENTER").  It gets sentence case: common English words lowercase, the
--     rest Title-case, and the sentence's first letter capitalised.
--
-- Sentences are found on the WHOLE string, so a sentence that continues onto
-- the next row never gets a stray capital at the start of that row.
--
-- No word changes its glyph count, so a converted message wraps, scrolls and
-- types out exactly like the original.  The one rewrite that changes bytes,
-- the Game Boy "#" (which the font draws as the four glyphs POKé), keeps the
-- glyph count too: "#MON" (4 + 3) -> "Pokémon" (7).
--
-- Control sequences are opaque: {TOKENS}, <MACROS>, backslash escapes (\n,
-- \p, \l), Gen 3's 0xFC codes, and the box's own \n \v \f \r bytes pass
-- through untouched.

local D = {}

-- the Game Boy fonts draw "#" as POKé (src/render/Font.lua MACRO_TEXT); the
-- Gen 1 / Gen 2 arms turn this on
D.pokeMacro = false

local function wordSet(text, pattern)
  local t = {}
  for w in text:gmatch(pattern or "[%u']+") do t[w] = true end
  return t
end

-- kept in capitals, matched on the letters of the word only
local ABBREV = wordSet([[TM HM PKMN PK MN HP PP PC ID OK KO TV LV ATK DEF SPD SPC
  SPCL SP HQ UFO CD DJ SS GS GB GBA GBC BP NPC VS IQ ROM RAM CPU EV IV OT
  II III VI VII VIII IX XI XII USA UK EXP PSN PAR SLP BRN FRZ FNT]], "%u+")

-- joining words: lowercase inside a NAME run ("Hall of Fame") unless they
-- open a sentence, a row or a menu column
local MINOR = wordSet([[A AN THE AND OR NOR BUT OF IN ON AT TO BY FOR FROM WITH
  AS VS INTO ONTO UPON]])

-- what makes an ALL-CAPS run a sentence rather than a name
local PROSE = wordSet([[I I'M I'LL I'VE I'D YOU YOU'RE YOUR YOURS YOU'LL YOU'VE
  WE WE'RE OUR US HE HE'S SHE SHE'S IT IT'S ITS THEY THEY'RE THEIR THEM ME MY
  HIM HER IS ISN'T ARE AREN'T WAS WASN'T WERE AM BE BEEN DO DOES DID DON'T
  DOESN'T DIDN'T CAN'T CANNOT WON'T WOULDN'T COULDN'T SHOULDN'T HAVE HAS HAD
  WHAT WHAT'S WHERE WHY HOW WHO THIS THAT THAT'S THESE THOSE THERE THERE'S
  HERE NOT WOULD COULD SHOULD WILL SHALL JUST WANT KNOW THINK LET'S OH NO
  YES PLEASE THANK THANKS SORRY]])

-- lowercased inside a PROSE run: articles, pronouns, prepositions,
-- auxiliaries and the interjections the carts shout.  Anything not here is
-- treated as a name even inside a sentence.
local STOP = wordSet([[A AN THE AND OR NOR BUT SO YET IF THEN THAN AS AT BY FOR
  FROM IN INTO OF OFF ON ONTO OUT OVER TO UP UPON WITH WITHIN WITHOUT ABOUT
  ABOVE AFTER AGAIN AGAINST ALL ALSO ALWAYS AM ANY ARE AREN'T AROUND AWAY BACK
  BE BEEN BEFORE BEING BELOW BETWEEN BOTH CAN CAN'T CANNOT COULD COULDN'T DID
  DIDN'T DO DOES DOESN'T DOING DON'T DOWN DURING EACH EVEN EVER EVERY FEW GET
  GETS GOT GO GOES GOING GONE HAD HAS HASN'T HAVE HAVEN'T HAVING HE HE'S HER
  HERE HERS HERSELF HIM HIMSELF HIS HOW I'D I'LL I'M I'VE IS ISN'T IT IT'S ITS
  ITSELF JUST LIKE MAY ME MIGHT MINE MORE MOST MUCH MUST MY MYSELF NEVER NO NOT
  NOW ONCE ONLY OTHER OUR OURS OURSELVES OWN SAME SHE SHE'S SHOULD SOME SUCH
  THAT THAT'S THEIR THEIRS THEM THEMSELVES THERE THERE'S THESE THEY THEY'RE
  THIS THOSE THROUGH TOO UNDER UNTIL VERY WAS WASN'T WE WE'RE WERE WEREN'T WHAT
  WHAT'S WHEN WHERE WHICH WHILE WHO WHOM WHY WILL WON'T WOULD WOULDN'T YES YOU
  YOU'RE YOU'VE YOU'LL YOUR YOURS YOURSELF OH HEY HI HELLO WOW WHOA HUH HMM UH
  UM AH AHA HA HAHA OOPS YEAH YEP NOPE OKAY PLEASE THANKS THANK SORRY STOP WAIT
  HELP LOOK LISTEN COME RUN HURRY QUICK QUICKLY REALLY WELL GOOD GREAT BAD
  WRONG RIGHT LEFT SAVE WHEW GEE GOSH DARN DANG ARGH UGH HMPH EH BAH PSST SHH
  ZZZ SOMETHING NOTHING ANYTHING EVERYTHING SOMEONE ANYONE EVERYONE NOBODY ONE
  TWO THREE MANY LITTLE BIG NEW OLD STILL ALREADY ENOUGH LET LET'S KNOW THINK
  WANT SEE SAY SAID TELL TOLD MAKE MADE TAKE TOOK GIVE GAVE USE USED]])

-- a period after one of these is not the end of a sentence
local DOTTED = wordSet("PROF MR MRS MS DR MT LT CO ST JR SR VS NO DEPT INC VOL", "%u+")

-- the few names whose capitals are not just their first letter
local SPECIAL = {
  ["POKéNAV"] = "PokéNav",
  ["POKéGEAR"] = "PokéGear",
  ["MCDONALD"] = "McDonald",
  ["TM/HM"] = "TM/HM",
}

D.ABBREV, D.STOP, D.SPECIAL, D.MINOR, D.PROSE = ABBREV, STOP, SPECIAL, MINOR, PROSE

local function isUpperByte(b) return b >= 65 and b <= 90 end
local function isLowerByte(b) return b >= 97 and b <= 122 end
local function isDigitByte(b) return b >= 48 and b <= 57 end

local function hasLower(word)
  for i = 1, #word do
    if isLowerByte(word:byte(i)) then return true end
  end
  return false
end

local function hasUpper(word)
  for i = 1, #word do
    if isUpperByte(word:byte(i)) then return true end
  end
  return false
end

local function hasDigit(word)
  for i = 1, #word do
    if isDigitByte(word:byte(i)) then return true end
  end
  return false
end

-- the word's letters, upper-cased, é folded to E, apostrophes kept:
-- the key every table above is matched on
local function keyOf(word)
  local k = word:gsub("\195\169", "E"):gsub("\195\137", "E")
  k = k:gsub("[^%a']", "")
  return k:upper()
end

-- "BILL'S" -> "Bill's".  é is two bytes the pattern never matches, so it
-- simply rides along in place.
local function titleCase(word)
  local first = true
  return (word:gsub("%a", function(c)
    if first then
      first = false
      return c:upper()
    end
    return c:lower()
  end))
end

local function capitalizeFirst(word)
  return (word:gsub("^([^%a]*)(%a)", function(pre, c) return pre .. c:upper() end, 1))
end

-- A lowercase tail the cart writes after a name: 's 'd 'll 're 've 'm 't.
-- Returns the ALL-CAPS stem and the tail, or the word and "".
local function splitTail(word)
  local stem, tail = word:match("^(.-)('[a-z]+)$")
  if stem and stem ~= "" and not hasLower(stem) then return stem, tail end
  return word, ""
end

-- how a word takes part in a run:
--   "mixed"    has lowercase letters of its own; never touched, ends a run
--   "keep"     an abbreviation, a single letter or a word with a digit;
--              never touched, but part of the run around it
--   "caps"     an ALL-CAPS word this pass converts
local function classify(word)
  local stem = splitTail(word)
  if hasLower(stem) then return "mixed" end
  if not hasUpper(stem) then return "keep" end
  if hasDigit(stem) then return "keep" end
  local key = keyOf(stem)
  local letters = key:gsub("'", "")
  if #letters <= 1 then return "keep" end
  if ABBREV[letters] then return "keep" end
  return "caps"
end

D.classify = classify

-- one hyphen-free piece, as a name
local function namePiece(piece)
  local key = keyOf(piece)
  local letters = key:gsub("'", "")
  if #letters <= 1 or ABBREV[letters] or hasDigit(piece) then return piece end
  return titleCase(piece)
end

-- a plural abbreviation: TMS -> TMs, HMS -> HMs
local function pluralAbbrev(stem)
  local letters = keyOf(stem):gsub("'", "")
  local singular = letters:match("^(.+)S$")
  if singular and #singular >= 2 and ABBREV[singular] then
    return (stem:gsub("S$", "s"))
  end
  return nil
end

-- convert one ALL-CAPS word.  `lower` says the rules want it lowercase
-- (a joining word, or a common word in a sentence); the caller decides
-- whether a sentence start gives it its capital back.  Returns the new
-- spelling and whether it came out lowercase.
local function convertCaps(word, lower)
  local stem, tail = splitTail(word)
  local special = SPECIAL[stem]
  if special then return special .. tail, false end
  local plural = pluralAbbrev(stem)
  if plural then return plural .. tail, false end
  if lower then return stem:lower() .. tail, true end
  if stem:find("-", 1, true) then
    -- HO-OH, SAND-ATTACK, DOUBLE-EDGE: every piece is a name
    local out = {}
    for piece in (stem .. "-"):gmatch("([^%-]*)%-") do out[#out + 1] = namePiece(piece) end
    return table.concat(out, "-") .. tail, false
  end
  return titleCase(stem) .. tail, false
end

-- kept for the suite and other mods: one word on its own, as a name
function D.convertWord(word)
  local class = classify(word)
  if class ~= "caps" then return word, false end
  return convertCaps(word, false)
end

-- Gen 3's text codes are a 0xFC byte and a command whose argument count the
-- command decides (src/ui/game3/frlg_font.lua scanTokens).  The whole run is
-- opaque: a byte of it re-cased is a different code.
local CTRL_LEN = {
  [0x01] = 3, [0x02] = 3, [0x03] = 3, [0x04] = 5, [0x05] = 3, [0x06] = 3,
  [0x08] = 3, [0x0B] = 4, [0x0C] = 3, [0x0D] = 3, [0x0E] = 3, [0x10] = 4,
  [0x11] = 3, [0x12] = 3, [0x13] = 3, [0x14] = 3,
}

-- the opaque spans: {TOKEN}, <MACRO>, a backslash escape, a 0xFC text code
local function opaqueAt(s, i)
  local b = s:byte(i)
  if b == 0xFC then
    local cmd = s:byte(i + 1)
    local len = (cmd and CTRL_LEN[cmd]) or 2
    return math.min(#s, i + len - 1)
  end
  local c = s:sub(i, i)
  if c == "{" then
    local j = s:find("}", i + 1, true)
    if j then return j end
  elseif c == "<" then
    local j = s:find(">", i + 1, true)
    if j and j - i <= 12 then return j end
  elseif c == "\\" and i < #s then
    return i + 1
  end
  return nil
end

-- is byte position i the start of a word character?
local function wordByte(s, i)
  local b = s:byte(i)
  if not b then return false end
  if isUpperByte(b) or isLowerByte(b) or isDigitByte(b) then return true end
  -- é / É (UTF-8 C3 A9 / C3 89)
  if b == 195 then
    local n = s:byte(i + 1)
    return n == 169 or n == 137
  end
  return false
end

local function wordEnd(s, i)
  local n = #s
  local j = i
  while j <= n do
    local b = s:byte(j)
    if b == 195 and (s:byte(j + 1) == 169 or s:byte(j + 1) == 137) then
      j = j + 2
    elseif wordByte(s, j) then
      j = j + 1
    elseif (b == 39 or b == 45) and wordByte(s, j + 1) then
      -- an apostrophe or hyphen INSIDE a word: BILL'S, HO-OH, BILL's
      j = j + 1
    else
      break
    end
  end
  return j - 1
end

-- Break the text into tokens: words, opaque spans and everything else.
local function tokenize(text)
  local tokens = {}
  local i, n = 1, #text
  while i <= n do
    local stop = opaqueAt(text, i)
    if stop then
      tokens[#tokens + 1] = { kind = "opaque", s = text:sub(i, stop) }
      i = stop + 1
    elseif D.pokeMacro and text:sub(i, i) == "#" and wordByte(text, i + 1)
        and isUpperByte(text:byte(i + 1)) then
      -- "#MON" is the Game Boy font's POKéMON: one word, POKé + MON
      local j = wordEnd(text, i + 1)
      tokens[#tokens + 1] = { kind = "word", s = text:sub(i, j), macro = true }
      i = j + 1
    elseif wordByte(text, i) then
      local j = wordEnd(text, i)
      tokens[#tokens + 1] = { kind = "word", s = text:sub(i, j) }
      i = j + 1
    else
      tokens[#tokens + 1] = { kind = "sep", s = text:sub(i, i) }
      i = i + 1
    end
  end
  return tokens
end

-- Mark each word's run: which words belong together, whether the run reads
-- as a sentence, and where each word sits in it.
local function markRuns(tokens)
  local run = nil
  local function close()
    if not run then return end
    local markers = 0
    for _, t in ipairs(run.words) do
      local key = keyOf(splitTail(t.s))
      if PROSE[key] then markers = markers + 1 end
    end
    run.prose = markers >= 2
    run = nil
  end
  for _, t in ipairs(tokens) do
    if t.kind == "word" then
      t.class = t.macro and "caps" or classify(t.s)
      if t.class == "mixed" then
        close()
      else
        if not run then run = { words = {} } end
        run.words[#run.words + 1] = t
        t.run = run
        t.pos = #run.words
      end
    elseif t.kind == "opaque" then
      close()
    end
  end
  close()
end

-- The whole pass.  Returns the converted string; never errors on odd input.
--
-- Running it twice is harmless: a word it already converted carries a
-- lowercase letter (or is a kept abbreviation), and classify() leaves such a
-- word alone.  That is what lets the font pass re-run over a message the
-- text seam already converted without undoing its sentence decisions.
function D.convert(text)
  if type(text) ~= "string" or text == "" then return text end
  -- fast exit: no run of two capitals anywhere, nothing to do
  if not text:find("%u[%u\195]") then return text end
  -- the Braille pages are a cipher drawn from capitals; re-casing them
  -- would change what they spell
  if text:find("BRAILLE", 1, true) then return text end
  local tokens = tokenize(text)
  markRuns(tokens)
  local out = {}
  local sentenceStart, phraseStart = true, true
  local lastWordKey = nil
  -- a row break after a mixed-case word is prose wrapping onto the next
  -- line; after an ALL-CAPS word (or at the top) it is a new menu entry
  local lastMixed = false
  local spaces = 0
  for _, t in ipairs(tokens) do
    if t.kind == "word" then
      local s = t.s
      if t.class == "caps" then
        local run = t.run
        local key = keyOf(splitTail(t.macro and s:sub(2) or s))
        local lower
        if run.prose then
          lower = STOP[key] == true
        else
          -- a joining word is lowercase unless it opens a sentence, a row
          -- or a menu column: "HALL OF FAME", "the OF course", "THE END"
          lower = MINOR[key] == true and not phraseStart
        end
        local converted, lowered
        if t.macro then
          -- "#MON" -> "Pokémon", "#DEX" -> "Pokédex"
          converted, lowered = "Pok\195\169" .. s:sub(2):lower(), false
        else
          converted, lowered = convertCaps(s, lower)
        end
        if lowered and sentenceStart then converted = capitalizeFirst(converted) end
        s = converted
      elseif t.class == "keep" and t.run and t.run.prose and #t.run.words > 1
          and s == "A" then
        -- the article inside an ALL-CAPS sentence: "HAVE A LOOK" -> "have a look"
        s = sentenceStart and "A" or "a"
      end
      out[#out + 1] = s
      lastWordKey = keyOf(t.s)
      lastMixed = t.class == "mixed"
      sentenceStart, phraseStart = false, false
      spaces = 0
    elseif t.kind == "opaque" then
      out[#out + 1] = t.s
      spaces = 0
    else
      local c = t.s
      if c == "." then
        -- PROF. OAK, MT. MOON, S.S.ANNE: not the end of a sentence
        local letters = lastWordKey and lastWordKey:gsub("'", "")
        if not (letters and (DOTTED[letters] or #letters == 1)) then
          sentenceStart, phraseStart = true, true
        end
      elseif c == "!" or c == "?" or c == ":" then
        sentenceStart, phraseStart = true, true
      elseif c == "\n" or c == "\v" or c == "\f" or c == "\r" or c == "\t" then
        -- a new row starts a new menu entry; a sentence carries on
        if not lastMixed then phraseStart = true end
      end
      if c == " " then
        spaces = spaces + 1
        -- a gap of two or more spaces is a menu column: "ITEM  RUN"
        if spaces >= 2 and not lastMixed then phraseStart = true end
      else
        spaces = 0
      end
      out[#out + 1] = c
    end
  end
  return table.concat(out)
end

-- The cached entry point the font passes use: they run over every string
-- the game draws, many of them every frame.
local cache, cacheCount = {}, 0
local CACHE_MAX = 4096

function D.cached(text)
  if type(text) ~= "string" or text == "" then return text end
  local hit = cache[text]
  if hit ~= nil then return hit end
  local ok, out = pcall(D.convert, text)
  if not ok then out = text end
  if cacheCount >= CACHE_MAX then cache, cacheCount = {}, 0 end
  cache[text] = out
  cacheCount = cacheCount + 1
  return out
end

function D.clearCache() cache, cacheCount = {}, 0 end

return D
