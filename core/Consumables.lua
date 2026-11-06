local _, ns = ...
local consumables = {}
ns.consumables = consumables

-- Best in bags for consumables: the shared evaluation behind the
-- bars macros and the vendor surplus ask (Principles #11: the second
-- module with the need moved it here, and bars migrated to it).
-- Stateless: every call walks the bags fresh and returns new tables.
-- Item classes live in the generated docs:
-- Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- ItemConstantsDocumentation.lua, Enum.ItemClass.Consumable = 0,
-- Enum.ItemConsumableSubclass Potion = 1 and Fooddrink = 5.

consumables.CONSUMABLE_CLASS = 0
consumables.SUBCLASS_POTION = 1
consumables.SUBCLASS_FOODDRINK = 5

-- Category words, matched case-insensitively against the item's spell
-- name plus its item name. Seeded from the classic consumable pool;
-- "/vui bars survey" prints the exact fields behind every match, so
-- this table is corrected from observed bags, never from memory.
consumables.CATEGORY_WORDS = {
  food = {
    "food",
    "bread",
    "roll",
    "cake",
    "pie",
    "meat",
    "ham",
    "cheese",
    "fish",
    "clam",
    "crab",
    "soup",
    "stew",
    "sausage",
    "roast",
    "pork",
    "beef",
    "chicken",
    "egg",
    "apple",
    "melon",
    "berry",
    "grain",
    "loaf",
    "biscuit",
    "cookie",
    "muffin",
    "tart",
    "jerky",
    "fillet",
    "chops",
    "kebab",
    "omelet",
  },
  drink = {
    "drink",
    "water",
    "juice",
    "milk",
    "tea",
    "coffee",
    "nectar",
    "dew",
    "brew",
    "nog",
    "punch",
  },
  health = { "heal" },
  mana = { "mana" },
}

local function playerLevel()
  if type(UnitLevel) ~= "function" then
    return nil
  end
  local ok, level = pcall(UnitLevel, "player")
  if ok and type(level) == "number" then
    return level
  end
  return nil
end

-- Full item facts for one bag link, or nil when the item cache cannot
-- answer yet. An uncached answer is unsure, never a verdict: the
-- caller skips the link and GET_ITEM_INFO_RECEIVED retries it.
function consumables.ItemFacts(link)
  if type(link) ~= "string" then
    return nil
  end
  if type(C_Item) ~= "table" or type(C_Item.GetItemInfo) ~= "function" then
    return nil
  end
  local ok, name, _, _, itemLevel, minLevel, _, subType, _, _, icon, _, classID, subclassID =
    pcall(C_Item.GetItemInfo, link)
  if not ok or type(name) ~= "string" or type(classID) ~= "number" or type(subclassID) ~= "number" then
    return nil
  end
  local spellName = nil
  if type(C_Item.GetItemSpell) == "function" then
    local okSpell, got = pcall(C_Item.GetItemSpell, link)
    if okSpell and type(got) == "string" then
      spellName = got
    end
  end
  return {
    name = name,
    itemLevel = itemLevel,
    minLevel = minLevel,
    subType = subType,
    icon = icon,
    classID = classID,
    subclassID = subclassID,
    spell = spellName,
    link = link,
  }
end

local function hasWord(text, words)
  for _, word in ipairs(words) do
    if text:find(word, 1, true) then
      return true
    end
  end
  return false
end

-- One of "food", "drink", "health", "mana", or nil. Only the potion
-- and food-and-drink subclasses can match, so elixirs, flasks,
-- bandages, and scrolls never categorize. An item matching both
-- halves of a split matches neither: a miscategorized verdict is
-- worse than none, and the survey names it for the word table.
function consumables.CategoryOf(facts)
  if type(facts) ~= "table" or facts.classID ~= consumables.CONSUMABLE_CLASS then
    return nil
  end
  local text = ((facts.spell or "") .. " " .. facts.name):lower()
  if facts.subclassID == consumables.SUBCLASS_POTION then
    local heal = hasWord(text, consumables.CATEGORY_WORDS.health)
    local mana = hasWord(text, consumables.CATEGORY_WORDS.mana)
    if mana and not heal then
      return "mana"
    end
    if heal and not mana then
      return "health"
    end
    return nil
  end
  if facts.subclassID == consumables.SUBCLASS_FOODDRINK then
    if hasWord(text, consumables.CATEGORY_WORDS.drink) and not hasWord(text, consumables.CATEGORY_WORDS.food) then
      return "drink"
    end
    return "food"
  end
  return nil
end

-- Highest usable level wins; ties break toward the higher item level,
-- then the earlier name, so the pick is deterministic bag to bag.
function consumables.RanksAbove(a, b)
  if a.minLevel ~= b.minLevel then
    return a.minLevel > b.minLevel
  end
  local ai = a.itemLevel or 0
  local bi = b.itemLevel or 0
  if ai ~= bi then
    return ai > bi
  end
  return a.name < b.name
end

-- Every bag link through one callback: the Syndicator cache when it
-- is present and settled (it already walked the bags for Baganator),
-- else the Blizzard bag walk. fn(link) runs per link; returning true
-- stops a Blizzard walk early.
function consumables.EachLink(fn)
  if type(fn) ~= "function" then
    return
  end
  if not (ns.inventory and type(ns.inventory.BagLinks) == "function") then
    return
  end
  local links = ns.inventory.BagLinks()
  if links then
    for _, link in ipairs(links) do
      if type(link) == "string" then
        fn(link)
      end
    end
    return
  end
  if type(ns.inventory.EachSlot) == "function" then
    ns.inventory.EachSlot(function(_, _, _, link)
      if type(link) == "string" then
        return fn(link)
      end
      return false
    end)
  end
end

-- The best usable facts per category key. Items above the player's
-- level never win; an unknown player level fails open. Uncached links
-- are skipped for the next item-info event, never guessed at.
function consumables.CollectBest()
  local best = {}
  local level = playerLevel()
  consumables.EachLink(function(link)
    local facts = consumables.ItemFacts(link)
    if not facts then
      return false
    end
    if facts.classID ~= consumables.CONSUMABLE_CLASS then
      return false
    end
    if facts.subclassID ~= consumables.SUBCLASS_POTION and facts.subclassID ~= consumables.SUBCLASS_FOODDRINK then
      return false
    end
    if type(facts.minLevel) ~= "number" then
      return false
    end
    if level ~= nil and facts.minLevel > level then
      return false
    end
    local cat = consumables.CategoryOf(facts)
    if not cat then
      return false
    end
    if best[cat] == nil or consumables.RanksAbove(facts, best[cat]) then
      best[cat] = facts
    end
    return false
  end)
  return best
end
