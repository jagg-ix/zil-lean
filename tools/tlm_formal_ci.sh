#!/usr/bin/env bash
set -euo pipefail

# One-shot formal pipeline for TLM ZIL models:
# 1) LTS profile gate
# 2) Constraint/Z3 profile gate
# 3) TLA+ export
# 4) Lean4 export
#
# Usage:
#   ./tools/tlm_formal_ci.sh [model.zc] [out_dir] [tla_module] [lean_namespace]
#
# Defaults:
#   model.zc       = examples/tlm-formal-bridge.zc
#   out_dir        = /tmp
#   tla_module     = TLMBridgeFromZil
#   lean_namespace = Zil.Generated.TLM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODEL_PATH="${1:-examples/tlm-formal-bridge.zc}"
OUT_DIR="${2:-/tmp}"
TLA_MODULE="${3:-TLMBridgeFromZil}"
LEAN_NAMESPACE="${4:-Zil.Generated.TLM}"

mkdir -p "$OUT_DIR"

TLA_OUT="$OUT_DIR/tlm_bridge.tla"
LEAN_OUT="$OUT_DIR/tlm_bridge.lean"

echo "[tlm-ci] model=$MODEL_PATH"
echo "[tlm-ci] out_dir=$OUT_DIR"
echo "[tlm-ci] tla_module=$TLA_MODULE"
echo "[tlm-ci] lean_namespace=$LEAN_NAMESPACE"

cd "$ZIL_ROOT"

echo "[tlm-ci] step 1/4: lts gate"
./bin/zil bundle-check "$MODEL_PATH" lts

echo "[tlm-ci] step 2/4: constraint gate (z3)"
./bin/zil bundle-check "$MODEL_PATH" constraint

echo "[tlm-ci] step 3/4: export tla"
./bin/zil export-tla "$MODEL_PATH" "$TLA_OUT" "$TLA_MODULE"

echo "[tlm-ci] step 4/4: export lean"
./bin/zil export-lean "$MODEL_PATH" "$LEAN_OUT" "$LEAN_NAMESPACE"

echo "[tlm-ci] complete"
echo "[tlm-ci] tla_out=$TLA_OUT"
echo "[tlm-ci] lean_out=$LEAN_OUT"
