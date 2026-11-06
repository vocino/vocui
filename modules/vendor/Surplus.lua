local _, ns = ...
local vendor = ns.vendor

-- Surplus: bag consumables worse than the best in their category. The
-- best verdicts come from the core consumables service (the same
-- judgments the bars macros track); this file only finds the losers
-- and, once per merchant visit, asks before selling them. Selling is
-- the one irreversible action in the package (Principles #6), so an
-- empty find, a missing popup, or a declined ask all leave the bags
-- alone, quietly after the first line.

vendor.surplusDeclined = false -- a declined ask stays quiet this session
vendor.surplusPopupSaid = false -- the missing-popup note says once
vendor.merchantOpen = false

-- One surplus line: where the stack sits, what it is, how many, and
-- its per-unit vendor value in copper. Anything unprovable is nil:
-- best stock, an unknown identity, an unusable level, or nothing to
-- gain (a worthless sale still burns a buyback slot).
local function surplusLine(bag, slot, info, link, facts, bestID, level)
  local myID = link:match("item:(%d+)")
  if myID == nil or bestID == nil or myID == bestID then
    return nil
  end
  if type(facts.minLevel) ~= "number" then
    return nil
  end
  if level ~= nil and facts.minLevel > level then
    return nil
  end
  local value = ns.prices.VendorPrice(link)
  if type(value) ~= "number" or value <= 0 then
    return nil
  end
  local count = 1
  if type(info) == "table" and type(info.stackCount) == "number" and info.stackCount >= 1 then
    count = math.floor(info.stackCount)
  end
  return {
    bag = bag,
    slot = slot,
    link = link,
    name = facts.name,
    count = count,
    value = value,
    itemID = myID,
  }
end

-- The surplus list: one walk over the bags through the shared
-- inventory service against the best per category. A category with
-- no best crowns nothing, so its holders are never surplus.
function vendor.ScanSurplus()
  local found = {}
  local svc = ns.consumables
  if not (svc and type(svc.CollectBest) == "function") then
    return found
  end
  if type(svc.ItemFacts) ~= "function" or type(svc.CategoryOf) ~= "function" then
    return found
  end
  if not (ns.inventory and type(ns.inventory.EachSlot) == "function") then
    return found
  end
  local level = nil
  if type(UnitLevel) == "function" then
    local ok, got = pcall(UnitLevel, "player")
    if ok and type(got) == "number" then
      level = got
    end
  end
  local best = svc.CollectBest()
  ns.inventory.EachSlot(function(bag, slot, info, link)
    if type(link) ~= "string" then
      return false
    end
    local facts = svc.ItemFacts(link)
    if not facts then
      return false
    end
    local cat = svc.CategoryOf(facts)
    if not cat then
      return false
    end
    local winner = best[cat]
    if not winner or type(winner.link) ~= "string" then
      return false
    end
    local line = surplusLine(bag, slot, info, link, facts, winner.link:match("item:(%d+)"), level)
    if line ~= nil then
      found[#found + 1] = line
    end
    return false
  end)
  return found
end

function vendor.SurplusTotal(found)
  local total = 0
  for _, line in ipairs(found) do
    if type(line.value) == "number" and type(line.count) == "number" then
      total = total + line.value * line.count
    end
  end
  return total
end

-- The popup text: the question first, then up to six names, then the
-- overflow count. Names are plain text; links never enter a popup.
vendor.SURPLUS_LIST_MAX = 6
function vendor.SurplusText(found, total)
  local label = ns.prices.Label(total) or "0c"
  local lines = {
    "Sell " .. #found .. " worse " .. (#found == 1 and "stack" or "stacks") .. " for " .. label .. "?",
  }
  for i, line in ipairs(found) do
    if i > vendor.SURPLUS_LIST_MAX then
      lines[#lines + 1] = "and " .. (#found - vendor.SURPLUS_LIST_MAX) .. " more"
      break
    end
    local name = type(line.name) == "string" and line.name or line.link
    if type(line.count) == "number" and line.count > 1 then
      name = name .. " x" .. line.count
    end
    lines[#lines + 1] = name
  end
  return table.concat(lines, "\n")
end

-- Audit: report what would be asked about, sell nothing. Same shape
-- as the junk audit: lines with prices, then the count and total.
function vendor.SurplusAudit(found)
  for _, line in ipairs(found) do
    local price = ns.prices.Label(line.value * line.count) or "0c"
    ns.say("audit: would sell " .. line.link .. " for " .. price)
  end
  local total = ns.prices.Label(vendor.SurplusTotal(found)) or "0c"
  ns.say("audit: " .. #found .. " surplus stacks for " .. total)
end

-- A popup system that never showed up says so once, then stays quiet
-- like a decline: the bags are untouched either way.
function vendor.SurplusUnavailable(count)
  if vendor.surplusPopupSaid then
    return false
  end
  vendor.surplusPopupSaid = true
  ns.say("popup unavailable: " .. count .. " worse consumables kept")
  return false
end

-- The ask: Blizzard's own generic confirmation, or nothing. A
-- decline sets the session flag through the cancel callback, so the
-- rest of the visit and the session stay quiet.
function vendor.AskSurplus(found)
  if #found == 0 or vendor.surplusDeclined then
    return false
  end
  if type(StaticPopup_Show) ~= "function" then
    return vendor.SurplusUnavailable(#found)
  end
  if type(StaticPopupDialogs) ~= "table" or StaticPopupDialogs["GENERIC_CONFIRMATION"] == nil then
    return vendor.SurplusUnavailable(#found)
  end
  local text = vendor.SurplusText(found, vendor.SurplusTotal(found))
  local ok = pcall(StaticPopup_Show, "GENERIC_CONFIRMATION", nil, nil, {
    text = text,
    acceptText = "Sell",
    callback = function()
      vendor.SellSurplusNow(found)
    end,
    cancelCallback = function()
      vendor.surplusDeclined = true
    end,
  })
  return ok
end

-- The confirmed sale: revalidate every slot at accept time, because
-- bags shift and merchants close. A slot that no longer holds the
-- listed item is skipped, never guessed; a closed merchant stops the
-- loop instead of eating a potion. Only emptied slots count, and the
-- money delta is the ground truth behind the total.
function vendor.SellSurplusNow(found)
  if not vendor.opts().enabled then
    return false
  end
  if ns.combat() then
    ns.say("in combat: surplus kept")
    return false
  end
  if not vendor.merchantOpen then
    ns.say("merchant closed: surplus kept")
    return false
  end
  if type(C_Container) ~= "table" or type(C_Container.GetContainerItemLink) ~= "function" then
    return false
  end
  if type(C_Container.UseContainerItem) ~= "function" or type(GetMoney) ~= "function" then
    return false
  end
  local before = GetMoney()
  if type(before) ~= "number" then
    return false
  end
  local sold = 0
  for _, line in ipairs(found) do
    if not vendor.merchantOpen then
      break
    end
    local okLink, cur = pcall(C_Container.GetContainerItemLink, line.bag, line.slot)
    local curID = okLink and type(cur) == "string" and cur:match("item:(%d+)") or nil
    if curID ~= nil and curID == line.itemID then
      local okUse = pcall(C_Container.UseContainerItem, line.bag, line.slot)
      if okUse then
        local okAfter, after = pcall(C_Container.GetContainerItemLink, line.bag, line.slot)
        if okAfter and after == nil then
          sold = sold + 1
        end
      end
    end
  end
  local after = GetMoney()
  if type(after) ~= "number" then
    return false
  end
  local earned = after - before
  if earned <= 0 then
    return false
  end
  ns.say("sold " .. sold .. " worse " .. (sold == 1 and "stack" or "stacks") .. " for " .. ns.prices.Label(earned))
  return true
end
