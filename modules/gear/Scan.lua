local _, ns = ...
local gear = ns.gear

-- Scanning and equipping: the event-driven heart of the module. One
-- equip per scan; the next bag update handles the rest, so valuations
-- stay correct as gear changes. Nothing acts in combat, while dead, or
-- in a pet battle, and a loop guard keeps two verdicts from fighting
-- over one slot.

gear.scanning = false
gear.SWAP_COOLDOWN = 30 -- seconds a displaced link is skipped
gear.SETTLE_WINDOW = 10 -- seconds a slot we equipped into is left alone
gear.BREAKER_WINDOW = 60 -- sliding window for same-slot re-equips
gear.BREAKER_TRIPS = 3 -- our equips to one slot in-window that pause auto-equip
gear.BREAKER_PAUSE = 60 -- pause length in seconds
gear.UNSURE_RETRIES = 5 -- consecutive unsure scans before going quiet
gear.equippedSnap = nil -- slotID -> link at the last scan's start
gear.recentSwap = {} -- link -> timestamp when it was displaced
gear.slotTouches = {} -- slotID -> timestamps of OUR equips
gear.pausedUntil = nil
gear.ourEquipPending = false
gear.retryPending = false
gear.unsureStreak = 0

function gear.SnapshotEquipped()
  local snap = {}
  for slotID = 1, 19 do
    snap[slotID] = GetInventoryItemLink("player", slotID)
  end
  return snap
end

