local _, ns = ...
local xp = ns.xp

-- The bar, built the way Blizzard builds its own ExpStatusBarTemplate:
-- a StatusBar wearing the native XP fill atlases, the native
-- background, blue rested and gold quest overlays on classic bar
-- grain, and a GameFontHighlight label. Sized from the live native
-- geometry every refresh, so the stroke and ticks land at 1:1.

xp.BAR_WIDTH = 571 -- Mainline container width, the fallback everywhere
xp.TROUGH_WIDTH = 565 -- InitializeBars seats the bar at container minus 6
xp.TROUGH_HEIGHT = 11
xp.MAX_SEGMENTS = 40 -- validation ceiling, twice the widest native bar
xp.ART_HEIGHT = 17 -- the native container height; rate and stats live below it
xp.FRAME_HEIGHT = 55 -- art zone, rate line, and stats line
xp.XP_ATLAS = "UI-HUD-ExperienceBar-Fill-Experience"
xp.RESTED_ATLAS = "UI-HUD-ExperienceBar-Fill-Rested"
xp.BG_ATLAS = "UI-HUD-ExperienceBar-Background"
xp.FRAME_ATLAS = "UI-HUD-ExperienceBar-Frame"
xp.PIP_ATLAS = "UI-HUD-ExperienceBar-Frame-Pip"
xp.DIVIDER_ATLAS = "ui-hud-experiencebar-divider" -- Camelot segment ticks
xp.FLARE_XP_ATLAS = "UI-HUD-ExperienceBar-Flare-XP-2x-Flipbook"
xp.FLARE_RESTED_ATLAS = "UI-HUD-ExperienceBar-Flare-Rested-2x-Flipbook"
xp.LEVELUP_XP_ATLAS = "UI-HUD-ExperienceBar-Fill-Experience-2x-Flipbook"
xp.LEVELUP_RESTED_ATLAS = "UI-HUD-ExperienceBar-Fill-Rested-2x-Flipbook"

local frame = CreateFrame("Frame", "VocUIXPFrame", UIParent)
xp.frame = frame
frame:SetSize(xp.BAR_WIDTH, xp.FRAME_HEIGHT)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true) -- hover tooltip always; lock gates dragging, not looking

-- The animated template is Blizzard's own XP-bar machinery (gain flare,
-- level-up flash, ding wrap); a client without it gets a plain bar.
local barOk, animatedBar = pcall(CreateFrame, "StatusBar", nil, frame, "GradualAnimatedStatusBarTemplate")
-- Animated when the template exists (its mixin methods are
-- presence-gated at every use); a plain StatusBar otherwise.
local bar = (barOk and animatedBar) or CreateFrame("StatusBar", nil, frame)
local hasAnimatedBar = barOk and animatedBar ~= nil
-- InitializeBars seats the trough at (1, -1) of the container,
-- resized every refresh from the live native geometry (see below).
bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
bar:SetSize(xp.TROUGH_WIDTH, xp.TROUGH_HEIGHT)
if not hasAnimatedBar then
  -- Plain bars have no SetBarTexture: the file texture plus a 0..1
  -- range until the first refresh paints real values.
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
end

-- Atlases are Blizzard's own art. A missing atlas hides its layer
-- instead of erroring, so a client without one still shows the bar.
local function setAtlasOrHide(tex, atlas, useSize)
  if pcall(function()
    tex:SetAtlas(atlas, useSize)
  end) then
    return true
  end
  tex:Hide()
  return false
end

local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(bar)
setAtlasOrHide(bg, xp.BG_ATLAS, false)

local restFill = bar:CreateTexture(nil, "ARTWORK", nil, -1)
restFill:SetPoint("LEFT", bar, "LEFT", 0, 0)
restFill:SetPoint("TOP", bar, "TOP", 0, 0)
restFill:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
restFill:SetWidth(0)
-- Blizzard's own bar grain under a blue tint: atlas fills all read
-- purple-family, and a flat color lost the texture. The classic
-- statusbar file is neutral grain, so the tint renders true.
restFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
restFill:SetVertexColor(ns.COLORS.rest[1], ns.COLORS.rest[2], ns.COLORS.rest[3])
restFill:Hide()

