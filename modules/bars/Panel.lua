local _, ns = ...
local bars = ns.bars

-- The module's settings page: one subcategory under VocUI, named for
-- its job, holding only this module's options. Rows render from the
-- declarative bars.OPTIONS table through the core settings service
-- (settings.BuildPage), so the module declares rows and gets the
-- native controls, live callbacks, and enable-gating for free.
bars.panelBuilt = false

-- What a row does when its value changes, beyond the store write the
-- Settings control already made. Growth reads live on every buff-bar
-- update, so only the toggle acts: it registers or unregisters the
-- viewer load waiter.
function bars.RowChanged(key)
  if key == "enabled" then
    if bars.ApplyEnabledImpl then
      bars.ApplyEnabledImpl()
    end
  end
end

function bars.BuildPanelImpl(page)
  ns.settings.BuildModulePage(bars, page, "Cooldown buff bars grow from the chosen edge")
end
