local _, ns = ...
local gear = ns.gear

-- Upgrade judgment: pure item level. There is no weight path to
-- consult, so this file is the whole verdict: an item level
-- comparison against what is worn,
-- behind the usability gates below. Result shape:
--   nil when unsure (data uncached or erroring), else
--   { upgrade=bool, ilvl=bool, ilvlDiff=n|nil, itemLevel=n|nil }

-- True when the link is not equipment at all. C_Item.IsEquippableItem
-- answers whether the item goes in an equipment slot; it does not check
-- class proficiency, so shields get their own gate below. Only an
-- explicit no blocks: a missing API or a hiccup fails open.
function gear.Unusable(link)
  if type(C_Item) ~= "table" or type(C_Item.IsEquippableItem) ~= "function" then
    return false
  end
  local ok, equippable = pcall(C_Item.IsEquippableItem, link)
  if not ok then
    return false
  end
  return equippable == false
end

-- Poor (grey) items are vendor trash: no stats worth wearing, so they
-- never displace worn gear. An empty slot takes anything, though, so a
-- confirmed empty home slot is an exception. Enum.ItemQuality.Poor = 0.
gear.POOR_RARITY = 0
gear.HEIRLOOM_RARITY = 7 -- Enum.ItemQuality.Heirloom

function gear.EmptyHome(link)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  if not equipLoc or equipLoc == "" then
    return false
  end
  local pair = gear.slotPairs[equipLoc]
  if pair then
    for _, slotID in ipairs(pair) do
      if GetInventoryItemLink("player", slotID) == nil then
        return true
      end
    end
    return false
  end
  local slotID = gear.HomeSlot(equipLoc)
  if not slotID then
    return false
  end
  return GetInventoryItemLink("player", slotID) == nil
end

-- Shield proficiency by class: warrior, paladin, shaman. The client
-- offers no proficiency query, so the class table is carried here.
gear.SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }
-- Thrown weapons by class: warriors and rogues. The client offers no
-- proficiency query, so the class table is carried here, like shields
-- above. Anything else holding thrown would only send a doomed equip
-- at the client every scan.
gear.THROWN_CLASSES = { WARRIOR = true, ROGUE = true }
function gear.ThrownBlocked(link)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  if equipLoc ~= "INVTYPE_THROWN" then
    return false
  end
  local _, classKey = UnitClass("player")
  return classKey ~= nil and not gear.THROWN_CLASSES[classKey]
end
function gear.ShieldBlocked(link)
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  local isShield = (classID == 4 and subclassID == 6) or equipLoc == "INVTYPE_SHIELD"
  if not isShield then
    return false
  end
  local _, classKey = UnitClass("player")
  return classKey ~= nil and not gear.SHIELD_CLASSES[classKey]
end

-- Cosmetic gear is never an upgrade: shirts and tabards carry no stats,
-- and a fishing pole must never win a weapon slot.
-- Enum.ItemWeaponSubclass.Fishingpole = 20.
gear.COSMETIC_LOCS = { INVTYPE_BODY = true, INVTYPE_TABARD = true }
gear.FISHING_SUBCLASS = 20
-- Container and ammunition slots are never gear: bags, quivers, and
-- ammo carry no stats and no item level, so scoring them only churns
-- the unsure path. Refused outright instead of left unanswered.
gear.NO_SLOT_LOCS = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true }
function gear.NoSlot(link)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  return equipLoc ~= nil and gear.NO_SLOT_LOCS[equipLoc] or false
end
function gear.Cosmetic(link)
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  if equipLoc and gear.COSMETIC_LOCS[equipLoc] then
    return true
  end
  if classID == 2 and subclassID == gear.FISHING_SUBCLASS then
    return true
  end
  return false
end