local questFill = bar:CreateTexture(nil, "ARTWORK", nil, 0)
questFill:SetPoint("TOP", bar, "TOP", 0, 0)
questFill:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
questFill:SetWidth(0)
-- Banked quest XP wears the same classic grain under a deeper gold
-- tint: the flat slab read correct but foreign next to the fills.
questFill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
questFill:SetVertexColor(ns.COLORS.quest[1], ns.COLORS.quest[2], ns.COLORS.quest[3])
questFill:Hide()

-- The stroke around the bar and the rested pip: the same two atlas
-- layers Blizzard's own bar wears; the stroke hangs on the frame.
local frameTex = frame:CreateTexture(nil, "OVERLAY")
frameTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
frameTex:SetSize(xp.BAR_WIDTH, xp.ART_HEIGHT)
setAtlasOrHide(frameTex, xp.FRAME_ATLAS, false)

local pip = bar:CreateTexture(nil, "OVERLAY", nil, 1)
pip:SetSize(10, 14)
local pipOk = setAtlasOrHide(pip, xp.PIP_ATLAS, false)
pip:Hide()
-- Unknown font objects error at creation, so the label resolves its
-- white face with a fallback to gold.
local function makeFont(parent, template, fallback)
  local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", template)
  if ok and fs ~= nil then
    return fs
  end
  return parent:CreateFontString(nil, "OVERLAY", fallback)
end
local barText = makeFont(bar, "GameFontHighlight", "GameFontNormal")
barText:SetPoint("CENTER", bar, "CENTER", 0, 1)
barText:SetShadowOffset(1, -1)

-- Snap every region to the pixel grid: Blizzard rounds layout natively,
-- so fractional widths and drag positions render crisp instead of blurred.
local function snapRegion(region)
  if region ~= nil and type(region.SetRoundLayoutToNearestPixel) == "function" then
    pcall(region.SetRoundLayoutToNearestPixel, region, true)
  end
end
snapRegion(frame)
snapRegion(bar)
snapRegion(bg)
snapRegion(restFill)
snapRegion(questFill)
snapRegion(frameTex)
snapRegion(pip)
snapRegion(barText)

-- The rate line under the art zone: XP/hr and time-to-level, always visible.
local rate = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
rate:SetPoint("TOP", frame, "TOP", 0, -(xp.ART_HEIGHT + 5))
rate:SetShadowOffset(1, -1)
snapRegion(rate)

-- The stats line under the rate line: ready quests and rested reach,
-- always visible, in the standard face with the 1px shadow.
local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
sub:SetPoint("TOP", rate, "BOTTOM", 0, -2)
sub:SetShadowOffset(1, -1)
snapRegion(sub)
sub:Hide()

