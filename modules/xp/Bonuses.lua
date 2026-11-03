local _, ns = ...
local xp = ns.xp

-- Bonus lines: what raises the gain right now, and what is missing.
-- On Forever only Rested is ever suggested: War Mode, Mentored, and
-- the event buffs are unconfirmed there, so the module shows them when
-- active but never recommends them. Detection stays ungated on every
-- client (a lit flag or a present aura is real anywhere); only the
-- suggestions gate. Regalia is retail-only and has no line here at
-- all. The Regalia set does not exist on Forever.

-- Fixed-value XP-buff auras by spell ID: WHEE! (Darkmoon carousel and
-- coaster), Darkmoon Top Hat (separate aura, same +10%), Grim Visage /
-- Unburdened (Hallow's End Wickerman, one per faction).
xp.XP_BUFFS = {
  { id = 46668, label = "+10% WHEE!", pct = 10 },
  { id = 136583, label = "+10% Darkmoon Top Hat", pct = 10 },
  { id = 24705, label = "+10% Grim Visage", pct = 10 },
  { id = 95987, label = "+10% Unburdened", pct = 10 },
}

-- Rep buffs, all +10%: the Faire pair, the Wickerman pair, and the
-- Pilgrim's Bounty Spirit of Sharing (rep-only).
xp.REP_BUFFS = {
  { id = 46668, label = "+10% WHEE!", pct = 10 },
  { id = 136583, label = "+10% Darkmoon Top Hat", pct = 10 },
  { id = 24705, label = "+10% Grim Visage", pct = 10 },
  { id = 95987, label = "+10% Unburdened", pct = 10 },
  { id = 61849, label = "+10% Spirit of Sharing", pct = 10 },
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

function xp.warMode()
  return type(C_PvP) == "table" and type(C_PvP.IsWarModeDesired) == "function" and C_PvP.IsWarModeDesired()
end

-- The Enlisted buff starts at +10% but a Call to Arms for the
-- player's faction raises it, so read the live value instead of
-- hardcoding the base.
function xp.warModeOffered()
  local pct = 10
  if type(C_PvP) == "table" and type(C_PvP.GetWarModeRewardBonus) == "function" then
    local v = C_PvP.GetWarModeRewardBonus()
    if type(v) == "number" and v >= 1 and v <= 100 then
      pct = v
    end
  end
  return pct
end

function xp.warModePct()
  if not xp.warMode() then
    return nil
  end
  return xp.warModeOffered()
end

-- Warband Mentored Leveling scales 5-25% with max-level characters;
-- the aura's first effect point carries the current value.
xp.MENTORED_ID = 430191

function xp.mentoredBonus()
  local aura = xp.playerAura(xp.MENTORED_ID)
  if not aura then
    return nil
  end
  local pct = aura.points and aura.points[1]
  if type(pct) == "number" and pct >= 1 and pct <= 100 then
    return ("+%d%% Warband Mentored"):format(pct), pct
  end
  return "Warband Mentored", nil
end

-- Aura reads go blind in instances: the API returns nil there for
-- present world-granted buffs, so both lists gate aura-derived lines
-- on this and say so instead of false absence.
function xp.inInstance()
  if type(IsInInstance) ~= "function" then
    return false
  end
  return IsInInstance() == true
end

function xp.rested()
  if type(GetXPExhaustion) ~= "function" then
    return false
  end
  return GetXPExhaustion() ~= nil
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

-- Bonus lines, highest value first. Lines without a number (Rested,
-- an unreadable Mentored value) trail in their usual order.
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
  local wm = xp.warModePct()
  if wm then
    add(wm, ("+%d%% War Mode"):format(wm))
  end
  local restricted = xp.inInstance()
  if not restricted then
    local mentored, mentoredPct = xp.mentoredBonus()
    if mentored then
      add(mentoredPct, mentored)
    end
    for _, buff in ipairs(xp.XP_BUFFS) do
      if xp.hasAura(buff.id) then
        add(buff.pct, buff.label)
      end
    end
  end
  if xp.rested() then
    add(nil, "Rested")
  end
  return bonusLabels(parts)
end

-- Buffs the player could be running but isn't: each names its value
-- and a short how-to. On Forever only Rested is recommended, so the
-- missing list holds just that; a lit War Mode flag or a present aura
-- still shows above, it is only never suggested.
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
  if not xp.rested() then
    add(nil, "Rested (rest in town)")
  end
  if xp.inInstance() then
    add(nil, "Aura scan unavailable in instances")
  end
  return bonusLabels(parts)
end