-- Profession tools are never an upgrade: a skinning knife must never
-- win a weapon slot, whatever its item level. Modern profession
-- equipment (Enum.ItemClass.Profession = 19) is not a weapon at all;
-- classic tool-weapons are weapon-slot items of the Generic weapon
-- subclass (Enum.ItemWeaponSubclass.Generic = 14), statless, and
-- wielding one breaks real weapon abilities.
gear.PROFESSION_CLASS = 19
gear.GENERIC_WEAPON_SUBCLASS = 14
function gear.ProfessionTool(link)
  local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  if classID == gear.PROFESSION_CLASS then
    return true
  end
  if classID == 2 and subclassID == gear.GENERIC_WEAPON_SUBCLASS then
    return true
  end
  return false
end

function gear.Evaluate(link)
  local _, _, rarity, _, minLevel = C_Item.GetItemInfo(link)
  if minLevel and UnitLevel("player") < minLevel then
    return { upgrade = false }
  end
  if gear.Cosmetic(link) then
    return { upgrade = false }
  end
  if gear.ProfessionTool(link) then
    return { upgrade = false }
  end
  if gear.Unusable(link) or gear.ShieldBlocked(link) or gear.ThrownBlocked(link) then
    return { upgrade = false }
  end
  if gear.NoSlot(link) then
    return { upgrade = false }
  end
  if rarity == gear.POOR_RARITY then
    return { upgrade = gear.EmptyHome(link) }
  end
  return gear.EvaluateBuiltin(link)
end

-- Class best armor, Enum.ItemArmorSubclass: Cloth 1, Leather 2,
-- Mail 3, Plate 4.
gear.ARMOR_BEST = {
  WARRIOR = 4,
  PALADIN = 4,
  DEATHKNIGHT = 4,
  HUNTER = 3,
  SHAMAN = 3,
  EVOKER = 3,
  ROGUE = 2,
  MONK = 2,
  DRUID = 2,
  DEMONHUNTER = 2,
  MAGE = 1,
  PRIEST = 1,
  WARLOCK = 1,
}
gear.ARMOR_NONGATED = { [0] = true, [5] = true, [6] = true } -- Generic, Cosmetic, Shield
-- Relic subclasses, Enum.ItemArmorSubclass (verified on the Forever
-- branch): Libram 7, Idol 8, Totem 9, Sigil 10. Each relic answers to
-- one class; the client offers no relic proficiency query, so the
-- class table is carried here, like shields above.
gear.RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN", [10] = "DEATHKNIGHT" }
-- Leveling armor for transitioning classes: hunters and shamans wear
-- leather until 40, warriors and paladins wear mail until 40 (classic
-- rule; best armor unlocks at 40). Below 40 a candidate of the leveling
-- type passes like the best type; the best type itself waits until 40.
gear.ARMOR_LEVELING = { WARRIOR = 3, PALADIN = 3, HUNTER = 2, SHAMAN = 2 }
gear.ARMOR_TRANSITION_LEVEL = 40

-- Armor-type gate. A candidate passes when it matches the class best
-- type (or its pre-40 leveling type), or when it matches what is
-- already worn. Cloaks bypass the gate. Unknown data reads as unsure
-- (nil), never as a yes: a firm answer waits for the item cache.
function gear.ArmorBestBuiltin(link)
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  if equipLoc == "INVTYPE_CLOAK" then
    return true
  end
  if classID == nil or subclassID == nil then
    return nil
  end
  if classID ~= 4 or gear.ARMOR_NONGATED[subclassID] then
    return true
  end
  local _, classKey = UnitClass("player")
  local best = classKey and gear.ARMOR_BEST[classKey]
  local leveling = classKey and gear.ARMOR_LEVELING[classKey]
  local playerLevel = (UnitLevel("player") or 0)
  if best and subclassID == best then
    -- Transitioning classes (hunter, shaman, warrior, paladin) earn
    -- their best armor at the transition level; before that only the
    -- leveling type passes, so a pre-40 mail chest never equips on a
    -- hunter that cannot wear it yet.
    if not leveling or playerLevel >= gear.ARMOR_TRANSITION_LEVEL then
      return true
    end
  end
  if leveling and subclassID == leveling and playerLevel < gear.ARMOR_TRANSITION_LEVEL then
    return true
  end
  -- Relics answer to their class, not to armor weight: a paladin's
  -- libram passes here, a hunter holding one never reaches a verdict.
  local relicClass = classID == 4 and gear.RELIC_CLASS[subclassID] or nil
  if relicClass then
    return classKey == relicClass
  end
  local slotID = equipLoc and gear.primarySlot[equipLoc]
  local held = slotID and GetInventoryItemLink("player", slotID)
  if held then
    local _, _, _, _, _, hClass, hSub = C_Item.GetItemInfoInstant(held)
    if hClass == 4 and hSub == subclassID then
      return true
    end
  end
  return false
