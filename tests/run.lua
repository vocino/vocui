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
  "core/Combat.lua",
  "core/Config.lua",
  "core/Inventory.lua",
  "core/Consumables.lua",
  "core/Guests.lua",
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
    "palette tokens present",
    c.gold[1] == 1 and c.gold[2] == 0.82 and c.gold[3] == 0 and c.text and c.muted and c.red and c.green
  )
  local r, g, b, a = ns.rgb(c.gold, 0.5)
  check("rgb spreads a token with alpha", r == 1 and g == 0.82 and b == 0 and a == 0.5)
  r, g, b, a = ns.rgb(c.text)
  check("rgb without alpha", r == 1 and g == 1 and b == 1 and a == nil)
end

-- Chat.lua: the chat voice (colored prefix, no trailing period)
do
  local ns = loadCore()
  check("chat prefix color", ns.PREFIX_COLOR == "ff66ccff")
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

-- Sounds.lua: numeric IDs play through the same helper route
do
  local ns = loadCore()
  check("playID helper exists", type(ns.playID) == "function")
  if type(ns.playID) == "function" then
    local sounded = {}
    _G.PlaySound = function(id)
      sounded[#sounded + 1] = id
    end
    _G.SOUNDKIT = nil
    ns.playID(878)
    ns.playID("0")
    ns.playID("bogus")
    ns.playID(nil)
    check("playID plays numeric ids only", #sounded == 1 and sounded[1] == 878)
    _G.PlaySound = nil
    check("playID without an API is silent", pcall(ns.playID, 878) == true)
    _G.SOUNDKIT = nil
  end
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

-- Settings.lua BuildPage: slider, header, and choices rows
do
  local registered, created, headers = {}, {}, {}
  _G.Settings = {
    RegisterAddOnSetting = function(page, variable, key, tbl, vtype, label, default)
      local s = { page = page, key = key, vtype = vtype }
      s.SetValueChangedCallback = function(_, fn)
        s.callback = fn
      end
      registered[#registered + 1] = s
      return s
    end,
    CreateCheckbox = function(_, s, tooltip)
      created[#created + 1] = { kind = "checkbox", setting = s, tooltip = tooltip }
      return {}
    end,
    CreateSliderOptions = function(minValue, maxValue, step)
      return { minValue = minValue, maxValue = maxValue, step = step }
    end,
    CreateSlider = function(_, s, options, tooltip)
      created[#created + 1] = { kind = "slider", setting = s, options = options, tooltip = tooltip }
      return {}
    end,
    CreateDropdown = function(_, s, options, tooltip)
      created[#created + 1] = { kind = "dropdown", setting = s, options = options, tooltip = tooltip }
      return {}
    end,
    CreateControlTextContainer = function()
      local data = {}
      return {
        Add = function(_, v, label, tip)
          data[#data + 1] = { value = v, label = label, tooltip = tip }
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
          headers[#headers + 1] = init
        end,
      }
    end,
  }
  _G.CreateSettingsListSectionHeaderInitializer = function(text)
    return text
  end
  local buttons = {}
  _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, addSearchTags)
    local init = { name = name, buttonText = buttonText, tooltip = tooltip, addSearchTags = addSearchTags }
    function init.SetParentInitializer(_, parent, gate)
      init.parent, init.gate = parent, gate
    end
    buttons[#buttons + 1] = { init = init, click = onClick }
    return init
  end
  local ns = loadCore()
  ns.db = {}
  local changed = {}
  local built = ns.settings.BuildPage(
    {},
    "VocUI_demo_",
    ns.config.Section("demo", { enabled = true, level = 5, mode = "a" }),
    { enabled = true, level = 5, mode = "a" },
    {
      { key = "enabled", kind = "checkbox", label = "On", tooltip = "Toggle" },
      { kind = "header", label = "Group" },
      { key = "level", kind = "slider", label = "Level", tooltip = "How much", min = 1, max = 10, step = 2 },
      {
        key = "mode",
        kind = "dropdown",
        label = "Mode",
        tooltip = "Which",
        choices = {
          { value = "a", label = "Alpha", tooltip = "First" },
          { value = "b", label = "Beta", tooltip = "Second" },
        },
      },
      {
        kind = "button",
        label = "Survey bags",
        button = "Survey",
        tooltip = "List matches",
        action = "survey",
      },
    },
    function()
      return true
    end,
    function(key)
      changed[#changed + 1] = key
    end
  )
  check("page builds the checkbox, slider, dropdown, and button rows", built == 4)
  check(
    "section header adds a label and the button adds its control",
    #headers == 2 and headers[1] == "Group" and headers[2] == buttons[1].init and #registered == 3
  )
  local slider
  for _, c in ipairs(created) do
    if c.kind == "slider" then
      slider = c
    end
  end
  check(
    "slider carries the range, the step, and the tooltip",
    slider ~= nil
      and slider.options.minValue == 1
      and slider.options.maxValue == 10
      and slider.options.step == 2
      and slider.tooltip == "How much"
  )
  local dropdown
  for _, c in ipairs(created) do
    if c.kind == "dropdown" then
      dropdown = c
    end
  end
  local picked = dropdown ~= nil and dropdown.options() or {}
  check(
    "dropdown choices become the options",
    #picked == 2 and picked[1].value == "a" and picked[2].label == "Beta" and dropdown.tooltip == "Which"
  )
  check(
    "button carries its label, caption, tooltip, and search tags",
    #buttons == 1
      and buttons[1].init.name == "Survey bags"
      and buttons[1].init.buttonText == "Survey"
      and buttons[1].init.tooltip == "List matches"
      and buttons[1].init.addSearchTags == true
  )
  registered[1].callback()
  buttons[1].click()
  check("button presses call back with the action", changed[2] == "survey")
  check(
    "button rows gate on the toggle without storing anything",
    buttons[1].init.parent ~= nil and type(buttons[1].init.gate) == "function" and #registered == 3
  )
  check("row changes call back with the key", changed[1] == "enabled")
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer, _G.CreateSettingsButtonInitializer =
    nil, nil, nil, nil
end

-- Settings.lua Init: an unavailable module gets no page
do
  local builtPages, subcats = {}, {}
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
  }
  local ns = loadCore()
  ns.db = {}
  ns.modules.Register({
    name = "here",
    job = "x",
    init = function() end,
    IsAvailable = function()
      return true
    end,
    BuildPanel = function(page)
      builtPages[#builtPages + 1] = page
    end,
  })
  ns.modules.Register({
    name = "gone",
    job = "x",
    init = function() end,
    IsAvailable = function()
      return false
    end,
    BuildPanel = function(page)
      builtPages[#builtPages + 1] = page
    end,
  })
  ns.settings.Init()
  check("unavailable modules get no page", #subcats == 1 and subcats[1].name == "here" and #builtPages == 1)
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
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

-- Gear module: equip bag upgrades by item level. Item level decides
-- (Pawn has no Forever build); Pawn and Great Vault code does not exist.
local GEAR = {
  "modules/gear/Gear.lua",
  "modules/gear/Evaluate.lua",
  "modules/gear/Panel.lua",
  "modules/gear/Scan.lua",
  "modules/gear/Sheet.lua",
  "modules/gear/Plugins.lua",
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
    if type(row.key) == "string" then
      keys[row.key] = true
    end
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
  -- Best armor waits until 40: a pre-40 hunter refuses mail, a 50 wears it.
  addItem(w, "leatherworn", { equipLoc = "INVTYPE_CHEST", ilvl = 10, classID = 4, subclassID = 2 })
  addItem(w, "mailbag", { equipLoc = "INVTYPE_CHEST", ilvl = 99, classID = 4, subclassID = 3 })
  w.equipped[5] = "leatherworn"
  w.level = 30
  check("pre-40 best armor refused", gear.Evaluate("mailbag").upgrade == false)
  w.level = 50
  check("post-40 best armor passes", gear.Evaluate("mailbag").upgrade == true)
end

-- Gear evaluate: relics, thrown, and never-gear on the ranged slot
do
  local w = gearWorld()
  local ns = loadGear()
  ns.db = {}
  local gear = ns.gear
  -- Relics and thrown share the ranged slot (slot 18).
  check("relic home is the ranged slot", gear.HomeSlot("INVTYPE_RELIC") == 18)
  check("thrown home is the ranged slot", gear.HomeSlot("INVTYPE_THROWN") == 18)
  -- A paladin's libram upgrades; a hunter's does not.
  addItem(w, "libram", { equipLoc = "INVTYPE_RELIC", ilvl = 20, classID = 4, subclassID = 7 })
  addItem(w, "oldlibram", { equipLoc = "INVTYPE_RELIC", ilvl = 10, classID = 4, subclassID = 7 })
  w.classKey = "PALADIN"
  w.equipped[18] = "oldlibram"
  check("relic upgrades for its class", gear.Evaluate("libram").upgrade == true)
  w.classKey = "HUNTER"
  check("relic refused for other classes", gear.Evaluate("libram").upgrade == false)
  -- Thrown: a rogue's upgrade, a hunter's refusal.
  addItem(w, "axe", { equipLoc = "INVTYPE_THROWN", ilvl = 20, classID = 2, subclassID = 16 })
  addItem(w, "oldaxe", { equipLoc = "INVTYPE_THROWN", ilvl = 10, classID = 2, subclassID = 16 })
  w.equipped[18] = "oldaxe"
  w.classKey = "ROGUE"
  check("thrown upgrades for rogues", gear.Evaluate("axe").upgrade == true)
  w.classKey = "HUNTER"
  check("thrown refused for hunters", gear.Evaluate("axe").upgrade == false)
  -- Bags and ammo are never upgrades, and say so plainly.
  addItem(w, "bigbag", { equipLoc = "INVTYPE_BAG" })
  addItem(w, "ammo", { equipLoc = "INVTYPE_AMMO" })
  local bagEv = gear.Evaluate("bigbag")
  check("bags never upgrade", bagEv ~= nil and bagEv.upgrade == false)
  local ammoEv = gear.Evaluate("ammo")
  check("ammo never upgrades", ammoEv ~= nil and ammoEv.upgrade == false)
  check("bags explain themselves", gear.WhyNot("bigbag", { upgrade = false }):find("bag", 1, true) ~= nil)
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

-- Gear as a Baganator upgrade plugin: our verdicts badge the bags.
do
  local w = gearWorld()
  local ns = loadGear()
  ns.db = {}
  local gear = ns.gear
  addItem(w, "oldchest", { equipLoc = "INVTYPE_CHEST", ilvl = 10, classID = 4, subclassID = 1 })
  addItem(w, "newchest", { equipLoc = "INVTYPE_CHEST", ilvl = 15, classID = 4, subclassID = 1 })
  w.equipped[5] = "oldchest"
  ns.modules.InitAll()
  check("an upgrade badges true", gear.UpgradeForBaganator("newchest") == true)
  check("a lateral badges false", gear.UpgradeForBaganator("oldchest") == false)
  check("an unknown link badges nil", gear.UpgradeForBaganator("mystery") == nil)
  check("junk input badges nil", gear.UpgradeForBaganator(nil) == nil)
  gear.opts().enabled = false
  check("a disabled module badges nil", gear.UpgradeForBaganator("newchest") == nil)
  gear.opts().enabled = true
  local seen = {}
  local function stubBaganator()
    _G.Baganator = {
      API = {
        RegisterUpgradePlugin = function(label, id, fn)
          seen = { label = label, id = id, fn = fn }
        end,
      },
    }
  end
  _G.C_AddOns = {
    IsAddOnLoaded = function(name)
      return name == "Baganator"
    end,
  }
  stubBaganator()
  gear.RegisterBaganatorPlugin()
  check("a loaded Baganator registers now", seen.id == "vocui-gear" and seen.label == "VocUI Gear")
  check("the registered callback is the verdict", seen.fn("newchest") == true)
  _G.C_AddOns = {
    IsAddOnLoaded = function()
      return false
    end,
  }
  _G.Baganator = nil
  seen = {}
  gear.RegisterBaganatorPlugin()
  check("an absent Baganator registers nothing yet", seen.id == nil)
  stubBaganator()
  for _, frame in ipairs(mock.frames) do
    if frame.scripts.OnEvent and frame.events.ADDON_LOADED then
      pcall(frame.scripts.OnEvent, frame, "ADDON_LOADED", "Baganator")
    end
  end
  check("the guest load registers later", seen.id == "vocui-gear" and seen.fn("newchest") == true)
  _G.Baganator, _G.C_AddOns = nil, nil
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
  local equipRow
  for _, row in ipairs(gear.OPTIONS) do
    if row.key == "equipSound" then
      equipRow = row
    end
  end
  check(
    "equip sound row declares its choices as data",
    equipRow ~= nil and equipRow.choices ~= nil and #equipRow.choices == 4 and equipRow.choices[1].value == "0"
  )
  check(
    "gear groups its rows under headers",
    w.headers[3] == "Announcements"
      and w.headers[4] == "Equipping"
      and w.headers[5] == "Feedback"
      and w.headers[6] == "Character sheet"
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

-- Shared combat, guest, and bag-walk helpers: one definition in core,
-- every module delegates instead of rebuilding.
do
  local ns = loadCore()
  check("combat helper exists", type(ns.combat) == "function")
  check("guest helper exists", type(ns.guests) == "table" and type(ns.guests.IsLoaded) == "function")
  check(
    "bag walker exists",
    type(ns.inventory.EachSlot) == "function" and type(ns.settings.BuildModulePage) == "function"
  )
end

-- Combat reads the client, not just the UI: on pull frames the unit
-- already fights while the lockdown still reads clear.
do
  local ns = loadCore()
  _G.InCombatLockdown = function()
    return true
  end
  _G.UnitAffectingCombat = nil
  check("lockdown reads busy", ns.combat() == true)
  _G.InCombatLockdown = function()
    return false
  end
  _G.UnitAffectingCombat = function()
    return true
  end
  check("pull frames read busy", ns.combat() == true)
  _G.UnitAffectingCombat = function()
    return false
  end
  check("peace reads clear", ns.combat() == false)
  _G.InCombatLockdown, _G.UnitAffectingCombat = nil, nil
  check("missing api never reads busy", ns.combat() == false)
end

-- Guest presence: loaded addons read loaded, anything else does not.
do
  local ns = loadCore()
  _G.C_AddOns = {
    IsAddOnLoaded = function(name)
      return name == "There"
    end,
  }
  check("loaded guests read loaded", ns.guests.IsLoaded("There") == true)
  check("absent guests read clear", ns.guests.IsLoaded("Away") == false)
  check("junk names read clear", ns.guests.IsLoaded(nil) == false)
  _G.C_AddOns = nil
  check("missing api never reads loaded", ns.guests.IsLoaded("There") == false)
end

-- Guests.WhenLoaded: now when loaded, later on ADDON_LOADED, never an error.
do
  local ns = loadCore()
  local ran = {}
  _G.C_AddOns = {
    IsAddOnLoaded = function(name)
      return name == "There"
    end,
  }
  check("loaded guests run now", ns.guests.WhenLoaded("There", function()
    ran[#ran + 1] = "now"
  end) == true and ran[1] == "now")
  check(
    "bad arguments decline",
    ns.guests.WhenLoaded(nil, function() end) == false and ns.guests.WhenLoaded("There", nil) == false
  )
  check("a throwing guest never propagates", ns.guests.WhenLoaded("There", function()
    error("boom")
  end) == true)
  check("absent guests defer", ns.guests.WhenLoaded("Away", function()
    ran[#ran + 1] = "later"
  end) == true and #ran == 1)
  local function fire(name)
    for _, frame in ipairs(mock.frames) do
      if frame.scripts.OnEvent and frame.events.ADDON_LOADED then
        frame.scripts.OnEvent(frame, "ADDON_LOADED", name)
      end
    end
  end
  fire("Other")
  check("other addons fire nothing", #ran == 1)
  fire("Away")
  check("the guest load runs the waiter", ran[2] == "later")
  fire("Away")
  check("a load fires once", #ran == 2)
  _G.C_AddOns = nil
  local fresh = loadCore()
  local savedFrame = _G.CreateFrame
  _G.CreateFrame = nil
  check("missing frame api declines", fresh.guests.WhenLoaded("Away", function() end) == false)
  _G.CreateFrame = savedFrame
end

-- The fallback bag walk: every readable slot once, early stop honored.
do
  local ns = loadCore()
  local seen = {}
  _G.NUM_BAG_SLOTS = 1
  _G.C_Container = {
    GetContainerNumSlots = function(bag)
      return bag == 0 and 2 or 1
    end,
    GetContainerItemInfo = function(bag, slot)
      if bag == 1 then
        error("broken slot")
      end
      return { quality = 0, hyperlink = "s" .. bag .. slot }
    end,
    GetContainerItemLink = function()
      return nil
    end,
  }
  ns.inventory.EachSlot(function(bag, slot, info, link)
    seen[#seen + 1] = bag .. slot .. (info and info.hyperlink or "-") .. (link or "-")
  end)
  check("walk reads every slot once", table.concat(seen, ",") == "01s01s01,02s02s02")
  check("broken slots yield nothing", #seen == 2)
  local stopped = 0
  ns.inventory.EachSlot(function()
    stopped = stopped + 1
    return true
  end)
  check("early stop ends the walk", stopped == 1)
  _G.C_Container = nil
  check("missing containers walk nowhere", ns.inventory.EachSlot(function()
    return true
  end) == nil)
  _G.NUM_BAG_SLOTS = nil
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

-- Gear: the equip sound resolves SOUNDKIT names first, numeric behind
do
  gearWorld()
  local ns = loadGear()
  ns.db = {}
  local gear = ns.gear
  local played = {}
  _G.PlaySound = function(id)
    played[#played + 1] = id
  end
  _G.SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 9999 }
  gear.opts().equipSound = "878"
  gear.playEquipSound()
  check("equip sound prefers the SOUNDKIT name", played[1] == 9999)
  _G.SOUNDKIT = nil
  gear.playEquipSound()
  check("equip sound falls back to the numeric id", played[2] == 878)
  gear.opts().equipSound = "0"
  gear.playEquipSound()
  check("equip sound off is silent", #played == 2)
  _G.PlaySound = nil
  check("equip sound without an API is silent", pcall(gear.playEquipSound) == true)
  _G.SOUNDKIT = nil
end

-- Gear sheet: the button honors the module toggle, and its tooltip
-- warns when equips cannot run right now
do
  local w = gearWorld()
  local ns = loadGear()
  ns.db = {}
  ns.modules.InitAll()
  local gear = ns.gear
  ns.say = function() end
  ns.play = function() end
  gear.EnsureSheetImpl()
  check("check bags shows while gear is on", gear.sheetButton ~= nil and gear.sheetButton.shown == true)
  gear.SetEnabled(false)
  check("disabling gear hides check bags", gear.sheetButton.shown == false)
  gear.SetEnabled(true)
  check("re-enabling gear shows check bags", gear.sheetButton.shown == true)
  local tip = { lines = {} }
  _G.GameTooltip = {
    SetOwner = function() end,
    SetText = function(_, t, r, g)
      tip.title = t
      tip.color = { r, g }
    end,
    AddLine = function(_, t, r)
      tip.lines[#tip.lines + 1] = { text = t, red = (r == 0.9) }
    end,
    Show = function()
      tip.shown = true
    end,
    Hide = function() end,
  }
  w.combat = false
  gear.sheetButton.scripts.OnEnter(gear.sheetButton)
  local calm = true
  for _, line in ipairs(tip.lines) do
    if line.red then
      calm = false
    end
  end
  check(
    "sheet tooltip names check bags in gold",
    tip.title == "Check Bags" and tip.color[1] == 1 and tip.color[2] == 0.82
  )
  check("sheet tooltip stays quiet out of combat", calm == true)
  w.combat = true
  tip.lines = {}
  gear.sheetButton.scripts.OnEnter(gear.sheetButton)
  local warned = false
  for _, line in ipairs(tip.lines) do
    if line.red and line.text:find("combat", 1, true) then
      warned = true
    end
  end
  check("sheet tooltip warns in combat", warned == true)
  _G.GameTooltip = nil
end

-- XP module: the leveling readout. Rate and reputation
-- math, rested and quest overlays, War Mode and aura detection without
-- Forever suggestions, and no Regalia (retail-only, never on Forever).
local XP = {
  "modules/xp/XP.lua",
  "modules/xp/Bar.lua",
  "modules/xp/Bonuses.lua",
  "modules/xp/Modes.lua",
  "modules/xp/Panel.lua",
  "modules/xp/Rate.lua",
  "modules/xp/Rep.lua",
}
local function loadXP()
  local ns = loadCore()
  for _, file in ipairs(XP) do
    assert(loadfile(file))("VocUI", ns)
  end
  return ns
end

-- A stub world for xp tests: leveling snapshot reads, a monotonic
-- clock, and no optional APIs unless a block installs them.
local function xpWorld()
  local w = { time = 1000, combat = false }
  _G.UnitXP = function()
    return 400
  end
  _G.UnitXPMax = function()
    return 1000
  end
  _G.UnitLevel = function()
    return 10
  end
  _G.UnitGUID = function()
    return "p1"
  end
  _G.GetTime = function()
    return w.time
  end
  _G.InCombatLockdown = function()
    return w.combat
  end
  _G.UIParent = {}
  _G.C_Timer, _G.C_AddOns, _G.C_QuestLog, _G.C_Reputation, _G.C_MajorFactions = nil, nil, nil, nil, nil
  _G.C_GossipInfo, _G.C_PvP, _G.C_UnitAuras = nil, nil, nil
  _G.GetXPExhaustion, _G.IsXPUserDisabled, _G.IsInInstance = nil, nil, nil
  _G.GetQuestLogRewardXP = nil
  _G.GetMaxLevelForLatestExpansion, _G.GetMaxLevelForPlayerExpansion = nil, nil
  _G.GetMaxPlayerLevel, _G.PlayerIsTimerunning, _G.IsTrialAccount = nil, nil, nil
  _G.StatusTrackingBarManager = nil
  _G.STATUS_BAR_CONTAINER_WIDTH, _G.STATUS_BAR_NUM_SEGMENTS = nil, nil
  _G.STATUS_BAR_SIZE_ADJUSTMENT, _G.EXHAUSTION_TICK_OFFSET_Y = nil, nil
  _G.MAX_REPUTATION_REACTION = nil
  _G.EventRegistry = nil
  _G.GameTooltip = nil
  return w
end

-- XP: descriptor, state location, Forever-only options
do
  xpWorld()
  local ns = loadXP()
  ns.db = {}
  local xp = ns.xp
  ns.modules.InitAll()
  check(
    "xp descriptor registered",
    ns.modules.GetAll()[1] == xp.descriptor and xp.descriptor.name == "xp" and xp.descriptor.default == true
  )
  check(
    "xp state lives under modules.xp",
    type(ns.db.modules) == "table" and ns.db.modules.xp.enabled == true and ns.db.xp == nil
  )
  local keys = {}
  for _, row in ipairs(xp.OPTIONS) do
    if type(row.key) == "string" then
      keys[row.key] = true
    end
  end
  check(
    "xp options present",
    keys.enabled and keys.announce and keys.hideDefault and keys.repMode and keys.followLatest and keys.locked
  )
  check("retail regalia never crossed over", xp.regaliaPieces == nil and xp.regaliaReduction == nil)
  check("no flavor detection on a forever-only package", xp.clientFlavor == nil)
  check(
    "xp help lines keep config second to last",
    ns.HELP[#ns.HELP - 1]:find("config", 1, true) ~= nil and ns.HELP[3]:find("/vui xp", 1, true) ~= nil
  )
  _G.UnitXP, _G.UnitXPMax, _G.UnitLevel = nil, nil, nil
  check("unavailable xp stays hidden", xp.IsAvailable() == false)
end

-- XP rate math: tracker windows, gains, estimate statuses
do
  xpWorld()
  local ns = loadXP()
  local xp = ns.xp
  local tr = xp.newTracker(0)
  check("fresh tracker is empty", tr.sum == 0 and tr.head == 1)
  check("zero and negative awards never count", xp.addAward(tr, 10, 0) == false and xp.addAward(tr, 10, -5) == false)
  xp.addAward(tr, 10, 100)
  xp.addAward(tr, 20, 100)
  local snap = { level = 10, xp = 0, req = 1000, capped = false }
  local est = xp.estimate(tr, 20, snap, false)
  check("early observation is collecting", est.status == "collecting" and est.xpPerHour == 200 / 20 * 3600)
  est = xp.estimate(tr, 200, snap, false)
  check("partial window is warming up", est.status == "warming-up")
  est = xp.estimate(tr, 700, snap, false)
  check("expired awards leave the window", est.windowXp == 0 and est.status == "no-recent-xp")
  local tr2 = xp.newTracker(0)
  xp.addAward(tr2, 650, 100)
  est = xp.estimate(tr2, 700, snap, false)
  check("full window with earnings is ready", est.status == "ready" and est.etaSeconds == 1000 * 600 / 100)
  local tr3 = xp.newTracker(0)
  xp.addAward(tr3, 101, 100)
  est = xp.estimate(tr3, 700, snap, false)
  check("a quiet full window is idle", est.status == "idle")
  check("paused never estimates", xp.estimate(tr2, 700, snap, true).status == "paused")
  check(
    "capped never estimates",
    xp.estimate(tr2, 700, { level = 60, xp = 0, req = 1, capped = true }, false).status == "capped"
  )
  check("junk snapshots are unavailable", xp.estimate(tr2, 700, nil, false).status == "unavailable")
  local done = { level = 10, xp = 1000, req = 1000, capped = false }
  local doneEst = xp.estimate(tr2, 700, done, false)
  check("a full bar awaits the level update", doneEst.status == "awaiting-level-update" and doneEst.etaSeconds == 0)
  check(
    "gains reconstruct across snapshots",
    xp.gain({ level = 10, xp = 900, req = 1000, capped = false }, { level = 10, xp = 950, req = 1000, capped = false })
      == 50
  )
  check(
    "gains carry across one ding",
    xp.gain({ level = 10, xp = 900, req = 1000, capped = false }, { level = 11, xp = 100, req = 2000, capped = false })
      == 200
  )
  check(
    "losses and jumps resync",
    xp.gain({ level = 10, xp = 900, req = 1000, capped = false }, { level = 10, xp = 100, req = 1000, capped = false })
        == nil
      and xp.gain(
          { level = 10, xp = 900, req = 1000, capped = false },
          { level = 12, xp = 100, req = 1000, capped = false }
        )
        == nil
  )
  check("longer memory steadies the forecast", xp.etaSeconds(tr2, 700, 500) == 500 * 600 / 100)
  check("empty memory forecasts nothing", xp.etaSeconds(xp.newTracker(700), 700, 500) == nil)
  tr2.events = { { time = 1, amount = 1 }, { time = 2, amount = 2 }, { time = 650, amount = 100 } }
  tr2.head = 3
  tr2.sum = 100
  xp.compact(tr2)
  check("compaction drops dead slots", tr2.head == 1 and #tr2.events == 1 and tr2.sum == 100)
end

-- XP text: titles, subtitles, segments, labels, summaries
do
  xpWorld()
  local ns = loadXP()
  local xp = ns.xp
  local ready = { status = "ready", xpPerHour = 144000, etaSeconds = 1500, windowSeconds = 600 }
  check("title reads rate and eta", xp.titleText(ready) == "144k XP/hr · 25m")
  ready.unit = "Rep"
  check("rep titles speak rep", xp.titleText(ready) == "144k Rep/hr · 25m")
  ready.unit = nil
  ready.etaSeconds = nil
  check("title without eta reads pace alone", xp.titleText(ready) == "144k XP/hr")
  check("collecting title admits it", xp.titleText({ status = "collecting" }) == "Collecting data")
  check("reps at cap name the rank", xp.titleText({ status = "rep-capped", capLabel = "Exalted" }) == "Exalted")
  check(
    "subtitles name the span",
    xp.subText({ status = "ready", windowSeconds = 600 }) == "Last 10m"
      and xp.subText({ status = "warming-up", observedSeconds = 180, windowSeconds = 600 }) == "Warming up · last 3m of 10m"
      and xp.subText({ status = "idle", idleSeconds = 120, windowSeconds = 600 }) == "Idle 2m · last 10m"
      and xp.subText({ status = "collecting" }) == "Collecting data"
      and xp.subText({ status = "no-recent-xp", windowSeconds = 600 }) == "No XP in the last 10m"
  )
  local seg = xp.barSegments({ level = 10, xp = 400, req = 1000, capped = false }, 200, 100)
  check(
    "overlays stack in play order",
    seg.progress == 0.4 and seg.questEnd == 0.5 and seg.restedEnd == 0.7 and seg.questPct == 10
  )
  check("capped snapshots have no bar", xp.barSegments({ level = 60, xp = 0, req = 1, capped = true }, 0, 0) == nil)
  local full = xp.barSegments({ level = 10, xp = 900, req = 1000, capped = false }, 300, 0)
  check(
    "rested overflow clamps but flags",
    full.restedEnd == 1 and full.restedOverflow == true and seg.restedOverflow == false
  )
  check(
    "bar label reads level and percent",
    xp.barLabel({ level = 10, xp = 400, req = 1000 }, seg) == "10  400/1k (40%)"
  )
  check("stats line names quests and rested", xp.subStatsLine(seg, 2) == "2 quests ready: 10% · Rested: 20%")
  check("stats line hides when neither shows", xp.subStatsLine(seg, 0) == "Rested: 20%")
  local acc = xp.newSummary()
  check("single gains stay silent", xp.formatSummary(acc) == nil)
  acc = xp.noteSummaryGain(acc, 1000, "xp", nil, nil, 200, false)
  check("one gain still stays silent", xp.formatSummary(acc) == nil)
  acc = xp.noteSummaryGain(acc, 1000.05, "xp", nil, nil, 100, false)
  check("bursts net to one line", xp.formatSummary(acc) == "+300 XP")
  local racc = xp.newSummary()
  racc = xp.noteSummaryGain(racc, 1000, "rep", 1, "Stormwind", 200, false)
  racc = xp.noteSummaryGain(racc, 1000.05, "rep", 2, "Orgrimmar", 100, false)
  check("rep bursts name every faction", xp.formatSummary(racc) == "+300 rep (Stormwind 200, Orgrimmar 100)")
  local qacc = xp.newSummary()
  qacc = xp.noteSummaryGain(qacc, 1000, "rep", 1, "Stormwind", 100, false)
  qacc = xp.noteSummaryGain(qacc, 1000.2, "rep", 1, "Stormwind", 100, false)
  check("quiet spells split bursts", qacc.count == 1)
  local bacc = xp.newSummary()
  bacc = xp.noteSummaryGain(bacc, 1000, "xp", nil, nil, 100, true)
  bacc = xp.noteSummaryGain(bacc, 1000.05, "xp", nil, nil, 100, true)
  check("combat holds the burst open", bacc.count == 2 and xp.formatSummary(bacc) == "+200 XP in combat")
end

-- XP reputation math: every faction kind normalizes to one shape
do
  xpWorld()
  local ns = loadXP()
  local xp = ns.xp
  check(
    "only real factions track",
    xp.validRepRow({ factionID = 1, name = "A" }) == true
      and xp.validRepRow({ factionID = 0, name = "A" }) == false
      and xp.validRepRow({ factionID = 1, name = "A", isHeader = true }) == false
      and xp.validRepRow({ factionID = 1, name = "A", isHeader = true, isHeaderWithRep = true }) == true
  )
  local std = {
    factionID = 1,
    name = "A",
    reaction = 5,
    currentReactionThreshold = 3000,
    nextReactionThreshold = 9000,
    currentStanding = 6000,
  }
  local standing = xp.repStandardProgress(std)
  check("standard progress reads in-rank", standing.have == 3000 and standing.need == 6000 and standing.capped == false)
  check("rank labels read friendly", xp.repBarLabel(standing) == "A  3k/6k (50%)")
  check(
    "rank context names the next rank",
    xp.repStatsLine(standing) == "Friendly · 50% to Honored" and xp.standingName(8) == "Exalted"
  )
  local cap = {
    factionID = 1,
    name = "A",
    reaction = 8,
    currentReactionThreshold = 0,
    nextReactionThreshold = 0,
    currentStanding = 999,
  }
  check("exalted caps the bar", xp.repStandardProgress(cap).capped == true)
  local ren = xp.repRenownProgress(
    { factionID = 2, name = "B", currentStanding = 1500 },
    { renownLevel = 7, renownLevelThreshold = 2500 },
    false
  )
  check("renown reads the live standing", ren.have == 1500 and ren.need == 2500 and ren.levelLabel == "Renown 7")
  check("renown blues the fill", xp.repAtlas(ren) == xp.REP_FILL_BLUE)
  local par = xp.repParagonProgress({ factionID = 3, name = "C" }, 12500, 10000, false)
  check("paragon wraps the cycle", par.have == 2500 and par.need == 10000 and par.capped == false)
  local pen = xp.repParagonProgress({ factionID = 3, name = "C" }, 12500, 10000, true)
  check("pending rewards pin the bar full", pen.have == 10000 and pen.pending == true)
  local fr = xp.repFriendshipProgress(
    { factionID = 4, name = "D" },
    { reaction = "Friend", standing = 5000, reactionThreshold = 0, nextThreshold = 8400 },
    { currentLevel = 3 }
  )
  check("friendship reads between ranks", fr.have == 5000 and fr.need == 8400 and fr.capped == false)
  local frMax = xp.repFriendshipProgress(
    { factionID = 4, name = "D" },
    { reaction = "Best Friend", standing = 9999 },
    { currentLevel = 6 }
  )
  check("max friendship caps", frMax.capped == true)
  check(
    "same-kind gains are exact",
    xp.repGain(
      { id = 1, kind = "standing", level = 5, have = 3000, need = 6000, capped = false },
      { id = 1, kind = "standing", level = 5, have = 4000, need = 6000, capped = false }
    ) == 1000
  )
  check(
    "rank-ups carry the remainder",
    xp.repGain(
      { id = 1, kind = "standing", level = 5, have = 5000, need = 6000, capped = false },
      { id = 1, kind = "standing", level = 6, have = 1000, need = 12000, capped = false }
    ) == 2000
  )
  check(
    "losses and swaps resync",
    xp.repGain(
      { id = 1, kind = "standing", level = 5, have = 5000, need = 6000, capped = false },
      { id = 1, kind = "standing", level = 5, have = 1000, need = 6000, capped = false }
    )
        == nil
      and xp.repGain(
          { id = 1, kind = "standing", level = 5, have = 5000, need = 6000, capped = false },
          { id = 2, kind = "standing", level = 5, have = 5000, need = 6000, capped = false }
        )
        == nil
  )
  check(
    "paragon gains read lifetime deltas",
    xp.repGain(
      { id = 3, kind = "paragon", raw = 10000, capped = false },
      { id = 3, kind = "paragon", raw = 10250, capped = false }
    ) == 250
  )
  check("wild reactions read friendly", xp.repAtlas({ kind = "standing", level = 99 }) == xp.REP_FILL[5])
  check("reaction ceiling falls back to eight", xp.maxRepReaction() == 8)
  _G.MAX_REPUTATION_REACTION = 10
  check("reaction ceiling reads the client", xp.maxRepReaction() == 10)
  _G.MAX_REPUTATION_REACTION = nil
  check("unknown reactions name the rank", xp.standingName(99) == "Rank 99")
end

-- XP quest scan: ready turn-ins sum, selection restores, gaps degrade
do
  xpWorld()
  local selected = 100
  _G.C_QuestLog = {
    GetNumQuestLogEntries = function()
      return 3
    end,
    GetInfo = function(i)
      return { questID = 100 + i, isHeader = false }
    end,
    ReadyForTurnIn = function(id)
      return id == 102
    end,
    GetSelectedQuest = function()
      return selected
    end,
    SetSelectedQuest = function(id)
      selected = id
    end,
  }
  _G.GetQuestLogRewardXP = function()
    return 500
  end
  local ns = loadXP()
  local xp = ns.xp
  local total, count = xp.scanQuestXp()
  check("ready quests sum their rewards", total == 500 and count == 1 and selected == 100)
  _G.C_QuestLog.GetInfo = function()
    return nil
  end
  total, count = xp.scanQuestXp()
  check("unreadable logs overlay nothing", total == 0 and count == 0)
  _G.C_QuestLog, _G.GetQuestLogRewardXP = nil, nil
  total, count = xp.scanQuestXp()
  check("missing quest api overlays nothing", total == 0 and count == 0)
end

-- XP snapshots and cap detection mirror the client's own rules
do
  xpWorld()
  local ns = loadXP()
  local xp = ns.xp
  local snap = xp.readSnapshot()
  check("leveling snapshots read live", snap.level == 10 and snap.xp == 400 and snap.req == 1000)
  _G.GetMaxPlayerLevel = function()
    return 60
  end
  check("per-player max caps the bar", xp.isLevelCapped(60, 100000) == true)
  _G.GetMaxLevelForLatestExpansion = function()
    return 70
  end
  _G.GetMaxLevelForPlayerExpansion = function()
    return 60
  end
  check("expansion max wins below the latest", xp.effectiveMaxLevel() == 60)
  _G.PlayerIsTimerunning = function()
    return true
  end
  check("timerunning compares against the latest", xp.effectiveMaxLevel() == 60)
  _G.GetMaxPlayerLevel, _G.GetMaxLevelForLatestExpansion = nil, nil
  _G.GetMaxLevelForPlayerExpansion, _G.PlayerIsTimerunning = nil, nil
  _G.GetXPExhaustion = function()
    return 200
  end
  check("rested reads the exhaustion value", xp.restedAmount() == 200)
  _G.IsXPUserDisabled = function()
    return true
  end
  check("disabled xp hides rested", xp.restedAmount() == nil)
  _G.GetXPExhaustion, _G.IsXPUserDisabled = nil, nil
end

-- XP bonuses: the registry reports its active and missing halves; rested
-- and quest reach stay on the bar, never in the section
do
  xpWorld()
  local ns = loadXP()
  local xp = ns.xp
  check(
    "registry holds the verified food buff",
    #xp.REGISTRY == 1
      and xp.REGISTRY[1].aura == 24870
      and xp.REGISTRY[1].name == "Well Fed"
      and xp.REGISTRY[1].food == true
  )
  check("no apis means no active lines", #xp.bonusParts("xp") == 0)
  local missing = xp.missingParts("xp")
  check("missing names the source without a bag read", #missing == 1 and missing[1] == "Well Fed · kill XP (eat food)")
  check("rep side keeps its own list", xp.bonusParts("rep", true)[1] == "Bonus rep gain")
  _G.GetXPExhaustion = function()
    return 100
  end
  check("rested stays on the bar, not in the section", #xp.bonusParts("xp") == 0 and #xp.missingParts("xp") == 1)
  _G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
      if id == 24870 then
        return { expirationTime = 2500 }
      end
      return nil
    end,
  }
  local buffs = xp.bonusParts("xp")
  check(
    "active shows with its remaining time",
    buffs[1] == "Well Fed · kill XP (25m left)" and #xp.missingParts("xp") == 0
  )
  _G.C_UnitAuras.GetPlayerAuraBySpellID = function(id)
    if id == 24870 then
      return {}
    end
    return nil
  end
  check("active without a clock reads no time", xp.bonusParts("xp")[1] == "Well Fed · kill XP")
  _G.C_UnitAuras.GetPlayerAuraBySpellID = function(id)
    if id == 24870 then
      return { expirationTime = 2500 }
    end
    return nil
  end
  _G.canaccessvalue = function()
    return false
  end
  check("secret stamps read no time, never an error", xp.auraTimeLeft(24870) == nil)
  _G.canaccessvalue = function()
    return true
  end
  check("allowed stamps keep their time", xp.auraTimeLeft(24870) == 1500)
  _G.canaccessvalue = nil
  check("no guard keeps the old read", xp.auraTimeLeft(24870) == 1500)
  -- Any food's Well Fed answers to the name, not just the one spell ID:
  -- the ID read is blind here, the name read sees the buff.
  _G.C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
      return nil
    end,
    GetAuraDataBySpellName = function(unit, spellName)
      if unit == "player" and spellName == "Well Fed" then
        return { expirationTime = 2500 }
      end
      return nil
    end,
  }
  local named = xp.bonusParts("xp")
  check(
    "a different food's Well Fed still shows",
    named[1] == "Well Fed · kill XP (25m left)" and #xp.missingParts("xp") == 0
  )
  _G.IsInInstance = function()
    return true
  end
  check(
    "instances gate aura reads",
    #xp.bonusParts("xp") == 0 and xp.missingParts("xp")[1] == "Aura scan unavailable in instances"
  )
  _G.C_PvP, _G.C_UnitAuras, _G.IsInInstance, _G.GetXPExhaustion = nil, nil, nil, nil
end

-- XP bag hints: food in the bags flips the missing line; without a read
-- the section still works and the hint stays off
do
  xpWorld()
  local ns = loadXP()
  local xp = ns.xp
  check("no bag read means no hint", xp.missingParts("xp")[1] == "Well Fed · kill XP (eat food)")
  _G.C_Item = {
    GetItemInfoInstant = function(link)
      if link == "food" then
        return 1, "Consumable", "Food & Drink", "", 1, 0, 5
      end
      return 2, "Armor", "Cloth", "", 2, 4, 1
    end,
  }
  ns.inventory.BagLinks = function()
    return { "food", "notfood" }
  end
  check("food in bags flips the hint", xp.missingParts("xp")[1] == "Well Fed · kill XP (food in bags)")
  check("bags change nothing active", #xp.bonusParts("xp") == 0)
  ns.inventory.BagLinks = function()
    return { "notfood" }
  end
  check("bags without food keep the plain reminder", xp.missingParts("xp")[1] == "Well Fed · kill XP (eat food)")
  ns.inventory.BagLinks = function()
    return nil
  end
  ns.inventory.EachSlot = function(fn)
    fn(0, 1, {}, "food")
  end
  check("the core walk backs the guest cache", xp.missingParts("xp")[1] == "Well Fed · kill XP (food in bags)")
  _G.C_Item = nil
  check("no item api means no hint, never an error", xp.missingParts("xp")[1] == "Well Fed · kill XP (eat food)")
end

-- XP slash and toggle: every subcommand sounds and says, typos help
do
  xpWorld()
  local ns = loadXP()
  ns.db = {}
  ns.modules.InitAll()
  local xp, said, played = ns.xp, {}, {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function(kind)
    played[#played + 1] = kind
  end
  _G.SlashCmdList.VOCUI("xp off")
  check("slash turns the module off with sound", xp.opts().enabled == false and played[#played] == "off")
  _G.SlashCmdList.VOCUI("xp on")
  check("slash turns the module on with sound", xp.opts().enabled == true and played[#played] == "on")
  _G.SlashCmdList.VOCUI("xp lock")
  check("slash locks the bar", xp.opts().locked == true and said[#said] == "locked")
  _G.SlashCmdList.VOCUI("xp pause")
  check("slash pauses tracking", said[#said] == "paused")
  _G.SlashCmdList.VOCUI("xp pause")
  check("slash resumes tracking", said[#said] == "resumed")
  _G.SlashCmdList.VOCUI("xp reset")
  check("slash restarts the session", said[#said] == "session reset")
  _G.SlashCmdList.VOCUI("xp rep")
  check("slash toggles reputation", xp.opts().repMode == false and said[#said] == "reputation tracking off")
  local before = #played
  _G.SlashCmdList.VOCUI("xp bogus")
  check("unknown xp subcommand only prints help", xp.opts().enabled == true and #played == before)
  _G.SlashCmdList.VOCUI("xp")
  check("bare xp toggles the bar", xp.opts().enabled == false)
end

-- XP panel: a subcategory under VocUI, Forever rows only, live callbacks
do
  xpWorld()
  local registered, subcats = {}, {}
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
    CreateCheckbox = function()
      return {}
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
  local ns = loadXP()
  ns.db = {}
  ns.modules.InitAll()
  ns.settings.Init()
  local xp = ns.xp
  check("xp page is a subcategory under VocUI", #subcats == 1 and subcats[1].name == "XP")
  check("panel rows bind to the subcategory", registered[1].page == subcats[1])
  local keys = {}
  for _, s in ipairs(registered) do
    keys[#keys + 1] = s.key
  end
  check(
    "panel registers the rows in order",
    table.concat(keys, ",") == "enabled,announce,hideDefault,repMode,followLatest,locked"
  )
  check(
    "panel leads with the job and the window",
    headers[1] == xp.descriptor.job and headers[2] == "Rate window: trailing 10 minutes, forecast 15"
  )
  check(
    "xp groups its rows under headers",
    headers[3] == "Display" and headers[4] == "Reputation" and headers[5] == "Position"
  )
  local enabledSetting
  for _, s in ipairs(registered) do
    if s.key == "enabled" then
      enabledSetting = s
    end
  end
  ns.db.modules.xp.enabled = false
  enabledSetting.callback("enabled")
  check("panel toggle applies live", xp.frame.events.PLAYER_XP_UPDATE == nil)
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
end

-- XP modes: entering the world seats the bar, cap pivots to rep
do
  xpWorld()
  local ns = loadXP()
  ns.db = {}
  local said = {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function() end
  ns.modules.InitAll()
  local xp = ns.xp
  check("init listens for the world", xp.frame.events.PLAYER_ENTERING_WORLD ~= nil)
  xp.frame.scripts.OnEvent(xp.frame, "PLAYER_ENTERING_WORLD")
  check("entering seats the bar", xp.frame.points ~= nil and xp.frame.shown == true)
  check("first sighting teaches the default bar", said[1] == nil or said[1]:find("default XP bar", 1, true) ~= nil)
  check("unavailable tracker stays untracked", xp.repTracked() == nil)
  xp.SetEnabled(false)
  check(
    "toggle off unregisters and hides",
    xp.frame.events.PLAYER_XP_UPDATE == nil and xp.frame.events.PLAYER_LEVEL_UP == nil and xp.frame.shown == false
  )
  xp.SetEnabled(true)
  check(
    "toggle on restores the bar without level-ups",
    xp.frame.events.PLAYER_XP_UPDATE ~= nil and xp.frame.events.PLAYER_LEVEL_UP == nil
  )
end

-- XP at cap: reputation takes the bar, latest gains resolve
do
  xpWorld()
  _G.GetMaxPlayerLevel = function()
    return 10
  end
  _G.C_Reputation = {
    GetWatchedFactionData = function()
      return {
        factionID = 7,
        name = "G",
        reaction = 5,
        currentReactionThreshold = 0,
        nextReactionThreshold = 6000,
        currentStanding = 3000,
      }
    end,
    GetFactionDataByID = function()
      return {
        factionID = 7,
        name = "G",
        reaction = 5,
        currentReactionThreshold = 0,
        nextReactionThreshold = 6000,
        currentStanding = 3000,
      }
    end,
    IsFactionParagonForCurrentPlayer = function()
      return false
    end,
    IsMajorFaction = function()
      return false
    end,
  }
  local ns = loadXP()
  ns.db = {}
  ns.say = function() end
  ns.play = function() end
  ns.modules.InitAll()
  local xp = ns.xp
  xp.frame.scripts.OnEvent(xp.frame, "PLAYER_ENTERING_WORLD")
  check("cap pivots to the watched faction", xp.repTracked() == 7)
  check("rep mode watches the event set", xp.frame.events.UPDATE_FACTION ~= nil)
  check("rep mode never listens for level-ups", xp.frame.events.PLAYER_LEVEL_UP == nil)
  check("the guild send helpers are gone", xp.maybeGuildDing == nil and xp.flushGuildDing == nil)
  _G.GetMaxPlayerLevel, _G.C_Reputation = nil, nil
end

-- XP tooltip: gold title, rate lines, bonuses, slash hint, drag guard
do
  xpWorld()
  local ns = loadXP()
  local xp = ns.xp
  local tip = { lines = {} }
  _G.GameTooltip = {
    SetOwner = function() end,
    ClearLines = function()
      tip.lines = {}
    end,
    SetText = function(_, t, r, g)
      tip.title = t
      tip.color = { r, g }
    end,
    AddLine = function(_, t)
      tip.lines[#tip.lines + 1] = t
    end,
    Show = function()
      tip.shown = true
    end,
    Hide = function() end,
  }
  local seg = xp.barSegments({ level = 10, xp = 400, req = 1000, capped = false }, 200, 100)
  local est = { status = "ready", xpPerHour = 144000, etaSeconds = 1500, windowSeconds = 600 }
  xp.showTip(est, seg, 1, "xp", "10  400/1k (40%)")
  check(
    "tooltip titles the xp numbers in gold",
    tip.title == "10  400/1k (40%)" and tip.color[1] == 1 and tip.color[2] == 0.82
  )
  check(
    "tooltip carries reach and hint",
    tip.lines[3] == "Rested: 20% of level"
      and tip.lines[4] == "1 quest ready: 10% of level"
      and tip.lines[#tip.lines]:find("/vui help", 1, true) ~= nil
  )
  xp.dragging = true
  tip.lines = {}
  xp.showTip(est, seg, 1, "xp", "10  400/1k (40%)")
  check("tooltip never fires mid-drag", #tip.lines == 0)
  xp.dragging = false
  tip.lines = {}
  xp.showTip(est, seg, 1, "xp")
  check("tooltip falls back to the module name", tip.title == "XP")
  _G.GameTooltip = nil
end

-- XP rivals: guests warn once, and only when announced
do
  xpWorld()
  _G.C_AddOns = {
    IsAddOnLoaded = function(addon)
      return addon == "Dominos"
    end,
  }
  local ns = loadXP()
  ns.db = {}
  local said = {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function() end
  ns.modules.InitAll()
  local xp = ns.xp
  local warned = xp.checkRivals()
  check("a loaded rival warns once", warned == true and said[1]:find("Dominos", 1, true) ~= nil)
  check("the warning never repeats", xp.checkRivals() == false and #said == 1)
  -- Level-up guild posts were removed outright: the SendChatMessage call
  -- tripped the blocked-action guard, which no pcall can catch, so the xp
  -- module holds no send helper and registers no level-up event.
  check("no guild send survives the removal", xp.maybeGuildDing == nil and xp.flushGuildDing == nil)
  _G.C_AddOns = nil
end

-- Vendor module: junk sells and gear repairs at the merchant, poor
-- quality only, guild funds first, audit instead of acting. No old
-- gear, no disenchanting, no button hooks: sell junk and repair.
local VENDOR = {
  "modules/vendor/Vendor.lua",
  "modules/vendor/Panel.lua",
  "modules/vendor/Repair.lua",
  "modules/vendor/Sell.lua",
  "modules/vendor/Surplus.lua",
  "modules/vendor/Tooltip.lua",
  "modules/vendor/Plugins.lua",
}
local function loadVendor()
  local ns = loadCore()
  for _, file in ipairs(VENDOR) do
    assert(loadfile(file))("VocUI", ns)
  end
  return ns
end

-- A stub merchant world: two bags, a money purse, a repair bill, and
-- a guild flag, all mutable per block.
local function vendorWorld()
  local w = {
    combat = false,
    money = 100,
    bill = 0,
    canRepair = true,
    inGuild = false,
    guildAllowed = false,
    bulkCalled = false,
    bulkEarned = 12,
    sellEnabled = true,
    repairCalls = {},
    junkEnabled = true,
  }
  local quality = { ["item:1"] = 0, ["item:3"] = 0, ["item:4"] = 0, ["item:2"] = 2 }
  local price = { ["item:1"] = 5, ["item:4"] = 7 }
  _G.InCombatLockdown = function()
    return w.combat
  end
  _G.NUM_BAG_SLOTS = 1
  local slots = {
    [0] = { { link = "item:1", quality = 0 }, { link = "item:2", quality = 2 } },
    [1] = { { link = nil, quality = 0, backlink = "item:4" } },
  }
  _G.C_Container = {
    GetContainerNumSlots = function(bag)
      return slots[bag] ~= nil and #slots[bag] or 0
    end,
    GetContainerItemInfo = function(bag, slot)
      local s = slots[bag] ~= nil and slots[bag][slot] or nil
      if s == nil then
        return nil
      end
      return { quality = s.quality, hyperlink = s.link, stackCount = 1, hasNoValue = false }
    end,
    GetContainerItemLink = function(bag, slot)
      local s = slots[bag] ~= nil and slots[bag][slot] or nil
      if s == nil then
        return nil
      end
      return s.link or s.backlink
    end,
  }
  _G.C_Item = {
    GetItemInfo = function(link)
      return link, link, quality[link], 100, 1, "Armor", "Cloth", 1, "", 132456, price[link] or 0
    end,
  }
  _G.C_MerchantFrame = {
    SellAllJunkItems = function()
      w.bulkCalled = true
      w.money = w.money + w.bulkEarned
    end,
    GetNumJunkItems = function()
      return 2
    end,
    IsSellAllJunkEnabled = function()
      return w.sellEnabled
    end,
  }
  _G.GetMoney = function()
    return w.money
  end
  _G.GetRepairAllCost = function()
    return w.bill, w.canRepair
  end
  _G.RepairAllItems = function(useGuild)
    w.repairCalls[#w.repairCalls + 1] = useGuild
    w.bill = 0
  end
  _G.CanMerchantRepair = function()
    return true
  end
  _G.CanGuildBankRepair = function()
    return w.guildAllowed
  end
  _G.IsInGuild = function()
    return w.inGuild
  end
  _G.GetInventoryItemLink = function(_, _)
    return nil
  end
  _G.Syndicator, _G.C_AddOns = nil, nil
  _G.GetTime = function()
    return 1000
  end
  return w
end

-- Vendor: descriptor, state location, Forever rows
do
  vendorWorld()
  local ns = loadVendor()
  ns.db = {}
  local vendor = ns.vendor
  ns.modules.InitAll()
  check("vendor descriptor registered", vendor.descriptor.name == "vendor" and vendor.descriptor.default == true)
  check(
    "vendor state lives under modules.vendor",
    type(ns.db.modules) == "table" and ns.db.modules.vendor.enabled == true and ns.db.vendor == nil
  )
  local keys = {}
  for _, row in ipairs(vendor.OPTIONS) do
    if type(row.key) == "string" then
      keys[#keys + 1] = row.key
    end
  end
  check(
    "vendor options present in order",
    table.concat(keys, ",") == "enabled,sellJunk,surplus,autoRepair,guildFunds,audit,tooltipPrice"
  )
  check("junk means poor quality only", vendor.ScanJunk()[1].link == "item:1")
  check("vendor help lines keep config second to last", ns.HELP[#ns.HELP - 1]:find("config", 1, true) ~= nil)
  local hasVendorLine = false
  for _, line in ipairs(ns.HELP) do
    if line:find("/vui vendor", 1, true) ~= nil then
      hasVendorLine = true
    end
  end
  check("vendor help teaches the slash", hasVendorLine)
  local saved = _G.C_MerchantFrame
  _G.C_MerchantFrame = nil
  check("unavailable merchant hides", vendor.IsAvailable() == false)
  _G.C_MerchantFrame = saved
end

-- Vendor scan: guest cache first, Blizzard walk behind it
do
  vendorWorld()
  local ns = loadVendor()
  local vendor = ns.vendor
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
        return {
          bags = {
            [1] = {
              { itemLink = "item:1" },
              { itemLink = "item:2" },
              { itemLink = "item:3" },
              { itemLink = "item:9" },
            },
          },
        }
      end,
    },
  }
  local found = vendor.ScanJunk()
  check("guest junk is quality zero only", #found == 2 and found[1].link == "item:1" and found[2].link == "item:3")
  check("guest total counts vendor value", vendor.JunkTotal(found) == 5)
  _G.Auctionator = {
    API = {
      v1 = {
        IsReady = function()
          return true
        end,
        GetAuctionPriceByItemLink = function(_, link)
          if link == "item:1" then
            return 10000
          end
          return nil
        end,
      },
    },
  }
  local noted = {}
  local realSay = ns.say
  ns.say = function(msg)
    noted[#noted + 1] = msg
  end
  vendor.AuditReport(found)
  ns.say = realSay
  check("audit annotates auction values only", noted[1] == "audit: would sell item:1 for 5c (auction 1g)")
  check("worthless junk audits at zero", noted[2] == "audit: would sell item:3 for 0c")
  _G.Auctionator = nil
  _G.Syndicator.API.IsReady = function()
    return "loading"
  end
  local walked = vendor.ScanJunk()
  check(
    "unsettled guests fall back to the walk",
    #walked == 2 and walked[1].link == "item:1" and walked[2].link == "item:4"
  )
  check("walk total counts both bags", vendor.JunkTotal(walked) == 12)
  _G.Syndicator = nil
end

-- Vendor sell: bulk call, announced total, audit sells nothing
do
  local w = vendorWorld()
  local ns = loadVendor()
  ns.db = {}
  local said = {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function() end
  ns.modules.InitAll()
  local vendor = ns.vendor
  vendor.OnMerchant()
  check("junk sells through the bulk call", w.bulkCalled == true)
  check("the sale announces its total", said[1] == "sold junk for 12c")
  ns.db.modules.vendor.audit = true
  w.bulkCalled = false
  vendor.OnMerchant()
  check("audit sells nothing", w.bulkCalled == false)
  check(
    "audit names each line and the total",
    said[2] == "audit: would sell item:1 for 5c"
      and said[3] == "audit: would sell item:4 for 7c"
      and said[4] == "audit: 2 items for 12c"
  )
  ns.db.modules.vendor.audit = false
  w.sellEnabled = false
  w.bulkCalled = false
  said = {}
  vendor.OnMerchant()
  check("a disabled sell button ends the visit", w.bulkCalled == false and #said == 0)
  w.sellEnabled = true
  w.combat = true
  vendor.OnMerchant()
  check("combat gates the whole visit", w.bulkCalled == false and #said == 0)
end

-- Vendor repair: guild first when allowed, personal next, shortfall said once
do
  local w = vendorWorld()
  local ns = loadVendor()
  ns.db = {}
  local said = {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function() end
  ns.modules.InitAll()
  local vendor = ns.vendor
  check(
    "funds decide guild, personal, short",
    vendor.DecideFunds(500, true, true, 100) == "guild"
      and vendor.DecideFunds(500, true, false, 600) == "personal"
      and vendor.DecideFunds(500, true, false, 100) == "short"
      and vendor.DecideFunds(0, true, false, 100) == "none"
      and vendor.DecideFunds(500, false, false, 600) == "none"
  )
  check("shortfall counts the missing copper", select(2, vendor.DecideFunds(500, true, false, 100)) == 400)
  ns.db.modules.vendor.sellJunk = false
  w.bill, w.inGuild, w.guildAllowed = 500, true, true
  vendor.OnMerchant()
  check("guild repairs announce guild funds", w.repairCalls[1] == true and said[1] == "repaired for 5s (guild funds)")
  w.bill, w.guildAllowed, w.money = 500, false, 600
  said = {}
  vendor.OnMerchant()
  check("personal repairs announce the bill", w.repairCalls[2] == false and said[1] == "repaired for 5s")
  w.bill, w.money = 500, 100
  said = {}
  w.repairCalls = {}
  vendor.OnMerchant()
  check(
    "an uncovered bill says what is missing once",
    #w.repairCalls == 0 and #said == 1 and said[1] == "short 4s for repairs"
  )
  w.bill = 0
  said = {}
  vendor.OnMerchant()
  check("no bill means no repair line", #said == 0)
end

-- Vendor tooltip: Vendor line only when no vendor line shows
do
  vendorWorld()
  local hooks = {}
  _G.hooksecurefunc = function(obj, name, fn)
    hooks[#hooks + 1] = { obj = obj, name = name, fn = fn }
  end
  _G.GameTooltip = {}
  local ns = loadVendor()
  ns.db = {}
  ns.modules.InitAll()
  local vendor = ns.vendor
  check("tooltip hooks all three setters", #hooks == 3 and hooks[1].name == "SetBagItem")
  check("hooks install once", vendor.InstallTooltip() == nil and #hooks == 3)
  local function tipWith(lines)
    local left = {}
    for i, text in ipairs(lines) do
      left[i] = {
        GetText = function()
          return text
        end,
      }
    end
    local added = {}
    return {
      _left = left,
      NumLines = function(self)
        return #self._left
      end,
      GetLeftLine = function(self, i)
        return self._left[i]
      end,
      AddLine = function(self, text)
        added[#added + 1] = text
      end,
      added = added,
    }
  end
  local tip = tipWith({ "Gray Boots", "Some other line" })
  check("clean tooltips gain the line", vendor.MaybeAddPrice(tip, "item:1") == true)
  check("the line reads vendor and price", tip.added[1] == "Vendor: 5c")
  check("vendor lines dedupe", vendor.MaybeAddPrice(tipWith({ "Vendor: 9s" }), "item:1") == false)
  _G.SELL_PRICE = "Sell Price"
  check("native lines dedupe", vendor.MaybeAddPrice(tipWith({ "Sell Price: 1c" }), "item:1") == false)
  _G.SELL_PRICE = nil
  check("priceless items stay quiet", vendor.MaybeAddPrice(tipWith({}), "item:9") == false)
  ns.db.modules.vendor.tooltipPrice = false
  check("the row gates the line", vendor.MaybeAddPrice(tipWith({}), "item:1") == false)
  _G.hooksecurefunc, _G.GameTooltip = nil, nil
end

-- Vendor slash and panel: toggle sounds and says, rows bind live
do
  vendorWorld()
  local ns = loadVendor()
  ns.db = {}
  local said, played = {}, {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function(kind)
    played[#played + 1] = kind
  end
  ns.modules.InitAll()
  local vendor = ns.vendor
  _G.SlashCmdList.VOCUI("vendor off")
  check(
    "slash turns the module off with sound",
    vendor.opts().enabled == false and played[#played] == "off" and vendor.frame.events.MERCHANT_SHOW == nil
  )
  _G.SlashCmdList.VOCUI("vendor on")
  check(
    "slash turns the module on with sound",
    vendor.opts().enabled == true and vendor.frame.events.MERCHANT_SHOW ~= nil
  )
  local before = #played
  _G.SlashCmdList.VOCUI("vendor bogus")
  check("unknown vendor subcommand only prints help", #played == before)
  _G.SlashCmdList.VOCUI("vendor")
  check("bare vendor toggles the module", vendor.opts().enabled == false)
end

-- Vendor panel: a subcategory under VocUI, six rows, live callbacks
do
  vendorWorld()
  local registered, subcats = {}, {}
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
    CreateCheckbox = function()
      return {}
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
  local ns = loadVendor()
  ns.db = {}
  ns.modules.InitAll()
  ns.settings.Init()
  local vendor = ns.vendor
  check("vendor page is a subcategory under VocUI", #subcats == 1 and subcats[1].name == "Vendor")
  local keys = {}
  for _, s in ipairs(registered) do
    keys[#keys + 1] = s.key
  end
  check(
    "panel registers the rows in order",
    table.concat(keys, ",") == "enabled,sellJunk,surplus,autoRepair,guildFunds,audit,tooltipPrice"
  )
  check("panel leads with the job", headers[1] == vendor.descriptor.job)
  check(
    "vendor groups its rows under headers",
    headers[2] == "Sells poor quality only, asks about surplus, repairs all, each visit announced"
      and headers[3] == "At the merchant"
      and headers[4] == "Reporting"
  )
  local enabledSetting
  for _, s in ipairs(registered) do
    if s.key == "enabled" then
      enabledSetting = s
    end
  end
  ns.db.modules.vendor.enabled = false
  enabledSetting.callback("enabled")
  check("panel toggle applies live", vendor.frame.events.MERCHANT_SHOW == nil)
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
end

-- Vendor as a Baganator junk plugin: poor quality coins the bags.
do
  vendorWorld()
  local ns = loadVendor()
  ns.db = {}
  ns.modules.InitAll()
  local vendor = ns.vendor
  check("poor quality coins junk", vendor.JunkForBaganator(0, 1, nil, "item:1") == true)
  check("fine quality coins nothing", vendor.JunkForBaganator(0, 2, nil, "item:2") == false)
  check("the bag slot answers without a link", vendor.JunkForBaganator(1, 1, nil, nil) == true)
  check("unknown slots coin nothing", vendor.JunkForBaganator(9, 9, nil, nil) == false)
  ns.db.modules.vendor.enabled = false
  check("a disabled module coins nothing", vendor.JunkForBaganator(0, 1, nil, "item:1") == false)
  ns.db.modules.vendor.enabled = true
  ns.db.modules.vendor.sellJunk = false
  check("a quiet module coins nothing", vendor.JunkForBaganator(0, 1, nil, "item:1") == false)
  ns.db.modules.vendor.sellJunk = true
  local seen = {}
  local function stubBaganator()
    _G.Baganator = {
      API = {
        RegisterJunkPlugin = function(label, id, fn)
          seen = { label = label, id = id, fn = fn }
        end,
      },
    }
  end
  _G.C_AddOns = {
    IsAddOnLoaded = function(name)
      return name == "Baganator"
    end,
  }
  stubBaganator()
  vendor.RegisterBaganatorPlugin()
  check("a loaded Baganator registers now", seen.id == "vocui-vendor" and seen.label == "VocUI Vendor")
  check("the registered callback is the verdict", seen.fn(0, 1, nil, "item:1") == true)
  _G.C_AddOns = {
    IsAddOnLoaded = function()
      return false
    end,
  }
  _G.Baganator = nil
  seen = {}
  vendor.RegisterBaganatorPlugin()
  check("an absent Baganator registers nothing yet", seen.id == nil)
  stubBaganator()
  for _, frame in ipairs(mock.frames) do
    if frame.scripts.OnEvent and frame.events.ADDON_LOADED then
      pcall(frame.scripts.OnEvent, frame, "ADDON_LOADED", "Baganator")
    end
  end
  check("the guest load registers later", seen.id == "vocui-vendor" and seen.fn(0, 1, nil, "item:1") == true)
  _G.Baganator, _G.C_AddOns = nil, nil
end

-- Bars module: action bars and the cooldown manager. Buff bars grow
-- from the center instead of the native left-to-right fill.
local BARS = {
  "modules/bars/Bars.lua",
  "modules/bars/Consumables.lua",
  "modules/bars/Grow.lua",
  "modules/bars/Panel.lua",
}
local function loadBars()
  local ns = loadCore()
  for _, file in ipairs(BARS) do
    assert(loadfile(file))("VocUI", ns)
  end
  return ns
end

-- A stub cooldown viewer world: a mixin with the one buff-bar method,
-- a hook recorder, and bar frames with a recording status texture.
local function barsWorld()
  local w = { hooks = {} }
  _G.hooksecurefunc = function(obj, name, fn)
    w.hooks[#w.hooks + 1] = { obj = obj, name = name, fn = fn }
  end
  _G.CooldownViewerBuffBarItemMixin = {
    RefreshCooldownInfo = function() end,
  }
  return w
end
local function stubBar(o)
  o = o or {}
  local tex = { points = {}, filled = false }
  function tex:ClearAllPoints()
    self.points = {}
    self.filled = false
  end
  function tex:SetPoint(point, relativeTo, relativePoint, x, y)
    self.points[#self.points + 1] = { point, relativePoint, x, y }
  end
  function tex:SetAllPoints()
    self.points = {}
    self.filled = true
  end
  local bar = { _tex = tex }
  function bar:GetStatusBarTexture()
    return self._tex
  end
  function bar:GetMinMaxValues()
    return 0, o.max or 100
  end
  function bar:GetValue()
    return o.value or 0
  end
  function bar:GetWidth()
    return o.w or 200
  end
  function bar:GetHeight()
    return o.h or 19
  end
  function bar:GetOrientation()
    return o.orient or "HORIZONTAL"
  end
  local item = {}
  function item:GetBarFrame()
    return bar
  end
  return item, bar, tex
end

-- A stub bag world for the consumable tests: canned item facts at
-- level 10, an empty macro box, and the macro globals. Returns the
-- box so tests can assert creates and rewrites.
local CONSUMABLE_INFO = {
  ["item:1"] = { "Loaf", 5, 5, "Food", nil, 0, 5, 5 },
  ["item:2"] = { "Tough Jerky", 8, 10, "Food", "Food", 0, 5 },
  ["item:3"] = { "Feast", 30, 20, "Food", "Food", 0, 5 },
  ["item:4"] = { "Crystal Water", 1, 1, "Drink", "Drink", 0, 5 },
  ["item:5"] = { "Healing Potion", 10, 8, "Potion", "Healing", 0, 1 },
  ["item:6"] = { "Mana Potion", 10, 8, "Potion", "Restore Mana", 0, 1 },
  ["item:7"] = { "Short Sword", 10, 1, "Sword", nil, 2, 7 },
  ["item:8"] = { "Weak Water", 1, 1, "Drink", "Drink", 0, 5, 2 },
  ["item:9"] = { "Lesser Healing Potion", 5, 5, "Potion", "Healing", 0, 1, 8 },
}
local function consumableWorld()
  local box = { acc = 0, char = 0, slots = {} }
  _G.UnitLevel = function()
    return 10
  end
  _G.C_Item = {
    GetItemInfo = function(link)
      local it = CONSUMABLE_INFO[link]
      if not it then
        return nil
      end
      return it[1], link, 1, it[2], it[3], "Consumable", it[4], 20, "", 134400, it[8] or 0, it[6], it[7]
    end,
    GetItemSpell = function(link)
      local it = CONSUMABLE_INFO[link]
      if not it or not it[5] then
        return nil
      end
      return it[5], 1
    end,
  }
  _G.GetNumMacros = function()
    return box.acc, box.char
  end
  _G.GetMacroInfo = function(i)
    local m = box.slots[i]
    if not m then
      return nil
    end
    return m.name, m.icon, m.body
  end
  _G.CreateMacro = function(name, icon, body)
    box.char = box.char + 1
    local index = 120 + box.char
    box.slots[index] = { name = name, icon = icon, body = body }
    return index
  end
  _G.EditMacro = function(i, _, icon, body)
    local m = box.slots[i]
    if not m then
      return nil
    end
    if icon ~= nil then
      m.icon = icon
    end
    if body ~= nil then
      m.body = body
    end
    return i
  end
  return box
end
local function consumableTeardown()
  _G.UnitLevel, _G.C_Item, _G.GetNumMacros, _G.GetMacroInfo, _G.CreateMacro, _G.EditMacro, _G.InCombatLockdown =
    nil, nil, nil, nil, nil, nil, nil
end

-- Bars: descriptor, state location, Forever-only options
do
  local w = barsWorld()
  local ns = loadBars()
  ns.db = {}
  local bars = ns.bars
  ns.modules.InitAll()
  check(
    "bars descriptor registered",
    ns.modules.GetAll()[1] == bars.descriptor and bars.descriptor.name == "bars" and bars.descriptor.default == true
  )
  check(
    "bars state lives under modules.bars",
    type(ns.db.modules) == "table"
      and ns.db.modules.bars.enabled == true
      and ns.db.modules.bars.growth == "center"
      and ns.db.modules.bars.consumables == true
      and ns.db.modules.bars.food == true
      and ns.db.modules.bars.drink == true
      and ns.db.modules.bars.health == true
      and ns.db.modules.bars.mana == true
      and ns.db.bars == nil
  )
  local keys = {}
  for _, row in ipairs(bars.OPTIONS) do
    if type(row.key) == "string" then
      keys[#keys + 1] = row.key
    end
  end
  check(
    "bars options present",
    table.concat(keys, ",") == "enabled,growth,consumables,food,drink,health,mana"
      and ns.db.modules.bars.growth == "center"
  )
  check(
    "bars help lines keep config second to last",
    ns.HELP[#ns.HELP - 1]:find("config", 1, true) ~= nil and ns.HELP[3]:find("/vui bars", 1, true) ~= nil
  )
  check("bars hooks the buff-bar update on init", #w.hooks == 1 and w.hooks[1].name == "RefreshCooldownInfo")
  _G.hooksecurefunc, _G.CooldownViewerBuffBarItemMixin = nil, nil
end

-- Bars fill: center, left, right, and vertical
do
  barsWorld()
  local ns = loadBars()
  ns.db = {}
  local bars = ns.bars
  local item, _, tex = stubBar({ value = 40 })
  check(
    "center anchors half the fill each way",
    bars.ApplyFill(item) == true
      and #tex.points == 4
      and tex.points[3][1] == "LEFT"
      and tex.points[3][2] == "CENTER"
      and tex.points[3][3] == -40
      and tex.points[4][1] == "RIGHT"
      and tex.points[4][2] == "CENTER"
      and tex.points[4][3] == 40
  )
  ns.db.modules.bars.growth = "right"
  check(
    "right pins the fill to the right edge",
    bars.ApplyFill(item) == true
      and tex.points[3][1] == "LEFT"
      and tex.points[3][2] == "RIGHT"
      and tex.points[3][3] == -80
      and tex.points[4][1] == "RIGHT"
      and tex.points[4][2] == "RIGHT"
  )
  ns.db.modules.bars.growth = "left"
  check(
    "left hands the fill back to the client",
    bars.ApplyFill(item) == true and tex.filled == true and #tex.points == 0
  )
  ns.db.modules.bars.growth = "sideways"
  check("unknown growth stays native", bars.ApplyFill(item) == true and tex.filled == true)
  ns.db.modules.bars.growth = "center"
  local vitem, _, vtex = stubBar({ value = 50, orient = "VERTICAL" })
  check(
    "vertical bars center vertically",
    bars.ApplyFill(vitem) == true and vtex.points[3][1] == "TOP" and vtex.points[3][2] == "CENTER"
  )
  check("nothing to place on stays quiet", bars.ApplyFill(nil) == false and bars.ApplyFill({}) == false)
  ns.db.modules.bars.enabled = false
  bars.ApplyFill(item)
  check("a disabled module restores the fill", bars.OnBarCooldown(item) == false and tex.filled == true)
  _G.hooksecurefunc, _G.CooldownViewerBuffBarItemMixin = nil, nil
end

-- Bars hook: installs once, on viewer load
do
  local w = barsWorld()
  local ns = loadBars()
  ns.db = {}
  local bars = ns.bars
  ns.modules.InitAll()
  check(
    "the viewer load hooks the buff-bar update",
    #w.hooks == 1 and w.hooks[1].name == "RefreshCooldownInfo" and bars.hooked == true
  )
  check("the hook installs once", bars.InstallHook() == true and #w.hooks == 1)
  local fresh = loadBars()
  fresh.db = {}
  fresh.modules.InitAll()
  check("a viewer already loaded still hooks", #w.hooks == 2)
  _G.CooldownViewerBuffBarItemMixin = nil
  local later = loadBars()
  later.db = {}
  check("no viewer means no hook yet", later.bars.InstallHook() == false and later.bars.hooked ~= true)
  _G.hooksecurefunc, _G.CooldownViewerBuffBarItemMixin = nil, nil
  check("no hook API means unavailable", bars.IsAvailable() == false)
end

-- Consumables service: category matchers behind the macro words.
do
  local ns = loadBars()
  ns.db = {}
  local consumables = ns.consumables
  local function facts(name, classID, subclassID, spell)
    return { name = name, classID = classID, subclassID = subclassID, spell = spell, minLevel = 1, itemLevel = 1 }
  end
  check("bread is food", consumables.CategoryOf(facts("Tough Jerky", 0, 5, "Food")) == "food")
  check("unworded food and drink is food", consumables.CategoryOf(facts("Dalaran Sharp", 0, 5, nil)) == "food")
  check("water is drink", consumables.CategoryOf(facts("Conjured Crystal Water", 0, 5, "Drink")) == "drink")
  check("healing potion is health", consumables.CategoryOf(facts("Major Healing Potion", 0, 1, "Healing")) == "health")
  check("mana potion is mana", consumables.CategoryOf(facts("Major Mana Potion", 0, 1, "Restore Mana")) == "mana")
  check("elixirs never match", consumables.CategoryOf(facts("Elixir of Giants", 0, 2, "Elixir")) == nil)
  check("bandages never match", consumables.CategoryOf(facts("Heavy Linen Bandage", 0, 7, "First Aid")) == nil)
  check("gear never matches", consumables.CategoryOf(facts("Short Sword", 2, 7, nil)) == nil)
  check(
    "a potion matching both halves matches neither",
    consumables.CategoryOf(facts("Mana Healing Draught", 0, 1, "Odd Brew")) == nil
  )
  check("an unworded potion matches nothing", consumables.CategoryOf(facts("Mysterious Vial", 0, 1, "Unknown")) == nil)
  check("food and drink words together stay food", consumables.CategoryOf(facts("Watery Soup", 0, 5, nil)) == "food")
end

-- Consumables service: ranking picks the highest usable level.
do
  local box = consumableWorld()
  local ns = loadBars()
  ns.db = {}
  ns.inventory.BagLinks = function()
    return { "item:1", "item:2", "item:3", "item:4", "item:5", "item:6", "item:7" }
  end
  local best = ns.consumables.CollectBest()
  check("highest usable food wins", best.food and best.food.name == "Tough Jerky")
  check("drink matched", best.drink and best.drink.name == "Crystal Water")
  check("health potion matched", best.health and best.health.name == "Healing Potion")
  check("mana potion matched", best.mana and best.mana.name == "Mana Potion")
  check("the macro box is untouched by a ranking look", box.char == 0)
  consumableTeardown()
end

-- Bars consumables: macro create, retarget, empty, combat, and slots.
do
  local box = consumableWorld()
  local ns = loadBars()
  ns.db = {}
  local bars = ns.bars
  ns.inventory.BagLinks = function()
    return { "item:2", "item:4", "item:5", "item:6" }
  end
  local said = capturePrint(function()
    bars.ResyncMacros()
  end)
  check("first look creates four macros", box.char == 4 and #said == 4)
  local saidAgain = capturePrint(function()
    bars.ResyncMacros()
  end)
  check("an unchanged look stays silent", box.char == 4 and #saidAgain == 0)
  ns.inventory.BagLinks = function()
    return { "item:1", "item:4", "item:5", "item:6" }
  end
  local retarget = capturePrint(function()
    bars.ResyncMacros()
  end)
  local food = bars.FindMacro("VUI Food")
  check("a new best rewrites the macro silently", food and food.body:find("Loaf", 1, true) ~= nil and #retarget == 0)
  ns.inventory.BagLinks = function()
    return { "item:4", "item:5", "item:6" }
  end
  local empty = capturePrint(function()
    bars.ResyncMacros()
  end)
  check("an empty category keeps its macro and says so once", #empty == 1 and bars.FindMacro("VUI Food") ~= nil)
  local emptyAgain = capturePrint(function()
    bars.ResyncMacros()
  end)
  check("empty stays quiet after the first line", #emptyAgain == 0)
  _G.InCombatLockdown = function()
    return true
  end
  check("combat only pends", bars.ResyncMacros() == false and bars.macroPending == true)
  _G.InCombatLockdown = nil
  bars.InitMacrosImpl()
  ns.inventory.BagLinks = function()
    return { "item:2", "item:4", "item:5", "item:6" }
  end
  capturePrint(function()
    bars.macroFrame.scripts["OnEvent"]()
  end)
  local flushed = bars.FindMacro("VUI Food")
  check(
    "the regen event flushes the pending look",
    bars.macroPending == false and flushed and flushed.body:find("Tough Jerky", 1, true) ~= nil
  )
  box.slots, box.acc, box.char = {}, 0, 30
  _G.CreateMacro = function()
    return nil
  end
  bars.macroSaid.slots = nil
  local full = capturePrint(function()
    bars.ResyncMacros()
  end)
  check("full macro slots say so once", #full == 1)
  consumableTeardown()
end

-- Bars consumables: events follow the toggle, slash refreshes and surveys.
do
  barsWorld()
  local box = consumableWorld()
  local ns = loadBars()
  ns.db = {}
  ns.modules.InitAll()
  local bars = ns.bars
  check(
    "macro bag events register with the toggle",
    bars.macroFrame ~= nil
      and bars.macroFrame.events["BAG_UPDATE_DELAYED"] == true
      and bars.macroFrame.events["PLAYER_REGEN_ENABLED"] == true
  )
  ns.db.modules.bars.consumables = false
  bars.ApplyMacrosImpl()
  check("disabling macros unregisters the bag events", bars.macroFrame.events["BAG_UPDATE_DELAYED"] == nil)
  ns.db.modules.bars.consumables = true
  bars.ApplyMacrosImpl()
  ns.inventory.BagLinks = function()
    return { "item:2", "item:4", "item:5", "item:6" }
  end
  local refreshed = capturePrint(function()
    bars.Slash("refresh")
  end)
  check(
    "refresh reports where the macros point",
    refreshed[#refreshed]:find("macros: food Tough Jerky", 1, true) ~= nil and box.char == 4
  )
  local surveyed = capturePrint(function()
    bars.Slash("survey")
  end)
  check(
    "survey names the census and a match",
    surveyed[1]:find("survey: 4 distinct", 1, true) ~= nil and surveyed[2]:find("Tough Jerky", 1, true) ~= nil
  )
  local bogus = capturePrint(function()
    bars.Slash("bogus")
  end)
  check("a typo prints help", bogus[1]:find("commands", 1, true) ~= nil)
  ns.db.modules.bars.enabled = false
  bars.RowChanged("enabled")
  check("disabling the module unregisters the bag events", bars.macroFrame.events["BAG_UPDATE_DELAYED"] == nil)
  _G.hooksecurefunc, _G.CooldownViewerBuffBarItemMixin = nil, nil
  consumableTeardown()
end

-- Bars actions: the page buttons refresh and survey without slash.
do
  local box = consumableWorld()
  local ns = loadBars()
  ns.db = {}
  local bars = ns.bars
  ns.inventory.BagLinks = function()
    return { "item:2", "item:4", "item:5", "item:6" }
  end
  local actions = {}
  for _, row in ipairs(bars.OPTIONS) do
    if type(row) == "table" and row.kind == "button" then
      actions[#actions + 1] = row.action
    end
  end
  check("page buttons declare refresh and survey", table.concat(actions, ",") == "refresh,survey")
  local refreshed = capturePrint(function()
    bars.RowChanged("refresh")
  end)
  check(
    "the refresh button points the macros now",
    box.char == 4 and refreshed[#refreshed]:find("macros: food Tough Jerky", 1, true) ~= nil
  )
  local surveyed = capturePrint(function()
    bars.RowChanged("survey")
  end)
  check("the survey button lists the census", surveyed[1]:find("survey: 4 distinct", 1, true) ~= nil)
  consumableTeardown()
end

-- Vendor surplus: worse consumables are found, asked about, and sold.
do
  vendorWorld()
  consumableWorld()
  local ns = loadVendor()
  ns.db = {}
  local vendor = ns.vendor
  ns.inventory.BagLinks = function()
    return { "item:2", "item:1", "item:4", "item:8", "item:5", "item:7" }
  end
  local slots = {
    { 0, 1, 1, "item:2" },
    { 0, 2, 2, "item:1" },
    { 0, 3, 1, "item:4" },
    { 0, 4, 1, "item:8" },
    { 0, 5, 1, "item:5" },
    { 0, 6, 1, "item:7" },
  }
  ns.inventory.EachSlot = function(fn)
    for _, s in ipairs(slots) do
      if fn(s[1], s[2], { stackCount = s[3] }, s[4]) then
        break
      end
    end
  end
  local found = vendor.ScanSurplus()
  check(
    "surplus finds the worse stacks only",
    #found == 2 and found[1].link == "item:1" and found[2].link == "item:8" and found[1].count == 2
  )
  check("surplus totals price times count", vendor.SurplusTotal(found) == 12)
  local text = vendor.SurplusText(found, 12)
  check(
    "popup text asks with names and total",
    text:find("Sell 2 worse stacks for 12c?", 1, true) ~= nil
      and text:find("Loaf x2", 1, true) ~= nil
      and text:find("Weak Water", 1, true) ~= nil
  )
  check("a full merchant world is available", vendor.IsAvailable() == true)
  local savedItem = _G.C_Item
  _G.C_Item = nil
  check("missing item reads hide the module", vendor.IsAvailable() == false)
  _G.C_Item = savedItem
  consumableTeardown()
end

-- Vendor surplus: the ask pops once, declines stay quiet, accepts sell.
do
  vendorWorld()
  consumableWorld()
  local ns = loadVendor()
  ns.db = {}
  local vendor = ns.vendor
  ns.inventory.BagLinks = function()
    return { "item:2", "item:1", "item:4", "item:8", "item:5", "item:7" }
  end
  ns.inventory.EachSlot = function(fn)
    local slots = {
      { 0, 1, 1, "item:2" },
      { 0, 2, 2, "item:1" },
      { 0, 3, 1, "item:4" },
      { 0, 4, 1, "item:8" },
      { 0, 5, 1, "item:5" },
      { 0, 6, 1, "item:7" },
    }
    for _, s in ipairs(slots) do
      if fn(s[1], s[2], { stackCount = s[3] }, s[4]) then
        break
      end
    end
  end
  local shown = {}
  _G.StaticPopupDialogs = { GENERIC_CONFIRMATION = {} }
  _G.StaticPopup_Show = function(which, _, _, data)
    shown[#shown + 1] = { which = which, data = data }
    return #shown
  end
  local found = vendor.ScanSurplus()
  local asked = capturePrint(function()
    vendor.AskSurplus(found)
  end)
  check("the ask shows one popup", #shown == 1 and shown[1].which == "GENERIC_CONFIRMATION" and #asked == 0)
  check(
    "the popup names the sale",
    shown[1].data.text:find("Sell 2 worse stacks", 1, true) ~= nil and shown[1].data.acceptText == "Sell"
  )
  shown[1].data.cancelCallback()
  local askedAgain = capturePrint(function()
    vendor.AskSurplus(found)
  end)
  check("a decline stays quiet", #shown == 1 and #askedAgain == 0)
  vendor.surplusDeclined = false
  vendor.merchantOpen = true
  local money = 1000
  _G.GetMoney = function()
    return money
  end
  local state = { ["0:2"] = "item:1", ["0:4"] = "item:8" }
  _G.C_Container.GetContainerItemLink = function(bag, slot)
    return state[bag .. ":" .. slot]
  end
  _G.C_Container.UseContainerItem = function(bag, slot)
    local link = state[bag .. ":" .. slot]
    if link == "item:1" then
      money = money + 10
    end
    if link == "item:8" then
      money = money + 2
    end
    state[bag .. ":" .. slot] = nil
    return true
  end
  local said = capturePrint(function()
    shown[1].data.callback()
  end)
  check("accept sells the listed stacks for the delta", said[#said]:find("sold 2 worse stacks for 12c", 1, true) ~= nil)
  check("sold slots are empty", state["0:2"] == nil and state["0:4"] == nil)
  _G.C_Container, _G.GetMoney, _G.StaticPopupDialogs, _G.StaticPopup_Show = nil, nil, nil, nil
  consumableTeardown()
end

-- Vendor surplus: closed merchants and moved slots sell nothing.
do
  vendorWorld()
  consumableWorld()
  local ns = loadVendor()
  ns.db = {}
  local vendor = ns.vendor
  ns.inventory.BagLinks = function()
    return { "item:2", "item:1", "item:4", "item:8" }
  end
  ns.inventory.EachSlot = function(fn)
    local slots = {
      { 0, 1, 1, "item:2" },
      { 0, 2, 1, "item:1" },
      { 0, 3, 1, "item:4" },
      { 0, 4, 1, "item:8" },
    }
    for _, s in ipairs(slots) do
      if fn(s[1], s[2], { stackCount = s[3] }, s[4]) then
        break
      end
    end
  end
  local found = vendor.ScanSurplus()
  local money = 1000
  _G.GetMoney = function()
    return money
  end
  local state = { ["0:2"] = "item:1", ["0:4"] = "item:8" }
  _G.C_Container.GetContainerItemLink = function(bag, slot)
    return state[bag .. ":" .. slot]
  end
  _G.C_Container.UseContainerItem = function(bag, slot)
    money = money + 1
    state[bag .. ":" .. slot] = nil
    return true
  end
  vendor.merchantOpen = false
  local said = capturePrint(function()
    vendor.SellSurplusNow(found)
  end)
  check(
    "a closed merchant keeps everything",
    said[1]:find("merchant closed", 1, true) ~= nil and state["0:2"] == "item:1"
  )
  vendor.merchantOpen = true
  state["0:2"] = "item:2"
  state["0:4"] = "item:4"
  local quiet = capturePrint(function()
    vendor.SellSurplusNow(found)
  end)
  check(
    "moved slots are skipped silently",
    state["0:2"] == "item:2" and state["0:4"] == "item:4" and money == 1000 and #quiet == 0
  )
  _G.C_Container, _G.GetMoney = nil, nil
  consumableTeardown()
end

-- Vendor surplus: audit reports, live visits ask, the flag tracks open.
do
  vendorWorld()
  consumableWorld()
  local ns = loadVendor()
  ns.db = {}
  local vendor = ns.vendor
  ns.inventory.BagLinks = function()
    return { "item:2", "item:1", "item:4", "item:8", "item:5", "item:7" }
  end
  local slots = {
    { 0, 1, 1, "item:2" },
    { 0, 2, 2, "item:1" },
    { 0, 3, 1, "item:4" },
    { 0, 4, 1, "item:8" },
    { 0, 5, 1, "item:5" },
    { 0, 6, 1, "item:7" },
  }
  ns.inventory.EachSlot = function(fn)
    for _, s in ipairs(slots) do
      if fn(s[1], s[2], { stackCount = s[3] }, s[4]) then
        break
      end
    end
  end
  local audited = capturePrint(function()
    vendor.SurplusAudit(vendor.ScanSurplus())
  end)
  check(
    "audit names the surplus and totals it",
    audited[1]:find("audit: would sell", 1, true) ~= nil
      and audited[#audited]:find("audit: 2 surplus stacks for 12c", 1, true) ~= nil
  )
  vendor.opts()
  vendor.RepairNow = function() end
  local shown = {}
  _G.StaticPopupDialogs = { GENERIC_CONFIRMATION = {} }
  _G.StaticPopup_Show = function(_, _, _, data)
    shown[#shown + 1] = data
    return true
  end
  ns.db.modules.vendor.audit = true
  capturePrint(function()
    vendor.OnMerchant()
  end)
  check("audit visits ask nothing", #shown == 0)
  ns.db.modules.vendor.audit = false
  capturePrint(function()
    vendor.OnMerchant()
  end)
  check("live visits ask once with the flag open", #shown == 1 and vendor.merchantOpen == true)
  _G.StaticPopupDialogs, _G.StaticPopup_Show = nil, nil
  consumableTeardown()
end

-- Map module: one blue button on the minimap for the regular actions.
local MAP = {
  "modules/map/Map.lua",
  "modules/map/Panel.lua",
}
local function loadMap()
  local ns = loadCore()
  for _, file in ipairs(MAP) do
    assert(loadfile(file))("VocUI", ns)
  end
  return ns
end

-- A stub minimap world: an anchor frame and the tooltip recorder.
local function mapWorld()
  local w = { tooltip = { lines = {} } }
  _G.Minimap = {}
  _G.UIParent = {}
  _G.GameTooltip = {
    SetOwner = function(_, owner, anchor)
      w.tooltip.owner, w.tooltip.anchor = owner, anchor
    end,
    SetText = function(_, t, r, g, b)
      w.tooltip.title = t
      w.tooltip.color = { r, g, b }
    end,
    AddLine = function(_, t)
      w.tooltip.lines[#w.tooltip.lines + 1] = t
    end,
    Show = function()
      w.tooltip.shown = true
    end,
    Hide = function()
      w.tooltip.shown = false
    end,
  }
  return w
end
local function mapTeardown()
  _G.Minimap, _G.UIParent, _G.GameTooltip = nil, nil, nil
end

-- Map: descriptor, state location, the button on the ring
do
  mapWorld()
  local ns = loadMap()
  ns.db = {}
  ns.modules.InitAll()
  local map = ns.map
  check(
    "map descriptor registered",
    ns.modules.GetAll()[1] == map.descriptor and map.descriptor.name == "map" and map.descriptor.default == true
  )
  check(
    "map state lives under modules.map",
    type(ns.db.modules) == "table" and ns.db.modules.map.enabled == true and ns.db.modules.map.angle == 225
  )
  local button = map.button
  check("map builds one button", button ~= nil and button.width == 31 and button.height == 31)
  check("map layers ring, disk, and icon", map.border ~= nil and map.background ~= nil and map.icon ~= nil)
  local points = button.points
  check(
    "map hangs the button on the minimap ring",
    points ~= nil and points[1] == "CENTER" and points[2] == _G.Minimap and points[3] == "CENTER"
  )
  local wantX, wantY = map.OffsetForAngle(225, map.RADIUS)
  check(
    "default angle sits bottom-left",
    points ~= nil and math.abs(points[4] - wantX) < 0.01 and math.abs(points[5] - wantY) < 0.01
  )
  mapTeardown()
end

-- Map: the ring math every anchor shares
do
  local ns = loadMap()
  local function near(a, b)
    return math.abs(a - b) < 0.01
  end
  local x, y = ns.map.OffsetForAngle(0, 100)
  check("angle 0 faces right", near(x, 100) and near(y, 0))
  x, y = ns.map.OffsetForAngle(90, 100)
  check("angle 90 faces up", near(x, 0) and near(y, 100))
  x, y = ns.map.OffsetForAngle(225, 100)
  check("angle 225 sits bottom-left", near(x, -70.71) and near(y, -70.71))
end

-- Map: left-click pops the actions out, right-click opens settings
do
  mapWorld()
  local ns = loadMap()
  ns.db = {}
  local pressed = {}
  ns.modules.Register({
    name = "bars",
    init = function() end,
    Slash = function(rest)
      pressed[#pressed + 1] = rest
    end,
  })
  ns.modules.InitAll()
  local map = ns.map
  local opened, played = 0, {}
  ns.settings.Open = function()
    opened = opened + 1
  end
  ns.play = function(kind)
    played[#played + 1] = kind
  end
  check("actions start put away", map.window ~= nil and map.window.shown == false)
  local onClick = map.button.scripts.OnClick
  onClick(map.button, "LeftButton")
  check("left-click pops the actions out", map.window.shown == true and played[1] == "open")
  local names, press = {}, {}
  for _, a in ipairs(map.actions) do
    names[#names + 1] = a.key
    press[a.key] = a.press
  end
  check("pop-out lists the regular actions", table.concat(names, ",") == "refresh,survey,settings")
  press.refresh()
  check(
    "refresh runs through slash and puts the window away",
    played[2] == "on" and pressed[1] == "refresh" and map.window.shown == false
  )
  onClick(map.button, "LeftButton")
  press.survey()
  check(
    "survey runs through slash and puts the window away",
    played[4] == "open" and pressed[2] == "survey" and map.window.shown == false
  )
  onClick(map.button, "LeftButton")
  press.settings()
  check(
    "settings opens the tree and puts the window away",
    opened == 1 and played[6] == "open" and map.window.shown == false
  )
  onClick(map.button, "LeftButton")
  onClick(map.button, "LeftButton")
  check("left-click toggles the window", map.window.shown == false and played[7] == "open" and played[8] == "close")
  onClick(map.button, "LeftButton")
  onClick(map.button, "RightButton")
  check(
    "right-click opens settings and puts the window away",
    opened == 2 and played[10] == "open" and map.window.shown == false
  )
  mapTeardown()
end

-- Map: hover follows the tooltip contract
do
  local w = mapWorld()
  local ns = loadMap()
  ns.db = {}
  ns.modules.InitAll()
  local map = ns.map
  map.button.scripts.OnEnter(map.button)
  check(
    "map tooltip anchors to the button",
    w.tooltip.owner == map.button and w.tooltip.anchor == "ANCHOR_LEFT" and w.tooltip.shown == true
  )
  check(
    "map tooltip title is gold",
    w.tooltip.title == "VocUI" and w.tooltip.color[1] == 1 and w.tooltip.color[2] == 0.82 and w.tooltip.color[3] == 0
  )
  check("map tooltip teaches the clicks", #w.tooltip.lines == 2 and w.tooltip.lines[2]:find("settings", 1, true) ~= nil)
  map.button.scripts.OnLeave()
  check("map leave hides the tooltip", w.tooltip.shown == false)
  mapTeardown()
end

-- Map: slash and toggle
do
  mapWorld()
  local ns = loadMap()
  ns.db = {}
  local pressed = {}
  ns.modules.Register({
    name = "bars",
    init = function() end,
    Slash = function(rest)
      pressed[#pressed + 1] = rest
    end,
  })
  ns.modules.InitAll()
  local map = ns.map
  map.Slash("off")
  check("map off hides the button", map.opts().enabled == false and map.button.shown == false)
  map.Slash("on")
  check("map on shows the button", map.opts().enabled == true and map.button.shown == true)
  map.Slash("refresh")
  map.Slash("survey")
  check("map slash forwards its presses", pressed[1] == "refresh" and pressed[2] == "survey")
  capturePrint(function()
    map.Slash("bogus")
  end)
  check("unknown map subcommand only prints help", #pressed == 2)
  mapTeardown()
end

-- Map: without a minimap the button hangs off the screen corner
do
  mapWorld()
  _G.Minimap = nil
  local ns = loadMap()
  ns.db = {}
  ns.modules.InitAll()
  local points = ns.map.button.points
  check("no minimap means the screen corner", points ~= nil and points[1] == "TOPRIGHT" and points[2] == _G.UIParent)
  mapTeardown()
end

-- Map: validity needs frames
do
  mapWorld()
  local ns = loadMap()
  local realCreateFrame = _G.CreateFrame
  _G.CreateFrame = nil
  check("no frames means unavailable", ns.map.IsAvailable() == false)
  _G.CreateFrame = realCreateFrame
  check("frames mean available", ns.map.IsAvailable() == true)
  mapTeardown()
end

-- Map panel: a subcategory under VocUI, toggle plus angle plus actions
do
  mapWorld()
  local registered, subcats, headers, created, buttons = {}, {}, {}, {}, {}
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
      local s = { page = page, key = key, vtype = vtype }
      s.SetValueChangedCallback = function(_, fn)
        s.callback = fn
      end
      registered[#registered + 1] = s
      return s
    end,
    CreateCheckbox = function(_, s, tooltip)
      created[#created + 1] = { kind = "checkbox", setting = s, tooltip = tooltip }
      return {}
    end,
    CreateSliderOptions = function(minValue, maxValue, step)
      return { minValue = minValue, maxValue = maxValue, step = step }
    end,
    CreateSlider = function(_, s, options, tooltip)
      created[#created + 1] = { kind = "slider", setting = s, options = options, tooltip = tooltip }
      return {}
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
  _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, addSearchTags)
    local init = { name = name, buttonText = buttonText, tooltip = tooltip, addSearchTags = addSearchTags }
    function init.SetParentInitializer(_, parent, gate)
      init.parent, init.gate = parent, gate
    end
    buttons[#buttons + 1] = { init = init, click = onClick }
    return init
  end
  local ns = loadMap()
  ns.db = {}
  local pressed = {}
  ns.modules.Register({
    name = "bars",
    init = function() end,
    Slash = function(rest)
      pressed[#pressed + 1] = rest
    end,
  })
  ns.modules.InitAll()
  ns.settings.Init()
  local map = ns.map
  check("map page is a subcategory under VocUI", #subcats == 1 and subcats[1].name == "Map")
  local keys = {}
  for _, s in ipairs(registered) do
    keys[#keys + 1] = s.key
  end
  check("panel registers the toggle and the angle", table.concat(keys, ",") == "enabled,angle")
  check("panel leads with the job", headers[1] == map.descriptor.job)
  check(
    "panel teaches the clicks and groups the actions",
    headers[2] == "Left-click opens the quick actions, right-click opens these settings"
      and headers[3] == "Quick actions"
  )
  check("panel carries both action buttons", #buttons == 2)
  local slider
  for _, c in ipairs(created) do
    if c.kind == "slider" then
      slider = c
    end
  end
  check(
    "angle slider spans the ring",
    slider ~= nil and slider.options.minValue == 0 and slider.options.maxValue == 360 and slider.options.step == 5
  )
  local enabledSetting, angleSetting
  for _, s in ipairs(registered) do
    if s.key == "enabled" then
      enabledSetting = s
    elseif s.key == "angle" then
      angleSetting = s
    end
  end
  ns.db.modules.map.enabled = false
  enabledSetting.callback("enabled")
  check("panel toggle hides the button", map.button.shown == false)
  ns.db.modules.map.enabled = true
  enabledSetting.callback("enabled")
  buttons[1].click()
  buttons[2].click()
  check("action buttons dispatch through slash", pressed[1] == "refresh" and pressed[2] == "survey")
  ns.db.modules.map.angle = 90
  angleSetting.callback("angle")
  local points = map.button.points
  check(
    "angle slider re-anchors live",
    points ~= nil and math.abs(points[4] - 0) < 0.01 and math.abs(points[5] - 100) < 0.01
  )
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer, _G.CreateSettingsButtonInitializer =
    nil, nil, nil, nil
  mapTeardown()
end

-- Chat module: the outgoing dialect filter on the documented send call.
local CHAT = {
  "modules/chat/Chat.lua",
  "modules/chat/Dialect.lua",
  "modules/chat/Dictionaries.lua",
  "modules/chat/Panel.lua",
}
local function loadChat()
  local ns = loadCore()
  for _, file in ipairs(CHAT) do
    assert(loadfile(file))("VocUI", ns)
  end
  return ns
end

-- Deterministic randomness for dialect tests: variant picks take the
-- first variant, chance rolls return the controllable roll. Scoped to
-- the module table under test, so the shared generator is never touched.
local testRoll = 1
local function stubRandom(chat)
  testRoll = 1
  chat.random = function(n)
    if n == 100 then
      return testRoll
    end
    return 1
  end
end

-- Chat: descriptor, state location, options, help grammar
do
  _G.C_ChatInfo = { SendChatMessage = function() end }
  local ns = loadChat()
  ns.db = {}
  local chat = ns.chat
  check(
    "chat descriptor registered",
    ns.modules.GetAll()[1] == chat.descriptor and chat.descriptor.name == "chat" and chat.descriptor.default == true
  )
  ns.modules.InitAll()
  check(
    "chat state lives under modules.chat",
    type(ns.db.modules) == "table" and ns.db.modules.chat.enabled == true and ns.db.chat == nil
  )
  check(
    "chat defaults speak dwarven at chance 8",
    ns.db.modules.chat.dialect == "dwarf" and ns.db.modules.chat.chance == 8
  )
  local keys = {}
  for _, row in ipairs(chat.OPTIONS) do
    if type(row.key) == "string" then
      keys[#keys + 1] = row.key
    end
  end
  check(
    "chat options present in panel order",
    table.concat(keys, ",") == "enabled,dialect,chance,say,yell,whisper,channel,party,guild,raid"
  )
  check(
    "chat help lines keep config second to last",
    ns.HELP[#ns.HELP - 1]:find("config", 1, true) ~= nil and ns.HELP[2]:find("/vui chat", 1, true) ~= nil
  )
  _G.C_ChatInfo = nil
  check("unavailable chat stays hidden", chat.IsAvailable() == false)
end

-- Chat engine: dwarven word rewrites at full chance
do
  local ns = loadChat()
  local chat = ns.chat
  stubRandom(chat)
  local dwarf = chat.DICTIONARIES.dwarf
  check("dwarf says gday", chat.Mangle("well hello there friend", dwarf, 10) == "well G'day ther' friend")
  check("dwarf phrases need surrounding spaces", chat.Mangle("here I am today", dwarf, 10) == "'ere I'mma today")
  check("all caps stays untouched", chat.Mangle("HELLO FRIEND", dwarf, 10) == "HELLO FRIEND")
  check("punctuation rides along", chat.Mangle("hello, traveler!", dwarf, 10) == "G'day, traveler!")
  check("double apostrophes collapse", chat.Mangle("a''b", dwarf, 10) == "a'b")
  local troll = chat.DICTIONARIES.troll
  check("troll greets", chat.Mangle("hello yes man", troll, 10) == "'ello yah, mon mon")
end

-- Chat engine: flavor markers thin out below chance 10
do
  local ns = loadChat()
  local chat = ns.chat
  stubRandom(chat)
  local dwarf = chat.DICTIONARIES.dwarf
  testRoll = 90
  check("flavor sits out a bad roll", chat.Mangle("hello there", dwarf, 8) == "G'day there")
  check("plain words ignore the roll", chat.Mangle("hello boy", dwarf, 8) == "G'day lad")
  testRoll = 80
  check("the boundary roll still applies", chat.Mangle("hello there", dwarf, 8) == "G'day ther'")
end

-- Chat engine: hyperlinks shelter and come back byte-identical
do
  local ns = loadChat()
  local chat = ns.chat
  stubRandom(chat)
  local dwarf, troll = chat.DICTIONARIES.dwarf, chat.DICTIONARIES.troll
  check(
    "one link survives",
    chat.Mangle("hello |cffffff00|Hitem:12345|h[Thunderfury]|h|r today", dwarf, 10)
      == "G'day |cffffff00|Hitem:12345|h[Thunderfury]|h|r today"
  )
  -- The apostrophe guard skips ^-anchored rules after an', so that
  -- reads through the loose th rule, like the original.
  check(
    "two links survive with mangling between",
    chat.Mangle("say this |c1|h[A]|h|r and that |c2|h[B]|h|r now", troll, 10)
      == "say dis |c1|h[A]|h|r an' t'at |c2|h[B]|h|r now"
  )
end

-- Chat gate: toggles, types, channels, and the (( hatch
do
  local ns = loadChat()
  ns.db = {}
  local chat = ns.chat
  stubRandom(chat)
  check("say mangles", chat.MangleForSend("hello", "SAY") == "G'day")
  check("lowercase types mangle", chat.MangleForSend("hello", "say") == "G'day")
  check("ooc stays as typed", chat.MangleForSend("(( hello", "SAY") == "(( hello")
  check("emote never changes", chat.MangleForSend("hello", "EMOTE") == "hello")
  check("unknown types pass through", chat.MangleForSend("hello", "RAID_WARNING") == "hello")
  check(
    "numbered channels gate on 1-4",
    chat.MangleForSend("hello", "CHANNEL", 2) == "G'day"
      and chat.MangleForSend("hello", "CHANNEL", 5) == "hello"
      and chat.MangleForSend("hello", "CHANNEL", nil) == "hello"
  )
  local o = chat.opts()
  o.whisper = false
  check("a flipped channel passes through", chat.MangleForSend("hello", "WHISPER") == "hello")
  o.whisper = true
  o.chance = 0
  check("chance 0 stays silent", chat.MangleForSend("hello", "SAY") == "hello")
  o.chance = 8
  o.enabled = false
  check("a disabled module passes through", chat.MangleForSend("hello", "SAY") == "hello")
  o.enabled = true
  o.dialect = "troll"
  check("troll speaks", chat.MangleForSend("hello", "SAY") == "'ello")
  o.dialect = "orc"
  check("unknown dialects stay silent", chat.MangleForSend("hello", "SAY") == "hello")
  o.dialect = "dwarf"
  check("nil sends empty", chat.MangleForSend(nil, "SAY") == "")
  check("junk input crosses untouched", chat.MangleForSend(42, "SAY") == 42)
end

-- Chat hook: the wrapper mangles in place and restores on disable
do
  local sent = {}
  local original = function(message, chatType, languageID, target)
    sent = { message = message, chatType = chatType, languageID = languageID, target = target }
  end
  _G.C_ChatInfo = { SendChatMessage = original }
  local ns = loadChat()
  ns.db = {}
  local chat = ns.chat
  stubRandom(chat)
  ns.say = function() end
  ns.play = function() end
  ns.modules.InitAll()
  check("send wrapper installed", _G.C_ChatInfo.SendChatMessage == chat.SendChatMessage)
  _G.C_ChatInfo.SendChatMessage("hello", "SAY", 1, nil)
  check(
    "wrapper mangles and passes args through",
    sent.message == "G'day" and sent.chatType == "SAY" and sent.languageID == 1 and sent.target == nil
  )
  local brokenGate = chat.MangleForSend
  chat.MangleForSend = function()
    error("boom")
  end
  _G.C_ChatInfo.SendChatMessage("hello", "SAY")
  check("a mangling error fails open", sent.message == "hello")
  chat.MangleForSend = brokenGate
  chat.SetEnabled(false)
  check("disable restores the saved call", _G.C_ChatInfo.SendChatMessage == original)
  chat.SetEnabled(true)
  check("re-enable rewraps", _G.C_ChatInfo.SendChatMessage == chat.SendChatMessage)
  _G.C_ChatInfo = nil
  check("hook declines without the api", chat.HookSend() == false)
  check("disable without the api stays silent", pcall(chat.ApplyEnabledImpl) == true)
end

-- Chat slash: dialect, chance, and channel subcommands
do
  _G.C_ChatInfo = {
    SendChatMessage = function() end,
  }
  local ns = loadChat()
  ns.db = {}
  local chat = ns.chat
  stubRandom(chat)
  local said, played = {}, {}
  ns.say = function(msg)
    said[#said + 1] = msg
  end
  ns.play = function(kind)
    played[#played + 1] = kind
  end
  ns.modules.InitAll()
  _G.SlashCmdList.VOCUI("chat troll")
  check(
    "slash sets the dialect with sound",
    chat.opts().dialect == "troll" and played[#played] == "on" and said[#said] == "chat dialect troll"
  )
  _G.SlashCmdList.VOCUI("chat chance 3")
  check(
    "slash sets the chance with sound",
    chat.opts().chance == 3 and played[#played] == "on" and said[#said] == "chat chance 3"
  )
  local before = chat.opts().chance
  local saidBefore = #said
  local printed = capturePrint(function()
    _G.SlashCmdList.VOCUI("chat chance 11")
  end)
  check(
    "out-of-range chance only prints help",
    chat.opts().chance == before and #printed == #ns.HELP and #said == saidBefore + 1
  )
  _G.SlashCmdList.VOCUI("chat toggle say")
  check(
    "slash flips a channel with sound",
    chat.opts().say == false and played[#played] == "off" and said[#said] == "chat say channel off"
  )
  _G.SlashCmdList.VOCUI("chat toggle general")
  check("general names the channel key", chat.opts().channel == false)
  _G.SlashCmdList.VOCUI("chat toggle list")
  check("toggle list names every channel", said[#said]:find("channels say off", 1, true) ~= nil)
  before = chat.opts().say
  saidBefore = #said
  printed = capturePrint(function()
    _G.SlashCmdList.VOCUI("chat toggle bogus")
  end)
  check(
    "unknown channels only print help",
    chat.opts().say == before and #printed == #ns.HELP and #said == saidBefore + 1
  )
  _G.SlashCmdList.VOCUI("chat")
  check(
    "bare slash toggles the module",
    chat.opts().enabled == false and played[#played] == "off" and _G.C_ChatInfo.SendChatMessage ~= chat.SendChatMessage
  )
  _G.SlashCmdList.VOCUI("chat on")
  check("slash turns the module on", chat.opts().enabled == true and played[#played] == "on")
  saidBefore = #said
  printed = capturePrint(function()
    _G.SlashCmdList.VOCUI("chat bogus")
  end)
  check(
    "unknown chat subcommands only print help",
    chat.opts().enabled == true and #printed == #ns.HELP and #said == saidBefore + 1
  )
  _G.C_ChatInfo = nil
end

-- Chat panel: subcategory under VocUI, dialect and channel rows, live toggle
do
  _G.C_ChatInfo = {
    SendChatMessage = function() end,
  }
  local registered, subcats, headers = {}, {}, {}
  local dropdownInit
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
      return { setting = s }
    end,
    CreateSlider = function(_, s, options)
      return { setting = s, options = options }
    end,
    CreateSliderOptions = function(minValue, maxValue, step)
      return { minValue = minValue, maxValue = maxValue, step = step }
    end,
    CreateDropdown = function(_, s, options)
      dropdownInit = { setting = s, options = options }
      return dropdownInit
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
          headers[#headers + 1] = init
        end,
      }
    end,
  }
  _G.CreateSettingsListSectionHeaderInitializer = function(text)
    return text
  end
  local ns = loadChat()
  ns.db = {}
  ns.modules.InitAll()
  ns.settings.Init()
  local chat = ns.chat
  check("chat page is a subcategory under VocUI", #subcats == 1 and subcats[1].name == "Chat")
  local keys = {}
  for _, s in ipairs(registered) do
    keys[#keys + 1] = s.key
  end
  check(
    "panel registers the rows in order",
    table.concat(keys, ",") == "enabled,dialect,chance,say,yell,whisper,channel,party,guild,raid"
  )
  check(
    "panel leads with the job and the escape hatch",
    headers[1] == chat.descriptor.job
      and headers[2] == "Lines starting with (( stay untouched, emotes never change"
      and headers[3] == "Dialect"
      and headers[4] == "Channels"
  )
  local dropdown
  for _, s in ipairs(registered) do
    if s.key == "dialect" then
      dropdown = s
    end
  end
  check("dialect row exists", dropdown ~= nil)
  local picked = dropdownInit ~= nil and dropdownInit.options() or {}
  check(
    "dialect dropdown offers dwarven and troll",
    #picked == 2 and picked[1].value == "dwarf" and picked[2].value == "troll"
  )
  local enabledSetting
  for _, s in ipairs(registered) do
    if s.key == "enabled" then
      enabledSetting = s
    end
  end
  ns.db.modules.chat.enabled = false
  enabledSetting.callback()
  check("panel toggle removes the wrapper", _G.C_ChatInfo.SendChatMessage ~= chat.SendChatMessage)
  ns.db.modules.chat.enabled = true
  enabledSetting.callback()
  check("panel toggle reinstalls the wrapper", _G.C_ChatInfo.SendChatMessage == chat.SendChatMessage)
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
  _G.C_ChatInfo = nil
end

-- Chat engine: rebuilt voice vectors (chance 10, first variant)
do
  local ns = loadChat()
  ns.db = {}
  local chat = ns.chat
  stubRandom(chat)
  local dwarf, troll = chat.DICTIONARIES.dwarf, chat.DICTIONARIES.troll
  local vectors = {
    { dwarf, "say hello to my little friend", "say G'day ta me wee lad" },
    { dwarf, "tell me what do you want", "tell me wha' d'ye want" },
    { dwarf, "fight for the Alliance today", "fight fer Khaz Modan today" },
    { dwarf, "those lads are brave", "them lads are brave" },
    { dwarf, "do you ken me", "do ya ken me" },
    { dwarf, "we cannot win", "we cannae win" },
    { dwarf, "she is no girl", "she is nay lass" },
    { dwarf, "yes I know the way", "aye I ken th' way" },
    { dwarf, "go to hell now", "go ta blazes now" },
    { dwarf, "give him the gold", "give 'im th' gold" },
    { dwarf, "it is never just a little beer", "it is nev'r jes a wee ale" },
    { dwarf, "before you go tell me no", "afore ya go tell me nay" },
    { dwarf, "the thane thanked them", "th' thane thanked 'em" },
    { troll, "tell me are you coming", "tell mi ya be coming" },
    { troll, "we are going to take the city", "we be gonna take da city" },
    { troll, "who are you mon", "who ya be mon" },
    { troll, "what do you want", "wha' do ya want" },
    { troll, "I thank you very much", "I tank ya, mon real much" },
    { troll, "my brother is very brave", "mi brudda be real brave" },
    { troll, "this power is dark", "dis mojo be black" },
    { troll, "the doctor is in", "da doctor be in" },
    { troll, "those men", "dose men" },
    { troll, "thanks", "tank ya" },
    { troll, "thank the loa", "tank da loa" },
    { troll, "do you feel lucky", "do ya be feelin' lucky" },
    { troll, "sure thing thanks bye", "ya mon t'ing tank ya later, mon" },
    { troll, "your gear is ready", "ya gear be ready" },
  }
  for _, v in ipairs(vectors) do
    check("voice: " .. v[2], chat.Mangle(v[2], v[1], 10) == v[3])
  end
end

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail > 0 and 1 or 0)
