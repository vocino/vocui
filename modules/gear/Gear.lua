local _, ns = ...
local gear = {}
ns.gear = gear

-- Gear: equip bag upgrades out of combat. This is the Forever build of
-- the VocGear job, rebuilt under the VocUI module contract. Forever has
-- no Pawn build, so item level decides here; the Pawn path, its scale
-- and margin options, and the Great Vault helper are Retail-only in
-- VocGear and do not exist in this module at all.

gear.SECTION = "modules.gear"

-- Defaults are the product: the module ships set up the way its player
-- plays, and the settings page exists mainly to turn things off. Only
-- options that do something on the Forever client are declared; the
-- VocGear options tied to Pawn (minimum upgrade %, Pawn scale, include
-- item-level upgrades) and to the Great Vault have no row here.
gear.defaults = {
  enabled = true,
  announce = true,
  audit = false,
  autoTwoSlot = false,
  keepHeirlooms = true,
  protectSets = true,
  swapWeapons = true,
  equipSound = "878", -- "0" = off; others are SOUNDKIT IDs, see gear.EQUIP_SOUNDS
  sessionIlvl = true,
  sheetButton = true,
}

-- The live state table: VocUIDB.modules.gear and nowhere else.
function gear.opts()
  return ns.config.Section(gear.SECTION, gear.defaults)
end

-- Equip celebration sounds. IDs verified on the Forever branch
-- (Blizzard_SharedXML/Mainline/SoundKitConstants.lua): the client's own
-- UI chimes, played through the core helper so they honor the player's volume.
gear.EQUIP_SOUNDS = {
  { id = "878", key = "IG_QUEST_LIST_COMPLETE", label = "Quest chime" },
  { id = "23404", key = "UI_AUTO_QUEST_COMPLETE", label = "Auto quest complete" },
  { id = "73277", key = "UI_WORLDQUEST_COMPLETE", label = "World quest complete" },
}

