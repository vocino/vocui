local _, ns = ...
local xp = ns.xp
local frame = xp.frame

-- Session state. Trackers, baselines, and the mode live here, never in
-- SavedVariables: monotonic timestamps must not cross a reload. Only
-- the tracked faction ID persists, so a reload restores it.

local rateTracker = nil
local etaTracker = nil
local baseline = nil
local identity = nil
local paused = false
local mode = "xp" -- "xp", "rep", or "dormant"; derived from the snapshot, never toggled
local questXp, questCount, scanning = 0, 0, false
local ticker = nil
local nativeHiddenByUs = false
local rivalsWarned = false
local repCache = {}
local repFactionID, repWatching, lastGainedID, repBaseline = nil, false, nil, nil
local pendingGuildDing = nil -- a combat-deferred ding level; the latest wins
local summaryAcc = nil -- built by resetTrackers during init; guard below covers early reads

local xpEvents = {
  "PLAYER_XP_UPDATE",
  "PLAYER_EQUIPMENT_CHANGED",
  "UPDATE_EXHAUSTION",
  "PLAYER_UPDATE_RESTING",
  "QUEST_LOG_UPDATE",
  "QUEST_TURNED_IN",
  "QUEST_ACCEPTED",
  "QUEST_REMOVED",
  "QUEST_COMPLETE",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
}
local repEvents = {
  "UPDATE_FACTION",
  "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
  "FACTION_STANDING_CHANGED",
  "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED",
}

local function resetTrackers()
  rateTracker = xp.newTracker(xp.now())
  etaTracker = xp.newTracker(xp.now(), xp.ETA_WINDOW)
  summaryAcc = xp.newSummary() -- observation restarts: the old burst never reports
end

function xp.now()
  if type(GetTime) == "function" then
    return GetTime()
  end
  return 0
end

-- Report the pending burst when it is due: at least two gains, no new
-- gains for SUMMARY_QUIET, and no longer busy. Called from refresh(),
-- so no new timer and no new event: the 1s ticker bounds the delay.
-- Burst and advice lines honor the announce toggle; confirmations do not.
local function flushSummary(now)
  if summaryAcc == nil or summaryAcc.count < 2 then
    return false
  end
  if ns.combat() then
    return false
  end
  if (now - summaryAcc.lastAt) < xp.SUMMARY_QUIET then
    return false
  end
  local line = xp.formatSummary(summaryAcc)
  summaryAcc = xp.newSummary()
  if line == nil then
    return false
  end
  if xp.opts().announce then
    ns.say(line)
  end
  return true
end

function xp.sayAnnounce(line)
  if xp.opts().announce then
    ns.say(line)
  end
end

-- Capped test, mirroring GameRulesUtil.IsPlayerAtEffectiveMaxLevel
-- (Blizzard_SharedXML/GameRulesUtil.lua): a level comparison, never
-- UnitXPMax == 0. At cap the client reports a phantom requirement
-- instead of zeroing, so max == 0 survives only as the last-resort
-- fallback when no max-level API exists at all.
function xp.effectiveMaxLevel()
  local latest, expansion, perPlayer
  if type(GetMaxLevelForLatestExpansion) == "function" then
    latest = GetMaxLevelForLatestExpansion()
  end
  if type(GetMaxLevelForPlayerExpansion) == "function" then
    expansion = GetMaxLevelForPlayerExpansion()
  end
  if type(GetMaxPlayerLevel) == "function" then
    perPlayer = GetMaxPlayerLevel()
  end
  if type(latest) ~= "number" or type(expansion) ~= "number" or type(perPlayer) ~= "number" then
    if type(perPlayer) == "number" then
      return perPlayer
    end
    return nil
  end
  local timerunning = type(PlayerIsTimerunning) == "function" and PlayerIsTimerunning()
  local trial = type(IsTrialAccount) == "function" and IsTrialAccount()
  local expansionMax = (timerunning and not trial) and latest or expansion
  return math.min(expansionMax, perPlayer)
end

function xp.isLevelCapped(level, max)
  if type(level) ~= "number" then
    return false
  end
  local cap = xp.effectiveMaxLevel()
  if type(cap) == "number" then
    return level >= cap
  end
  return max == 0