end

-- Trash loses ties: a higher-rarity candidate at equal item level
-- displaces grey. Above grey, equal level with different stats is a
-- stat question item level cannot answer, so ties stand.
function gear.RarityBeats(candLink, heldLink)
  if not heldLink then
    return false
  end
  local _, _, candRarity = C_Item.GetItemInfo(candLink)
  local _, _, heldRarity = C_Item.GetItemInfo(heldLink)
  if heldRarity ~= gear.POOR_RARITY then
    return false
  end
  if type(candRarity) ~= "number" then
    return false
  end
  return candRarity > heldRarity
end

function gear.EvaluateBuiltin(link)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  if not equipLoc or equipLoc == "" then
    return nil
  end -- uncached: unsure
  local armorOK = gear.ArmorBestBuiltin(link)
  if armorOK == nil then
    return nil
  end
  if not armorOK then
    return { upgrade = false }
  end
  local candLevel = C_Item.GetDetailedItemLevelInfo(link)
  if not candLevel then
    return nil
  end
  local pair = gear.slotPairs[equipLoc]
  if pair then
    local weakLink, weakLevel
    for _, slotID in ipairs(pair) do
      local held = GetInventoryItemLink("player", slotID)
      if not held then
        return { upgrade = true, ilvl = true, ilvlDiff = candLevel, itemLevel = candLevel }
      end
      local lvl = C_Item.GetDetailedItemLevelInfo(held)
      if lvl and (not weakLevel or lvl < weakLevel) then
        weakLink, weakLevel = held, lvl
      end
    end
    if not weakLevel then
      return nil
    end
    local diff = candLevel - weakLevel
    if diff ~= 0 then
      return { upgrade = diff > 0, ilvl = true, ilvlDiff = diff, itemLevel = candLevel }
    end
    if gear.RarityBeats(link, weakLink) then
      return { upgrade = true, tiebreak = true, ilvlDiff = 0, itemLevel = candLevel }
    end
    return { upgrade = false, ilvl = true, ilvlDiff = 0, itemLevel = candLevel }
  end
  local slotID = gear.HomeSlot(equipLoc)
  if not slotID then
    return { upgrade = false }
  end
  local held = GetInventoryItemLink("player", slotID)
  if not held then
    return { upgrade = true, ilvl = true, ilvlDiff = candLevel, itemLevel = candLevel }
  end
  local heldLevel = C_Item.GetDetailedItemLevelInfo(held)
  if not heldLevel then
    return nil
  end
  local diff = candLevel - heldLevel
  if diff ~= 0 then
    return { upgrade = diff > 0, ilvl = true, ilvlDiff = diff, itemLevel = candLevel }
  end
  if gear.RarityBeats(link, held) then
    return { upgrade = true, tiebreak = true, ilvlDiff = 0, itemLevel = candLevel }
  end
  return { upgrade = false, ilvl = true, ilvlDiff = 0, itemLevel = candLevel }
end

gear.slotPairs = { INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 } }
gear.primarySlot = {
  INVTYPE_HEAD = 1,
  INVTYPE_NECK = 2,
  INVTYPE_SHOULDER = 3,
  INVTYPE_BODY = 4,
  INVTYPE_CHEST = 5,
  INVTYPE_ROBE = 5,
  INVTYPE_WAIST = 6,
  INVTYPE_LEGS = 7,
  INVTYPE_FEET = 8,
  INVTYPE_WRIST = 9,
  INVTYPE_HAND = 10,
  INVTYPE_FINGER = 11,
  INVTYPE_TRINKET = 13,
  INVTYPE_CLOAK = 15,
  INVTYPE_WEAPON = 16,
  INVTYPE_SHIELD = 17,
  INVTYPE_2HWEAPON = 16,
  INVTYPE_WEAPONMAINHAND = 16,
  INVTYPE_RANGED = 16,
  INVTYPE_RANGEDRIGHT = 16,
  INVTYPE_WEAPONOFFHAND = 17,
  INVTYPE_HOLDABLE = 17,
  INVTYPE_TABARD = 19,
}

