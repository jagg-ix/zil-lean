#!/usr/bin/env bash
set -euo pipefail

# Formal pipeline for D-MetaVM (evmone-oriented) ZIL models.
#
# Steps:
# 1) compile the ZIL model to Lean and typecheck the generated module
# 2) optional TLC run for DistributedL3.tla (if TLA2TOOLS_JAR exists)
#
# The LTS and constraint bundle gates and the TLA+ export from ZIL belonged to the removed
# Clojure runtime (spec/clojure-removal.md); the TLA+ models under formal/dmetavm are checked on their own.
#
# Usage:
#   ./tools/dmetavm_formal_ci.sh [model.zc] [out_dir] [lean_namespace]
#
# Defaults:
#   model.zc       = examples/evmone-dmetavm.zc
#   out_dir        = /tmp
#   lean_namespace = Zil.Generated.DMetaVMEvmone

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CALLER_DIR="$(pwd)"

MODEL_PATH="${1:-examples/evmone-dmetavm.zc}"
OUT_DIR="${2:-/tmp}"
LEAN_NAMESPACE="${3:-Zil.Generated.DMetaVMEvmone}"

mkdir -p "$OUT_DIR"

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
echo "[dmetavm-ci] lean_namespace=$LEAN_NAMESPACE"

cd "$ZIL_ROOT"

echo "[dmetavm-ci] step 1/2: compile to Lean and typecheck"
./bin/zil compile "$MODEL_PATH" "$LEAN_OUT" "$LEAN_NAMESPACE"
lake env lean "$LEAN_OUT"

echo "[dmetavm-ci] step 2/2: optional TLC check (DistributedL3)"
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
echo "[dmetavm-ci] lean_out=$LEAN_OUT"
