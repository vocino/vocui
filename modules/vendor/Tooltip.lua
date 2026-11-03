local _, ns = ...
local vendor = ns.vendor

-- The vendor line: "Vendor: <price>" on item tooltips that show a
-- sell price and do not already show one. Auctionator writes its own
-- price lines into tooltips, and the client writes its own Sell
-- Price line, so the module scans the tooltip first and adds nothing
-- when a vendor line of any origin is present. Hooks install once
-- per session through hooksecurefunc (ledgered) and every handler
-- re-checks the option, so turning the row off takes effect without
-- unhooking anything.

vendor.tooltipHooked = false

-- A vendor line already on the tooltip: ours ("Vendor: ..."),
-- Auctionator's (same shape), or the client's own Sell Price line,
-- matched by the client's own label when readable.
local function nativeSellLabel()
  if type(SELL_PRICE) == "string" and SELL_PRICE ~= "" then
    return SELL_PRICE
  end
  return nil
end

function vendor.TooltipHasPrice(tip)
  if type(tip) ~= "table" then
    return false
  end
  if type(tip.NumLines) ~= "function" or type(tip.GetLeftLine) ~= "function" then
    return false
  end
  local ok, count = pcall(tip.NumLines, tip)
  if not ok or type(count) ~= "number" then
    return false
  end
  local sellLabel = nativeSellLabel()
  for i = 1, count do
    local okLine, left = pcall(tip.GetLeftLine, tip, i)
    if okLine and type(left) == "table" and type(left.GetText) == "function" then
      local okText, text = pcall(left.GetText, left)
      if okText and type(text) == "string" then
        if text:sub(1, 7) == "Vendor:" then
          return true
        end
        if sellLabel ~= nil and text:sub(1, #sellLabel) == sellLabel then
          return true
        end
      end
    end
  end
  return false
end

-- Add the line for a link with a sell price, unless the tooltip
-- already shows one. The sell price comes from the client's item
-- data, never from a guest: the decision is vendor value or nothing.
function vendor.MaybeAddPrice(tip, link)
  if not vendor.opts().tooltipPrice then
    return false
  end
  if type(tip) ~= "table" or type(tip.AddLine) ~= "function" then
    return false
  end
  if type(link) ~= "string" then
    return false
  end
  local value = ns.prices.VendorPrice(link)
  if value == nil or value <= 0 then
    return false
  end
  if vendor.TooltipHasPrice(tip) then
    return false
  end
  local c = ns.COLORS
  pcall(tip.AddLine, tip, "Vendor: " .. ns.prices.Label(value), c.text[1], c.text[2], c.text[3])
  return true
end

local function linkForBag(bag, slot)
  if type(C_Container) ~= "table" or type(C_Container.GetContainerItemLink) ~= "function" then
    return nil
  end
  local ok, link = pcall(C_Container.GetContainerItemLink, bag, slot)
  if ok and type(link) == "string" then
    return link
  end
  return nil
end

local function linkForInventory(unit, slot)
  if type(GetInventoryItemLink) ~= "function" then
    return nil
  end
  local ok, link = pcall(GetInventoryItemLink, unit, slot)
  if ok and type(link) == "string" then
    return link
  end
  return nil
end

-- One hook per setter, each verified on the Forever branch through
-- Blizzard's own use: SetBagItem (Camelot BankFrame, Mainline
-- ContainerFrame), SetInventoryItem (BankFrame), SetHyperlink
-- (DressUpFrames, GroupLootFrame, ItemRef). Installing twice would
-- double every line, so the flag guards it.
function vendor.InstallTooltip()
  if vendor.tooltipHooked then
    return
  end
  if type(hooksecurefunc) ~= "function" then
    return
  end
  if type(GameTooltip) ~= "table" then
    return
  end
  pcall(hooksecurefunc, GameTooltip, "SetBagItem", function(tip, bag, slot)
    vendor.MaybeAddPrice(tip, linkForBag(bag, slot))
  end)
  pcall(hooksecurefunc, GameTooltip, "SetInventoryItem", function(tip, unit, slot)
    vendor.MaybeAddPrice(tip, linkForInventory(unit, slot))
  end)
  pcall(hooksecurefunc, GameTooltip, "SetHyperlink", function(tip, link)
    vendor.MaybeAddPrice(tip, link)
  end)
  vendor.tooltipHooked = true
end
