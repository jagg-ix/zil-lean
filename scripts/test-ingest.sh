#!/usr/bin/env bash
# Gate for datasource ingest and data-file conversion (Lean only).
#
#   scripts/test-ingest.sh [--skip-build]
#
# Fifteen datasource models (test/fixtures/ingest/cases) were ingested by the earlier Clojure implementation; the Lean
# tool must produce the same facts (object, relation, subject, attributes, revision, event), the same causal edges and
# the same counts, or refuse the same inputs. Conversions between data formats must match the earlier tool byte for
# byte. HTTP is checked against a throw-away local server. Data files that are EDN are stored as `.edn.sample`,
# because no EDN file may be tracked; the gate copies them into place in a scratch tree.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "${1:-}" == "--skip-build" ]] || lake build zilIngest zil >/dev/null
ingest="$root/.lake/build/bin/zilIngest"
zil="$root/.lake/build/bin/zil"
fixtures="$root/test/fixtures/ingest"
work="$(mktemp -d "${TMPDIR:-/tmp}/ingest.XXXXXX")"
server_pid=""
cleanup() { [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

unsample() { # dir: drop the .sample suffix of every file below it
  find "$1" -name '*.sample' | while IFS= read -r f; do mv "$f" "${f%.sample}"; done
}

normalize='
import json, sys
def na(a): return {k: v for k, v in a.items() if k != "ingest_ts"}
def fact(f): return {"object": f["object"], "relation": f["relation"], "subject": f["subject"], "attrs": na(f["attrs"]), "revision": f["revision"], "event": f["event"]}
doc = json.load(open(sys.argv[1]))
if sys.argv[2] == "lean":
    kept = {}
    for f in doc["fact_list"]:   # one fact per object, relation and subject; a later one replaces an earlier one
        kept[(f["object"], f["relation"], f["subject"])] = f
    facts = [fact(f) for f in kept.values()]
    edges = [[e["left"], e["right"]] for e in doc["before_edge_list"]]
    summary = {k: doc[k] for k in ("sources", "records", "facts")}
    summary["by_source"] = doc["by_source"]
else:
    facts = [fact(f) for f in doc["facts"]]
    edges = doc["edges"]
    summary = doc["summary"]
out = {"summary": summary, "facts": sorted(facts, key=lambda f: json.dumps(f, sort_keys=True)), "edges": sorted(edges)}
print(json.dumps(out, sort_keys=True))'

# 1. datasource models
cases="$work/cases"; cp -R "$fixtures/cases" "$cases"; unsample "$cases"
for dir in "$cases"/*/; do
  name="$(basename "$dir")"
  if [[ -f "$fixtures/expected/$name.refused" ]]; then
    set +e; (cd "$dir" && "$ingest" run m.zc --revision 7 --timestamp 0 --json "$work/$name.json" >/dev/null 2>"$work/$name.err"); code=$?; set -e
    if [[ "$code" -eq 2 && -s "$work/$name.err" ]]; then pass "$name: refused as the earlier tool refused it"
    else fail "$name: expected a refusal (exit 2), got exit $code"; fi
  else
    if (cd "$dir" && "$ingest" run m.zc --revision 7 --timestamp 0 --json "$work/$name.json" >/dev/null 2>"$work/$name.err") \
      && [[ "$(python3 -I -c "$normalize" "$work/$name.json" lean)" == "$(python3 -I -c "$normalize" "$fixtures/expected/$name.json" clj)" ]]; then
      pass "$name: facts, edges and counts equal the earlier tool's"
    else fail "$name: facts, edges or counts differ from the earlier tool's"; head -3 "$work/$name.err" >&2; fi
  fi
done

# 2. data-file conversion and import, byte for byte
inputs="$work/inputs"; cp -R "$fixtures/interop/inputs" "$inputs"; unsample "$inputs"
declare -A format=([json]=json [csv]=csv [yaml]=yaml [kv]=kv [edn]=edn [txt]=text)
converted=0; convert_failed=0
for input in "$inputs"/*; do
  n="$(basename "$input")"
  for target in json yaml csv kv edn text; do
    expected="$fixtures/interop/expected/$n.$target.out"
    [[ -f "$expected" ]] || continue
    "$ingest" convert "$input" "$target" - >"$work/conv.out" 2>/dev/null || true
    if [[ "$(cat "$work/conv.out")" == "$(cat "$expected")" ]]; then converted=$((converted + 1))
    else convert_failed=$((convert_failed + 1)); echo "  differs: $n -> $target" >&2; fi
  done
done
if [[ "$convert_failed" -eq 0 && "$converted" -ge 60 ]]; then pass "conversions: $converted outputs equal the earlier tool's"
else fail "conversions: $convert_failed of $((converted + convert_failed)) differ"; fi
for n in p1.json p2.csv p3.yaml; do
  ext="${n##*.}"
  "$ingest" import-data "$inputs/$n" - interop.t "${format[$ext]}" >"$work/import.out"
  if cmp -s "$work/import.out" "$fixtures/interop/expected/$n.import.out"; then pass "import-data $n equals the earlier tool's facts"
  else fail "import-data $n differs"; fi
done

# 3. behaviour the earlier tool did not have, or wrote differently
printf '{:tag :hot :n 1}' >"$work/kw.edn"
if [[ "$("$ingest" convert "$work/kw.edn" json -)" == '{"tag":"hot","n":1}' ]]; then pass "an EDN keyword value is read as its name"
else fail "an EDN keyword value is read as its name"; fi
printf '[{"note":"two words, a comma","path":"/a/b","empty":""}]' >"$work/odd.json"
"$ingest" import-data "$work/odd.json" "$work/odd.zc" >/dev/null
if grep -q '#note@"value:two words, a comma"\.' "$work/odd.zc" && grep -q '#empty@"value:"\.' "$work/odd.zc" \
  && "$zil" compile "$work/odd.zc" - Zil.Odd >/dev/null 2>&1; then pass "import-data quotes terms that would not parse, and the facts compile"
else fail "import-data quotes terms that would not parse, and the facts compile"; fi
set +e; "$ingest" import-data "$work/odd.json" - interop.t bogus >/dev/null 2>&1; bad_format=$?
"$ingest" import-data "$work/nofile.dat" >/dev/null 2>&1; no_file=$?
"$ingest" convert "$work/odd.json" yaml - --from bogus >/dev/null 2>&1; bad_from=$?
"$ingest" frobnicate >/dev/null 2>&1; unknown=$?
set -e
[[ "$bad_format" -eq 2 && "$no_file" -eq 2 && "$bad_from" -eq 2 && "$unknown" -eq 2 ]] && pass "refused: a bad format, a missing file, a bad --from, an unknown command" \
  || fail "refusals ($bad_format $no_file $bad_from $unknown)"

# 4. outputs: ZIL source and the revision log, read by the native commands
smoke="$cases/smoke"
(cd "$smoke" && "$ingest" run m.zc --revision 7 --timestamp 1000 --zc "$work/smoke.zc" --zilr "$work/smoke.zilr" >/dev/null)
if "$zil" compile "$work/smoke.zc" - Zil.Smoke >/dev/null 2>&1; then pass "the facts as ZIL source compile"; else fail "the facts as ZIL source compile"; fi
summary="$("$zil" revision-summary "$work/smoke.zilr")"
if grep -q '^latest-revision: 7$' <<<"$summary" && "$zil" snapshot "$work/smoke.zilr" 7 - >"$work/snap.txt" && grep -q 'metric.latency' "$work/snap.txt" \
  && [[ "$("$zil" snapshot "$work/smoke.zilr" 6 - | wc -l | tr -d ' ')" -eq 0 ]]; then
  pass "the revision log reads back: a snapshot at 7 has the facts, one at 6 has none"
else fail "the revision log reads back"; fi
(cd "$cases/cucumber" && "$ingest" run m.zc --revision 3 --timestamp 0 --zilr "$work/cuc.zilr" >/dev/null)
if "$zil" causal-check "$work/cuc.zilr" >/dev/null 2>&1 && grep -q '^causal-edges: [1-9]' <("$zil" revision-summary "$work/cuc.zilr"); then
  pass "causal edges from a Cucumber report are in the revision log and acyclic"
else fail "causal edges from a Cucumber report are in the revision log and acyclic"; fi

# 5. source selection, polling and revisions
sel="$(cd "$smoke" && "$ingest" run m.zc --source ds_file --revision 1 --timestamp 0)"
if python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["sources"]==1 and d["by_source"][0]["datasource"]=="datasource:ds_file"' "$sel"; then pass "--source selects one datasource"
else fail "--source selects one datasource"; fi
set +e; (cd "$smoke" && "$ingest" run m.zc --source nothing >/dev/null 2>&1); nosource=$?; set -e
[[ "$nosource" -eq 2 ]] && pass "refused: an unknown --source" || fail "refused: an unknown --source (exit $nosource)"
cat >"$work/poll.zc" <<'ZC'
MODULE poll.demo.
DATASOURCE live [type=rest, mock_response={:metric "metric:tick", :value 1}, poll_mode=interval, poll_every_ms=20].
ZC
"$ingest" run "$work/poll.zc" --polls 3 --initial-revision 100 --timestamp 5 --json "$work/poll.json" >/dev/null
if python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["sources"]==3 and sorted({f["revision"] for f in d["fact_list"]})==[101,102,103]' "$work/poll.json"; then
  pass "an interval source polled three times gives revisions 101, 102, 103"
else fail "an interval source polled three times gives revisions 101, 102, 103"; fi

# 6. HTTP, against a local server
cat >"$work/server.py" <<'PY'
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        if self.path == "/missing": return self.reply(404, b"nope")
        self.reply(200, {"metric": "metric:latency", "value": len(self.path)})
    def do_POST(self):
        data = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        self.reply(200, {"metric": "metric:echo", "value": data, "token": self.headers.get("X-Token")})
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PY
python3 -I "$work/server.py" >"$work/port" 2>/dev/null &
server_pid=$!
for _ in $(seq 1 50); do [[ -s "$work/port" ]] && break; sleep 0.1; done
port="$(head -1 "$work/port")"
cat >"$work/http.zc" <<ZC
MODULE http.demo.
DATASOURCE get_it [type=rest, url="http://127.0.0.1:$port/metrics", format=json].
DATASOURCE post_it [type=rest, url="http://127.0.0.1:$port/echo", method=post, body="hello body", headers={X-Token "abc"}, format=json].
ZC
"$ingest" run "$work/http.zc" --revision 1 --timestamp 0 --json "$work/http.json" >/dev/null
if python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
obs = {f["object"]: f["attrs"] for f in d["fact_list"] if f["relation"] == "observed_from"}
assert obs["metric:latency"]["value"] == len("/metrics"), obs
assert obs["metric:echo"]["value"] == "hello body", obs' "$work/http.json"; then pass "REST over HTTP: GET, and POST with a body and a header"
else fail "REST over HTTP: GET, and POST with a body and a header"; fi
cat >"$work/http404.zc" <<ZC
MODULE http.demo.
DATASOURCE gone [type=rest, url="http://127.0.0.1:$port/missing", format=json].
ZC
set +e; "$ingest" run "$work/http404.zc" >/dev/null 2>"$work/404.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q "404" "$work/404.err"; then pass "refused: an HTTP error status"; else fail "refused: an HTTP error status (exit $code)"; fi
cat >"$work/httpdown.zc" <<ZC
MODULE http.demo.
DATASOURCE down [type=rest, url="http://127.0.0.1:1/none", format=json, timeout_ms=1000].
ZC
set +e; "$ingest" run "$work/httpdown.zc" >/dev/null 2>&1; code=$?; set -e
[[ "$code" -eq 2 ]] && pass "refused: an unreachable server" || fail "refused: an unreachable server (exit $code)"

if [[ "$failures" -eq 0 ]]; then echo "ingest: all checks passed"; else echo "ingest: $failures check(s) failed" >&2; exit 1; fi
