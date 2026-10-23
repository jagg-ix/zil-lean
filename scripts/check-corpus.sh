#!/usr/bin/env bash
# Check that every ZIL source in the repository still compiles, or still fails, as recorded.
#
#   scripts/check-corpus.sh [--update] [--skip-build] [--jobs N]
#
# Every .zc file under lib/, libsets/ and examples/ is compiled alone by the native compiler. spec/corpus-status.tsv
# records, per file, whether that is accepted or rejected, and for a rejected file the first line of the error (a macro
# file or a model that needs its library is rejected alone; the macro matrix covers those with their libraries).
# The check fails when a file changes status. --update rewrites the record: review the diff before committing it.
# Only the status is compared, so a changed error message is not a failure.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
record="spec/corpus-status.tsv"
update=0
skip_build=0
jobs=4
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) update=1 ;;
    --skip-build) skip_build=1 ;;
    --jobs) shift; jobs="${1:?--jobs needs a number}" ;;
    *) echo "usage: $0 [--update] [--skip-build] [--jobs N]" >&2; exit 2 ;;
  esac
  shift
done

work="$(mktemp -d "${TMPDIR:-/tmp}/zil-corpus.XXXXXX")"
trap 'rm -rf "$work"' EXIT
if [[ "$skip_build" -eq 0 ]]; then
  lake build zil >"$work/build.log" 2>&1 || { tail -20 "$work/build.log" >&2; exit 1; }
fi
zil="$root/.lake/build/bin/zil"

one() {
  local file="$1" out="$2" err
  if err="$(timeout 180 "$zil" compile "$file" /dev/null 2>&1 >/dev/null)"; then
    printf '%s\taccepted\t\n' "$file" >"$out"
  else
    printf '%s\trejected\t%s\n' "$file" "$(printf '%s' "$err" | grep -v -e '^warning' -e '^$' | head -1 | cut -c1-110 | tr '\t' ' ')" >"$out"
  fi
}
export -f one
export zil

mkdir -p "$work/out"
git ls-files 'lib/*.zc' 'libsets/*.zc' 'examples/*.zc' | LC_ALL=C sort >"$work/files.txt"
n=0
while IFS= read -r file; do
  n=$((n + 1))
  printf '%s\0%s\0' "$file" "$work/out/$(printf '%05d' "$n")"
done <"$work/files.txt" | xargs -0 -n 2 -P "$jobs" bash -c 'one "$0" "$1"'
cat "$work/out"/* | LC_ALL=C sort >"$work/current.tsv"

if [[ "$update" -eq 1 ]]; then
  cp "$work/current.tsv" "$record"
  echo "corpus record now lists $(wc -l <"$record" | tr -d ' ') file(s): $(awk -F'\t' '$2 == "accepted"' "$record" | wc -l | tr -d ' ') accepted"
  exit 0
fi
[[ -f "$record" ]] || { echo "no record at $record (create it with: $0 --update)" >&2; exit 2; }

if diff <(cut -f1,2 "$record") <(cut -f1,2 "$work/current.tsv") >"$work/diff.txt"; then
  echo "corpus: $(wc -l <"$record" | tr -d ' ') file(s), $(awk -F'\t' '$2 == "accepted"' "$record" | wc -l | tr -d ' ') accepted, none changed status"
else
  echo "corpus: these files changed status (< recorded, > now):" >&2
  grep '^[<>]' "$work/diff.txt" >&2
  exit 1
fi
