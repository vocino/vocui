#!/usr/bin/env bash
# VocUI changelog: deterministic release notes from commit subjects.
# One formatter feeds both surfaces (the GitHub release notes and the
# Discord embed), so the two always carry the same sections and
# bullets. No fetching, no network, no rewriting: subjects in,
# bullets out.
#
# Usage: bash tools/changelog.sh <prev-rev> <new-rev> <version> [modules-dir] [notes-file] [desc-file]
#   prev-rev/new-rev bound the counted commits (exclusive/inclusive,
#   git log order: newest first). version is informational only.
#   modules-dir names the module folders behind bold bullets.
#   notes-file gets the full notes; desc-file gets the embed text,
#   truncated to whole bullets with a more-line when over budget.
# Either file may be /dev/null. Empty outputs when nothing is
# player-facing; the caller skips both surfaces then.
set -u

prev="${1:?usage: changelog.sh <prev-rev> <new-rev> <version>}"
new="${2:?usage: changelog.sh <prev-rev> <new-rev> <version>}"
version="${3:?usage: changelog.sh <prev-rev> <new-rev> <version>}"
moddir="${4:-modules}"
notes="${5:-/dev/null}"
desc="${6:-/dev/null}"

# Embed descriptions carry 4096 characters; the budget stays well
# under it so encoding and the more-line never overflow.
budget=3900

new_bullets=()
fixed_bullets=()

subject_re='^(feat|fix)(\([^)]*\))?([!])?:[[:space:]]*(.+)$'
while IFS= read -r subject; do
  if [[ "$subject" =~ $subject_re ]]; then
    type="${BASH_REMATCH[1]}"
    text="${BASH_REMATCH[4]}"
  else
    continue # chore, docs, refactor, style, test, ci, merges: never listed
  fi
  text="${text%"${text##*[![:space:]]}"}" # trailing whitespace
  text="${text%.}" # no trailing period
  text="${text%"${text##*[![:space:]]}"}"
  if [ -z "$text" ]; then
    continue
  fi
  first="${text%% *}"
  rest=""
  if [[ "$text" == *" "* ]]; then
    rest="${text#* }"
  fi
  lower="$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]')"
  if [ -n "$rest" ] && [ -d "$moddir/$lower" ]; then
    cap="$(printf '%s' "${first:0:1}" | tr '[:lower:]' '[:upper:]')${first:1}"
    bullet="- **$cap**: $rest"
  else
    cap="$(printf '%s' "${text:0:1}" | tr '[:lower:]' '[:upper:]')${text:1}"
    bullet="- $cap"
  fi
  if [ "$type" = "feat" ]; then
    new_bullets+=("$bullet")
  else
    fixed_bullets+=("$bullet")
  fi
done < <(git log --format=%s "$prev..$new" 2>/dev/null)

{
  if [ "${#new_bullets[@]}" -gt 0 ]; then
    printf 'New\n\n'
    printf '%s\n' "${new_bullets[@]}"
  fi
  if [ "${#new_bullets[@]}" -gt 0 ] && [ "${#fixed_bullets[@]}" -gt 0 ]; then
    printf '\n'
  fi
  if [ "${#fixed_bullets[@]}" -gt 0 ]; then
    printf 'Fixed\n\n'
    printf '%s\n' "${fixed_bullets[@]}"
  fi
} >"$notes"

# Embed text: the same sections and bullets, truncated to whole
# bullets when over budget, ending with the more-line. The post is a
# prefix of the full notes: lines are taken in order and the take
# stops at the first line that no longer fits, so the shown items are
# always the first items. Sizes are bytes, which never exceed
# characters, so the budget holds under any locale.
{
  lines=()
  if [ "${#new_bullets[@]}" -gt 0 ]; then
    lines+=("New" "")
    lines+=("${new_bullets[@]}")
  fi
  if [ "${#new_bullets[@]}" -gt 0 ] && [ "${#fixed_bullets[@]}" -gt 0 ]; then
    lines+=("")
  fi
  if [ "${#fixed_bullets[@]}" -gt 0 ]; then
    lines+=("Fixed" "")
    lines+=("${fixed_bullets[@]}")
  fi
  total_bullets=$((${#new_bullets[@]} + ${#fixed_bullets[@]}))
  if [ "$total_bullets" -eq 0 ]; then
    : # empty in, empty out: the caller posts nothing
  else
    # Longest possible more-line, reserved before measuring.
    reserve=32
    size=0
    take=0
    for line in "${lines[@]}"; do
      nbytes=$(printf '%s\n' "$line" | wc -c)
      if [ $((size + nbytes + reserve)) -le "$budget" ]; then
        size=$((size + nbytes))
        take=$((take + 1))
      else
        break
      fi
    done
    # Never end on a header or a blank line: back the take off to
    # the last bullet.
    while [ "$take" -gt 0 ]; do
      last="${lines[$((take - 1))]}"
      if [ -n "$last" ] && [ "$last" != "New" ] && [ "$last" != "Fixed" ]; then
        break
      fi
      take=$((take - 1))
    done
    for ((i = 0; i < take; i++)); do
      printf '%s\n' "${lines[$i]}"
    done
    shown=0
    for ((i = 0; i < take; i++)); do
      case "${lines[$i]}" in
        "- "*) shown=$((shown + 1)) ;;
      esac
    done
    omitted=$((total_bullets - shown))
    if [ "$omitted" -gt 0 ]; then
      printf '+%d more in the full release\n' "$omitted"
    fi
  fi
} >"$desc"

echo "changelog $version: ${#new_bullets[@]} new, ${#fixed_bullets[@]} fixed"
