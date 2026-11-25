-- QoL Comp / core: the pieces every arm leans on.
--
--   options   one cached copy of the mod's option values, refreshed on
--             mod.options_changed, so per-frame wrappers read a table field
--             instead of walking the schema
--   patch     a reload-safe way to wrap an engine module's function: the
--             first wrap stores the pristine function on the module under a
--             private key, and every later install (hot reload, a second
--             boot) wraps THAT, so wrappers never pile up on each other
--   store     a tiny installation-wide key/value file in mod.cache, for the
--             start-menu layout (a preference, not part of any one save)
--   try       pcall with the failure logged once per label, so a broken seam
--             costs the player one feature, never the game

local V = ...
local mod = V.mod
local C = {}

-- ------- options
--
-- Read LIVE from the loader on every query, never from a copy taken at
-- install time: a copy goes stale the moment the player changes a row and
-- the mod.options_changed event does not arrive (a profile load, a second
-- manager, a reload), and a stale copy makes a toggle look broken.  A query
-- is two table lookups inside the loader, so the only thing memoised is the
-- per-frame answer for the hot readers (the font pass runs per string).

C.opts = setmetatable({}, {
  __index = function(_, key)
    local ok, value = pcall(mod.options.get, mod.options, key)
    if ok then return value end
    return nil
  end,
})

-- Option values are read once and kept until they change.  main.lua calls
-- C.refresh() on every mod.options_changed (a row stepped, RESET DEFAULTS, a
-- profile load), and newFrame re-reads them every REFRESH_FRAMES as a
-- safety net, so a value can never be stale for long.  (0.1.31 dropped the
-- whole cache every frame: each option read was then a protected call into
-- the options service, plus a new table, sixty times a second.)
local memo = {}
local REFRESH_FRAMES = 120
local lastRefresh = -REFRESH_FRAMES

function C.opt(key)
  local v = memo[key]
  if v == nil then
    v = C.opts[key]
    if v == nil then v = false end
    memo[key] = v
  end
  return v
end

-- per-frame work registered by the modules, run from main.lua's ONE
-- input.step wrapper: every extra hook wrapper costs the engine a vararg
-- pack per frame, so the mod keeps a single one
local frameTasks = {}

