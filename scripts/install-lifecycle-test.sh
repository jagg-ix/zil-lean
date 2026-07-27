#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

report="$ZIL_ROOT/.zil/install-lifecycle-test.tsv"
keep_workdir=false
verbose=false

usage() {
  cat <<'EOF'
Usage: bash scripts/install-lifecycle-test.sh [options]

Options:
  --report FILE    ZIL-INSTALL-LIFECYCLE-TEST/1 output path
  --keep-workdir   Preserve bundle, prefix, reports, and logs
  --verbose        Stream successful step logs

The test uses --no-build and performs no dependency downloads. It exercises package,
copy install, structural verification, installed self-check, forced replacement,
normal uninstall with inactive-version retention, and explicit purge.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      [[ $# -ge 2 ]] || zil_die '--report requires a value'
      report="$2"
      shift 2
      ;;
    --keep-workdir)
      keep_workdir=true
      shift
      ;;
    --verbose)
      verbose=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      zil_die "unknown lifecycle-test option: $1"
      ;;
  esac
done

report="$(zil_abs_path "$report")"
zil_mkdir_parent "$report"
workdir="$(zil_temp_dir)"
prefix="$workdir/prefix"
artifacts="$workdir/artifacts"
logs="${report}.logs"
mkdir -p "$prefix" "$artifacts" "$logs"
failures=0
steps=0
started="$(zil_epoch)"

cleanup() {
  if [[ "$keep_workdir" == true ]]; then
    zil_log "install lifecycle workdir preserved: $workdir"
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

{
  printf 'ZIL-INSTALL-LIFECYCLE-TEST/1\n'
  printf 'root\t%s\n' "$(zil_tsv_escape "$ZIL_ROOT")"
  printf 'prefix\t%s\n' "$(zil_tsv_escape "$prefix")"
  printf 'workdir\t%s\n' "$(zil_tsv_escape "$workdir")"
  printf 'started_epoch\t%s\n' "$started"
  printf 'step\tdescription\texit\tstatus\tduration_seconds\tlog\n'
} > "$report"

run_step() {
  local id="$1" description="$2"
  shift 2
  local log_file="$logs/$id.log" begin end rc status
  begin="$(zil_epoch)"
  steps=$((steps + 1))
  zil_log "[$id] $description"
  set +e
  "$@" > "$log_file" 2>&1
  rc=$?
  set -e
  end="$(zil_epoch)"
  if [[ $rc -eq 0 ]]; then
    status=pass
    if [[ "$verbose" == true && -s "$log_file" ]]; then cat "$log_file"; fi
  else
    status=fail
    failures=$((failures + 1))
    zil_warn "[$id] failed with exit $rc"
    tail -n 80 "$log_file" >&2 || true
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$(zil_tsv_escape "$description")" "$rc" "$status" \
    "$((end - begin))" "$(zil_tsv_escape "$log_file")" >> "$report"
}

cd "$ZIL_ROOT"
run_step package 'build directory source bundle from committed HEAD' \
  bash scripts/package.sh --format dir --output "$artifacts" \
  --report "$workdir/package-report.tsv"

bundle="$(find "$artifacts" -mindepth 1 -maxdepth 1 -type d -name 'zil-lean-*' | sed -n '1p')"
if [[ -z "$bundle" ]]; then
  failures=$((failures + 1))
  printf 'bundle-discovery\tlocate packaged directory\t2\tfail\t0\t-\n' >> "$report"
else
  run_step install 'install copied source bundle without build' \
    bash "$bundle/scripts/install.sh" --prefix "$prefix" --source "$bundle" \
    --mode copy --profile lean --no-build --no-verify
  run_step verify 'verify installed state, bundle hashes, and self-check' \
    bash "$prefix/lib/zil-lean/current/scripts/verify-install.sh" \
    --prefix "$prefix" --structural --report "$workdir/verify.tsv"
  run_step installed-self-check 'invoke self-check through installed wrapper' \
    "$prefix/bin/zil" self-check --report "$workdir/installed-self-check.tsv" --quiet
  run_step replace 'atomically replace the same installed version' \
    bash "$bundle/scripts/install.sh" --prefix "$prefix" --source "$bundle" \
    --mode copy --profile lean --no-build --force --no-verify
  run_step uninstall 'remove installer-owned wrapper and active copied root' \
    bash "$bundle/scripts/uninstall.sh" --prefix "$prefix" \
    --report "$workdir/uninstall.tsv"
  run_step absence 'confirm wrapper and current pointer are removed' \
    bash -c '[[ ! -e "$1/bin/zil" && ! -e "$1/lib/zil-lean/current" ]]' _ "$prefix"
  run_step inactive-retained 'confirm prior immutable copied root remains inactive' \
    bash -c '[[ $(find "$1/lib/zil-lean/versions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d " ") -eq 1 ]]' _ "$prefix"
  run_step purge 'remove every inactive copied version explicitly' \
    bash "$bundle/scripts/uninstall.sh" --prefix "$prefix" --purge --force \
    --report "$workdir/purge.tsv"
  run_step purge-absence 'confirm managed versions directory is absent or empty' \
    bash -c '[[ ! -d "$1/lib/zil-lean/versions" ]] || [[ -z $(find "$1/lib/zil-lean/versions" -mindepth 1 -maxdepth 1 -print -quit) ]]' _ "$prefix"
fi

finished="$(zil_epoch)"
{
  printf 'finished_epoch\t%s\n' "$finished"
  printf 'duration_seconds\t%s\n' "$((finished - started))"
  printf 'steps\t%s\n' "$steps"
  printf 'failures\t%s\n' "$failures"
  printf 'result\t%s\n' "$([[ $failures -eq 0 ]] && printf pass || printf fail)"
} >> "$report"

zil_log "install lifecycle report: $report"
zil_log "install lifecycle logs: $logs"
[[ $failures -eq 0 ]]
