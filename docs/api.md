# API verification

How VocUI knows what the Forever client's API actually is, instead of
guessing. Nothing in this package is coded from memory, from a wiki
signature, or from what a function used to take on another client.
Every Blizzard name the code relies on is verified against Blizzard's
own sources for the build in `## Interface:` (16001) before it ships,
and the verdict is recorded in `docs/api-ledger.md`.

## Build currency: check before coding

The Forever client is new and changes often, so a verdict ages with
the build it was checked against. Before any code work in a session,
run:

```
bash tools/check-build.sh
```

The script reads the latest Forever build from the head commit of
the mirror's `forever` branch (those commits are stamped
"<version> (<build>)"), derives the interface number, and compares
it with `VocUI.toc` and with the build recorded at the top of
`docs/api-ledger.md`. It answers CURRENT or STALE; it never guesses,
and when it cannot reach the mirror it says so and fails.

On STALE, no feature code is written until the bump pass is done:

1. Fetch the mirror (the script already did) and diff the generated
   docs between the old build and the new one for every namespace
   the ledger relies on.
2. Re-verify every ledger row against the new build; update verdicts
   that moved, and fix any code a moved verdict breaks.
3. Bump `## Interface:` in `VocUI.toc` and the build recorded in the
   ledger header, in one commit whose body names the old and new
   builds. Then code work resumes.

## Sources of truth, in order

1. **Blizzard's API documentation for the build.** In the client,
   `/api` opens it (the `Blizzard_APIDocumentation` addon). Outside
   the client, the same generated files are mirrored at
   https://github.com/Gethe/wow-ui-source on the `forever` branch,
   under `Interface/AddOns/Blizzard_APIDocumentationGenerated/`.
   Function names, namespaces, argument and return lists, and events
   come from here and nowhere else.
2. **Blizzard's UI source for the build**, same mirror, same branch:
   how Blizzard itself calls the API, the templates and mixins the
   package builds on (Settings, object pools, tooltips), and the
   `Blizzard_Deprecated*` folders for what is leaving and what
   replaces it.
3. **The Lua 5.1 reference manual** (https://www.lua.org/manual/5.1/).
   The client runs Lua 5.1 in a sandbox: no `io`, `os`, `require`, or
   `loadfile`, plus Blizzard additions such as `strtrim`, `wipe`, and
   `tContains`. Nothing from Lua 5.2 or later exists in the client.
4. **https://warcraft.wiki.gg**, for prose and examples only, and only
   after checking the page's patch note against the build. A signature
   there is a lead to confirm in source 1, never the source.
5. **Blizzard's own data for IDs.** The running client is the
   database: code treats IDs as keys and the client resolves them
   (`C_Spell.GetSpellInfo`, `C_Item.GetItemInfo`). Check an ID in game
   with `/dump C_Spell.GetSpellInfo(<id>)`; nil means a wrong ID.
   Outside the client, Blizzard's Game Data API covers items fully
   and spells partially; a spell missing there proves nothing, the
   client check wins. Database sites are leads, never the source.
   (Wowhead's Forever database is the Forever-flavored lead; it still
   does not outrank the client.)

Not used, ever: Wowpedia, WoWWiki, forum threads, blog tutorials, and
memory. Tell-tale staleness: bare globals that now live in a `C_*`
namespace (`GetItemInfo` is `C_Item.GetItemInfo`, `IsAddOnLoaded` is
`C_AddOns.IsAddOnLoaded`), `UIDropDownMenu` templates where native
Settings controls exist, and return lists that have since gained or
lost positions. The known moved names are listed in
`checks/deprecated-globals.txt`, and `checks/no-deprecated-globals.sh`
rejects them in code and in the `.luacheckrc` allowlist.

## The verification procedure

Before a name is added to `.luacheckrc` or called unguarded in code:

1. Keep a sparse local mirror of the Forever branch (gitignored,
   under `.reference/`):

   ```
   git clone --depth 1 --branch forever --filter=blob:none --sparse https://github.com/Gethe/wow-ui-source .reference/wow-ui-source
   git -C .reference/wow-ui-source sparse-checkout set Interface/AddOns/Blizzard_APIDocumentationGenerated Interface/AddOns/Blizzard_Settings_Shared Interface/AddOns/Blizzard_SharedXML
   ```

   Widen the sparse checkout when a lookup needs another folder.
2. Look the name up. For a documented function, search the generated
   docs for its definition:

   ```
   grep -rn 'Name = "GetContainerItemInfo"' .reference/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/
   ```

   For a Lua-defined function or a sound constant, search Blizzard's
   UI source:

   ```
   grep -rn "function Settings.OpenToCategory" .reference/wow-ui-source/Interface/AddOns/
   grep -rn "IG_MAINMENU_OPTION_CHECKBOX_ON" .reference/wow-ui-source/Interface/AddOns/Blizzard_SharedXML/
   ```
3. Record the verdict in `docs/api-ledger.md`, in the same commit
   that adds the name to `.luacheckrc`, and quote the verdict in the
   commit body. The verdict vocabulary:

   - `ok, documented`: listed in the generated docs under that
     namespace.
   - `ok, Lua: <file>`: defined in Blizzard's own UI code.
   - `used`: undocumented, but Blizzard's own code calls it; ship it
     presence-gated.
   - `bare`: a C-side global Blizzard's code still calls bare and
     undocumented; presence-gate it.
   - `GONE` or `unknown`: never ships unguarded. Find the replacement
     in sources 1 and 2, or presence-gate and `pcall` the call.

## How the rule holds without anyone watching

- `.luacheckrc` lists every WoW global the package reads, and lint
  fails on any other. A name enters the allowlist only after step 2
  above confirms it, under that namespace, in the Forever build.
- The ledger is the auditable record behind the allowlist. A row
  changes only after the code does; a new name gets its row in the
  same change that adds it to `.luacheckrc`.
- Third-party addon APIs are verified against that addon's current
  source, kept as a local checkout under `.reference/` (gitignored),
  with the finding written in `.reference/<addon>-analysis.md` or a
  code comment naming the version checked.
- Anything that cannot be verified is presence-gated, `pcall`-guarded,
  and covered by a stub test that pins the assumed shape (README
  principle 20).
- When `## Interface:` is bumped, the generated docs for the new
  build are diffed against the old before any code changes, and the
  ledger's rows are re-verified in the same pass. `tools/check-build.sh`
  is what notices the bump is needed (see "Build currency" above).
