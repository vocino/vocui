-- Lint config for VocUI (Forever client, Lua 5.1). read_globals is
-- the allowlist of WoW API verified against the Forever build in
-- `## Interface:`; lint fails on any other global on purpose: add a
-- name here only after confirming it exists, under that namespace, in
-- the Forever build. Never from a wiki.
std = "lua51"
max_line_length = false
self = false
unused_args = false

-- Globals this package owns: the SavedVariable, slash registration,
-- and the addon compartment entry points named in the .toc.
globals = {
  "VocUIDB",
  "SLASH_VOCUI1", "SLASH_VOCUI2",
  "SlashCmdList",
  "VocUI_CompartmentClick", "VocUI_CompartmentEnter", "VocUI_CompartmentLeave",
}

-- WoW API and UI globals read by the core. Every entry is
-- presence-gated at the call site; a missing API is never an error.
read_globals = {
  "CreateFrame",
  "CreateSettingsListSectionHeaderInitializer",
  "GameTooltip",
  "PlaySound", "SOUNDKIT",
  "Settings", "SettingsPanel",
}

-- Tests install stubs onto _G by design.
files["tests/**"] = {
  std = "max",
  globals = { "print", "_G" },
  read_globals = { "os" },
}
