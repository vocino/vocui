local _, ns = ...
local bars = ns.bars

-- Consumable macros: one action-bar macro per hunger, thirst, and
-- potion category, retargeted at the best usable item in bags whenever
-- bags, level, or macro state changes. The player drags each macro to
-- the bar once; the macro slot never moves, so placement and keybinds
-- survive every retarget. Nothing acts in combat: a bag change
-- mid-fight only sets a pending flag that the regen event flushes.
-- (The four macro globals below are C-side bare names Blizzard's own
-- MacroUI calls bare on the Forever branch:
-- Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.lua and
-- Blizzard_MacroIconSelector.lua. Slot limits live in the generated
-- docs: Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- MacroConstantsDocumentation.lua, 120 account and 30 character
-- macros. Item classes live there too: ItemConstantsDocumentation.lua,
-- Enum.ItemClass.Consumable = 0, Enum.ItemConsumableSubclass Potion = 1
-- and Fooddrink = 5.)

bars.CONSUMABLE_CLASS = 0
bars.SUBCLASS_POTION = 1
bars.SUBCLASS_FOODDRINK = 5
bars.ACCOUNT_MACRO_MAX = 120 -- Constants.MacroConsts.MAX_ACCOUNT_MACROS
bars.CHARACTER_MACRO_MAX = 30 -- Constants.MacroConsts.MAX_CHARACTER_MACROS

-- The four macros, in bar order. Names are fixed: free text never
-- belongs on the settings page (wiki/Coding.md), and fixed names keep
-- the bar slot stable across retargets.
bars.MACRO_DEFS = {
  { key = "food", name = "VUI Food", label = "food" },
  { key = "drink", name = "VUI Drink", label = "drink" },
  { key = "health", name = "VUI Health", label = "health potion" },
  { key = "mana", name = "VUI Mana", label = "mana potion" },
}

-- Category words, matched case-insensitively against the item's spell
-- name plus its item name. Seeded from the classic consumable pool;
-- "/vui bars survey" prints the exact fields behind every match, so
-- this table is corrected from observed bags, never from memory.
bars.CATEGORY_WORDS = {
  food = {
    "food",
    "bread",
    "roll",
    "cake",
    "pie",
    "meat",
    "ham",
    "cheese",
    "fish",
    "clam",
    "crab",
    "soup",
    "stew",
    "sausage",
    "roast",
    "pork",
    "beef",
    "chicken",
    "egg",
    "apple",
    "melon",
    "berry",
    "grain",
    "loaf",
    "biscuit",
    "cookie",
    "muffin",
    "tart",
    "jerky",
    "fillet",
    "chops",
    "kebab",
    "omelet",
  },
  drink = {
    "drink",
    "water",
    "juice",
    "milk",
    "tea",
    "coffee",
    "nectar",
    "dew",
    "brew",
    "nog",
    "punch",
  },
  health = { "heal" },
  mana = { "mana" },
}

-- Session-only macro state: announce-once flags and the combat defer.
-- Nothing here persists; the macros themselves are the storage.
bars.macroSaid = {}
bars.macroPending = false

local function playerLevel()
  if type(UnitLevel) ~= "function" then
    return nil
  end
  local ok, level = pcall(UnitLevel, "player")
  if ok and type(level) == "number" then
    return level
  end
  return nil
end

-- Full item facts for one bag link, or nil when the item cache cannot
-- answer yet. An uncached answer is unsure, never a verdict: the
-- caller skips the link and GET_ITEM_INFO_RECEIVED retries it.
function bars.ItemFacts(link)
  if type(link) ~= "string" then
    return nil
  end
  if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then
    return nil
  end
  local ok, name, _, _, itemLevel, minLevel, _, subType, _, _, icon, _, classID, subclassID =
    pcall(C_Item.GetItemInfo, link)
  if not ok or type(name) ~= "string" or type(classID) ~= "number" or type(subclassID) ~= "number" then
    return nil
  end
  local spellName = nil
  if type(C_Item.GetItemSpell) == "function" then
    local okSpell, got = pcall(C_Item.GetItemSpell, link)
    if okSpell and type(got) == "string" then
      spellName = got
    end
  end
  return {
    name = name,
    itemLevel = itemLevel,
    minLevel = minLevel,
    subType = subType,
    icon = icon,
    classID = classID,
    subclassID = subclassID,
    spell = spellName,
    link = link,
  }
