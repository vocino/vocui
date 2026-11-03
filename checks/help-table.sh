#!/usr/bin/env bash
# voc-addons check: the slash help is on the family grammar (FAMILY.md
# "Slash grammar"). Exactly one `ns.HELP = { ... }` table of string
# lines, every line starting with the same short slash, `config` second
# to last, `help` last and naming the long form ("works too").
#
# Usage: bash help-table.sh <repo-dir>
# Exit nonzero on violation. Fast, dependency-free.

set -u
dir="${1:?usage: help-table.sh <repo-dir>}"
fail=0

files="$(grep -lE '^\s*ns\.HELP\s*=\s*\{' $(find "$dir" -name '*.lua' -not -path '*/.git/*' -not -path '*/tests/*' -not -path '*/.reference/*') 2>/dev/null || true)"
count="$(printf '%s' "$files" | grep -c . || true)"
if [ "$count" -eq 0 ]; then
  echo "no ns.HELP table: every addon lists its subcommands under /<short> help"
  echo "FAIL: add ns.HELP (FAMILY.md \"Slash grammar\")."
  exit 1
fi
if [ "$count" -gt 1 ]; then
  echo "more than one ns.HELP table:"; printf '%s\n' "$files"
  fail=1
fi

file="$(printf '%s\n' "$files" | head -1)"
# The table body: from the `ns.HELP = {` line to the first line that is
# just `}`; comments stripped; one quoted string per entry.
lines="$(sed -n '/^\s*ns\.HELP\s*=\s*{/,/^\s*}/p' "$file" | sed -E 's/--.*$//' | grep -oE '"[^"]*"' | sed -E 's/^"//; s/"$//')"
n="$(printf '%s\n' "$lines" | grep -c . || true)"
if [ "$n" -lt 2 ]; then
  echo "$file: ns.HELP needs at least config and help lines (found $n)"
  echo "FAIL: help lists every subcommand, config second to last, help last."
  exit 1
fi

short="$(printf '%s\n' "$lines" | head -1 | grep -oE '^/[a-z]+' || true)"
if [ -z "$short" ]; then
  echo "$file: help lines start with the short slash, e.g. \"/vg scan   check bags now\""
  fail=1
fi
while IFS= read -r line; do
  case "$line" in
    "$short "*|"$short") ;;
    *) echo "$file: help line does not start with $short: \"$line\""; fail=1 ;;
  esac
done <<EOF
$lines
EOF

last="$(printf '%s\n' "$lines" | tail -1)"
second="$(printf '%s\n' "$lines" | tail -2 | head -1)"
case "$second" in
  "$short config"*) ;;
  *) echo "$file: second to last help line is config, not \"$second\""; fail=1 ;;
esac
case "$last" in
  "$short help"*"works too"*) ;;
  *) echo "$file: last help line is help and names the long form (\"... (/vocname works too)\"), not \"$last\""; fail=1 ;;
esac

if [ "$fail" -eq 1 ]; then
  echo "FAIL: put the help table on the family grammar (FAMILY.md \"Slash grammar\")."
  exit 1
fi
echo "OK: help table on the family grammar."
