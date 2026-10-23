#!/usr/bin/env bash
# Smoke test of the AWS plus namespace scoped-compatibility example, on the native engine alone.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIL_BIN="${ROOT_DIR}/bin/zil"
MODEL="${ROOT_DIR}/examples/aws-namespace-compat.zc"
LIBSET_DIR="${ROOT_DIR}/libsets/aws-namespace"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aws-namespace-smoke.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "[fail] $*" >&2
  exit 1
}

echo "[info] running aws+namespace scoped-compat smoke..."

EXPANDED="${TMP_DIR}/aws_ns.expanded.zc"
LEAN_OUT="${TMP_DIR}/aws_ns.lean"

"${ZIL_BIN}" expand "${MODEL}" "${EXPANDED}" --lib "${LIBSET_DIR}" >/dev/null
"${ZIL_BIN}" compile "${MODEL}" "${LEAN_OUT}" Zil.Smoke.AwsNamespace --lib "${LIBSET_DIR}" >/dev/null
(cd "${ROOT_DIR}" && lake env lean "${LEAN_OUT}")

witnesses() {
  "${ZIL_BIN}" explain-query "${EXPANDED}" "$1" | grep '^witness'
}

witnesses aws_ns_scoped_missing_services | grep -Fq 'aws.model.dev_scoped' || fail "expected dev_scoped in the scoped-missing services"
witnesses aws_ns_scoped_missing_services | grep -Fq 'aws.service.aws_cloudtrail' || fail "expected missing scoped service cloudtrail"
witnesses aws_ns_scoped_missing_regions | grep -Fq 'aws.region.europe_ireland' || fail "expected missing scoped region europe_ireland"
witnesses aws_compat_ready_models | grep -Fq 'aws.model.prod_scoped' || fail "expected prod_scoped among the compatible models"
if witnesses aws_compat_ready_models | grep -Fq 'aws.model.dev_scoped'; then fail "dev_scoped must not be compatible"; fi

echo "[ok] aws+namespace scoped-compat smoke checks passed."
