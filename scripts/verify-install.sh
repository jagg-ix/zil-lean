#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

prefix="${ZIL_INSTALL_PREFIX:-$HOME/.local}"
structural=true
smoke=false
report=""
quiet=false

usage() {
  cat <<'EOF'
Usage: bash scripts/verify-install.sh [options]

Options:
  --prefix DIR      Installation prefix (default: ~/.local)
  --structural      Verify state, wrapper, root, hashes, and self-check (default)
  --smoke           Also run the installed smoke test profile
  --report FILE     ZIL-INSTALL-VERIFY/1 output path
  --quiet           Suppress progress output
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || zil_die '--prefix requires a value'
      prefix="$2"
      shift 2
      ;;
    --structural)
      structural=true
      shift
      ;;
    --smoke)
      smoke=true
      shift
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
      zil_die "unknown verify-install option: $1"
      ;;
  esac
done

prefix="$(zil_abs_path "$prefix")"
state="$prefix/share/zil-lean/install.tsv"
wrapper="$prefix/bin/zil"
current="$prefix/lib/zil-lean/current"
report="${report:-$prefix/share/zil-lean/verify-report.tsv}"
report="$(zil_abs_path "$report")"
rows="$(mktemp "${TMPDIR:-/tmp}/zil-install-verify.XXXXXX")"
trap 'rm -f "$rows"' EXIT
failures=0

record() {
  local check="$1" status="$2" detail="$3"
  printf '%s\t%s\t%s\n' "$(zil_tsv_escape "$check")" "$status" "$(zil_tsv_escape "$detail")" >> "$rows"
  [[ "$status" == pass ]] || failures=$((failures + 1))
  if [[ "$quiet" != true ]]; then
    printf '%-8s %-28s %s\n' "$status" "$check" "$detail"
  fi
}

state_value() {
  local key="$1"
  awk -F '\t' -v key="$key" '$1 == key {print $2; exit}' "$state" 2>/dev/null
}

verify_manifest() {
  local root="$1"
  local manifest="$root/ZIL-BUNDLE-MANIFEST.tsv"
  if [[ ! -f "$manifest" ]]; then
    record bundle-manifest pass 'installation is from a checkout or a bundle without embedded manifest'
    return
  fi
  local path bytes digest actual_bytes actual_digest invalid=0 count=0
  while IFS=$'\t' read -r path bytes digest; do
    [[ "$path" == 'ZIL-BUNDLE-MANIFEST/1' || "$path" == version || "$path" == source_commit || "$path" == path ]] && continue
    [[ -n "$path" ]] || continue
    count=$((count + 1))
    if [[ ! -f "$root/$path" ]]; then
      invalid=$((invalid + 1))
      continue
    fi
    actual_bytes="$(zil_file_size "$root/$path")"
    actual_digest="$(zil_sha256_file "$root/$path")"
    if [[ "$actual_bytes" != "$bytes" || "$actual_digest" != "$digest" ]]; then
      invalid=$((invalid + 1))
    fi
  done < "$manifest"
  if [[ $invalid -eq 0 ]]; then
    record bundle-manifest pass "$count bundle files match size and SHA-256"
  else
    record bundle-manifest fail "$invalid of $count bundle files failed verification"
  fi
}

install_root=""
version=""
install_id=""
mode=""
profile=""

if [[ -f "$state" ]]; then
  if [[ "$(sed -n '1p' "$state")" == 'ZIL-INSTALL-STATE/1' ]]; then
    record state-schema pass "$state"
  else
    record state-schema fail 'state file has an unsupported schema'
  fi
  install_root="$(state_value install_root)"
  version="$(state_value version)"
  install_id="$(state_value install_id)"
  mode="$(state_value mode)"
  profile="$(state_value profile)"
else
  record state-schema fail "installation state is missing: $state"
fi

if [[ -f "$wrapper" && -x "$wrapper" ]] && grep -q 'ZIL-INSTALL-WRAPPER/1' "$wrapper"; then
  record wrapper pass "$wrapper"
else
  record wrapper fail 'launcher is missing, non-executable, or not installer-owned'
fi

if [[ -L "$current" || -d "$current" ]]; then
  resolved="$(zil_canonical_dir "$current" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    record current-root pass "$resolved"
    if [[ -n "$install_root" && "$resolved" != "$(zil_canonical_dir "$install_root" 2>/dev/null || printf '%s' "$install_root")" ]]; then
      record state-current-binding fail 'state install_root does not match the active current root'
    else
      record state-current-binding pass 'state and active root agree'
    fi
    install_root="$resolved"
  else
    record current-root fail 'current root cannot be resolved'
  fi
else
  record current-root fail "current pointer is missing: $current"
fi

if [[ -n "$install_root" && -f "$install_root/.zil-install.tsv" ]]; then
  root_version="$(awk -F '\t' '$1 == "version" {print $2; exit}' "$install_root/.zil-install.tsv")"
  root_install_id="$(awk -F '\t' '$1 == "install_id" {print $2; exit}' "$install_root/.zil-install.tsv")"
  if [[ -n "$version" && "$root_version" == "$version" ]]; then
    record root-version pass "version $version"
  else
    record root-version fail "root version '$root_version' does not match state '$version'"
  fi
  if [[ -n "$install_id" && "$root_install_id" == "$install_id" ]]; then
    record root-install-id pass "$install_id"
  else
    record root-install-id fail "root install id '$root_install_id' does not match state '$install_id'"
  fi
else
  record root-version fail 'active root lacks .zil-install.tsv'
  record root-install-id fail 'active root lacks .zil-install.tsv'
fi

if [[ -n "$install_root" && -x "$install_root/bin/zil" ]]; then
  record root-launcher pass "$install_root/bin/zil"
else
  record root-launcher fail 'active root launcher is not executable'
fi

if [[ "$structural" == true && -n "$install_root" ]]; then
  verify_manifest "$install_root"
  self_report="$prefix/share/zil-lean/self-check.tsv"
  if bash "$install_root/scripts/self-check.sh" --quiet --report "$self_report"; then
    record self-check pass "$self_report"
  else
    record self-check fail "$self_report"
  fi
fi

if [[ "$smoke" == true && -x "$wrapper" ]]; then
  smoke_report="$prefix/share/zil-lean/smoke-test.tsv"
  if "$wrapper" test --profile smoke --report "$smoke_report"; then
    record smoke-test pass "$smoke_report"
  else
    record smoke-test fail "$smoke_report"
  fi
fi

zil_mkdir_parent "$report"
{
  printf 'ZIL-INSTALL-VERIFY/1\n'
  printf 'prefix\t%s\n' "$(zil_tsv_escape "$prefix")"
  printf 'version\t%s\n' "$(zil_tsv_escape "$version")"
  printf 'install_id\t%s\n' "$(zil_tsv_escape "$install_id")"
  printf 'mode\t%s\n' "$(zil_tsv_escape "$mode")"
  printf 'profile\t%s\n' "$(zil_tsv_escape "$profile")"
  printf 'check\tstatus\tdetail\n'
  cat "$rows"
  printf 'failures\t%s\n' "$failures"
  printf 'result\t%s\n' "$([[ $failures -eq 0 ]] && printf pass || printf fail)"
} > "$report"

[[ "$quiet" == true ]] || zil_log "installation verification report: $report"
[[ $failures -eq 0 ]]
