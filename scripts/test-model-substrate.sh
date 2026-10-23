#!/usr/bin/env bash
# Gate for the model substrate (spec/model-substrate-v0.1.md, spec/model-substrate-targets-v0.md).
#
#   scripts/test-model-substrate.sh [--skip-build] [--no-clojure]
#
# 1. Lean tests (lake build zilLeanTests), which include the existing macro suites.
# 2. The macro and relation prefixes are owned by the substrate alone.
# 3. The worked example expands to its golden and its coherence profile gives the expected counts.
# 4. The Lean and the Clojure frontends expand every substrate input identically (needs Clojure).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

skip_build=0
no_clojure=0
for argument in "$@"; do
  case "$argument" in
    --skip-build) skip_build=1 ;;
    --no-clojure) no_clojure=1 ;;
    *) echo "usage: $0 [--skip-build] [--no-clojure]" >&2; exit 2 ;;
  esac
done

work="$(mktemp -d "${TMPDIR:-/tmp}/model-substrate.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

zil="$root/.lake/build/bin/zil"
example="examples/model-substrate/book-loan"
substrate="libsets/model-substrate"

if [[ "$skip_build" -eq 0 ]]; then
  if lake build zilLeanTests zil >"$work/build.log" 2>&1; then
    pass "lean tests (lake build zilLeanTests)"
  else
    tail -30 "$work/build.log" >&2
    fail "lean tests (lake build zilLeanTests)"
  fi
fi

if scripts/check-model-substrate-names.sh >"$work/names.log" 2>&1; then
  pass "$(cat "$work/names.log")"
else
  cat "$work/names.log" >&2
  fail "prefix ownership"
fi

if "$zil" expand "$example/model.zc" "$work/expanded.zc" --lib "$substrate" \
    && diff -u "$example/expected.expanded.zc" "$work/expanded.zc" >"$work/expanded.diff"; then
  pass "example expansion equals its golden"
else
  head -40 "$work/expanded.diff" >&2 || true
  fail "example expansion equals its golden"
fi

if "$zil" query-ci "$example/model.zc" loan_profile "$work/report.tsv" --lib "$substrate" \
    && awk -F'\t' '$1 == "status" && $2 == "pass" {found = 1} END {exit !found}' "$work/report.tsv"; then
  actual="$(awk -F'\t' '$1 == "query" {print $2 "\t" $3}' "$work/report.tsv")"
  if [[ "$actual" == "$(cat "$example/expected.query-counts.tsv")" ]]; then
    pass "example coherence profile gives the expected row counts"
  else
    diff <(cat "$example/expected.query-counts.tsv") <(echo "$actual") >&2 || true
    fail "example coherence profile gives the expected row counts"
  fi
else
  fail "example coherence profile runs"
fi

if [[ "$no_clojure" -eq 1 ]]; then
  echo "SKIP  frontend parity (--no-clojure)"
else
  compose="$work/compose"
  mkdir -p "$compose"
  cp "$substrate"/*.zc test/fixtures/model-substrate/t6_compose/lib/*.zc "$compose/"
  check_parity() {
    local model="$1"; shift
    if bin/zil macro-parity "$model" "$@" --output "$work/parity.edn" >/dev/null 2>"$work/parity.err" \
        && grep -q ':exact true' "$work/parity.edn"; then
      pass "frontend parity: $model"
    else
      cat "$work/parity.err" >&2 || true
      fail "frontend parity: $model"
    fi
  }
  check_parity examples/macro-extension/model.zc
  check_parity "$example/model.zc" --lib "$substrate"
  check_parity test/fixtures/model-substrate/t6_compose/model.zc --lib "$compose"
fi

if [[ "$failures" -ne 0 ]]; then
  echo "model substrate gate: $failures failure(s)" >&2
  exit 1
fi
echo "model substrate gate: all checks passed"
