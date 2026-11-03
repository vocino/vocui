local _, ns = ...
local gear = ns.gear

-- The module's settings page: one subcategory under VocUI, named for
-- its job, holding only this module's options. Rows render from the
-- declarative gear.OPTIONS table through the core settings service
-- (settings.BuildPage), so a future module declares rows and gets the
-- native controls, live callbacks, and enable-gating for free.
gear.panelBuilt = false

-- What a row does when its value changes, beyond the store write the
-- Settings control already made. Behavior rows rescan; the enable row
-- also registers or unregisters the module's events.
local function rowChanged(key)
  if key == "enabled" then
    if gear.ApplyEnabledImpl then
      gear.ApplyEnabledImpl()
    end
    if gear.EnsureSheetImpl then
      gear.EnsureSheetImpl()
    end
    gear.Scan()
  elseif key == "equipSound" then
    gear.playEquipSound()
  elseif key == "sessionIlvl" then
    if gear.RefreshIlvlSuffixImpl then
      gear.RefreshIlvlSuffixImpl()
    end
  elseif key == "sheetButton" then
    if gear.EnsureSheetImpl then
      gear.EnsureSheetImpl()
    end
  else
    gear.Scan()
  end
end

function gear.EquipSoundOptions()
  local container = Settings.CreateControlTextContainer()
  container:Add("0", "Off", "No sound when equipping")
  for _, snd in ipairs(gear.EQUIP_SOUNDS) do
    container:Add(snd.id, snd.label, "")
  end
  return container:GetData()
end

-- Dropdown rows resolve their options here, at load: the OPTIONS table
-- stays pure data in the descriptor file.
for _, row in ipairs(gear.OPTIONS) do
  if row.kind == "dropdown" and row.key == "equipSound" then
    row.options = gear.EquipSoundOptions
  end
end

function gear.BuildPanelImpl(page)
  if gear.panelBuilt then
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
  ns.settings.AddNote(page, gear.descriptor.job)
  ns.settings.AddNote(page, "Upgrade source: built-in item level")
  ns.settings.BuildPage(page, "VocUI_gear_", gear.opts(), gear.defaults, gear.OPTIONS, function()
    return gear.opts().enabled
  end, function(key)
    rowChanged(key)
  end)
  gear.panelBuilt = true
end
