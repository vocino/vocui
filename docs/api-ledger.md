# API ledger

Every Blizzard name VocUI relies on, with its verification verdict on
the `forever` branch of the wow-ui-source mirror (procedure:
`docs/api.md`). One row per name. A name whose verdict is `GONE` or
`unknown` never ships unguarded; the bare forms Blizzard moved into a
namespace live in `checks/deprecated-globals.txt` instead of here.

When a row changes, change the code first, the row second. Add a row
when the package comes to rely on a new name, in the same commit that
adds the name to `.luacheckrc`, and quote the verdict in the commit
body.

Seeded 2026-11-03 with the core scaffold's full API surface, verified
against the `forever` branch for the build in `## Interface:` (16001).

| Name | forever |
| --- | --- |
| `Settings.RegisterVerticalLayoutCategory` | ok, Lua: Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua |
| `Settings.RegisterVerticalLayoutSubcategory` | ok, Lua: Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua |
| `Settings.RegisterAddOnCategory` | ok, Lua: Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua |
| `Settings.OpenToCategory` | ok, Lua: Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua |
| `CreateSettingsListSectionHeaderInitializer` | used, Lua: Interface/AddOns/Blizzard_Settings_Shared/Blizzard_SettingControls.lua (undocumented; Blizzard calls it) |
| `CreateFrame` | bare (C-side global; Blizzard's Forever code calls it bare throughout) |
| `PlaySound` | ok, Lua: Interface/AddOns/Blizzard_SharedXML/Mainline/Sound.lua |
| `SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON` | ok, = 856 |
| `SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF` | ok, = 857 |
| `SOUNDKIT.IG_MAINMENU_OPEN` | ok, = 850 |
| `SOUNDKIT.IG_MAINMENU_CLOSE` | ok, = 851 |

`GameTooltip`, `Settings`, `SettingsPanel`, and `SOUNDKIT` are the
global frames and tables the rows above hang off; they are part of
Blizzard's UI in the Forever client and are read presence-gated like
everything else in `.luacheckrc`.
