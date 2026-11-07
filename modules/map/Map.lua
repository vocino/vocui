local _, ns = ...
local map = {}
ns.map = map

-- Map: one blue button on the minimap for the package's regular
-- actions. Left-click opens the VocUI settings; right-click runs the
-- bars macro refresh through the core slash line, so the button never
-- calls another module directly (Principles #11: modules meet at the
-- core). The button sits on the minimap's edge at the stored angle and
-- re-anchors live when the slider moves; without a minimap it hangs
-- off the screen corner, never an error.

map.SECTION = "modules.map"

-- The button's look, in one place: a square on the minimap ring, the
-- toc's stock gear tinted the palette's blue, gold while hovered.
map.SIZE = 33
map.RADIUS = 100
map.BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder" -- Blizzard's own minimap-button ring (ArtifactUI, HelpPlate, and ItemDisplay read the same file)
map.ICON = "Interface\\Icons\\INV_Misc_Gear_01" -- the toc's stock gear, tinted blue

-- Defaults are the product: the button shows from landing, bottom-left
-- like the classic buttons, so the regular actions are one click away
-- before the settings page is ever opened.
map.defaults = {
  enabled = true,
  angle = 225,
}

-- The live state table: VocUIDB.modules.map and nowhere else.
function map.opts()
  return ns.config.Section(map.SECTION, map.defaults)
end

-- Declarative option rows for the module's settings page (CRAFT:
-- settings are data). The toggle shows or hides the button, the slider
-- re-anchors it, and the action rows run their press through the core
-- slash line, so the page never calls the bars module directly.
map.OPTIONS = {
  {
    key = "enabled",
    kind = "checkbox",
    label = "Show the minimap button",
    tooltip = "Adds a blue VocUI button to the minimap for the regular actions",
  },
  {
    key = "angle",
    kind = "slider",
    label = "Button position",
    tooltip = "Where the button sits around the minimap, in degrees",
    min = 0,
    max = 360,
    step = 5,
  },
  {
    kind = "header",
    label = "Quick actions",
  },
  {
    kind = "button",
    label = "Refresh macros",
    button = "Refresh",
    tooltip = "Point the food, drink and potion macros at the best in bags now",
    action = "refresh",
  },
  {
    kind = "button",
    label = "Survey bags",
    button = "Survey",
    tooltip = "List bag consumables and their macro match",
    action = "survey",
  },
}

-- Validity predicate. The whole job is one button frame; without
-- CreateFrame nothing here can act, so the module is never initialized
-- and never listed (principle 12).
function map.IsAvailable()
  return type(CreateFrame) == "function"
end

-- Edge offsets for an angle in degrees on a circle of the given
-- radius, so the button and its tests share one math: 0 faces right,
-- 90 faces up, 225 sits bottom-left.
function map.OffsetForAngle(angle, radius)
  local a = math.rad(tonumber(angle) or 0)
  local r = tonumber(radius) or 0
  return math.cos(a) * r, math.sin(a) * r
end

