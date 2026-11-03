# AGENTS.md

## Code Map

- `VocUI.toc` - Forever client metadata (Interface 16001)
- `core/` - loader, settings store, palette, sounds, chat, slash
- `modules/` - one folder per module, descriptor first (none yet)
- `tests/` - headless tests (`lua tests/run.lua`)
- `CRAFT.md` - the style paradigms: palette, type, panels, sounds, hover, anti-patterns
- `docs/coding.md` - how Lua is written here: file shape, naming, slash grammar, chat voice, sounds, settings mechanics
- `docs/api.md` - sources of truth and the API verification procedure; `docs/api-ledger.md` is the verdict record
- `docs/debugging.md` - the !BugGrabber / BugSack loop
- `checks/` - mechanical checks; `bash checks/run-all.sh .` runs them all

## Conventions

- Place each module in its own folder under `modules/`.
- Place shared loader and services under `core/`.
- Keep Forever client metadata in a `.toc` file.
- Forever only: verify every API against the Forever build, Lua 5.1, no deprecated globals.
- Read `CRAFT.md` before any UI, settings, tooltip, sound, or visual work, and review against it before calling that work done. It carries the palette tokens, type levels, information order, sound table, and tooltip contract every module follows.

## References

This repo is self-contained: everything an agent needs is in it, and
nothing outside it is consulted. Read by task:

- Any UI, settings page, tooltip, sound, or visual work: `CRAFT.md`
  first, then review against it before calling the work done.
- Writing or changing Lua: `docs/coding.md` (shape, naming, slash,
  chat, sounds, settings mechanics) and the module contract in
  README.
- Any Blizzard API, event, or ID: `docs/api.md` for the sources of
  truth and the verification procedure, `docs/api-ledger.md` for the
  recorded verdicts. Never code an API from memory or from a wiki
  signature. A name not in the ledger gets verified against the
  `forever` branch before it is used, added to `.luacheckrc` only
  after verification, and given its ledger row in the same commit.
- A bug report or a Lua error: `docs/debugging.md`.
- Before any commit: `lua tests/run.lua`, `luacheck .`,
  `wowlua_ls check . --severity warning`, and
  `bash checks/run-all.sh .` all pass.

## The one system

VocUI is one addon, not a bundle of addons. Modules feel like one
product: one install, one update, one entry point, one settings tree,
one palette and sound language (README principles 23 and 16). When a
choice trades cohesion for a module's convenience, cohesion wins.

## Module contract (short form)

The full contract is in README, "The module contract". The shape:

- Folder `modules/<job>/`; the descriptor file loads first.
- Descriptor: id (folder name), title, job in one sentence, default
  on or off, validity predicate, init function. The core loads modules
  from descriptors only.
- State only under `VocUIDB.modules.<id>`. No other module's state,
  no state anywhere else.
- No module calls another module. Shared needs go through core
  services or core broadcasts.
- Init runs inside a protected call from the core loader; a module
  that fails its validity predicate is never initialized or listed.

## Settings tree

- The core registers the single parent category `VocUI` once, in
  `core/Settings.lua`, with `Settings.RegisterVerticalLayoutCategory`.
- Each module gets one subcategory page under that parent, named for
  its job, via the core settings service
  (`Settings.RegisterVerticalLayoutSubcategory`, verified ok on the
  Forever branch 2026-11-03). A module never registers a top-level
  category.
- A module with no options still gets a page: its toggle and one line
  saying what it does.
- Options are declarative rows on the module's own page; changing one
  applies live through the core store.

## Adding a module

Follow these steps in order, every time (README principle 25). If a
step does not fit the module, extend this list in the same commit.

1. Create `modules/<job>/` with the descriptor file first, then the
   module's files. One job, statable in one sentence.
2. Add the module's files to `VocUI.toc`, after the core block, in
   alphabetical order by folder, descriptor first within the folder.
3. Give the module its settings page through the core settings
   service (see Settings tree). Declare its options as data.
4. Keep its state under `VocUIDB.modules.<job>` and nowhere else.
5. Add headless tests for its logic in `tests/`; run
   `lua tests/run.lua`, `luacheck .`, and
   `wowlua_ls check . --severity warning` until all three pass.
6. Add the module to the Status section of README.md.
7. Commit as `feat:` and name the README principles the module
   serves in the commit body.