-- Native geometry: the native bar is not one size. Mainline seats a
-- 571x17 container (565x11 trough, no segments) while Camelot seats
-- 1192x17 (1189x14, 20 segment divider ticks). The module reads the
-- live numbers every refresh and wears them, so the stroke, trough,
-- and ticks land at 1:1. Every read validates and falls back to the
-- Mainline numbers; a missing native bar is never an error.
function xp.nativeGeometry()
  local width, segments, adjust, pipY = nil, nil, nil, nil
  local mgr = StatusTrackingBarManager
  local container = type(mgr) == "table" and mgr.MainStatusTrackingBarContainer or nil
  if type(container) == "table" then
    if type(container.GetWidth) == "function" then
      local ok, w = pcall(container.GetWidth, container)
      if ok and type(w) == "number" and w >= 200 and w <= 3000 then
        width = w
      end
    end
    if type(container.GetExpectedSegments) == "function" then
      local ok, s = pcall(container.GetExpectedSegments, container)
      if ok and type(s) == "number" and s >= 1 and s <= xp.MAX_SEGMENTS then
        segments = math.floor(s)
      end
    end
  end
  if
    width == nil
    and type(STATUS_BAR_CONTAINER_WIDTH) == "number"
    and STATUS_BAR_CONTAINER_WIDTH >= 200
    and STATUS_BAR_CONTAINER_WIDTH <= 3000
  then
    width = STATUS_BAR_CONTAINER_WIDTH
  end
  if
    segments == nil
    and type(STATUS_BAR_NUM_SEGMENTS) == "number"
    and STATUS_BAR_NUM_SEGMENTS >= 1
    and STATUS_BAR_NUM_SEGMENTS <= xp.MAX_SEGMENTS
  then
    segments = math.floor(STATUS_BAR_NUM_SEGMENTS)
  end
  if
    type(STATUS_BAR_SIZE_ADJUSTMENT) == "number"
    and STATUS_BAR_SIZE_ADJUSTMENT >= 0
    and STATUS_BAR_SIZE_ADJUSTMENT <= 16
  then
    adjust = STATUS_BAR_SIZE_ADJUSTMENT
  end
  if
    type(EXHAUSTION_TICK_OFFSET_Y) == "number"
    and EXHAUSTION_TICK_OFFSET_Y >= -8
    and EXHAUSTION_TICK_OFFSET_Y <= 8
  then
    pipY = EXHAUSTION_TICK_OFFSET_Y
  end
  width = width or xp.BAR_WIDTH
  segments = segments or 1
  adjust = adjust or 6
  pipY = pipY or 2
  return {
    width = width,
    segments = segments,
    troughW = width - adjust,
    troughH = xp.ART_HEIGHT - adjust,
    pipY = pipY,
  }
end

-- Segment ticks, Camelot's divider look. The native template draws
-- them when it exists; otherwise a small frame wears the divider
-- atlas by hand, and hides when the atlas is missing too.
local dividers = {}

local function ensureDivider(i)
  if dividers[i] ~= nil then
    return dividers[i]
  end
  local ok, d = pcall(CreateFrame, "Frame", nil, frame, "StatusBarDividerTemplate")
  if ok and d ~= nil then
    snapRegion(d)
    dividers[i] = d
    return d
  end
  local f = CreateFrame("Frame", nil, frame)
  f:SetSize(3, 10)
  local tex = f:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(f)
  f.usable = setAtlasOrHide(tex, xp.DIVIDER_ATLAS, false)
  snapRegion(f)
  snapRegion(tex)
  dividers[i] = f
  return f
end

-- Seat the frame, trough, stroke, and ticks on the live native
-- geometry. Runs every refresh but only moves regions when the
-- numbers change (a gamepad toggle resizes native mid-session).
local appliedGeo = nil

function xp.applyGeometry()
  local geo = xp.nativeGeometry()
  if
    appliedGeo ~= nil
    and appliedGeo.width == geo.width
    and appliedGeo.segments == geo.segments
    and appliedGeo.troughW == geo.troughW
    and appliedGeo.troughH == geo.troughH
  then
    return geo
  end
  appliedGeo = geo
  frame:SetSize(geo.width, xp.FRAME_HEIGHT)
  bar:SetSize(geo.troughW, geo.troughH)
  frameTex:SetSize(geo.width, xp.ART_HEIGHT)
  local ticks = geo.segments - 1
  for i = 1, ticks do
    local d = ensureDivider(i)
    d:ClearAllPoints()
    d:SetPoint("LEFT", frame, "TOPLEFT", geo.width / geo.segments * i, -xp.ART_HEIGHT / 2)
    d:SetShown(d.usable ~= false)
  end
  local i = ticks + 1
  while dividers[i] ~= nil do
    dividers[i]:SetShown(false)
    i = i + 1
  end
  return geo
end

-- One texture swap for both modes: the animated template takes atlas
-- names, the plain-bar fallback paints its fill texture instead.
-- The animated template's mixin methods live outside the checker's
-- StatusBar shape, so resolve them once here; every use below stays
-- presence-gated, and the plain-bar fallback never touches them.
---@diagnostic disable-next-line: undefined-field
local setBarTexture = bar.SetBarTexture
---@diagnostic disable-next-line: undefined-field
local setAnimationTextures = bar.SetAnimationTextures
---@diagnostic disable-next-line: undefined-field
local setAnimatedValues = bar.SetAnimatedValues

