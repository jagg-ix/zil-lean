#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX="${1:-${ROOT_DIR}/spec/macro-extension-matrix.tsv}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zil-macro-matrix.XXXXXX")"
if [[ -z "${ZIL_MACRO_KEEP_TMP:-}" ]]; then
  trap 'rm -rf "${TMP_DIR}"' EXIT
else
  echo "[info] preserving matrix output at ${TMP_DIR}"
fi
cd "${ROOT_DIR}"

if [[ ! -f "${MATRIX}" ]]; then
  echo "macro extension matrix not found: ${MATRIX}" >&2
  exit 2
fi

pass_count=0
fail_count=0
if ! clojure -M:macro-matrix --matrix "${MATRIX}" --out "${TMP_DIR}"; then
  fail_count=1
fi

while IFS=$'\t' read -r name _lib_dir _model; do
  [[ -z "${name}" || "${name}" == \#* ]] && continue
  report="${TMP_DIR}/${name}.parity.edn"
  lean_file="${TMP_DIR}/${name}.lean"
  if [[ ! -f "${report}" ]] || ! rg -q ':ok true' "${report}"; then
    printf '[fail] %s: exact legacy/native expansion parity or native compile\n' "${name}" >&2
    fail_count=$((fail_count + 1))
    continue
  fi
  if [[ ! -f "${lean_file}" ]] || ! lake env lean "${lean_file}"; then
    printf '[fail] %s: generated Lean typecheck\n' "${name}" >&2
    fail_count=$((fail_count + 1))
    continue
  fi
  printf '[pass] %s: exact expansion parity + native compile + generated Lean typecheck\n' "${name}"
  pass_count=$((pass_count + 1))
done < "${MATRIX}"

printf '[summary] passed=%d failed=%d\n' "${pass_count}" "${fail_count}"
[[ "${fail_count}" -eq 0 ]]
