local _, ns = ...
local vendor = ns.vendor

-- Baganator junk coin (installed Baganator 839: API/Main.lua): mark
-- poor-quality bag items with the verdict the merchant visit sells by,
-- so the bags show what the visit will do. Display only; the sale
-- itself still happens at the merchant, never from here. Unknown items
-- read as not-junk: a coin must never mark what the visit would skip.
vendor.BAGANATOR_JUNK_ID = "vocui-vendor"

local function bagLink(bag, slot)
  if type(C_Container) ~= "table" or type(C_Container.GetContainerItemLink) ~= "function" then
    return nil
  end
  local ok, link = pcall(C_Container.GetContainerItemLink, bag, slot)
  if ok and type(link) == "string" then
    return link
  end
  return nil
end

local function poorQuality(link)
  if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then
    return nil
  end
  local ok, quality = pcall(function()
    return select(3, C_Item.GetItemInfo(link))
  end)
  if not ok then
    return nil
  end
  return quality
end

function vendor.JunkForBaganator(bag, slot, _, itemLink)
  local o = vendor.opts()
  if not o.enabled or not o.sellJunk then
    return false
  end
  local link = itemLink
  if type(link) ~= "string" then
    link = bagLink(bag, slot)
  end
  if type(link) ~= "string" then
    return false
  end
  return poorQuality(link) == 0
end

-- Offer the verdict to Baganator, now when it is loaded, else when it
-- loads (core guests.WhenLoaded). A missing plugin API only skips.
function vendor.RegisterBaganatorPlugin()
  ns.guests.WhenLoaded("Baganator", function()
    local api = type(Baganator) == "table" and Baganator.API or nil
    if type(api) ~= "table" or type(api.RegisterJunkPlugin) ~= "function" then
      return
    end
    pcall(api.RegisterJunkPlugin, "VocUI Vendor", vendor.BAGANATOR_JUNK_ID, vendor.JunkForBaganator)
  end)
end