-- The equip-sound choices as data: off plus the client chimes.
-- The panel row carries this table; the core turns it into the
-- dropdown options function, so the control vocabulary lives in the
-- core exactly once (Principles #11).
function gear.EquipSoundChoices()
  local choices = {
    { value = "0", label = "Off", tooltip = "No sound when equipping" },
  }
  for _, snd in ipairs(gear.EQUIP_SOUNDS) do
    choices[#choices + 1] = { value = snd.id, label = snd.label, tooltip = "" }
  end
  return choices
end

-- The dropdown options function, built by the core from the choices
-- above. Kept so the dropdown and its test read the same source.
function gear.EquipSoundOptions()
  return ns.settings.DropdownOptions(gear.EquipSoundChoices())()
end

-- Play the configured equip sound through the core helper's route
-- (ns.playID, presence-gated). SOUNDKIT names first and the numeric
-- IDs behind them, so a Blizzard rename never silences the polish.
-- Silent when off or unavailable.
function gear.playEquipSound()
  local id = tonumber(gear.opts().equipSound) or 0
  if id == 0 then
    return
  end
  local key
  for _, snd in ipairs(gear.EQUIP_SOUNDS) do
    if snd.id == tostring(id) then
      key = snd.key
      break
    end
  end
  local named = type(SOUNDKIT) == "table" and type(key) == "string" and SOUNDKIT[key] or nil
  ns.playID(type(named) == "number" and named or id)
end

-- Session-only state. None of this persists: displaced-gear memory,
-- one-shot announcements, placeholder rows, and declined sets are all
-- per-login judgments.
gear.flagged = {} -- links announced as not-auto-equipped, per session
gear.pendingInfo = {} -- itemID -> placeholder rows waiting on item data
gear.setDeclined = {} -- setID -> true, per session

-- Declarative option rows for the module's settings page (CRAFT:
-- settings are data). The panel builder in Panel.lua renders these;
-- only Forever-relevant options exist here.
gear.OPTIONS = {
  {
    key = "enabled",
    kind = "checkbox",
    label = "Enable auto-equip",
    tooltip = "Equip bag upgrades out of combat by item level",
  },
  {
    kind = "header",
    label = "Announcements",
  },
  {
    key = "announce",
    kind = "checkbox",
    label = "Chat announcements",
    tooltip = "Print a line when Gear equips or advises",
  },
  {
    key = "audit",
    kind = "checkbox",
    label = "Audit mode",
    tooltip = "Announce only: never equip, just say what would happen",
  },
  {
    kind = "header",
    label = "Equipping",
  },
  {
    key = "autoTwoSlot",
    kind = "checkbox",
    label = "Auto-equip rings and trinkets",
    tooltip = "Equip into the weaker of the pair instead of announcing",
  },
  {
    key = "keepHeirlooms",
    kind = "checkbox",
    label = "Don't replace heirlooms",
    tooltip = "Keep equipped heirlooms even when something else scores higher",
  },
  {
    key = "protectSets",
    kind = "checkbox",
    label = "Prioritize set bonuses",
    tooltip = "Complete set bonuses automatically and never break an active one",
  },
  {
    key = "swapWeapons",
    kind = "checkbox",
    label = "Swap weapon types",
    tooltip = "Equip upgrades across weapon types and across the one-hand/two-hand line. Melee-to-ranged swaps always announce instead",
  },
  {
    kind = "header",
    label = "Feedback",
  },
  {
    key = "equipSound",
    kind = "dropdown",
    choices = gear.EquipSoundChoices(),
    label = "Equip sound",
    tooltip = "Sound played when Gear equips an upgrade. Changing it previews the sound",
  },
  {
    kind = "header",
    label = "Character sheet",
  },
  {
    key = "sessionIlvl",
    kind = "checkbox",
    label = "Session item-level gain",
    tooltip = "Show the session's item-level gain on the character sheet's Item Level readout",
  },
  {
    key = "sheetButton",
    kind = "checkbox",
    label = "Character sheet button",
    tooltip = "Show a Check Bags button on the character sheet",
  },
}

-- Validity predicate. Gear judges bags through the item and container
-- namespaces; without them there is nothing to equip with, so the
-- module is never initialized and never listed (principle 12).
function gear.IsAvailable()
  return type(C_Item) == "table" and type(C_Container) == "table"
end

-- Toggle the module: the setting applies live, the checkbox sound
-- confirms, and re-enabling clears the loop guard before rescanning.
function gear.SetEnabled(on)
  ns.config.Set(gear.SECTION, "enabled", on)
  ns.play(on and "on" or "off")
  ns.say("gear module " .. (on and "on" or "off"))
  if on then
    -- An explicit enable overrides a rival stand-down and clears the
    -- loop guard: the player's choice wins.
    gear.rivalStoodDown = false
    if gear.ClearGuard then
      gear.ClearGuard()
    end
  end
  if gear.ApplyEnabledImpl then
    gear.ApplyEnabledImpl()
  end
  if gear.EnsureSheetImpl then
    gear.EnsureSheetImpl()
  end
  if on and gear.CheckNowImpl then
    gear.CheckNowImpl()
  end
end

function gear.Slash(rest)
  local cmd = (rest or ""):match("^(%S*)") or ""
  if cmd == "on" then
    gear.SetEnabled(true)
  elseif cmd == "off" then
    gear.SetEnabled(false)
  elseif cmd == "scan" then
    if gear.CheckNowImpl then
      gear.CheckNowImpl()
    end
  elseif cmd == "why" then
    if gear.WhySayImpl then
      gear.WhySayImpl()
    end
  elseif cmd == "ilvl" then
    if gear.IlvlSayImpl then
      gear.IlvlSayImpl()
    end
  elseif cmd == "announce" then
    local on = not gear.opts().announce
    ns.config.Set(gear.SECTION, "announce", on)
    ns.play(on and "on" or "off")
    ns.say("announcements " .. (on and "on" or "off"))
  else
    ns.help()
  end
end

-- The descriptor loads first; the job files below fill in the Impl
-- functions it delegates to, so registration never waits on them.
local descriptor = {
  name = "gear",
  title = "Gear",
  job = "Equips bag upgrades out of combat by item level",
  default = true,
  IsAvailable = gear.IsAvailable,
  init = function()
    if gear.InitImpl then
      gear.InitImpl()
    end
  end,
  BuildPanel = function(page)
    if gear.BuildPanelImpl then
      gear.BuildPanelImpl(page)
    end
  end,
  Slash = gear.Slash,
}
gear.descriptor = descriptor
ns.modules.Register(descriptor)

-- Help lines for this module's subcommands, inserted ahead of the
-- config/help pair so the family grammar (config second to last, help
-- last) still holds.
do
  local lines = {
    "/vui gear on|off   turn the gear module on or off",
    "/vui gear scan     check bags now",
    "/vui gear why      explain every bag item",
    "/vui gear ilvl     show session item-level gain",
    "/vui gear announce toggle chat announcements",
  }
  local at = #ns.HELP - 2 -- ahead of the config line (second to last)
  for i, line in ipairs(lines) do
    table.insert(ns.HELP, at + i, line)
  end
end
