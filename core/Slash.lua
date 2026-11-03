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
  for _, line in ipairs(ns.HELP) do
    print("  " .. line)
  end
end

local function findModule(cmd)
  if not (ns.modules and type(ns.modules.GetAll) == "function") then
    return nil
  end
  for _, mod in ipairs(ns.modules.GetAll()) do
    if mod.name == cmd then
      return mod
    end
  end
  return nil
end

function slash.run(msg)
  local text = (msg or ""):lower()
  local cmd = text:match("^(%S*)") or ""
  if cmd == "" or cmd == "config" then
    ns.play("open")
    ns.settings.Open()
    return
  end
  -- Module subcommands: "/vui <module> ..." delegates to the module,
  -- which owns its grammar under its name and never acts on a typo.
  local mod = findModule(cmd)
  if mod and type(mod.Slash) == "function" then
    local rest = text:match("^%S+%s+(.*)$") or ""
    mod.Slash(rest)
    return
  end
  ns.help()
end

-- Blizzard's slash dispatcher reads SLASH_* globals by name, so these
-- cannot be namespaced (they are declared in .luacheckrc instead).
SLASH_VOCUI1 = "/vui"
SLASH_VOCUI2 = "/vocui"
SlashCmdList.VOCUI = function(msg)
  slash.run(msg)
end
