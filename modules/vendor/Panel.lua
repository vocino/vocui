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
local function rowChanged(key)
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
  if vendor.panelBuilt then
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
  -- Information order: what the module does first, the deciding
  -- source second, configuration last.
  ns.settings.AddNote(page, vendor.descriptor.job)
  ns.settings.AddNote(page, "Sells poor quality only, repairs all, each visit announced")
  ns.settings.BuildPage(page, "VocUI_vendor_", vendor.opts(), vendor.defaults, vendor.OPTIONS, function()
    return vendor.opts().enabled
  end, function(key)
    rowChanged(key)
  end)
  vendor.panelBuilt = true
end
