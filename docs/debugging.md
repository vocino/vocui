# Debugging

The coding agent is blind in game: only Lua errors surface on their
own. This package debugs with the community's tools, not its own.

- **!BugGrabber** captures every Lua error with stack and context.
  **BugSack** is the in-game viewer (`/bugsack`). Both are installed
  on the dev machine.
- Errors persist to
  `WTF/Account/<account>/SavedVariables/!BugGrabber.lua` on `/reload`
  or logout. The loop: the player reproduces the problem, runs
  `/reload`, and the agent reads that file directly. No paste step on
  a machine that also runs WoW.
- Parse with regex on `["message"]` fields, never brace-counting: the
  `["locals"]` dump nests braces and breaks structural parsers.
- Stale records survive a fix. Confirm the player reproduced the
  issue again before trusting a record.
- A module that errors in init is caught by the core's `pcall` and
  reported in chat with its name; the rest of the package keeps
  running (README principle 12). The BugGrabber record is still the
  source for the stack.
