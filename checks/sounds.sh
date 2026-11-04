#!/usr/bin/env bash
# voc-addons check: the family sound helper is defined (FAMILY.md "Sounds").
# ns.SOUNDS carries at least the on/off/open/close keys, and ns.play
# plays them. Extra keys and extra helpers are fine.
#
# Usage: bash sounds.sh <repo-dir>
# Exit nonzero on violation. Fast, dependency-free.

set -u
dir="${1:?usage: sounds.sh <repo-dir>}"
fail=0

file="$(grep -rlE --include='*.lua' --exclude-dir=.git --exclude-dir=tests --exclude-dir=.reference --exclude-dir=.release 'ns\.SOUNDS[[:space:]]*=[[:space:]]*\{' "$dir" 2>/dev/null | head -1 || true)"
if [ -z "$file" ]; then
  echo "no ns.SOUNDS table: every addon confirms toggles and windows with sound"
  echo "FAIL: add ns.SOUNDS and ns.play (FAMILY.md \"Sounds\")."
  exit 1
fi
body="$(sed -n '/ns\.SOUNDS[[:space:]]*=[[:space:]]*{/,/^[[:space:]]*}/p' "$file")"
for key in on off open close; do
  if ! printf '%s\n' "$body" | grep -qE "(^|[^A-Za-z0-9_])$key[[:space:]]*="; then
    echo "$file: ns.SOUNDS is missing the \"$key\" key"
    fail=1
  fi
done

if ! grep -rqE --include='*.lua' --exclude-dir=.git --exclude-dir=tests --exclude-dir=.reference --exclude-dir=.release '(function ns\.play\(|ns\.play[[:space:]]*=[[:space:]]*function)' "$dir"; then
  echo "no ns.play function: every addon plays its sounds through one helper"
  fail=1
fi

# Nothing plays the sound API directly: every play goes through the
# helper above, so a missing API stays silent instead of erroring.
while IFS= read -r f; do
  if [ "$f" = "$file" ]; then
    continue
  fi
  hits="$(sed -E 's/--.*$//' "$f" | grep -nE 'PlaySound[[:space:]]*(\(|,)' || true)"
  if [ -n "$hits" ]; then
    echo "direct PlaySound call in $f:"
    echo "$hits" | head -5
    echo "play it through ns.play/ns.playID in $file instead"
    fail=1
  fi
done < <(find "$dir" -name '*.lua' -not -path '*/.git/*' -not -path '*/tests/*' -not -path '*/.reference/*' -not -path '*/.release/*')

if [ "$fail" -eq 1 ]; then
  echo "FAIL: add ns.SOUNDS and ns.play (FAMILY.md \"Sounds\")."
  exit 1
fi
echo "OK: family sound helper defined."
