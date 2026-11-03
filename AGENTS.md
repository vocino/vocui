# AGENTS.md

## Code Map

- `VocUI.toc` - Forever client metadata (Interface 16001)
- `core/` - loader, settings store, palette, sounds, chat, slash
- `modules/` - one folder per module, descriptor first (none yet)
- `tests/` - headless tests (`lua tests/run.lua`)

## Conventions

- Place each module in its own folder under `modules/`.
- Place shared loader and services under `core/`.
- Keep Forever client metadata in a `.toc` file.
- Forever only: verify every API against the Forever build, Lua 5.1, no deprecated globals.
