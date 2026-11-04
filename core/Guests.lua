local _, ns = ...
local guests = {}
ns.guests = guests

-- Another addon loaded right now: the guest check every module shares
-- (rival detection, feature detection). Presence-gated and pcall-
-- guarded; a missing API never reads as loaded.
function guests.IsLoaded(addonName)
  if type(addonName) ~= "string" then
    return false
  end
  if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoaded) ~= "function" then
    return false
  end
  local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, addonName)
  return ok and loaded == true
end