-- Ranged home slot, per client layout. Forever equips bows, guns, thrown,
-- wands, and relics to a dedicated ranged slot (INVSLOT_RANGED = 18); resolved the
-- way Blizzard character panels do (C_PaperDollInfo.GetInventorySlotInfo,
-- used by the Camelot PaperDollFrame), falling back to the main hand
-- when the client has no ranged slot. Cached: the layout never changes
-- mid-session, and a failed lookup latches instead of retrying.
gear.rangedHomeID = false -- cached slot id, false = not yet resolved
function gear.RangedHome()
  if gear.rangedHomeID == false then
    gear.rangedHomeID = 16
    if type(C_PaperDollInfo) == "table" and type(C_PaperDollInfo.GetInventorySlotInfo) == "function" then
      local ok, id = pcall(C_PaperDollInfo.GetInventorySlotInfo, "RangedSlot")
      if ok and type(id) == "number" then
        gear.rangedHomeID = id
      end
    end
  end
  return gear.rangedHomeID
end

function gear.HomeSlot(equipLoc)
  if equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
    return gear.RangedHome()
  end
  -- Relics share the ranged slot (the Camelot PaperDollFrame paints the
  -- relic texture onto the RangedSlot button for relic classes), and
  -- thrown weapons equip there too.
  if equipLoc == "INVTYPE_RELIC" or equipLoc == "INVTYPE_THROWN" then
    return gear.RangedHome()
  end
  return equipLoc and gear.primarySlot[equipLoc] or nil
end

function gear.IsHeirloom(link)
  if not link then
    return false
  end
  local _, _, rarity = C_Item.GetItemInfo(link)
  return rarity == gear.HEIRLOOM_RARITY
end

function gear.AnnounceHeirloom(link, held)
  local o = gear.opts()
  if o.announce and not gear.flagged[link] then
    gear.flagged[link] = true
    ns.say("keeping heirloom " .. held .. " (" .. link .. " is an upgrade)")
  end
end

-- Weapon-kind gate. A swap across the melee/ranged line can disable a
-- whole action bar (a hunter with a sword), so those swaps announce
-- and are left to the player, both ways. Unknown kinds fail open.
-- Enum.ItemWeaponSubclass: Bows 2, Guns 3, Crossbow 18, Wand 19.
gear.RANGED_SUBCLASS = { [2] = true, [3] = true, [18] = true }
gear.WAND_SUBCLASS = 19
function gear.WeaponKind(link)
  if not link then
    return nil
  end
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  if equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
    if subclassID == gear.WAND_SUBCLASS then
      return "melee"
    end -- wand: main-hand
    return "ranged"
  end
  if
    equipLoc == "INVTYPE_WEAPON"
    or equipLoc == "INVTYPE_WEAPONMAINHAND"
    or equipLoc == "INVTYPE_WEAPONOFFHAND"
    or equipLoc == "INVTYPE_2HWEAPON"
    or equipLoc == "INVTYPE_SHIELD"
    or equipLoc == "INVTYPE_HOLDABLE"
  then
    if classID == 2 and gear.RANGED_SUBCLASS[subclassID] then
      return "ranged"
    end
    return "melee"
  end
  return nil
end

function gear.WeaponKindCrosses(link, held)
  if not held then
    return false
  end
  local cand, cur = gear.WeaponKind(link), gear.WeaponKind(held)
  if not cand or not cur then
    return false
  end
  return cand ~= cur
end

