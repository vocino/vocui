local _, ns = ...
local xp = ns.xp

-- Rolling estimator: a trailing window over timestamped XP awards. All
-- times are GetTime() seconds: one monotonic clock, never mixed with
-- wall time, and never persisted (monotonic timestamps die with the
-- process). Pure functions; the bar owns the live trackers.

xp.WINDOW = 600 -- trailing rate window, seconds
xp.ETA_WINDOW = 900 -- ETA basis window, seconds
xp.GATE = 30 -- observation before estimates display, seconds
xp.IDLE_AFTER = 60 -- quiet span before the rate admits staleness, seconds

function xp.newTracker(t0, window)
  return { t0 = t0, window = window or xp.WINDOW, events = {}, head = 1, sum = 0 }
end

local function cutoff(tr, now)
  return math.max(tr.t0, now - tr.window)
end

-- Drop events at or before the cutoff: awards exactly at t - W have
-- expired, and an award stamped exactly at session start is a
-- zero-elapsed-time boundary event, excluded the same way.
local function prune(tr, now)
  local c = cutoff(tr, now)
  local evs = tr.events
  while tr.head <= #evs and evs[tr.head].time <= c do
    tr.sum = tr.sum - evs[tr.head].amount
    tr.head = tr.head + 1
  end
  if tr.head > 256 then
    xp.compact(tr)
  end
end