end

function xp.readSnapshot()
  local max, level = UnitXPMax("player"), UnitLevel("player")
  if xp.isLevelCapped(level, max) then
    return { level = level, xp = 0, req = 1, capped = true }
  end
  return { level = level, xp = UnitXP("player"), req = max, capped = false }
end

-- Rested XP as a number, or nil when there is none to draw. Blizzard
-- hides the rested layer while XP gain is disabled, so do we; a
-- missing API there means XP assumed enabled, never a missing bar.
function xp.restedAmount()
  if type(IsXPUserDisabled) == "function" and IsXPUserDisabled() then
    return nil
  end
  if type(GetXPExhaustion) ~= "function" then
    return nil
  end
  local v = GetXPExhaustion()
  if type(v) ~= "number" or v <= 0 then
    return nil
  end
  return v
end

-- Ready-to-turn-in quest XP: the payout waiting at quest givers, as
-- raw XP and a quest count. GetQuestLogRewardXP reads the selected
-- entry, so the scan saves and restores the selection and never
-- re-enters: a quest event fired mid-scan re-renders on the previous
-- total instead of recursing. A missing API anywhere in the chain
-- means no overlay, never an error.
function xp.scanQuestXp()
  if scanning then
    return questXp, questCount
  end
  if type(C_QuestLog) ~= "table" or type(GetQuestLogRewardXP) ~= "function" then
    questXp, questCount = 0, 0
    return questXp, questCount
  end
  local QL = C_QuestLog
  if
    type(QL.GetNumQuestLogEntries) ~= "function"
    or type(QL.GetInfo) ~= "function"
    or type(QL.ReadyForTurnIn) ~= "function"
    or type(QL.GetSelectedQuest) ~= "function"
    or type(QL.SetSelectedQuest) ~= "function"
  then
    questXp, questCount = 0, 0
    return questXp, questCount
  end
  scanning = true
  local ok, total, count = pcall(function()
    local shown = QL.GetNumQuestLogEntries()
    if type(shown) ~= "number" then
      return 0, 0
    end
    local sel = QL.GetSelectedQuest()
    local sum, n = 0, 0
    for i = 1, shown do
      local info = QL.GetInfo(i)
      if
        type(info) == "table"
        and not info.isHeader
        and type(info.questID) == "number"
        and QL.ReadyForTurnIn(info.questID)
      then
        QL.SetSelectedQuest(info.questID)
        local reward = GetQuestLogRewardXP()
        if type(reward) == "number" and reward > 0 then
          sum, n = sum + reward, n + 1
        end
      end
    end
    if type(sel) == "number" and sel ~= 0 then
      QL.SetSelectedQuest(sel)
    end
    return sum, n
  end)
  scanning = false
  if ok then
    questXp, questCount = total, count
  else
    questXp, questCount = 0, 0
  end
  return questXp, questCount
end

-- Gain scan: re-read every visible faction row and diff standings
-- against the cache, returning the ID with the largest increase (or
-- nil). Paragon rows compare lifetime values and friendship rows
-- their own standing, the way Blizzard's ReputationFrame does;
-- Renown rows compare currentStanding like the native watch bar.
-- Decreases only resync the cache: a loss never steals tracking.
-- Collapsed headers hide their children from the index list, so a
-- collapsed row's gains never surface here; the watched and persisted
-- paths use ByID and never depend on the scan.
local function scanStanding(R, id, standing)
  if
    type(R.IsFactionParagonForCurrentPlayer) == "function"
    and type(R.GetFactionParagonInfo) == "function"
    and R.IsFactionParagonForCurrentPlayer(id)
  then
    local currentValue = R.GetFactionParagonInfo(id)
    if type(currentValue) == "number" then
      return currentValue
    end
    return nil
  end
  if type(C_GossipInfo) == "table" and type(C_GossipInfo.GetFriendshipReputation) == "function" then
    local repInfo = C_GossipInfo.GetFriendshipReputation(id)
    if
      type(repInfo) == "table"
      and type(repInfo.friendshipFactionID) == "number"
      and repInfo.friendshipFactionID > 0
      and type(repInfo.standing) == "number"
    then
      return repInfo.standing
    end
  end
  return standing
