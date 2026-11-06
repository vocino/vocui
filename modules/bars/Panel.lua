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
-- update, so only the toggles act: the module toggle registers or
-- unregisters the viewer load waiter and the macro bag events, and any
-- macro row resyncs the macros at once.
function bars.RowChanged(key)
  if key == "enabled" then
    if bars.ApplyEnabledImpl then
      bars.ApplyEnabledImpl()
    end
    if bars.ApplyMacrosImpl then
      bars.ApplyMacrosImpl()
    end
    if bars.ResyncMacros then
      bars.ResyncMacros()
    end
  elseif bars.IsMacroKey and bars.IsMacroKey(key) then
    if bars.ApplyMacrosImpl then
      bars.ApplyMacrosImpl()
    end
    if bars.ResyncMacros then
      bars.ResyncMacros()
    end
  end
end

function bars.BuildPanelImpl(page)
  ns.settings.BuildModulePage(bars, page, "Cooldown buff bars grow from the chosen edge")
end
