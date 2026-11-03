local _, ns = ...
local slash = {}
ns.slash = slash

-- Slash grammar: the bare command does the one main thing (open the
-- package settings; there is no window yet), `config` opens the panel,
-- `help` lists the rest, and anything unrecognized prints help instead
-- of acting, so a typo can never toggle anything.
ns.HELP = {
  "/vui          open Settings > AddOns > VocUI",
  "/vui config   open Settings > AddOns > VocUI",
  "/vui help     this list (/vocui works too)",
}

function ns.help()
  ns.say("commands")
  for _, line in ipairs(ns.HELP) do print("  " .. line) end
end

function slash.run(msg)
  local cmd = ((msg or ""):match("^(%S*)") or ""):lower()
  if cmd == "" or cmd == "config" then
    ns.play("open")
    ns.settings.Open()
  else
    ns.help()
  end
end

-- Blizzard's slash dispatcher reads SLASH_* globals by name, so these
-- cannot be namespaced (they are declared in .luacheckrc instead).
SLASH_VOCUI1 = "/vui"
SLASH_VOCUI2 = "/vocui"
SlashCmdList.VOCUI = function(msg) slash.run(msg) end