-- Handedness gate. With "Swap weapon types" on, a one-hand/two-hand
-- swap equips flagged as such; with it off the swap is announced
-- instead. Unknown hands fail open.
gear.HAND_1H = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
function gear.Handedness(link)
  if not link then
    return nil
  end
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  if equipLoc == "INVTYPE_2HWEAPON" then
    return "2H"
  end
  if gear.HAND_1H[equipLoc] then
    return "1H"
  end
  return nil
end

function gear.HandCrosses(link, held)
  if not held then
    return false
  end
  local cand, cur = gear.Handedness(link), gear.Handedness(held)
  if not cand or not cur then
    return false
  end
  return cand ~= cur
end

-- Weapon-type gate. With "Swap weapon types" off, a weapon only
-- displaces the same weapon type (same class and subclass). Unknown
-- types fail open.
function gear.WeaponTypeCrosses(link, held)
  if not held then
    return false
  end
  if not gear.WeaponKind(link) or not gear.WeaponKind(held) then
    return false
  end
  local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  local _, _, _, _, _, hClass, hSub = C_Item.GetItemInfoInstant(held)
  if classID == nil or subclassID == nil or hClass == nil or hSub == nil then
    return false
  end
  return classID ~= hClass or subclassID ~= hSub
end

-- Off-hand pairing gate. Equipping an off-hand while a two-hand weapon
-- fills the main hand makes the client drop the two-hander and leaves
-- the main hand empty, so those announce instead.
gear.OFFHAND_LOCS = { INVTYPE_SHIELD = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true }
function gear.OffhandStrands(link)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  if not equipLoc or not gear.OFFHAND_LOCS[equipLoc] then
    return false
  end
  local mh = GetInventoryItemLink("player", 16)
  if not mh then
    return false
  end
  if gear.Handedness(mh) == "2H" then
    return true
  end
  return gear.WeaponKind(mh) == "ranged"
end

-- Set bonus handling, as a gate rather than a weight: with "Prioritize
-- set bonuses" on, a bag piece that completes a bonus equips
-- automatically, and anything that would break an active bonus is
-- announced instead. Breaking a set yourself declines it for the
-- session. Detection: C_Item.GetItemInfo's 16th return is the setID,
-- C_Item.GetSetBonusesForSpecializationByItemID lists the set's bonus
-- spells for a spec, and C_SpecializationInfo resolves the current
-- specID (all verified on the Forever branch). Piece-count thresholds
-- have no API, so the 2/4 layout is assumed: wider layouts are
-- under-protected, never over-protected.
gear.SET_THRESHOLDS = { 2, 4 }

function gear.SetID(link)
  if not link then
    return nil
  end
  local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID = pcall(C_Item.GetItemInfo, link)
  if not ok then
    return nil
  end
  return setID
end

function gear.PlayerSpecID()
  if type(C_SpecializationInfo) ~= "table" then
    return nil
  end
  if type(C_SpecializationInfo.GetSpecialization) ~= "function" then
    return nil
  end
  if type(C_SpecializationInfo.GetSpecializationInfo) ~= "function" then
    return nil
  end
  local okIdx, idx = pcall(C_SpecializationInfo.GetSpecialization)
  if not okIdx or type(idx) ~= "number" then
    return nil
  end
  local okID, specID = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
  if not okID or type(specID) ~= "number" or specID == 0 then
    return nil
  end
  return specID
end

function gear.SetHasBonuses(link, specID)
  if not link or type(specID) ~= "number" then
    return false
  end
  if gear.SetID(link) == nil then
    return false
  end
  local itemID = C_Item.GetItemInfoInstant(link)
  if type(itemID) ~= "number" then
    return false
  end
  if type(C_Item.GetSetBonusesForSpecializationByItemID) ~= "function" then
    return false
  end
  local ok, spells = pcall(C_Item.GetSetBonusesForSpecializationByItemID, specID, itemID)
  return ok and type(spells) == "table" and #spells > 0
end

function gear.SetName(setID)
  if type(C_Item.GetItemSetInfo) ~= "function" then
    return nil
  end
  local ok, label = pcall(C_Item.GetItemSetInfo, setID)
  if ok and type(label) == "string" and label ~= "" then
    return label
  end
  return nil
