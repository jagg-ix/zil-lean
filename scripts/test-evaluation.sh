#!/usr/bin/env bash
# Gate for runtime placement evaluation (Lean only).
#
#   scripts/test-evaluation.sh [--skip-build]
#
# Eleven models with their measurements (test/fixtures/evaluation/) were evaluated by the earlier Clojure implementation;
# the Lean evaluator must give the same report: the same recommendations, statuses, eligibility and counts, and scores
# equal to within 1e-9. The exit status is 1 exactly when a change is recommended. Bad inputs are refused with 2.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "${1:-}" == "--skip-build" ]] || lake build zilEvaluate >/dev/null
evaluate="$root/.lake/build/bin/zilEvaluate"
work="$(mktemp -d "${TMPDIR:-/tmp}/evaluation.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

compare='
import json, sys
def close(a, b):
    if isinstance(a, bool) or isinstance(b, bool) or a is None or b is None: return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)): return abs(a - b) <= 1e-9
    if isinstance(a, dict) and isinstance(b, dict): return set(a) == set(b) and all(close(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list): return len(a) == len(b) and all(close(x, y) for x, y in zip(a, b))
    return a == b
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
sys.exit(0 if close(a, b) else 1)'

for dir in test/fixtures/evaluation/*/; do
  name="$(basename "$dir")"
  set +e; "$evaluate" --model "$dir/model.json" --measurements "$dir/measurements.json" --output "$work/$name.json"; code=$?; set -e
  changes="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["summary"]["candidate-change"])' "$work/$name.json")"
  expected_code=0; [[ "$changes" -gt 0 ]] && expected_code=1
  if python3 -I -c "$compare" "$dir/expected.json" "$work/$name.json" && [[ "$code" -eq "$expected_code" ]]; then
    pass "$name: the report equals the Clojure report (exit $code)"
  else fail "$name: the report differs from the Clojure report, or the exit status ($code) is wrong"; fi
done

# the EDN form of the inputs reads to the same report
cat >"$work/model.edn" <<'EDN'
{:schema "ZIL-RUNTIME-EVALUATION/1"
 :components [{:id :a :description "d" :current :lean :candidates [:lean :hybrid] :constraints {:requires-kernel-evidence true}}]}
EDN
cat >"$work/measurements.edn" <<'EDN'
[{:component :a :candidate :lean :metric :correctness :value 0.9 :confidence 0.9 :samples 3 :source "x"}]
EDN
if "$evaluate" --model "$work/model.edn" --measurements "$work/measurements.edn" >"$work/edn.json" \
  && python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["components"][0]["decision"]["status"]=="insufficient-evidence"' "$work/edn.json"; then
  pass "EDN inputs are read"
else fail "EDN inputs are read"; fi

# refusals
refuse() { # name json
  echo "$2" >"$work/bad.json"
  set +e; "$evaluate" --model "$work/bad.json" >/dev/null 2>"$work/bad.err"; code=$?; set -e
  if [[ "$code" -eq 2 ]]; then pass "refused: $1"; else fail "refused: $1 (exit $code)"; fi
}
refuse "wrong schema" '{"schema":"nope","components":[]}'
refuse "no components" '{"schema":"ZIL-RUNTIME-EVALUATION/1","components":[]}'
refuse "weights that do not sum to one" '{"schema":"ZIL-RUNTIME-EVALUATION/1","weights":{"correctness":0.5},"components":[{"id":"a","description":"d","current":"lean","candidates":["lean"]}]}'
refuse "a current runtime that is not a candidate" '{"schema":"ZIL-RUNTIME-EVALUATION/1","components":[{"id":"a","description":"d","current":"lean","candidates":["hybrid"]}]}'
refuse "duplicate component ids" '{"schema":"ZIL-RUNTIME-EVALUATION/1","components":[{"id":"a","description":"d","current":"lean","candidates":["lean"]},{"id":"a","description":"d","current":"lean","candidates":["lean"]}]}'

if [[ "$failures" -ne 0 ]]; then echo "evaluation gate: $failures failure(s)" >&2; exit 1; fi
echo "evaluation gate: all checks passed"
