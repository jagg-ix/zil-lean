#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIL_BIN="${ROOT_DIR}/bin/zil"
EXTRACTOR="${ROOT_DIR}/tools/extract_aws_overview_model_inputs.py"
BASE_MODEL="${ROOT_DIR}/examples/generated/aws-overview-model-inputs.zc"
POS_ADDON="${ROOT_DIR}/examples/aws-compat-positive.zc"
NEG_ADDON="${ROOT_DIR}/examples/aws-compat-negative.zc"

TMP_DIR="$(mktemp -d /tmp/aws-overview-compat-smoke.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "[fail] $*" >&2
  exit 1
}

echo "[info] extracting AWS baseline model from pdf..."
python3 "${EXTRACTOR}" >/dev/null

[[ -f "${BASE_MODEL}" ]] || fail "missing baseline model: ${BASE_MODEL}"
[[ -f "${POS_ADDON}" ]] || fail "missing positive addon: ${POS_ADDON}"
[[ -f "${NEG_ADDON}" ]] || fail "missing negative addon: ${NEG_ADDON}"

POS_COMBINED="${TMP_DIR}/aws_pos_combined.zc"
NEG_COMBINED="${TMP_DIR}/aws_neg_combined.zc"
POS_OUT="${TMP_DIR}/aws_pos.out"
NEG_OUT="${TMP_DIR}/aws_neg.out"

cat "${BASE_MODEL}" "${POS_ADDON}" > "${POS_COMBINED}"
cat "${BASE_MODEL}" "${NEG_ADDON}" > "${NEG_COMBINED}"

"${ZIL_BIN}" "${POS_COMBINED}" > "${POS_OUT}"
"${ZIL_BIN}" "${NEG_COMBINED}" > "${NEG_OUT}"

# Positive expectations: ready, no missing markers.
rg -Fq "aws:model:prod_target" "${POS_OUT}" || fail "positive: target not present"
rg -Fq ":relation :compat_ready" "${POS_OUT}" || fail "positive: compat_ready missing"
if rg -Fq ":relation :missing_required_" "${POS_OUT}"; then
  fail "positive: unexpected missing_required_* facts present"
fi
if rg -Fq ":relation :has_missing_any" "${POS_OUT}"; then
  fail "positive: unexpected has_missing_any fact present"
fi

# Negative expectations: explicit missing markers + no compat_ready.
rg -Fq "aws:model:staging_target" "${NEG_OUT}" || fail "negative: target not present"
rg -Fq ":relation :missing_required_service" "${NEG_OUT}" || fail "negative: missing_required_service not found"
rg -Fq "nonexistent_stream_router" "${NEG_OUT}" || fail "negative: missing service id not found"
rg -Fq ":relation :missing_required_region" "${NEG_OUT}" || fail "negative: missing_required_region not found"
rg -Fq "antarctica_1" "${NEG_OUT}" || fail "negative: missing region id not found"
rg -Fq ":relation :missing_required_control_category" "${NEG_OUT}" || fail "negative: missing_required_control_category not found"
rg -Fq "value:quantum" "${NEG_OUT}" || fail "negative: missing control category not found"
rg -Fq ":relation :missing_required_config_key" "${NEG_OUT}" || fail "negative: missing_required_config_key not found"
if rg -Fq "aws:model:staging_target" "${NEG_OUT}" && rg -Fq ":relation :compat_ready" "${NEG_OUT}"; then
  fail "negative: compat_ready should not be present"
fi

echo "[ok] aws overview compatibility smoke checks passed (positive + negative)."
