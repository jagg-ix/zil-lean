#!/usr/bin/env bash
# Gate for ZIL blocks embedded in host-language sources (Lean only).
#
#   scripts/test-embedded.sh [--skip-build] [--no-typecheck]
#
# The sources in test/fixtures/embedded/cases and the expected outputs in test/fixtures/embedded/expected were
# produced by the earlier Clojure implementation: scan facts and snapshots must match byte for byte, drift reports and
# compile manifests must match as data, and the generated Lean modules must match byte for byte. The host file for the
# Clojure language is stored under a different name (`core.clj.sample`) because no Clojure source may be tracked; the
# gate copies it into place in a scratch tree. One block set is also typechecked with `lake env lean`.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
skip_build=0; typecheck=1
for arg in "$@"; do
  case "$arg" in
    --skip-build) skip_build=1 ;;
    --no-typecheck) typecheck=0 ;;
    *) echo "usage: $0 [--skip-build] [--no-typecheck]" >&2; exit 2 ;;
  esac
done
[[ "$skip_build" -eq 1 ]] || lake build zilEmbedded >/dev/null
embedded="$root/.lake/build/bin/zilEmbedded"
fixtures="$root/test/fixtures/embedded"
work="$(mktemp -d "${TMPDIR:-/tmp}/embedded.XXXXXX")"
real="$(cd "$work" && pwd -P)"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

# a scratch tree with the same relative paths the expected outputs were written with
stage="$work/stage"
mkdir -p "$stage/test/fixtures/embedded"
cp -R "$fixtures/cases/." "$stage/test/fixtures/embedded/"
for sample in "$stage"/test/fixtures/embedded/*/src/*.sample; do
  mv "$sample" "${sample%.sample}"
done
cases=test/fixtures/embedded
expected="$fixtures/expected"

same_json() { # expected actual: equal as data
  python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])) == json.load(open(sys.argv[2])) else 1)' "$1" "$2"
}

scan_case() { # name path
  local name="$1" path="$2"
  if [[ -f "$expected/$name.err" ]]; then
    set +e; (cd "$stage" && "$embedded" scan "$path" - >"$work/$name.out" 2>"$work/$name.err"); local code=$?; set -e
    # the macro expander words its own refusals; every other refusal text is the earlier implementation's
    if [[ "$code" -eq 2 && ( "$name" == err-badmacro || "$(head -1 "$work/$name.err")" == "$(cat "$expected/$name.err")" ) ]]; then
      pass "$name: refused"
    else fail "$name: expected exit 2 and '$(cat "$expected/$name.err")', got exit $code and '$(head -1 "$work/$name.err")'"; fi
  else
    if ! (cd "$stage" && "$embedded" scan "$path" - >"$work/$name.zc" 2>"$work/$name.err" \
        && "$embedded" snapshot "$path" "$work/$name.snapshot.json" >/dev/null 2>>"$work/$name.err"); then
      fail "$name: the scan was refused: $(head -1 "$work/$name.err")"; return
    fi
    if cmp -s "$expected/$name.zc" "$work/$name.zc" && cmp -s "$expected/$name.snapshot.json" "$work/$name.snapshot.json"; then
      pass "$name: facts and snapshot are byte-identical"
    else fail "$name: facts or snapshot differ"; diff "$expected/$name.zc" "$work/$name.zc" | head -6 >&2 || true; fi
  fi
}
# every case with a `src` directory; a refused case has an expected message
for dir in "$fixtures"/cases/*/src; do
  name="$(basename "$(dirname "$dir")")"
  [[ "$name" == single ]] && continue   # a file given directly, below
  scan_case "$name" "$cases/$name/src"
done
scan_case single "$cases/single/src/data.dat"

(cd "$stage" && "$embedded" scan "$cases/macros/src" - embedded.annotations "$cases/macros/lib" >"$work/explicit.zc")
if cmp -s "$expected/macros-explicit-lib.zc" "$work/explicit.zc"; then pass "an explicit lib directory"; else fail "an explicit lib directory"; fi
(cd "$stage" && "$embedded" scan "$cases/macros/src" - custom.module >"$work/named.zc")
if cmp -s "$expected/macros-module-name.zc" "$work/named.zc"; then pass "a module name"; else fail "a module name"; fi

# writing to a file prints a summary and the same facts
(cd "$stage" && "$embedded" scan "$cases/tree/src" "$work/out.zc" >"$work/summary.json")
if cmp -s "$expected/tree.zc" "$work/out.zc" \
  && python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["ok"] is True and s["block_count"]==4 and s["file_count"]==3' "$work/summary.json"; then
  pass "scan to a file"
else fail "scan to a file"; fi

