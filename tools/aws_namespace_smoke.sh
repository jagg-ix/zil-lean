#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIL_BIN="${ROOT_DIR}/bin/zil"
MODEL="${ROOT_DIR}/examples/aws-namespace-compat.zc"
LIBSET_DIR="${ROOT_DIR}/libsets/aws-namespace"

TMP_DIR="$(mktemp -d /tmp/aws-namespace-smoke.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "[fail] $*" >&2
  exit 1
}

echo "[info] running aws+namespace scoped-compat smoke..."

PRE="${TMP_DIR}/aws_ns.pre.zc"
OUT="${TMP_DIR}/aws_ns.out"

"${ZIL_BIN}" preprocess "${MODEL}" "${PRE}" "${LIBSET_DIR}" >/dev/null
"${ZIL_BIN}" "${PRE}" > "${OUT}"

rg -Fq '"aws_ns_scoped_missing_services"' "${OUT}" || fail "missing aws_ns_scoped_missing_services query output"
rg -Fq '"aws_ns_scoped_missing_regions"' "${OUT}" || fail "missing aws_ns_scoped_missing_regions query output"
rg -Fq 'aws:model:dev_scoped' "${OUT}" || fail "expected dev_scoped in scoped-missing output"
rg -Fq 'aws:service:aws_cloudtrail' "${OUT}" || fail "expected missing scoped service cloudtrail"
rg -Fq 'aws:region:europe_ireland' "${OUT}" || fail "expected missing scoped region europe_ireland"
rg -Fq 'aws:model:prod_scoped' "${OUT}" || fail "expected prod_scoped facts"
rg -Fq '"aws_compat_ready_models"' "${OUT}" || fail "missing aws_compat_ready_models query output"

echo "[ok] aws+namespace scoped-compat smoke checks passed."
