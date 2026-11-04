local _, ns = ...
local xp = ns.xp

-- Bonus registry: the effects on the Forever client that change kill-XP
-- gain, one entry per effect. Each entry names the effect, what it grants,
-- and where it comes from, in the player's terms, plus the aura that marks
-- it live and how to spot its granting item in the bags. Only Forever-
-- verified effects get entries: Well Fed is the first, the food buff that
-- raises kill XP. A short registry that is right beats a long one that is
-- guessed, so the retail guesses are gone outright: War Mode, Mentored,
-- and the Faire and Wickerman auras are unconfirmed on Forever (spell
-- 24705 is the stamina-regen Invocation on Era-line data, not Grim
-- Visage), and Joyous Journeys is Era-excluded by Blizzard's own notice.
-- Combat buffs stay out even when they share a source: Sayge's Faire
-- fortunes are damage and resistance, not XP. Eating does not feed rested
-- on Era-line data (Food restores health, Well Fed adds stamina and
-- spirit, rested accrues in rest areas), so no bonus touches rested; the
-- bar's own reach lines already report it.
xp.REGISTRY = {
  {
    aura = 24870, -- Well Fed, the eat-triggered food aura (Wowhead Era lead: classic spell 24870)
    label = "Well Fed",
    grant = "kill XP",
    source = "food",
    food = true, -- any food item grants it; the bag hint looks for food, not one item
  },
}

function xp.playerAura(spellID)
  if type(C_UnitAuras) ~= "table" then
    return nil
  end
  if type(C_UnitAuras.GetPlayerAuraBySpellID) ~= "function" then
    return nil
  end
  return C_UnitAuras.GetPlayerAuraBySpellID(spellID)
end

function xp.hasAura(spellID)
  return xp.playerAura(spellID) ~= nil
end

-- Remaining time on a live aura, in seconds, or nil when the client does
-- not report one. Blizzard's own BuffFrame reads auraData.expirationTime
-- against GetTime() the same way (forever branch, BuffFrame.lua); a
-- missing aura, a missing field, a missing clock, or an expired stamp all
-- read no time, never an error. The stamp can also arrive secret,
-- and a secret errors on compare and arithmetic in addon code:
-- canaccessvalue gates both, presence-gated like every other read.
function xp.auraTimeLeft(spellID)
  local aura = xp.playerAura(spellID)
  if type(aura) ~= "table" then
    return nil
  end
  local expires = aura.expirationTime
  if canaccessvalue and not canaccessvalue(expires) then
    return nil
  end
  if type(expires) ~= "number" or expires <= 0 then
    return nil
  end
  if type(GetTime) ~= "function" then
    return nil
  end
  local left = expires - GetTime()
  if type(left) ~= "number" or left <= 0 then
    return nil
  end
  return left
end

-- Food in the player's bags, through the core's inventory service and its
-- guests: the guest cache first (it already walked the bags for Baganator),
-- else the core's Blizzard walk, the same order the gear module reads. No
-- bag walk of our own. Without either source the hint simply stays off.
-- Consumable class 0, Food & Drink subclass 5, both from the forever
-- branch's own ItemConstantsDocumentation; GetItemInfoInstant is the
-- ledger-verified read.
xp.FOOD_CLASS = 0
xp.FOOD_SUBCLASS = 5

local function isFoodLink(link)
  if type(link) ~= "string" then
    return false
  end
  if type(C_Item) ~= "table" or type(C_Item.GetItemInfoInstant) ~= "function" then
    return false
  end
  local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, link)
  return ok and classID == xp.FOOD_CLASS and subClassID == xp.FOOD_SUBCLASS
end

function xp.foodInBags()
  local inv = ns.inventory
  if type(inv) ~= "table" then
    return false
  end
  if type(inv.BagLinks) == "function" then
    local links = inv.BagLinks()
    if type(links) == "table" then
      for _, link in ipairs(links) do
        if isFoodLink(link) then
          return true
        end
      end
      return false
    end
  end
  local found = false
  if type(inv.EachSlot) == "function" then
    inv.EachSlot(function(_, _, _, link)
      if isFoodLink(link) then
        found = true
        return true
      end
      return false
    end)
  end
  return found
