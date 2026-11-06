local _, ns = ...
local vendor = ns.vendor

-- Junk: poor quality (0) and nothing else, ever. The scan walks the
-- bags once through the shared inventory service; unknown quality is
-- skipped, never guessed. Guests are never requirements: a missing
-- guest only changes which read supplies the same answer.

-- One junk line: the link and its vendor value in copper.
local function junkLine(link)
  if type(link) ~= "string" then
    return nil
  end
  if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then
    return nil
  end
  local quality = select(3, C_Item.GetItemInfo(link))
  if quality ~= 0 then
    return nil
  end
  local value = ns.prices.VendorPrice(link)
  if value == nil then
    value = 0
  end
  return { link = link, value = value }
end

-- The junk list: one walk over the bags through the shared
-- inventory service, which reads the guest bag index when one is
-- settled and walks Blizzard's containers otherwise.
function vendor.ScanJunk()
  local found = {}
  local function collect(link)
    local line = junkLine(link)
    if line ~= nil then
      found[#found + 1] = line
    end
  end
  local links = ns.inventory.BagLinks()
  if type(links) == "table" then
    for _, link in ipairs(links) do
      collect(link)
    end
    return found
  end
  ns.inventory.EachSlot(function(bag, slot, info, link)
    collect(link)
    return false
  end)
  return found
end

function vendor.JunkTotal(found)
  local total = 0
  for _, line in ipairs(found) do
    if type(line.value) == "number" then
      total = total + line.value
    end
  end
  return total
end

-- Auction context for one audit line, and nothing else: the sell
-- price already names the vendor value, so only an Auctionator value
-- earns a mention. The guest never decides, it only annotates.
local function auctionNote(link)
  local auction = ns.prices.AuctionPrice(link)
  if auction == nil then
    return ""
  end
  local label = ns.prices.Label(auction)
  if label == nil then
    return ""
  end
  return " (auction " .. label .. ")"
end

-- Audit: report what would be sold, sell nothing. Each line names the
-- item and its vendor price, with the Auctionator value beside it
-- when the guest knows one; the sell decision itself never depends on
-- the guest, so the audit context cannot leak into it.
function vendor.AuditReport(found)
  for _, line in ipairs(found) do
    local price = ns.prices.Label(line.value) or "0c"
    ns.say("audit: would sell " .. line.link .. " for " .. price .. auctionNote(line.link))
  end
  local total = ns.prices.Label(vendor.JunkTotal(found)) or "0c"
  ns.say("audit: " .. #found .. " items for " .. total)
end

-- The bulk sale: Blizzard's own junk call, the same one the Sell Junk
-- button makes, so junk means what the client means by it. The
-- module only invokes it after its own scan found poor-quality
-- items, and the total comes from the money delta around the call.
-- A missing bulk call is never an error: the visit just ends.
function vendor.SellNow(found)
  if #found == 0 then
    return false
  end
  if type(C_MerchantFrame) ~= "table" then
    return false
  end
  local M = C_MerchantFrame
  if type(M.SellAllJunkItems) ~= "function" or type(GetMoney) ~= "function" then
    return false
  end
  if type(M.IsSellAllJunkEnabled) == "function" then
    local okEnabled, enabled = pcall(M.IsSellAllJunkEnabled)
    if okEnabled and not enabled then
      return false
    end
  end
  local before = GetMoney()
  local ok = pcall(M.SellAllJunkItems)
  if not ok or type(GetMoney) ~= "function" then
    return false
  end
  local earned = GetMoney() - before
  if type(before) ~= "number" or type(earned) ~= "number" or earned <= 0 then
    return false
  end
  ns.say("sold junk for " .. ns.prices.Label(earned))
  return true
end

-- One merchant visit: sell, then ask about surplus, then repair. Combat gates everything;
-- the close event only drops the open flag the confirmed sale
-- rechecks before every slot.
function vendor.OnMerchant()
  if not vendor.opts().enabled then
    return
  end
  vendor.merchantOpen = true
  if ns.combat() then
    return
  end
  local o = vendor.opts()
  if o.sellJunk then
    local found = vendor.ScanJunk()
    if o.audit then
      if #found > 0 then
        vendor.AuditReport(found)
      end
    else
      vendor.SellNow(found)
    end
  end
  if o.surplus then
    local extra = vendor.ScanSurplus()
    if #extra > 0 then
      if o.audit then
        vendor.SurplusAudit(extra)
      else
        vendor.AskSurplus(extra)
      end
    end
  end
  if o.autoRepair then
    vendor.RepairNow()
  end
end