end

function xp.scanRepGains()
  if type(C_Reputation) ~= "table" then
    return nil
  end
  local R = C_Reputation
  if type(R.GetNumFactions) ~= "function" or type(R.GetFactionDataByIndex) ~= "function" then
    return nil
  end
  local ok, gained = pcall(function()
    local n = R.GetNumFactions()
    if type(n) ~= "number" then
      return nil
    end
    local bestID, bestGain = nil, 0
    for i = 1, n do
      local fd = R.GetFactionDataByIndex(i)
      if xp.validRepRow(fd) then
        local standing = scanStanding(R, fd.factionID, fd.currentStanding)
        if type(standing) == "number" then
          local prev = repCache[fd.factionID]
          repCache[fd.factionID] = standing
          if type(prev) == "number" and standing > prev and standing - prev > bestGain then
            bestID, bestGain = fd.factionID, standing - prev
          end
        end
      end
    end
    return bestID
  end)
  if ok then
    return gained
  end
  return nil
end

-- Tracked-faction resolution, first readable candidate wins: watched,
-- then the latest gainer, then the persisted ID from the last
-- session, then nothing (the untracked state). followLatest flips the
-- order to latest, persisted, watched: the bar always follows fresh
-- gains and only borrows the watched faction until the first one.
-- The choice persists, so a reload restores it; every candidate
-- revalidates to readable progress on the way in, so tracking never
-- sticks on a dead row.
function xp.resolveRepFaction()
  repWatching = false
  local watched = xp.watchedFaction()
  local watchedID = watched ~= nil and watched.factionID or nil
  local order
  if xp.opts().followLatest then
    order = { lastGainedID, xp.opts().repFaction, watchedID }
  else
    order = { watchedID, lastGainedID, xp.opts().repFaction }
  end
  repFactionID = nil
  for i = 1, 3 do -- fixed bound: the order has holes (ipairs would stop at the first nil)
    local id = order[i]
    if type(id) == "number" and xp.readRepProgress(id) then
      repFactionID = id
      repWatching = (id == watchedID)
      break
    end
  end
  xp.opts().repFaction = repFactionID
  return repFactionID
end

function xp.repTracked()
  return repFactionID
end

function xp.repFollowingWatched()
  return repWatching
end

-- Re-resolve after a scan or a tick, restarting observation only when
-- the tracked faction actually moved. Watched changes carry no
-- event, so refresh calls this every second; the reads are cheap.
function xp.maybeSwitchRep()
  local before = repFactionID
  local rid = xp.resolveRepFaction()
  if rid ~= before then
    repBaseline = rid and xp.readRepProgress(rid) or nil
    resetTrackers()
    return true
  end
  return false
end

function xp.noteRepGain(factionID)
  if type(factionID) == "number" then
    lastGainedID = factionID
  end
end

-- Rep gains arrive as faction updates: rescan for the latest gainer,
-- re-resolve (following it when nothing is watched), then reconstruct
-- at most one award for the tracked faction from its baseline delta,
-- exactly like the XP path. The index scan cannot see collapsed rows,
-- so a gain there never surfaces as a latest gainer; the
-- FACTION_STANDING_CHANGED payload carries the gainer faction ID
-- outright, ByID-readable whatever the headers do, so the payload is
-- the primary signal and the scan stays the fallback for
-- UPDATE_FACTION, which carries none. Paragon lifetime values and
-- friendship standings live outside FactionData.currentStanding, so
-- the payload standing only compares for standard/renown rows;
-- anything else follows when readable.
local function notePayloadGain(factionID, updatedStanding)
  if type(factionID) ~= "number" then
    return
  end
  local special = false
  if
    type(C_Reputation) == "table"
    and type(C_Reputation.IsFactionParagonForCurrentPlayer) == "function"
    and C_Reputation.IsFactionParagonForCurrentPlayer(factionID)
  then
    special = true
  end
  if not special and type(C_GossipInfo) == "table" and type(C_GossipInfo.GetFriendshipReputation) == "function" then
    local repInfo = C_GossipInfo.GetFriendshipReputation(factionID)
    if
      type(repInfo) == "table"
      and type(repInfo.friendshipFactionID) == "number"
      and repInfo.friendshipFactionID > 0
    then
      special = true
    end
  end
  if
    not special
    and type(repCache[factionID]) == "number"
    and type(updatedStanding) == "number"
    and updatedStanding <= repCache[factionID]
  then
    -- A loss or a no-op resyncs the cache like the scan: it never
    -- steals tracking.
    repCache[factionID] = updatedStanding
    return
  end
  -- First sighting (a collapsed row has no cache entry) follows: the
  -- resolver revalidates readability, so a dead row never sticks.
  xp.noteRepGain(factionID)
