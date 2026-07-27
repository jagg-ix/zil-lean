#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

group="all"
report=""
keep_workdir=false
skip_build=false
verbose=false
list_only=false
suite=""
build_completed=false

usage() {
  cat <<'EOF'
Usage: bash scripts/examples.sh [options]

Runs the documented example commands, group by group, exactly as the example
headers and READMEs advertise them. Steps whose toolchain is unavailable are
recorded as skips, never failures.

Options:
  --group lean|native|integration|legacy|all
  --report FILE       ZIL-EXAMPLES-REPORT/1 output path
  --keep-workdir      Preserve temporary generated files
  --skip-build        Skip lake build in groups that normally build
  --verbose           Stream successful step logs
  --list              List groups without running commands

Step logs are always persisted beside the report in <report>.logs/.

Exit codes:
  0  all executed steps passed (skips allowed)
  1  one or more executed steps failed
  2  invalid example-runner arguments
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --group)
      [[ $# -ge 2 ]] || zil_die '--group requires a value'
      group="$2"
      shift 2
      ;;
    --report)
      [[ $# -ge 2 ]] || zil_die '--report requires a value'
      report="$2"
      shift 2
      ;;
    --keep-workdir)
      keep_workdir=true
      shift
      ;;
    --skip-build)
      skip_build=true
      shift
      ;;
    --verbose)
      verbose=true
      shift
      ;;
    --list)
      list_only=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      zil_die "unknown examples option: $1"
      ;;
  esac
done

groups=(lean native integration legacy all)
if [[ "$list_only" == true ]]; then
  printf '%s\n' "${groups[@]}"
  exit 0
fi

case "$group" in
  lean|native|integration|legacy|all) ;;
  *) zil_die "unknown examples group: $group" ;;
esac

cd "$ZIL_ROOT"
workdir="$(zil_temp_dir)"
mkdir -p "$ZIL_ROOT/.zil/examples-reports"

if [[ -z "$report" ]]; then
  report="$ZIL_ROOT/.zil/examples-reports/$group-latest.tsv"
else
  report="$(zil_abs_path "$report")"
fi
zil_mkdir_parent "$report"
logs="${report}.logs"
rm -rf "$logs"
mkdir -p "$logs"