end

function gear.BonusLabel(setID, threshold)
  local label = setID and gear.SetName(setID) or nil
  if label then
    return label .. " " .. threshold .. "pc"
  end
  return threshold .. "pc"
end

function gear.SetCounts()
  local counts = {}
  for slotID = 1, 19 do
    local id = gear.SetID(GetInventoryItemLink("player", slotID))
    if id then
      counts[id] = (counts[id] or 0) + 1
    end
  end
  return counts
end

function gear.SetCountsForSnap(snap)
  local counts = {}
  if snap then
    for slotID = 1, 19 do
      local id = gear.SetID(snap[slotID])
      if id then
        counts[id] = (counts[id] or 0) + 1
      end
    end
  end
  return counts
end

-- Per-scan set state, or nil when set logic is off or the spec is
-- unknown (fail open: pure item-level behavior).
function gear.SetContext()
  if not gear.opts().protectSets then
    return nil
  end
  local specID = gear.PlayerSpecID()
  if not specID then
    return nil
  end
  return { specID = specID, counts = gear.SetCounts() }
end

function gear.SetBreaks(ctx, link, held)
  if not ctx or not held then
    return nil
  end
  local heldSet = gear.SetID(held)
  if not heldSet or gear.setDeclined[heldSet] then
    return nil
  end
  if gear.SetID(link) == heldSet then
    return nil
  end
  if not gear.SetHasBonuses(held, ctx.specID) then
    return nil
  end
  local n = ctx.counts[heldSet] or 0
  for _, t in ipairs(gear.SET_THRESHOLDS) do
    if n == t then
      return t, heldSet
    end
  end
  return nil
end

function gear.SetCompletionReady(ctx, link)
  if not ctx then
    return nil
  end
  local candSet = gear.SetID(link)
  if not candSet or gear.setDeclined[candSet] then
    return nil
  end
  if not gear.SetHasBonuses(link, ctx.specID) then
    return nil
  end
  local n = ctx.counts[candSet] or 0
  for _, t in ipairs(gear.SET_THRESHOLDS) do
    if n + 1 == t then
      local okLvl, _, _, _, _, minLevel = pcall(C_Item.GetItemInfo, link)
      if okLvl and minLevel and UnitLevel("player") < minLevel then
        return nil
      end
      return t, candSet
    end
  end
  return nil
end

function gear.SetSwapCompletes(held, readyThreshold, readySet)
  if readyThreshold and gear.SetID(held) ~= readySet then
    return readyThreshold
  end
  return nil
end

function gear.TrackSetCrossings(prevSnap, snap)
  local before, after = gear.SetCountsForSnap(prevSnap), gear.SetCountsForSnap(snap)
  local seen = {}
  for id in pairs(before) do
    seen[id] = true
  end
  for id in pairs(after) do
    seen[id] = true
  end
  for id in pairs(seen) do
    local b, a = before[id] or 0, after[id] or 0
    if b ~= a then
      for _, t in ipairs(gear.SET_THRESHOLDS) do
        if b >= t and a < t then
          gear.setDeclined[id] = true
        end
        if b < t and a >= t then
          gear.setDeclined[id] = nil
        end
      end
    end
  end
end

-- Two-slot resolution by item level: the empty slot first, then the
-- weaker of the pair, but only when the candidate actually beats it
-- (with the rarity tiebreak). Returns a slot ID, or nil to announce.
function gear.ResolveTwoSlotSlot(equipLoc, ev, link)
  local pair = gear.slotPairs[equipLoc]
  if not pair then
    return nil
  end
  local held = {}
  for _, slotID in ipairs(pair) do
    held[slotID] = GetInventoryItemLink("player", slotID)
  end
  for _, slotID in ipairs(pair) do
    if not held[slotID] then
      return slotID
    end
  end
  local candLevel = ev.itemLevel or C_Item.GetDetailedItemLevelInfo(link)
  if not candLevel then
    return nil
  end
  local weakSlot, weakLevel
  for _, slotID in ipairs(pair) do
    local lvl = C_Item.GetDetailedItemLevelInfo(held[slotID])
    if lvl and (not weakLevel or lvl < weakLevel) then
      weakSlot, weakLevel = slotID, lvl
    end
  end
  if weakSlot and candLevel > weakLevel then
    return weakSlot
  end
  if weakSlot and candLevel == weakLevel and gear.RarityBeats(link, GetInventoryItemLink("player", weakSlot)) then
    return weakSlot
  end
  return nil
