-- Headless tests for VocUI. No game client needed.
-- Run from the repo root:  lua tests/run.lua

local mock = dofile("tests/mock.lua")
mock.install()

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1
  else fail = fail + 1 print("FAIL " .. name) end
end

local CORE = {
  "core/Palette.lua", "core/Chat.lua", "core/Sounds.lua", "core/Config.lua",
  "core/Modules.lua", "core/Settings.lua", "core/Slash.lua", "core/Main.lua",
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
  print = function(s) lines[#lines + 1] = s end
  local ok, err = pcall(fn)
  print = realPrint
  assert(ok, err)
  return lines
end

-- palette.lua: every color has a name; rgb() spreads a token
do
  local ns = loadCore()
  local c = ns.COLORS
  check("family tokens present", c.gold[1] == 1 and c.gold[2] == 0.82 and c.gold[3] == 0
    and c.text and c.muted and c.red and c.green)
  local r, g, b, a = ns.rgb(c.gold, 0.5)
  check("rgb spreads a token with alpha", r == 1 and g == 0.82 and b == 0 and a == 0.5)
  r, g, b, a = ns.rgb(c.text)
  check("rgb without alpha", r == 1 and g == 1 and b == 1 and a == nil)
end

-- Chat.lua: the family chat voice (colored prefix, no trailing period)
do
  local ns = loadCore()
  check("family prefix color", ns.PREFIX_COLOR == "ff66ccff")
  local said = capturePrint(function() ns.say("hello") end)
  check("say prefixes the package name", said[1] == "|c" .. ns.PREFIX_COLOR .. "VocUI|r: hello")
end

-- Sounds.lua: SOUNDKIT names first, numeric fallback, silent without an API
do
  local ns = loadCore()
  local played = {}
  _G.PlaySound = function(id) played[#played + 1] = id end
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
  check("get misses outside defaults", ns.config.Get("demo", "nope") == nil
    and ns.config.Get("ghost", "nope") == nil)
  local defaultList = ns.config.Default("demo", "list")
  check("default returns a copy", type(defaultList) == "table" and defaultList ~= live.list)
  local events = {}
  ns.config.Subscribe(function(section, key, value)
    events[#events + 1] = section .. "." .. key .. "=" .. tostring(value)
  end)
  ns.config.Subscribe(function() error("broken listener") end)
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
  ns.say = function(msg) said[#said + 1] = msg end
  local order = {}
  check("register rejects junk", ns.modules.Register(nil) == false
    and ns.modules.Register({}) == false
    and ns.modules.Register({ name = "bad" }) == false)
  ns.modules.Register({ name = "good", job = "first",
    init = function() order[#order + 1] = "good" end })
  ns.modules.Register({ name = "broken", job = "second",
    init = function() error("boom") end })
  ns.modules.Register({ name = "third", job = "third",
    init = function() order[#order + 1] = "third" end })
  ns.modules.Register({ name = "hidden", job = "never here",
    -- gated at load: this situation never applies, so it stays hidden
    IsAvailable = function() return false end,
    init = function() order[#order + 1] = "hidden" end })
  ns.modules.Register({ name = "checker", job = "faulty check",
    IsAvailable = function() error("no api") end,
    init = function() order[#order + 1] = "checker" end })
  ns.modules.InitAll()
  check("every available module initializes", order[1] == "good" and order[2] == "third" and #order == 2)
  check("unavailable modules stay hidden", order[3] == nil)
  check("problems and breakage are reported", #said == 5)
  local periods = false
  for _, line in ipairs(said) do
    if line:sub(-1) == "." then periods = true end
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
      local cat = { name = n, GetID = function() return 7 end }
      categories[#categories + 1] = cat
      return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) openedID = id end,
  }
  _G.SettingsPanel = { GetLayout = function() return {
    AddInitializer = function(_, init) headers[#headers + 1] = init end,
  } end }
  _G.CreateSettingsListSectionHeaderInitializer = function(text) return text end

  local ns = loadCore()
  ns.db = {}
  local builtWith = {}
  ns.modules.Register({ name = "demo", job = "x",
    init = function() end,
    BuildPanel = function(cat) builtWith[#builtWith + 1] = cat end })
  ns.modules.Register({ name = "oops", job = "x",
    init = function() end,
    BuildPanel = function() error("panel boom") end })
  local said = {}
  ns.say = function(msg) said[#said + 1] = msg end
  ns.settings.Init()
  check("one category for the package", #categories == 1 and categories[1].name == "VocUI")
  check("module sections build against the category",
    #builtWith == 1 and builtWith[1] == categories[1])
  check("a broken panel never breaks the package",
    #said == 1 and said[1]:find("oops", 1, true) ~= nil)
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
      return { name = n, GetID = function() return 7 end }
    end,
    RegisterAddOnCategory = function() end,
  }
  _G.SettingsPanel = { GetLayout = function() return {
    AddInitializer = function(_, init) headers[#headers + 1] = init end,
  } end }
  _G.CreateSettingsListSectionHeaderInitializer = function(text) return text end
  local ns = loadCore()
  ns.db = {}
  ns.settings.Init()
  check("empty panel names the module contract",
    headers[1] == "No modules installed yet: modules add their own sections here")
  _G.Settings, _G.SettingsPanel, _G.CreateSettingsListSectionHeaderInitializer = nil, nil, nil
end

-- Settings.lua without the Settings API: no-op init, open says where
do
  local ns = loadCore()
  ns.db = {}
  local said
  ns.say = function(line) said = line end
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
  check("config sits second to last",
    ns.HELP[#ns.HELP - 1]:find("config", 1, true) ~= nil)
  check("help is last and names the long form",
    ns.HELP[#ns.HELP]:find("help", 1, true) ~= nil
    and ns.HELP[#ns.HELP]:find("/vocui", 1, true) ~= nil)

  local opened, played = 0, {}
  ns.settings = { Open = function() opened = opened + 1 end }
  ns.play = function(kind) played[#played + 1] = kind end
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
  check("typos print help, never act", opened == 3
    and #lines == 2 * (1 + #ns.HELP))
  check("help lines carry the prefix", lines[1]:find("^|cff66ccffVocUI|r: ") ~= nil)
end

-- Main.lua: the addon compartment (gold title, job line, slash hint)
do
  local ns = loadCore()
  check("compartment trio defined", type(_G.VocUI_CompartmentClick) == "function"
    and type(_G.VocUI_CompartmentEnter) == "function"
    and type(_G.VocUI_CompartmentLeave) == "function")
  local opened, played = 0, 0
  ns.settings = { Open = function() opened = opened + 1 end }
  ns.play = function() played = played + 1 end
  _G.VocUI_CompartmentClick("VocUI", "LeftButton")
  check("compartment click opens settings", opened == 1 and played == 1)
  local tip = { lines = {} }
  _G.GameTooltip = {
    SetOwner = function(_, owner, anchor) tip.owner, tip.anchor = owner, anchor end,
    SetText = function(_, t, r, g, b) tip.title = t tip.color = { r, g, b } end,
    AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end,
    Show = function() tip.shown = true end,
    Hide = function() tip.shown = false end,
  }
  local btn = {}
  _G.VocUI_CompartmentEnter("VocUI", btn)
  check("compartment tooltip anchors to the button",
    tip.owner == btn and tip.anchor == "ANCHOR_LEFT" and tip.shown == true)
  check("compartment tooltip title is gold", tip.title == "VocUI"
    and tip.color[1] == 1 and tip.color[2] == 0.82 and tip.color[3] == 0)
  check("compartment tooltip teaches the slash",
    #tip.lines == 2 and tip.lines[2]:find("/vui", 1, true) ~= nil)
  _G.VocUI_CompartmentLeave("VocUI", btn)
  check("compartment leave hides the tooltip", tip.shown == false)
  _G.GameTooltip = nil
  check("compartment enter without the API is silent",
    pcall(_G.VocUI_CompartmentEnter, "VocUI", btn) == true)
end

-- Main.lua: boot rebinds the SavedVariable, then inits once
do
  mock.reset()
  local ns = loadCore()
  local boot = mock.frames[#mock.frames]
  local onEvent = boot.scripts.OnEvent
  check("boot listens for load and login",
    boot.events.ADDON_LOADED and boot.events.PLAYER_LOGIN)
  local inits = {}
  ns.modules.Register({ name = "early", job = "x",
    init = function() inits[#inits + 1] = "early" end })
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

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail > 0 and 1 or 0)