cleanup() {
  if [[ "$keep_workdir" == true ]]; then
    zil_log "examples workdir preserved: $workdir"
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

started="$(zil_epoch)"
failures=0
steps=0
skips=0

{
  printf 'ZIL-EXAMPLES-REPORT/1\n'
  printf 'group\t%s\n' "$group"
  printf 'root\t%s\n' "$(zil_tsv_escape "$ZIL_ROOT")"
  printf 'workdir\t%s\n' "$(zil_tsv_escape "$workdir")"
  printf 'logs\t%s\n' "$(zil_tsv_escape "$logs")"
  printf 'started_epoch\t%s\n' "$started"
  printf 'step\tdescription\texpected\texit\tstatus\tduration_seconds\tlog\tcommand\n'
} > "$report"

accepted_exit() {
  local expected="$1" actual="$2" item
  IFS=',' read -r -a codes <<< "$expected"
  for item in "${codes[@]}"; do
    [[ "$actual" == "$item" ]] && return 0
  done
  return 1
}

run_step() {
  local id="$1" description="$2" expected="$3"
  shift 3
  local full_id="${suite:+$suite-}$id"
  local log_file="$logs/$full_id.log"
  local begin end duration rc status command_text
  command_text="$(printf '%q ' "$@")"
  begin="$(zil_epoch)"
  steps=$((steps + 1))
  zil_log "[$full_id] $description"
  set +e
  "$@" >"$log_file" 2>&1
  rc=$?
  set -e
  end="$(zil_epoch)"
  duration=$((end - begin))
  if accepted_exit "$expected" "$rc"; then
    status=pass
    if [[ "$verbose" == true && -s "$log_file" ]]; then
      cat "$log_file"
    fi
  else
    status=fail
    failures=$((failures + 1))
    zil_warn "[$full_id] failed with exit $rc; expected $expected"
    if [[ -s "$log_file" ]]; then
      tail -n 80 "$log_file" >&2
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$full_id" "$(zil_tsv_escape "$description")" "$expected" "$rc" "$status" \
    "$duration" "$(zil_tsv_escape "$log_file")" \
    "$(zil_tsv_escape "$command_text")" >> "$report"
  return 0
}

skip_step() {
  local id="$1" description="$2" reason="$3"
  shift 3
  local full_id="${suite:+$suite-}$id"
  local command_text
  command_text="$(printf '%q ' "$@")"
  steps=$((steps + 1))
  skips=$((skips + 1))
  zil_log "[$full_id] skipped: $reason"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$full_id" "$(zil_tsv_escape "$description ($reason)")" 0 - skip 0 - \
    "$(zil_tsv_escape "$command_text")" >> "$report"
  return 0
}

run_build() {
  if [[ "$skip_build" != true && "$build_completed" != true ]]; then
    local failures_before="$failures"
    run_step build 'build Lean package' 0 lake build
    if [[ "$failures" == "$failures_before" ]]; then
      build_completed=true
    fi
  fi
}

have_lake() {
  zil_command_exists lake
}

have_legacy_runtime() {
  if zil_command_exists java && [[ -f "$ZIL_ROOT/dist/zil-standalone.jar" ]]; then
    return 0
  fi
  zil_command_exists clojure
}

run_lean_group() {
  suite=lean
  if ! have_lake; then
    skip_step all 'run the examples/lean progression' 'lake unavailable' \
      lake env lean examples/lean/01_FactsAndRelations.lean
    return 0
  fi
  run_build
  run_step 01 'facts and relations' 0 \
    lake env lean examples/lean/01_FactsAndRelations.lean
  run_step 02 'theorem-shaped graph rule' 0 \
    lake env lean examples/lean/02_TheoremShapedRule.lean
  run_step 03 'typed relation profiles' 0 \
    lake env lean examples/lean/03_TypedRule.lean
  run_step 04 'multi-step inference and querying' 0 \
    lake env lean examples/lean/04_MultiStepQuery.lean
  run_step 05-knowledge 'build the imported knowledge module' 0 \
    lake build KnowledgeBase
  run_step 05 'knowledge across Lean imports' 0 \
    lake env lean examples/lean/05_ImportedKnowledge.lean
  run_step 06 'a real formalization arc' 0 \
    lake env lean examples/lean/06_ProjectVerificationArc.lean
  run_step provenance 'derivation provenance walkthrough' 0 \
    lake env lean --run examples/provenance/DerivationDAG.lean
}

run_native_group() {
  suite=native
  if ! have_lake; then
    skip_step all 'run the native CLI example commands' 'lake unavailable' \
      bin/zil expand examples/quickstart-beginner.zc -
    return 0
  fi
  run_build
  run_step expand 'expand quickstart macros' 0 \
    bin/zil expand examples/quickstart-beginner.zc -
  run_step query-ci 'query CI over the quickstart model' 0 \
    bin/zil query-ci examples/quickstart-beginner.zc
  run_step trace 'trace quickstart evaluation' 0 \
    bin/zil trace examples/quickstart-beginner.zc -
  run_step dependency-graph 'render a dependency graph' 0 \
    bin/zil dependency-graph examples/impact/project.zc -
  run_step explain-query 'explain a provenance query' 0 \
    bin/zil explain-query examples/provenance/access.zc ancestors
  run_step claims-expand 'expand the formalization-claims model' 0 \
    bin/zil expand examples/native-cli/formalization-claims.zc -
  run_step claims-trace 'trace the formalization-claims model' 0 \
    bin/zil trace examples/native-cli/formalization-claims.zc -
  run_step claims-query-ci 'query CI over the formalization-claims model' 0 \
    bin/zil query-ci examples/native-cli/formalization-claims.zc
  run_step claims-explain 'explain the claim-requirements query' 0 \
    bin/zil explain-query examples/native-cli/formalization-claims.zc claim_requirements
  run_step claims-compile 'compile the formalization-claims model to Lean' 0 \
    bin/zil compile examples/native-cli/formalization-claims.zc \
    "$workdir/FormalizationClaims.lean" Zil.Generated.FormalizationClaims
  run_step claims-elaborate 'elaborate the compiled claims module' 0 \
    lake env lean "$workdir/FormalizationClaims.lean"
  run_step revision-summary 'summarize the revision log' 0 \
    bin/zil revision-summary examples/revision/release.zilr
  run_step revision-snapshot 'replay the revision log to revision 2' 0 \
    bin/zil snapshot examples/revision/release.zilr 2 -
  run_step revision-causal 'validate revision causal ordering' 0 \
    bin/zil causal-check examples/revision/release.zilr
}

run_integration_group() {
  suite=integration
  if ! have_lake; then
    skip_step all 'elaborate lean4-integration artifacts' 'lake unavailable' \
      lake env lean examples/lean4-integration/generated/KnowledgeCore.lean
    return 0
  fi
  run_build
  run_step knowledge-core 'elaborate the knowledge-core snapshot module' 0 \
    lake env lean examples/lean4-integration/generated/KnowledgeCore.lean
  run_step access-control 'elaborate the access-control snapshot module' 0 \
    lake env lean examples/lean4-integration/generated/AccessControl.lean
  run_step measurement-protocol 'elaborate the measurement-protocol module' 0 \
    lake env lean examples/lean4-integration/generated/MeasurementProtocol.lean
  if [[ -f examples/lean4-integration/generated/CategoryTheoryBridge.lean ]]; then
    run_step category-theory 'elaborate the category-theory bridge module' 0 \
      lake env lean examples/lean4-integration/generated/CategoryTheoryBridge.lean
  fi
  if have_legacy_runtime; then
    run_step regen-measurement 'regenerate the measurement-protocol module' 0 \
      bin/zil-legacy export-lean examples/lean4-integration/measurement-protocol-lts.zc \
      "$workdir/MeasurementProtocol.lean" Zil.Generated.MeasurementProtocol
    run_step regen-elaborate 'elaborate the regenerated module' 0 \
      lake env lean "$workdir/MeasurementProtocol.lean"
    run_step annotated-scan 'scan @zil annotations from Lean source' 0 \
      bin/zil-legacy embedded-scan examples/lean4-integration \
      "$workdir/annotated.zc" lean4.integration.annotated
  else
    skip_step regen-measurement 'regenerate the measurement-protocol module' \
      'legacy runtime unavailable' \
      bin/zil-legacy export-lean examples/lean4-integration/measurement-protocol-lts.zc \
      "$workdir/MeasurementProtocol.lean" Zil.Generated.MeasurementProtocol
    skip_step annotated-scan 'scan @zil annotations from Lean source' \
      'legacy runtime unavailable' \
      bin/zil-legacy embedded-scan examples/lean4-integration \
      "$workdir/annotated.zc" lean4.integration.annotated
  fi
}

run_legacy_model() {
  local id="$1" model="$2" libset="${3:-}"
  local pre="$workdir/$id.pre.zc"
  if [[ -n "$libset" ]]; then
    run_step "$id-pre" "preprocess $model" 0 \
      bin/zil-legacy preprocess "$model" "$pre" "$libset"
  else
    run_step "$id-pre" "preprocess $model" 0 \
      bin/zil-legacy preprocess "$model" "$pre"
  fi
  run_step "$id-run" "execute $model" 0 \
    bin/zil-legacy "$pre"
}

run_legacy_group() {
  suite=legacy
  if ! have_legacy_runtime; then
    skip_step all 'run the legacy preprocess examples' \
      'legacy runtime unavailable (needs java + dist/zil-standalone.jar, or clojure)' \
      bin/zil-legacy preprocess examples/kubernetes-compat.zc \
      "$workdir/kubernetes_compat.pre.zc" libsets/k8s-helm-compat
    return 0
  fi
  run_legacy_model k8s-pos examples/kubernetes-compat.zc libsets/k8s-helm-compat
  run_legacy_model k8s-neg examples/kubernetes-compat-negative.zc libsets/k8s-helm-compat
  run_legacy_model everparse examples/everparse-interop-demo.zc libsets/everparse-interop
  run_legacy_model config examples/config-declarative-macros.zc libsets/config-declarative
  run_legacy_model request-form examples/request-form-recursive.zc libsets/request-form
  run_step thm-arc 'theorem DSL pipeline on the formalization arc' 0 \
    bin/zil-legacy theorem-dsl-ci examples/formalization-arc-demo.zc "$workdir/thm-arc"
  run_step thm-incident 'theorem DSL pipeline on the incident demo' 0 \
    bin/zil-legacy theorem-dsl-ci examples/theorem-dsl-incident.zc "$workdir/thm-incident"
}

case "$group" in
  lean) run_lean_group ;;
  native) run_native_group ;;
  integration) run_integration_group ;;
  legacy) run_legacy_group ;;
  all)
    run_lean_group
    run_native_group
    run_integration_group
    run_legacy_group
    ;;
esac

finished="$(zil_epoch)"
{
  printf 'finished_epoch\t%s\n' "$finished"
  printf 'duration_seconds\t%s\n' "$((finished - started))"
  printf 'steps\t%s\n' "$steps"
  printf 'failures\t%s\n' "$failures"
  printf 'skips\t%s\n' "$skips"
  printf 'result\t%s\n' "$([[ $failures -eq 0 ]] && printf pass || printf fail)"
} >> "$report"

zil_log "examples report: $report"
zil_log "step logs: $logs"
if [[ $failures -eq 0 ]]; then
  zil_log "examples group '$group' passed ($steps steps, $skips skipped)"
  exit 0
fi

zil_warn "examples group '$group' failed ($failures of $steps steps)"
exit 1