function C.onFrame(fn) frameTasks[#frameTasks + 1] = fn end

function C.newFrame(n, game, dt)
  if n - lastRefresh >= REFRESH_FRAMES then C.refresh(n) end
  for i = 1, #frameTasks do
    local ok, err = pcall(frameTasks[i], game, dt, n)
    if not ok then C.warnOnce("frame." .. i, err) end
  end
end

-- toggles store booleans; tolerate a stray string from an older options file
function C.on(key)
  local v = C.opt(key)
  return v == true or v == "on" or v == "true"
end

-- re-read every option (and put toggle-only patches on or off to match)
local enableHooks = {}

function C.refresh(n)
  for k in pairs(memo) do memo[k] = nil end
  if n then lastRefresh = n end
  C.syncToggles()
  for i = #enableHooks, 1, -1 do
    local h = enableHooks[i]
    if C.on(h.key) then
      table.remove(enableHooks, i)
      C.try("enable." .. h.key, h.fn)
    end
  end
end

-- Run fn once, the first time option `key` is on (now or later).  For a
-- hook that costs something every frame (FULL SCREEN MENUS' frame
-- composite), so it is only installed for someone who uses it.
function C.onEnable(key, fn)
  enableHooks[#enableHooks + 1] = { key = key, fn = fn }
  if C.on(key) then C.refresh() end
end

-- ------- logging

local warned = {}
C.warnings = {}

function C.log(fmt, ...)
  if mod.log and mod.log.info then mod.log:info(fmt, ...) end
end

function C.warnOnce(label, err)
  if warned[label] then return end
  warned[label] = true
  C.warnings[#C.warnings + 1] = tostring(label) .. ": " .. tostring(err)
  if mod.log and mod.log.warn then
    mod.log:warn("%s: %s", tostring(label), tostring(err))
  end
end

-- logged every time (a player-facing action failing is worth each line)
function C.warn(label, err)
  C.warnings[#C.warnings + 1] = tostring(label) .. ": " .. tostring(err)
  if mod.log and mod.log.warn then
    mod.log:warn("%s: %s", tostring(label), tostring(err))
  end
end

function C.try(label, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    C.warnOnce(label, a)
    return nil
  end
  return a, b, c
end

-- ------- reload-safe patching

local ORIG = "__qol_comp_orig_"

-- wrap tbl[name] with fn(orig, ...).  Returns true when installed.
function C.patch(tbl, name, fn)
  if type(tbl) ~= "table" then return false end
  local key = ORIG .. name
  local orig = rawget(tbl, key)
  if orig == nil then
    orig = tbl[name]
    if type(orig) ~= "function" then return false end
    rawset(tbl, key, orig)
  end
  tbl[name] = function(...) return fn(orig, ...) end
  return true
end

-- the untouched engine function behind a patch (or the live one)
function C.original(tbl, name)
  return rawget(tbl, ORIG .. name) or tbl[name]
end

-- A patch that is only installed while an option is on.
--
-- DECAPITALIZATION's font pass is the reason this exists: replacing
-- Font.encode makes the engine measure text uncached from then on (see
-- src/render/Font.lua Font.width), which is a cost no one should pay for a
-- toggle they left off.  So the wrapper goes on when the option goes on and
-- comes off again when it does not.
--
-- Taking a patch off only ever restores OUR OWN wrapper: if another mod has
-- since wrapped the same function, its wrapper is live instead of ours and
-- removing it would quietly disable that mod, so the patch stays.
local toggled = {}

function C.togglePatch(tbl, name, key, fn)
  if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then return false end
  toggled[#toggled + 1] = { tbl = tbl, name = name, key = key, fn = fn, on = false }
  return true
end

function C.syncToggles()
  for _, t in ipairs(toggled) do
    local want = C.on(t.key)
    if want ~= t.on then
      if want then
        if C.patch(t.tbl, t.name, t.fn) then
          t.installed = t.tbl[t.name]
          t.on = true
        end
      elseif t.tbl[t.name] == t.installed then
        t.tbl[t.name] = C.original(t.tbl, t.name)
        t.installed = nil
        t.on = false
      else
        -- someone else is on top of ours; leave it alone
        t.on = false
      end
    end
  end
end

C._toggled = toggled

-- ------- tiny persistent store (installation scope)

local function encode(t)
  local lines = {}
  for k, v in pairs(t) do
    lines[#lines + 1] = tostring(k) .. "=" .. tostring(v)
  end
  table.sort(lines)
  return table.concat(lines, "\n")
end

local function decode(s)
  local t = {}
  for line in (s or ""):gmatch("[^\n]+") do
    local k, v = line:match("^([^=]+)=(.*)$")
    if k then t[k] = v end
  end
  return t
end

function C.loadStore(name)
  if not (mod.cache and mod.cache.read) then return {} end
  local ok, bytes = pcall(mod.cache.read, mod.cache, "qol_comp/" .. name .. ".txt")
  if not ok or type(bytes) ~= "string" then return {} end
  return decode(bytes)
end

function C.saveStore(name, t)
  if not (mod.cache and mod.cache.write) then return false end
  local ok = pcall(mod.cache.write, mod.cache, "qol_comp/" .. name .. ".txt", encode(t))
  return ok
end

-- ------- engine modules
--
-- A mod's `package` is the sandbox's stand-in (src/mods/LegacyCompat.lua
-- packageShim): its `loaded` table is always EMPTY, so package.loaded[name]
-- is nil for every engine module.  v0.1.1 looked modules up that way in a
-- few places (Gen 3 REMATCH, HIDDEN ITEM SHINE, the START menu editor's
-- tutorial check), which quietly turned those parts off.  require is the
-- supported way in; an engine module is only ever loaded once, so asking for
-- one that is already loaded just hands back the same table.
function C.engine(name)
  local ok, m = pcall(require, name)
  if ok and type(m) == "table" then return m end
  return nil
end

-- ------- misc helpers

function C.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function C.round(v) return math.floor(v + 0.5) end

-- a shallow list copy
function C.copy(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

return C
