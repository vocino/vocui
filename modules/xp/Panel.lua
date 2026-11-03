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
local function rowChanged(key)
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
  if xp.panelBuilt then
    return
  end
  if type(Settings) ~= "table" then
    return
  end
  if type(Settings.RegisterAddOnSetting) ~= "function" then
    return
  end
  if type(ns.db) ~= "table" then
    return
  end
  -- Information order: what the module does first, the deciding source
  -- second, configuration last.
  ns.settings.AddNote(page, xp.descriptor.job)
  ns.settings.AddNote(page, "Rate window: trailing 10 minutes, forecast 15")
  ns.settings.BuildPage(page, "VocUI_xp_", xp.opts(), xp.defaults, xp.OPTIONS, function()
    return xp.opts().enabled
  end, function(key)
    rowChanged(key)
  end)
  xp.panelBuilt = true
end
