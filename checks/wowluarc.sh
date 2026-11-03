#!/usr/bin/env bash
# vocui check: the repo carries a $schema-validated .wowluarc.json
# pinning the forever flavor, so wowlua-ls (editor and CI)
# type-checks against the right APIs and wrong-flavor use fails loudly.
# Syntax validity is enforced by wowlua_ls itself when it parses the
# config; this check holds the conventions a parser cannot.
#
# Run: bash checks/wowluarc.sh <repo-dir>
# Exit nonzero on violation. Fast, dependency-free.
set -u

dir="${1:?usage: wowluarc.sh <repo-dir>}"
fail=0

check_config() { # <path>
  local cfg="$1" content
  if [ ! -f "$cfg" ]; then
    echo "missing wowlua-ls config: $cfg"
    fail=1
    return
  fi
  content="$(cat "$cfg")"
  case "$content" in
    *'"$schema"'*) ;;
    *) echo "$cfg: no \$schema key (see the wowlua-ls configuration reference)"; fail=1 ;;
  esac
  case "$content" in
    *'"flavors"'*) ;;
    *) echo "$cfg: no flavors pin"; fail=1 ;;
  esac
  case "$content" in
    *'"forever"'*) ;;
    *) echo "$cfg: flavors pin is missing forever"; fail=1 ;;
  esac
}

check_config "$dir/.wowluarc.json"
check_config "$dir/tests/.wowluarc.json"

if [ "$fail" -eq 0 ]; then
  echo "OK: wowlua-ls config pinned."
fi
exit "$fail"
