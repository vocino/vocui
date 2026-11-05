local _, ns = ...
local bars = ns.bars

-- Center-out fill for the cooldown viewer's buff bars. The native bar
-- is a plain horizontal StatusBar whose texture spans the whole frame,
-- so the client always fills left to right. The hook below re-anchors
-- that same texture every update instead: centered with a width of the
-- filled fraction for center growth, pinned to the right edge for right
-- growth, and handed back to the client for left growth. No new frames,
-- no new textures, nothing to clean up. The pip rides the texture's
-- right edge by Blizzard's own anchor, so it marks the leading edge.
-- (Blizzard_CooldownViewer/CooldownViewer.lua, CooldownViewerBuffBarItemMixin.)

-- Bars restyled by us, for the disable path. Weak keys: pooled viewer
-- frames come and go, and nothing here may hold them.
local styled = setmetatable({}, { __mode = "k" })

-- Hand one bar's texture back to the client: the native fill takes over
-- on its next update. Returns true when a bar was read.
local function restoreBar(bar)
  local tex = bar:GetStatusBarTexture()
  if tex == nil or type(tex.ClearAllPoints) ~= "function" or type(tex.SetAllPoints) ~= "function" then
    return false
  end
  tex:ClearAllPoints()
  tex:SetAllPoints(bar)
  styled[bar] = nil
  return true
end

function bars.RestoreBar(bar)
  if type(bar) ~= "table" or type(bar.GetStatusBarTexture) ~= "function" then
    return false
  end
  return restoreBar(bar)
end

-- Apply the growth option to one buff-bar item. Returns true when the
-- bar's fill was placed, false when there was nothing to place on.
-- Every read is presence-gated: an unknown shape keeps the native fill,
-- never an error.
function bars.ApplyFill(item)
  if type(item) ~= "table" or type(item.GetBarFrame) ~= "function" then
    return false
  end
  local bar = item:GetBarFrame()
  if type(bar) ~= "table" then
    return false
  end
  for _, method in ipairs({ "GetStatusBarTexture", "GetMinMaxValues", "GetValue", "GetWidth", "GetHeight", "GetOrientation" }) do
    if type(bar[method]) ~= "function" then
      return false
    end
  end
  local growth = bars.opts().growth
  if growth ~= "center" and growth ~= "right" then
    -- Left is the native fill, and anything unknown with it.
    return restoreBar(bar)
  end
  local tex = bar:GetStatusBarTexture()
  if tex == nil or type(tex.ClearAllPoints) ~= "function" or type(tex.SetPoint) ~= "function" then
    return false
  end
  local min, max = bar:GetMinMaxValues()
  local value = bar:GetValue()
  local frac = 0
  if type(max) == "number" and type(min) == "number" and type(value) == "number" and max > min then
    frac = (value - min) / (max - min)
    if frac < 0 then
      frac = 0
    elseif frac > 1 then
      frac = 1
    end
  end
  local orientation = bar:GetOrientation()
  tex:ClearAllPoints()
  if orientation == "VERTICAL" then
    -- Vertical bars know only center: anything else stays native.
    if growth ~= "center" then
      tex:SetAllPoints(bar)
      styled[bar] = nil
      return true
    end
    local h = bar:GetHeight()
    if type(h) ~= "number" then
      return false
    end
    local half = (h * frac) / 2
    tex:SetPoint("LEFT", bar, "LEFT", 0, 0)
    tex:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    tex:SetPoint("TOP", bar, "CENTER", 0, half)
    tex:SetPoint("BOTTOM", bar, "CENTER", 0, -half)
  else
    local w = bar:GetWidth()
    if type(w) ~= "number" then
      return false
    end
    tex:SetPoint("TOP", bar, "TOP", 0, 0)
    tex:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    if growth == "right" then
      local fill = w * frac
      tex:SetPoint("LEFT", bar, "RIGHT", -fill, 0)
      tex:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    else
      local half = (w * frac) / 2
      tex:SetPoint("LEFT", bar, "CENTER", -half, 0)
      tex:SetPoint("RIGHT", bar, "CENTER", half, 0)
    end
  end
  styled[bar] = true
  return true
end

-- The secure post-hook: runs after Blizzard lays out the fill, so our
-- anchors win every frame. While the module is off every touched bar
-- goes back to the client instead.
function bars.OnBarCooldown(item)
  if not bars.opts().enabled then
    if type(item) == "table" and type(item.GetBarFrame) == "function" then
      local bar = item:GetBarFrame()
      if type(bar) == "table" and styled[bar] then
        bars.RestoreBar(bar)
      end
    end
    return false
  end
  return bars.ApplyFill(item)
end