end

-- Unique-Equipped handling: a Unique-Equipped ring or trinket whose
-- twin is already worn is announced instead of equipped, because the
-- client refuses that equip. Bonus variants share the base item ID.
function gear.IsUniqueEquipped(link)
  if not link then
    return false
  end
  if type(C_Item.GetItemUniquenessByID) ~= "function" then
    return false
  end
  local ok, isUnique = pcall(C_Item.GetItemUniquenessByID, link)
  return ok and isUnique == true
end

function gear.BaseItemID(link)
  if not link then
    return nil
  end
  local ok, itemID = pcall(C_Item.GetItemInfoInstant, link)
  if not ok then
    return nil
  end
  return itemID
end

function gear.UniqueConflict(link, otherHeld)
  if not otherHeld then
    return false
  end
  if not gear.IsUniqueEquipped(link) then
    return false
  end
  local candID, otherID = gear.BaseItemID(link), gear.BaseItemID(otherHeld)
  if type(candID) ~= "number" or type(otherID) ~= "number" then
    return false
  end
  return candID == otherID
end

function gear.Why(ev)
  local base = ""
  if ev.tiebreak then
    base = " (higher rarity)"
  elseif ev.ilvl then
    base = " (item level +" .. tostring(ev.ilvlDiff or "?") .. ")"
  end
  if ev.completes then
    base = base .. " (completes " .. ev.completes .. ")"
  end
  if ev.handSwap then
    base = base .. " (1H/2H swap)"
  end
  return base
end

local function announceOnce(link, line)
  local o = gear.opts()
  if o.announce and not gear.flagged[link] then
    gear.flagged[link] = true
    ns.say(line)
  end
end
gear.AnnounceOnce = announceOnce

function gear.Announce(link, ev)
  announceOnce(link, "item level upgrade in bags (not auto-equipped): " .. link .. gear.Why(ev))
end

function gear.AnnounceWeaponKind(link, ev)
  announceOnce(link, "item level upgrade in bags (melee/ranged swap, not auto-equipped): " .. link .. gear.Why(ev))
end

function gear.AnnounceHandSwap(link, ev)
  announceOnce(link, "not equipping " .. link .. " (1H/2H swap, swap weapon types is off)" .. gear.Why(ev))
end

function gear.AnnounceWeaponType(link, ev)
  announceOnce(link, "not equipping " .. link .. " (different weapon type, swap weapon types is off)" .. gear.Why(ev))
end

function gear.AnnounceOffhand(link, ev)
  announceOnce(link, "not equipping " .. link .. " (off-hand needs a one-hand main hand)" .. gear.Why(ev))
end

function gear.AnnounceSetBreak(link, breakSet, threshold)
  announceOnce(link, "not equipping " .. link .. " (would break " .. gear.BonusLabel(breakSet, threshold) .. ")")
end

function gear.AnnounceUnique(link, otherHeld)
  announceOnce(link, "not equipping " .. link .. " (unique-equipped: " .. otherHeld .. " already equipped)")
end