function gear.NoteDisplacement(prevLink, newLink, slotID, now)
  if prevLink then
    gear.recentSwap[prevLink] = now
  end
  if newLink and gear.ourEquipPending then
    local fresh = {}
    for _, t in ipairs(gear.slotTouches[slotID] or {}) do
      if now - t < gear.BREAKER_WINDOW then
        fresh[#fresh + 1] = t
      end
    end
    fresh[#fresh + 1] = now
    gear.slotTouches[slotID] = fresh
    if #fresh >= gear.BREAKER_TRIPS then
      gear.pausedUntil = now + gear.BREAKER_PAUSE
      if gear.opts().announce then
        ns.say("equip loop detected, auto-equip paused 60s (/vui gear on resumes now)")
      end
    end
  end
end

function gear.TrackSwaps()
  local now = GetTime()
  local snap = gear.SnapshotEquipped()
  if gear.equippedSnap then
    for slotID = 1, 19 do
      local prev, cur = gear.equippedSnap[slotID], snap[slotID]
      if cur ~= prev then
        gear.NoteDisplacement(prev, cur, slotID, now)
      end
    end
    gear.TrackSetCrossings(gear.equippedSnap, snap)
  end
  gear.equippedSnap = snap
  gear.ourEquipPending = false
  for link, t in pairs(gear.recentSwap) do
    if now - t >= gear.SWAP_COOLDOWN then
      gear.recentSwap[link] = nil
    end
  end
end

function gear.SlotSettling(slotID, now)
  if not slotID then
    return false
  end
  for _, t in ipairs(gear.slotTouches[slotID] or {}) do
    if now - t < gear.SETTLE_WINDOW then
      return true
    end
  end
  return false
end

function gear.IsPaused()
  return gear.pausedUntil ~= nil and GetTime() < gear.pausedUntil
end

function gear.ClearGuard()
  gear.pausedUntil = nil
  gear.slotTouches = {}
  gear.recentSwap = {}
end

-- Rival auto-equippers (outfit and gear-set swappers): two writers
-- ping-pong over slots, so when one is loaded Gear warns once and
-- stands down instead of fighting it. An explicit "/vui gear on"
-- resumes anyway: the player's choice wins.
gear.RIVALS = { Outfitter = "outfit swaps", ItemRack = "gear-set swaps" }
gear.rivalWarned = {}
gear.rivalStoodDown = false

function gear.CheckRival(addonName)
  if type(addonName) ~= "string" then
    return
  end
  local reason = gear.RIVALS[addonName]
  if not reason then
    return
  end
  if gear.rivalWarned[addonName] then
    return
  end
  gear.rivalWarned[addonName] = true
  gear.rivalStoodDown = true
  ns.say(
    "standing down: "
      .. addonName
      .. " is loaded and also changes gear ("
      .. reason
      .. "), so our equips would fight it (/vui gear on resumes anyway)"
  )
end

function gear.CheckRivalsLoaded()
  for rivalName in pairs(gear.RIVALS) do
    if ns.guests.IsLoaded(rivalName) then
      gear.CheckRival(rivalName)
    end
  end
end

-- Restricted states where the client forbids equipment changes without
-- combat lockdown: dead or ghost, and pet battles. Both reads are
-- presence-gated and fail open.
function gear.Restricted()
  if type(UnitIsDeadOrGhost) == "function" then
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    if ok and dead then
      return true
    end
  end
  if type(C_PetBattles) == "table" and type(C_PetBattles.IsInBattle) == "function" then
    local ok, battle = pcall(C_PetBattles.IsInBattle)
    if ok and battle then
      return true
    end
  end
  return false
end

function gear.RetrySoon()
  if gear.retryPending then
    return
  end
  if not (type(C_Timer) == "table" and type(C_Timer.After) == "function") then
    return
  end
  gear.retryPending = true
  C_Timer.After(5, function()
    gear.retryPending = false
    gear.Scan()
  end)
end

-- Returns true when an equip happened (the scan stops for this pass).
function gear.Equip(link, ev, slotID)
  local o = gear.opts()
  local paused = gear.IsPaused()
  if o.audit or paused then
    if o.announce and not gear.flagged[link] then
      gear.flagged[link] = true
      local reason = paused and " (paused: loop guard)" or " (audit mode)"
      ns.say("would equip " .. link .. gear.Why(ev) .. reason)
    end
    return false
  end
  if ns.combat() then
    return false
  end
  if gear.Restricted() then
    gear.RetrySoon()
    return false
  end
  local checkSlot = slotID
  if not checkSlot then
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    checkSlot = equipLoc and gear.HomeSlot(equipLoc)
  end
  if checkSlot and gear.SlotSettling(checkSlot, GetTime()) and GetInventoryItemLink("player", checkSlot) then
    if o.announce and not gear.flagged[link] then
      gear.flagged[link] = true
      ns.say("would equip " .. link .. gear.Why(ev) .. " (slot settling)")
    end
    gear.RetrySoon()
    return false
  end
  -- C_Item.EquipItemByName (verified on the Forever branch). A missing
  -- namespace is announced once instead of erroring on every scan.
  if not (type(C_Item) == "table" and type(C_Item.EquipItemByName) == "function") then
    if o.announce and not gear.flagged[link] then
      gear.flagged[link] = true
      ns.say("cannot equip on this client (C_Item.EquipItemByName is missing): " .. link)
    end
    return false
  end
  gear.ourEquipPending = true
  if slotID then
    C_Item.EquipItemByName(link, slotID)
  else
    C_Item.EquipItemByName(link)
  end
  gear.playEquipSound()
  if o.announce then
    ns.say("equipped " .. link .. gear.Why(ev))
  end
  return true
end

function gear.CheckNowImpl()
  gear.unsureStreak = 0 -- a manual look re-arms quieted retries
  gear.flagged = {}
  gear.Scan()
end

-- Re-entrancy shell: a thrown pass must never wedge gear.scanning on.
-- The error itself still surfaces so a real bug stays loud.
function gear.Scan()
  local ok, err = pcall(gear.ScanInner)
  gear.scanning = false
  if not ok then
    error(err, 0)
  end
end

function gear.ScanInner()
  if gear.scanning then
    return
  end
  local o = gear.opts()
  if not o.enabled then
    return
  end
  if gear.rivalStoodDown then
    return
  end
  if ns.combat() then
    return
  end
  if gear.Restricted() then
    gear.RetrySoon()
    return
  end
  gear.TrackSwaps()
  gear.scanning = true
  local setCtx = gear.SetContext()
  local unsure = false
  -- Candidate links: Syndicator's bag cache when it is present and
  -- settled (it already walked the bags for Baganator), else the
  -- Blizzard bag walk. Either way the verdicts are ours.
  local links = ns.inventory and ns.inventory.BagLinks and ns.inventory.BagLinks() or nil
  local function scanOne(link)
    if not link then
      return false
    end
    local okEv, ev = pcall(gear.Evaluate, link)
    if not okEv or ev == nil then
      unsure = true
      return false
    end
    if gear.recentSwap[link] then
      return false
    end
    local readyThreshold, readySet = gear.SetCompletionReady(setCtx, link)
    if not ev.upgrade and not readyThreshold then
      return false
    end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    local pair = equipLoc and gear.slotPairs[equipLoc]
    if equipLoc == nil or (pair and not o.autoTwoSlot) then
      if ev.upgrade then
        gear.Announce(link, ev)
      end
      return false
    end
    if pair then
      return gear.ScanTwoSlot(link, ev, o, setCtx, readyThreshold, readySet)
    end
    return gear.ScanSingle(link, ev, o, setCtx, readyThreshold, readySet)
  end
  -- One equip per scan; the next bag update handles the rest, so
  -- valuations stay correct as gear changes.
  if links then
    for _, link in ipairs(links) do
      if scanOne(link) then
        gear.scanning = false
        return
      end
    end
  else
    ns.inventory.EachSlot(function(_, _, _, link)
      if scanOne(link) then
        gear.scanning = false
        return true
      end
      return false
    end)
  end
  gear.scanning = false
  -- Items nobody could answer yet get a few retries for slow caches,
  -- then go quiet until the next bag event so unresolvable links can't
  -- churn.
  if unsure then
    gear.unsureStreak = gear.unsureStreak + 1
    if gear.unsureStreak <= gear.UNSURE_RETRIES then
      gear.RetrySoon()
    end
  else
    gear.unsureStreak = 0
  end
end

-- Two-slot candidate: resolve the target slot, then the shared gates.
-- Returns true when an equip happened.
function gear.ScanTwoSlot(link, ev, o, setCtx, readyThreshold, readySet)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  local slotID = gear.ResolveTwoSlotSlot(equipLoc, ev, link)
  if not slotID then
    if ev.upgrade then
      gear.Announce(link, ev)
    end
    return false
  end
  local held = GetInventoryItemLink("player", slotID)
  local otherHeld
  for _, s in ipairs(gear.slotPairs[equipLoc]) do
    if s ~= slotID then
      otherHeld = GetInventoryItemLink("player", s)
    end
  end
  local breakThreshold, breakSet = gear.SetBreaks(setCtx, link, held)
  local completes = gear.SetSwapCompletes(held, readyThreshold, readySet)
  if o.keepHeirlooms and gear.IsHeirloom(held) then
    gear.AnnounceHeirloom(link, held)
  elseif breakThreshold then
    gear.AnnounceSetBreak(link, breakSet, breakThreshold)
  elseif gear.UniqueConflict(link, otherHeld) then
    gear.AnnounceUnique(link, otherHeld)
  elseif ev.upgrade or completes then
    if completes then
      ev.completes = gear.BonusLabel(readySet, completes)
    end
    if gear.Equip(link, ev, slotID) then
      return true
    end
  end
  return false
end

-- Single-slot candidate: weapon gates, then the shared gates. Returns
-- true when an equip happened.
function gear.ScanSingle(link, ev, o, setCtx, readyThreshold, readySet)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  local slotID = equipLoc and gear.HomeSlot(equipLoc)
  local held = slotID and GetInventoryItemLink("player", slotID)
  local breakThreshold, breakSet = gear.SetBreaks(setCtx, link, held)
  local completes = gear.SetSwapCompletes(held, readyThreshold, readySet)
  local handSwap = gear.HandCrosses(link, held)
  if gear.IsFishingRod(held) then
    gear.AnnounceFishingRod(link, held)
  elseif o.keepHeirlooms and gear.IsHeirloom(held) then
    gear.AnnounceHeirloom(link, held)
  elseif gear.WeaponKindCrosses(link, held) then
    gear.AnnounceWeaponKind(link, ev)
  elseif gear.OffhandStrands(link) then
    gear.AnnounceOffhand(link, ev)
  elseif handSwap and not o.swapWeapons then
    gear.AnnounceHandSwap(link, ev)
  elseif not o.swapWeapons and gear.WeaponTypeCrosses(link, held) then
    gear.AnnounceWeaponType(link, ev)
  elseif breakThreshold then
    gear.AnnounceSetBreak(link, breakSet, breakThreshold)
  elseif ev.upgrade or completes then
    if completes then
      ev.completes = gear.BonusLabel(readySet, completes)
    end
    if handSwap then
      ev.handSwap = true
    end
    if gear.Equip(link, ev, nil) then
      return true
    end
  end
  return false
end

-- Events. Toggling the module fully enables or disables it: its scan
-- events register and unregister with the toggle (CRAFT paradigm 3).
local SCAN_EVENTS = {
  "BAG_UPDATE_DELAYED",
  "PLAYER_REGEN_ENABLED",
  "PLAYER_LEVEL_UP",
  "PLAYER_SPECIALIZATION_CHANGED",
  "GET_ITEM_INFO_RECEIVED",
}

function gear.ApplyEnabledImpl()
  if not gear.frame then
    return
  end
  local on = gear.opts().enabled
  for _, event in ipairs(SCAN_EVENTS) do
    if on then
      gear.frame:RegisterEvent(event)
    else
      gear.frame:UnregisterEvent(event)
    end
  end
end

function gear.InitImpl()
  gear.opts() -- fill VocUIDB.modules.gear from defaults
  if gear.RegisterBaganatorPlugin then
    gear.RegisterBaganatorPlugin()
  end
  local frame = CreateFrame("Frame")
  gear.frame = frame
  frame:RegisterEvent("ADDON_LOADED")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  gear.ApplyEnabledImpl()
  frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "GET_ITEM_INFO_RECEIVED" then
      gear.PatchPending(arg1, arg2)
      return
    end
    if event == "ADDON_LOADED" then
      gear.CheckRival(arg1)
      if gear.EnsureSheetImpl then
        gear.EnsureSheetImpl()
      end
      return
    end
    if event == "PLAYER_ENTERING_WORLD" then
      gear.CheckRivalsLoaded()
      if gear.CaptureSessionStartImpl then
        gear.CaptureSessionStartImpl()
      end
      if gear.EnsureSheetImpl then
        gear.EnsureSheetImpl()
      end
    end
    gear.Scan()
  end)
  gear.CheckRivalsLoaded()
end
