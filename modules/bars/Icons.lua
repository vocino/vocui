local _, ns = ...
local bars = ns.bars

-- Centered icon strips for the cooldown viewer's icon groups (essential,
-- utility, and tracked buffs). Blizzard lays out each viewer as a
-- corner-anchored grid that hugs its content, so a strip grows out from
-- the placed anchor as icons come and go. After every layout the strip
-- below shifts the viewer back so the icons stay centered on that
-- anchor. No new frames, no new textures: one anchor move per layout,
-- handed back to the client for anything native. Growth reads live on
-- every layout, like the bar fill in Grow.lua: center centers, anything
-- else stays native.

-- The viewer mixins whose grids center, by global name. Hooked one by
-- one when the viewer addon loads; anything missing stays native.
bars.ICON_VIEWERS = {
  "EssentialCooldownViewerMixin",
  "UtilityCooldownViewerMixin",
  "BuffIconCooldownViewerMixin",
}

-- Anchors a viewer was placed with, and the last anchors we applied, by
-- viewer. Weak keys: viewer frames come and go, and nothing here holds
-- them. Compared by value every layout, so a drag in EditMode re-bases
-- instead of fighting the player.
local iconState = setmetatable({}, { __mode = "k" })

local function readAnchors(viewer)
  if type(viewer.GetNumPoints) ~= "function" or type(viewer.GetPoint) ~= "function" then
    return nil
  end
  local count = viewer:GetNumPoints()
  if type(count) ~= "number" then
    return nil
  end
  local points = {}
  for i = 1, count do
    local point, relativeTo, relativePoint, x, y = viewer:GetPoint(i)
    if type(point) ~= "string" or type(relativePoint) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
      return nil
    end
    points[i] = { point, relativeTo, relativePoint, x, y }
  end
  return points
end

local function sameAnchors(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
    return false
  end
  for i, p in ipairs(a) do
    local q = b[i]
    if type(q) ~= "table" or p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3] or p[4] ~= q[4] or p[5] ~= q[5] then
      return false
    end
  end
  return true
end

local function shiftAnchors(base, dx, dy)
  local moved = {}
  for i, p in ipairs(base) do
    moved[i] = { p[1], p[2], p[3], p[4] + dx, p[5] + dy }
  end
  return moved
end

local function applyAnchors(viewer, points)
  viewer:ClearAllPoints()
  for _, p in ipairs(points) do
    viewer:SetPoint(p[1], p[2], p[3], p[4], p[5])
  end
end

-- Center offset for one viewer: half its content size back along each
-- growth axis, or nil when there is nothing to place on. Pure: reads
-- size and direction, writes nothing.
function bars.IconOffset(viewer)
  if type(viewer) ~= "table" then
    return nil
  end
  if type(viewer.GetWidth) ~= "function" or type(viewer.GetHeight) ~= "function" then
    return nil
  end
  local w, h = viewer:GetWidth(), viewer:GetHeight()
  if type(w) ~= "number" or type(h) ~= "number" then
    return nil
  end
  if type(viewer.isHorizontal) ~= "boolean" then
    return nil
  end
  if type(viewer.layoutFramesGoingRight) ~= "boolean" or type(viewer.layoutFramesGoingUp) ~= "boolean" then
    return nil
  end
  local dx = viewer.layoutFramesGoingRight and -w / 2 or w / 2
  local dy = viewer.layoutFramesGoingUp and -h / 2 or h / 2
  return dx, dy
end

-- Post-layout hook: center the strip, or hand the viewer back to the
-- client when the module is off or growth is not center. Returns true
-- when the anchors match the wanted state, false when unreadable.
function bars.OnViewerLayout(viewer)
  if type(viewer) ~= "table" then
    return false
  end
  if type(viewer.ClearAllPoints) ~= "function" or type(viewer.SetPoint) ~= "function" then
    return false
  end
  local st = iconState[viewer]
  local base, applied
  if st then
    base, applied = st.base, st.applied
  end
  local cur = readAnchors(viewer)
  if not cur then
    return false
  end
  if not applied or not sameAnchors(cur, applied) then
    base = cur
  end
  local dx, dy = 0, 0
  local o = bars.opts()
  if o.enabled and o.growth == "center" then
    local ox, oy = bars.IconOffset(viewer)
    if ox == nil then
      return false
    end
    dx, dy = ox, oy
  end
  local want = shiftAnchors(base, dx, dy)
  if sameAnchors(cur, want) then
    iconState[viewer] = { base = base, applied = want }
    return true
  end
  -- Re-anchoring an EditMode-managed frame can refuse in combat; a
  -- refused pass fails loud nowhere and retries on the next layout.
  if not pcall(applyAnchors, viewer, want) then
    return false
  end
  iconState[viewer] = { base = base, applied = want }
  return true
end

-- Install the icon hooks, one viewer mixin at a time. Anything missing
-- stays native; each hooked table latches so a late enable never hooks
-- twice. Returns true when at least one viewer hooked.
function bars.InstallIconHooks()
  if type(hooksecurefunc) ~= "function" then
    return false
  end
  local hooked = false
  for _, name in ipairs(bars.ICON_VIEWERS) do
    if not bars.hookedIcons[name] then
      local mixin = _G[name]
      if type(mixin) == "table" and type(mixin.RefreshLayout) == "function" then
        hooksecurefunc(mixin, "RefreshLayout", bars.OnViewerLayout)
        bars.hookedIcons[name] = true
        hooked = true
      end
    end
  end
  return hooked
end

bars.hookedIcons = {}
