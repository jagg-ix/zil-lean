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
PRE_ZC="${TMP_DIR}/aws_extension_icons_combined.pre.zc"
OUT_TXT="${TMP_DIR}/aws_extension_icons_combined.out"
if [[ "${MODE}" == "full" ]]; then
  cat "${BASE_ZC}" "${ICON_CATALOG_ZC}" "${ICON_LINKS_ZC}" "${DEMO_ZC}" > "${COMBINED_ZC}"
else
  # Fast mode keeps icon semantics through service links, avoiding full asset catalog load.
  cat "${BASE_ZC}" "${ICON_LINKS_ZC}" "${DEMO_ZC}" > "${COMBINED_ZC}"
fi

"${ZIL_BIN}" preprocess "${COMBINED_ZC}" "${PRE_ZC}" "${ROOT_DIR}/libsets/aws-model" >/dev/null
"${ZIL_BIN}" "${PRE_ZC}" > "${OUT_TXT}"

rg -Fq "\"aws_compat_ready_models\"" "${OUT_TXT}" || fail "missing aws_compat_ready_models query output"
rg -Fq "aws:model:prod_extension" "${OUT_TXT}" || fail "expected prod_extension ready model"
rg -Fq "\"aws_compat_missing_services\" {:vars [\"?m\" \"?svc\"], :rows []}" "${OUT_TXT}" \
  || fail "expected no missing services"
rg -Fq "\"aws_compat_missing_regions\" {:vars [\"?m\" \"?region\"], :rows []}" "${OUT_TXT}" \
  || fail "expected no missing regions"
rg -Fq "\"aws_compat_missing_config_keys\" {:vars [\"?m\" \"?key\"], :rows []}" "${OUT_TXT}" \
  || fail "expected no missing config keys"
rg -Fq "\"aws_services_missing_icons\" {:vars [\"?svc\"], :rows []}" "${OUT_TXT}" \
  || fail "expected no missing icon links"
rg -Fq "\"aws_service_icon_links\"" "${OUT_TXT}" || fail "expected non-empty aws_service_icon_links query"

echo "[ok] aws extension + icon smoke checks passed (${MODE} mode)."
