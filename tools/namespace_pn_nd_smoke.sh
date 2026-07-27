#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIL_BIN="${ROOT_DIR}/bin/zil"
MODEL="${ROOT_DIR}/examples/namespace-pn-nd-extension.zc"
LIBSET_DIR="${ROOT_DIR}/libsets/namespace-pn-nd"

TMP_DIR="$(mktemp -d /tmp/namespace-pn-nd-smoke.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "[fail] $*" >&2
  exit 1
}

echo "[info] running namespace+petrinet+n-dimensional smoke..."

PRE="${TMP_DIR}/namespace_pn_nd.pre.zc"
OUT="${TMP_DIR}/namespace_pn_nd.out"

"${ZIL_BIN}" preprocess "${MODEL}" "${PRE}" "${LIBSET_DIR}" >/dev/null
"${ZIL_BIN}" "${PRE}" > "${OUT}"

rg -Fq '"namespace_hierarchy_edges"' "${OUT}" || fail "missing namespace_hierarchy_edges query output"
rg -Fq '"namespace_visible_names"' "${OUT}" || fail "missing namespace_visible_names query output"
rg -Fq '"namespace_morphism_reachability"' "${OUT}" || fail "missing namespace_morphism_reachability query output"
rg -Fq '"namespace_resolution_witnesses"' "${OUT}" || fail "missing namespace_resolution_witnesses query output"

# Key expected witnesses from demo model.
rg -Fq 'ns:ctx:root_org' "${OUT}" || fail "missing root_org in output"
rg -Fq 'ns:ctx:finance_team' "${OUT}" || fail "missing finance_team in output"
rg -Fq 'ns:ctx:finance_api_ctx' "${OUT}" || fail "missing finance_api_ctx in output"
rg -Fq 'value:table' "${OUT}" || fail "missing table visibility signal"
rg -Fq 'nspn:token:tok_policy_lookup' "${OUT}" || fail "missing token in resolution witnesses"

echo "[ok] namespace+petrinet+n-dimensional smoke checks passed."
