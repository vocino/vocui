# VocUI

A comprehensive addon package for World of Warcraft: Forever, built for
one player and the way he actually plays. VocUI is not a suite for
everyone. It is a personal instrument: one package, many small modules,
every one of them there because it serves a real habit at the keyboard.

This README is the constitution. It defines the principles the code will
follow before any feature code exists, and it keeps defining them as the
package grows. Features come later, one module at a time, and every
module has to name the principles it serves. A feature that cannot name
one does not ship.

## What this is

- One addon package for the Forever client only, installed as a single
  folder, updated as a single release.
- A collection of independent modules under a small shared core. Each
  module does one job. The package is comprehensive because the modules
  add up, not because any module is big.
- A living record of one player's play style, expressed as software:
  leveling a small warband, professions as real systems, a guild and
  community to show up for, appearances worth collecting, and a second
  screen beside the game for planning.

## What this is not

- Not a retail addon. Nothing here is designed for, tested on, or
  constrained by the retail client. If that ever changes, it changes as
  a decision recorded in this file, not as a quiet port.
- Not a public product. There is no audience to onboard, no
  configuration owed to strangers, no localization, no feature ballot.
  Defaults are tuned to one player's habits because there is one player.
- Not a framework. No library stack, no plugin API for other authors,
  no abstraction kept for a future that has not asked for it.

## The player

The design target, stated plainly so modules can be judged against it:

- Forever is the game right now. Leveling comes first: a Troll Warlock
  and a Human Hunter, professions trained as he goes, quests read and
  routes followed with a guide addon in game and a planning site on the
  second screen.
- Play is deliberate and unhurried. Power matters, but so do the
  collection, the guild, and the look of the character.
- Attention is the scarce resource. Anything the package shows has to
  earn its place in a glance, during play, without a manual.

## Product principles

1. **Audience of one.** Every decision resolves to one question: does
   this serve how this player plays? "Other players might want" is
   never a reason to build, keep, or complicate anything.
2. **Forever only.** Design against Forever's actual systems: its
   classes, camping, the Legacy system, dual specialization at 40, its
   professions and its economy. Never import a retail assumption.
   Retail features that do not exist here stay absent, and Forever
   features with no retail analogue get designs of their own.
3. **Follow the current game.** The roadmap is whatever the player is
   doing this season. When his goals move from leveling to endgame, the
   modules follow. Nothing is built ahead of the habit it serves.
4. **Answers first, attention last.** Screens and readouts order
   information the family way: the answer first, supporting context
   second, actions third, configuration last. Nothing acts in combat,
   nothing spams at login, nothing pops up uninvited.
5. **Beside the second screen, not instead of it.** Planning lives on
   wow.vocino.com. VocUI handles the decisions that happen at the
   keyboard, in the moment, and stays out of the planning surface's
   way. The two never duplicate each other.
6. **Automate the reversible, confirm the irreversible.** Equipping,
   sorting, and reporting may run on their own and announce themselves.
   Destroying, selling, mailing, or spending always asks first.
7. **Guests, not dependencies.** The player's other addons (guide,
   bags, waypoint, and the four Voc family addons) are welcome and
   integrated with softly when present. VocUI requires none of them and
   degrades silently when any of them is absent or broken.
8. **Modules earn their place in play.** A module that stops being
   used gets removed, and the removal is recorded here with its reason.
   Scope discipline applies to the whole package, not only to code.

## Architecture principles

9. **A small core, many modules.** The core does five things only:
   load modules, hold settings, provide the shared palette and sounds,
   route the slash command, and print chat. Everything a player would
   recognize as a feature is a module.
10. **Modules are self-contained.** A module is a folder with a small
    descriptor (name, job in one sentence, toggle, validity check), its
    own files, and its own section of the settings store. It registers
    itself; the core never reaches inside it.
11. **Modules meet only at the core.** No module calls another module.
    Shared needs become core services or stay duplicated in the small.
    Deleting a module means deleting its folder and its descriptor
    line; nothing else references it.
12. **One broken module never breaks the package.** Modules initialize
    inside protected calls. A module that cannot work in the current
    situation is never initialized and never listed: unavailable is a
    designed state, hidden rather than shown broken. Each validity
    check is a named predicate with a comment giving its reason.
13. **Boring Lua.** Local by default, state on the namespace, never on
    globals the prefix does not own. File top levels define; they do
    not act. Updates are event-driven; nothing polls and nothing ticks
    to re-read state. The cleanest module is the one a maintainer can
    understand in one pass.
