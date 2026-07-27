#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

prefix="${ZIL_INSTALL_PREFIX:-$HOME/.local}"
source_root="$ZIL_ROOT"
mode="copy"
profile="full"
version=""
build=true
install_tools=false
verify=true
force=false
prune_old=false
report=""
candidate=""
link_tmp=""
wrapper_tmp=""
state_tmp=""
activation_started=false
activation_complete=false
old_target=""
base=""
current=""

cleanup() {
  local rc=$?
  if [[ "$activation_started" == true && "$activation_complete" != true && -n "$current" ]]; then
    if [[ -n "$old_target" ]]; then
      local rollback_link="$base/.rollback.$$"
      rm -f "$rollback_link"
      if ln -s "$old_target" "$rollback_link"; then
        zil_replace_symlink "$rollback_link" "$current" || \
          zil_warn "failed to restore previous current pointer: $old_target"
      fi
    else
      rm -f "$current"
    fi
  fi
  [[ -z "$candidate" || ! -d "$candidate" ]] || rm -rf "$candidate"
  [[ -z "$link_tmp" ]] || rm -f "$link_tmp"
  [[ -z "$wrapper_tmp" ]] || rm -f "$wrapper_tmp"
  [[ -z "$state_tmp" ]] || rm -f "$state_tmp"
  return "$rc"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: bash scripts/install.sh [options]

Options:
  --prefix DIR          Installation prefix (default: ~/.local)
  --source DIR          Checkout or extracted bundle root (default: repository root)
  --mode copy|link      Copy a versioned root or link a development checkout
  --profile PROFILE     lean|full|extensions|legacy (default: full)
  --version VERSION     Override version from bundle metadata or lakefile.lean
  --no-build            Activate without resolving dependencies or building
  --install-tools       Allow setup to install Elan/Clojure CLI in user space
  --no-verify           Skip post-install structural verification
  --force               Install another immutable root for the same source identifier
  --prune-old           Remove inactive copied versions after activation
  --report FILE         ZIL-INSTALL-REPORT/1 output path

Copy mode installs under PREFIX/lib/zil-lean/versions/VERSION-SOURCE_ID and
atomically updates PREFIX/lib/zil-lean/current. Link mode points current at the
supplied development source root.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || zil_die '--prefix requires a value'
      prefix="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || zil_die '--source requires a value'
      source_root="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || zil_die '--mode requires a value'
      mode="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || zil_die '--profile requires a value'
      profile="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || zil_die '--version requires a value'
      version="$2"
      shift 2
      ;;
    --no-build)
      build=false
      shift
      ;;
    --install-tools)
      install_tools=true
      shift
      ;;
    --no-verify)
      verify=false
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    --prune-old)
      prune_old=true
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
      zil_die "unknown install option: $1"
      ;;
  esac
done

case "$mode" in copy|link) ;; *) zil_die "unsupported install mode: $mode" ;; esac
case "$profile" in lean|full|extensions|legacy) ;; *) zil_die "unsupported install profile: $profile" ;; esac

prefix="$(zil_abs_path "$prefix")"
source_root="$(zil_abs_path "$source_root")"
source_root="$(zil_canonical_dir "$source_root")" || zil_die "source directory does not exist: $source_root"
[[ -f "$source_root/lakefile.lean" && -f "$source_root/bin/zil" ]] || \
  zil_die 'source root is not a complete ZIL source tree'

metadata="$source_root/ZIL-BUNDLE-METADATA.tsv"
source_commit=""
if [[ -f "$metadata" ]]; then
  source_commit="$(awk -F '\t' '$1 == "source_commit" {print $2; exit}' "$metadata")"
  if [[ -z "$version" ]]; then
    version="$(awk -F '\t' '$1 == "version" {print $2; exit}' "$metadata")"
  fi
fi
if [[ -z "$source_commit" ]] && zil_command_exists git; then
  source_commit="$(git -C "$source_root" rev-parse HEAD 2>/dev/null || true)"