end

local function onRep(gainedID, updatedStanding, renownLevel)
  if renownLevel then
    -- A renown level-up is a gain by definition: the in-level
    -- standing resets low and reads as a loss to standing compares.
    xp.noteRepGain(gainedID)
  else
    notePayloadGain(gainedID, updatedStanding)
  end
  xp.noteRepGain(xp.scanRepGains())
  if xp.maybeSwitchRep() then
    xp.refresh()
    return
  end
  if repFactionID then
    local snap = xp.readRepProgress(repFactionID)
    if snap == nil then
      -- Tracked faction went unreadable: resolve again (usually the
      -- untracked state) instead of awarding against stale reads.
      xp.maybeSwitchRep()
    else
      if not paused then
        local award = xp.repGain(repBaseline, snap)
        if award then
          local stamp = xp.now()
          xp.addAward(rateTracker, stamp, award)
          xp.addAward(etaTracker, stamp, award)
          summaryAcc = xp.noteSummaryGain(summaryAcc, stamp, "rep", repFactionID, snap.name, award, ns.combat())
        end
      end
      repBaseline = snap
    end
  end
  xp.refresh()
end

-- The client refuses chat from addon code while its messaging lockdown
-- holds, and answers with ADDON_ACTION_BLOCKED, which no pcall can
-- catch: a refused call still logs the block against the addon. Ask
-- first and stay quiet instead. A missing query is not a refusal: the
-- gate only holds when the client says so.
local function chatLocked()
  if type(C_ChatInfo) ~= "table" then
    return false
  end
  local gated = C_ChatInfo.InChatMessagingLockdown
  if type(gated) ~= "function" then
    return false
  end
  local ok, held = pcall(gated)
  return ok and held == true
end

-- One send through the documented namespace first. The bare global is
-- Blizzard's deprecated shim over the same function, so it only runs
-- when the namespace is missing, never as a retry: a refused line would
-- book a second blocked action for the same send.
local function sendGuild(text)
  if type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function" then
    return pcall(C_ChatInfo.SendChatMessage, text, "GUILD")
  end
  if type(SendChatMessage) == "function" then
    return pcall(SendChatMessage, text, "GUILD")
  end
  return false
end

-- Level-up posts to guild chat, opt-in and off by default: guild chat
-- is shared space, so nothing posts unless the player asks. Guildless,
-- or no chat API, means silence, never an error. Returns true when a
-- line went out, so tests can pin the behavior. A level-up can land
-- somewhere the client refuses chat, in combat or under the messaging
-- lockdown, so a refused ding stashes its level and goes out on a later
-- flush; the latest level wins when two land before the flush.
function xp.maybeGuildDing(level)
  if not xp.opts().guildDing then
    return false
  end
  if type(IsInGuild) ~= "function" or not IsInGuild() then
    return false
  end
  local lvl = level
  if type(lvl) ~= "number" then
    if type(UnitLevel) ~= "function" then
      return false
    end
    lvl = UnitLevel("player")
  end
  if type(lvl) ~= "number" then
    return false
  end
  if ns.combat() or chatLocked() then
    pendingGuildDing = lvl
    return false
  end
  local ok = sendGuild(("Ding %d"):format(math.floor(lvl)))
  if ok then
    pendingGuildDing = nil
  end
  return ok
end

