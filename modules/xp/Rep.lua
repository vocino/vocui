local _, ns = ...
local xp = ns.xp

-- Reputation mode: at max level the bar pivots from XP to reputation.
-- A faction of any kind -- standard standing, Renown, Paragon,
-- friendship -- normalizes to one progress shape ({ id, name, kind,
-- have, need, level, levelLabel, capLabel, capped, bonus }, Paragon
-- adding raw and pending), following Blizzard's own
-- ReputationStatusBarMixin math. The rolling estimator never learns
-- the kinds: rep paints synthetic XP-shaped snapshots through it with
-- est.unit set, and only the format layer speaks Rep.

-- Standing names, Hated to Exalted. English literals like every other
-- line the module prints; the client localizes, we don't.
xp.STANDING_NAMES = {
  "Hated",
  "Hostile",
  "Unfriendly",
  "Neutral",
  "Friendly",
  "Honored",
  "Revered",
  "Exalted",
}

-- The standing ceiling. Blizzard defines MAX_REPUTATION_REACTION in
-- its own (possibly unloaded) ReputationFrame, so a missing global
-- falls back to the eight reactions that have held since 2004.
function xp.maxRepReaction()
  if type(MAX_REPUTATION_REACTION) == "number" and MAX_REPUTATION_REACTION >= 1 then
    return math.floor(MAX_REPUTATION_REACTION)
  end
  return 8
end

function xp.standingName(reaction)
  if type(reaction) == "number" and xp.STANDING_NAMES[reaction] ~= nil then
    return xp.STANDING_NAMES[reaction]
  end
  return ("Rank %s"):format(tostring(reaction))
end

