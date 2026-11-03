local _, ns = ...
local prices = {}
ns.prices = prices

-- Guest price data. Auctionator is the auction source (verified
-- against the installed Auctionator 341 source on the Forever client:
-- Source/API/v1, whose README marks the v1 surface stable); vendor
-- price is the fallback every item carries. Like every guest call in
-- this package, reads are presence-gated and pcall-guarded: no
-- Auctionator, no scanned price, or a broken neighbor answers nil and
-- the caller simply shows nothing. Queries only; VocUI never posts,
-- searches, or writes a shopping list through this service.

local CALLER = "VocUI"

local function v1()
  if type(Auctionator) ~= "table" then
    return nil
  end
  if type(Auctionator.API) ~= "table" then
    return nil
  end
  if type(Auctionator.API.v1) ~= "table" then
    return nil
  end
  return Auctionator.API.v1
end

local function positive(value)
  if type(value) == "number" and value > 0 then
    return value
  end
  return nil
end

-- Last scanned auction price for a link, in copper, or nil.
function prices.AuctionPrice(link)
  local api = v1()
  if not api or type(link) ~= "string" then
    return nil
  end
  if type(api.GetAuctionPriceByItemLink) ~= "function" then
    return nil
  end
  local ok, price = pcall(api.GetAuctionPriceByItemLink, CALLER, link)
  if not ok then
    return nil
  end
  return positive(price)
end

-- Vendor sell price for a link, in copper, or nil. Auctionator's
-- vendor cache answers first when present; the item's own vendor
-- price (C_Item.GetItemInfo, 11th return) is the fallback.
function prices.VendorPrice(link)
  if type(link) ~= "string" then
    return nil
  end
  local api = v1()
  if api and type(api.GetVendorPriceByItemLink) == "function" then
    local ok, price = pcall(api.GetVendorPriceByItemLink, CALLER, link)
    if ok and positive(price) then
      return price
    end
  end
  if type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
    local ok, price = pcall(function()
      return select(11, C_Item.GetItemInfo(link))
    end)
    if ok then
      return positive(price)
    end
  end
  return nil
end

-- "12g 34s" for a copper amount (zero parts omitted), or nil when
-- there is no price worth printing.
function prices.Label(copper)
  if not positive(copper) then
    return nil
  end
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local cop = copper % 100
  local parts = {}
  if gold > 0 then
    parts[#parts + 1] = gold .. "g"
  end
  if silver > 0 then
    parts[#parts + 1] = silver .. "s"
  end
  if cop > 0 or #parts == 0 then
    parts[#parts + 1] = cop .. "c"
  end
  return table.concat(parts, " ")
end

-- The value suffix a readout appends for an item: auction value when
-- Auctionator knows one, vendor value otherwise, nothing when neither
-- does. Returns "" or " (auction 12g 34s)" / " (vendor 5s)".
function prices.Suffix(link)
  local auction = prices.AuctionPrice(link)
  if auction then
    local label = prices.Label(auction)
    if label then
      return " (auction " .. label .. ")"
    end
  end
  local vendor = prices.VendorPrice(link)
  if vendor then
    local label = prices.Label(vendor)
    if label then
      return " (vendor " .. label .. ")"
    end
  end
  return ""
end