14. **Settings are data, applied live.** Options are declarative
    tables. A central store broadcasts changes; modules subscribe.
    Changing a setting takes effect immediately, with no reload. The
    settings panel is one native category for the whole package, and
    each module contributes its own section to it.
15. **Defaults are the product.** Because there is one player, defaults
    carry the design. A module ships already set up the way he plays;
    settings exist mainly to turn modules off, not to configure them
    into usefulness. If a module needs explaining, simplify the module.

## Craft principles

16. **The family look and feel.** VocUI inherits the Voc family's craft
    whole: the palette defined once and referenced by name, Blizzard
    panels and font objects, a sound confirming every meaningful
    interaction, the family chat voice (one line, a fact or a next
    step, no trailing period). The `voc-addons` skill is the source of
    truth for that craft; when this file and the skill disagree about
    look and feel, the skill wins.
17. **Stock first.** Default chrome is Blizzard's own, so the package
    looks native beside the game's windows. Custom visuals are spent
    only where the game's own cannot say the thing.
18. **Designed for the next developer.** Modules are documented at the
    descriptor, public functions say what they do, and the layout below
    stays accurate. The next developer is usually the same player and
    an agent with this README open; both should be able to extend a
    module without reading anyone's mind.

## Engineering principles

19. **Verify the API on the Forever branch.** Code targets the build
    in the Forever client's `## Interface:`. Every API fact is checked
    against Blizzard's own documentation and UI source for that build
    (the `forever` branch of the UI source mirror), in the order
    FAMILY.md's Sources of truth prescribes. Wikis and memory are leads
    to confirm, never sources. Every global the code reads is listed
    in the lint allowlist, added only after verification.
20. **Headless tests, always green.** Module logic lives behind
    functions that stubbed WoW APIs can drive. No release ships with a
    failing test, a lint error, or a type error.
21. **Debug with the community's tools.** !BugGrabber captures errors
    and BugSack shows them in game; the development loop reads the
    saved error file directly after a reproduction and a `/reload`.
22. **Releases are tags.** Versioning is semantic and tag-driven, and
    commit subjects are the changelog: `feat:`, `fix:`, `docs:`,
    `chore:`, written so the player can read what changed and why.

## Deliberate breaks from the Voc family

VocUI is a sibling of the four family addons, not a fifth member, and
it breaks two family rules on purpose:

- **One job per addon** becomes one job per module. The family stays
  tiny and independent; this package is where integration is allowed
  to live, and the modularity principles above are what keep that from
  becoming a tangle.
- **Every version of the game** becomes Forever only (principle 2).
  The family keeps shipping dual clients; VocUI spends all of its
  effort on the one client its player is playing.

Everything else in FAMILY.md (naming, slash grammar, chat voice,
sounds, palette, settings mechanics) applies here unchanged, carried
by reference rather than copied, so this file can stay about what is
different.

The graduation path runs the other way: when a module proves useful
enough to stand alone for other players, it graduates into a family
addon of its own, with its own repo, and leaves VocUI behind.

## Repository layout

```
VocUI/
  VocUI.toc           Forever client metadata (Interface 16001)
  core/               loader, settings store, palette, sounds, chat, slash
  modules/            one folder per module, descriptor first
  tests/              headless tests for core and modules
  README.md           this file
  AGENTS.md           contributor map for agents
  LICENSE             MIT
```

Naming follows the family: the package is `VocUI`, its saved variables
are `VocUIDB`, its slash commands are `/vui` and `/vocui`, and every
global it owns carries the `VocUI` prefix. Module folders are named for
their job in lower case.

## How this document evolves

Principles are numbered and never renumbered. A principle changes by
editing this file in the same commit as the work that motivates the
change, with the reason in the commit. A retired principle is marked
retired, with the date and the lesson, not deleted: the paper trail is
part of the design. When a principle and the code disagree, the code is
wrong until this file says otherwise.

## Status

Principles first, on purpose. There is no feature code yet. The first
feature set will be chosen against these principles, built as modules,
and recorded here when it lands.

---

Built for Forever, for one player, by vocino. The four family addons
stay independent: [VocWarbank](https://github.com/vocino/vocwarbank) ·
[VocGear](https://github.com/vocino/vocgear) ·
[VocXP](https://github.com/vocino/vocxp) ·
[VocVendor](https://github.com/vocino/vocvendor)
