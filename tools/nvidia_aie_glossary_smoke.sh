#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIL_BIN="${ROOT_DIR}/bin/zil"
EXTRACTOR="${ROOT_DIR}/tools/extract_nvidia_aie_glossary_inputs.py"
JSON_OUT="${ROOT_DIR}/examples/generated/nvidia-aie-glossary-inputs.json"
ZC_OUT="${ROOT_DIR}/examples/generated/nvidia-aie-glossary-inputs.zc"

TMP_DIR="$(mktemp -d /tmp/nvidia-aie-glossary-smoke.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "[fail] $*" >&2
  exit 1
}

echo "[info] extracting NVIDIA AIE glossary model..."
python3 "${EXTRACTOR}" >/dev/null

[[ -f "${JSON_OUT}" ]] || fail "missing json output: ${JSON_OUT}"
[[ -f "${ZC_OUT}" ]] || fail "missing zc output: ${ZC_OUT}"

python3 - "${JSON_OUT}" <<'PY'
import json, sys
p = sys.argv[1]
obj = json.load(open(p, encoding='utf-8'))
stats = obj.get('stats', {})
sections = obj.get('sections', [])
terms = obj.get('terms', [])
meta = obj.get('meta', {})
section_ids = {s.get('id') for s in sections}
required = {
    'glossary',
    'architecture-specific-terms',
    'licensing-terms',
    'deployment-terms',
    'related-concepts',
    'performance-and-optimization',
}
if stats.get('terms_found', 0) < 80:
    raise SystemExit(f"too few terms: {stats.get('terms_found', 0)}")
if stats.get('sections_found', 0) < 6:
    raise SystemExit(f"too few sections: {stats.get('sections_found', 0)}")
missing = sorted(required - section_ids)
if missing:
    raise SystemExit(f"missing expected sections: {missing}")
term_names = {t.get('term','').lower() for t in terms}
for needle in ('cuda', 'gpu operator', 'cose', 'nvidia-smi'):
    # 'cose' is not expected in this glossary, keep checks to glossary-native terms.
    pass
for needle in ('cuda', 'gpu operator', 'nvidia-smi', 'tensorrt'):
    if needle not in term_names:
        raise SystemExit(f"missing expected term: {needle}")
if not meta.get('docs_version'):
    raise SystemExit('missing docs_version metadata')
print('[ok] json structure checks passed')
print('[ok] sections:', stats.get('sections_found'), 'terms:', stats.get('terms_found'))
PY

MODEL_OUT="${TMP_DIR}/nvidia_glossary.out"
"${ZIL_BIN}" "${ZC_OUT}" > "${MODEL_OUT}"

rg -Fq '"nvidia_glossary_sections"' "${MODEL_OUT}" || fail "missing nvidia_glossary_sections query output"
rg -Fq '"nvidia_glossary_terms"' "${MODEL_OUT}" || fail "missing nvidia_glossary_terms query output"
rg -Fq 'nvaie:section:glossary' "${MODEL_OUT}" || fail "missing glossary section facts in model output"
rg -Fq 'value:cuda' "${MODEL_OUT}" || fail "missing cuda term in model output"
rg -Fq 'value:gpu_operator' "${MODEL_OUT}" || fail "missing gpu_operator term in model output"

echo "[ok] nvidia AIE glossary smoke checks passed."
