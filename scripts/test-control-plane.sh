#!/usr/bin/env bash
# Gate for the durable control store and the control plane (Lean only; needs the sqlite3 shell).
#
#   scripts/test-control-plane.sh [--skip-build]
#
#  1. A store written by the earlier Clojure implementation (test/fixtures/control-store/clojure-written.db) verifies,
#     and projecting it finds its snapshot already stored with identical bytes.
#  2. Appends advance one revision at a time; a stale expected revision is refused as a conflict.
#  3. Six writers racing for the same revision: exactly one wins.
#  4. Editing a stored event, or a stored payload, is detected by verify.
#  5. A Lean-authoritative decision is run through the supervised worker and recorded as a semantic-decision event.
#  6. The capability inventory validates, and the exchange client and control plane answer a parse.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
skip_build=0
[[ "${1:-}" == "--skip-build" ]] && skip_build=1

command -v sqlite3 >/dev/null || { echo "sqlite3 is required for the control store" >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/control-plane.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

if [[ "$skip_build" -eq 0 ]]; then
  lake build zilControl zilWorker >"$work/build.log" 2>&1 || { tail -20 "$work/build.log" >&2; exit 1; }
fi
binary="$root/.lake/build/bin/zilControl"
# Every call has a deadline, so a hung worker fails the gate instead of stalling it.
control() { timeout 120 "$binary" "$@"; }
payload="test/fixtures/control-store/action-consumed.edn"
decision="sha256:86ae35d58a6aa3b5742df94ef9d7162219f0106a911ae1954c1f0604aaec805d"
stream="stream:gate"

json_field() { python3 -I -c 'import json,sys; v=json.load(sys.stdin); [v:=v[k] for k in sys.argv[1].split(".")]; print(json.dumps(v) if not isinstance(v,str) else v)' "$1"; }

# 1. a store written by the earlier implementation
cp test/fixtures/control-store/clojure-written.db "$work/old.db"
if out="$(control store verify "$work/old.db" stream:diff)" && [[ "$(json_field ok <<<"$out")" == true ]]; then
  pass "a store written by the earlier Clojure implementation verifies"
else fail "a store written by the earlier Clojure implementation verifies"; fi
if out="$(control store project "$work/old.db" stream:diff)" && [[ "$(json_field snapshot.existing <<<"$out")" == true ]]; then
  pass "projecting it finds its snapshot stored with identical bytes"
else fail "projecting it finds its snapshot stored with identical bytes"; fi

# 2. appends and the revision compare-and-swap
db="$work/new.db"
if control store record "$db" "$stream" 0 agent:one action-token-issued "$decision" "$payload" >"$work/a1.json" \
  && control store record "$db" "$stream" 1 agent:two checkpoint-created "$decision" "$payload" >"$work/a2.json" \
  && [[ "$(json_field receipt.final_revision <"$work/a2.json")" == 2 ]]; then
  pass "appends advance one revision at a time"
else fail "appends advance one revision at a time"; fi
set +e; control store record "$db" "$stream" 1 agent:late action-consumed "$decision" "$payload" >/dev/null 2>"$work/stale.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q 'revision-conflict' "$work/stale.err"; then pass "a stale expected revision is refused as a conflict"
else fail "a stale expected revision is refused as a conflict (exit $code)"; fi

# 3. six racing writers, one winner
for n in 1 2 3 4 5 6; do
  ( set +e; control store record "$db" "$stream" 2 "agent:racer$n" action-consumed "$decision" "$payload" >/dev/null 2>&1; echo $? >"$work/race$n" ) &
done
wait
wins=0; losses=0
for n in 1 2 3 4 5 6; do case "$(cat "$work/race$n")" in 0) wins=$((wins + 1)) ;; 2) losses=$((losses + 1)) ;; esac; done
if [[ "$wins" -eq 1 && "$losses" -eq 5 ]]; then pass "six racing writers: exactly one wins"
else fail "six racing writers: exactly one wins (wins $wins, refused $losses)"; fi
if out="$(control store verify "$db" "$stream")" && [[ "$(json_field ok <<<"$out")" == true ]]; then pass "the stream still verifies after the race"
else fail "the stream still verifies after the race"; fi