end

-- Aura reads go blind in instances: the API returns nil there for
-- present world-granted buffs, so the registry scan gates on this and
-- says so instead of false absence.
function xp.inInstance()
  if type(IsInInstance) ~= "function" then
    return false
  end
  return IsInInstance() == true
end

-- Highest value first; lines without a number trail in insertion
-- order, so the sort is stable. Shared by the active and missing lists.
local function sortByValue(parts)
  table.sort(parts, function(a, b)
    if (a.pct or -1) ~= (b.pct or -1) then
      return (a.pct or -1) > (b.pct or -1)
    end
    return a.seq < b.seq
  end)
end

local function bonusLabels(parts)
  sortByValue(parts)
  local labels = {}
  for _, p in ipairs(parts) do
    labels[#labels + 1] = p.label
  end
  return labels
end

-- Rep buffs, unchanged: reputation bonuses at max level are outside this
-- extension's scope, so the rep side keeps the list it already had.
xp.REP_BUFFS = {
  { id = 46668, label = "+10% WHEE!", pct = 10 },
  { id = 136583, label = "+10% Darkmoon Top Hat", pct = 10 },
  { id = 24705, label = "+10% Grim Visage", pct = 10 },
  { id = 95987, label = "+10% Unburdened", pct = 10 },
  { id = 61849, label = "+10% Spirit of Sharing", pct = 10 },
}

-- Bonus lines, highest value first. Leveling lines come from the registry
-- only: one line per live effect, with its remaining time when the client
-- reports one. The bar already shows rested reach, so Rested has no line
-- here; effects the client cannot confirm have no entry at all.
function xp.bonusParts(mode, repBonus)
  local parts = {}
  local function add(pct, label)
    parts[#parts + 1] = { pct = pct, label = label, seq = #parts + 1 }
  end
  if mode == "rep" then
    local restricted = xp.inInstance()
    for _, buff in ipairs(xp.REP_BUFFS) do
      if not restricted and xp.hasAura(buff.id) then
        add(buff.pct, buff.label)
      end
    end
    if repBonus then
      add(nil, "Bonus rep gain")
    end
    return bonusLabels(parts)
  end
  if not xp.inInstance() then
    for _, entry in ipairs(xp.REGISTRY) do
      if xp.hasAura(entry.aura) then
        local left = xp.auraTimeLeft(entry.aura)
        if left then
          add(nil, entry.label .. " · " .. entry.grant .. " (" .. xp.formatEta(left) .. " left)")
        else
          add(nil, entry.label .. " · " .. entry.grant)
        end
      end
    end
  end
  return bonusLabels(parts)
end

-- The missing half of the registry: one dimmed reminder per effect that
-- is not live, naming where it comes from, with the in-bags hint when the
-- granting food sits in the player's bags. No rested line here either;
-- the bar already answers that. In instances the aura scan goes blind, so
-- the scan line replaces the list instead of guessing absence.
function xp.missingParts(mode)
  local parts = {}
  local function add(pct, label)
    parts[#parts + 1] = { pct = pct, label = label, seq = #parts + 1 }
  end
  if mode == "rep" then
    if xp.inInstance() then
      add(nil, "Aura scan unavailable in instances")
    end
    return bonusLabels(parts)
  end
  if xp.inInstance() then
    add(nil, "Aura scan unavailable in instances")
    return bonusLabels(parts)
  end
  local bagged = nil
  for _, entry in ipairs(xp.REGISTRY) do
    if not xp.hasAura(entry.aura) then
      local hint = "eat " .. entry.source
      if entry.food then
        if bagged == nil then
          bagged = xp.foodInBags()
        end
        if bagged then
          hint = entry.source .. " in bags"
        end
      end
      add(nil, entry.label .. " · " .. entry.grant .. " (" .. hint .. ")")
    end
  end
  return bonusLabels(parts)
end
