#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

output="$ZIL_ROOT/dist"
format="tar.gz"
ref="HEAD"
version=""
report="$ZIL_ROOT/.zil/package-report.tsv"

usage() {
  cat <<'EOF'
Usage: bash scripts/package.sh [options]

Options:
  --output DIR          Output directory (default: dist)
  --format tar.gz|dir   Bundle format (default: tar.gz)
  --ref GIT_REF         Committed Git ref to package (default: HEAD)
  --version VERSION     Override package version from lakefile.lean
  --report FILE         ZIL-PACKAGE-REPORT/1 path

The bundle contains committed source files plus ZIL-SOURCE-BUNDLE/1 metadata,
ZIL-BUNDLE-MANIFEST/1 regular-file hashes, and SHA256SUMS. Uncommitted files are
never included. Git symlink modes remain in the archive but are not separate manifest
rows in v1.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || zil_die '--output requires a value'
      output="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || zil_die '--format requires a value'
      format="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || zil_die '--ref requires a value'
      ref="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || zil_die '--version requires a value'
      version="$2"
      shift 2
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
      zil_die "unknown package option: $1"
      ;;
  esac
done

case "$format" in
  tar.gz|dir) ;;
  *) zil_die "unsupported package format: $format" ;;
esac

for command in git tar; do
  zil_command_exists "$command" || zil_die "$command is required to build a source bundle"
done
if [[ "$format" == tar.gz ]]; then
  zil_command_exists gzip || zil_die 'gzip is required for tar.gz bundles'
fi

cd "$ZIL_ROOT"
commit="$(git rev-parse --verify "${ref}^{commit}")" || zil_die "cannot resolve Git ref: $ref"
if [[ -z "$version" ]]; then
  version="$(git show "${commit}:lakefile.lean" | sed -n 's/.*version := v!"\([^"]*\)".*/\1/p' | sed -n '1p')"
fi
[[ -n "$version" ]] || zil_die 'unable to derive package version from lakefile.lean'
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || zil_die "invalid package version: $version"

output="$(zil_abs_path "$output")"
report="$(zil_abs_path "$report")"
mkdir -p "$output" "$ZIL_ROOT/.zil"
workdir="$(zil_temp_dir)"
trap 'rm -rf "$workdir"' EXIT
bundle_name="zil-lean-$version"
bundle_root="$workdir/$bundle_name"

zil_log "exporting committed ref $ref ($commit)"
git archive --format=tar --prefix="$bundle_name/" "$commit" | tar -xf - -C "$workdir"

source_epoch="${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct "$commit")}"
cat > "$bundle_root/ZIL-BUNDLE-METADATA.tsv" <<EOF
ZIL-SOURCE-BUNDLE/1
name	zil-lean
version	$version
source_ref	$(zil_tsv_escape "$ref")
source_commit	$commit
source_epoch	$source_epoch
layout	source-complete
EOF

manifest="$bundle_root/ZIL-BUNDLE-MANIFEST.tsv"
checksums="$bundle_root/SHA256SUMS"
printf 'ZIL-BUNDLE-MANIFEST/1\n' > "$manifest"
printf 'version\t%s\n' "$version" >> "$manifest"
printf 'source_commit\t%s\n' "$commit" >> "$manifest"
printf 'path\tbytes\tsha256\n' >> "$manifest"
: > "$checksums"

while IFS= read -r relative; do
  [[ "$relative" == './ZIL-BUNDLE-MANIFEST.tsv' || "$relative" == './SHA256SUMS' ]] && continue
  path="$bundle_root/${relative#./}"
  digest="$(zil_sha256_file "$path")"
  bytes="$(zil_file_size "$path")"
  clean="${relative#./}"
  printf '%s\t%s\t%s\n' "$(zil_tsv_escape "$clean")" "$bytes" "$digest" >> "$manifest"
  printf '%s  %s\n' "${digest#sha256:}" "$clean" >> "$checksums"
done < <(cd "$bundle_root" && find . -type f -print | LC_ALL=C sort)

manifest_digest="$(zil_sha256_file "$manifest")"
checksums_digest="$(zil_sha256_file "$checksums")"
artifact=""
case "$format" in
  dir)
    artifact="$output/$bundle_name"
    temp_artifact="$output/.$bundle_name.tmp.$$"
    rm -rf "$temp_artifact"
    cp -R "$bundle_root" "$temp_artifact"
    rm -rf "$artifact"
    mv "$temp_artifact" "$artifact"
    ;;
  tar.gz)
    artifact="$output/$bundle_name.tar.gz"
    temp_artifact="$artifact.tmp.$$"
    if tar --help 2>/dev/null | grep -q -- '--sort'; then
      tar --sort=name --mtime="@$source_epoch" --owner=0 --group=0 --numeric-owner \
        -cf - -C "$workdir" "$bundle_name" | gzip -n > "$temp_artifact"
    else
      tar -cf - -C "$workdir" "$bundle_name" | gzip -n > "$temp_artifact"
    fi
    mv "$temp_artifact" "$artifact"
    ;;
esac

artifact_digest=""
if [[ -f "$artifact" ]]; then
  artifact_digest="$(zil_sha256_file "$artifact")"
else
  artifact_digest="$manifest_digest"
fi

zil_mkdir_parent "$report"
{
  printf 'ZIL-PACKAGE-REPORT/1\n'
  printf 'version\t%s\n' "$version"
  printf 'source_ref\t%s\n' "$(zil_tsv_escape "$ref")"
  printf 'source_commit\t%s\n' "$commit"
  printf 'format\t%s\n' "$format"
  printf 'artifact\t%s\n' "$(zil_tsv_escape "$artifact")"
  printf 'artifact_sha256\t%s\n' "$artifact_digest"
  printf 'manifest_sha256\t%s\n' "$manifest_digest"
  printf 'checksums_sha256\t%s\n' "$checksums_digest"
  printf 'result\tpass\n'
} > "$report"

zil_log "source bundle: $artifact"
zil_log "package report: $report"
