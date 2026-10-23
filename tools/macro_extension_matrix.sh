#!/usr/bin/env bash
# Qualify every macro library listed in spec/macro-extension-matrix.tsv.
#
#   tools/macro_extension_matrix.sh [--update] [--skip-build] [--only NAME]... [MATRIX]
#
# For each row, the native frontend expands the model with its library and the result
# must equal the reviewed golden in spec/macro-extension-golden/<name>.expanded.zc; the native frontend then compiles
# the model, and the generated Lean must typecheck. --update rewrites the goldens from the native expansion (review
# the diff before committing it). A row whose library column is "-" has a model that defines its macros itself.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

update=0
skip_build=0
only=" "
MATRIX="${ROOT_DIR}/spec/macro-extension-matrix.tsv"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) update=1 ;;
    --skip-build) skip_build=1 ;;
    --only) shift; only="${only}${1:?--only needs a row name} " ;;
    -*) echo "usage: $0 [--update] [--skip-build] [--only NAME]... [MATRIX]" >&2; exit 2 ;;
    *) MATRIX="$1" ;;
  esac
  shift
done

if [[ ! -f "${MATRIX}" ]]; then
  echo "macro extension matrix not found: ${MATRIX}" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zil-macro-matrix.XXXXXX")"
if [[ -z "${ZIL_MACRO_KEEP_TMP:-}" ]]; then
  trap 'rm -rf "${TMP_DIR}"' EXIT
else
  echo "[info] preserving matrix output at ${TMP_DIR}"
fi

pass_count=0
fail_count=0

zil="${ROOT_DIR}/.lake/build/bin/zil"
if [[ "${skip_build}" -eq 0 ]]; then
  lake build zil >"${TMP_DIR}/build.log" 2>&1 || { tail -30 "${TMP_DIR}/build.log" >&2; exit 1; }
fi
golden_dir="$(dirname "${MATRIX}")/macro-extension-golden"
mkdir -p "${golden_dir}"

while IFS=$'\t' read -r name lib model; do
  [[ -z "${name}" || "${name}" == \#* ]] && continue
  [[ "${only}" == " " || "${only}" == *" ${name} "* ]] || continue
  lib_args=()
  if [[ "${lib}" == "-" ]]; then
    # The model defines its own macros inline: nothing to compose.
    lib_dir=""
  elif [[ "${lib}" == @* ]]; then
    # A single library file: composed alone, as the macro frontend composes a lib/ directory.
    lib_dir="${TMP_DIR}/.${name}-lib"
    mkdir -p "${lib_dir}"
    cp "${ROOT_DIR}/${lib#@}" "${lib_dir}/"
  else
    lib_dir="${ROOT_DIR}/${lib}"
  fi
  [[ -n "${lib_dir}" ]] && lib_args=(--lib "${lib_dir}")
  expanded="${TMP_DIR}/${name}.expanded.zc"
  lean_file="${TMP_DIR}/${name}.lean"
  golden="${golden_dir}/${name}.expanded.zc"
  namespace="Zil.MacroMatrix.$(printf '%s' "${name}" | tr -c 'A-Za-z0-9\n' '_')"

  if ! "${zil}" expand "${model}" "${expanded}" ${lib_args[@]+"${lib_args[@]}"} 2>"${TMP_DIR}/${name}.err"; then
    cat "${TMP_DIR}/${name}.err" >&2
    printf '[fail] %s: native expansion\n' "${name}" >&2
    fail_count=$((fail_count + 1))
    continue
  fi
  if [[ "${update}" -eq 1 ]]; then
    cp "${expanded}" "${golden}"
  elif [[ ! -f "${golden}" ]]; then
    printf '[fail] %s: no golden at %s (run with --update, then review it)\n' "${name}" "${golden}" >&2
    fail_count=$((fail_count + 1))
    continue
  elif ! diff -u "${golden}" "${expanded}" >"${TMP_DIR}/${name}.diff"; then
    head -30 "${TMP_DIR}/${name}.diff" >&2
    printf '[fail] %s: native expansion differs from its golden\n' "${name}" >&2
    fail_count=$((fail_count + 1))
    continue
  fi
  if ! "${zil}" compile "${model}" "${lean_file}" "${namespace}" ${lib_args[@]+"${lib_args[@]}"} 2>"${TMP_DIR}/${name}.err"; then
    cat "${TMP_DIR}/${name}.err" >&2
    printf '[fail] %s: native compile\n' "${name}" >&2
    fail_count=$((fail_count + 1))
    continue
  fi
  if ! lake env lean "${lean_file}" >"${TMP_DIR}/${name}.lean.log" 2>&1; then
    tail -20 "${TMP_DIR}/${name}.lean.log" >&2
    printf '[fail] %s: generated Lean typecheck\n' "${name}" >&2
    fail_count=$((fail_count + 1))
    continue
  fi
  printf '[pass] %s: native expansion equals golden + native compile + generated Lean typecheck\n' "${name}"
  pass_count=$((pass_count + 1))
done < "${MATRIX}"

printf '[summary] passed=%d failed=%d\n' "${pass_count}" "${fail_count}"
[[ "${fail_count}" -eq 0 ]]
