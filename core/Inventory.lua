local _, ns = ...
local inventory = {}
ns.inventory = inventory

-- Guest inventory data from Syndicator (Baganator's data backend,
-- verified against the installed Syndicator 289 source on the Forever
-- client: API/Main.lua, Tracking/BagCache.lua, Core/Constants.lua).
-- Syndicator already scans and caches every bag item for Baganator, so
-- when it is present and settled, modules read its cache instead of
-- walking bags themselves. It is a guest, never a dependency: every
-- read is presence-gated and pcall-guarded, and a missing, loading, or
-- broken Syndicator answers nil so the caller uses Blizzard's own
-- container APIs. Nothing here writes to Syndicator.

local function api()
  if type(Syndicator) ~= "table" then
    return nil
  end
  if type(Syndicator.API) ~= "table" then
    return nil
  end
  return Syndicator.API
end

-- True when Syndicator is loaded and its tracking data is ready.
function inventory.Available()
  local a = api()
  if not a or type(a.IsReady) ~= "function" then
    return false
  end
  local ok, ready = pcall(a.IsReady)
  return ok and ready == true
end

-- True while Syndicator is still applying a bag update. Callers that
-- need the freshest read (an equip decision) fall back to Blizzard
-- while this is true and use the cache once it settles.
function inventory.Pending()
  local a = api()
  if not a or type(a.IsBagEventPending) ~= "function" then
    return false
  end
  local ok, pending = pcall(a.IsBagEventPending)
  return ok and pending == true
end

-- Item links in the current character's bags (backpack and the four
-- bag slots, Syndicator's AllBagIndexes order), or nil when Syndicator
-- cannot answer. Slot shape per Syndicator 289's BagCache: each bag is
-- an array of slot tables, empty slots bare, items carrying itemLink.
function inventory.BagLinks()
  local a = api()
  if not a then
    return nil
  end
  if not inventory.Available() or inventory.Pending() then
    return nil
  end
  if type(a.GetCurrentCharacter) ~= "function" then
    return nil
  end
  if type(a.GetByCharacterFullName) ~= "function" then
    return nil
  end
  local okName, character = pcall(a.GetCurrentCharacter)
  if not okName or type(character) ~= "string" then
    return nil
  end
  local okData, data = pcall(a.GetByCharacterFullName, character)
  if not okData or type(data) ~= "table" or type(data.bags) ~= "table" then
    return nil
  end
  local links = {}
  -- Syndicator bags[1..5] are Backpack, Bag_1 .. Bag_4; later indexes
  -- (reagent bag, keyring) are outside the bag walk modules replace.
  for index = 1, 5 do
    local bag = data.bags[index]
    if type(bag) == "table" then
      for _, slot in ipairs(bag) do
        if type(slot) == "table" and type(slot.itemLink) == "string" then
          links[#links + 1] = slot.itemLink
        end
      end
    end
  end
  return links
end
