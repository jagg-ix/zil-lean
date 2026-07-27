#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

output="$ZIL_ROOT/dist"
ref="HEAD"
version=""
report="$ZIL_ROOT/.zil/release-assets-report.tsv"

usage() {
  cat <<'EOF'
Usage: bash scripts/release-assets.sh [options]

Options:
  --output DIR       Release asset directory (default: dist)
  --ref GIT_REF      Committed Git ref to package (default: HEAD)
  --version VERSION  Expected version; must match lakefile.lean at GIT_REF
  --report FILE      ZIL-RELEASE-ASSETS-REPORT/1 path

Creates a deterministic source tarball, a release-level SHA256SUMS file, and a
machine-readable release manifest suitable for upload to a GitHub Release.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || zil_die '--output requires a value'
      output="$2"
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
      zil_die "unknown release-assets option: $1"
      ;;
  esac
done

for command in git tar; do
  zil_command_exists "$command" || zil_die "$command is required to build release assets"
done

cd "$ZIL_ROOT"
commit="$(git rev-parse --verify "${ref}^{commit}")" || zil_die "cannot resolve Git ref: $ref"
declared_version="$(git show "${commit}:lakefile.lean" | sed -n 's/.*version := v!"\([^"]*\)".*/\1/p' | sed -n '1p')"
[[ -n "$declared_version" ]] || zil_die 'unable to derive release version from lakefile.lean'
if [[ -n "$version" && "$version" != "$declared_version" ]]; then
  zil_die "requested version $version does not match lakefile.lean version $declared_version at $ref"
fi
version="$declared_version"
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]] || zil_die "invalid release version: $version"

output="$(zil_abs_path "$output")"
report="$(zil_abs_path "$report")"
mkdir -p "$output" "$ZIL_ROOT/.zil"

package_report="$ZIL_ROOT/.zil/release-package-report.tsv"
bash "$SCRIPT_DIR/package.sh" \
  --format tar.gz \
  --output "$output" \
  --ref "$ref" \
  --version "$version" \
  --report "$package_report"

artifact_name="zil-lean-$version.tar.gz"
artifact="$output/$artifact_name"
[[ -f "$artifact" ]] || zil_die "packager did not create expected artifact: $artifact"

artifact_digest="$(zil_sha256_file "$artifact")"
artifact_bytes="$(zil_file_size "$artifact")"
checksum_file="$output/SHA256SUMS"
manifest_name="zil-lean-$version.release.tsv"
manifest="$output/$manifest_name"

checksum_tmp="$checksum_file.tmp.$$"
manifest_tmp="$manifest.tmp.$$"
printf '%s  %s\n' "${artifact_digest#sha256:}" "$artifact_name" > "$checksum_tmp"
{
  printf 'ZIL-RELEASE-ASSETS/1\n'
  printf 'name\tzil-lean\n'
  printf 'version\t%s\n' "$version"
  printf 'source_ref\t%s\n' "$(zil_tsv_escape "$ref")"
  printf 'source_commit\t%s\n' "$commit"
  printf 'artifact\t%s\n' "$artifact_name"
  printf 'artifact_bytes\t%s\n' "$artifact_bytes"
  printf 'artifact_sha256\t%s\n' "$artifact_digest"
  printf 'checksum_file\tSHA256SUMS\n'
} > "$manifest_tmp"
mv "$checksum_tmp" "$checksum_file"
mv "$manifest_tmp" "$manifest"

zil_mkdir_parent "$report"
{
  printf 'ZIL-RELEASE-ASSETS-REPORT/1\n'
  printf 'version\t%s\n' "$version"
  printf 'source_ref\t%s\n' "$(zil_tsv_escape "$ref")"
  printf 'source_commit\t%s\n' "$commit"
  printf 'artifact\t%s\n' "$(zil_tsv_escape "$artifact")"
  printf 'artifact_sha256\t%s\n' "$artifact_digest"
  printf 'checksums\t%s\n' "$(zil_tsv_escape "$checksum_file")"
  printf 'manifest\t%s\n' "$(zil_tsv_escape "$manifest")"
  printf 'result\tpass\n'
} > "$report"

zil_log "release artifact: $artifact"
zil_log "release checksums: $checksum_file"
zil_log "release manifest: $manifest"
zil_log "release-assets report: $report"