function xp.applyBarArt(fillAtlas, flareAtlas, levelupAtlas)
  if type(setBarTexture) == "function" then
    pcall(setBarTexture, bar, fillAtlas)
  elseif type(bar.GetStatusBarTexture) == "function" then
    local fill = bar:GetStatusBarTexture()
    if fill ~= nil then
      pcall(function()
        fill:SetAtlas(fillAtlas, false)
      end)
    end
  end
  if type(setAnimationTextures) == "function" then
    pcall(setAnimationTextures, bar, flareAtlas, levelupAtlas)
  end
end

function xp.paintProgress(have, need, level, label)
  if type(setAnimatedValues) == "function" then
    -- Level wraps the ding animation through full and around; maxLevel
    -- stays nil, which the template reads as never-capped, true
    -- whenever the module shows. Raw values, never fractions: the
    -- template floors animated values, and the floor of a fraction is
    -- a vanished fill.
    setAnimatedValues(bar, have, 0, need, level)
  else
    bar:SetMinMaxValues(0, need)
    bar:SetValue(have)
  end
  barText:SetText(label)
end

function xp.paintOverlays(geo, seg)
  local isRested = seg ~= nil and seg.hasRested
  xp.applyBarArt(
    isRested and xp.RESTED_ATLAS or xp.XP_ATLAS,
    isRested and xp.FLARE_RESTED_ATLAS or xp.FLARE_XP_ATLAS,
    isRested and xp.LEVELUP_RESTED_ATLAS or xp.LEVELUP_XP_ATLAS
  )
  if isRested then
    restFill:SetWidth(seg.restedEnd * geo.troughW)
    -- Crop, never stretch: the grain maps across the full bar width,
    -- so each span keeps its native shading at any width.
    restFill:SetTexCoord(0, seg.restedEnd, 0, 1)
    restFill:Show()
  else
    restFill:Hide()
  end
  if seg ~= nil and seg.questEnd > seg.progress then
    questFill:ClearAllPoints()
    questFill:SetPoint("LEFT", bar, "LEFT", seg.progress * geo.troughW, 0)
    questFill:SetPoint("TOP", bar, "TOP", 0, 0)
    questFill:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    questFill:SetWidth((seg.questEnd - seg.progress) * geo.troughW)
    questFill:SetTexCoord(seg.progress, seg.questEnd, 0, 1)
    questFill:Show()
  else
    questFill:Hide()
  end
  -- The rested pip rides the rested reach, hidden at the bar edges
  -- like the native one (hideAtBarEdge), and hidden without rested.
  if pipOk and isRested and seg.restedEnd >= 0.01 and seg.restedEnd <= 0.99 then
    pip:ClearAllPoints()
    pip:SetPoint("CENTER", bar, "LEFT", seg.restedEnd * geo.troughW, geo.pipY)
    pip:Show()
  else
    pip:Hide()
  end
end

-- Rep mode paints no overlays: rested and quest XP don't exist there.
function xp.hideOverlays()
  restFill:Hide()
  questFill:Hide()
  pip:Hide()
end

function xp.paintLines(title, stats)
  rate:SetText(title)
  if stats then
    sub:SetText(stats)
    sub:Show()
  else
    sub:Hide()
  end
end

-- The tooltip carries the engine the bar replaced: the rate line, the
-- rested and quest reach, the bonus list, and the missing list. It
-- never fires mid-drag: the module's own drag flag guards it, which
-- keeps the promise without touching an unverified global.
xp.dragging = false

local function tipBase()
  if xp.dragging then
    return false
  end
  if type(GameTooltip) ~= "table" then
    return false
  end
  GameTooltip:SetOwner(frame, "ANCHOR_TOP")
  GameTooltip:ClearLines()
  return true
end