-- Flush a refused ding once the fight ends and the client takes chat
-- back. Called from refresh, which already runs every second and on
-- every event including PLAYER_REGEN_ENABLED, so no new timer and no
-- new event. The attempt consumes the pending level either way: a
-- dropped option, a left guild, or a missing API never retries forever,
-- and a fresh refused ding re-stashes on its own event.
function xp.flushGuildDing()
  if pendingGuildDing == nil then
    return false
  end
  if ns.combat() or chatLocked() then
    return false
  end
  local lvl = pendingGuildDing
  pendingGuildDing = nil
  return xp.maybeGuildDing(lvl)
end

-- The XP bar is the single authoritative award source: each update
-- reconstructs at most one gain from the snapshot delta and stamps it
-- with the receipt time. Actual awarded XP already includes every
-- bonus, so nothing is ever multiplied twice.
local function onXP()
  local snap = xp.readSnapshot()
  if snap.capped then
    baseline = snap
    xp.activateMode(snap)
    return
  end
  if not paused then
    local gained = xp.gain(baseline, snap)
    if gained then
      local stamp = xp.now()
      xp.addAward(rateTracker, stamp, gained)
      xp.addAward(etaTracker, stamp, gained)
      summaryAcc = xp.noteSummaryGain(summaryAcc, stamp, "xp", nil, nil, gained, ns.combat())
    end
  end
  baseline = snap
  xp.refresh()
end

-- The native cluster hides wholesale while the module shows: Blizzard
-- offers no per-bar switch, so watched reputation and honor hide with
-- the XP bar and the setting tooltip says so. Re-applied every
-- refresh because Edit Mode sessions may reshow it; restored the
-- moment the module stops hiding, including the max-level shutdown.
local function applyNativeBar()
  if type(StatusTrackingBarManager) ~= "table" then
    return
  end
  local mgr = StatusTrackingBarManager
  if type(mgr.IsShown) ~= "function" or type(mgr.Hide) ~= "function" or type(mgr.Show) ~= "function" then
    return
  end
  local o = xp.opts()
  local wantHidden = o.enabled and o.hideDefault and mode ~= "dormant"
  if wantHidden then
    if mgr:IsShown() then
      mgr:Hide()
    end
    nativeHiddenByUs = true
  elseif nativeHiddenByUs then
    mgr:Show()
    nativeHiddenByUs = false
  end
end

-- Edit Mode cooperation: the module never joins Edit Mode (no
-- supported API), but an arranging session should include the bar:
-- while Edit Mode is open the bar drags even when locked. Derived,
-- never persisted: a reload mid-session restores the saved lock on
-- its own. No cooperation beyond the two signals: dragging behaves
-- exactly as it always has.
xp.editModeActive = false

function xp.setEditModeActive(active)
  xp.editModeActive = active and true or false
end

local editSubscribed = false

function xp.subscribeEditMode()
  if editSubscribed then
    return
  end
  if type(EventRegistry) ~= "table" then
    return
  end
  if type(EventRegistry.RegisterCallback) ~= "function" then
    return
  end
  local ok = pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", function()
    xp.setEditModeActive(true)
  end)
  local ok2 = pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function()
    xp.setEditModeActive(false)
  end)
  if ok and ok2 then
    editSubscribed = true
  end
end

local function draggable()
  return (not xp.opts().locked) or xp.editModeActive
end

-- One rep estimate for the bar and the tooltip, so they never
-- disagree. Untracked carries guidance; a capped faction carries its
-- cap label; otherwise a synthetic snapshot flows through the same
-- estimator and longer ETA basis as XP.
local function repEstimate(progress)
  if progress == nil then
    return {
      status = "untracked",
      windowSeconds = rateTracker.window,
      observedSeconds = 0,
      windowXp = 0,
      idleSeconds = nil,
      xpPerHour = nil,
      remainingXp = nil,
      etaSeconds = nil,
      unit = "Rep",
    }
  end
  local now = xp.now()
  local snap
  if progress.capped then
    snap = { level = 0, xp = 1, req = 1, capped = false }
  else
    snap = { level = progress.level or 0, xp = progress.have, need = progress.need, capped = false }
  end
  local est = xp.estimate(rateTracker, now, snap, paused)
  est.unit = "Rep"
  if progress.capped and not paused then
    est.status = "rep-capped"
    est.capLabel = progress.capLabel
    est.etaSeconds = nil
    return est
  end
  local longEta = xp.etaSeconds(etaTracker, now, est.remainingXp or 0)
  if est.etaSeconds and (est.remainingXp or 0) > 0 then
    est.etaSeconds = longEta or est.etaSeconds
  end
  return est
