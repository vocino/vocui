local _, ns = ...
local gear = ns.gear

-- Baganator badges (installed Baganator 839: API/Main.lua): the bags
-- the player actually sees. Registering Gear's own upgrade verdict as
-- Baganator's upgrade plugin keeps the bag badges consistent with what
-- the next scan would equip. A guest, never a requirement: no
-- Baganator, or a broken one, only skips registration. The callback
-- itself never errors and never acts: true when Gear would call the
-- link an upgrade, false when not, nil when nobody can answer yet or
-- the module is off.
gear.BAGANATOR_UPGRADE_ID = "vocui-gear"

function gear.UpgradeForBaganator(itemLink)
  if not gear.opts().enabled then
    return nil
  end
  if type(itemLink) ~= "string" then
    return nil
  end
  local ok, ev = pcall(gear.Evaluate, itemLink)
  if not ok or ev == nil then
    return nil
  end
  if ev.upgrade == true then
    return true
  end
  return false
end

-- Offer the verdict to Baganator, now when it is loaded, else when it
-- loads (core guests.WhenLoaded). Re-registering only overwrites our
-- own id, and a missing plugin API only skips.
function gear.RegisterBaganatorPlugin()
  ns.guests.WhenLoaded("Baganator", function()
    local api = type(Baganator) == "table" and Baganator.API or nil
    if type(api) ~= "table" or type(api.RegisterUpgradePlugin) ~= "function" then
      return
    end
    pcall(api.RegisterUpgradePlugin, "VocUI Gear", gear.BAGANATOR_UPGRADE_ID, gear.UpgradeForBaganator)
  end)
end
