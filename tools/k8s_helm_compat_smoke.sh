#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIL_BIN="${ROOT_DIR}/bin/zil"
LIBSET_DIR="${ROOT_DIR}/libsets/k8s-helm-compat"
POS_MODEL="${ROOT_DIR}/examples/kubernetes-compat.zc"
NEG_MODEL="${ROOT_DIR}/examples/kubernetes-compat-negative.zc"

TMP_DIR="$(mktemp -d /tmp/k8s-helm-compat-smoke.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "[fail] $*" >&2
  exit 1
}

run_model() {
  local model="$1"
  local pre="$2"
  local out="$3"
  "${ZIL_BIN}" preprocess "${model}" "${pre}" "${LIBSET_DIR}" >/dev/null
  "${ZIL_BIN}" "${pre}" >"${out}"
}

echo "[info] running k8s/helm compatibility smoke checks..."

POS_PRE="${TMP_DIR}/k8s-pos.pre.zc"
POS_OUT="${TMP_DIR}/k8s-pos.out"
NEG_PRE="${TMP_DIR}/k8s-neg.pre.zc"
NEG_OUT="${TMP_DIR}/k8s-neg.out"

run_model "${POS_MODEL}" "${POS_PRE}" "${POS_OUT}"
run_model "${NEG_MODEL}" "${NEG_PRE}" "${NEG_OUT}"

# Positive-path expectations.
rg -Fq "\"khc_releases\"" "${POS_OUT}" || fail "positive case missing khc_releases query output"
rg -Fq "\"khc_missing_required_values\" {:vars [\"?release\" \"?path\"], :rows []}" "${POS_OUT}" \
  || fail "positive case expected no missing required values"
rg -Fq "\"khc_drift_candidates\" {:vars [\"?release\" \"?res\"], :rows []}" "${POS_OUT}" \
  || fail "positive case expected no drift candidates"

# Negative-path expectations.
rg -Fq "\"khc_missing_required_values\"" "${NEG_OUT}" \
  || fail "negative case missing khc_missing_required_values query output"
rg -Fq "khc:release:staging_runtime" "${NEG_OUT}" \
  || fail "negative case missing expected release id"
rg -Fq "value:image_tag" "${NEG_OUT}" \
  || fail "negative case missing expected missing-required image_tag signal"
rg -Fq "\"khc_drift_candidates\"" "${NEG_OUT}" \
  || fail "negative case missing khc_drift_candidates query output"
rg -Fq "khc:resource:deployment_runtime_negative" "${NEG_OUT}" \
  || fail "negative case missing expected drift candidate resource"

echo "[ok] positive and negative k8s/helm compatibility checks passed."