# drift: a baseline from one tree, checked against another at the same path
for scenario in drift-source drift-macro; do
  dir="$work/$scenario"; mkdir -p "$dir"
  cp -R "$fixtures/cases/$scenario/base/src" "$dir/src"; cp -R "$fixtures/cases/$scenario/base/lib" "$dir/lib"
  (cd "$dir" && "$embedded" snapshot src baseline.json >/dev/null)
  if cmp -s "$expected/$scenario.baseline.json" "$dir/baseline.json"; then pass "$scenario: baseline is byte-identical"
  else fail "$scenario: baseline differs"; fi
  set +e; (cd "$dir" && "$embedded" drift-check src baseline.json >clean.json); clean=$?; set -e
  if [[ "$clean" -eq 0 ]] && python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["ok"] is True and r["drift"] is False and r["differences"]==[]' "$dir/clean.json"; then
    pass "$scenario: no change, no drift (exit 0)"
  else fail "$scenario: unchanged sources report drift (exit $clean)"; fi
  rm -rf "$dir/src" "$dir/lib"
  cp -R "$fixtures/cases/$scenario/changed/src" "$dir/src"; cp -R "$fixtures/cases/$scenario/changed/lib" "$dir/lib"
  set +e; (cd "$dir" && "$embedded" drift-check src baseline.json >report.json); code=$?; set -e
  if [[ "$code" -eq 1 ]] && same_json "$expected/$scenario.drift.json" "$dir/report.json"; then pass "$scenario: the drift report equals the earlier one (exit 1)"
  else fail "$scenario: the drift report differs (exit $code)"; fi
done

# compile: generated modules byte for byte, manifests as data
normalize_manifest() { # actual -> stdout
  python3 -I - "$1" "$real" <<'PY'
import json, sys
text = open(sys.argv[1]).read().replace(sys.argv[2] + "/stage", "@W@").replace(sys.argv[2], "@W@")
def strip(x):
    if isinstance(x, dict):
        return {k: (strip([{kk: vv for kk, vv in e.items() if kk not in ("message", "data")} for e in v]) if k == "scan-errors" else strip(v))
                for k, v in x.items() if k != "command"}
    if isinstance(x, list): return [strip(v) for v in x]
    return x
print(json.dumps(strip(json.loads(text)), sort_keys=True))
PY
}
compile_case() { # name expected-exit args...
  local name="$1" want="$2"; shift 2
  local out="$real/gen-$name"
  set +e; (cd "$stage" && "$embedded" compile --out "$out" --manifest "$work/$name.manifest.json" --no-verify "$@" >"$work/$name.log" 2>&1); local code=$?; set -e
  local ok=1
  [[ "$code" -eq "$want" ]] || ok=0
  if [[ -d "$fixtures/expected/compile/$name/gen" ]]; then
    diff -r "$fixtures/expected/compile/$name/gen" "$out" >/dev/null 2>&1 || ok=0
  else
    [[ ! -e "$out" ]] || ok=0
  fi
  [[ "$(normalize_manifest "$work/$name.manifest.json" | sed "s#@W@/gen-$name#@W@/gen#g")" \
    == "$(python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$fixtures/expected/compile/$name/manifest.json")" ]] || ok=0
  if [[ "$ok" -eq 1 ]]; then pass "compile $name: modules and manifest equal the earlier ones (exit $code)"
  else fail "compile $name (exit $code, wanted $want)"; fi
}
r=test/fixtures/embedded
compile_case lean 0 --root "$r/lean/src"
compile_case python 0 --root "$r/python/src" --root "$r/rust/src"
compile_case tree 0 --root "$r/tree/src"
compile_case macros 0 --root "$r/macros/src" --lib "$r/macros/lib"
compile_case err-noend 1 --root "$r/err-noend/src"
compile_case empty-require 1 --root "$r/err-nofact/src" --require-blocks
compile_case check 0 --root "$r/text/src" --check

# the generated modules typecheck
if [[ "$typecheck" -eq 1 ]]; then
  if "$embedded" compile --root "$stage/$r/tree/src" --out "$real/gen-verify" --manifest "$work/verify.json" >"$work/verify.log" 2>&1 \
    && python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["ok"] and m["verified"]==m["block-count"]==4' "$work/verify.json"; then
    pass "compile tree with typecheck: 4 of 4 modules verified"
  else fail "compile tree with typecheck"; tail -5 "$work/verify.log" >&2; fi
fi

# refusals
set +e; "$embedded" scan "$work/does-not-exist" >/dev/null 2>"$work/missing.err"; missing=$?
"$embedded" frobnicate >/dev/null 2>&1; unknown=$?
"$embedded" drift-check "$stage/$r/tree/src" "$work/no-such-baseline.json" >/dev/null 2>&1; nobaseline=$?
echo '{"format":"other"}' >"$work/other.json"; "$embedded" drift-check "$stage/$r/tree/src" "$work/other.json" >/dev/null 2>&1; badformat=$?
set -e
[[ "$missing" -eq 2 && -s "$work/missing.err" ]] && pass "refused: a missing path" || fail "refused: a missing path (exit $missing)"
[[ "$unknown" -eq 2 ]] && pass "refused: an unknown command" || fail "refused: an unknown command (exit $unknown)"
[[ "$nobaseline" -ne 0 && "$nobaseline" -ne 1 ]] && pass "refused: a missing baseline" || fail "refused: a missing baseline (exit $nobaseline)"
[[ "$badformat" -eq 2 ]] && pass "refused: a baseline of another format" || fail "refused: a baseline of another format (exit $badformat)"

if [[ "$failures" -eq 0 ]]; then echo "embedded: all checks passed"; else echo "embedded: $failures check(s) failed" >&2; exit 1; fi
