# AGENTS.md

## Code Map

- `VocUI.toc` - Forever client metadata (Interface 16001)
- `core/` - loader, settings store and page builder, shared reads (combat, guest presence, bag walk), guest services (Syndicator inventory, Auctionator prices), palette, sounds, chat, slash
- `modules/` - one folder per module, descriptor first (gear so far)
- `tests/` - headless tests (`lua tests/run.lua`)
- `wiki/` - the docs (ignored clone of `vocino/vocui.wiki.git`, the single source; see Wiki below)
- `wiki/Home.md` - the wiki index: Principles, Craft, Coding, API pages, Toolchain, Gear, Log
- `wiki/Principles.md` - the charter: 25 principles, module contract, absorption/graduation
- `wiki/Craft.md` - the style paradigms: palette, type, panels, sounds, hover, anti-patterns
- `wiki/Coding.md` - how Lua is written here: file shape, naming, slash grammar, chat voice, sounds, settings mechanics
- `wiki/API-Verification.md` - sources of truth and the API verification procedure; `wiki/API-Ledger.md` is the verdict record
- `wiki/Debugging.md` - the !BugGrabber / BugSack loop
- `checks/` - mechanical checks; `bash checks/run-all.sh .` runs them all
- `tools/check-build.sh` - build currency: is the targeted Forever build still current?
- `.stylua.toml` - formatting (two-space indents, CRLF); `stylua --check core modules tests` is a commit gate
- `.github/workflows/test.yml` - CI: tests (Lua 5.1), luacheck, stylua, wowlua_ls, checks

## Conventions

- Place each module in its own folder under `modules/`.
- Place shared loader and services under `core/`.
- Keep Forever client metadata in a `.toc` file.
- Forever only: verify every API against the Forever build, Lua 5.1, no deprecated globals.
- Read `wiki/Craft.md` before any UI, settings, tooltip, sound, or visual work, and review against it before calling that work done. It carries the palette tokens, type levels, information order, sound table, and tooltip contract every module follows.

## Before coding

Run `bash tools/check-build.sh` before any code work, every session.
The Forever client changes often, and the API verdicts in
`wiki/API-Ledger.md` are only valid for the build they were checked
against. The script compares the build this repo targets (the toc's
interface, the ledger's recorded build) with the current Forever
build on Blizzard's UI source mirror. On CURRENT, proceed. On STALE,
do the bump pass in `wiki/API-Verification.md` ("Build currency") first: no
feature code is written against a moved build. When the script
cannot reach the mirror it says so; treat unverified as stale for
any API-touching work.

## References

The wiki is the source of truth for how to build: `wiki/` is an
ignored local clone of `vocino/vocui.wiki.git` (see Wiki below).
The repo holds code, tests, checks, and identity; Blizzard's own
sources remain the API authority. Read by task:

- Any UI, settings page, tooltip, sound, or visual work: `wiki/Craft.md`
  first, then review against it before calling the work done.
- Writing or changing Lua: `wiki/Coding.md` (shape, naming, slash,
  chat, sounds, settings mechanics) and the module contract in
  `wiki/Principles.md`.
- Any Blizzard API, event, or ID: `wiki/API-Verification.md` for the sources of
  truth and the verification procedure, `wiki/API-Ledger.md` for the
  recorded verdicts. Never code an API from memory or from a wiki
  signature. A name not in the ledger gets verified against the
  `forever` branch before it is used, added to `.luacheckrc` only
  after verification, and given its ledger row in the same wiki commit.
- A bug report or a Lua error: `wiki/Debugging.md`.
- Before any commit: `lua tests/run.lua`, `luacheck .`,
  `wowlua_ls check . --severity warning`,
  `stylua --check core modules tests`, and
  `bash checks/run-all.sh .` all pass.
  `bash checks/run-all.sh .` all pass.

## Wiki

The wiki (`wiki/`, an ignored local clone of `vocino/vocui.wiki.git`,
published at https://github.com/vocino/vocui/wiki) is the single
source for charter, craft, mechanics, API discipline, and module
decisions. It is agent-maintained and human-curated: the agent keeps
it true as the work changes it; the human resolves taste and
direction. `wiki/Home.md` is the index; `wiki/Log.md` is the
append-only record.

- Read the relevant wiki page before the work it governs
  (References), and file findings back when the work teaches
  something durable: update the page, link both ways, add a Log entry
  `## [date] op | title` (`ingest` for new sources or verdicts,
  `page` for new or moved pages, `fix` for corrections).
- New Blizzard names go through API-Verification and land as ledger
  rows in the same wiki commit as the code that uses them.
- New principles, module decisions, and toolchain changes land in the
  wiki in the same commit as the work, with the reason.
- Health-check the wiki when it smells stale: contradictions between
  pages, verdicts older than the targeted build, pages nothing links
  to, Log entries without page updates. Fix or file them; Log the
  pass.
## The one system

VocUI is one addon, not a bundle of addons. Modules feel like one
product: one install, one update, one entry point, one settings tree,
one palette and sound language (Principles #23 and #16 in the wiki). When a
choice trades cohesion for a module's convenience, cohesion wins.

## Module contract (short form)

The full contract is in `wiki/Principles.md`, "The module contract". The shape:

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

Follow these steps in order, every time (Principles #25 in the wiki). If a
step does not fit the module, extend this list in the same commit.

1. Create `modules/<job>/` with the descriptor file first, then the
   module's files. One job, statable in one sentence. Survey `core/`
   before writing logic: a need another module already met lives in
   a core service (Principles #11) — use it, and if the service does
   not exist yet, extract it and migrate the older module to it.
2. Add the module's files to `VocUI.toc`, after the core block, in
   alphabetical order by folder, descriptor first within the folder.
3. Give the module its settings page through the core settings
   service (see Settings tree). Declare its options as data.
4. Keep its state under `VocUIDB.modules.<job>` and nowhere else.
5. Add headless tests for its logic in `tests/`; run
   `lua tests/run.lua`, `luacheck .`, and
   `wowlua_ls check . --severity warning`, `stylua --check core modules tests`,
   and `bash checks/run-all.sh .` until all five pass.
6. Add the module to the Status section of README.md.
7. Commit as `feat:` and name the wiki principles the module
   serves in the commit body.
