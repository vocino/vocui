# VocUI

A comprehensive addon package for World of Warcraft: Forever, built for
one player and the way he actually plays. VocUI is not a suite for
everyone. It is a personal instrument: one package, many small modules,
every one of them there because it serves a real habit at the keyboard.

It grows while he plays. There is no roadmap and no release train: when
a session surfaces a need, a module gets built for it, and the package
he logs into next week is a little more his than the one from the week
before. This repository is that running record.

The constitution lives in the wiki ([Principles](https://github.com/vocino/vocui/wiki/Principles)).
It defines the principles the code follows before any feature code
exists, and it keeps defining them as the package grows. Features come
later, one module at a time, and every module has to name the
principles it serves. A feature that cannot name one does not ship.
This README keeps the player profile and the package status; the
[Charter](#charter) section below points at the wiki for everything else.

## If you are not me

You are welcome here. The license is MIT; take it, use it, fork it. But
know what you are looking at: an addon fitted to one person's setup,
habits, keybinds, and taste, maintained for an audience of one. There is
no support, no feature request queue, and no plan to reshape anything
for another player's game. If it fits your play too, that is a happy
accident, not a design goal.

## What this is

- One addon package for the Forever client only, installed as a single
  folder, updated as a single release. Self-contained: its core, its
  modules, its craft, and its rules all live in this repo and its
  wiki, and it owes nothing to any other project.
- A work in progress by design. It is never finished, because the play
  it serves is never finished; it just keeps accumulating the modules
  its player has needed so far.
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

## Charter

The 25 principles, the module contract, repository layout, and how
the charter evolves live in the wiki:
[Principles](https://github.com/vocino/vocui/wiki/Principles) (local
copy: wiki/Principles.md). API in
[API-Verification](https://github.com/vocino/vocui/wiki/API-Verification),
style in [Craft](https://github.com/vocino/vocui/wiki/Craft) and
[Coding](https://github.com/vocino/vocui/wiki/Coding), core decisions in
[Principles](https://github.com/vocino/vocui/wiki/Principles), the modules in
[Modules-Gear](https://github.com/vocino/vocui/wiki/Modules-Gear),
[Modules-XP](https://github.com/vocino/vocui/wiki/Modules-XP), and
[Modules-Vendor](https://github.com/vocino/vocui/wiki/Modules-Vendor). This README
keeps the player's profile and the package status; for everything
else, the wiki is the single source.

## Status

Principles first, on purpose. The core scaffolding is in place (loader,
settings store, palette, sounds, chat, slash, and the headless test
harness). Modules so far:
- **Gear** (`modules/gear/`): equips bag upgrades out of combat by
  item level, with its own page under Settings > AddOns > VocUI and
  `/vui gear` subcommands. Item level is the whole judgment; Forever
  has no stat weights to configure.
  Bag contents come from Syndicator when it is present and settled
  (else Blizzard's own bag walk), and item values from Auctionator
  with a vendor fallback; both are guests, never requirements.
- **XP** (`modules/xp/`): XP per hour and time to level on its own
  bar, with rested reach and ready-to-turn-in quest XP overlaid, and
  reputation with Rep/hr at max level. While leveling, the tooltip
  carries a bonuses section: verified XP effects show active with time
  left and missing dimmed, with a food-in-bags hint. Its own page
  under Settings > AddOns > VocUI and `/vui xp` subcommands.
- **Vendor** (`modules/vendor/`): sells poor-quality junk and repairs
  gear automatically at the merchant, guild funds first, audit mode
  instead of acting, and a deduped Vendor line in item tooltips. It
  sells junk and repairs, nothing else: no old-gear selling, no
  disenchanting, no button. Its own page under Settings > AddOns >
  VocUI and `/vui vendor` subcommands.

From here the package grows the way it was designed to: a module at
a time, added while playing, each
one recorded here when it lands.

---

Built for Forever, for one player, by vocino.