end

local function hasWord(text, words)
  for _, word in ipairs(words) do
    if text:find(word, 1, true) then
      return true
    end
  end
  return false
end

-- One of "food", "drink", "health", "mana", or nil. Only the potion
-- and food-and-drink subclasses can match, so elixirs, flasks,
-- bandages, and scrolls never land in a macro. An item matching both
-- halves of a split matches neither: a miscategorized macro is worse
-- than an unchanged one, and the survey names it for the word table.
function bars.CategoryOf(facts)
  if type(facts) ~= "table" or facts.classID ~= bars.CONSUMABLE_CLASS then
    return nil
  end
  local text = ((facts.spell or "") .. " " .. facts.name):lower()
  if facts.subclassID == bars.SUBCLASS_POTION then
    local heal = hasWord(text, bars.CATEGORY_WORDS.health)
    local mana = hasWord(text, bars.CATEGORY_WORDS.mana)
    if mana and not heal then
      return "mana"
    end
    if heal and not mana then
      return "health"
    end
    return nil
  end
  if facts.subclassID == bars.SUBCLASS_FOODDRINK then
    if hasWord(text, bars.CATEGORY_WORDS.drink) and not hasWord(text, bars.CATEGORY_WORDS.food) then
      return "drink"
    end
    return "food"
  end
  return nil
end

-- Highest usable level wins; ties break toward the higher item level,
-- then the earlier name, so the pick is deterministic bag to bag.
function bars.RanksAbove(a, b)
  if a.minLevel ~= b.minLevel then
    return a.minLevel > b.minLevel
  end
  local ai = a.itemLevel or 0
  local bi = b.itemLevel or 0
  if ai ~= bi then
    return ai > bi
  end
  return a.name < b.name
end

-- Every bag link through one callback: the Syndicator cache when it
-- is present and settled (it already walked the bags for Baganator),
-- else the Blizzard bag walk. fn(link) runs per link; returning true
-- stops a Blizzard walk early.
function bars.EachLink(fn)
  if type(fn) ~= "function" then
    return
  end
  if not (ns.inventory and type(ns.inventory.BagLinks) == "function") then
    return
  end
  local links = ns.inventory.BagLinks()
  if links then
    for _, link in ipairs(links) do
      if type(link) == "string" then
        fn(link)
      end
    end
    return
  end
  if type(ns.inventory.EachSlot) == "function" then
    ns.inventory.EachSlot(function(_, _, _, link)
      if type(link) == "string" then
        return fn(link)
      end
      return false
    end)
  end
end

-- The best usable facts per category key. Items above the player's
-- level never win; an unknown player level fails open. Uncached links
-- are skipped for the next item-info event, never guessed at.
function bars.CollectBest()
  local best = {}
  local level = playerLevel()
  bars.EachLink(function(link)
    local facts = bars.ItemFacts(link)
    if not facts then
      return false
    end
    if facts.classID ~= bars.CONSUMABLE_CLASS then
      return false
    end
    if facts.subclassID ~= bars.SUBCLASS_POTION and facts.subclassID ~= bars.SUBCLASS_FOODDRINK then
      return false
    end
    if type(facts.minLevel) ~= "number" then
      return false
    end
    if level ~= nil and facts.minLevel > level then
      return false
    end
    local cat = bars.CategoryOf(facts)
    if not cat then
      return false
    end
    if best[cat] == nil or bars.RanksAbove(facts, best[cat]) then
      best[cat] = facts
    end
    return false
  end)
  return best
end

