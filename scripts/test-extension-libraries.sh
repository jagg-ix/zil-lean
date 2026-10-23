#!/usr/bin/env bash
# Gate for the extension libraries whose models are answered by the native engine alone (no Clojure).
#
#   scripts/test-extension-libraries.sh [--skip-build]
#
# 1. libsets/process-algebra: the checkout example gives the expected row count for every question.
# 2. libsets/discovery-api: the sample API gives the expected row count for every question.
# 3. libsets/proof-evidence: the theorem audit accepts a high-criticality theorem whose evidence comes from LEAN_PROOF,
#    and refuses the same theorem without it.
# The expansion, compile and typecheck of each library is the macro matrix (tools/macro_extension_matrix.sh).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

skip_build=0
[[ "${1:-}" == "--skip-build" ]] && skip_build=1

work="$(mktemp -d "${TMPDIR:-/tmp}/extension-libraries.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

if [[ "$skip_build" -eq 0 ]]; then
  lake build zil zilTheoremAudit >"$work/build.log" 2>&1 || { tail -20 "$work/build.log" >&2; exit 1; }
fi
zil="$root/.lake/build/bin/zil"
audit="$root/.lake/build/bin/zilTheoremAudit"

# check_counts NAME MODEL PROFILE LIBRARY EXPECTED
check_counts() {
  local name="$1" model="$2" profile="$3" library="$4" expected="$5"
  if "$zil" query-ci "$model" "$profile" "$work/$name.tsv" --lib "$library" >/dev/null 2>"$work/$name.err" \
      && awk -F'\t' '$1 == "status" && $2 == "pass" {found = 1} END {exit !found}' "$work/$name.tsv"; then
    if diff <(awk -F'\t' '$1 == "query" {print $2 "\t" $3}' "$work/$name.tsv") "$expected" >"$work/$name.diff"; then
      pass "$name: every question gives its expected row count"
    else
      cat "$work/$name.diff" >&2
      fail "$name: every question gives its expected row count"
    fi
  else
    cat "$work/$name.err" >&2 || true
    fail "$name: the profile runs and passes"
  fi
}

check_counts process-algebra examples/process-algebra-checks.zc checkout_profile libsets/process-algebra \
  examples/process-algebra-checks.expected-counts.tsv
check_counts discovery-api examples/discovery-api/sample-model.zc gcp_api_profile libsets/discovery-api \
  examples/discovery-api/expected-counts.tsv

model=examples/proof-evidence/contracts.zc
"$zil" expand "$model" "$work/with-evidence.zc" --lib libsets/proof-evidence >/dev/null 2>&1
grep -v '^USE LEAN_' "$model" >"$work/without-evidence.zc"
"$zil" expand "$work/without-evidence.zc" "$work/without-evidence.expanded.zc" --lib libsets/proof-evidence >/dev/null 2>&1
# The audit exits non-zero when it refuses, so read its report rather than its status.
audit_status() { "$audit" "$1" - 2>/dev/null | awk -F'\t' '$1 == "status" {print $2}' || true; }
if [[ "$(audit_status "$work/with-evidence.zc")" == pass ]]; then
  pass "proof-evidence: the audit accepts a theorem whose evidence is LEAN_PROOF"
else
  fail "proof-evidence: the audit accepts a theorem whose evidence is LEAN_PROOF"
fi
if [[ "$(audit_status "$work/without-evidence.expanded.zc")" == fail ]]; then
  pass "proof-evidence: the audit refuses the same theorem without evidence"
else
  fail "proof-evidence: the audit refuses the same theorem without evidence"
fi

if [[ "$failures" -ne 0 ]]; then
  echo "extension libraries gate: $failures failure(s)" >&2
  exit 1
fi
echo "extension libraries gate: all checks passed"