end

local function refreshRep(o)
  xp.applyGeometry()
  xp.maybeSwitchRep()
  local progress = repFactionID and xp.readRepProgress(repFactionID) or nil
  local est = repEstimate(progress)
  if progress then
    xp.paintProgress(progress.have, progress.need, nil, xp.repBarLabel(progress))
    xp.applyBarArt(xp.repAtlas(progress))
  else
    xp.paintProgress(0, 1, nil, xp.repBarLabel(nil))
    xp.applyBarArt(xp.XP_ATLAS, xp.FLARE_XP_ATLAS, xp.LEVELUP_XP_ATLAS)
  end
  -- No overlays in rep mode: rested and quest XP don't exist here.
  xp.hideOverlays()
  applyNativeBar()
  xp.barShown(true)
  frame._tip = function()
    xp.showRepTip(est, progress, repWatching)
  end
end

function xp.refresh()
  if not xp.opts().enabled then
    return
  end
  local o = xp.opts()
  local now = xp.now()
  -- Bursts report here: deferred through combat, netted after 0.15s of quiet.
  flushSummary(now)
  xp.flushGuildDing()
  if mode == "dormant" then
    xp.barShown(false)
    applyNativeBar()
    return
  end
  if mode == "rep" then
    refreshRep(o)
    return
  end
  local geo = xp.applyGeometry()
  local est = xp.estimate(rateTracker, now, baseline, paused)
  -- The ETA reads the longer basis (which also prunes it); the rate
  -- window still gates whether any ETA shows at all.
  local longEta = xp.etaSeconds(etaTracker, now, est.remainingXp or 0)
  if est.etaSeconds and (est.remainingXp or 0) > 0 then
    est.etaSeconds = longEta or est.etaSeconds
  end
  local seg = xp.barSegments(baseline, xp.restedAmount(), questXp)
  local label = seg and xp.barLabel(baseline, seg) or nil
  if seg then
    -- Raw XP, never fractions: the template floors animated values,
    -- and the floor of a fraction is a vanished fill.
    xp.paintProgress(baseline.xp, baseline.req, baseline.level, label)
    xp.paintOverlays(geo, seg)
  end
  applyNativeBar()
  xp.barShown(true)
  frame._tip = function()
    xp.showTip(est, seg, questCount, mode, label)
  end
end

-- Modes: leveling characters track XP; max-level characters track
-- reputation (or go dormant when repMode is off). Each mode owns its
-- event set; entering-world, cap-change, regen, and aura signals stay
-- registered in every active mode. Entering a mode restarts
-- observation: a rate never spans two different progressions.

local function setEvents(list, on)
  for _, e in ipairs(list) do
    if on then
      frame:RegisterEvent(e)
    else
      frame:UnregisterEvent(e)
    end
  end
end

local function ensureTicker()
  if not ticker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
    ticker = C_Timer.NewTicker(1, xp.refresh)
  end
end

local function enterXPMode()
  mode = "xp"
  repBaseline = nil
  setEvents(repEvents, false)
  setEvents(xpEvents, true)
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:RegisterEvent("UNIT_AURA")
  ensureTicker()
end

local function enterRepMode()
  mode = "rep"
  setEvents(xpEvents, false)
  setEvents(repEvents, true)
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  frame:RegisterEvent("UNIT_AURA")
  ensureTicker()
  repCache = {}
  xp.scanRepGains() -- seed the cache: arriving gains diff, nothing awards
  local id = xp.resolveRepFaction()
  repBaseline = id and xp.readRepProgress(id) or nil
  resetTrackers()
  paused = false
  local o = xp.opts()
  if not o.repAnnounced then
    o.repAnnounced = true
    xp.sayAnnounce("tracking reputation at max level (/vui xp rep to turn it off)")
  end
end

