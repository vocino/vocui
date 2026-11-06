local _, ns = ...
local bars = {}
ns.bars = bars

-- Bars: action-bar and cooldown-manager customization, under the
-- module contract. First job: the cooldown viewer's buff bars grow
-- from the center instead of the native left-to-right fill, through
-- one secure hook and no new frames.

bars.SECTION = "modules.bars"

-- Defaults are the product: the module ships set up the way its player
-- plays. Center growth is the look; left is the native fill and right
-- its mirror, kept for players who read the other way.
bars.defaults = {
  enabled = true,
  growth = "center",
  consumables = true,
  food = true,
  drink = true,
  health = true,
  mana = true,
}

-- The live state table: VocUIDB.modules.bars and nowhere else.
function bars.opts()
  return ns.config.Section(bars.SECTION, bars.defaults)
end

-- Declarative option rows for the module's settings page (CRAFT:
-- settings are data). Growth reads live on every buff-bar update, so
-- only the toggle acts beyond the store write.
bars.OPTIONS = {
  {
    key = "enabled",
    kind = "checkbox",
    label = "Enable the bars module",
    tooltip = "Turns off the cooldown fill and the consumable macros",
  },
  {
    kind = "header",
    label = "Fill",
  },
  {
    key = "growth",
    kind = "dropdown",
    label = "Bar growth",
    tooltip = "Horizontal bars grow from the center, left, or right; vertical bars center or stay native",
    choices = {
      { value = "center", label = "Center" },
      { value = "left", label = "Left" },
      { value = "right", label = "Right" },
    },
  },
  {
    kind = "header",
    label = "Macros",
  },
  {
    key = "consumables",
    kind = "checkbox",
    label = "Maintain consumable macros",
    tooltip = "Keep the food, drink and potion macros pointed at the best in bags",
  },
  {
    key = "food",
    kind = "checkbox",
    label = "Food macro",
    tooltip = "Maintain the VUI Food macro",
  },
  {
    key = "drink",
    kind = "checkbox",
    label = "Drink macro",
    tooltip = "Maintain the VUI Drink macro",
  },
  {
    key = "health",
    kind = "checkbox",
    label = "Health potion macro",
    tooltip = "Maintain the VUI Health macro",
  },
  {
    key = "mana",
    kind = "checkbox",
    label = "Mana potion macro",
    tooltip = "Maintain the VUI Mana macro",
  },
  {
    kind = "header",
    label = "Actions",
  },
  {
    kind = "button",
    label = "Refresh macros",
    button = "Refresh",
    tooltip = "Point the food, drink and potion macros at the best in bags now",
    action = "refresh",
  },
  {
    kind = "button",
    label = "Survey bags",
    button = "Survey",
    tooltip = "List bag consumables and their macro match",
    action = "survey",
  },
}

-- Validity predicate. The whole job is one secure hook onto the cooldown
-- viewer's buff-bar items; without hooksecurefunc nothing here can act,
-- so the module is never initialized and never listed (principle 12).
function bars.IsAvailable()
  return type(hooksecurefunc) == "function"
end

local frame = CreateFrame("Frame")
bars.frame = frame

frame:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" and addon == "Blizzard_CooldownViewer" then
    bars.InstallHook()
  end
end)

-- Install the one hook, once, whenever the viewer addon loads. Acquire
-- ordering never matters: the hook re-applies on every buff-bar update,
-- so items acquired before it still restyle on their next frame.
function bars.InstallHook()
  if bars.hooked then
    return true
  end
  if type(hooksecurefunc) ~= "function" then
    return false
  end
  local mixin = CooldownViewerBuffBarItemMixin
  if type(mixin) ~= "table" or type(mixin.RefreshCooldownInfo) ~= "function" then
    return false
  end
  hooksecurefunc(mixin, "RefreshCooldownInfo", bars.OnBarCooldown)
  bars.hooked = true
  return true
end

-- Toggle the module: the setting applies live, the checkbox sound
-- confirms, and the fill restores itself through the hook, so nothing
-- foreign lingers while off.
function bars.SetEnabled(on)
  ns.config.Set(bars.SECTION, "enabled", on)
  ns.play(on and "on" or "off")
  ns.say("bars module " .. (on and "on" or "off"))
  if bars.ApplyEnabledImpl then
    bars.ApplyEnabledImpl()
  end
  if bars.ApplyMacrosImpl then
    bars.ApplyMacrosImpl()
  end
  if on and bars.ResyncMacros then
    bars.ResyncMacros()
  end
end

function bars.ToggleEnabled()
  bars.SetEnabled(not bars.opts().enabled)
end

-- The Impl hooks the descriptor delegates to: the load waiter registers
-- or unregisters with the toggle, and enabling late-installs the hook
-- when the viewer already loaded first.
function bars.ApplyEnabledImpl()
  if bars.opts().enabled then
    frame:RegisterEvent("ADDON_LOADED")
    bars.InstallHook()
  else
    frame:UnregisterEvent("ADDON_LOADED")
  end
end

function bars.InitImpl()
  bars.ApplyEnabledImpl()
  if bars.InitMacrosImpl then
    bars.InitMacrosImpl()
  end
end

function bars.Slash(rest)
  local cmd = (rest or ""):match("^(%S*)") or ""
  if cmd == "" then
    bars.ToggleEnabled()
  elseif cmd == "on" then
    bars.SetEnabled(true)
  elseif cmd == "off" then
    bars.SetEnabled(false)
  elseif cmd == "refresh" then
    if bars.RefreshMacrosImpl then
      bars.RefreshMacrosImpl()
    end
  elseif cmd == "survey" then
    if bars.SurveyImpl then
      bars.SurveyImpl()
    end
  else
    ns.help()
  end
end

-- The descriptor loads first; the job files below fill in the Impl
-- functions it delegates to, so registration never waits on them.
local descriptor = {
  name = "bars",
  title = "Bars",
  job = "Grows cooldown buff bars from the center and keeps food, drink and potion macros pointed at the best in bags",
  default = true,
  IsAvailable = bars.IsAvailable,
  init = function()
    if bars.InitImpl then
      bars.InitImpl()
    end
  end,
  BuildPanel = function(page)
    if bars.BuildPanelImpl then
      bars.BuildPanelImpl(page)
    end
  end,
  Slash = bars.Slash,
}
bars.descriptor = descriptor
ns.modules.Register(descriptor)

-- Help lines for this module's subcommands, first among the modules so
-- the house grammar (config second to last, help last) still holds.
do
  local lines = {
    "/vui bars          turn the bars module on or off",
    "/vui bars on|off   turn the bars module on or off",
    "/vui bars refresh   point the macros at the best in bags now",
    "/vui bars survey    list bag consumables and their macro match",
  }
  local at = #ns.HELP - 2 -- ahead of the config line (second to last)
  for i, line in ipairs(lines) do
    table.insert(ns.HELP, at + i, line)
  end
end
