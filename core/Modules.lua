local _, ns = ...
local modules = {}
ns.modules = modules

-- The module registry. A module is a folder with a descriptor first:
--   name        folder-style short name, lower case ("bags")
--   job         one sentence saying what it does
--   init        builds the module; runs once, inside a protected call
--   IsAvailable optional validity predicate; a module that cannot work
--               in the current situation stays hidden, never broken.
--               Name it for the flavor (IsAvailableBank), with a
--               comment giving the reason.
--   BuildPanel  optional Settings section builder; the core hands it
--               the package category and it adds its own controls.
-- Registering never errors: an invalid descriptor waits for InitAll
-- and is reported there, so one broken module file can never break
-- the package load.
local registry = {}
local problems = {}

function modules.Register(descriptor)
  if type(descriptor) ~= "table" then
    problems[#problems + 1] = "descriptor is not a table"
    return false
  end
  if type(descriptor.name) ~= "string" or descriptor.name == "" then
    problems[#problems + 1] = "descriptor is missing a name"
    return false
  end
  if type(descriptor.init) ~= "function" then
    problems[#problems + 1] = descriptor.name .. " is missing init"
    return false
  end
  registry[#registry + 1] = descriptor
  return true
end

-- Every registered module, in registration order. A fresh array each
-- call; the registry itself stays private.
function modules.GetAll()
  local all = {}
  for i, mod in ipairs(registry) do all[i] = mod end
  return all
end

local function initOne(mod)
  local ok, err = pcall(mod.init)
  if not ok then ns.say(mod.name .. " failed to load: " .. tostring(err)) end
end

-- Initialize every module inside its own protected call, skipping the
-- ones that cannot work here. Boot calls this once.
function modules.InitAll()
  for _, reason in ipairs(problems) do
    ns.say("module not loaded: " .. reason)
  end
  for _, mod in ipairs(registry) do
    if type(mod.IsAvailable) == "function" then
      local ok, available = pcall(mod.IsAvailable)
      if not ok then
        ns.say(mod.name .. " check failed: " .. tostring(available))
      elseif available then
        initOne(mod)
      end
    else
      initOne(mod)
    end
  end
end
