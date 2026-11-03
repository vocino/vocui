#!/usr/bin/env bash
# vocui: is the Forever build this repo targets still the current one?
#
# The Forever client changes often, and every API verdict in
# wiki/API-Ledger.md is only as good as the build it was checked
# against. Run this before starting code work (AGENTS.md, "Before
# coding"). It reads the latest Forever build from the head commit of
# the `forever` branch of Blizzard's UI source mirror (Gethe titles
# those commits "<version> (<build>)", e.g. "1.60.1 (70755)"), derives
# the interface number, and compares it with VocUI.toc and with the
# build recorded in wiki/API-Ledger.md.
#
# Usage: bash tools/check-build.sh
# Exit 0: current. Exit 1: stale or unverifiable; the output says what
# to do. The mirror lives in .reference/ (gitignored); the first run
# clones it, later runs fetch.

set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mirror="$root/.reference/wow-ui-source"
repo="https://github.com/Gethe/wow-ui-source"

if [ -d "$mirror/.git" ]; then
  git -C "$mirror" fetch --quiet --depth 1 origin forever || {
    echo "could not fetch the forever branch; build currency unverified"
    exit 1
  }
  head_ref="FETCH_HEAD"
else
  mkdir -p "$root/.reference"
  git clone --quiet --depth 1 --branch forever --filter=blob:none --no-checkout "$repo" "$mirror" || {
    echo "could not clone the mirror; build currency unverified"
    exit 1
  }
  head_ref="HEAD"
fi

subject="$(git -C "$mirror" log -1 --format=%s "$head_ref")"
version="$(printf '%s' "$subject" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)"
build="$(printf '%s' "$subject" | grep -oE '\([0-9]+\)' | tr -d '()' || true)"
if [ -z "$version" ] || [ -z "$build" ]; then
  echo "mirror head commit is not a build stamp: '$subject'"
  echo "build currency unverified; check the forever branch by hand"
  exit 1
fi

major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
interface=$((major * 10000 + minor * 100 + patch))

toc_interface="$(grep -E '^## Interface:' "$root/VocUI.toc" | grep -oE '[0-9]+' | head -1)"
ledger_build="$(grep -oE '\([0-9]{5}\)' "$root/wiki/API-Ledger.md" | head -1 | tr -d '()')"

echo "forever branch: $version ($build), interface $interface"
echo "VocUI.toc:      interface ${toc_interface:-none}"
echo "api-ledger.md:  build ${ledger_build:-unrecorded}"

fail=0
if [ "$toc_interface" != "$interface" ]; then
  echo "STALE: the toc targets interface ${toc_interface:-none}, the client is $interface"
  fail=1
fi
if [ "$ledger_build" != "$build" ]; then
  echo "STALE: the ledger was verified against build ${ledger_build:-unrecorded}, the client is $build"
  fail=1
fi
if [ "$fail" -eq 1 ]; then
  echo "run the interface-bump pass in wiki/API-Verification.md before writing code:"
  echo "diff the generated docs, re-verify the ledger rows, bump the toc and the ledger header, one commit"
  exit 1
fi
echo "CURRENT: this repo targets the live Forever build"
