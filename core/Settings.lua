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
-- on their own page so a page leads with what the module does; header
-- rows in a module's OPTIONS table come through here too.
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

-- A dropdown's options function from declarative choices data
-- ({{ value, label, tooltip }}), so modules declare data and the core
-- owns the one container builder (Principles #11).
function settings.DropdownOptions(choices)
  return function()
    if type(Settings) ~= "table" or type(Settings.CreateControlTextContainer) ~= "function" then
      return {}
    end
    local container = Settings.CreateControlTextContainer()
    for _, choice in ipairs(choices or {}) do
      if type(choice) == "table" then
        container:Add(choice.value, choice.label, choice.tooltip or "")
      end
    end
    return container:GetData()
  end
end

-- One row's native control for the value the row wants (wiki/Craft.md,
-- "Settings panels"): a checkbox for a yes-or-no, a slider with
-- min/max/step for a number in a range, a dropdown for one choice
-- among named choices. Dropdown rows carry their options function, or
-- declare choices data the core turns into one. Anything else falls
-- back to a checkbox. A row whose factory is missing builds nothing,
-- never an error. Returns the initializer, or nil.
local function buildInitializer(page, setting, row)
  if type(Settings) ~= "table" then
    return nil
  end
  if row.kind == "slider" then
    local step = row.step
    if type(step) ~= "number" then
      step = nil
    end
    if
      type(row.min) == "number"
      and type(row.max) == "number"
      and type(Settings.CreateSlider) == "function"
      and type(Settings.CreateSliderOptions) == "function"
    then
      return Settings.CreateSlider(page, setting, Settings.CreateSliderOptions(row.min, row.max, step), row.tooltip)
    end
    return nil
  end
  if row.kind == "dropdown" then
    local options = row.options
    if type(options) ~= "function" and type(row.choices) == "table" then
      options = settings.DropdownOptions(row.choices)
    end
    if type(options) == "function" and type(Settings.CreateDropdown) == "function" then
      return Settings.CreateDropdown(page, setting, options, row.tooltip)
    end
    return nil
  end
  if type(Settings.CreateCheckbox) == "function" then
    return Settings.CreateCheckbox(page, setting, row.tooltip)
  end
  return nil
end

-- Declarative option rows, rendered through the native Settings
-- controls (Principles #1: settings are data, never hand-built frames
-- per option). A module hands its OPTIONS table; the core registers
-- each row, wires the value-changed callback so a change applies at
-- once with no reload, and gates child rows on the enable toggle
-- (disabled, never hidden). Header rows ({ kind = "header", label })
-- are plain section labels and register nothing. Returns how many
-- control rows were built.
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
    if type(row) == "table" and row.kind == "header" and type(row.label) == "string" then
      settings.AddNote(page, row.label)
    elseif type(row.key) == "string" then
      local setting = Settings.RegisterAddOnSetting(
        page,
        tag .. row.key,
        row.key,
        state,
        type(defaults[row.key]),
        row.label,
        defaults[row.key]
      )
      local initializer = buildInitializer(page, setting, row)
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
      if initializer then
        built = built + 1
      end
    end
  end
  return built
end

-- A module's settings page through the same service every module
-- shares: guards, the job note plus one context line, rows from the
-- module's OPTIONS table, enable-gating, and the module's own
-- RowChanged callback. The tag derives from the descriptor name so
-- pages cannot collide. Modules keep their OPTIONS, their notes, and
-- their RowChanged; this owns only the shape.
function settings.BuildModulePage(mod, page, extra)
  if type(mod) ~= "table" or type(mod.descriptor) ~= "table" then
    return 0
  end
  if mod.panelBuilt then
    return 0
  end
  if type(Settings) ~= "table" then
    return 0
  end
  if type(Settings.RegisterAddOnSetting) ~= "function" then
    return 0
  end
  if type(ns.db) ~= "table" then
    return 0
  end
  ns.settings.AddNote(page, mod.descriptor.job)
  if type(extra) == "string" then
    ns.settings.AddNote(page, extra)
  end
  local built = ns.settings.BuildPage(
    page,
    "VocUI_" .. tostring(mod.descriptor.name) .. "_",
    mod.opts(),
    mod.defaults,
    mod.OPTIONS,
    function()
      return mod.opts().enabled
    end,
    function(key)
      if type(mod.RowChanged) == "function" then
        mod.RowChanged(key)
      end
    end
  )
  mod.panelBuilt = true
  return built
end

-- A module that cannot work here gets no page: unavailable is a
-- designed state, hidden rather than shown broken (Principles #12,
-- Craft #4). Mirrors modules.InitAll, which skips the same modules; a
-- broken check fails open here because InitAll already reported it.
local function panelWanted(mod)
  if type(mod) ~= "table" then
    return false
  end
  local check = mod.IsAvailable
  if type(check) ~= "function" and type(mod.descriptor) == "table" then
    check = mod.descriptor.IsAvailable
  end
  if type(check) ~= "function" then
    return true
  end
  local ok, available = pcall(check)
  if not ok then
    return true
  end
  return available and true or false
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
    if type(mod.BuildPanel) == "function" and panelWanted(mod) then
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
