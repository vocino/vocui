local _, ns = ...
local gear = ns.gear

-- The module's settings page: one subcategory under VocUI, named for
-- its job, holding only this module's options. Rows render from the
-- declarative gear.OPTIONS table through the native Settings controls;
-- every row carries a value-changed callback so a change applies at
-- once, with no reload. Child rows gate on the enable toggle: when it
-- is off they show disabled, never hidden.
gear.panelBuilt = false

local function onSettingChanged(setting, fn)
  if setting and type(setting.SetValueChangedCallback) == "function" then
    setting:SetValueChangedCallback(fn)
  end
end

-- What a row does when its value changes, beyond the store write the
-- Settings control already made. Behavior rows rescan; the enable row
-- also registers or unregisters the module's events.
local function rowChanged(key)
  if key == "enabled" then
    if gear.ApplyEnabledImpl then
      gear.ApplyEnabledImpl()
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
  local state = gear.opts()
  local defaults = gear.defaults
  -- Information order: what the module does first, the deciding source
  -- second, configuration last.
  ns.settings.AddNote(page, gear.descriptor.job)
  ns.settings.AddNote(page, "Upgrade source: built-in item level")
  local parentInit = nil
  for _, row in ipairs(gear.OPTIONS) do
    local key = row.key
    local setting = Settings.RegisterAddOnSetting(
      page,
      "VocUI_gear_" .. key,
      key,
      state,
      type(defaults[key]),
      row.label,
      defaults[key]
    )
    local initializer
    if row.kind == "dropdown" then
      initializer = Settings.CreateDropdown(page, setting, gear.EquipSoundOptions, row.tooltip)
    else
      initializer = Settings.CreateCheckbox(page, setting, row.tooltip)
    end
    onSettingChanged(setting, function()
      rowChanged(key)
    end)
    if key == "enabled" then
      parentInit = initializer
    elseif parentInit and initializer and type(initializer.SetParentInitializer) == "function" then
      -- Disabled, never hidden, while the module is off.
      pcall(initializer.SetParentInitializer, initializer, parentInit, function()
        return gear.opts().enabled
      end)
    end
  end
  gear.panelBuilt = true
end
