#!/usr/bin/env bash
set -euo pipefail

# Formal pipeline for TLM ZIL models: compile the model to Lean and typecheck the generated module.
#
# The LTS and constraint bundle gates and the TLA+ export belonged to the removed Clojure runtime
# (spec/clojure-removal.md).
#
# Usage:
#   ./tools/tlm_formal_ci.sh [model.zc] [out_dir] [lean_namespace]
#
# Defaults:
#   model.zc       = examples/tlm-formal-bridge.zc
#   out_dir        = /tmp
#   lean_namespace = Zil.Generated.TLM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODEL_PATH="${1:-examples/tlm-formal-bridge.zc}"
OUT_DIR="${2:-/tmp}"
LEAN_NAMESPACE="${3:-Zil.Generated.TLM}"

mkdir -p "$OUT_DIR"

LEAN_OUT="$OUT_DIR/tlm_bridge.lean"

echo "[tlm-ci] model=$MODEL_PATH"
echo "[tlm-ci] out_dir=$OUT_DIR"
echo "[tlm-ci] lean_namespace=$LEAN_NAMESPACE"

cd "$ZIL_ROOT"

echo "[tlm-ci] step 1/1: compile to Lean and typecheck"
./bin/zil compile "$MODEL_PATH" "$LEAN_OUT" "$LEAN_NAMESPACE"
lake env lean "$LEAN_OUT"

echo "[tlm-ci] complete"
echo "[tlm-ci] lean_out=$LEAN_OUT"
