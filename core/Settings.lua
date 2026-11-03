local _, ns = ...
local settings = {}
ns.settings = settings

-- The one native Settings category for the whole package (Settings >
-- AddOns > VocUI). Each module with a BuildPanel gets its own
-- subcategory page under it (wiki/Principles.md #24); the core only owns the parent category
-- and the closing note.
-- Free-text options, if a module ever has them, stay on the slash
-- line, and the panel says so.
local category

-- A section header is the one plain-text element the vertical layout
-- offers. Guarded: the panel is complete without it. Modules call this
-- on their own page so a page leads with what the module does.
function settings.AddNote(page, text)
  if type(page) ~= "table" then
    return
  end
  if type(CreateSettingsListSectionHeaderInitializer) ~= "function" then
    return
  end
  if not (SettingsPanel and type(SettingsPanel.GetLayout) == "function") then
    return
  end
  pcall(function()
    -- GetLayout takes the category in Blizzard's own code
    -- (Blizzard_SettingsPanel.lua); the stub signature is short an argument.
    ---@diagnostic disable-next-line: redundant-parameter
    local layout = SettingsPanel:GetLayout(page)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
  end)
end

local function note(text)
  settings.AddNote(category, text)
end

-- Declarative option rows, rendered through the native Settings
-- controls (Principles #1: settings are data, never hand-built frames
-- per option). A module hands its OPTIONS table; the core registers
-- each row, wires the value-changed callback so a change applies at
-- once with no reload, and gates child rows on the enable toggle
-- (disabled, never hidden). Dropdown rows carry their options
-- function. Returns how many rows were built.
function settings.BuildPage(page, tag, state, defaults, rows, isEnabled, onChange)
  if type(page) ~= "table" then
    return 0
  end
  if type(state) ~= "table" or type(defaults) ~= "table" then
    return 0
  end
  if type(rows) ~= "table" then
    return 0
  end
  local built = 0
  local parentInit = nil
  for _, row in ipairs(rows) do
    if type(row) == "table" and type(row.key) == "string" then
      local setting = Settings.RegisterAddOnSetting(
        page,
        tag .. row.key,
        row.key,
        state,
        type(defaults[row.key]),
        row.label,
        defaults[row.key]
      )
      local initializer
      if row.kind == "dropdown" and type(row.options) == "function" then
        initializer = Settings.CreateDropdown(page, setting, row.options, row.tooltip)
      else
        initializer = Settings.CreateCheckbox(page, setting, row.tooltip)
      end
      if setting and type(setting.SetValueChangedCallback) == "function" and type(onChange) == "function" then
        local key = row.key
        setting:SetValueChangedCallback(function()
          onChange(key)
        end)
      end
      if row.key == "enabled" then
        parentInit = initializer
      elseif
        parentInit
        and initializer
        and type(initializer.SetParentInitializer) == "function"
        and type(isEnabled) == "function"
      then
        -- Disabled, never hidden, while the module is off.
        pcall(initializer.SetParentInitializer, initializer, parentInit, isEnabled)
      end
      built = built + 1
    end
  end
  return built
end

-- The module's own page under the VocUI parent: a vertical-layout
-- subcategory named for the module's job (wiki/Principles.md #24). When
-- the subcategory API is missing the module builds on the parent page
-- instead, so the panel is never broken.
local function modulePage(mod)
  if type(Settings.RegisterVerticalLayoutSubcategory) == "function" then
    local ok, page = pcall(Settings.RegisterVerticalLayoutSubcategory, category, mod.title or mod.name)
    if ok and type(page) == "table" then
      return page
    end
  end
  return category
end

local function allModules()
  if ns.modules and type(ns.modules.GetAll) == "function" then
    return ns.modules.GetAll()
  end
  return {}
end

function settings.Init()
  if category ~= nil then
    return
  end
  if type(Settings) ~= "table" then
    return
  end
  if type(Settings.RegisterVerticalLayoutCategory) ~= "function" then
    return
  end
  if type(ns.db) ~= "table" then
    return
  end
  category = Settings.RegisterVerticalLayoutCategory("VocUI")
  Settings.RegisterAddOnCategory(category)
  local built = 0
  for _, mod in ipairs(allModules()) do
    if type(mod.BuildPanel) == "function" then
      local ok, err = pcall(mod.BuildPanel, modulePage(mod))
      if ok then
        built = built + 1
      else
        ns.say(mod.name .. " settings failed to load: " .. tostring(err))
      end
    end
  end
  if built == 0 then
    note("No modules installed yet: modules add their own sections here")
  else
    note("More on the slash line: /vui help")
  end
end

function settings.Open()
  local ok = category ~= nil and pcall(function()
    Settings.OpenToCategory(category:GetID())
  end)
  if not ok then
    ns.say("open Settings > AddOns > VocUI")
  end
end
