local name, ns = ...

-- Addon compartment: the toc names these three globals. The click does
-- what the bare slash does (open the package settings); hover follows
-- the tooltip contract: gold title, one line naming the job, one muted
-- line teaching the slash command.
function VocUI_CompartmentClick(_, _)
  ns.play("open")
  ns.settings.Open()
end

function VocUI_CompartmentEnter(_, button)
  if type(GameTooltip) ~= "table" then
    return
  end
  local c = ns.COLORS
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText("VocUI", c.gold[1], c.gold[2], c.gold[3])
  GameTooltip:AddLine("Small modules for the way one player plays", c.text[1], c.text[2], c.text[3], true)
  GameTooltip:AddLine("/vui opens settings. /vui help lists the rest", c.muted[1], c.muted[2], c.muted[3], true)
  GameTooltip:Show()
end

function VocUI_CompartmentLeave(_, _)
  if type(GameTooltip) == "table" then
    GameTooltip:Hide()
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" then
    if addon ~= name then
      return
    end
    if type(VocUIDB) ~= "table" then
      VocUIDB = {}
    end
    ns.db = VocUIDB
    ns.config.Init()
    ns.modules.InitAll()
    ns.settings.Init()
    boot:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    ns.settings.Init() -- in case the Settings API was not up at ADDON_LOADED
    boot:UnregisterEvent("PLAYER_LOGIN")
  end
end)
