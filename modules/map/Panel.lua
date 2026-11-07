local _, ns = ...
local map = ns.map

-- The module's settings page: one subcategory under VocUI, named for
-- its job, holding only this module's options. Rows render from the
-- declarative map.OPTIONS table through the core settings service
-- (settings.BuildModulePage), so the module declares rows and gets the
-- native controls, live callbacks, and enable-gating for free.

-- What a row does when its value changes, beyond the store write the
-- Settings control already made. The toggle shows or hides the button,
-- the slider re-anchors it, and either action row runs its press
-- through the core slash line (refresh sounds on, survey sounds open),
-- so the page never calls the bars module directly.
function map.RowChanged(key)
  if key == "enabled" then
    if map.ApplyEnabledImpl then
      map.ApplyEnabledImpl()
    end
  elseif key == "angle" then
    if map.ApplyPositionImpl then
      map.ApplyPositionImpl()
    end
  elseif key == "refresh" then
    ns.play("on")
    map.RunBarsAction("refresh")
  elseif key == "survey" then
    ns.play("open")
    map.RunBarsAction("survey")
  end
end

function map.BuildPanelImpl(page)
  ns.settings.BuildModulePage(map, page, "Left-click opens these settings, right-click refreshes the macros")
end
