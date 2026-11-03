# Coding

How Lua is written in this package. The standard is boring Lua: a
maintainer understands the whole feature in one pass. Optimize for
that, not for the fewest lines or the cleverest architecture. When in
doubt, write the dumber version.

## Shape of the code

- `local` by default. Every helper is a `local function`; every file
  opens `local name, ns = ...`; state lives on `ns`, never on `_G`.
  The only globals are the prefixed entry points Blizzard requires
  (`VocUIDB`, `SLASH_VOCUI1/2`, the compartment functions), and
  `.luacheckrc` holds that boundary while `wowlua_ls` holds the types.
- Explicit initialization. File top level defines; it does not act.
  SavedVariables rebind on `ADDON_LOADED`, defaults fill before use,
  the settings tree builds once, and a module's job runs from its
  descriptor's init, called by the core loader inside a `pcall`,
  never as a side effect of loading.
- Event-driven updates. Register only the events a module needs;
  unregister what a disable turns off. A setting change calls the
  code it affects through the core store's change events. Nothing
  polls, and nothing ticks on `OnUpdate` to re-read state.
- Almost no framework. Straight-line code and small helpers: no OOP
  emulation, no metatable magic, no generic event bus, no vendored
  libraries. A second small function beats an abstraction.
- Testable seams. Behavior lives behind `ns.*` functions (and module
  functions) that stubbed WoW APIs can drive from `tests/`; the
  Blizzard entry points are thin wrappers around them.
- Template order inside a file, so every file reads the same way:
  the file's descriptor or locals first, then its state, then its
  helpers, then the job, then its settings rows, then its events
  last. Core files follow the scaffold's shape (palette, chat,
  sounds, config, modules, settings, slash, main).

## Naming

- The package is `VocUI`. Every global carries the name: the
  SavedVariable is `VocUIDB`, named frames are `VocUISomething`,
  static popups are `VOCUI_SOMETHING`. Never introduce an unprefixed
  global.
- Modules are named for their job in lower case (`modules/gear/`),
  and the folder name is the module's id everywhere: descriptor,
  saved-variables section, settings page.
- Validity predicates are named `IsAvailable()` on the module, with a
  comment giving the reason for each condition they check.

## The module descriptor

The core loads modules from descriptors and from nothing else. A
module's first file defines:

- `name`: the module id (its folder name).
- `title`: the display name for the settings tree and the addon list.
- `job`: one sentence saying what the module does; it becomes the
  first line of its settings page.
- `default`: whether the module starts on or off for a fresh install.
- `IsAvailable()`: the validity predicate. False means the module is
  never initialized and never listed (README principle 12).
- `init()`: wires the module up; runs inside the core's `pcall`. A
  module's toggle fully enables or disables it: its events register
  and unregister with the toggle.
- `BuildPanel(page)`: fills the module's settings page with
  declarative option rows (below).

## Slash grammar

One slash pair serves the whole package; modules add subcommands,
never their own slash commands.

```
/vui              open the settings tree (or the package's main window, when one exists)
/vui config       open Settings > AddOns > VocUI
/vui help         list every subcommand
/vui <module> on|off    toggle a module
/vui <sub> ...    module subcommands, lower-case, case-insensitive input
```

Anything unrecognized prints help; it never performs an action, so a
typo can never toggle, sell, or equip. `config` and `help` always
exist. Help is an `ns.HELP` table, one subcommand per line, the
command padded so descriptions line up, `config` second to last and
`help` last, naming the long form: "(/vocui works too)".

## Chat voice

Chat lines go through the core chat helper (`ns.say`), which prints
the package name as a colored prefix followed by the message:

```lua
ns.PREFIX_COLOR = "ff66ccff"   -- the family color
function ns.say(msg)
  print("|c" .. ns.PREFIX_COLOR .. name .. "|r: " .. tostring(msg))
end
```

One line per event. Announce-once per session for advice that would
otherwise repeat. Lower-case first word after the prefix ("equipped
... ", "gear module on"). No trailing period: a chat line is a log
entry, not a sentence. Every line is a fact or a next step, never a
greeting.

## Sounds

Every toggle and every window confirms with a Blizzard sound, through
the core helper only; nothing calls `PlaySound` directly. SOUNDKIT
names first and the numeric IDs behind them, so a Blizzard rename
never silences the polish and a missing sound API never errors:

```lua
ns.SOUNDS = {
  on = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
  off = { "IG_MAINMENU_OPTION_CHECKBOX_OFF", 857 },
  open = { "IG_MAINMENU_OPEN", 850 },
  close = { "IG_MAINMENU_CLOSE", 851 },
}
function ns.play(kind)
  local s = ns.SOUNDS[kind]
  if not s or type(PlaySound) ~= "function" then return end
  local id = type(SOUNDKIT) == "table" and SOUNDKIT[s[1]] or nil
  pcall(PlaySound, type(id) == "number" and id or s[2])
end
```

Toggles use `on`/`off`, windows and readouts `open`/`close`, and
slash toggles count: `/vui gear off` sounds like the checkbox it is.
A module with a sound of its own adds a key to the same table. The
four SOUNDKIT values are verified in `docs/api-ledger.md`.

## Settings mechanics

- One account-wide SavedVariable, `VocUIDB`: the core's options at
  the top level, each module's state under `VocUIDB.modules.<id>` and
  nowhere else.
- A `defaults` table per owner (core, each module) is the single
  source of truth. On load, missing keys are filled, and any key
  holding the wrong type or an out-of-range value is reset to its
  default. Unknown keys are left alone for forward compatibility.
- Options are declarative rows handed to the core settings service,
  which registers them on the module's subcategory page with native
  Settings controls (`Settings.RegisterAddOnSetting` plus the
  checkbox, slider, and dropdown creators). No hand-drawn canvas
  panels. Registration is retried at `PLAYER_LOGIN` when the Settings
  API was not up at `ADDON_LOADED`, and every setting carries a
  value-changed callback so the change applies at once, with no
  reload (`checks/no-reloadui.sh` holds this).
- Child options gate on their parent: when the parent is off,
  children show disabled, never hidden, with the reason visible on
  the row. A conditional section header shares one predicate with its
  widgets, so the header never disagrees with what sits under it.
- Free-text options (names, keys) live on the slash line, and the
  module's page says so.
- No search or sort UI while a page's options fit on one screen.

## Addon compartment

The package registers with Blizzard's addon compartment through the
`.toc` (`AddonCompartmentFunc`, `...OnEnter`, `...OnLeave`), so the
player finds it even without the slash command. The click opens the
settings tree (or the main window, when one exists). Hover follows
the tooltip contract in CRAFT.md: gold title, one white line saying
what the package does, one muted line teaching the slash command.
Disabling a module from its page prints the re-enable command in
chat, so the way back is one line away.

## Tests and lint

- Tests are plain Lua with stubbed WoW APIs, written for Lua 5.1 (the
  client's dialect) and passing on 5.4 as well. `lua tests/run.lua`
  from the repo root exits non-zero on failure.
- `luacheck .` passes with the repo's `.luacheckrc`.
- `wowlua_ls check . --severity warning` passes. The repo's
  `.wowluarc.json` pins the `forever` flavor, so retail-only API use
  fails the check.
- `bash checks/run-all.sh .` passes (see `checks/`).
- No release ships red, and no commit lands with any of the four
  failing.