local function tipClose()
  GameTooltip:AddLine(
    "/vui xp shows or hides it. /vui help lists the rest",
    ns.COLORS.muted[1],
    ns.COLORS.muted[2],
    ns.COLORS.muted[3],
    true
  )
  GameTooltip:Show()
end

function xp.showTip(est, seg, questCount, mode)
  if not tipBase() then
    return
  end
  if mode == "rep" then
    xp.showRepTip(est)
    return
  end
  GameTooltip:SetText("XP", ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3])
  GameTooltip:AddLine(xp.titleText(est), ns.COLORS.text[1], ns.COLORS.text[2], ns.COLORS.text[3], true)
  GameTooltip:AddLine(xp.subText(est), ns.COLORS.muted[1], ns.COLORS.muted[2], ns.COLORS.muted[3], true)
  if seg then
    if seg.hasRested and seg.restedPct >= 0.5 then
      local pct = math.floor(seg.restedPct + 0.5)
      GameTooltip:AddLine(
        ("Rested: %d%% of level"):format(pct),
        ns.COLORS.text[1],
        ns.COLORS.text[2],
        ns.COLORS.text[3],
        true
      )
    end
    if questCount > 0 and seg.questEnd > seg.progress and seg.questPct >= 0.5 then
      local pct = math.floor(seg.questPct + 0.5)
      local noun = questCount == 1 and "quest" or "quests"
      GameTooltip:AddLine(
        ("%d %s ready: %d%% of level"):format(questCount, noun, pct),
        ns.COLORS.text[1],
        ns.COLORS.text[2],
        ns.COLORS.text[3],
        true
      )
    end
  end
  xp.tipBonuses(mode, nil)
  tipClose()
end

function xp.showRepTip(est, progress, watching)
  if not tipBase() then
    return
  end
  GameTooltip:SetText("XP", ns.COLORS.gold[1], ns.COLORS.gold[2], ns.COLORS.gold[3])
  GameTooltip:AddLine(xp.titleText(est), ns.COLORS.text[1], ns.COLORS.text[2], ns.COLORS.text[3], true)
  GameTooltip:AddLine(xp.subText(est), ns.COLORS.muted[1], ns.COLORS.muted[2], ns.COLORS.muted[3], true)
  if progress then
    local stats = xp.repStatsLine(progress)
    if stats then
      GameTooltip:AddLine(progress.name .. ": " .. stats, ns.COLORS.text[1], ns.COLORS.text[2], ns.COLORS.text[3], true)
    else
      GameTooltip:AddLine(
        progress.name .. " · " .. progress.capLabel,
        ns.COLORS.text[1],
        ns.COLORS.text[2],
        ns.COLORS.text[3],
        true
      )
    end
    if progress.pending then
      GameTooltip:AddLine("Paragon reward pending", ns.COLORS.green[1], ns.COLORS.green[2], ns.COLORS.green[3], true)
    end
  end
  xp.tipBonuses("rep", progress)
  if progress then
    GameTooltip:AddLine(
      watching and "Following watched faction" or "Following latest gains",
      ns.COLORS.muted[1],
      ns.COLORS.muted[2],
      ns.COLORS.muted[3],
      true
    )
  end
  tipClose()
end

-- Bonus and missing lines, shared by both tooltips. Red appears only
-- for state: nothing active is a state worth noticing.
function xp.tipBonuses(mode, progress)
  local bonuses = xp.bonusParts(mode, progress and progress.bonus)
  if #bonuses == 0 then
    local none = mode == "rep" and "No rep bonus" or "No XP bonus"
    GameTooltip:AddLine(none, ns.COLORS.red[1], ns.COLORS.red[2], ns.COLORS.red[3], true)
  else
    for _, b in ipairs(bonuses) do
      GameTooltip:AddLine(b, ns.COLORS.green[1], ns.COLORS.green[2], ns.COLORS.green[3], true)
    end
  end
  for _, m in ipairs(xp.missingParts(mode)) do
    GameTooltip:AddLine(m, ns.COLORS.muted[1], ns.COLORS.muted[2], ns.COLORS.muted[3], true)
  end
end
