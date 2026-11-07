local _, ns = ...
local chat = {}
ns.chat = chat

-- Chat: the outgoing dialect filter, under the module contract. It
-- wraps the documented send call (C_ChatInfo.SendChatMessage, the only
-- outgoing route on the Forever branch: Blizzard's own edit box calls
-- it directly at ChatFrameEditBox.lua:306, and the bare SendChatMessage
-- global only exists behind the loadDeprecationFallbacks shim), so
-- every sender passes through one gate: the stock UI, macros, and
-- replacement chat frames like Chattynator, which needs no integration
-- of its own (Principles #7: guests are welcome but never required).
-- The 2007 Dwarvenizer/Trollizer global hook could not survive that
-- move, so only its behavior crossed over: two dialect tables, a
-- chance slider, say/yell toggles, and the (( escape hatch.
-- Emotes never change.

chat.SECTION = "modules.chat"

-- Defaults are the product: loaded speaking dwarven at chance 8, the
-- 2007 landing state, one slash away from troll or silence. An unknown
-- hand-edited dialect reads as silence downstream, never an error.
chat.defaults = {
  enabled = true,
  dialect = "dwarf",
  chance = 8,
  say = true,
  yell = true,
}

-- The live state table: VocUIDB.modules.chat and nowhere else.
function chat.opts()
  return ns.config.Section(chat.SECTION, chat.defaults)
end

-- Declarative option rows for the module's settings page (CRAFT:
-- settings are data). The toggle installs or removes the send
-- wrapper; dialect, chance, and channels read live at send time, so
-- only the toggle needs a row callback.
chat.OPTIONS = {
  {
    key = "enabled",
    kind = "checkbox",
    label = "Speak in dialect",
    tooltip = "Rewrite outgoing chat in the chosen dialect before it sends",
  },
  {
    kind = "header",
    label = "Dialect",
  },
  {
    key = "dialect",
    kind = "dropdown",
    label = "Dialect",
    tooltip = "Which voice rewrites outgoing chat",
    choices = {
      { value = "dwarf", label = "Dwarven", tooltip = "Rewrite outgoing chat like a dwarf" },
      { value = "troll", label = "Troll", tooltip = "Rewrite outgoing chat like a troll" },
    },
  },
  {
    key = "chance",
    kind = "slider",
    label = "How often",
    tooltip = "How often the dialect rewrites words, from 0 (never) to 10 (always)",
    min = 0,
    max = 10,
    step = 1,
  },
  {
    kind = "header",
    label = "Channels",
  },
  {
    key = "say",
    kind = "checkbox",
    label = "Say",
    tooltip = "Rewrite /say chat",
  },
  {
    key = "yell",
    kind = "checkbox",
    label = "Yell",
    tooltip = "Rewrite /yell chat",
  },
}

-- Validity predicate. The whole job is one wrapper around the
-- documented send call; without it nothing here can act, so the
-- module is never initialized and never listed (principle 12).
function chat.IsAvailable()
  return type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function"
end

-- Whether one outgoing message changes. The module toggle, a known
-- dialect, and a nonzero chance gate everything; emotes never change
-- (the 2007 rule). Only /say and /yell reach the engine; every
-- other type passes through untouched.
-- A (( prefix marks out-of-character and stays as typed.
function chat.MangleForSend(message, chatType, target)
  if message == nil then
    message = ""
  end
  if type(message) ~= "string" then
    return message
  end
  local o = chat.opts()
  if not o.enabled then
    return message
  end
  if o.dialect ~= "dwarf" and o.dialect ~= "troll" then
    return message
  end
  if (o.chance or 0) <= 0 then
    return message
  end
  local kind = "SAY"
  if type(chatType) == "string" and chatType ~= "" then
    kind = chatType:upper()
  end
  if kind == "EMOTE" then
    return message
  end
  if kind ~= "SAY" and kind ~= "YELL" then
    return message
  end
  if o[string.lower(kind)] ~= true then
    return message
  end
  if message:find("^%(%(") then
    return message
  end
  return chat.Mangle(message, chat.DICTIONARIES[o.dialect], o.chance)
end

-- The send wrapper: one gate, then the saved call with its original
-- arguments, so types, languages, and targets cross exactly as sent.
-- A mangling error fails open to the untouched line; a message is
-- never swallowed to protect a filter.
function chat.SendChatMessage(message, chatType, languageID, target)
  local out = message
  local ok, mangled = pcall(chat.MangleForSend, message, chatType, target)
  if ok then
    out = mangled
  end
  return chat.savedSend(out, chatType, languageID, target)
end

-- Wrap the documented send call. Chain-safe: only one wrapper stands
-- at a time, and removing it restores exactly what was there. A
-- missing API declines instead of erroring.
function chat.HookSend()
  if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.SendChatMessage) ~= "function" then
    return false
  end
  if C_ChatInfo.SendChatMessage == chat.SendChatMessage then
    return true
  end
  chat.savedSend = C_ChatInfo.SendChatMessage
  C_ChatInfo.SendChatMessage = chat.SendChatMessage
  return true
end

-- Remove the wrapper, but only while it is still ours: a later
-- wrapper from another addon stays standing, and our saved call
-- simply stops being reached.
function chat.UnhookSend()
  if type(C_ChatInfo) == "table" and C_ChatInfo.SendChatMessage == chat.SendChatMessage then
    C_ChatInfo.SendChatMessage = chat.savedSend
  end
  chat.savedSend = nil
end

-- The Impl hooks the descriptor delegates to: toggling installs or
-- removes the send wrapper, so nothing intercepts while off.
function chat.ApplyEnabledImpl()
  if chat.opts().enabled then
    chat.HookSend()
  else
    chat.UnhookSend()
  end
end

function chat.InitImpl()
  chat.ApplyEnabledImpl()
end

-- Toggle the module: the setting applies live, the checkbox sound
-- confirms, and the wrapper installs or removes with it.
function chat.SetEnabled(on)
  ns.config.Set(chat.SECTION, "enabled", on)
  ns.play(on and "on" or "off")
  ns.say("chat module " .. (on and "on" or "off"))
  if chat.ApplyEnabledImpl then
    chat.ApplyEnabledImpl()
  end
end

function chat.ToggleEnabled()
  chat.SetEnabled(not chat.opts().enabled)
end

-- One channel's display name: the numbered-channels toggle reads as
-- general everywhere but the stored key.
local function channelName(key)
  if key == "channel" then
    return "general"
  end
  return key
end

-- One line naming every channel toggle, in stored-key order.
function chat.ChannelStates()
  local o = chat.opts()
  local parts = {}
  for _, key in ipairs({ "say", "yell" }) do
    parts[#parts + 1] = channelName(key) .. " " .. (o[key] and "on" or "off")
  end
  return "channels " .. table.concat(parts, ", ")
end

-- Report one channel flip, or the whole list on a bare or list
-- toggle; an unknown channel prints help and changes nothing.
function chat.ToggleChannel(key)
  if key == nil or key == "" or key == "list" then
    ns.say("chat " .. chat.ChannelStates())
    return
  end
  local o = chat.opts()
  if o[key] == nil then
    ns.help()
    return
  end
  local on = not o[key]
  ns.config.Set(chat.SECTION, key, on)
  ns.play(on and "on" or "off")
  ns.say("chat " .. channelName(key) .. " channel " .. (on and "on" or "off"))
end

-- Report one dialect switch. Chance 0 stays silent by design, so the
-- line says so instead of promising a voice that never speaks.
function chat.SetDialect(dialect)
  ns.config.Set(chat.SECTION, "dialect", dialect)
  ns.play("on")
  local line = "chat dialect " .. (dialect == "dwarf" and "dwarven" or "troll")
  if (chat.opts().chance or 0) <= 0 then
    line = line .. ", chance 0 stays silent"
  end
  ns.say(line)
end

-- Report one chance change. Zero mutes the filter without uninstalling
-- it; anything outside 0-10 is a typo and prints help instead.
function chat.SetChance(raw)
  local chance = tonumber(raw)
  if chance == nil or chance < 0 or chance > 10 or chance ~= math.floor(chance) then
    ns.help()
    return
  end
  ns.config.Set(chat.SECTION, "chance", chance)
  ns.play(chance > 0 and "on" or "off")
  ns.say("chat chance " .. chance)
end

function chat.Slash(rest)
  local cmd, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
  if cmd == "" then
    chat.ToggleEnabled()
  elseif cmd == "on" then
    chat.SetEnabled(true)
  elseif cmd == "off" then
    chat.SetEnabled(false)
  elseif cmd == "dwarf" or cmd == "troll" then
    chat.SetDialect(cmd)
  elseif cmd == "chance" then
    chat.SetChance(arg)
  elseif cmd == "toggle" then
    chat.ToggleChannel(arg)
  else
    ns.help()
  end
end

-- The descriptor loads first; Dialect.lua and Dictionaries.lua hold
-- the engine and its tables, Panel.lua fills in the BuildPanelImpl it
-- delegates to, so registration never waits on them.
local descriptor = {
  name = "chat",
  title = "Chat",
  job = "Rewrites outgoing /say and /yell in a dwarven or troll dialect before it sends",
  default = true,
  IsAvailable = chat.IsAvailable,
  init = function()
    if chat.InitImpl then
      chat.InitImpl()
    end
  end,
  BuildPanel = function(page)
    if chat.BuildPanelImpl then
      chat.BuildPanelImpl(page)
    end
  end,
  Slash = chat.Slash,
}
chat.descriptor = descriptor
ns.modules.Register(descriptor)

-- Help lines for this module's subcommands, inserted ahead of the
-- config/help pair so the house grammar (config second to last, help
-- last) still holds. Chat loads first, so its lines read first.
do
  local lines = {
    "/vui chat                   turn the dialect filter on or off",
    "/vui chat on|off            turn the dialect filter on or off",
    "/vui chat dwarf|troll       speak dwarven or troll",
    "/vui chat chance <0-10>     how often the dialect rewrites words",
    "/vui chat toggle <channel>|list choose which channels change",
  }
  local at = #ns.HELP - 2 -- ahead of the config line (second to last)
  for i, line in ipairs(lines) do
    table.insert(ns.HELP, at + i, line)
  end
end
