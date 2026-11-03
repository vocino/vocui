-- Headless tests for VocUI. No game client needed.
-- Run from the repo root:  lua tests/run.lua

local mock = dofile("tests/mock.lua")
mock.install()

local pass, fail = 0, 0
local function check(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL " .. name)
  end
end

local CORE = {
  "core/Palette.lua",
  "core/Chat.lua",
  "core/Sounds.lua",
  "core/Config.lua",
  "core/Inventory.lua",
  "core/Prices.lua",
  "core/Modules.lua",
  "core/Settings.lua",
  "core/Slash.lua",
  "core/Main.lua",
}

-- Loads the whole core into one namespace, in toc order, as the client does.
local function loadCore()
  local ns = {}
  for _, file in ipairs(CORE) do
    assert(loadfile(file))("VocUI", ns)
  end
  return ns
end

-- Runs fn with print captured; print is restored even when fn errors.
local function capturePrint(fn)
  local lines = {}
  local realPrint = print
  print = function(s)
    lines[#lines + 1] = s
  end
  local ok, err = pcall(fn)
  print = realPrint
  assert(ok, err)
  return lines
end

-- palette.lua: every color has a name; rgb() spreads a token
do
  local ns = loadCore()
  local c = ns.COLORS
  check(
    "family tokens present",
    c.gold[1] == 1 and c.gold[2] == 0.82 and c.gold[3] == 0 and c.text and c.muted and c.red and c.green
  )
  local r, g, b, a = ns.rgb(c.gold, 0.5)
  check("rgb spreads a token with alpha", r == 1 and g == 0.82 and b == 0 and a == 0.5)
  r, g, b, a = ns.rgb(c.text)
  check("rgb without alpha", r == 1 and g == 1 and b == 1 and a == nil)
end

-- Chat.lua: the family chat voice (colored prefix, no trailing period)
do
  local ns = loadCore()
  check("family prefix color", ns.PREFIX_COLOR == "ff66ccff")
  local said = capturePrint(function()
    ns.say("hello")
  end)
  check("say prefixes the package name", said[1] == "|c" .. ns.PREFIX_COLOR .. "VocUI|r: hello")
end

-- Sounds.lua: SOUNDKIT names first, numeric fallback, silent without an API
do
  local ns = loadCore()
  local played = {}
  _G.PlaySound = function(id)
    played[#played + 1] = id
  end
  _G.SOUNDKIT = nil
  ns.play("open")
  ns.play("off")
  _G.SOUNDKIT = { IG_MAINMENU_OPEN = 1850 }
  ns.play("open")
  ns.play("bogus")
  check("sound fallback then SOUNDKIT name", table.concat(played, ",") == "850,857,1850")
  _G.PlaySound = nil
  ns.play("open") -- no sound API: silent, never an error
  check("no sound API is silent", #played == 3)
  _G.SOUNDKIT = nil
  check("unknown kind never errors", pcall(ns.play, "bogus") == true)
end

-- Config.lua: per-module sections, defaults fill once, Set broadcasts
do
  local ns = loadCore()
  local live = ns.config.Section("demo", { enabled = true, label = "x", list = { 1 } })
  check("section fills defaults", live.enabled == true and live.label == "x")
  check("section returns the live table", live == ns.db.demo)
  live.list[2] = 2
  ns.db = {} -- a new install binds a new table; defaults copy in, never alias
  local installed = ns.config.Section("demo", { enabled = true, label = "x", list = { 1 } })
  check("table defaults are not shared", installed.list[2] == nil and #installed.list == 1)
  check("get reads live values", ns.config.Get("demo", "label") == "x")
  ns.db.demo.label = nil
  check("get falls back to the default", ns.config.Get("demo", "label") == "x")
  check("get misses outside defaults", ns.config.Get("demo", "nope") == nil and ns.config.Get("ghost", "nope") == nil)
  local defaultList = ns.config.Default("demo", "list")
  check("default returns a copy", type(defaultList) == "table" and defaultList ~= live.list)
  local events = {}
  ns.config.Subscribe(function(section, key, value)
    events[#events + 1] = section .. "." .. key .. "=" .. tostring(value)
  end)
  ns.config.Subscribe(function()
    error("broken listener")
  end)
  ns.config.Subscribe(nil) -- ignored, never an error
  ns.config.Set("demo", "enabled", false)
  check("set writes the live table", ns.db.demo.enabled == false)
  check("set broadcasts to subscribers", events[1] == "demo.enabled=false")
  check("a broken subscriber never breaks the setter", #events == 1)
end

-- Config.lua: Init fills declared sections on the rebound table
do
  local ns = loadCore()
  ns.config.Section("demo", { enabled = true })
  ns.db = { unknown = 1 }
  ns.config.Init()
  check("init fills declared sections", ns.db.demo.enabled == true)
  check("init leaves unknown keys alone", ns.db.unknown == 1)
end

-- Modules.lua: descriptors register, breakage stays contained
do
  local ns = loadCore()
  local said = {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  local order = {}
  check(
    "register rejects junk",
    ns.modules.Register(nil) == false
      and ns.modules.Register({}) == false
      and ns.modules.Register({ name = "bad" }) == false
  )
  ns.modules.Register({
    name = "good",
    job = "first",
    init = function()
      order[#order + 1] = "good"
    end,
  })
  ns.modules.Register({
    name = "broken",
    job = "second",
    init = function()
      error("boom")
    end,
  })
  ns.modules.Register({
    name = "third",
    job = "third",
    init = function()
      order[#order + 1] = "third"
    end,
  })
  ns.modules.Register({
    name = "hidden",
    job = "never here",
    -- gated at load: this situation never applies, so it stays hidden
    IsAvailable = function()
      return false
    end,
    init = function()
      order[#order + 1] = "hidden"
    end,
  })
  ns.modules.Register({
    name = "checker",
    job = "faulty check",
    IsAvailable = function()
      error("no api")
    end,
    init = function()
      order[#order + 1] = "checker"
    end,
  })
  ns.modules.InitAll()
  check("every available module initializes", order[1] == "good" and order[2] == "third" and #order == 2)
  check("unavailable modules stay hidden", order[3] == nil)
  check("problems and breakage are reported", #said == 5)
  local periods = false
  for _, line in ipairs(said) do
    if line:sub(-1) == "." then
      periods = true
    end
  end
  check("chat lines never end in a period", not periods)
  local a, b = ns.modules.GetAll(), ns.modules.GetAll()
  check("GetAll returns a fresh list", a ~= b and #a == 5)
end

-- Settings.lua: one native category; modules add their own sections
do
  local categories, openedID, headers = {}, nil, {}
  _G.Settings = {
    RegisterVerticalLayoutCategory = function(n)
      local cat = {
        name = n,
        GetID = function()
          return 7
        end,
      }
      categories[#categories + 1] = cat
      return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id)
      openedID = id
    end,
  }
  _G.SettingsPanel = {
    GetLayout = function()
      return {
        AddInitializer = function(_, init)
          headers[#headers + 1] = init
        end,
      }
    end,
  }
  _G.CreateSettingsListSectionHeaderInitializer = function(text)
    return text
  end

  local ns = loadCore()
  ns.db = {}
  local builtWith = {}
  ns.modules.Register({
    name = "demo",
    job = "x",
    init = function() end,
    BuildPanel = function(cat)
      builtWith[#builtWith + 1] = cat
    end,
  })
  ns.modules.Register({
    name = "oops",
    job = "x",
    init = function() end,
    BuildPanel = function()
      error("panel boom")
    end,
  })
  local said = {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.settings.Init()
  check("one category for the package", #categories == 1 and categories[1].name == "VocUI")
  check("module sections build against the category", #builtWith == 1 and builtWith[1] == categories[1])
  check("a broken panel never breaks the package", #said == 1 and said[1]:find("oops", 1, true) ~= nil)
  check("slash-line note added", headers[1] == "More on the slash line: /vui help")
  ns.settings.Open()
  check("open goes to the category", openedID == 7)
  ns.settings.Init()
  check("init builds the category once", #categories == 1)
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
end

-- Settings.lua: no modules yet, so the panel says where sections go
do
  local headers = {}
  _G.Settings = {
    RegisterVerticalLayoutCategory = function(n)
      return {
        name = n,
        GetID = function()
          return 7
        end,
      }
    end,
    RegisterAddOnCategory = function() end,
  }
  _G.SettingsPanel = {
    GetLayout = function()
      return {
        AddInitializer = function(_, init)
          headers[#headers + 1] = init
        end,
      }
    end,
  }
  _G.CreateSettingsListSectionHeaderInitializer = function(text)
    return text
  end
  local ns = loadCore()
  ns.db = {}
  ns.settings.Init()
  check(
    "empty panel names the module contract",
    headers[1] == "No modules installed yet: modules add their own sections here"
  )
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
end

-- Settings.lua without the Settings API: no-op init, open says where
do
  local ns = loadCore()
  ns.db = {}
  local said
  ns.say = function(line)
    said = line
  end
  ns.settings.Init() -- no Settings API: no-op, never an error
  ns.settings.Open()
  check("open without Settings prints the path", said == "open Settings > AddOns > VocUI")
end

-- Slash.lua: short and long forms, bare opens settings, the rest is help
do
  local ns = loadCore()
  check("short slash is /vui", _G.SLASH_VOCUI1 == "/vui")
  check("long slash is /vocui", _G.SLASH_VOCUI2 == "/vocui")
  check("slash handler installed", type(_G.SlashCmdList.VOCUI) == "function")
  check("config sits second to last", ns.HELP[#ns.HELP - 1]:find("config", 1, true) ~= nil)
  check(
    "help is last and names the long form",
    ns.HELP[#ns.HELP]:find("help", 1, true) ~= nil and ns.HELP[#ns.HELP]:find("/vocui", 1, true) ~= nil
  )

  local opened, played = 0, {}
  ns.settings = {
    Open = function()
      opened = opened + 1
    end,
  }
  ns.play = function(kind)
    played[#played + 1] = kind
  end
  local printed = capturePrint(function()
    _G.SlashCmdList.VOCUI("")
    _G.SlashCmdList.VOCUI("config")
    _G.SlashCmdList.VOCUI("CONFIG")
  end)
  check("bare and config open settings", opened == 3)
  check("opening plays the open sound", #played == 3 and played[1] == "open")
  check("openers print nothing", #printed == 0)

  local lines = capturePrint(function()
    _G.SlashCmdList.VOCUI("bogus-command")
    _G.SlashCmdList.VOCUI("help")
  end)
  check("typos print help, never act", opened == 3 and #lines == 2 * (1 + #ns.HELP))
  check("help lines carry the prefix", lines[1]:find("^|cff66ccffVocUI|r: ") ~= nil)
end

-- Main.lua: the addon compartment (gold title, job line, slash hint)
do
  local ns = loadCore()
  check(
    "compartment trio defined",
    type(_G.VocUI_CompartmentClick) == "function"
      and type(_G.VocUI_CompartmentEnter) == "function"
      and type(_G.VocUI_CompartmentLeave) == "function"
  )
  local opened, played = 0, 0
  ns.settings = {
    Open = function()
      opened = opened + 1
    end,
  }
  ns.play = function()
    played = played + 1
  end
  _G.VocUI_CompartmentClick("VocUI", "LeftButton")
  check("compartment click opens settings", opened == 1 and played == 1)
  local tip = { lines = {} }
  _G.GameTooltip = {
    SetOwner = function(_, owner, anchor)
      tip.owner, tip.anchor = owner, anchor
    end,
    SetText = function(_, t, r, g, b)
      tip.title = t
      tip.color = { r, g, b }
    end,
    AddLine = function(_, t)
      tip.lines[#tip.lines + 1] = t
    end,
    Show = function()
      tip.shown = true
    end,
    Hide = function()
      tip.shown = false
    end,
  }
  local btn = {}
  _G.VocUI_CompartmentEnter("VocUI", btn)
  check(
    "compartment tooltip anchors to the button",
    tip.owner == btn and tip.anchor == "ANCHOR_LEFT" and tip.shown == true
  )
  check(
    "compartment tooltip title is gold",
    tip.title == "VocUI" and tip.color[1] == 1 and tip.color[2] == 0.82 and tip.color[3] == 0
  )
  check("compartment tooltip teaches the slash", #tip.lines == 2 and tip.lines[2]:find("/vui", 1, true) ~= nil)
  _G.VocUI_CompartmentLeave("VocUI", btn)
  check("compartment leave hides the tooltip", tip.shown == false)
  _G.GameTooltip = nil
  check("compartment enter without the API is silent", pcall(_G.VocUI_CompartmentEnter, "VocUI", btn) == true)
end

-- Main.lua: boot rebinds the SavedVariable, then inits once
do
  mock.reset()
  local ns = loadCore()
  local boot = mock.frames[#mock.frames]
  local onEvent = boot.scripts.OnEvent
  check("boot listens for load and login", boot.events.ADDON_LOADED and boot.events.PLAYER_LOGIN)
  local inits = {}
  ns.modules.Register({
    name = "early",
    job = "x",
    init = function()
      inits[#inits + 1] = "early"
    end,
  })
  onEvent(boot, "ADDON_LOADED", "SomeOtherAddon")
  check("other addons never boot the package", ns.db == nil and #inits == 0)
  _G.VocUIDB = { unknown = 1 }
  onEvent(boot, "ADDON_LOADED", "VocUI")
  check("boot rebinds the SavedVariable", ns.db == _G.VocUIDB)
  check("boot initializes modules", #inits == 1)
  check("boot leaves unknown keys alone", ns.db.unknown == 1)
  check("load event unregisters", boot.events.ADDON_LOADED == nil)
  onEvent(boot, "PLAYER_LOGIN")
  check("login event unregisters", boot.events.PLAYER_LOGIN == nil)
end

-- Config.lua: dotted sections nest module state under VocUIDB.modules
do
  local ns = loadCore()
  local live = ns.config.Section("modules.demo", { enabled = true })
  check("module state nests under modules", live.enabled == true and ns.db.modules.demo == live and ns.db.demo == nil)
  ns.config.Set("modules.demo", "enabled", false)
  check("dotted set/get round-trips", ns.config.Get("modules.demo", "enabled") == false)
end

-- Config.lua: a hand-edited or stale key holding the wrong type resets
do
  local ns = loadCore()
  ns.db = { demo = { enabled = "yes", label = "x", extra = 1 } }
  local live = ns.config.Section("demo", { enabled = true, label = "x" })
  check("wrong-typed keys reset to defaults", live.enabled == true and live.label == "x" and live.extra == 1)
end

-- Gear module: the Forever build of the VocGear job. Item level decides
-- (Pawn has no Forever build); Pawn and Great Vault code does not exist.
local GEAR = {
  "modules/gear/Gear.lua",
  "modules/gear/Evaluate.lua",
  "modules/gear/Panel.lua",
  "modules/gear/Scan.lua",
  "modules/gear/Sheet.lua",
}
local function loadGear()
  local ns = loadCore()
  for _, file in ipairs(GEAR) do
    assert(loadfile(file))("VocUI", ns)
  end
  return ns
end

-- A stub world for gear tests: items keyed by link, bags and equipped
-- slots as link tables, and every WoW global the module reads.
local function gearWorld()
  local w = {
    items = {},
    bags = {},
    equipped = {},
    equips = {},
    headers = {},
    level = 60,
    classKey = "WARLOCK",
    time = 1000,
    combat = false,
    rangedSlot = 18,
    avgIlvl = 0,
    timers = {},
    setBonusIDs = {},
  }
  local function item(link)
    return w.items[link]
  end
  _G.NUM_BAG_SLOTS = 4
  _G.C_Item = {
    GetItemInfo = function(link)
      local it = item(link)
      if not it then
        return nil
      end
      return link,
        link,
        it.rarity or 2,
        it.ilvl or 0,
        it.minLevel or 0,
        "",
        "",
        1,
        it.equipLoc or "",
        "",
        it.sellPrice or 0,
        it.classID or 0,
        it.subclassID or 0,
        1,
        1,
        it.setID
    end,
    GetItemInfoInstant = function(link)
      local it = item(link)
      if not it then
        return nil
      end
      return it.id or 1, "", "", it.equipLoc or "", "", it.classID or 0, it.subclassID or 0
    end,
    GetDetailedItemLevelInfo = function(link)
      local it = item(link)
      return it and it.ilvl or nil
    end,
    IsEquippableItem = function(link)
      local it = item(link)
      return not it or it.equippable ~= false
    end,
    EquipItemByName = function(link, slot)
      w.equips[#w.equips + 1] = { link = link, slot = slot }
    end,
    GetItemUniquenessByID = function(link)
      local it = item(link)
      return it and it.unique == true or false
    end,
    GetSetBonusesForSpecializationByItemID = function(_, itemID)
      if w.setBonusIDs[itemID] then
        return { 1 }
      end
      return {}
    end,
    GetItemSetInfo = function()
      return "Testplate"
    end,
  }
  _G.C_Container = {
    GetContainerNumSlots = function(bag)
      return #(w.bags[bag] or {})
    end,
    GetContainerItemLink = function(bag, slot)
      return (w.bags[bag] or {})[slot]
    end,
  }
  _G.C_PaperDollInfo = {
    GetInventorySlotInfo = function()
      return w.rangedSlot
    end,
    GetMinItemLevel = function()
      return 0
    end,
  }
  _G.C_SpecializationInfo = {
    GetSpecialization = function()
      return 1
    end,
    GetSpecializationInfo = function()
      return 123
    end,
  }
  _G.C_AddOns = {
    IsAddOnLoaded = function()
      return false
    end,
    GetAddOnInfo = function()
      return nil
    end,
  }
  _G.C_PetBattles = {
    IsInBattle = function()
      return false
    end,
  }
  _G.C_Timer = {
    After = function(_, fn)
      w.timers[#w.timers + 1] = fn
    end,
  }
  _G.GetInventoryItemLink = function(_, slot)
    return w.equipped[slot]
  end
  _G.UnitClass = function()
    return "Warlock", w.classKey
  end
  _G.UnitLevel = function()
    return w.level
  end
  _G.GetTime = function()
    return w.time
  end
  _G.InCombatLockdown = function()
    return w.combat
  end
  _G.UnitAffectingCombat = function()
    return false
  end
  _G.UnitIsDeadOrGhost = function()
    return false
  end
  _G.GetAverageItemLevel = function()
    return w.avgIlvl, w.avgIlvl, 0
  end
  _G.PaperDollFrame = {}
  _G.PaperDollFrame_SetItemLevel = function() end
  _G.hooksecurefunc = function() end
  return w
end

local function addItem(w, link, fields)
  w.items[link] = fields
  return link
end

-- Gear: descriptor, state location, Forever-only options
do
  gearWorld()
  local ns = loadGear()
  ns.db = {}
  local gear = ns.gear
  check(
    "gear descriptor registered",
    ns.modules.GetAll()[1] == gear.descriptor and gear.descriptor.name == "gear" and gear.descriptor.default == true
  )
  ns.modules.InitAll()
  check(
    "gear state lives under modules.gear",
    type(ns.db.modules) == "table" and ns.db.modules.gear.enabled == true and ns.db.gear == nil
  )
  local keys = {}
  for _, row in ipairs(gear.OPTIONS) do
    keys[row.key] = true
  end
  check(
    "forever options present",
    keys.enabled
      and keys.announce
      and keys.audit
      and keys.autoTwoSlot
      and keys.keepHeirlooms
      and keys.protectSets
      and keys.swapWeapons
      and keys.equipSound
      and keys.sessionIlvl
      and keys.sheetButton
  )
  check(
    "retail-only options absent",
    not keys.minUpgradePct and not keys.scale and not keys.includeIlvl and gear.defaults.minUpgradePct == nil
  )
  check("no pawn or vault code", gear.EvaluatePawn == nil and gear.VaultSay == nil and gear.VaultRecommend == nil)
  check(
    "gear help lines keep config second to last",
    ns.HELP[#ns.HELP - 1]:find("config", 1, true) ~= nil and ns.HELP[3]:find("/vui gear", 1, true) ~= nil
  )
  _G.C_Item, _G.C_Container = nil, nil
  check("unavailable gear stays hidden", gear.IsAvailable() == false)
end

-- Gear evaluate: item level behind the gates
do
  local w = gearWorld()
  local ns = loadGear()
  ns.db = {}
  local gear = ns.gear
  addItem(w, "oldchest", { equipLoc = "INVTYPE_CHEST", ilvl = 10, classID = 4, subclassID = 1 })
  addItem(w, "newchest", { equipLoc = "INVTYPE_CHEST", ilvl = 15, classID = 4, subclassID = 1 })
  addItem(w, "weakchest", { equipLoc = "INVTYPE_CHEST", ilvl = 5, classID = 4, subclassID = 1 })
  w.equipped[5] = "oldchest"
  local up = gear.Evaluate("newchest")
  check("higher item level upgrades", up.upgrade == true and up.ilvlDiff == 5)
  check("lower item level does not", gear.Evaluate("weakchest").upgrade == false)
  addItem(w, "neck", { equipLoc = "INVTYPE_NECK", ilvl = 8 })
  check("empty slot takes an upgrade", gear.Evaluate("neck").upgrade == true)
  addItem(w, "trash", { equipLoc = "INVTYPE_CHEST", ilvl = 99, rarity = 0, classID = 4, subclassID = 1 })
  check("grey never displaces worn gear", gear.Evaluate("trash").upgrade == false)
  addItem(w, "mailchest", { equipLoc = "INVTYPE_CHEST", ilvl = 99, classID = 4, subclassID = 3 })
  check("wrong armor type refused", gear.Evaluate("mailchest").upgrade == false)
  addItem(w, "future", { equipLoc = "INVTYPE_NECK", ilvl = 99, minLevel = 61 })
  check("above-level refused", gear.Evaluate("future").upgrade == false)
  addItem(w, "shirt", { equipLoc = "INVTYPE_BODY", ilvl = 99 })
  check("cosmetic refused", gear.Evaluate("shirt").upgrade == false)
  addItem(w, "knife", { equipLoc = "INVTYPE_WEAPON", ilvl = 99, classID = 2, subclassID = 14 })
  check("profession tool refused", gear.Evaluate("knife").upgrade == false)
  -- Forever ranged layout: bows compare against slot 18, not the main hand.
  addItem(w, "oldbow", { equipLoc = "INVTYPE_RANGED", ilvl = 10, classID = 2, subclassID = 2 })
  addItem(w, "newbow", { equipLoc = "INVTYPE_RANGED", ilvl = 20, classID = 2, subclassID = 2 })
  w.equipped[18] = "oldbow"
  check("ranged home is the forever slot", gear.HomeSlot("INVTYPE_RANGED") == 18)
  check("bow displaces bow at 18", gear.Evaluate("newbow").upgrade == true)
  -- Leveling armor: a level-30 hunter's leather passes, a 50's does not.
  w.classKey, w.level = "HUNTER", 30
  addItem(w, "leather", { equipLoc = "INVTYPE_CHEST", ilvl = 99, classID = 4, subclassID = 2 })
  addItem(w, "mailworn", { equipLoc = "INVTYPE_CHEST", ilvl = 10, classID = 4, subclassID = 3 })
  w.equipped[5] = "mailworn"
  check("pre-40 leveling armor passes", gear.Evaluate("leather").upgrade == true)
  w.level = 50
  check("post-40 leveling armor refused", gear.Evaluate("leather").upgrade == false)
end

-- Gear scan: equips, combat, audit, two-slot, heirloom, rival, toggle
do
  local w = gearWorld()
  local ns = loadGear()
  ns.db = {}
  ns.modules.InitAll()
  local gear, said = ns.gear, {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  addItem(w, "oldchest", { equipLoc = "INVTYPE_CHEST", ilvl = 10, classID = 4, subclassID = 1 })
  addItem(w, "newchest", { equipLoc = "INVTYPE_CHEST", ilvl = 15, classID = 4, subclassID = 1 })
  w.equipped[5] = "oldchest"
  w.bags[0] = { "newchest" }
  gear.Scan()
  check("scan equips an upgrade", #w.equips == 1 and w.equips[1].link == "newchest")
  check("equip is announced", said[1] ~= nil and said[1]:find("equipped", 1, true) ~= nil)
  w.combat = true
  gear.Scan()
  check("nothing equips in combat", #w.equips == 1)
  w.combat = false
  gear.opts().audit = true
  gear.CheckNowImpl()
  check("audit mode equips nothing", #w.equips == 1)
  gear.opts().audit = false
  -- Rings announce by default; with auto-two-slot they take the weaker slot.
  addItem(w, "ringA", { equipLoc = "INVTYPE_FINGER", ilvl = 5 })
  addItem(w, "ringB", { equipLoc = "INVTYPE_FINGER", ilvl = 9 })
  addItem(w, "newring", { equipLoc = "INVTYPE_FINGER", ilvl = 12 })
  w.equipped[11], w.equipped[12] = "ringA", "ringB"
  w.bags[0] = { "newring" }
  gear.CheckNowImpl()
  check("rings announce by default", #w.equips == 1)
  gear.opts().autoTwoSlot = true
  gear.CheckNowImpl()
  check("rings equip into the weaker slot", #w.equips == 2 and w.equips[2].link == "newring" and w.equips[2].slot == 11)
  -- Heirlooms are kept.
  addItem(w, "heirloom", { equipLoc = "INVTYPE_CHEST", ilvl = 10, rarity = 7, classID = 4, subclassID = 1 })
  addItem(w, "better", { equipLoc = "INVTYPE_CHEST", ilvl = 30, classID = 4, subclassID = 1 })
  w.equipped[5] = "heirloom"
  w.bags[0] = { "better" }
  gear.CheckNowImpl()
  check("heirlooms are kept", #w.equips == 2)
  -- A rival stands the module down; an explicit on resumes it.
  gear.CheckRival("Outfitter")
  gear.Scan()
  check("a rival stands gear down", #w.equips == 2 and gear.rivalStoodDown == true)
  w.equipped[5] = "oldchest"
  ns.Slash = nil
  gear.SetEnabled(true)
  check("explicit on resumes past a rival", #w.equips == 3)
  -- Toggling off unregisters the scan events.
  gear.SetEnabled(false)
  check(
    "toggle off unregisters scan events",
    gear.frame.events.BAG_UPDATE_DELAYED == nil and gear.opts().enabled == false
  )
end

-- Gear panel: subcategory under VocUI, Forever rows only, live callbacks
do
  local w = gearWorld()
  local registered, subcats, inits = {}, {}, {}
  _G.Settings = {
    RegisterVerticalLayoutCategory = function(n)
      return {
        name = n,
        GetID = function()
          return 7
        end,
      }
    end,
    RegisterVerticalLayoutSubcategory = function(parent, n)
      local sub = { name = n, parent = parent }
      subcats[#subcats + 1] = sub
      return sub
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
    RegisterAddOnSetting = function(page, variable, key, tbl, vtype, label, default)
      local s = { page = page, variable = variable, key = key }
      s.SetValueChangedCallback = function(_, fn)
        s.callback = fn
      end
      registered[#registered + 1] = s
      return s
    end,
    CreateCheckbox = function(_, s)
      local i = { setting = s }
      inits[#inits + 1] = i
      return i
    end,
    CreateDropdown = function(_, s)
      local i = { setting = s, dropdown = true }
      inits[#inits + 1] = i
      return i
    end,
    CreateControlTextContainer = function()
      local data = {}
      return {
        Add = function(_, v, label)
          data[#data + 1] = { value = v, label = label }
        end,
        GetData = function()
          return data
        end,
      }
    end,
  }
  _G.SettingsPanel = {
    GetLayout = function()
      return {
        AddInitializer = function(_, init)
          w.headers[#w.headers + 1] = init
        end,
      }
    end,
  }
  _G.CreateSettingsListSectionHeaderInitializer = function(text)
    return text
  end
  local ns = loadGear()
  ns.db = {}
  ns.modules.InitAll()
  ns.settings.Init()
  local gear = ns.gear
  check("gear page is a subcategory under VocUI", #subcats == 1 and subcats[1].name == "Gear")
  check("panel rows bind to the subcategory", registered[1].page == subcats[1])
  local keys = {}
  for _, s in ipairs(registered) do
    keys[#keys + 1] = s.key
  end
  check(
    "panel registers the forever rows in order",
    table.concat(keys, ",")
      == "enabled,announce,audit,autoTwoSlot,keepHeirlooms,protectSets,swapWeapons,equipSound,sessionIlvl,sheetButton"
  )
  check(
    "panel leads with the job and the source",
    w.headers[1] == gear.descriptor.job and w.headers[2] == "Upgrade source: built-in item level"
  )
  local sounds = gear.EquipSoundOptions()
  check(
    "equip sound dropdown offers off and the chimes",
    sounds[1].value == "0" and sounds[2].value == "878" and #sounds == 4
  )
  -- The enabled row's callback unregisters events when switched off.
  local enabledSetting
  for _, s in ipairs(registered) do
    if s.key == "enabled" then
      enabledSetting = s
    end
  end
  ns.db.modules.gear.enabled = false
  enabledSetting.callback()
  check("panel toggle applies live", gear.frame.events.BAG_UPDATE_DELAYED == nil)
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
end

-- Gear sheet and slash: session gain readout, Check Bags, /vui gear ...
do
  local w = gearWorld()
  local ns = loadGear()
  ns.db = {}
  ns.modules.InitAll()
  local gear, said = ns.gear, {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  w.avgIlvl = 20
  gear.CaptureSessionStartImpl()
  w.avgIlvl = 25
  local value = {
    text = nil,
    SetText = function(self, t)
      self.text = t
    end,
  }
  gear.OnItemLevelSet({ Value = value, tooltip2 = "base" }, "player")
  check(
    "session gain suffixes the readout",
    value.text ~= nil and value.text:find("25", 1, true) ~= nil and value.text:find("%(%+5%)") ~= nil
  )
  gear.IlvlSayImpl()
  check(
    "ilvl line reports the session gain",
    said[#said]:find("session %+5 from 20", 1, true) ~= nil or said[#said]:find("session +5 from 20", 1, true) ~= nil
  )
  gear.EnsureSheetImpl()
  check(
    "check bags button on the sheet",
    gear.sheetButton ~= nil and gear.sheetButton.text == "Check Bags" and gear.sheetButton.shown == true
  )
  -- Slash dispatch through the core command.
  local played = {}
  ns.play = function(kind)
    played[#played + 1] = kind
  end
  _G.SlashCmdList.VOCUI("gear off")
  check("slash turns the module off with sound", gear.opts().enabled == false and played[#played] == "off")
  _G.SlashCmdList.VOCUI("gear on")
  check("slash turns the module on with sound", gear.opts().enabled == true and played[#played] == "on")
  _G.SlashCmdList.VOCUI("gear announce")
  check("slash toggles announcements", gear.opts().announce == false)
  local before = #played
  _G.SlashCmdList.VOCUI("gear bogus")
  check("unknown gear subcommand only prints help", gear.opts().enabled == true and #played == before)
  _G.PaperDollFrame, _G.PaperDollFrame_SetItemLevel, _G.hooksecurefunc = nil, nil, nil
end

-- Guests: Syndicator bag data and Auctionator prices, presence-gated
-- and pcall-guarded, silent when absent or broken.
do
  local ns = loadCore()
  check(
    "no guests means nil data",
    ns.inventory.BagLinks() == nil and ns.inventory.Available() == false and ns.prices.AuctionPrice("x") == nil
  )
  _G.C_Item = {
    GetItemInfo = function()
      return nil, nil, 2, 0, 0, "", "", 1, "", "", 500
    end,
  }
  check("vendor fallback prices the link", ns.prices.VendorPrice("x") == 500)
  check(
    "money labels read plainly",
    ns.prices.Label(123456) == "12g 34s 56c"
      and ns.prices.Label(1) == "1c"
      and ns.prices.Label(0) == nil
      and ns.prices.Suffix("x") == " (vendor 5s)"
  )
  _G.C_Item = nil
  check("no item api means no vendor price", ns.prices.VendorPrice("x") == nil and ns.prices.Suffix("x") == "")
  _G.Auctionator = {
    API = {
      v1 = {
        GetAuctionPriceByItemLink = function(caller, link)
          assert(type(caller) == "string", "caller id first")
          return link == "rich" and 123456 or nil
        end,
        GetVendorPriceByItemLink = function()
          return nil
        end,
      },
    },
  }
  check("auctionator prices the link", ns.prices.AuctionPrice("rich") == 123456)
  check("auction suffix wins over vendor", ns.prices.Suffix("rich") == " (auction 12g 34s 56c)")
  check("unknown links stay silent", ns.prices.AuctionPrice("poor") == nil)
  _G.Auctionator = { API = { v1 = {
    GetAuctionPriceByItemLink = function()
      error("boom")
    end,
  } } }
  check(
    "a broken guest never errors",
    pcall(ns.prices.AuctionPrice, "rich") == true and ns.prices.AuctionPrice("rich") == nil
  )
  _G.Auctionator = nil
end

-- Syndicator bag cache: current character's bags, settles before use.
do
  local ns = loadCore()
  local bags = { [1] = { { itemLink = "a" }, {} }, [2] = { { itemLink = "b" } } }
  local pending = false
  _G.Syndicator = {
    API = {
      IsReady = function()
        return true
      end,
      IsBagEventPending = function()
        return pending
      end,
      GetCurrentCharacter = function()
        return "A-Realm"
      end,
      GetByCharacterFullName = function()
        return { bags = bags }
      end,
    },
  }
  check(
    "settled cache lists bag links",
    ns.inventory.Available() == true and table.concat(ns.inventory.BagLinks(), ",") == "a,b"
  )
  pending = true
  check("pending cache falls back to blizzard", ns.inventory.BagLinks() == nil and ns.inventory.Pending() == true)
  _G.Syndicator = nil
  check("no syndicator falls back to blizzard", ns.inventory.BagLinks() == nil)
end

-- Gear through Syndicator: the scan reads bag links from the cache,
-- and the why lines carry Auctionator value.
do
  local w = gearWorld()
  local ns = loadGear()
  ns.db = {}
  ns.modules.InitAll()
  local gear, said = ns.gear, {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  addItem(w, "oldchest", { equipLoc = "INVTYPE_CHEST", ilvl = 10, classID = 4, subclassID = 1 })
  addItem(w, "newchest", { equipLoc = "INVTYPE_CHEST", ilvl = 15, classID = 4, subclassID = 1 })
  w.equipped[5] = "oldchest"
  w.bags = {} -- nothing in the blizzard walk: the cache is the source
  _G.Syndicator = {
    API = {
      IsReady = function()
        return true
      end,
      IsBagEventPending = function()
        return false
      end,
      GetCurrentCharacter = function()
        return "A-Realm"
      end,
      GetByCharacterFullName = function()
        return { bags = { [1] = { { itemLink = "newchest" } } } }
      end,
    },
  }
  gear.Scan()
  check("scan equips from the syndicator cache", #w.equips == 1 and w.equips[1].link == "newchest")
  _G.Syndicator = nil
  _G.Auctionator = {
    API = {
      v1 = {
        GetAuctionPriceByItemLink = function()
          return 123456
        end,
        GetVendorPriceByItemLink = function()
          return nil
        end,
      },
    },
  }
  w.bags = { [0] = { "newchest" } }
  gear.WhySayImpl()
  local valued = false
  for _, line in ipairs(said) do
    if line:find("newchest", 1, true) and line:find("(auction 12g 34s 56c)", 1, true) then
      valued = true
    end
  end
  check("why lines carry auction value", valued)
  _G.Auctionator = nil
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail > 0 and 1 or 0)
