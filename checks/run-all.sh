#!/usr/bin/env bash
# vocui: run every check against a repo. CI calls this once, so a
# new check lands here and nowhere else.
#
# Usage: bash checks/run-all.sh <repo-dir>
# Exit nonzero when any check fails; every check still runs, so one
# pass reports everything.

set -u
dir="${1:?usage: run-all.sh <repo-dir>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
ran=0

for check in "$here"/*.sh; do
  name="$(basename "$check")"
  case "$name" in
    run-all.sh|self-test.sh) continue ;;
  esac
  ran=$((ran + 1))
  echo "== $name"
  if ! bash "$check" "$dir"; then
    fail=1
  fi
done

if [ "$ran" -eq 0 ]; then
  echo "no checks found beside $0"
  exit 1
fi
if [ "$fail" -eq 1 ]; then
  echo "FAIL: $dir does not pass every vocui check."
  exit 1
fi
echo "OK: $dir passes all $ran checks."
