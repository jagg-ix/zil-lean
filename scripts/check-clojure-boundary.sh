#!/usr/bin/env bash
# Keep the Clojure dependency of the scripts shrinking.
#
#   scripts/check-clojure-boundary.sh                  fail if any line that calls Clojure is new or changed
#   scripts/check-clojure-boundary.sh --print          print the current inventory
#   scripts/check-clojure-boundary.sh --update         rewrite the baseline, only when nothing was added
#
# The native Lean tools (bin/zil compile, expand, query-ci, conformance, ...) need no Clojure. What still calls it is
# listed in spec/clojure-boundary-baseline.tsv, one line per call: the file, a fingerprint of the normalized line, and
# the start of the line for a reader. Removing a call is always allowed. Adding or changing one is refused: write the
# native replacement instead of growing the list.
#
# The inventory covers the commands and scripts around the engine (bin, scripts, tools, Makefile, the container files
# and workflows). The legacy engine's own sources (src/, test/) are governed by legacy-retirement.edn.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
baseline="spec/clojure-boundary-baseline.tsv"
pattern='\bclojure\b|\bclj\b|-M:[a-z]|zil-legacy|ZIL_LEGACY_MODE|deps\.edn'

mode=check
case "${1:-}" in
  "") ;;
  --print) mode=print ;;
  --update) mode=update ;;
  *) echo "usage: $0 [--print|--update]" >&2; exit 2 ;;
esac

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-16; }

inventory() {
  git ls-files bin scripts tools Makefile Dockerfile.test compose.test.yml .github 2>/dev/null \
    | { grep -v -e '^scripts/check-clojure-boundary.sh$' -e '^tools/tests/' || true; } \
    | while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        { grep -n -i -E "$pattern" "$file" 2>/dev/null || true; } | while IFS= read -r hit; do
          number="${hit%%:*}"
          text="$(printf '%s' "${hit#*:}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
          # A comment is not a call, and neither is a mention of this check itself.
          case "$text" in "#"*|"//"*|*clojure-boundary*) continue ;; esac
          printf '%s\t%s\t%s\n' "$file" "$(printf '%s' "$text" | sha)" "${text:0:70}"
        done
      done | LC_ALL=C sort
}

current="$(mktemp "${TMPDIR:-/tmp}/clojure-boundary.XXXXXX")"
trap 'rm -f "$current"' EXIT
inventory >"$current"

if [[ "$mode" == print ]]; then
  cat "$current"
  exit 0
fi

keys() { cut -f1,2 "$1" | LC_ALL=C sort; }

if [[ "$mode" == update ]]; then
  if [[ -f "$baseline" ]]; then
    added="$(LC_ALL=C comm -23 <(keys "$current") <(keys "$baseline"))"
    if [[ -n "$added" ]]; then
      echo "refusing to update: these calls are not in the baseline" >&2
      printf '%s\n' "$added" | cut -f1 | sort | uniq -c >&2
      exit 1
    fi
  fi
  cp "$current" "$baseline"
  echo "baseline now lists $(wc -l <"$baseline" | tr -d ' ') call(s)"
  exit 0
fi

if [[ ! -f "$baseline" ]]; then
  echo "no baseline at $baseline (create it once with: $0 --update)" >&2
  exit 2
fi

added="$(LC_ALL=C comm -23 <(keys "$current") <(keys "$baseline"))"
removed="$(LC_ALL=C comm -13 <(keys "$current") <(keys "$baseline"))"
if [[ -n "$added" ]]; then
  echo "new or changed Clojure calls (write the native replacement instead):" >&2
  while IFS=$'\t' read -r file fingerprint; do
    awk -F'\t' -v f="$file" -v h="$fingerprint" '$1 == f && $2 == h {print "  " f ": " $3}' "$current" | head -1 >&2
  done <<<"$added"
  exit 1
fi
count="$(wc -l <"$current" | tr -d ' ')"
gone="$(printf '%s' "$removed" | grep -c . || true)"
echo "Clojure boundary: no new calls; $count remain (baseline $(wc -l <"$baseline" | tr -d ' '), $gone removed since)"