local function enterDormant()
  mode = "dormant"
  xp.barShown(false)
  paused = false
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
  setEvents(xpEvents, false)
  setEvents(repEvents, false)
  frame:UnregisterEvent("UNIT_AURA")
  -- The ding belongs to the module, not the mode: a dormant mode keeps
  -- PLAYER_LEVEL_UP registered while the module runs, so a level-up that caps
  -- the character still posts. Only a disabled module drops the event (and its deferred ding with it).
  if not xp.opts().enabled then
    frame:UnregisterEvent("PLAYER_LEVEL_UP")
    pendingGuildDing = nil
  end
  applyNativeBar()
end

-- Enter the mode a snapshot calls for. Entering rep mode or waking
-- from dormancy restarts observation; callers already reset when the
-- character itself changed.
function xp.activateMode(snap)
  if not xp.opts().enabled then
    enterDormant()
    return
  end
  if snap.capped and xp.opts().repMode then
    if mode ~= "rep" then
      enterRepMode()
    end
  elseif snap.capped then
    enterDormant()
  elseif mode ~= "xp" then
    resetTrackers()
    paused = false
    enterXPMode()
  else
    enterXPMode()
  end
end

-- Rival XP/reputation bars. Other addons are guests: when an addon
-- known to paint its own XP or reputation bar is loaded, say so once
-- and suggest ours hide. Never touch the rival: no disable, no
-- hiding its frames, no fighting it.
xp.RIVALS = { "ElvUI", "Bartender4", "Dominos" }

function xp.checkRivals()
  if rivalsWarned then
    return false
  end
  if not xp.opts().enabled or mode == "dormant" then
    return false
  end
  local hit = nil
  for _, addon in ipairs(xp.RIVALS) do
    if ns.guests.IsLoaded(addon) then
      hit = addon
      break
    end
  end
  if hit == nil then
    return false
  end
  rivalsWarned = true
  xp.sayAnnounce(hit .. " is loaded: two XP bars may show (/vui xp hides ours)")
  return true
end

local function enteringWorld()
  xp.CheckAnchor()
  xp.subscribeEditMode()
  local o = xp.opts()
  frame:ClearAllPoints()
  frame:SetPoint(o.point, UIParent, o.point, o.x, o.y)
  local snap = xp.readSnapshot()
  local id = nil
  if type(UnitGUID) == "function" then
    id = UnitGUID("player")
  end
  local switched = id ~= identity
  if switched or mode == "dormant" then
    -- New character, first login, or waking from dormancy: fresh
    -- window and a fresh observation gate. Zone loads on the same
    -- character keep history; travel is tracked time.
    identity = id
    resetTrackers()
    paused = false
  end
  baseline = snap -- zone loads carry no timestamped gains: resync, add nothing
  if snap.capped and o.repMode then
    if mode == "rep" and not switched then
      -- Zone load inside rep mode: silent resync, history kept.
      xp.scanRepGains()
      xp.maybeSwitchRep()
      local rid = xp.repTracked()
      repBaseline = rid and xp.readRepProgress(rid) or nil
    else
      enterRepMode()
    end
  else
    xp.activateMode(snap)
  end
  if mode == "xp" then
    xp.scanQuestXp()
  end
  xp.checkRivals() -- a loaded rival bar warns once here; never fought
  if mode ~= "dormant" and o.hideDefault and not o.barAnnounced then
    o.barAnnounced = true
    xp.sayAnnounce("the default XP bar hides while the XP bar shows (/vui help for the switch)")
  end
end

-- Drag to move; position persists in VocUIDB.modules.xp. Lock gates
-- the drag, and an open Edit Mode session tempers the lock.
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function()
  if draggable() then
    xp.dragging = true
    frame:StartMoving()
  end