fi
if [[ -z "$version" ]]; then
  version="$(sed -n 's/.*version := v!"\([^"]*\)".*/\1/p' "$source_root/lakefile.lean" | sed -n '1p')"
fi
[[ -n "$version" ]] || zil_die 'unable to derive installation version'
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || zil_die "invalid installation version: $version"

if [[ "$source_commit" =~ ^[0-9a-fA-F]{12,}$ ]]; then
  source_id="${source_commit:0:12}"
elif [[ -f "$source_root/ZIL-BUNDLE-MANIFEST.tsv" ]]; then
  source_id="$(zil_sha256_file "$source_root/ZIL-BUNDLE-MANIFEST.tsv")"
  source_id="${source_id#sha256:}"
  source_id="${source_id:0:12}"
else
  source_id="$(zil_sha256_text "$version|$(zil_sha256_file "$source_root/lakefile.lean")")"
  source_id="${source_id#sha256:}"
  source_id="${source_id:0:12}"
fi
install_id="$version-$source_id"

base="$prefix/lib/zil-lean"
versions="$base/versions"
current="$base/current"
bin_dir="$prefix/bin"
share_dir="$prefix/share/zil-lean"
wrapper="$bin_dir/zil"
state="$share_dir/install.tsv"
report="${report:-$share_dir/install-report.tsv}"
report="$(zil_abs_path "$report")"
mkdir -p "$versions" "$bin_dir" "$share_dir"

if [[ -e "$current" && ! -L "$current" ]]; then
  zil_die "refusing to replace non-symlink current path: $current"
fi
if [[ -e "$wrapper" || -L "$wrapper" ]]; then
  if [[ ! -f "$wrapper" ]] || ! grep -q 'ZIL-INSTALL-WRAPPER/1' "$wrapper"; then
    zil_die "refusing to replace launcher without installer ownership marker: $wrapper"
  fi
fi

verify_bundle_manifest() {
  local root="$1"
  local manifest="$root/ZIL-BUNDLE-MANIFEST.tsv"
  [[ -f "$manifest" ]] || return 0
  local path bytes digest actual_bytes actual_digest
  while IFS=$'\t' read -r path bytes digest; do
    [[ "$path" == 'ZIL-BUNDLE-MANIFEST/1' || "$path" == version || "$path" == source_commit || "$path" == path ]] && continue
    [[ -n "$path" ]] || continue
    [[ -f "$root/$path" ]] || zil_die "bundle manifest file is missing: $path"
    actual_bytes="$(zil_file_size "$root/$path")"
    actual_digest="$(zil_sha256_file "$root/$path")"
    [[ "$actual_bytes" == "$bytes" ]] || zil_die "bundle file size mismatch: $path"
    [[ "$actual_digest" == "$digest" ]] || zil_die "bundle digest mismatch: $path"
  done < "$manifest"
}

copy_source_tree() {
  local from="$1" to="$2"
  mkdir -p "$to"
  if zil_command_exists tar; then
    (cd "$from" && tar \
      --exclude='./.git' --exclude='./.lake' --exclude='./.zil' \
      --exclude='./target' --exclude='./dist' -cf - .) | tar -xf - -C "$to"
  else
    cp -R "$from/." "$to/"
    rm -rf "$to/.git" "$to/.lake" "$to/.zil" "$to/target" "$to/dist"
  fi
}

write_install_metadata() {
  local root="$1"
  cat > "$root/.zil-install.tsv" <<EOF
ZIL-INSTALL-ROOT/1
version	$version
source_id	$source_id
install_id	$install_id
mode	$mode
profile	$profile
source	$(zil_tsv_escape "$source_root")
source_commit	$(zil_tsv_escape "$source_commit")
installed_epoch	$(zil_epoch)
EOF
}

prepare_root() {
  local root="$1"
  write_install_metadata "$root"
  chmod +x "$root/bin/"zil* "$root/bin/build-jar" \
    "$root/scripts/"*.sh "$root/scripts/lib/"*.sh 2>/dev/null || true
  if [[ "$build" == true ]]; then
    local args=(--profile "$profile" --prefix "$prefix")
    [[ "$install_tools" == true ]] && args+=(--install-tools)
    bash "$root/scripts/setup.sh" "${args[@]}"
  fi
}

verify_bundle_manifest "$source_root"
if [[ -L "$current" ]]; then
  old_target="$(readlink "$current" 2>/dev/null || true)"
fi

activated_root=""
if [[ "$mode" == copy ]]; then
  final_root="$versions/$install_id"
  if [[ -e "$final_root" ]]; then
    if [[ "$force" == true ]]; then
      install_id="$install_id-$(zil_epoch)-$$"
      final_root="$versions/$install_id"
    else
      zil_die "source version is already installed: $final_root"
    fi
  fi
  candidate="$versions/.$install_id.installing.$$"
  rm -rf "$candidate"
  copy_source_tree "$source_root" "$candidate"
  prepare_root "$candidate"
  mv "$candidate" "$final_root"
  candidate=""
  activated_root="$final_root"
else
  prepare_root "$source_root"
  activated_root="$source_root"
fi

# Prepare every activation artifact before changing the active pointer.
prefix_literal="$(printf '%q' "$prefix")"
wrapper_tmp="$wrapper.tmp.$$"
cat > "$wrapper_tmp" <<EOF
#!/usr/bin/env bash
# ZIL-INSTALL-WRAPPER/1
set -euo pipefail
ZIL_PREFIX=$prefix_literal
ZIL_CURRENT="\$ZIL_PREFIX/lib/zil-lean/current"
if [[ ! -x "\$ZIL_CURRENT/bin/zil" ]]; then
  printf '[zil] error: installed current root is unavailable: %s\n' "\$ZIL_CURRENT" >&2
  exit 2
fi
case "\${1:-}" in
  verify-install)
    shift
    ZIL_INSTALL_PREFIX="\$ZIL_PREFIX" exec bash "\$ZIL_CURRENT/scripts/verify-install.sh" "\$@"
    ;;
  uninstall)
    shift
    ZIL_INSTALL_PREFIX="\$ZIL_PREFIX" exec bash "\$ZIL_CURRENT/scripts/uninstall.sh" "\$@"
    ;;
  *)
    exec "\$ZIL_CURRENT/bin/zil" "\$@"
    ;;