-- A faction-list row is trackable when it names a real faction and
-- carries reputation (headers with rep count; plain headers don't).
function xp.validRepRow(fd)
  if type(fd) ~= "table" then
    return false
  end
  if type(fd.factionID) ~= "number" or fd.factionID == 0 then
    return false
  end
  if fd.isHeader and not fd.isHeaderWithRep then
    return false
  end
  return type(fd.name) == "string" and fd.name ~= ""
end

-- Standard standing: currentStanding between the reaction thresholds.
function xp.repStandardProgress(fd, maxReaction)
  if not xp.validRepRow(fd) then
    return nil
  end
  maxReaction = maxReaction or xp.maxRepReaction()
  local r, lo, hi, cur = fd.reaction, fd.currentReactionThreshold, fd.nextReactionThreshold, fd.currentStanding
  if type(r) ~= "number" or r < 1 or r ~= math.floor(r) then
    return nil
  end
  if type(lo) ~= "number" or type(hi) ~= "number" or type(cur) ~= "number" then
    return nil
  end
  local label = xp.standingName(math.min(r, maxReaction))
  if r >= maxReaction then
    return {
      id = fd.factionID,
      name = fd.name,
      kind = "standing",
      have = 1,
      need = 1,
      level = r,
      levelLabel = label,
      capLabel = label,
      capped = true,
      bonus = fd.hasBonusRepGain == true,
    }
  end
  if hi <= lo or cur < lo then
    return nil
  end
  return {
    id = fd.factionID,
    name = fd.name,
    kind = "standing",
    have = cur - lo,
    need = hi - lo,
    level = r,
    levelLabel = label,
    capLabel = label,
    capped = false,
    bonus = fd.hasBonusRepGain == true,
  }
end

-- Renown: currentStanding is already in-level progress over the
-- faction's level threshold (the native watch bar reads it raw).
function xp.repRenownProgress(fd, major, hasMax)
  if not xp.validRepRow(fd) then
    return nil
  end
  if type(major) ~= "table" then
    return nil
  end
  local level, threshold = major.renownLevel, major.renownLevelThreshold
  if type(level) ~= "number" or type(threshold) ~= "number" or threshold <= 0 then
    return nil
  end
  if type(fd.currentStanding) ~= "number" then
    return nil
  end
  local label = ("Renown %d"):format(math.floor(level))
  if hasMax then
    return {
      id = fd.factionID,
      name = fd.name,
      kind = "renown",
      have = 1,
      need = 1,
      level = level,
      levelLabel = label,
      capLabel = label,
      capped = true,
      bonus = fd.hasBonusRepGain == true,
    }
  end
  local have = math.max(0, math.min(threshold, fd.currentStanding))
  return {
    id = fd.factionID,
    name = fd.name,
    kind = "renown",
    have = have,
    need = threshold,
    level = level,
    levelLabel = label,
    capLabel = label,
    capped = false,
    bonus = fd.hasBonusRepGain == true,
  }
end

-- Paragon: the cycle position is the lifetime value modulo the
-- threshold; a pending reward pins the bar full. Never capped.
function xp.repParagonProgress(fd, currentValue, threshold, hasRewardPending)
  if not xp.validRepRow(fd) then
    return nil
  end
  if type(currentValue) ~= "number" or type(threshold) ~= "number" or threshold <= 0 then
    return nil
  end
  local have = currentValue % threshold
  if hasRewardPending then
    have = threshold
  end
  return {
    id = fd.factionID,
    name = fd.name,
    kind = "paragon",
    raw = currentValue,
    have = have,
    need = threshold,
    level = nil,
    levelLabel = "Paragon",
    capLabel = "Paragon",
    capped = false,
    pending = hasRewardPending == true,
    bonus = fd.hasBonusRepGain == true,
  }
end

-- Friendship: standing between the rank thresholds; a nil next
-- threshold is max rank and paints a full bar.
function xp.repFriendshipProgress(fd, repInfo, rankInfo)
  if not xp.validRepRow(fd) then
    return nil
  end
  if type(repInfo) ~= "table" or type(rankInfo) ~= "table" then
    return nil
  end
  local reaction = type(repInfo.reaction) == "string" and repInfo.reaction or "Friend"
  local level = type(rankInfo.currentLevel) == "number" and rankInfo.currentLevel or nil
  if repInfo.nextThreshold == nil then
    return {
      id = fd.factionID,
      name = fd.name,
      kind = "friendship",
      have = 1,
      need = 1,
      level = level,
      levelLabel = reaction,
      capLabel = reaction,
      capped = true,
      bonus = fd.hasBonusRepGain == true,
    }
  end
  local lo, hi, cur = repInfo.reactionThreshold, repInfo.nextThreshold, repInfo.standing
  if type(lo) ~= "number" or type(hi) ~= "number" or type(cur) ~= "number" then
    return nil
  end
  if hi <= lo or cur < lo then
    return nil
  end
  return {
    id = fd.factionID,
    name = fd.name,
    kind = "friendship",
    have = cur - lo,
    need = hi - lo,
    level = level,
    levelLabel = reaction,
    capLabel = reaction,
    capped = false,
    bonus = fd.hasBonusRepGain == true,
  }
end

-- Rep gain between two progress reads of one faction. Same-kind and
-- same-level deltas are exact; a single rank-up carries the remainder
-- across; anything else (kind swap, faction swap, multi-rank jump, a
-- loss) resyncs with nil, exactly like xp.gain. Paragon has no ranks:
-- the lifetime value's non-negative delta is the gain.
function xp.repGain(old, new)
  if type(old) ~= "table" or type(new) ~= "table" then
    return nil
  end
  if old.id ~= new.id or old.kind ~= new.kind then
    return nil
  end
  if new.capped then
    return nil
  end
  if new.kind == "paragon" then
    if type(old.raw) ~= "number" or type(new.raw) ~= "number" then
      return nil
    end
    if new.raw >= old.raw then
      return new.raw - old.raw
    end
    return nil
  end
  if type(old.level) ~= "number" or type(new.level) ~= "number" then
    return nil
  end
  if type(old.have) ~= "number" or type(new.have) ~= "number" then
    return nil
  end
  if type(old.need) ~= "number" or type(new.need) ~= "number" then
    return nil
  end
  if new.level == old.level then
    if new.have >= old.have then
      return new.have - old.have
    end
    return nil
  elseif new.level == old.level + 1 then
    return math.max(0, old.need - old.have + new.have)
  end
  return nil
end

-- Bar label: the faction name with in-rank numbers, name alone at the
-- cap like the native bar, guidance when nothing is tracked.
function xp.repBarLabel(progress)
  if progress == nil then
    return "No faction tracked"
  end
  if progress.capped then
    return progress.name
  end
  local pct = math.max(0, math.min(100, math.floor(progress.have / progress.need * 100 + 0.5)))
  return ("%s  %s/%s (%d%%)"):format(progress.name, xp.fmt(progress.have), xp.fmt(progress.need), pct)
end

-- Stats line: rank context the bar label skips. Nil at the cap (the
-- tooltip carries it) and for unknown kinds.
function xp.repStatsLine(progress)
  if progress == nil or progress.capped then
    return nil
  end
  local pct = math.max(0, math.min(100, math.floor(progress.have / progress.need * 100 + 0.5)))
  if progress.kind == "standing" then
    return ("%s · %d%% to %s"):format(progress.levelLabel, pct, xp.standingName(progress.level + 1))
  elseif progress.kind == "renown" then
    return ("%s · %d%% to %d"):format(progress.levelLabel, pct, progress.level + 1)
  elseif progress.kind == "paragon" then
    return ("Paragon · %d%% to reward"):format(pct)
  elseif progress.kind == "friendship" then
    return ("%s · %d%% to next rank"):format(progress.levelLabel, pct)
  end
  return nil
end

-- Fill art for a tracked faction: the reaction row, blue for Renown
-- and major-faction Paragon, forced green for friendships. A missing
-- or wild reaction reads friendly rather than erroring.
xp.REP_FILL_BLUE = "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Blue"
xp.REP_FILL = {
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Red",
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Red",
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Orange",
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Yellow",
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
  "UI-HUD-ExperienceBar-Fill-Reputation-Faction-Green",
}
xp.REP_FLARE = {
  "UI-HUD-ExperienceBar-Flare-Faction-Orange-2x-Flipbook",
  "UI-HUD-ExperienceBar-Flare-Faction-Orange-2x-Flipbook",
  "UI-HUD-ExperienceBar-Flare-Faction-Orange-2x-Flipbook",
  "UI-HUD-ExperienceBar-Flare-ArtifactPower-2x-Flipbook",
  "UI-HUD-ExperienceBar-Flare-Reputation-2x-Flipbook",
  "UI-HUD-ExperienceBar-Flare-Reputation-2x-Flipbook",
  "UI-HUD-ExperienceBar-Flare-Reputation-2x-Flipbook",
  "UI-HUD-ExperienceBar-Flare-Reputation-2x-Flipbook",
}
xp.REP_FLARE_BLUE = "UI-HUD-ExperienceBar-Flare-Rested-2x-Flipbook"
xp.REP_LEVELUP = {
  "UI-HUD-ExperienceBar-Fill-Honor-2x-Flipbook",
  "UI-HUD-ExperienceBar-Fill-Honor-2x-Flipbook",
  "UI-HUD-ExperienceBar-Fill-Honor-2x-Flipbook",
  "UI-HUD-ExperienceBar-Fill-ArtifactPower-2x-Flipbook",
  "UI-HUD-ExperienceBar-Fill-Reputation-2x-Flipbook",
  "UI-HUD-ExperienceBar-Fill-Reputation-2x-Flipbook",
  "UI-HUD-ExperienceBar-Fill-Reputation-2x-Flipbook",
  "UI-HUD-ExperienceBar-Fill-Reputation-2x-Flipbook",
}
xp.REP_LEVELUP_BLUE = "UI-HUD-ExperienceBar-Fill-Rested-2x-Flipbook"

function xp.repAtlas(progress)
  if progress.kind == "renown" or progress.blue then
    return xp.REP_FILL_BLUE, xp.REP_FLARE_BLUE, xp.REP_LEVELUP_BLUE
  end
  local row = progress.kind == "friendship" and 5 or progress.level
  if type(row) ~= "number" or row < 1 or row > 8 then
    row = 5
  end
  row = math.floor(row)
  return xp.REP_FILL[row], xp.REP_FLARE[row], xp.REP_LEVELUP[row]
end

-- Presence-gated readers. Every C_* call below is verified in
-- wiki/API-Ledger.md; a missing namespace still degrades to nil,
-- never an error.
function xp.watchedFaction()
  if type(C_Reputation) ~= "table" then
    return nil
  end
  if type(C_Reputation.GetWatchedFactionData) ~= "function" then
    return nil
  end
  local fd = C_Reputation.GetWatchedFactionData()
  if not xp.validRepRow(fd) then
    return nil
  end
  return fd
end

-- Full progress for one faction ID, dispatching paragon -> renown ->
-- friendship -> standard like the native watch bar. An unreadable
-- kind reads nil instead of falling through to a wrong one; a
-- missing kind API does the same.
function xp.readRepProgress(factionID)
  if type(C_Reputation) ~= "table" or type(factionID) ~= "number" then
    return nil
  end
  local R = C_Reputation
  -- The watched struct is the live one native itself paints; ByID can
  -- lag it, so the watched faction always reads through
  -- GetWatchedFactionData.
  local fd = nil
  local watched = xp.watchedFaction()
  if watched ~= nil and watched.factionID == factionID then
    fd = watched
  elseif type(R.GetFactionDataByID) == "function" then
    fd = R.GetFactionDataByID(factionID)
  end
  if not xp.validRepRow(fd) then
    return nil
  end
  if type(R.IsFactionParagonForCurrentPlayer) == "function" and R.IsFactionParagonForCurrentPlayer(factionID) then
    if type(R.GetFactionParagonInfo) ~= "function" then
      return nil
    end
    local currentValue, threshold, _, hasRewardPending = R.GetFactionParagonInfo(factionID)
    local paragon = xp.repParagonProgress(fd, currentValue, threshold, hasRewardPending)
    if paragon and type(R.IsMajorFaction) == "function" and R.IsMajorFaction(factionID) then
      paragon.blue = true
    end
    return paragon
  end
  if type(R.IsMajorFaction) == "function" and R.IsMajorFaction(factionID) then
    if
      type(C_MajorFactions) ~= "table"
      or type(C_MajorFactions.GetMajorFactionData) ~= "function"
      or type(C_MajorFactions.HasMaximumRenown) ~= "function"
    then
      return nil
    end
    return xp.repRenownProgress(
      fd,
      C_MajorFactions.GetMajorFactionData(factionID),
      C_MajorFactions.HasMaximumRenown(factionID)
    )
  end
  if
    type(C_GossipInfo) == "table"
    and type(C_GossipInfo.GetFriendshipReputation) == "function"
    and type(C_GossipInfo.GetFriendshipReputationRanks) == "function"
  then
    local repInfo = C_GossipInfo.GetFriendshipReputation(factionID)
    if
      type(repInfo) == "table"
      and type(repInfo.friendshipFactionID) == "number"
      and repInfo.friendshipFactionID > 0
    then
      return xp.repFriendshipProgress(
        fd,
        repInfo,
        C_GossipInfo.GetFriendshipReputationRanks(repInfo.friendshipFactionID)
      )
    end
  end
  return xp.repStandardProgress(fd)
end
