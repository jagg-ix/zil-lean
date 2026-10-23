#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

profile="smoke"
report=""
keep_workdir=false
skip_build=false
verbose=false
list_only=false
suite=""
build_completed=false

usage() {
  cat <<'EOF'
Usage: bash scripts/test.sh [options]

Options:
  --profile smoke|lean|all
  --report FILE       ZIL-TEST-REPORT/1 output path
  --keep-workdir      Preserve temporary generated files
  --skip-build        Skip lake build in profiles that normally build
  --verbose           Stream successful step logs
  --list              List profiles without running commands

Step logs are always persisted beside the report in <report>.logs/.

Exit codes:
  0  all selected steps passed
  1  one or more selected steps failed
  2  invalid test-runner arguments
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || zil_die '--profile requires a value'
      profile="$2"
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
      zil_die "unknown test option: $1"
      ;;
  esac
done

profiles=(smoke lean all)
if [[ "$list_only" == true ]]; then
  printf '%s\n' "${profiles[@]}"
  exit 0
fi

case "$profile" in
  smoke|lean|all) ;;
  *) zil_die "unknown test profile: $profile" ;;
esac

cd "$ZIL_ROOT"
workdir="$(zil_temp_dir)"
mkdir -p "$ZIL_ROOT/.zil/test-reports"

if [[ -z "$report" ]]; then
  report="$ZIL_ROOT/.zil/test-reports/$profile-latest.tsv"
else
  report="$(zil_abs_path "$report")"
fi
zil_mkdir_parent "$report"
logs="${report}.logs"
rm -rf "$logs"
mkdir -p "$logs"

cleanup() {
  if [[ "$keep_workdir" == true ]]; then
    zil_log "test workdir preserved: $workdir"
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

started="$(zil_epoch)"
failures=0
steps=0

{
  printf 'ZIL-TEST-REPORT/1\n'
  printf 'profile\t%s\n' "$profile"
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

run_doctor() {
  local doctor_profile="$1"
  run_step doctor "validate $doctor_profile environment" 0 \
    bash scripts/doctor.sh --profile "$doctor_profile" --quiet \
    --report "$workdir/${suite:-run}-doctor-$doctor_profile.tsv"
}

run_build() {
  if [[ "$skip_build" != true && "$build_completed" != true ]]; then
    local failures_before="$failures"
    run_step lean-build 'build Lean package' 0 lake build
    if [[ "$failures" == "$failures_before" ]]; then
      build_completed=true
    fi
  fi
}

run_lean_suite() {
  suite=lean
  run_doctor lean
  run_build
  run_step lean-tests 'run native Lean test executable' 0 lake exe zilLeanTests
  run_step native-compile 'compile a ZIL source to Lean' 0 \
    bin/zil compile examples/authorization/access.zc \
    "$workdir/GeneratedAccess.lean" Test.Install.GeneratedAccess
  run_step generated-elaboration 'elaborate generated Lean source' 0 \
    lake env lean "$workdir/GeneratedAccess.lean"
  run_step native-authorize 'evaluate native authorization' 0 \
    bin/zil authorize examples/authorization/access.zc \
    doc:readme viewer user:11
  run_step native-impact 'evaluate native impact graph' 0 \
    bin/zil impact examples/impact/project.zc lean:Parser.parse
  run_step macro-matrix 'expand, compile and typecheck every macro library against its golden' 0 \
    tools/macro_extension_matrix.sh --skip-build
  run_step extension-libraries 'row counts and evidence checks of the extension libraries' 0 \
    scripts/test-extension-libraries.sh --skip-build
  run_step model-substrate 'model substrate names, golden expansion and coherence counts' 0 \
    scripts/test-model-substrate.sh --skip-build
  run_step corpus 'every source compiles or fails as recorded' 0 \
    scripts/check-corpus.sh --skip-build
  run_step worker-parse 'parse through the native exchange worker' 0 \
    bash -c 'bin/zil worker --once < examples/exchange/parse-request.json | grep -q "\"status\":\"ok\""'
  run_step no-clojure 'no Clojure source, tool or call anywhere' 0 \
    scripts/check-no-clojure.sh
}

run_smoke_suite() {
  suite=smoke
  run_doctor lean
  run_build
  run_step smoke-compile 'compile checked-in source' 0 \
    bin/zil compile examples/authorization/access.zc "$workdir/Smoke.lean" Test.Smoke
  run_step smoke-authorize 'run native authorization' 0 \
    bin/zil authorize examples/authorization/access.zc \
    doc:readme viewer user:11
  run_step smoke-worker 'parse through the native exchange worker' 0 \
    bash -c 'bin/zil worker --once < examples/exchange/parse-request.json | grep -q "\"status\":\"ok\""'
}

case "$profile" in
  smoke) run_smoke_suite ;;
  lean|all) run_lean_suite ;;
esac

finished="$(zil_epoch)"
{
  printf 'finished_epoch\t%s\n' "$finished"
  printf 'duration_seconds\t%s\n' "$((finished - started))"
  printf 'steps\t%s\n' "$steps"
  printf 'failures\t%s\n' "$failures"
  printf 'result\t%s\n' "$([[ $failures -eq 0 ]] && printf pass || printf fail)"
} >> "$report"

zil_log "test report: $report"
zil_log "step logs: $logs"
if [[ $failures -eq 0 ]]; then
  zil_log "profile '$profile' passed ($steps steps)"
  exit 0
fi

zil_warn "profile '$profile' failed ($failures of $steps steps)"
exit 1
