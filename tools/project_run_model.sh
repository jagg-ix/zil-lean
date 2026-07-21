#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="${1:?usage: project_run_model.sh <project-name> [model-rel-path]}"
MODEL_REL_PATH="${2:-models/examples/system-sync-migration-generic.zc}"
OUT_PATH="${OUT_PATH:-/tmp/zil-project-${PROJECT_NAME}.$$.pre.zc}"

MODEL_PATH="$ROOT_DIR/projects/$PROJECT_NAME/$MODEL_REL_PATH"
if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Model not found: $MODEL_PATH" >&2
  exit 2
fi

ZIL_BIN="${ZIL_BIN:-$ROOT_DIR/bin/zil}"
if [[ ! -x "$ZIL_BIN" ]]; then
  echo "ZIL runtime not executable: $ZIL_BIN" >&2
  exit 2
fi

LIB_DIR="$("$ROOT_DIR/tools/project_stage_lib.sh" "$PROJECT_NAME")"

echo "[project:$PROJECT_NAME] preprocess: $MODEL_PATH"
"$ZIL_BIN" preprocess "$MODEL_PATH" "$OUT_PATH" "$LIB_DIR" >/dev/null

echo "[project:$PROJECT_NAME] execute: $OUT_PATH"
"$ZIL_BIN" "$OUT_PATH"
