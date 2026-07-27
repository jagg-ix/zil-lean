#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

report="$ZIL_ROOT/.zil/public-content-audit.tsv"
quiet=false

usage() {
  cat <<'EOF'
Usage: bash scripts/public-content-audit.sh [--report FILE] [--quiet]

Scans tracked public text for common accidental disclosures:
- personal home-directory paths;
- conventional personal email addresses;
- GitHub repository URLs whose repository name indicates private material;
- PEM/OpenSSH private-key blocks.

The audit is intentionally generic. It does not contain or publish a list of private
research terms. Domain-specific research disclosure still requires human review.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
      zil_die "unknown public-content-audit option: $1"
      ;;
  esac
done

zil_command_exists git || zil_die 'git is required for the tracked-content audit'
cd "$ZIL_ROOT"
report="$(zil_abs_path "$report")"
zil_mkdir_parent "$report"
rows="$(mktemp "${TMPDIR:-/tmp}/zil-public-content.XXXXXX")"
files="$(mktemp "${TMPDIR:-/tmp}/zil-public-files.XXXXXX")"
trap 'rm -f "$rows" "$files"' EXIT

# The audit script is excluded so its detector expressions do not match themselves.
git ls-files -z -- \
  '*.md' '*.txt' '*.lean' '*.zc' '*.clj' '*.sh' '*.ps1' '*.edn' '*.json' '*.yaml' '*.yml' \
  | while IFS= read -r -d '' path; do
      [[ "$path" == scripts/public-content-audit.sh ]] && continue
      printf '%s\0' "$path"
    done > "$files"

findings=0

record_matches() {
  local kind="$1" expression="$2"
  local output
  output="$(xargs -0 grep -IEn -- "$expression" < "$files" 2>/dev/null || true)"
  [[ -n "$output" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    findings=$((findings + 1))
    printf '%s\t%s\n' "$kind" "$(zil_tsv_escape "$line")" >> "$rows"
    if [[ "$quiet" != true ]]; then
      printf '[zil] privacy finding: %s: %s\n' "$kind" "$line" >&2
    fi
  done <<< "$output"
}

record_matches personal-home-path '(^|[[:space:]"'"'"'=:(])(/Users/[^/[:space:]]+/|/home/[^/[:space:]]+/|[A-Za-z]:\\Users\\[^\\[:space:]]+\\)'
record_matches private-repository-url 'https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]*private[A-Za-z0-9_.-]*'
record_matches private-key-material '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|-----BEGIN OPENSSH PRIVATE KEY-----'

email_output="$(xargs -0 grep -IEno -- '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' < "$files" 2>/dev/null || true)"
if [[ -n "$email_output" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      *'@example.com'*|*'@example.org'*|*'@example.net'*|*'@users.noreply.github.com'*)
        continue
        ;;
    esac
    findings=$((findings + 1))
    printf 'email-address\t%s\n' "$(zil_tsv_escape "$line")" >> "$rows"
    if [[ "$quiet" != true ]]; then
      printf '[zil] privacy finding: email-address: %s\n' "$line" >&2
    fi
  done <<< "$email_output"
fi

{
  printf 'ZIL-PUBLIC-CONTENT-AUDIT/1\n'
  printf 'root\t%s\n' "$(zil_tsv_escape "$ZIL_ROOT")"
  printf 'finding_type\tlocation\n'
  cat "$rows"
  printf 'findings\t%s\n' "$findings"
  printf 'result\t%s\n' "$([[ $findings -eq 0 ]] && printf pass || printf fail)"
} > "$report"

[[ "$quiet" == true ]] || zil_log "public-content audit report: $report"
[[ $findings -eq 0 ]]
