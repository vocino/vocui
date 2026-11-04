local _, ns = ...
local vendor = {}
ns.vendor = vendor

-- Vendor: the merchant visit, automated. Poor-quality items sell the
-- moment the merchant window opens, gear repairs right after, each
-- with one chat line. This is the Forever half of the family addon
-- VocVendor; only its merchant behavior came across, rebuilt under
-- the module contract. Nothing here is retail-only to drop, but the
-- old-gear upgrading, expansion handling, disenchanting, and the
-- Sell Junk button hook stayed behind: this module sells junk and
-- repairs, nothing else.

vendor.SECTION = "modules.vendor"

-- Defaults are the product: the module ships set up the way its
-- player plays. Audit stays off: selling is the one irreversible
-- action in the package, so silence-until-asked is the shelf state.
vendor.defaults = {
  enabled = true,
  sellJunk = true,
  autoRepair = true,
  guildFunds = true,
  audit = false,
  tooltipPrice = true,
}

-- The live state table: VocUIDB.modules.vendor and nowhere else.
function vendor.opts()
  return ns.config.Section(vendor.SECTION, vendor.defaults)
end

-- Declarative option rows for the module's settings page (CRAFT:
-- settings are data). Pause and reset have no meaning at a vendor
-- visit, so they do not exist here at all.
vendor.OPTIONS = {
  {
    key = "enabled",
    kind = "checkbox",
    label = "Sell and repair at vendors",
    tooltip = "Sell junk and repair automatically at vendors",
  },
  {
    kind = "header",
    label = "At the merchant",
  },
  {
    key = "sellJunk",
    kind = "checkbox",
    label = "Sell junk",
    tooltip = "Sell poor-quality items when a merchant window opens",
  },
  {
    key = "autoRepair",
    kind = "checkbox",
    label = "Repair gear",
    tooltip = "Repair all items when a merchant window opens",
  },
  {
    key = "guildFunds",
    kind = "checkbox",
    label = "Guild funds first",
    tooltip = "Use guild repairs when allowed before personal funds",
  },
  {
    kind = "header",
    label = "Reporting",
  },
  {
    key = "audit",
    kind = "checkbox",
    label = "Audit mode",
    tooltip = "Report what would be sold instead of selling",
  },
  {
    key = "tooltipPrice",
    kind = "checkbox",
    label = "Vendor price in tooltips",
    tooltip = "Add a Vendor line to item tooltips missing one",
  },
}

-- Validity predicate. The junk scan walks Blizzard's containers and
-- the bulk sale goes through the merchant namespace; without both,
-- nothing here can act, so the module is never initialized and never
-- listed (principle 12).
function vendor.IsAvailable()
  return type(C_Container) == "table" and type(C_MerchantFrame) == "table"
end

local frame = CreateFrame("Frame")
vendor.frame = frame

frame:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_SHOW" then
    vendor.OnMerchant()
  end
end)

-- Toggle the module: the setting applies live, the checkbox sound
-- confirms, and the merchant event registers or unregisters with it,
-- so nothing runs while off.
function vendor.SetEnabled(on)
  ns.config.Set(vendor.SECTION, "enabled", on)
  ns.play(on and "on" or "off")
  ns.say("vendor module " .. (on and "on" or "off"))
  if vendor.ApplyEnabledImpl then
    vendor.ApplyEnabledImpl()
  end
end

function vendor.ToggleEnabled()
  vendor.SetEnabled(not vendor.opts().enabled)
end

-- The Impl hooks the descriptor delegates to: toggling fully enables
-- or disables the module, so the merchant event registers and
-- unregisters with the toggle and nothing runs while off. Tooltip
-- hooks install once, on init or on first enable of the row.
function vendor.ApplyEnabledImpl()
  if vendor.opts().enabled then
    vendor.frame:RegisterEvent("MERCHANT_SHOW")
  else
    vendor.frame:UnregisterEvent("MERCHANT_SHOW")
  end
end

function vendor.InitImpl()
  vendor.ApplyEnabledImpl()
  if vendor.opts().tooltipPrice then
    vendor.InstallTooltip()
  end
end

function vendor.Slash(rest)
  local cmd = (rest or ""):match("^(%S*)") or ""
  if cmd == "" then
    vendor.ToggleEnabled()
  elseif cmd == "on" then
    vendor.SetEnabled(true)
  elseif cmd == "off" then
    vendor.SetEnabled(false)
  else
    ns.help()
  end
end

-- The descriptor loads first; the job files below fill in the Impl
-- functions it delegates to, so registration never waits on them.
local descriptor = {
  name = "vendor",
  title = "Vendor",
  job = "Sells junk and repairs gear automatically whenever the player visits a vendor",
  default = true,
  IsAvailable = vendor.IsAvailable,
  init = function()
    if vendor.InitImpl then
      vendor.InitImpl()
    end
  end,
  BuildPanel = function(page)
    if vendor.BuildPanelImpl then
      vendor.BuildPanelImpl(page)
    end
  end,
  Slash = vendor.Slash,
}
vendor.descriptor = descriptor
ns.modules.Register(descriptor)

-- Help lines for this module's subcommands, behind the xp block and
-- ahead of the config/help pair so the family grammar
-- (config second to last, help last) still holds.
do
  local lines = {
    "/vui vendor        turn the vendor module on or off",
    "/vui vendor on|off turn the vendor module on or off",
  }
  local at = #ns.HELP - 2 -- ahead of the config line (second to last)
  for i, line in ipairs(lines) do
    table.insert(ns.HELP, at + i, line)
  end
end
