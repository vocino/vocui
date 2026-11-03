local _, ns = ...
local gear = ns.gear
local COLORS = ns.COLORS

-- Character sheet: a Check Bags button and the session item-level gain
-- on the Item Level readout. Both verified against the Camelot
-- PaperDollFrame on the Forever branch: PaperDollFrame_SetItemLevel
-- writes the row's Value text plus its tooltips, and a post-hook
-- re-applies the suffix every time Blizzard rebuilds the row.
gear.sessionStartIlvl = nil -- display item level at login
gear.ilvlHooked = false
gear.ilvlFrame = nil -- last player item-level stat frame seen
gear.sheetButton = nil

-- Blizzard's own display math: floor(max(minItemLevel, avgEquipped)).
-- GetAverageItemLevel is the bare C-side global Blizzard's Camelot
-- PaperDollFrame calls; nil when it has no data yet.
function gear.DisplayIlvl()
  if type(GetAverageItemLevel) ~= "function" then
    return nil
  end
  local ok, _, equipped = pcall(GetAverageItemLevel)
  if not ok or type(equipped) ~= "number" then
    return nil
  end
  local minIlvl = 0
  if type(C_PaperDollInfo) == "table" and type(C_PaperDollInfo.GetMinItemLevel) == "function" then
    local okMin, m = pcall(C_PaperDollInfo.GetMinItemLevel)
    if okMin and type(m) == "number" then
      minIlvl = m
    end
  end
  return math.floor(math.max(minIlvl, equipped))
end

-- Inline color code built from the palette: hardcoded |cff literals
-- never appear outside the palette, so the code is assembled.
function gear.ColorCode(rgb)
  if type(rgb) ~= "table" then
    rgb = COLORS.text
  end
  local function byte(v)
    if type(v) ~= "number" then
      v = 1
    end
    return math.floor(v * 255 + 0.5)
  end
  return string.format("|cff%02x%02x%02x", byte(rgb[1]), byte(rgb[2]), byte(rgb[3]))
end

function gear.CaptureSessionStartImpl()
  if gear.sessionStartIlvl ~= nil then
    return
  end
  local cur = gear.DisplayIlvl()
  if cur ~= nil and cur > 0 then
    gear.sessionStartIlvl = cur
  end
end

function gear.OnItemLevelSet(statFrame, unit)
  if unit ~= "player" then
    return
  end
  if type(statFrame) ~= "table" then
    return
  end
  gear.ilvlFrame = statFrame
  if not gear.opts().sessionIlvl then
    return
  end
  local cur = gear.DisplayIlvl()
  if cur == nil then
    return
  end
  if cur > 0 and gear.sessionStartIlvl == nil then
    gear.sessionStartIlvl = cur
  end
  local start = gear.sessionStartIlvl
  if start == nil then
    return
  end
  local delta = cur - start
  if delta == 0 then
    return
  end
  local gain
  if delta > 0 then
    gain = gear.ColorCode(COLORS.green) .. "(+" .. delta .. ")|r"
  else
    gain = "(" .. delta .. ")" -- a loss reads plain, never alarming red
  end
  local value = statFrame.Value
  if type(value) == "table" and type(value.SetText) == "function" then
    value:SetText(tostring(cur) .. " " .. gain)
  end
  if type(statFrame.tooltip2) == "string" then
    statFrame.tooltip2 = statFrame.tooltip2 .. "\n\nSession: " .. start .. " to " .. cur .. " " .. gain
  end
end

function gear.HookItemLevel()
  if gear.ilvlHooked then
    return
  end
  if type(hooksecurefunc) ~= "function" then
    return
  end
  if type(PaperDollFrame_SetItemLevel) ~= "function" then
    return
  end
  hooksecurefunc("PaperDollFrame_SetItemLevel", gear.OnItemLevelSet)
  gear.ilvlHooked = true
end

function gear.RefreshIlvlSuffixImpl()
  local f = gear.ilvlFrame
  if type(f) ~= "table" then
    return
  end
  if gear.opts().sessionIlvl then
    gear.OnItemLevelSet(f, "player")
  else
    local cur = gear.DisplayIlvl()
    local value = f.Value
    if cur ~= nil and type(value) == "table" and type(value.SetText) == "function" then
      value:SetText(tostring(cur))
    end
  end
end

function gear.IlvlSayImpl()
  local cur = gear.DisplayIlvl()
  if cur == nil then
    ns.say("item level unavailable")
    return
  end
  if cur > 0 and gear.sessionStartIlvl == nil then
    gear.sessionStartIlvl = cur
  end
  local start = gear.sessionStartIlvl
  if start == nil then
    ns.say("ilvl " .. cur)
    return
  end
  local delta = cur - start
  if delta == 0 then
    ns.say("ilvl " .. cur .. " (unchanged since login)")
    return
  end
  ns.say("ilvl " .. cur .. " (session " .. (delta > 0 and "+" or "") .. delta .. " from " .. start .. ")")
end

function gear.PlaceSheetButton()
  local btn = gear.sheetButton
  if not btn then
    return
  end
  btn:ClearAllPoints()
  btn:SetPoint("BOTTOM", PaperDollFrame, "BOTTOM", 0, 6)
end

function gear.EnsureSheetImpl()
  gear.HookItemLevel() -- the sheet loads lazily
  local o = gear.opts()
  if gear.sheetButton then
    gear.sheetButton:SetShown(o.sheetButton ~= false and o.enabled ~= false)
    gear.PlaceSheetButton()
    return
  end
  if PaperDollFrame == nil then
    return
  end
  local btn = CreateFrame("Button", nil, PaperDollFrame, "UIPanelButtonTemplate")
  btn:SetText("Check Bags")
  btn:SetSize(110, 24)
  btn:SetScript("OnClick", function()
    ns.play("on")
    gear.CheckNowImpl()
  end)
  btn:SetScript("OnEnter", function(self)
    if type(GameTooltip) ~= "table" then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Check Bags", COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    GameTooltip:AddLine(
      "Find the best gear in your bags now. Honors every Gear setting",
      COLORS.text[1],
      COLORS.text[2],
      COLORS.text[3],
      true
    )
    if gear.InCombat() then
      GameTooltip:AddLine("does not work in combat", COLORS.red[1], COLORS.red[2], COLORS.red[3], true)
    end
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    if type(GameTooltip) == "table" then
      GameTooltip:Hide()
    end
  end)
  btn:SetShown(o.sheetButton ~= false and o.enabled ~= false)
  gear.sheetButton = btn
  gear.PlaceSheetButton()
end
