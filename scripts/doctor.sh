#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

profile="full"
report=""
quiet=false

usage() {
  cat <<'EOF'
Usage: bash scripts/doctor.sh [--profile PROFILE] [--report FILE] [--quiet]

Profiles:
  lean        Lean SDK and native commands
  full        Lean + Java + official Clojure CLI
  extensions  Java + official Clojure CLI
  container   Docker with Compose support
  legacy      Java/JAR or Clojure legacy runtime
  all         Full workbench plus Make and Docker

The report uses the deterministic tab-separated schema ZIL-DOCTOR/1.
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
    --quiet)
      quiet=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      zil_die "unknown doctor option: $1"
      ;;
  esac
done

case "$profile" in
  lean|full|extensions|container|legacy|all) ;;
  *) zil_die "unknown doctor profile: $profile" ;;
esac

rows="$(mktemp "${TMPDIR:-/tmp}/zil-doctor.XXXXXX")"
trap 'rm -f "$rows"' EXIT
failures=0

record() {
  local category="$1" name="$2" required="$3" status="$4" detail="$5"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(zil_tsv_escape "$category")" \
    "$(zil_tsv_escape "$name")" \
    "$required" "$status" \
    "$(zil_tsv_escape "$detail")" >> "$rows"
  if [[ "$required" == "yes" && "$status" != "ok" ]]; then
    failures=$((failures + 1))
  fi
  if [[ "$quiet" != true ]]; then
    printf '%-10s %-20s %-8s %s\n' "$status" "$name" "$required" "$detail"
  fi
}

check_command() {
  local name="$1" required="$2" detail
  shift 2
  if ! zil_command_exists "$name"; then
    record tool "$name" "$required" missing 'not found on PATH'
  elif detail="$(zil_first_line "$@")"; then
    record tool "$name" "$required" ok "$detail"
  else
    record tool "$name" "$required" invalid 'command exists but its version probe failed'
  fi
}

check_file() {
  local path="$1" required="$2"
  if [[ -f "$ZIL_ROOT/$path" ]]; then
    record repository "$path" "$required" ok 'present'
  else
    record repository "$path" "$required" missing 'file is absent'
  fi
}

check_lean() {
  check_command git yes git --version
  check_command curl yes curl --version
  check_command elan yes elan --version
  check_command lean yes lean --version
  check_command lake yes lake --version
  check_file lean-toolchain yes
  if [[ -f "$ZIL_ROOT/lean-toolchain" ]]; then
    record configuration lean-toolchain yes ok "$(tr -d '\r\n' < "$ZIL_ROOT/lean-toolchain")"
  fi
}

check_clojure() {
  local detail
  check_command java yes java --version
  if ! zil_command_exists clojure; then
    record tool clojure yes missing 'official Clojure CLI not found on PATH'
  elif detail="$(clojure -Sdescribe 2>&1 | sed -n '1p')"; then
    record tool clojure yes ok "tools.deps CLI: $detail"
  else
    record tool clojure yes invalid 'clojure exists but does not support -Sdescribe; install the official Clojure CLI'
  fi
  check_file deps.edn yes
}

check_docker() {
  local detail
  check_command docker yes docker --version
  if zil_command_exists docker; then
    if detail="$(docker compose version 2>&1 | sed -n '1p')"; then
      record tool docker-compose yes ok "$detail"
    else
      record tool docker-compose yes missing 'docker compose plugin is unavailable'
    fi
  fi
  check_file Dockerfile.test yes
  check_file compose.test.yml yes
}

check_legacy() {
  local has_runtime=false
  if zil_command_exists java && [[ -f "$ZIL_ROOT/dist/zil-standalone.jar" ]]; then
    record runtime legacy-java no ok 'Java and dist/zil-standalone.jar are available'
    has_runtime=true
  else
    record runtime legacy-java no unavailable 'standalone JAR path is not ready'
  fi
  if zil_command_exists clojure && clojure -Sdescribe >/dev/null 2>&1; then
    record runtime legacy-clojure no ok 'official Clojure CLI is available'
    has_runtime=true
  else
    record runtime legacy-clojure no unavailable 'official Clojure CLI is unavailable'
  fi
  if [[ "$has_runtime" == true ]]; then
    record runtime legacy-any yes ok 'at least one legacy runtime is available'
  else
    record runtime legacy-any yes missing 'build the standalone JAR or install the official Clojure CLI'
  fi
}

check_common_repository() {
  check_file lakefile.lean yes
  check_file bin/zil yes
  check_file config/test-profiles.edn yes
  check_file INSTALLING.md yes
  mkdir -p "$ZIL_ROOT/.zil" 2>/dev/null || true
  if [[ -d "$ZIL_ROOT/.zil" && -w "$ZIL_ROOT/.zil" ]]; then
    record repository .zil yes ok 'local report directory is writable'
  else
    record repository .zil yes invalid 'cannot create or write local report directory'
  fi
}

if [[ "$quiet" != true ]]; then
  printf 'ZIL environment doctor\n'
  printf 'profile: %s\nroot: %s\nos: %s\narch: %s\n\n' \
    "$profile" "$ZIL_ROOT" "$(zil_os)" "$(zil_arch)"
  printf '%-10s %-20s %-8s %s\n' status check required detail
fi

check_common_repository
case "$profile" in
  lean)
    check_lean
    ;;
  full)
    check_lean
    check_clojure
    ;;
  extensions)
    check_clojure
    ;;
  container)
    check_docker
    ;;
  legacy)
    check_legacy
    ;;
  all)
    check_lean
    check_clojure
    check_command make yes make --version
    check_docker
    check_legacy
    ;;
esac

if [[ -n "$report" ]]; then
  report="$(zil_abs_path "$report")"
  zil_mkdir_parent "$report"
  {
    printf 'ZIL-DOCTOR/1\n'
    printf 'profile\t%s\n' "$profile"
    printf 'root\t%s\n' "$(zil_tsv_escape "$ZIL_ROOT")"
    printf 'os\t%s\n' "$(zil_os)"
    printf 'arch\t%s\n' "$(zil_arch)"
    printf 'category\tname\trequired\tstatus\tdetail\n'
    cat "$rows"
    printf 'result\t%s\n' "$([[ $failures -eq 0 ]] && printf pass || printf fail)"
  } > "$report"
  [[ "$quiet" == true ]] || zil_log "doctor report: $report"
fi

if [[ $failures -eq 0 ]]; then
  [[ "$quiet" == true ]] || zil_log "profile '$profile' is ready"
  exit 0
fi

[[ "$quiet" == true ]] || zil_warn "$failures required checks failed"
exit 1