-- Where the button hangs: the minimap when it exists (the global frame
-- Blizzard's own Minimap.xml names), else the screen corner with no
-- ring math. Returns the parent and whether it is the ring.
local function anchor()
  if type(Minimap) == "table" then
    return Minimap, true
  end
  if type(UIParent) == "table" then
    return UIParent, false
  end
  return nil, false
end

-- Tint the gear blue at rest, gold while hovered. Palette tokens only;
-- a missing helper or palette stays unpainted, never an error.
local function paint(icon, hover)
  if icon == nil or type(icon.SetVertexColor) ~= "function" then
    return
  end
  if type(ns.COLORS) ~= "table" or type(ns.rgb) ~= "function" then
    return
  end
  if hover then
    icon:SetVertexColor(ns.rgb(ns.COLORS.gold))
  else
    icon:SetVertexColor(ns.rgb(ns.COLORS.rest))
  end
end

-- One route to the bars module's presses, through the core slash line
-- (Principles #11): the button, the page, and the slash all dispatch
-- here, so no caller reaches into another module.
function map.RunBarsAction(cmd)
  if ns.slash and type(ns.slash.run) == "function" then
    ns.slash.run("bars " .. tostring(cmd))
  end
end

-- Left-click opens the package settings; right-click runs the macro
-- refresh through the core slash line, so the press stays a core
-- service call whatever the bars module does with it.
function map.OnClick(mouse)
  if mouse == "RightButton" then
    ns.play("on")
    map.RunBarsAction("refresh")
    return
  end
  ns.play("open")
  ns.settings.Open()
end

-- Hover follows the tooltip contract: gold title, one white line naming
-- the job, one muted line teaching the clicks.
function map.OnEnter(button)
  paint(map.icon, true)
  if type(GameTooltip) ~= "table" then
    return
  end
  local c = ns.COLORS
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText("VocUI", c.gold[1], c.gold[2], c.gold[3])
  GameTooltip:AddLine("Blue button for the regular actions", c.text[1], c.text[2], c.text[3], true)
  GameTooltip:AddLine("Left-click settings, right-click refreshes macros", c.muted[1], c.muted[2], c.muted[3], true)
  GameTooltip:Show()
end

function map.OnLeave()
  paint(map.icon, false)
  if type(GameTooltip) == "table" then
    GameTooltip:Hide()
  end
end

-- Build the button once: ring, blue gear, click and hover scripts. A
-- missing piece skips its step; the button is complete without it.
function map.BuildButton()
  if type(CreateFrame) ~= "function" then
    return nil
  end
  local parent = anchor()
  local button = CreateFrame("Button", "VocUIMinimapButton", parent)
  if button == nil then
    return nil
  end
  if type(button.SetSize) == "function" then
    button:SetSize(map.SIZE, map.SIZE)
  end
  if type(button.EnableMouse) == "function" then
    button:EnableMouse(true)
  end
  if type(button.RegisterForClicks) == "function" then
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  if type(button.CreateTexture) == "function" then
    local border = button:CreateTexture(nil, "BACKGROUND")
    if border ~= nil then
      if type(border.SetTexture) == "function" then
        border:SetTexture(map.BORDER)
      end
      if type(border.SetAllPoints) == "function" then
        border:SetAllPoints(button)
      end
    end
    local icon = button:CreateTexture(nil, "ARTWORK")
    if icon ~= nil then
      if type(icon.SetTexture) == "function" then
        icon:SetTexture(map.ICON)
      end
      if type(icon.SetSize) == "function" then
        icon:SetSize(21, 21)
      end
      if type(icon.SetPoint) == "function" then
        icon:SetPoint("CENTER", button, "CENTER", 0, 0)
      end
      if type(icon.SetTexCoord) == "function" then
        icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
      end
    end
    map.icon = icon
    paint(icon, false)
  end
  if type(button.SetScript) == "function" then
    button:SetScript("OnClick", function(self, mouse)
      map.OnClick(mouse)
    end)
    button:SetScript("OnEnter", function(self)
      map.OnEnter(self)
    end)
    button:SetScript("OnLeave", function()
      map.OnLeave()
    end)
  end
  map.button = button
  return button
end

-- Hang the button on the anchor at the stored angle. A bad angle falls
-- back to the default instead of stranding the button off screen.
function map.ApplyPositionImpl()
  local button = map.button
  if button == nil or type(button.ClearAllPoints) ~= "function" or type(button.SetPoint) ~= "function" then
    return false
  end
  local parent, ring = anchor()
  if parent == nil then
    return false
  end
  button:ClearAllPoints()
  if not ring then
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
    return true
  end
  local o = map.opts()
  local angle = tonumber(o.angle) or map.defaults.angle
  if angle < 0 or angle > 360 then
    angle = map.defaults.angle
  end
  local x, y = map.OffsetForAngle(angle, map.RADIUS)
  button:SetPoint("CENTER", parent, "CENTER", x, y)
  return true
end

-- Toggle the module: the setting applies live, the checkbox sound
-- confirms, and the button shows or hides with it, so nothing runs
-- while off.
function map.SetEnabled(on)
  ns.config.Set(map.SECTION, "enabled", on)
  ns.play(on and "on" or "off")
  ns.say("map module " .. (on and "on" or "off"))
  if map.ApplyEnabledImpl then
    map.ApplyEnabledImpl()
  end
end

function map.ToggleEnabled()
  map.SetEnabled(not map.opts().enabled)
end

function map.ApplyEnabledImpl()
  if map.button == nil then
    if not map.opts().enabled then
      return
    end
    map.BuildButton()
  end
  if map.button ~= nil and type(map.button.SetShown) == "function" then
    map.button:SetShown(map.opts().enabled)
  end
  if map.opts().enabled then
    map.ApplyPositionImpl()
  end
end

function map.InitImpl()
  map.ApplyEnabledImpl()
end

function map.Slash(rest)
  local cmd = (rest or ""):match("^(%S*)") or ""
  if cmd == "" then
    map.ToggleEnabled()
  elseif cmd == "on" then
    map.SetEnabled(true)
  elseif cmd == "off" then
    map.SetEnabled(false)
  elseif cmd == "refresh" or cmd == "survey" then
    map.RunBarsAction(cmd)
  else
    ns.help()
  end
end

-- The descriptor loads first; Panel.lua fills in the BuildPanelImpl it
-- delegates to, so registration never waits on it.
local descriptor = {
  name = "map",
  title = "Map",
  job = "A blue minimap button with the package's regular actions one click away",
  default = true,
  IsAvailable = map.IsAvailable,
  init = function()
    if map.InitImpl then
      map.InitImpl()
    end
  end,
  BuildPanel = function(page)
    if map.BuildPanelImpl then
      map.BuildPanelImpl(page)
    end
  end,
  Slash = map.Slash,
}
map.descriptor = descriptor
ns.modules.Register(descriptor)

-- Help lines for this module's subcommands, ahead of the bars lines so
-- the map reads first and the house grammar (config second to last,
-- help last) still holds.
do
  local lines = {
    "/vui map           turn the minimap button on or off",
    "/vui map on|off    turn the minimap button on or off",
    "/vui map refresh   point the macros at the best in bags now",
    "/vui map survey    list bag consumables and their macro match",
  }
  local at = #ns.HELP - 2 -- ahead of the config line (second to last)
  for i, line in ipairs(lines) do
    table.insert(ns.HELP, at + i, line)
  end
end
