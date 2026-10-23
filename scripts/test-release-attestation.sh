#!/usr/bin/env bash
# Gate for release attestation (Lean only).
#
#   scripts/test-release-attestation.sh [--skip-build]
#
# The example release in examples/release-evidence, and six variants of it, are attested; each attestation must equal,
# byte for byte, the one the earlier Clojure implementation wrote (test/fixtures/release-attestation/), and an escaping
# path or a wrong evidence format must be refused with exit status 2.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "${1:-}" == "--skip-build" ]] || lake build zilRelease >/dev/null
release="$root/.lake/build/bin/zilRelease"
work="$(mktemp -d "${TMPDIR:-/tmp}/release-attestation.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

variant() { rm -rf "$work/$1"; cp -R examples/release-evidence "$work/$1"; }
edit_json() { python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); exec(sys.argv[2]); json.dump(d,open(p,"w"),ensure_ascii=False)' "$1" "$2"; }

variant ok
variant artifact-changed; echo tamper >>"$work/artifact-changed/workflow/Demo.lean"
variant artifact-missing; rm "$work/artifact-missing/workflow/Demo.lean"
variant lock-drift; edit_json "$work/lock-drift/evidence/locks.json" 'd["changed"]=1'
variant denied; sed -i.bak 's/allow/deny/' "$work/denied/evidence/authorization.txt"
variant missing-target; edit_json "$work/missing-target/release-request.json" 'd["evidence"]["formalization"]["required_targets"]=["foundations","nonexistent"]'
variant unicode-slash; edit_json "$work/unicode-slash/release-request.json" 'd["release_id"]="release:démo/😀"'

expected_exit() { case "$1" in ok|unicode-slash) echo 0 ;; *) echo 1 ;; esac; }
for name in ok artifact-changed artifact-missing lock-drift denied missing-target unicode-slash; do
  set +e; "$release" attest "$work/$name/release-request.json" "$work/$name.out.json" >/dev/null 2>"$work/$name.err"; code=$?; set -e
  if [[ "$code" -eq "$(expected_exit "$name")" ]] && cmp -s "$work/$name.out.json" "test/fixtures/release-attestation/$name.json"; then
    pass "$name: the attestation equals the Clojure one byte for byte (exit $code)"
  else fail "$name: attestation differs or exit $code is wrong"; fi
done

variant escape; edit_json "$work/escape/release-request.json" 'd["artifacts"][0]["path"]="../outside.lean"; d["evidence"]["workflow"]["artifact"]="../outside.lean"'
set +e; "$release" attest "$work/escape/release-request.json" "$work/escape.out.json" >/dev/null 2>"$work/escape.err"; code=$?; set -e
if [[ "$code" -eq 2 && ! -f "$work/escape.out.json" ]] && grep -q 'escapes request directory' "$work/escape.err"; then pass "a path that leaves the request directory is refused"
else fail "a path that leaves the request directory is refused (exit $code)"; fi
variant bad-format; sed -i.bak 's/zil.workflow-verification.v0.1/zil.other/' "$work/bad-format/evidence/workflow.json"
set +e; "$release" attest "$work/bad-format/release-request.json" "$work/bad-format.out.json" >/dev/null 2>"$work/bf.err"; code=$?; set -e
if [[ "$code" -eq 2 && ! -f "$work/bad-format.out.json" ]]; then pass "evidence in the wrong format is refused"
else fail "evidence in the wrong format is refused (exit $code)"; fi

if [[ "$failures" -ne 0 ]]; then echo "release attestation gate: $failures failure(s)" >&2; exit 1; fi
echo "release attestation gate: all checks passed"
