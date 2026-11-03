-- Headless WoW API stubs for VocUI tests.
-- Installs fake globals; tests then load the core files against them:
--   local mock = dofile("tests/mock.lua")
--   mock.install()

local mock = {}
mock.frames = {}

function mock.reset()
  mock.frames = {}
  _G.VocUIDB = nil
end

function mock.install()
  _G.SlashCmdList = _G.SlashCmdList or {}
  local function makeRegion()
    local region = { shown = true }
    function region:SetSize() end
    function region:SetWidth() end
    function region:SetPoint(...)
      self.point = { ... }
    end
    function region:ClearAllPoints() end
    function region:SetShown(shown)
      self.shown = shown
    end
    function region:Show()
      self.shown = true
    end
    function region:Hide()
      self.shown = false
    end
    return region
  end
  _G.CreateFrame = function()
    local frame = { events = {}, scripts = {}, shown = true }
    function frame:RegisterEvent(event)
      self.events[event] = true
    end
    function frame:UnregisterEvent(event)
      self.events[event] = nil
    end
    function frame:SetScript(script, fn)
      self.scripts[script] = fn
    end
    function frame:SetText(text)
      self.text = text
    end
    function frame:SetSize(width, height)
      self.width, self.height = width, height
    end
    function frame:SetShown(shown)
      self.shown = shown
    end
    function frame:ClearAllPoints()
      self.points = {}
    end
    function frame:SetPoint(...)
      self.points = { ... }
    end
    function frame:GetPoint()
      return nil
    end
    function frame:SetMovable() end
    function frame:SetClampedToScreen() end
    function frame:EnableMouse() end
    function frame:RegisterForDrag() end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:Show()
      self.shown = true
    end
    function frame:Hide()
      self.shown = false
    end
    function frame:IsShown()
      return self.shown
    end
    function frame:SetStatusBarTexture() end
    function frame:SetMinMaxValues() end
    function frame:SetValue(value)
      self.value = value
    end
    function frame:CreateTexture()
      local tex = makeRegion()
      function tex:SetAllPoints() end
      function tex:SetAtlas() end
      function tex:SetTexture() end
      function tex:SetVertexColor() end
      function tex:SetTexCoord() end
      return tex
    end
    function frame:CreateFontString()
      local fs = makeRegion()
      function fs:SetText(text)
        self.text = text
      end
      function fs:SetShadowOffset() end
      return fs
    end
    mock.frames[#mock.frames + 1] = frame
    return frame
  end
end

return mock
