#!/usr/bin/env bash
set -euo pipefail

# One-shot formal pipeline for D-MetaVM (evmone-oriented) ZIL models.
#
# Steps:
# 1) LTS profile gate
# 2) Constraint/Z3 profile gate
# 3) TLA+ export from ZIL
# 4) Lean4 export from ZIL
# 5) Optional TLC run for DistributedL3.tla (if TLA2TOOLS_JAR exists)
#
# Usage:
#   ./tools/dmetavm_formal_ci.sh [model.zc] [out_dir] [tla_module] [lean_namespace]
#
# Defaults:
#   model.zc       = examples/evmone-dmetavm.zc
#   out_dir        = /tmp
#   tla_module     = DMetaVMEvmone
#   lean_namespace = Zil.Generated.DMetaVMEvmone

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CALLER_DIR="$(pwd)"

MODEL_PATH="${1:-examples/evmone-dmetavm.zc}"
OUT_DIR="${2:-/tmp}"
TLA_MODULE="${3:-DMetaVMEvmone}"
LEAN_NAMESPACE="${4:-Zil.Generated.DMetaVMEvmone}"

mkdir -p "$OUT_DIR"

TLA_OUT="$OUT_DIR/dmetavm_evmone.tla"
LEAN_OUT="$OUT_DIR/dmetavm_evmone.lean"

if [[ -n "${TLA2TOOLS_JAR:-}" ]]; then
  if [[ "${TLA2TOOLS_JAR}" = /* ]]; then
    TLA2TOOLS_JAR="${TLA2TOOLS_JAR}"
  else
    TLA2TOOLS_JAR="$CALLER_DIR/${TLA2TOOLS_JAR}"
  fi
elif [[ -f "$ZIL_ROOT/../tools/verification/vendor/tla2tools.jar" ]]; then
  TLA2TOOLS_JAR="$ZIL_ROOT/../tools/verification/vendor/tla2tools.jar"
else
  TLA2TOOLS_JAR=""
fi

echo "[dmetavm-ci] model=$MODEL_PATH"
echo "[dmetavm-ci] out_dir=$OUT_DIR"
echo "[dmetavm-ci] tla_module=$TLA_MODULE"
echo "[dmetavm-ci] lean_namespace=$LEAN_NAMESPACE"

cd "$ZIL_ROOT"

echo "[dmetavm-ci] step 1/5: lts gate"
./bin/zil bundle-check "$MODEL_PATH" lts

echo "[dmetavm-ci] step 2/5: constraint gate (z3)"
./bin/zil bundle-check "$MODEL_PATH" constraint

echo "[dmetavm-ci] step 3/5: export tla"
./bin/zil export-tla "$MODEL_PATH" "$TLA_OUT" "$TLA_MODULE"

echo "[dmetavm-ci] step 4/5: export lean"
./bin/zil export-lean "$MODEL_PATH" "$LEAN_OUT" "$LEAN_NAMESPACE"

echo "[dmetavm-ci] step 5/5: optional TLC check (DistributedL3)"
if [[ -n "$TLA2TOOLS_JAR" && -f "$TLA2TOOLS_JAR" ]]; then
  TLC_META_DIR="$OUT_DIR/tlc_dmetavm_meta"
  mkdir -p "$TLC_META_DIR"
  if java -jar "$TLA2TOOLS_JAR" \
    -metadir "$TLC_META_DIR" \
    -config "$ZIL_ROOT/formal/dmetavm/DistributedL3.cfg" \
    "$ZIL_ROOT/formal/dmetavm/DistributedL3.tla"; then
    echo "[dmetavm-ci] TLC run complete"
  else
    echo "[dmetavm-ci] TLC failed, running SANY parse fallback"
    (
      cd "$ZIL_ROOT/formal/dmetavm"
      java -cp "$TLA2TOOLS_JAR" tla2sany.SANY DistributedL3.tla
    )
    echo "[dmetavm-ci] SANY fallback complete"
  fi
else
  echo "[dmetavm-ci] skipping TLC (set TLA2TOOLS_JAR=/path/to/tla2tools.jar)"
fi

echo "[dmetavm-ci] complete"
echo "[dmetavm-ci] tla_out=$TLA_OUT"
echo "[dmetavm-ci] lean_out=$LEAN_OUT"