# 4. tampering
cp "$db" "$work/tamper-actor.db"
sqlite3 "$work/tamper-actor.db" "UPDATE control_events SET actor='mallory' WHERE revision=2;"
set +e; control store verify "$work/tamper-actor.db" "$stream" >/dev/null; code=$?; set -e
if [[ "$code" -eq 1 ]]; then pass "an edited event is detected"; else fail "an edited event is detected (exit $code)"; fi
cp "$db" "$work/tamper-payload.db"
sqlite3 "$work/tamper-payload.db" "UPDATE control_events SET payload_json='{\"workflow_id\":\"x\"}' WHERE revision=1;"
set +e; control store verify "$work/tamper-payload.db" "$stream" >/dev/null; code=$?; set -e
if [[ "$code" -eq 1 ]]; then pass "an edited payload is detected"; else fail "an edited payload is detected (exit $code)"; fi
cp "$db" "$work/tamper-receipt.db"
sqlite3 "$work/tamper-receipt.db" "UPDATE control_batches SET batch_sha256='sha256:$(printf '0%.0s' $(seq 1 64))' WHERE final_revision=1;"
set +e; control store verify "$work/tamper-receipt.db" "$stream" >/dev/null; code=$?; set -e
if [[ "$code" -eq 1 ]]; then pass "an edited receipt is detected"; else fail "an edited receipt is detected (exit $code)"; fi

# 5. an authoritative decision recorded through the supervised worker
if control store invoke "$work/decision.db" "$stream" 0 agent:tester authorize examples/authorization/access.zc doc:readme viewer user:11 >"$work/inv.json" \
  && [[ "$(json_field response.status <"$work/inv.json")" == ok ]] \
  && [[ "$(json_field event.event.event_type <"$work/inv.json")" == semantic-decision ]] \
  && [[ "$(json_field response.authority <"$work/inv.json")" == lean ]] \
  && python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1]))["response"]; assert r["result_sha256"].startswith("sha256:") and "result-sha256-pending-client-attestation" not in r["warnings"]' "$work/inv.json"; then
  pass "a decision runs through the worker, is attested, and is recorded as a semantic-decision"
else fail "a decision runs through the worker, is attested, and is recorded as a semantic-decision"; fi
if out="$(control store status "$work/decision.db" "$stream")" && [[ "$(json_field projection.workflow-count <<<"$out")" == 1 ]]; then
  pass "its workflow appears in the status projection"
else fail "its workflow appears in the status projection"; fi

# 6. inventory and exchange
if out="$(control capabilities)" && [[ "$(python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)["capabilities"]))' <<<"$out")" -ge 20 ]]; then
  pass "the capability inventory is valid and listed"
else fail "the capability inventory is valid and listed"; fi
if out="$(control exchange parse examples/authorization/access.zc)" && [[ "$(json_field status <<<"$out")" == ok ]]; then
  pass "the exchange client gets a verified, attested parse"
else fail "the exchange client gets a verified, attested parse"; fi
if out="$(control run compile examples/authorization/access.zc Gate.Compiled)" && [[ "$(json_field status <<<"$out")" == ok ]]; then
  pass "the control plane dispatches an owned operation"
else fail "the control plane dispatches an owned operation"; fi
set +e; control run no-such-operation examples/authorization/access.zc >/dev/null 2>"$work/unk.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q 'unknown-command' "$work/unk.err"; then pass "an operation nobody owns is refused"
else fail "an operation nobody owns is refused (exit $code)"; fi

# 7. supervision: a worker that never answers is timed out; one that exits is a transport error
start="$(date +%s)"
set +e; ZIL_WORKER_COMMAND="sleep 60" ZIL_WORKER_TIMEOUT_MS=500 control exchange parse examples/authorization/access.zc >/dev/null 2>"$work/slow.err"; code=$?; set -e
elapsed=$(( $(date +%s) - start ))
if [[ "$code" -eq 2 ]] && grep -q 'transport-error: timed out' "$work/slow.err" && [[ "$elapsed" -lt 20 ]]; then
  pass "a worker that never answers is timed out and killed (${elapsed}s)"
else fail "a worker that never answers is timed out and killed (exit $code, ${elapsed}s)"; fi
set +e; ZIL_WORKER_COMMAND="true" control exchange parse examples/authorization/access.zc >/dev/null 2>"$work/gone.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q 'transport-error' "$work/gone.err"; then pass "a worker that exits without answering is a transport error"
else fail "a worker that exits without answering is a transport error (exit $code)"; fi
set +e; ZIL_WORKER_COMMAND="echo not-json" control exchange parse examples/authorization/access.zc >/dev/null 2>"$work/junk.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q 'transport-error' "$work/junk.err"; then pass "a worker that answers with something else is a transport error"
else fail "a worker that answers with something else is a transport error (exit $code)"; fi

if [[ "$failures" -ne 0 ]]; then
  echo "control plane gate: $failures failure(s)" >&2
  exit 1
fi
echo "control plane gate: all checks passed"