-- Every macro slot on this character: account slots run 1..nAcc and
-- character slots run past the account max (Blizzard_MacroUI.lua:
-- actualIndex is the selection plus the macro base, 0 or
-- MAX_ACCOUNT_MACROS). Found shapes carry index, name, and body.
function bars.ListMacros()
  if type(GetNumMacros) ~= "function" or type(GetMacroInfo) ~= "function" then
    return nil
  end
  local okN, nAcc, nChar = pcall(GetNumMacros)
  if not okN or type(nAcc) ~= "number" or type(nChar) ~= "number" then
    return nil
  end
  local found = {}
  local function scan(from, count)
    for i = 0, count - 1 do
      local index = from + i
      local ok, name, _, body = pcall(GetMacroInfo, index)
      if ok and type(name) == "string" then
        found[#found + 1] = { index = index, name = name, body = body }
      end
    end
  end
  scan(1, nAcc)
  scan(bars.ACCOUNT_MACRO_MAX + 1, nChar)
  return found
end

function bars.FindMacro(name)
  local all = bars.ListMacros()
  if not all then
    return nil
  end
  for _, macro in ipairs(all) do
    if macro.name == name then
      return macro
    end
  end
  return nil
end

-- Character macro slots still free, or nil when the macro API cannot
-- answer. A full box is the only diagnosed create failure.
function bars.FreeCharacterSlots()
  if type(GetNumMacros) ~= "function" then
    return nil
  end
  local ok, _, nChar = pcall(GetNumMacros)
  if not ok or type(nChar) ~= "number" then
    return nil
  end
  return bars.CHARACTER_MACRO_MAX - nChar
end

function bars.MacroBody(itemName)
  return "#showtooltip " .. itemName .. "\n/use " .. itemName
end

-- Point one macro at one item: create the character macro when it is
-- missing, rewrite it when the target changed, leave it when the body
-- already matches so the client fires no macro update. Returns
-- "created", "updated", "current", "combat", "slots", or
-- "unavailable"; only "slots" diagnoses itself, the rest stay quiet.
function bars.EnsureMacro(macroName, facts)
  if type(CreateMacro) ~= "function" or type(EditMacro) ~= "function" then
    return "unavailable"
  end
  local body = bars.MacroBody(facts.name)
  local found = bars.FindMacro(macroName)
  if found and found.body == body then
    return "current"
  end
  if ns.combat and ns.combat() then
    return "combat"
  end
  if found then
    local ok = pcall(EditMacro, found.index, nil, facts.icon, body)
    return ok and "updated" or "unavailable"
  end
  local ok, index = pcall(CreateMacro, macroName, facts.icon, body, true)
  if ok and type(index) == "number" then
    return "created"
  end
  if bars.FreeCharacterSlots() == 0 then
    return "slots"
  end
  return "unavailable"
end

-- Point one category macro at its best item. An empty category keeps
-- the macro's last item (dim but stay: position and keybind never
-- move) and says so once per session. Creating says what to do next;
-- retargets stay silent, the bar shows them.
function bars.SyncOneMacro(def, facts)
  if facts == nil then
    if not bars.macroSaid["empty:" .. def.key] then
      bars.macroSaid["empty:" .. def.key] = true
      ns.say("out of " .. def.label .. ": " .. def.name .. " kept its last item")
    end
    return "empty"
  end
  bars.macroSaid["empty:" .. def.key] = nil
  local outcome = bars.EnsureMacro(def.name, facts)
  if outcome == "created" then
    ns.say("made macro " .. def.name .. " (" .. facts.name .. "), drag it to the bar")
  elseif outcome == "slots" then
    if not bars.macroSaid.slots then
      bars.macroSaid.slots = true
      ns.say("no free character macro slot for " .. def.name .. " (delete one, then /vui bars refresh)")
    end
  elseif outcome == "combat" then
    bars.macroPending = true
  end
  return outcome
end

