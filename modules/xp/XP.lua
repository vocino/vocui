local _, ns = ...
local xp = {}
ns.xp = xp

-- XP: the leveling readout, rebuilt from the VocXP job under the VocUI
-- module contract. A bar with XP per hour and time to level, rested
-- reach and ready-to-turn-in quest XP overlaid, refreshed every second;
-- at max level the same bar follows reputation instead. Only the
-- Forever behavior came across: the Regalia set is retail-only and does
-- not exist here, so it has no line; War Mode, Mentored, and the event
-- buffs are unconfirmed on Forever, so a lit one shows but none is
-- ever suggested. Detection stays presence-gated throughout: a missing
-- API means a missing overlay, never an error.

xp.SECTION = "modules.xp"

-- Defaults are the product: the module ships set up the way its player
-- plays, and the settings page exists mainly to turn things off.
-- Pause is session-only and lives outside this table on purpose.
xp.defaults = {
  enabled = true,
  announce = true,
  hideDefault = true,
  repMode = true,
  followLatest = false,
  locked = false,
  point = "BOTTOM",
  x = 0,
  y = 100,
  repAnnounced = false,
  barAnnounced = false,
}

-- The live state table: VocUIDB.modules.xp and nowhere else.
function xp.opts()
  return ns.config.Section(xp.SECTION, xp.defaults)
end

-- A hand-edited anchor the client cannot SetPoint to would error on
-- every login; fall back to the default instead of breaking the bar.
local VALID_POINTS = {
  TOPLEFT = true,
  TOP = true,
  TOPRIGHT = true,
  LEFT = true,
  CENTER = true,
  RIGHT = true,
  BOTTOMLEFT = true,
  BOTTOM = true,
  BOTTOMRIGHT = true,
}

function xp.CheckAnchor()
  local o = xp.opts()
  if not VALID_POINTS[o.point] then
    o.point = xp.defaults.point
  end
end

-- Declarative option rows for the module's settings page (CRAFT:
-- settings are data). Pause and reset are session actions, not state,
-- so they stay on the slash line and have no row here.
xp.OPTIONS = {
  {
    key = "enabled",
    kind = "checkbox",
    label = "Show the bar",
    tooltip = "Track XP per hour and time to level, reputation at max level",
  },
  {
    key = "announce",
    kind = "checkbox",
    label = "Chat announcements",
    tooltip = "Say burst gains, rival bars, and first-seen notes in chat",
  },
  {
    key = "hideDefault",
    kind = "checkbox",
    label = "Hide the default bar",
    tooltip = "Hide Blizzard's status bar cluster while the XP bar shows",
  },
  {
    key = "repMode",
    kind = "checkbox",
    label = "Track reputation at max level",
    tooltip = "Follow the watched faction with Rep/hr and time to rank",
  },
  {
    key = "followLatest",
    kind = "checkbox",
    label = "Follow latest reputation gains",
    tooltip = "Track the most recently earned faction, not the watched one",
  },
  {
    key = "locked",
    kind = "checkbox",
    label = "Lock the position",
    tooltip = "Keep the bar where it is. Unlocked, drag it anywhere",
  },
}

-- Validity predicate. XP snapshots come from the unit XP reads; without
-- them there is nothing to track, so the module is never initialized
-- and never listed (principle 12).
function xp.IsAvailable()
  return type(UnitXP) == "function" and type(UnitXPMax) == "function" and type(UnitLevel) == "function"
end

-- Toggle the module: the setting applies live, the checkbox sound
-- confirms, and enabling restarts observation before rescanning.
function xp.SetEnabled(on)
  ns.config.Set(xp.SECTION, "enabled", on)
  ns.play(on and "on" or "off")
  ns.say("xp module " .. (on and "on" or "off"))
  if xp.ApplyEnabledImpl then
    xp.ApplyEnabledImpl()
  end
  if on and xp.CheckNowImpl then
    xp.CheckNowImpl()
  end
end

function xp.ToggleShown()
  xp.SetEnabled(not xp.opts().enabled)
end

function xp.Slash(rest)
  local cmd = (rest or ""):match("^(%S*)") or ""
  if cmd == "" then
    xp.ToggleShown()
  elseif cmd == "on" then
    xp.SetEnabled(true)
  elseif cmd == "off" then
    xp.SetEnabled(false)
  elseif cmd == "lock" then
    if xp.LockImpl then
      xp.LockImpl()
    end
  elseif cmd == "pause" then
    if xp.PauseImpl then
      xp.PauseImpl()
    end
  elseif cmd == "reset" then
    if xp.ResetImpl then
      xp.ResetImpl()
    end
  elseif cmd == "rep" then
    if xp.RepImpl then
      xp.RepImpl()
    end
  else
    ns.help()
  end
end

-- The descriptor loads first; the job files below fill in the Impl
-- functions it delegates to, so registration never waits on them.
local descriptor = {
  name = "xp",
  title = "XP",
  job = "Tracks XP per hour and time to level on its own bar, and reputation at max level",
  default = true,
  IsAvailable = xp.IsAvailable,
  init = function()
    if xp.InitImpl then
      xp.InitImpl()
    end
  end,
  BuildPanel = function(page)
    if xp.BuildPanelImpl then
      xp.BuildPanelImpl(page)
    end
  end,
  Slash = xp.Slash,
}
xp.descriptor = descriptor
ns.modules.Register(descriptor)

-- Help lines for this module's subcommands, inserted behind the gear
-- block and ahead of the config/help pair so the family grammar
-- (config second to last, help last) still holds.
do
  local lines = {
    "/vui xp          show or hide the bar",
    "/vui xp on|off   turn the xp module on or off",
    "/vui xp lock     lock or unlock the position",
    "/vui xp pause     pause or resume tracking",
    "/vui xp reset     restart the session",
    "/vui xp rep      reputation tracking on or off",
  }
  local at = #ns.HELP - 2 -- ahead of the config line (second to last)
  for i, line in ipairs(lines) do
    table.insert(ns.HELP, at + i, line)
  end
end
