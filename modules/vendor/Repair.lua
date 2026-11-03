local _, ns = ...
local vendor = ns.vendor

-- Repairs: guild funds first when allowed, personal funds otherwise,
-- one line either way. The fund choice is a pure decision so tests
-- can drive it without a merchant: guild when the player is in a
-- guild and guild repair is available and allowed, personal when the
-- bill fits personal funds, short when neither covers it.

-- Guild repair is available and allowed: the player is in a guild
-- and the client says the guild bank can pay.
function vendor.GuildRepairAllowed()
  if type(IsInGuild) == "function" and not IsInGuild() then
    return false
  end
  if type(CanGuildBankRepair) ~= "function" then
    return false
  end
  local ok, allowed = pcall(CanGuildBankRepair)
  return ok and allowed == true
end

function vendor.PersonalMoney()
  if type(GetMoney) ~= "function" then
    return 0
  end
  local ok, money = pcall(GetMoney)
  if not ok or type(money) ~= "number" then
    return 0
  end
  return money
end

-- The fund decision: "guild", "personal", or "short" with the
-- shortfall in copper. The bill must be positive and the merchant
-- must be able to repair at all; anything else is "none", repair
-- nothing and say nothing.
function vendor.DecideFunds(cost, canRepair, guildAllowed, money)
  if type(cost) ~= "number" or cost <= 0 then
    return "none", 0
  end
  if not canRepair then
    return "none", 0
  end
  if guildAllowed then
    return "guild", 0
  end
  if type(money) == "number" and money >= cost then
    return "personal", 0
  end
  return "short", math.max(0, cost - (type(money) == "number" and money or 0))
end

function vendor.ReadBill()
  if type(CanMerchantRepair) == "function" then
    local ok, able = pcall(CanMerchantRepair)
    if ok and not able then
      return nil
    end
  end
  if type(GetRepairAllCost) ~= "function" then
    return nil
  end
  local ok, cost, canRepair = pcall(GetRepairAllCost)
  if not ok then
    return nil
  end
  return cost, canRepair
end

function vendor.DoRepair(useGuild)
  if type(RepairAllItems) ~= "function" then
    return false
  end
  return pcall(RepairAllItems, useGuild and true or false)
end

function vendor.RepairNow()
  local cost, canRepair = vendor.ReadBill()
  local o = vendor.opts()
  local guildAllowed = o.guildFunds and vendor.GuildRepairAllowed()
  local where, shortfall = vendor.DecideFunds(cost, canRepair, guildAllowed, vendor.PersonalMoney())
  if where == "none" then
    return false
  end
  if where == "short" then
    ns.say("short " .. ns.prices.Label(shortfall) .. " for repairs")
    return false
  end
  if not vendor.DoRepair(where == "guild") then
    return false
  end
  -- Re-read the bill: only a zeroed bill counts as repaired, never
  -- the repair call returning without error.
  local after = vendor.ReadBill()
  if after ~= nil and after > 0 then
    return false
  end
  if where == "guild" then
    ns.say("repaired for " .. ns.prices.Label(cost) .. " (guild funds)")
  else
    ns.say("repaired for " .. ns.prices.Label(cost))
  end
  return true
end
