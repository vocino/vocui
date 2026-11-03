#!/usr/bin/env bash
# voc-addons check: the addon compartment is wired (principle 10).
# Every toc declares the three compartment entry points, and the Lua
# sources define the globals they name, so a player who never learns
# the slash command still finds the addon on the minimap. Every toc
# Notes also teaches the short slash as (/xx), taken from the SLASH_*1
# definition in Lua, so the notes can never drift from the dispatcher.
#
# Usage: bash compartment.sh <repo-dir>
# Exit nonzero on violation. Fast, dependency-free.

set -u
dir="${1:?usage: compartment.sh <repo-dir>}"
fail=0
found=0

slash_line="$(grep -rhE --include='*.lua' --exclude-dir=.git --exclude-dir=tests --exclude-dir=.reference '^SLASH_[A-Z0-9_]*1[[:space:]]*=' "$dir" 2>/dev/null | head -1 || true)"
short="$(printf '%s' "$slash_line" | sed -nE "s|.*(['\"])(/[A-Za-z0-9]+)\1.*|\2|p")"
if [ -z "$short" ]; then
  echo "no SLASH_*1 short-slash definition in Lua (e.g. SLASH_VOCGEAR1 = \"/vg\")"
  fail=1
fi

for toc in "$dir"/*.toc; do
  [ -e "$toc" ] || continue
  found=1
  for key in AddonCompartmentFunc AddonCompartmentFuncOnEnter AddonCompartmentFuncOnLeave; do
    fn="$(grep -E "^## ${key}:" "$toc" | head -1 | sed -E "s/^## ${key}:[[:space:]]*//; s/[[:space:]]+$//")"
    if [ -z "$fn" ]; then
      echo "missing ## ${key}: in $toc"
      fail=1
      continue
    fi
    if ! grep -rqE "^function ${fn}\(" --include='*.lua' "$dir" --exclude-dir=.git --exclude-dir=tests --exclude-dir=.reference; then
      echo "$toc names ${key} ${fn}, but no Lua file defines it"
      fail=1
    fi
  done
  if [ -n "$short" ]; then
    notes="$(grep -E '^## Notes:' "$toc" | head -1)"
    case "$notes" in
      *"($short)"*) ;;
      *) echo "$toc Notes does not teach the short slash ($short)"; fail=1 ;;
    esac
  fi
done

if [ "$found" -eq 0 ]; then
  echo "no tocs found in $dir"
  fail=1
fi
if [ "$fail" -eq 1 ]; then
  echo "FAIL: wire the addon compartment (FAMILY.md \"Addon compartment\")."
  exit 1
fi
echo "OK: addon compartment wired."