-- The resync: best in bags into every enabled category macro. A
-- disabled module or toggle does nothing; combat only pends.
function bars.ResyncMacros()
  local o = bars.opts()
  if not o.enabled or not o.consumables then
    return false
  end
  if ns.combat and ns.combat() then
    bars.macroPending = true
    return false
  end
  bars.macroPending = false
  local best = bars.CollectBest()
  for _, def in ipairs(bars.MACRO_DEFS) do
    if o[def.key] then
      bars.SyncOneMacro(def, best[def.key])
    end
  end
  return true
end

-- One-line report of where every enabled macro points, for the
-- explicit refresh command. Kept macros name their last target.
function bars.MacroReport()
  local parts = {}
  for _, def in ipairs(bars.MACRO_DEFS) do
    if bars.opts()[def.key] then
      local found = bars.FindMacro(def.name)
      local target = found and found.body and found.body:match("/use%s+(.+)$") or "kept"
      parts[#parts + 1] = def.key .. " " .. target
    end
  end
  return "macros: " .. table.concat(parts, ", ")
end

function bars.RefreshMacrosImpl()
  if ns.combat and ns.combat() then
    bars.macroPending = true
    ns.say("in combat: the macros refresh after combat")
    return false
  end
  bars.macroSaid.slots = nil -- an explicit look re-arms the slot warning
  bars.ResyncMacros()
  ns.say(bars.MacroReport())
  return true
end

-- The bag census behind the word table: one line per distinct
-- consumable in bags with the fields that decided its category, so a
-- mistuned word is corrected from observed data. Explicit command, so
-- many lines are fine.
function bars.SurveyImpl()
  local seen, order = {}, {}
  bars.EachLink(function(link)
    local facts = bars.ItemFacts(link)
    if facts and facts.classID == bars.CONSUMABLE_CLASS then
      local id = link:match("item:(%d+)") or link
      if not seen[id] then
        seen[id] = facts
        order[#order + 1] = id
      end
    end
    return false
  end)
  ns.say("survey: " .. tostring(#order) .. " distinct consumables in bags")
  for _, id in ipairs(order) do
    local facts = seen[id]
    local cat = bars.CategoryOf(facts)
    if type(facts.minLevel) ~= "number" then
      cat = "uncached"
    end
    print(
      "  "
        .. facts.name
        .. " | "
        .. tostring(facts.classID)
        .. "."
        .. tostring(facts.subclassID)
        .. " | "
        .. tostring(facts.subType)
        .. " | lvl "
        .. tostring(facts.minLevel)
        .. " | "
        .. (facts.spell or "no spell")
        .. " -> "
        .. (cat or "no match")
    )
  end
end

function bars.IsMacroKey(key)
  if key == "consumables" then
    return true
  end
  for _, def in ipairs(bars.MACRO_DEFS) do
    if key == def.key then
      return true
    end
  end
  return false
end

-- Macro bag events, registered with the consumables toggle and no
-- wider (CRAFT paradigm 3). PLAYER_ENTERING_WORLD carries the first
-- look; the item-info event retries uncached links.
bars.MACRO_EVENTS = {
  "BAG_UPDATE_DELAYED",
  "GET_ITEM_INFO_RECEIVED",
  "PLAYER_LEVEL_UP",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_REGEN_ENABLED",
}

function bars.ApplyMacrosImpl()
  local frame = bars.macroFrame
  if frame == nil or type(frame.RegisterEvent) ~= "function" or type(frame.UnregisterEvent) ~= "function" then
    return
  end
  local on = bars.opts().enabled and bars.opts().consumables
  for _, event in ipairs(bars.MACRO_EVENTS) do
    if on then
      frame:RegisterEvent(event)
    else
      frame:UnregisterEvent(event)
    end
  end
end

function bars.InitMacrosImpl()
  if bars.macroFrame then
    bars.ApplyMacrosImpl()
    return
  end
  if type(CreateFrame) ~= "function" then
    return
  end
  local frame = CreateFrame("Frame")
  bars.macroFrame = frame
  bars.ApplyMacrosImpl()
  frame:SetScript("OnEvent", function()
    bars.ResyncMacros()
  end)
end
