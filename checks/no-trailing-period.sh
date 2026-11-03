#!/usr/bin/env bash
# voc-addons check: chat lines have no trailing period (FAMILY.md "Chat
# voice": a chat line is a log entry, not a sentence). Fails when a
# string literal handed to ns.say ends in a period, whether it closes
# the call, is concatenated onward, or sits in an and/or branch.
#
# Usage: bash no-trailing-period.sh <repo-dir>
# Exit nonzero on violation. Comments are stripped before matching.

set -u
dir="${1:?usage: no-trailing-period.sh <repo-dir>}"
fail=0
pattern='ns\.say\(.*[^.]\."[[:space:]]*(\)|\.\.|or |and )'

while IFS= read -r f; do
  hits="$(sed -E 's/--.*$//' "$f" | grep -nE "$pattern" || true)"
  if [ -n "$hits" ]; then
    echo "chat line ends in a period in $f:"
    echo "$hits" | head -5
    fail=1
  fi
done < <(find "$dir" -name '*.lua' -not -path '*/.git/*' -not -path '*/tests/*' -not -path '*/.reference/*')

if [ "$fail" -eq 1 ]; then
  echo "FAIL: drop the trailing period; a chat line is a log entry (FAMILY.md \"Chat voice\")."
  exit 1
fi
echo "OK: no trailing periods in chat lines."
