local _, ns = ...

-- Combat as the client enforces it, not just the UI lockdown: on pull
-- frames the unit already reads in-combat while InCombatLockdown still
-- returns false, and the client answers a forbidden action in that
-- window with ADDON_ACTION_FORBIDDEN. Every module that refuses to
-- act in combat shares this one read. Presence-gated and fail-open.
function ns.combat()
  if type(InCombatLockdown) == "function" and InCombatLockdown() then
    return true
  end
  if type(UnitAffectingCombat) == "function" then
    local ok, fighting = pcall(UnitAffectingCombat, "player")
    if ok and fighting then
      return true
    end
  end
  return false
end
