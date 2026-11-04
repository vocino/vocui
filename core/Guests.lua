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

-- Run fn once a guest is loaded: now when it already is, else on its
-- ADDON_LOADED. One shared waiter serves every module, so a guest that
-- loads after us still gets its registration. The call never errors:
-- bad arguments or a missing frame API only decline, and a throwing fn
-- is contained, never propagated. Returns true when fn ran or will run.
local pending = {} -- addonName -> array of fns waiting on its load
local waiter = nil -- the one ADDON_LOADED frame, created on first defer

local function ensureWaiter()
  if waiter ~= nil then
    return true
  end
  if type(CreateFrame) ~= "function" then
    return false
  end
  local okFrame, frame = pcall(CreateFrame, "Frame")
  if not okFrame or type(frame) ~= "table" then
    return false
  end
  if type(frame.RegisterEvent) ~= "function" or type(frame.SetScript) ~= "function" then
    return false
  end
  local okEvent = pcall(frame.RegisterEvent, frame, "ADDON_LOADED")
  if not okEvent then
    return false
  end
  local okScript = pcall(frame.SetScript, frame, "OnEvent", function(_, _, name)
    local fns = pending[name]
    pending[name] = nil
    if type(fns) == "table" then
      for _, fn in ipairs(fns) do
        pcall(fn)
      end
    end
  end)
  if not okScript then
    return false
  end
  waiter = frame
  return true
end

function guests.WhenLoaded(addonName, fn)
  if type(addonName) ~= "string" or type(fn) ~= "function" then
    return false
  end
  if guests.IsLoaded(addonName) then
    pcall(fn)
    return true
  end
  if not ensureWaiter() then
    return false
  end
  if pending[addonName] == nil then
    pending[addonName] = {}
  end
  local queue = pending[addonName]
  queue[#queue + 1] = fn
  return true
end
