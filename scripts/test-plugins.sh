#!/usr/bin/env bash
# Gate for the extension registry and the reference extensions (Lean only; the event-store commands need sqlite3).
#
#   scripts/test-plugins.sh [--skip-build]
#
#  1. Each reference extension gives the result the earlier Clojure implementation gave (test/fixtures/plugins/): the
#     repository inventory, its evidence, the exported report bytes, the external-tool runs and their evidence, and the
#     event-store commands. Evidence is compared apart from the `authority` field, which now reads operational.
#  2. An extension that is a separate command is described, invoked and asked for evidence.
#  3. The registry refuses what it must: a Clojure runtime or authority, a built-in command or capability shadowed,
#     a run that fails, a missing requirement, an untrusted claim of Lean authority.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "${1:-}" == "--skip-build" ]] || lake build zilPlugin >/dev/null
plugin="$root/.lake/build/bin/zilPlugin"
work="$(mktemp -d "${TMPDIR:-/tmp}/plugins.XXXXXX")"
work="${work//\/\//}"   # no doubled slash: the tools print normalized paths
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }
ref="extensions/reference"
fix="test/fixtures/plugins"

# compare NAME ACTUAL EXPECTED [ignored-field...]: JSON equality after replacing the work and repository paths
compare() {
  local name="$1" actual="$2" expected="$3"; shift 3
  if python3 -I - "$actual" "$expected" "$work" "$root" "$@" <<'PY'
import json, sys
actual, expected, work, root, *ignore = sys.argv[1:]
def load(path, restore):
    text = open(path).read()
    if restore:
        text = text.replace("@W@", work).replace("@R@", root)
    return json.loads(text)
def normalize(value):
    if isinstance(value, dict): return {k: normalize(v) for k, v in value.items() if k not in ignore}
    if isinstance(value, list): return [normalize(v) for v in value]
    if isinstance(value, str): return value.replace(work, "@W@").replace(root, "@R@")
    return value
sys.exit(0 if normalize(load(actual, False)) == normalize(load(expected, True)) else 1)
PY
  then pass "$name"; else fail "$name"; fi
}

# a deterministic tree for the repository scanner
mkdir -p "$work/tree/a/b" "$work/tree/.git" "$work/tree/.lake" "$work/tree/target" "$work/tree/sp ace"
printf 'one\n' >"$work/tree/a/one.txt"; : >"$work/tree/empty"; printf 'x\000y\377' >"$work/tree/a/b/bin.dat"
printf 'git\n' >"$work/tree/.git/config"; printf 'lake\n' >"$work/tree/.lake/x"; printf 't\n' >"$work/tree/target/y"
printf 'é\n' >"$work/tree/sp ace/é \"q\".txt"; printf 'top\n' >"$work/tree/top.md"

# 1. the reference extensions
"$plugin" run "$ref/repository-scanner/extension.json" repository-scan "$work/tree" >"$work/scan.json"
compare "repository inventory equals the Clojure one (.git, .lake and target excluded)" "$work/scan.json" "$fix/scan.json"
printf '{"root":"%s","subject":"repository:t"}' "$work/tree" >"$work/scan-request.json"
"$plugin" evidence "$ref/repository-scanner/extension.json" "$work/scan-request.json" >"$work/scan-evidence.json"
compare "repository evidence equals the Clojure one" "$work/scan-evidence.json" "$fix/scan-evidence.json" authority

printf '{:status :ok :a/b [1 2.5 "x/y" nil #{:z :a}] :n {:k "é"}}' >"$work/rep.edn"
"$plugin" run "$ref/report-exporter/extension.json" report-export "$work/rep.edn" "$work/out.json" json >"$work/export.json"
compare "report export result equals the Clojure one" "$work/export.json" "$fix/export.json"
if cmp -s "$work/out.json" "$fix/export-output.json"; then pass "the exported report is byte-identical to the Clojure one"
else fail "the exported report is byte-identical to the Clojure one"; fi
"$plugin" run "$ref/report-exporter/extension.json" report-export "$work/rep.edn" "$work/out.edn" edn >/dev/null
if grep -q '^{:a/b\|^{"a/b"' "$work/out.edn" || grep -q ':status' "$work/out.edn"; then pass "the EDN export is written"; else fail "the EDN export is written"; fi

printf '{"tools":{"cat":{"command":["cat","{input}"],"timeout-ms":5000},"bad":{"command":["sh","-c","echo oops >&2; exit 3"],"timeout-ms":5000}}}' >"$work/solver.json"
printf '{"tool":"cat","input-path":"examples/extensions/sample-goal.smt2","subject":"obligation:g"}' >"$work/solver-request.json"
for tool in cat bad; do
  "$plugin" run "$ref/external-solver/extension.json" solver-run "$tool" examples/extensions/sample-goal.smt2 --config "$work/solver.json" >"$work/solver-$tool.json"
  compare "external tool '$tool' report equals the Clojure one" "$work/solver-$tool.json" "$fix/solver-$tool.json"
done
"$plugin" evidence "$ref/external-solver/extension.json" "$work/solver-request.json" --config "$work/solver.json" >"$work/solver-evidence.json"
compare "external tool evidence equals the Clojure one" "$work/solver-evidence.json" "$fix/solver-evidence.json"
set +e; "$plugin" run "$ref/external-solver/extension.json" solver-run not-allowed examples/extensions/sample-goal.smt2 --config "$work/solver.json" >/dev/null 2>"$work/e.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q 'not allowlisted' "$work/e.err"; then pass "a tool that is not allowlisted is refused"; else fail "a tool that is not allowlisted is refused (exit $code)"; fi
printf '{"tools":{"slow":{"command":["sleep","30"],"timeout-ms":300}}}' >"$work/slow.json"
set +e; "$plugin" run "$ref/external-solver/extension.json" solver-run slow examples/extensions/sample-goal.smt2 --config "$work/slow.json" >/dev/null 2>"$work/e.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q 'timed out' "$work/e.err"; then pass "a tool past its deadline is killed"; else fail "a tool past its deadline is killed (exit $code)"; fi

