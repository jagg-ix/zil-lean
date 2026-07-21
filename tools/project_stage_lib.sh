#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="${1:?usage: project_stage_lib.sh <project-name> [out-lib-dir]}"
OUT_LIB_DIR="${2:-${OUT_LIB_DIR:-/tmp/zil-project-${PROJECT_NAME}-layered-lib}}"

PROJECT_DIR="$ROOT_DIR/projects/$PROJECT_NAME"
PROJECT_LIB_DIR="${PROJECT_LIB_DIR:-$PROJECT_DIR/lib}"
PLUGIN_LIB_DIR="${PLUGIN_LIB_DIR:-$PROJECT_DIR/plugins}"
ZIL_CORE_LIB_DIR="${ZIL_CORE_LIB_DIR:-$ROOT_DIR/lib}"
INCLUDE_ZIL_CORE_LIB="${INCLUDE_ZIL_CORE_LIB:-0}"
ZIL_SHARED_TLM_LIB="${ZIL_SHARED_TLM_LIB:-$ROOT_DIR/lib/tlm-macros.zc}"
INCLUDE_ZIL_SHARED_TLM_LIB="${INCLUDE_ZIL_SHARED_TLM_LIB:-1}"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Project directory not found: $PROJECT_DIR" >&2
  exit 2
fi

mkdir -p "$OUT_LIB_DIR"
find "$OUT_LIB_DIR" -type f -name '*.zc' -delete 2>/dev/null || true

copy_layer() {
  local prefix="$1"
  local layer_dir="$2"
  if [[ ! -d "$layer_dir" ]]; then
    return 0
  fi
  local f
  for f in "$layer_dir"/*.zc; do
    [[ -f "$f" ]] || continue
    cp "$f" "$OUT_LIB_DIR/${prefix}_$(basename "$f")"
  done
}

copy_file() {
  local prefix="$1"
  local f="$2"
  [[ -f "$f" ]] || return 0
  cp "$f" "$OUT_LIB_DIR/${prefix}_$(basename "$f")"
}

# Load order: core -> shared -> plugins -> project.
if [[ "$INCLUDE_ZIL_CORE_LIB" == "1" ]]; then
  copy_layer "10" "$ZIL_CORE_LIB_DIR"
fi
if [[ "$INCLUDE_ZIL_SHARED_TLM_LIB" == "1" ]]; then
  if [[ ! -f "$ZIL_SHARED_TLM_LIB" ]]; then
    echo "Missing shared TLM macro file: $ZIL_SHARED_TLM_LIB" >&2
    echo "Set ZIL_SHARED_TLM_LIB or disable with INCLUDE_ZIL_SHARED_TLM_LIB=0." >&2
    exit 2
  fi
  if [[ "$INCLUDE_ZIL_CORE_LIB" == "1" && -f "$ZIL_CORE_LIB_DIR/$(basename "$ZIL_SHARED_TLM_LIB")" ]]; then
    :
  else
    copy_file "15" "$ZIL_SHARED_TLM_LIB"
  fi
fi
copy_layer "20" "$PLUGIN_LIB_DIR"
copy_layer "30" "$PROJECT_LIB_DIR"

echo "$OUT_LIB_DIR"
