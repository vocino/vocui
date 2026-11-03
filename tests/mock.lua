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
    mock.frames[#mock.frames + 1] = frame
    return frame
  end
end

return mock
