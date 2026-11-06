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
-- MacroConstantsDocumentation.lua, 120 account and 30 character
-- macros.)

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
-- this table is corrected from observed bags, never from memory.
-- Session-only macro state: announce-once flags and the combat defer.
-- Nothing here persists; the macros themselves are the storage.
bars.macroSaid = {}

bars.macroPending = false
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
  local best = ns.consumables.CollectBest()
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
  ns.consumables.EachLink(function(link)
    local facts = ns.consumables.ItemFacts(link)
    if facts and facts.classID == ns.consumables.CONSUMABLE_CLASS then
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
    local cat = ns.consumables.CategoryOf(facts)
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
