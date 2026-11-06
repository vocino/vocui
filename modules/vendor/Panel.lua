local _, ns = ...
local vendor = ns.vendor

-- The module's settings page: one subcategory under VocUI, named for
-- its job, holding only this module's options. Rows render from the
-- declarative vendor.OPTIONS table through the core settings service
-- (settings.BuildPage), so the module declares rows and gets the
-- native controls, live callbacks, and enable-gating for free.
vendor.panelBuilt = false

-- What a row does when its value changes, beyond the store write the
-- Settings control already made. Everything here reads the options
-- live at merchant time, so only the toggle and the tooltip row act:
-- the toggle registers or unregisters the merchant event, and the
-- tooltip row installs the hooks on first enable.
function vendor.RowChanged(key)
  if key == "enabled" then
    if vendor.ApplyEnabledImpl then
      vendor.ApplyEnabledImpl()
    end
  elseif key == "tooltipPrice" then
    if vendor.opts().tooltipPrice and vendor.InstallTooltip then
      vendor.InstallTooltip()
    end
  end
end

function vendor.BuildPanelImpl(page)
  ns.settings.BuildModulePage(
    vendor,
    page,
    "Sells poor quality only, asks about surplus, repairs all, each visit announced"
  )
end
