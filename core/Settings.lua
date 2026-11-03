local _, ns = ...
local settings = {}
ns.settings = settings

-- The one native Settings category for the whole package (Settings >
-- AddOns > VocUI). Each module with a BuildPanel adds its own section
-- to it; the core only owns the category and the closing note.
-- Free-text options, if a module ever has them, stay on the slash
-- line, and the panel says so.
local category

-- A section header is the one plain-text element the vertical layout
-- offers. Guarded: the panel is complete without it.
local function note(text)
  if type(CreateSettingsListSectionHeaderInitializer) ~= "function" then return end
  if not (SettingsPanel and type(SettingsPanel.GetLayout) == "function") then return end
  pcall(function()
    -- GetLayout takes the category in Blizzard's own code
    -- (Blizzard_SettingsPanel.lua); the stub signature is short an argument.
    ---@diagnostic disable-next-line: redundant-parameter
    local layout = SettingsPanel:GetLayout(category)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
  end)
end

local function allModules()
  if ns.modules and type(ns.modules.GetAll) == "function" then
    return ns.modules.GetAll()
  end
  return {}
end

function settings.Init()
  if category ~= nil then return end
  if type(Settings) ~= "table" then return end
  if type(Settings.RegisterVerticalLayoutCategory) ~= "function" then return end
  if type(ns.db) ~= "table" then return end
  category = Settings.RegisterVerticalLayoutCategory("VocUI")
  Settings.RegisterAddOnCategory(category)
  local built = 0
  for _, mod in ipairs(allModules()) do
    if type(mod.BuildPanel) == "function" then
      local ok, err = pcall(mod.BuildPanel, category)
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
  local ok = category ~= nil
    and pcall(function() Settings.OpenToCategory(category:GetID()) end)
  if not ok then ns.say("open Settings > AddOns > VocUI") end
end