-- One-line diagnosis for "/vui gear why": every veto that applies, so a
-- silent refusal explains itself.
function gear.WhyNot(link, ev)
  local reasons = {}
  local _, _, rarity, _, minLevel = C_Item.GetItemInfo(link)
  if minLevel and UnitLevel("player") < minLevel then
    reasons[#reasons + 1] = "needs level " .. minLevel
  end
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  if not equipLoc or equipLoc == "" then
    reasons[#reasons + 1] = "unknown slot (item data uncached?)"
  end
  if gear.Cosmetic(link) then
    reasons[#reasons + 1] = "cosmetic, never equips"
  end
  if gear.ProfessionTool(link) then
    reasons[#reasons + 1] = "profession tool, never equips"
  end
  if gear.Unusable(link) then
    reasons[#reasons + 1] = "not equippable by you"
  end
  if gear.ShieldBlocked(link) then
    reasons[#reasons + 1] = "your class cannot use shields"
  end
  if gear.ThrownBlocked(link) then
    reasons[#reasons + 1] = "your class cannot use thrown weapons"
  end
  if gear.NoSlot(link) then
    reasons[#reasons + 1] = "not gear (bag, quiver, or ammo)"
  end
  if rarity == gear.POOR_RARITY and not gear.EmptyHome(link) then
    reasons[#reasons + 1] = "grey, slot occupied"
  end
  if #reasons == 0 then
    if ev == nil then
      reasons[#reasons + 1] = "waiting on item data"
    elseif gear.ArmorBestBuiltin(link) == false then
      reasons[#reasons + 1] = "wrong armor type for your class"
    elseif ev.ilvl and ev.ilvlDiff then
      reasons[#reasons + 1] = "item level "
        .. tostring(ev.itemLevel or "?")
        .. " vs worn "
        .. tostring((ev.itemLevel or 0) - (ev.ilvlDiff or 0))
    else
      reasons[#reasons + 1] = "not an upgrade"
    end
  end
  return table.concat(reasons, "; ")
end

-- Placeholder rows, patched on item data: the "/vui gear why" list
-- renders immediately, placeholders and all, then patches the rows that
-- were waiting when GET_ITEM_INFO_RECEIVED lands for them.
function gear.NotePending(link, kind)
  local itemID = gear.BaseItemID(link)
  if type(itemID) ~= "number" then
    return
  end
  local waiting = gear.pendingInfo[itemID]
  if not waiting then
    waiting = {}
    gear.pendingInfo[itemID] = waiting
  end
  for _, entry in ipairs(waiting) do
    if entry.link == link then
      return
    end
  end
  waiting[#waiting + 1] = { link = link, kind = kind }
end

-- What the item is worth, from the Auctionator scan database when
-- it knows a price, else vendor value: Auctionator first, silence
-- when neither does. Printed on the diagnostic lines so a manual
-- equip decision has the number in front of it.
function gear.ValueSuffix(link)
  if ns.prices and type(ns.prices.Suffix) == "function" then
    return ns.prices.Suffix(link)
  end
  return ""
end

function gear.PatchLine(kind, link, ev)
  if ev.upgrade then
    ns.say(link .. ": upgrade" .. gear.Why(ev) .. gear.ValueSuffix(link))
  else
    ns.say(link .. ": not equipping (" .. gear.WhyNot(link, ev) .. ")" .. gear.ValueSuffix(link))
  end
end

function gear.PatchPending(itemID, success)
  if type(itemID) ~= "number" then
    return
  end
  local waiting = gear.pendingInfo[itemID]
  if not waiting then
    return
  end
  gear.pendingInfo[itemID] = nil
  if success == false then
    return
  end
  for _, entry in ipairs(waiting) do
    local okEv, ev = pcall(gear.Evaluate, entry.link)
    if okEv and ev ~= nil then
      gear.PatchLine(entry.kind, entry.link, ev)
    else
      gear.NotePending(entry.link, entry.kind)
    end
  end
end

function gear.WhySayImpl()
  local found = false
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        found = true
        local okEv, ev = pcall(gear.Evaluate, link)
        if not okEv or ev == nil then
          gear.NotePending(link, "why")
          ns.say(link .. ": waiting on item data")
        elseif ev.upgrade then
          ns.say(link .. ": upgrade" .. gear.Why(ev) .. gear.ValueSuffix(link))
        else
          ns.say(link .. ": not equipping (" .. gear.WhyNot(link, ev) .. ")" .. gear.ValueSuffix(link))
        end
      end
    end
  end
  if not found then
    ns.say("bags hold no equipment")
  end
end
