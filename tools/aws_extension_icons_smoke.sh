#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIL_BIN="${ROOT_DIR}/bin/zil"
TMP_DIR="$(mktemp -d /tmp/aws-extension-icons-smoke.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

BASE_ZC="${ROOT_DIR}/examples/generated/aws-overview-model-inputs.zc"
ICON_CATALOG_ZC="${ROOT_DIR}/examples/generated/aws-icon-catalog.zc"
ICON_LINKS_ZC="${ROOT_DIR}/examples/generated/aws-service-icon-links.zc"
DEMO_ZC="${ROOT_DIR}/examples/aws-model-extension-with-icons.zc"
MODE="${1:-fast}"

fail() {
  echo "[fail] $*" >&2
  exit 1
}

echo "[info] extracting aws overview baseline..."
python3 "${ROOT_DIR}/tools/extract_aws_overview_model_inputs.py" >/dev/null

echo "[info] indexing aws icon package..."
python3 "${ROOT_DIR}/tools/index_aws_icon_package.py" >/dev/null

[[ -f "${BASE_ZC}" ]] || fail "missing baseline model"
[[ -f "${ICON_CATALOG_ZC}" ]] || fail "missing icon catalog model"
[[ -f "${ICON_LINKS_ZC}" ]] || fail "missing icon links model"
[[ -f "${DEMO_ZC}" ]] || fail "missing demo extension model"

COMBINED_ZC="${TMP_DIR}/aws_extension_icons_combined.zc"
EXPANDED_ZC="${TMP_DIR}/aws_extension_icons_combined.expanded.zc"
LEAN_OUT="${TMP_DIR}/aws_model_extension_icons.lean"
LIB="${ROOT_DIR}/libsets/aws-model"

# The source extension expands and compiles on the native macro path, and the generated Lean typechecks.
"${ZIL_BIN}" compile "${DEMO_ZC}" "${LEAN_OUT}" Zil.Smoke.AwsModel --lib "${LIB}" >/dev/null
(cd "${ROOT_DIR}" && lake env lean "${LEAN_OUT}")

# One module: the first file's MODULE line stays, the others' are dropped.
body() { grep -v '^MODULE ' "$1"; }
{
  cat "${BASE_ZC}"
  if [[ "${MODE}" == "full" ]]; then
    body "${ICON_CATALOG_ZC}"
  fi
  # Fast mode keeps icon semantics through service links, avoiding the full asset catalog load.
  body "${ICON_LINKS_ZC}"
  body "${DEMO_ZC}"
} > "${COMBINED_ZC}"

"${ZIL_BIN}" expand "${COMBINED_ZC}" "${EXPANDED_ZC}" --lib "${LIB}" >/dev/null

witness_count() {
  "${ZIL_BIN}" explain-query "${EXPANDED_ZC}" "$1" | awk -F'\t' '$1 == "witnesses" {print $2}'
}
witnesses() {
  "${ZIL_BIN}" explain-query "${EXPANDED_ZC}" "$1" | grep '^witness'
}

witnesses aws_compat_ready_models | grep -Fq "aws.model.prod_extension" || fail "expected prod_extension ready model"
[[ "$(witness_count aws_compat_missing_services)" == 0 ]] || fail "expected no missing services"
[[ "$(witness_count aws_compat_missing_regions)" == 0 ]] || fail "expected no missing regions"
[[ "$(witness_count aws_compat_missing_config_keys)" == 0 ]] || fail "expected no missing config keys"
[[ "$(witness_count aws_services_missing_icons)" == 0 ]] || fail "expected no missing icon links"
[[ "$(witness_count aws_service_icon_links)" -gt 0 ]] || fail "expected non-empty aws_service_icon_links query"

echo "[ok] aws extension + icon smoke checks passed (${MODE} mode)."