esac
EOF
chmod +x "$wrapper_tmp"

state_tmp="$state.tmp.$$"
cat > "$state_tmp" <<EOF
ZIL-INSTALL-STATE/1
prefix	$(zil_tsv_escape "$prefix")
mode	$mode
version	$version
source_id	$source_id
install_id	$install_id
profile	$profile
source	$(zil_tsv_escape "$source_root")
source_commit	$(zil_tsv_escape "$source_commit")
install_root	$(zil_tsv_escape "$activated_root")
current	$(zil_tsv_escape "$current")
wrapper	$(zil_tsv_escape "$wrapper")
previous_target	$(zil_tsv_escape "$old_target")
installed_epoch	$(zil_epoch)
EOF

link_tmp="$base/.current.$$"
rm -f "$link_tmp"
ln -s "$activated_root" "$link_tmp"
zil_replace_symlink "$link_tmp" "$current"
link_tmp=""
activation_started=true
mv -f "$wrapper_tmp" "$wrapper"
wrapper_tmp=""
mv -f "$state_tmp" "$state"
state_tmp=""
activation_complete=true

if [[ "$prune_old" == true && "$mode" == copy ]]; then
  find "$versions" -mindepth 1 -maxdepth 1 -type d ! -path "$activated_root" -exec rm -rf {} +
fi

verification_status=skipped
if [[ "$verify" == true ]]; then
  if bash "$activated_root/scripts/verify-install.sh" --prefix "$prefix" --structural; then
    verification_status=pass
  else
    verification_status=fail
    zil_warn 'installation activated but structural verification failed'
  fi
fi

zil_mkdir_parent "$report"
{
  printf 'ZIL-INSTALL-REPORT/1\n'
  printf 'prefix\t%s\n' "$(zil_tsv_escape "$prefix")"
  printf 'mode\t%s\n' "$mode"
  printf 'version\t%s\n' "$version"
  printf 'source_id\t%s\n' "$source_id"
  printf 'install_id\t%s\n' "$install_id"
  printf 'profile\t%s\n' "$profile"
  printf 'source\t%s\n' "$(zil_tsv_escape "$source_root")"
  printf 'source_commit\t%s\n' "$(zil_tsv_escape "$source_commit")"
  printf 'install_root\t%s\n' "$(zil_tsv_escape "$activated_root")"
  printf 'wrapper\t%s\n' "$(zil_tsv_escape "$wrapper")"
  printf 'build\t%s\n' "$build"
  printf 'verification\t%s\n' "$verification_status"
  printf 'result\t%s\n' "$([[ "$verification_status" == fail ]] && printf fail || printf pass)"
} > "$report"

zil_log "installed ZIL $version ($mode) at $activated_root"
zil_log "launcher: $wrapper"
zil_log "install report: $report"
[[ "$verification_status" != fail ]]