-- Drop leading dead slots; timestamps and sums untouched.
function xp.compact(tr)
  if tr.head <= 1 then
    return
  end
  local fresh = {}
  for i = tr.head, #tr.events do
    fresh[#fresh + 1] = tr.events[i]
  end
  tr.events, tr.head = fresh, 1
end

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Awards are stamped at receipt on a monotonic clock, so receipt order
-- is time order and the queue stays sorted by construction. Zero and
-- non-finite amounts are ignored, never counted.
function xp.addAward(tr, now, amount)
  if not finite(now) or not finite(amount) or amount <= 0 then
    return false
  end
  prune(tr, now)
  tr.events[#tr.events + 1] = { time = now, amount = amount }
  tr.sum = tr.sum + amount
  return true
end

-- Read path: prune even with no new awards, then report the observed
-- duration D and the in-window sum G.
local function observe(tr, now)
  prune(tr, now)
  return now - cutoff(tr, now), tr.sum
end

-- Gap since the freshest surviving in-window award, or nil when the
-- window holds nothing. Called after observe() has pruned, so the
-- last element is the most recent award.
local function lastAwardGap(tr, now)
  local evs = tr.events
  if #evs < tr.head then
    return nil
  end
  return now - evs[#evs].time
end

-- A progression snapshot is one atomic read of level, XP in level,
-- requirement, and the capped flag. Anything outside that shape is
-- rejected, never displayed as a misleading estimate.
function xp.validateSnapshot(snap)
  if type(snap) ~= "table" then
    return false
  end
  if type(snap.capped) ~= "boolean" then
    return false
  end
  if not finite(snap.level) or not finite(snap.xp) then
    return false
  end
  if snap.capped then
    return true
  end
  if not finite(snap.req) or snap.req <= 0 then
    return false
  end
  return snap.xp >= 0 and snap.xp <= snap.req
end

-- Reconstruct the XP gained between two snapshots. Same-level and
-- single-level gains are exact. A multi-level jump has unknown
-- intervening requirements, and a negative same-level delta is a
-- resync, never a negative award: both return nil and add nothing.
function xp.gain(old, new)
  if not xp.validateSnapshot(old) or not xp.validateSnapshot(new) then
    return nil
  end
  if new.capped then
    return nil
  end
  if new.level == old.level then
    if new.xp >= old.xp then
      return new.xp - old.xp
    end
    return nil
  elseif new.level == old.level + 1 then
    return math.max(0, old.req - old.xp + new.xp)
  end
  return nil
end

-- One estimate from the current window and snapshot. XP/hour is the
-- raw rolling rate whenever any time has been observed; the status
-- gates what the ETA may claim. Unknown ETAs stay null with an
-- explicit status; only a genuinely completed threshold reports zero.
function xp.estimate(tr, now, snap, paused)
  local d, g = observe(tr, now)
  local est = {
    status = nil,
    windowSeconds = tr.window,
    observedSeconds = math.max(d, 0),
    windowXp = g,
    idleSeconds = lastAwardGap(tr, now),
    xpPerHour = nil,
    remainingXp = nil,
    etaSeconds = nil,
  }
  if d > 0 then
    est.xpPerHour = g / d * 3600
  end
  if paused then
    est.status = "paused"
    return est
  end
  if type(snap) == "table" and snap.capped then
    est.status = "capped"
    est.xpPerHour = nil
    return est
  end
  if not xp.validateSnapshot(snap) then
    est.status = "unavailable"
    return est
  end
  est.remainingXp = math.max(0, snap.req - snap.xp)
  if est.remainingXp == 0 then
    est.status = "awaiting-level-update"
    est.etaSeconds = 0
    return est
  end
  if est.observedSeconds < xp.GATE then
    est.status = "collecting"
    return est
  end
  if est.observedSeconds < tr.window then
    -- Warming up owns the partial window whatever it holds: an empty
    -- start still fills, and idleness only reads at full span.
    est.status = "warming-up"
  elseif g == 0 then
    est.status = "no-recent-xp"
    return est
  elseif est.idleSeconds ~= nil and est.idleSeconds >= xp.IDLE_AFTER then
    est.status = "idle"
  else
    est.status = "ready"
  end
  if g > 0 then
    est.etaSeconds = est.remainingXp * d / g
  end
  return est
end

-- ETA basis: the same awards over longer memory, so one-off bursts
-- don't rewrite the forecast. Only used when the rate window holds
-- earnings, so the longer sum is never empty here.
function xp.etaSeconds(etaTr, now, remainingXp)
  local d, g = observe(etaTr, now)
  if d <= 0 or g <= 0 then
    return nil
  end
  return remainingXp * d / g
end

local function fmt(n)
  if n >= 1e6 then
    return ("%.1fm"):format(n / 1e6)
  end
  if n >= 1e3 then
    return ("%.0fk"):format(n / 1e3)
  end
  return ("%.0f"):format(n)
end

xp.fmt = fmt

function xp.formatObserved(d)
  local v = math.min(d, xp.WINDOW)
  if v >= 60 then
    return ("%dm"):format(math.floor(v / 60))
  end
  return ("%ds"):format(math.floor(v))
end

function xp.formatIdle(s)
  return ("%dm"):format(math.max(1, math.floor(s / 60)))
end

function xp.formatEta(sec)
  if not finite(sec) then
    return "-"
  end
  if sec < 60 then
    return "<1m"
  end
  local m = math.ceil(sec / 60)
  local h = math.floor(m / 60)
  local r = m % 60
  if h == 0 then
    return ("%dm"):format(m)
  end
  if r == 0 then
    return ("%dh"):format(h)
  end
  return ("%dh%02dm"):format(h, r)
end

function xp.titleText(est)
  if est.status == "paused" then
    return "Paused"
  end
  if est.status == "capped" then
    return "Max level"
  end
  if est.status == "untracked" then
    return "No reputation tracked"
  end
  if est.status == "rep-capped" then
    return est.capLabel or "Rank complete"
  end
  if est.status == "unavailable" then
    return "Unavailable"
  end
  local rate = est.xpPerHour
  -- No pace exists yet on the very first paint (zero elapsed time).
  if rate == nil then
    return "Collecting data"
  end
  local noun = est.unit == "Rep" and " Rep/hr" or " XP/hr"
  local head = fmt(rate) .. noun
  if est.etaSeconds == nil then
    return head
  end
  return head .. " · " .. xp.formatEta(est.etaSeconds)
end

function xp.subText(est)
  local s = est.status
  if s == "paused" then
    return "Tracking paused"
  end
  if s == "capped" then
    return "Max level"
  end
  if s == "unavailable" then
    return est.unit == "Rep" and "Waiting for rep data" or "Waiting for XP data"
  end
  if s == "untracked" then
    return "Watch a faction to track it"
  end
  if s == "rep-capped" then
    return "Rank complete"
  end
  if s == "awaiting-level-update" then
    return est.unit == "Rep" and "Rank complete; awaiting update" or "Level complete; awaiting update"
  end
  if s == "collecting" then
    return "Collecting data"
  end
  local span = xp.formatObserved(est.windowSeconds)
  if s == "no-recent-xp" then
    return (est.unit == "Rep" and "No rep in the last " or "No XP in the last ") .. span
  end
  if s == "warming-up" then
    return "Warming up · last " .. xp.formatObserved(est.observedSeconds) .. " of " .. span
  end
  if s == "idle" then
    return "Idle " .. xp.formatIdle(est.idleSeconds or 0) .. " · last " .. span
  end
  return "Last " .. span
end

-- Bar segments: fractions over the current level: where progress ends,
-- how far ready-to-turn-in quests reach, how far rested XP reaches
-- beyond them. The overlays STACK, in the order you would play them:
-- banked quest XP first, then rested grinding. They never overlap, so
-- each boundary is a hard edge. With no quest XP the rested reach is
-- the native projection, (xp + rested) / req. All clamped to [0, 1];
-- overlays never start before progress. An invalid or capped snapshot
-- has no bar: nil, never zeros that would paint a misleading bar.
function xp.barSegments(snap, restedXp, questXp)
  if not xp.validateSnapshot(snap) or snap.capped then
    return nil
  end
  local r = (type(restedXp) == "number" and restedXp > 0) and restedXp or 0
  local q = (type(questXp) == "number" and questXp > 0) and questXp or 0
  -- Overflow is native-semantics only: (xp + rested) / req, ignoring
  -- the custom quest overlay the native bar never knew.
  local overflowed = (snap.xp + r) / snap.req > 1
  local progress = math.max(0, math.min(1, snap.xp / snap.req))
  local questEnd = math.max(progress, math.min(1, (snap.xp + q) / snap.req))
  local restedEnd = math.max(questEnd, math.min(1, (snap.xp + q + r) / snap.req))
  return {
    progress = progress,
    restedEnd = restedEnd,
    questEnd = questEnd,
    hasRested = r > 0,
    restedOverflow = overflowed,
    hasQuest = q > 0,
    pct = progress * 100,
    restedPct = r / snap.req * 100,
    questPct = q / snap.req * 100,
  }
end

function xp.barLabel(snap, seg)
  local pct = math.floor(seg.pct + 0.5)
  return ("%d  %s/%s (%d%%)"):format(snap.level, fmt(snap.xp), fmt(snap.req), pct)
end

-- The stats line under the bar: ready quests and rested reach in one
-- glance, no hover needed. Same wording as the tooltip lines. Nil when
-- neither shows, so the frame keeps a stable size with an empty slot.
function xp.subStatsLine(seg, count)
  if seg == nil then
    return nil
  end
  local parts = {}
  if count > 0 and seg.questEnd > seg.progress and seg.questPct >= 0.5 then
    local noun = count == 1 and "quest" or "quests"
    parts[#parts + 1] = ("%d %s ready: %d%%"):format(count, noun, math.floor(seg.questPct + 0.5))
  end
  if seg.hasRested and seg.restedPct >= 0.5 then
    parts[#parts + 1] = ("Rested: %d%%"):format(math.floor(seg.restedPct + 0.5))
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, " · ")
end

-- Net gain summary (burst queue): gains arriving in a burst share one
-- deferred chat line instead of one line each. Awards still land in
-- the trackers at once: only this line waits, never the data.
xp.SUMMARY_QUIET = 0.15 -- stillness before a burst reports, seconds

function xp.newSummary()
  return { count = 0, xp = 0, rep = {}, repOrder = {}, lastAt = 0, busySeen = false }
end

-- One gain joins the pending summary. A quiet spell (no new gains for
-- SUMMARY_QUIET outside combat) closes the previous burst first, so a
-- line never spans two separate bursts; combat holds the burst open.
function xp.noteSummaryGain(acc, now, kind, id, factionName, amount, inCombat)
  if not finite(now) or not finite(amount) or amount <= 0 then
    return acc
  end
  if kind ~= "xp" and kind ~= "rep" then
    return acc
  end
  if kind == "rep" then
    if type(id) ~= "number" then
      return acc
    end
    if type(factionName) ~= "string" then
      factionName = "reputation"
    end
  end
  if acc.count > 0 and not inCombat and (now - acc.lastAt) >= xp.SUMMARY_QUIET then
    acc = xp.newSummary()
  end
  acc.count = acc.count + 1
  acc.lastAt = now
  if inCombat then
    acc.busySeen = true
  end
  if kind == "xp" then
    acc.xp = acc.xp + amount
  else
    local bucket = acc.rep[id]
    if bucket == nil then
      bucket = { name = factionName, amount = 0 }
      acc.rep[id] = bucket
      acc.repOrder[#acc.repOrder + 1] = id
    end
    bucket.amount = bucket.amount + amount
  end
  return acc
end

-- The net line for the pending burst, or nil when nothing reportable
-- waits: single gains stay silent, so slow play gains no new chatter.
function xp.formatSummary(acc)
  if acc.count < 2 then
    return nil
  end
  local parts = {}
  if acc.xp > 0 then
    parts[#parts + 1] = "+" .. fmt(acc.xp) .. " XP"
  end
  local total, factions = 0, {}
  for _, id in ipairs(acc.repOrder) do
    local bucket = acc.rep[id]
    if bucket ~= nil and bucket.amount > 0 then
      total = total + bucket.amount
      factions[#factions + 1] = bucket.name .. " " .. fmt(bucket.amount)
    end
  end
  if total > 0 then
    if #factions == 1 then
      local only = acc.rep[acc.repOrder[1]]
      parts[#parts + 1] = "+" .. fmt(total) .. " rep with " .. only.name
    else
      parts[#parts + 1] = "+" .. fmt(total) .. " rep (" .. table.concat(factions, ", ") .. ")"
    end
  end
  if #parts == 0 then
    return nil
  end
  local line = table.concat(parts, ", ")
  if acc.busySeen then
    line = line .. " in combat"
  end
  return line
end
