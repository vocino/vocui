local _, ns = ...
local xp = ns.xp

-- The module's settings page: one subcategory under VocUI, named for
-- its job, holding only this module's options. Rows render from the
-- declarative xp.OPTIONS table through the core settings service
-- (settings.BuildPage), so the module declares rows and gets the
-- native controls, live callbacks, and enable-gating for free.
xp.panelBuilt = false

-- What a row does when its value changes, beyond the store write the
-- Settings control already made. Behavior rows rescan; the enable row
-- also registers or unregisters the module's events.
function xp.RowChanged(key)
  if key == "enabled" then
    if xp.ApplyEnabledImpl then
      xp.ApplyEnabledImpl()
    end
  elseif key == "locked" then
    if xp.CheckNowImpl then
      xp.CheckNowImpl()
    end
  elseif key == "repMode" then
    -- Flipping rep mode re-derives the mode from a fresh snapshot.
    if xp.activateMode then
      xp.activateMode(xp.readSnapshot())
    end
    if xp.CheckNowImpl then
      xp.CheckNowImpl()
    end
  else
    if xp.CheckNowImpl then
      xp.CheckNowImpl()
    end
  end
end

function xp.BuildPanelImpl(page)
  ns.settings.BuildModulePage(xp, page, "Rate window: trailing 10 minutes, forecast 15")
end
