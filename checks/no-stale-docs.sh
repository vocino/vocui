#!/usr/bin/env bash
# vocui check: documentation lives in the wiki, not the repo.
# Fails if Lua sources, docs, or repo metadata point at the old homes
# (`docs/`, `CRAFT.md`, "README principle"): the wiki (`wiki/`, ignored
# clone of vocino/vocui.wiki.git) is the single source, and the repo
# only points at it. Legitimate mentions name the wiki path instead
# (e.g. `wiki/Principles.md`, `wiki/Craft.md`).

set -u
dir="${1:?usage: no-stale-docs.sh <repo-dir>}"
fail=0

while IFS= read -r f; do
  if grep -nE 'CRAFT\.md|(^|[^_a-zA-Z/])docs/|README principle' "$f" >/dev/null; then
    echo "stale docs pointer in $f:"
    grep -nE 'CRAFT\.md|(^|[^_a-zA-Z/])docs/|README principle' "$f" | head -5
    fail=1
  fi
done < <(find "$dir" -type f \( -name '*.lua' -o -name '*.md' -o -name '*.toc' -o -name '*.sh' -o -name '*.yml' -o -name '*.json' \) -not -path '*/.git/*' -not -path '*/wiki/*' -not -path '*/.reference/*' -not -name 'no-stale-docs.sh')
if [ "$fail" -eq 1 ]; then
  echo "FAIL: repo points outside the wiki; repoint to wiki/ pages."
  exit 1
fi
echo "OK: all doc pointers go to the wiki."