cp test/fixtures/control-store/clojure-written.db "$work/store.db"
"$plugin" run "$ref/sqlite-event-store/extension.json" event-store-status "$work/store.db" stream:diff >"$work/status.json"
compare "event-store-status equals the Clojure one" "$work/status.json" "$fix/store-status.json"
"$plugin" run "$ref/sqlite-event-store/extension.json" event-store-project "$work/store.db" stream:diff >"$work/project.json"
compare "event-store-project equals the Clojure one" "$work/project.json" "$fix/store-project.json"

# discovery and inspection
if [[ "$("$plugin" list extensions | python3 -I -c 'import json,sys; print(",".join(sorted(e["id"] for e in json.load(sys.stdin))))')" == \
  "extension:external-solver,extension:report-exporter,extension:repository-scanner,extension:sqlite-event-store" ]]; then
  pass "the four reference manifests are discovered"; else fail "the four reference manifests are discovered"; fi
if "$plugin" inspect "$ref/report-exporter/extension.json" | python3 -I -c 'import json,sys; v=json.load(sys.stdin); assert v["fingerprint"].startswith("sha256:") and v["trusted"] is False'; then
  pass "inspect gives the manifest with its fingerprint"; else fail "inspect gives the manifest with its fingerprint"; fi

# 2. an extension that is a separate command
echo_manifest="$fix/echo/extension.json"
if out="$("$plugin" run "$echo_manifest" echo hello world)" && [[ "$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["result"]["echoed"])' <<<"$out")" == True ]]; then
  pass "a separate-command extension is described and invoked"; else fail "a separate-command extension is described and invoked"; fi
printf '{}' >"$work/empty-request.json"
if out="$("$plugin" evidence "$echo_manifest" "$work/empty-request.json")" \
  && python3 -I -c 'import json,sys; e=json.load(sys.stdin)[0]; assert e["authority"]=="external" and e["assurance"]=="externally-attested" and e["payload"]=="hello" and e["output_sha256"].startswith("sha256:")' <<<"$out"; then
  pass "its evidence gets an envelope with the manifest's authority and assurance"; else fail "its evidence gets an envelope with the manifest's authority and assurance"; fi
set +e; "$plugin" run "$echo_manifest" fail >/dev/null 2>"$work/e.err"; code=$?; set -e
if [[ "$code" -eq 2 ]] && grep -q 'extension-failure' "$work/e.err"; then pass "a failing extension command is reported as an extension failure"; else fail "a failing extension command is reported as an extension failure (exit $code)"; fi

# 3. what the registry refuses
variant() { rm -rf "$work/$1"; mkdir -p "$work/$1"; cp "$fix/echo/echo-extension.sh" "$work/$1/"; }
refused() { # name manifest-json script-edit-sed message
  variant "$1"; printf '%s\n' "$2" >"$work/$1/extension.json"
  [[ -z "$3" ]] || sed -i.bak "$3" "$work/$1/echo-extension.sh"
  set +e; "$plugin" run "$work/$1/extension.json" "${5:-echo}" >/dev/null 2>"$work/$1.err"; local code=$?; set -e
  if [[ "$code" -eq 2 ]] && grep -q "$4" "$work/$1.err"; then pass "refused: $1"; else fail "refused: $1 (exit $code: $(head -c 120 "$work/$1.err"))"; fi
}
base='{"schema":"ZIL-EXTENSION/1","id":"extension:t","version":"1.0.0","runtime":"external","entrypoint":"echo-extension.sh","capabilities":["echo-provider","evidence-producer"],"requires":["ZIL-EXTENSION/1"],"inputs":[],"outputs":[],"authority":"external","trusted":false}'
edit() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); exec(sys.argv[2]); print(json.dumps(d))' "$base" "$1"; }
refused "a Clojure runtime" "$(edit 'd["runtime"]="clojure"')" "" "Clojure runtime was removed"
refused "a Clojure authority" "$(edit 'd["authority"]="clojure"')" "" "authority clojure was removed"
refused "an external runtime that claims another authority" "$(edit 'd["authority"]="operational"')" "" "must declare external authority"
refused "an untrusted claim of Lean authority" "$(edit 'd["runtime"]="lean"; d["authority"]="lean"')" "" "only a trusted extension"
refused "a trusted external extension" "$(edit 'd["trusted"]=True')" "" "reserved for configured Lean"
refused "a version that is not semantic" "$(edit 'd["version"]="1.0"')" "" "must be semantic"
refused "an id without the extension: prefix" "$(edit 'd["id"]="t"')" "" "must begin with extension:"
refused "a requirement nothing provides" "$(edit 'd["requires"]=["nothing-provides-this"]')" "" "requirements are unavailable"
refused "a command that shadows a built-in command" "$base" 's/"commands":{"echo"/"commands":{"compile"/' "shadows a built-in command" compile
refused "a capability that shadows an authoritative capability" "$(edit 'd["capabilities"]=["parse-v1","evidence-producer"]')" 's/"capabilities":\["echo-provider"/"capabilities":["parse-v1"/' "shadows an authoritative capability"
refused "capabilities that disagree with the manifest" "$base" 's/"echo-provider","evidence-producer"\],"commands"/"echo-provider","extra"],"commands"/' "disagree with its manifest"

if [[ "$failures" -ne 0 ]]; then echo "plugin gate: $failures failure(s)" >&2; exit 1; fi
echo "plugin gate: all checks passed"
