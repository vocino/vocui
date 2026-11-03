local _, ns = ...
local config = {}
ns.config = config

-- The central settings store. Each module owns one section of the live
-- SavedVariables table, declared with its defaults; the core never
-- reaches inside a section, it only fills and broadcasts. Changing a
-- setting takes effect at once: Set notifies every subscriber, and
-- modules apply the change in their callback. Nothing polls.
local sectionDefaults = {}
local listeners = {}

local function fresh(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = v end
  return copy
end

-- The live table: ns.db after boot, the SavedVariable before it, a
-- scratch table if neither exists yet (pre-load use never errors).
local function db()
  if type(ns.db) == "table" then return ns.db end
  if type(VocUIDB) == "table" then ns.db = VocUIDB return ns.db end
  ns.db = {}
  return ns.db
end

local function fill(name)
  local d = db()
  local defaults = sectionDefaults[name] or {}
  if type(d[name]) ~= "table" then d[name] = {} end
  for k, v in pairs(defaults) do
    if d[name][k] == nil then d[name][k] = fresh(v) end
  end
  return d[name]
end

-- Declare a module's section and return its live table. Missing keys
-- fill from defaults; unknown keys are left alone for forward
-- compatibility. Declared once per module, from its init.
function config.Section(name, defaults)
  sectionDefaults[name] = defaults or {}
  return fill(name)
end

-- Fill every declared section. Boot calls this after rebinding the
-- SavedVariable so file load order never matters.
function config.Init()
  for name in pairs(sectionDefaults) do fill(name) end
end

function config.Get(section, key)
  local s = db()[section]
  if type(s) == "table" and s[key] ~= nil then return s[key] end
  local defaults = sectionDefaults[section]
  if defaults and defaults[key] ~= nil then return fresh(defaults[key]) end
  return nil
end

-- The default for a key (a copy, for tables). The Settings panel reads
-- it so defaults are declared exactly once.
function config.Default(section, key)
  local defaults = sectionDefaults[section]
  if defaults then return fresh(defaults[key]) end
  return nil
end

function config.Set(section, key, value)
  fill(section)[key] = value
  for _, fn in ipairs(listeners) do
    pcall(fn, section, key, value)
  end
end

-- Subscribe to change events (section, key, value). A broken
-- subscriber never breaks the setter or the other subscribers.
function config.Subscribe(fn)
  if type(fn) == "function" then listeners[#listeners + 1] = fn end
end
