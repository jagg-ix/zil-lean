#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

prefix="${ZIL_INSTALL_PREFIX:-$HOME/.local}"
purge=false
force=false
report=""

usage() {
  cat <<'EOF'
Usage: bash scripts/uninstall.sh [options]

Options:
  --prefix DIR    Installation prefix (default: ~/.local)
  --purge         Remove every copied version, current pointer, and install state
  --force         Continue when state is missing, but still protect unowned paths
  --report FILE   ZIL-UNINSTALL-REPORT/1 output path

A linked development source tree is never deleted. All managed paths are validated
before mutation. The launcher is removed only when it contains the
ZIL-INSTALL-WRAPPER/1 ownership marker.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || zil_die '--prefix requires a value'
      prefix="$2"
      shift 2
      ;;
    --purge)
      purge=true
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    --report)
      [[ $# -ge 2 ]] || zil_die '--report requires a value'
      report="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      zil_die "unknown uninstall option: $1"
      ;;
  esac
done

prefix="$(zil_abs_path "$prefix")"
base="$prefix/lib/zil-lean"
versions="$base/versions"
current="$base/current"
wrapper="$prefix/bin/zil"
share_dir="$prefix/share/zil-lean"
state="$share_dir/install.tsv"
report="${report:-$share_dir/uninstall-report.tsv}"
report="$(zil_abs_path "$report")"

state_value() {
  local key="$1"
  awk -F '\t' -v key="$key" '$1 == key {print $2; exit}' "$state" 2>/dev/null
}

if [[ ! -f "$state" ]]; then
  [[ "$force" == true ]] || zil_die "installation state is missing: $state"
elif [[ "$(sed -n '1p' "$state")" != 'ZIL-INSTALL-STATE/1' ]]; then
  zil_die "installation state has an unsupported schema: $state"
fi

mode="$(state_value mode)"
version="$(state_value version)"
install_root="$(state_value install_root)"

# Preflight every path before deleting anything.
if [[ -e "$wrapper" || -L "$wrapper" ]]; then
  if [[ ! -f "$wrapper" ]] || ! grep -q 'ZIL-INSTALL-WRAPPER/1' "$wrapper"; then
    zil_die "refusing to remove launcher without installer ownership marker: $wrapper"
  fi
fi
if [[ -e "$current" && ! -L "$current" ]]; then
  zil_die "refusing to remove non-symlink current path: $current"
fi
if [[ "$purge" != true && "$mode" == copy && -n "$install_root" ]]; then
  case "$install_root" in
    "$versions"/*) ;;
    *) zil_die "refusing to remove copied root outside the managed versions directory: $install_root" ;;
  esac
fi
if [[ "$mode" == link && -n "$install_root" && -f "$install_root/.zil-install.tsv" ]]; then
  if [[ "$(sed -n '1p' "$install_root/.zil-install.tsv")" != 'ZIL-INSTALL-ROOT/1' ]]; then
    zil_die "refusing to remove unowned linked-root metadata: $install_root/.zil-install.tsv"
  fi
fi

removed_wrapper=false
removed_current=false
removed_root=false
removed_versions=false
removed_root_metadata=false

if [[ -e "$wrapper" || -L "$wrapper" ]]; then
  rm -f "$wrapper"
  removed_wrapper=true
fi
if [[ -L "$current" ]]; then
  rm -f "$current"
  removed_current=true
fi

if [[ "$purge" == true ]]; then
  if [[ -d "$versions" ]]; then
    rm -rf "$versions"
    removed_versions=true
  fi
elif [[ "$mode" == copy && -n "$install_root" && -d "$install_root" ]]; then
  rm -rf "$install_root"
  removed_root=true
elif [[ "$mode" == link && -n "$install_root" && -f "$install_root/.zil-install.tsv" ]]; then
  rm -f "$install_root/.zil-install.tsv"
  removed_root_metadata=true
fi

rm -f "$state"
if [[ -d "$base" ]]; then
  rmdir "$versions" 2>/dev/null || true
  rmdir "$base" 2>/dev/null || true
fi

zil_mkdir_parent "$report"
{
  printf 'ZIL-UNINSTALL-REPORT/1\n'
  printf 'prefix\t%s\n' "$(zil_tsv_escape "$prefix")"
  printf 'mode\t%s\n' "$(zil_tsv_escape "$mode")"
  printf 'version\t%s\n' "$(zil_tsv_escape "$version")"
  printf 'install_root\t%s\n' "$(zil_tsv_escape "$install_root")"
  printf 'purge\t%s\n' "$purge"
  printf 'removed_wrapper\t%s\n' "$removed_wrapper"
  printf 'removed_current\t%s\n' "$removed_current"
  printf 'removed_root\t%s\n' "$removed_root"
  printf 'removed_versions\t%s\n' "$removed_versions"
  printf 'removed_root_metadata\t%s\n' "$removed_root_metadata"
  printf 'linked_source_deleted\tfalse\n'
  printf 'result\tpass\n'
} > "$report"

zil_log "ZIL installation removed from prefix: $prefix"
zil_log "uninstall report: $report"
