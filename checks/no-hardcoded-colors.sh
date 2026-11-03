#!/usr/bin/env bash
# voc-addons check: no hardcoded colors (principle 2).
# Fails if Lua sources contain |cff hex literals, numeric CreateColor()
# calls, or numeric text colors (SetTextColor / SetVertexColor with a
# literal first argument) outside the addon's palette definition file.
# Chrome tints (backdrops, dividers, a skin's exact recipe) are not
# checked: they are a look's construction, not the semantic palette.
#
# Usage: bash no-hardcoded-colors.sh <repo-dir>
# The palette lives in exactly one file per addon: palette.lua (preferred)
# or a COLORS table defined once in main.lua. Everything else references it.

set -u
dir="${1:?usage: no-hardcoded-colors.sh <repo-dir>}"
fail=0

while IFS= read -r f; do
  base="$(basename "$f")"
  # The palette file itself may define colors.
  case "$base" in
    palette.lua|Palette.lua) continue ;;
  esac
  # |cffRRGGBB literals in strings.
  if grep -nE '\|cff[0-9a-fA-F]{6}' "$f" >/dev/null; then
    echo "hardcoded |cff color in $f:"
    grep -nE '\|cff[0-9a-fA-F]{6}' "$f" | head -5
    fail=1
  fi
  # CreateColor(r, g, b) with numeric literals.
  if grep -nE 'CreateColor\([0-9]' "$f" >/dev/null; then
    echo "numeric CreateColor in $f:"
    grep -nE 'CreateColor\([0-9]' "$f" | head -5
    fail=1
  fi
  # Text painted with a literal triple instead of a palette token.
  if grep -nE 'Set(Text|Vertex)Color\([0-9]' "$f" >/dev/null; then
    echo "numeric text color in $f:"
    grep -nE 'Set(Text|Vertex)Color\([0-9]' "$f" | head -5
    fail=1
  fi
done < <(find "$dir" -name '*.lua' -not -path '*/.git/*' -not -path '*/tests/*' -not -path '*/.reference/*')

if [ "$fail" -eq 1 ]; then
  echo "FAIL: move colors into the palette file and reference them by name."
  exit 1
fi
echo "OK: no hardcoded colors."
