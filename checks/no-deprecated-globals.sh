#!/usr/bin/env bash
# voc-addons check: no deprecated globals (FAMILY.md "Sources of truth";
# the skill's principle 11). Fails when a Lua file calls, or .luacheckrc
# allows, a bare global that Blizzard moved into a C_* namespace or
# still ships only as a Blizzard_Deprecated shim. The list and the
# evidence behind it: checks/deprecated-globals.txt.
#
# Usage: bash no-deprecated-globals.sh <repo-dir>
# Exit nonzero on violation. Comments are stripped before matching, so a
# note that says "GetItemInfo is C_Item.GetItemInfo now" is fine.

set -u
dir="${1:?usage: no-deprecated-globals.sh <repo-dir>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
list="$here/deprecated-globals.txt"
fail=0

names="$(grep -vE '^\s*(#|$)' "$list" | sed -E 's/[[:space:]]+$//')"
alternation="$(printf '%s\n' "$names" | paste -sd '|' -)"

while IFS= read -r f; do
  # Bare call: the name, not preceded by `.` or `:` (a C_* member is fine),
  # followed by `(`. Line comments are stripped first.
  hits="$(sed -E 's/--.*$//' "$f" | grep -nE "(^|[^A-Za-z0-9_.:])(${alternation})[[:space:]]*\(" || true)"
  if [ -n "$hits" ]; then
    echo "deprecated global called in $f:"
    echo "$hits" | head -5
    fail=1
  fi
done < <(find "$dir" -name '*.lua' -not -path '*/.git/*' -not -path '*/tests/*' -not -path '*/.reference/*')

rc="$dir/.luacheckrc"
if [ -f "$rc" ]; then
  hits="$(sed -E 's/--.*$//' "$rc" | grep -nE "\"(${alternation})\"" || true)"
  if [ -n "$hits" ]; then
    echo "deprecated global allowed in $rc (a stale name cannot ship by accident only if lint rejects it):"
    echo "$hits" | head -5
    fail=1
  fi
fi

if [ "$fail" -eq 1 ]; then
  echo "FAIL: read the C_* namespace instead; see checks/deprecated-globals.txt."
  exit 1
fi
echo "OK: no deprecated globals."