end)
frame:SetScript("OnDragStop", function()
  xp.dragging = false
  frame:StopMovingOrSizing()
  local o = xp.opts()
  local point, _, _, x, y = frame:GetPoint(1)
  if type(point) == "string" and type(x) == "number" and type(y) == "number" then
    o.point, o.x, o.y = point, math.floor(x + 0.5), math.floor(y + 0.5)
    xp.CheckAnchor()
  end
end)
frame:SetScript("OnEnter", function()
  xp.showBarLabel()
  if frame._tip then
    frame._tip()
  end
end)
frame:SetScript("OnLeave", function()
  xp.hideBarLabel()
  if type(GameTooltip) == "table" then
    GameTooltip:Hide()
  end
end)

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "PLAYER_ENTERING_WORLD" then
    enteringWorld()
  elseif event == "PLAYER_MAX_LEVEL_UPDATE" then
    -- Cap raised (or lowered): re-derive the mode from a fresh
    -- snapshot. A raise wakes everything; staying capped is a no-op.
    baseline = xp.readSnapshot()
    xp.activateMode(baseline)
    xp.refresh()
    return
  else
    if event == "UNIT_AURA" then
      if arg1 ~= "player" then
        return
      end
    elseif event == "PLAYER_XP_UPDATE" then
      onXP()
    elseif event == "PLAYER_LEVEL_UP" then
      xp.maybeGuildDing(arg1)
    elseif event == "UPDATE_FACTION" then
      onRep()
    elseif event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
      onRep(arg1, nil, true)
    elseif event == "FACTION_STANDING_CHANGED" then
      onRep(arg1, arg2, false)
    elseif
      event == "QUEST_LOG_UPDATE"
      or event == "QUEST_TURNED_IN"
      or event == "QUEST_ACCEPTED"
      or event == "QUEST_REMOVED"
      or event == "QUEST_COMPLETE"
    then
      xp.scanQuestXp()
    end
    -- PLAYER_LEVEL_UP only announces: the XP path
    -- is the single authoritative award source, so a ding never awards
    -- here and event order cannot double-count it.
    -- PLAYER_EQUIPMENT_CHANGED, UPDATE_EXHAUSTION, and
    -- PLAYER_UPDATE_RESTING fall through the same way: a rest change
    -- only re-renders, which refreshes the rested and quest lines at
    -- once.
  end
  xp.refresh()
end)

-- The Impl hooks the descriptor delegates to: toggling fully enables
-- or disables the module, so its events register and unregister with
-- the toggle and nothing runs while off.

function xp.InitImpl()
  resetTrackers()
  xp.CheckAnchor()
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_MAX_LEVEL_UPDATE")
  frame:RegisterEvent("PLAYER_LEVEL_UP")
  xp.ApplyEnabledImpl()
end

function xp.ApplyEnabledImpl()
  if xp.opts().enabled then
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_MAX_LEVEL_UPDATE")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    xp.activateMode(xp.readSnapshot())
    xp.refresh()
  else
    enterDormant()
  end
end

function xp.CheckNowImpl()
  if not xp.opts().enabled then
    return
  end
  if mode == "xp" then
    xp.scanQuestXp()
  end
  xp.refresh()
end

function xp.LockImpl()
  local o = xp.opts()
  o.locked = not o.locked
  xp.refresh()
  ns.play(o.locked and "on" or "off")
  ns.say(o.locked and "locked" or "unlocked, drag to move")
end

function xp.PauseImpl()
  paused = not paused
  if not paused then
    -- Resume restarts observation: the paused interval holds no
    -- timestamped awards, so history cannot span it.
    resetTrackers()
    baseline = xp.readSnapshot()
    if mode == "rep" then
      repBaseline = repFactionID and xp.readRepProgress(repFactionID) or nil
    end
  end
  xp.refresh()
  ns.play(paused and "on" or "off")
  ns.say(paused and "paused" or "resumed")
end

function xp.ResetImpl()
  resetTrackers()
  baseline = xp.readSnapshot()
  paused = false
  xp.refresh()
  if mode == "rep" then
    repBaseline = repFactionID and xp.readRepProgress(repFactionID) or nil
  end
  ns.play("on")
  ns.say("session reset")
end

function xp.RepImpl()
  local o = xp.opts()
  o.repMode = not o.repMode
  if o.repMode then
    -- On at cap wakes rep mode at once; leveling picks it up at the cap.
    xp.activateMode(xp.readSnapshot())
  elseif mode == "rep" then
    enterDormant()
  end
  xp.refresh()
  ns.play(o.repMode and "on" or "off")
  ns.say(o.repMode and "reputation tracking on" or "reputation tracking off")
end
