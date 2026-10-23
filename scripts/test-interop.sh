#!/usr/bin/env bash
# Gate for the HCL importer and the TLA+ / Lean exporters of LTS_ATOM declarations (Lean only).
#
#   scripts/test-interop.sh [--skip-build]
#
# The expected outputs in test/fixtures/hcl and test/fixtures/lts were written by the earlier Clojure implementation
# from the inputs next to them; zilInterop must reproduce them byte for byte. Bad inputs are refused with a message and
# a non-zero exit status.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "${1:-}" == "--skip-build" ]] || lake build zilInterop >/dev/null
interop="$root/.lake/build/bin/zilInterop"
work="$(mktemp -d "${TMPDIR:-/tmp}/interop.XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }

same() { # name expected actual
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1"; diff "$2" "$3" | head -10 >&2 || true; fi
}

# HCL files and directories become ZIL facts under the given module name.
hcl() { # fixture module
  local base=test/fixtures/hcl/$1 input
  input="$base"; [[ -f "$base/main.tf" ]] && input="$base/main.tf"
  "$interop" import-hcl "$input" - "$2" >"$work/$1.zc"
  same "import-hcl $1" "$base.expected.zc" "$work/$1.zc"
}
hcl basic hcl.import
hcl edge hcl.test.edge
hcl edge2 hcl.test.edge2
hcl second hcl.import
hcl dir hcl.dir

# LTS_ATOM declarations become TLA+ modules and Lean skeletons.
lts() { # fixture source [tla-module] [lean-namespace]
  local out=test/fixtures/lts/expected/$1
  "$interop" export-tla "$2" - ${3:+"$3"} >"$work/$1.tla"
  same "export-tla $1" "$out.tla" "$work/$1.tla"
  "$interop" export-lean "$2" - ${4:+"$4"} >"$work/$1.lean"
  same "export-lean $1" "$out.lean" "$work/$1.lean"
}
lts edge test/fixtures/lts/models/edge.zc
lts nominal test/fixtures/lts/models/nominal.zc
lts dir-named test/fixtures/lts/models/dir "My Module" "my.ns-x.9y"
lts evmone examples/evmone-dmetavm.zc
lts deploy-flow examples/lts-atom-deploy-flow.zc
lts tlm-bridge examples/tlm-formal-bridge.zc
lts measurement examples/lean4-integration/measurement-protocol-lts.zc

# the digit-leading module keeps its written name in the TLA+ module id
if head -1 "$work/nominal.tla" | grep -q 'MODULE M_9nine_module_LTSBridge'; then
  pass "a digit-leading module gets the M_ prefix"
else fail "a digit-leading module gets the M_ prefix"; fi

# refusals
refuse() { # name command...
  local name="$1"; shift
  set +e; "$@" >/dev/null 2>"$work/refuse.err"; local code=$?; set -e
  if [[ "$code" -ne 0 && -s "$work/refuse.err" ]]; then pass "refused: $name"; else fail "refused: $name (exit $code)"; fi
}
mkdir -p "$work/empty" "$work/nolts"
printf 'resource "x" "y" {\n}\n' >"$work/empty/main.tf"
printf 'MODULE m.\n\nPROVIDER p [source="s"].\n' >"$work/nolts/m.zc"
printf 'LTS_ATOM a [states=#{x}, initial=x, transitions={}].\n' >"$work/nolts/nomodule.zc"
refuse "a missing HCL path" "$interop" import-hcl "$work/nonexistent"
refuse "a directory with no HCL" "$interop" import-hcl "$work/nolts"
refuse "a TLA export with no LTS_ATOM" "$interop" export-tla "$work/nolts/m.zc"
refuse "a TLA export with no MODULE" "$interop" export-tla "$work/nolts/nomodule.zc"
refuse "an unknown command" "$interop" frobnicate

[[ "$failures" -eq 0 ]] && echo "interop: all checks passed" || { echo "interop: $failures check(s) failed" >&2; exit 1; }
