# Craft

How VocUI looks, feels, and behaves at the level of the hand: the
style paradigms every module follows when it builds a window, a
settings page, a tooltip, or a sound.

The standard, in one sentence: respect the player's attention.
Nothing loads unneeded, nothing shows broken, nothing is silent when
it should confirm, and nothing requires configuration that a good
default could replace.

## Where this comes from

This file distills the Voc family's craft sources into the copy this
repo works from: the `voc-addons` skill's visual identity spec and
its craft study of Peterodox's addons (Plumber, Narcissus,
DialogueUI). The paradigms are his and the family's; the code here is
original and built on Blizzard's own textures. Plumber is GPL and
nothing is copied from it: emulate the approach, never the code or
the art.

This file is the repo's own now. It was distilled once, at setup,
and it evolves here from what ships in this package; nothing outside
the repo is consulted for craft. Inside this repo, this file is what
an agent reads before UI work; the README's principle 16 points here.

## The look

**Blizzard-native is technique, not art.** Windows are built on
Blizzard's 9-slice backdrops and textures, snapped to the pixel grid,
corners crisp at any size. A frame looks like it belongs in the game
when it is constructed the way Blizzard constructs frames. Never draw
a custom border when a Blizzard one exists. Never ship a custom font;
use Blizzard font objects, and keep the 1-pixel text shadow on every
string.

**A tiny palette, used semantically.** Defined once in
`core/Palette.lua`, referenced by name, never written as a hex value
at a call site:

| Token | Value | Role |
| --- | --- | --- |
| gold | `1, 0.82, 0` (`ffd100`) | titles, emphasis, the one accent per screen |
| text | `1, 1, 1` | body text |
| muted | `0.5, 0.5, 0.5` | secondary text, hints, timestamps |
| red | `0.9, 0.3, 0.25` | warnings and restriction lines only |
| green | `0.25, 0.9, 0.35` | valid state only |

Red and green appear only for state. When red appears it means
something, because it almost never appears. Panels are dark and
textured, never flat fills. If a screen has two gold elements
competing, one of them is wrong. Data colors a module owns (item
quality, verdicts) live in the same palette table.

**Four type levels, no more.** Gold title (one per panel, names the
thing), white section header (names a group), white body (the working
text), gray hint (secondary info). Never skip a level. Size and
weight do the structural work; color does the emphasis.

**Information order, on every screen.** The answer first, supporting
context second, actions third, configuration last. Summary first,
detail on hover or click. A screen that shows everything at once has
no hierarchy. In the settings tree this is why module pages lead with
what the module does, not with its options.

**Panel construction.** One padding rhythm; related controls sit
closer than unrelated ones. Section headers are labeled plaques, not
bare text floating in space. Disabled controls desaturate; they
never just dim.

**One icon.** The package has one medallion identity: a circular gold
emblem on a dark field, one glyph, readable at 32 pixels. Until the
medallion ships, the toc points at the stock game icon that matches
the job, so the addon list and the compartment read as intended.

## The feel

**Every interaction confirms.** A Blizzard sound on every meaningful
interaction, SOUNDKIT names first and numeric IDs behind them, so a
Blizzard rename never silences the polish:

| Kind | Sound | ID |
| --- | --- | --- |
| toggle on | `IG_MAINMENU_OPTION_CHECKBOX_ON` | 856 |
| toggle off | `IG_MAINMENU_OPTION_CHECKBOX_OFF` | 857 |
| window open | `IG_MAINMENU_OPEN` | 850 |
| window close | `IG_MAINMENU_CLOSE` | 851 |

Toggles use the checkbox pair, windows use open and close, and slash
toggles count: `/vui` flipping a module sounds like the checkbox it
is. Buttons on stock templates play nothing until the addon hooks
their click; hook them. Nothing calls `PlaySound` directly; the core
sound helper is the only route.

**Hover is a contract.** Every toggle and control shows a
GameTooltip: gold title, one white line saying what it does, and a
red restriction line when it cannot work right now ("does not work
in instances"). Tooltips never fire mid-drag; the hover handler
checks `IsMouseButtonDown()` first. Anything longer than two lines
lives in an inline detail region beside the control, never in the
tooltip.

**Motion is subtle.** Panels fade or scale in; nothing pops.

**Chat voice.** One line per event through the core chat helper:
the addon name as a colored prefix, a lower-case first word, a fact
or a next step, no trailing period. Announces what it did and stays
quiet otherwise.

## The paradigms

Distilled from the Plumber study and the family skill, stated as
rules for this package:

1. **Settings are data, applied live.** Options are declarative
   tables (type, label, tooltip, key, validity), never hand-built
   frames per option. The core store broadcasts a change event per
   key; modules react to the event. Nothing polls, nothing needs a
   reload.
2. **Defaults are the onboarding.** There is no first-run wizard.
   New modules default on, announced with one chat line and a "New"
   tag on their settings page that expires after 7 days. The rare
   module that must not auto-enable is named in one explicit
   denylist in the core, never in scattered conditionals. Pick
   defaults as if the settings page will never be opened.
3. **Modules self-register and fail alone.** A module's descriptor
   carries its toggle, and toggling fully enables or disables it:
   its events register and unregister with it. Init runs inside a
   protected call, so one broken module reports and the rest of the
   package never notices.
4. **Unavailable is a designed state.** A module declares its
   validity conditions. What cannot work now is hidden or disabled
   with the reason on the row, never shown broken. If the UI must
   disappear (a countdown, a queue popup), it restores itself
   afterward. The player is never left blind or staring at an error.
5. **Heavy things load on demand.** Login stays light. A module with
   a rare, expensive trigger gates its heavy code behind the event
   that defines the situation, not behind startup.
6. **Retired in public, with reasons.** Removed code stays as a
   comment with its reason attached ("fixed by Blizzard in the
   Forever launch build"). The no decisions are documented where the
   next reader will find them, so a settled bad idea is not re-added.
7. **Read Blizzard's source, not only the docs.** The API docs say
   what a function should do; Blizzard's UI source says what it
   does. When a Forever quirk forces a workaround, the workaround
   lives in one clearly named place, never sprinkled through a
   module's logic.
8. **Zero dependencies.** No libraries folder, nothing vendored
   without its license and attribution in the file. Other addons are
   guests: detected, integrated with softly, degraded silently.

## Anti-patterns

These never ship, no matter how modern they look elsewhere:

- Flat web-style panels with no texture.
- Custom fonts, or text without its 1-pixel shadow.
- Rainbow colors; gold is the only warm accent.
- Silent buttons or toggles.
- Config-first screens that bury the answer below the options.
- A hex color written at a call site.
- One-off visual inventions per module or per screen. If it is not
  in this file, it does not go in until this file says it can.

## Applying this file

Read it before any UI, settings, tooltip, sound, or visual-polish
work on any module, and review against it before calling that work
done. Where a rule here can be checked mechanically, a script in
`checks/` checks it; run `bash checks/run-all.sh .` before committing.
