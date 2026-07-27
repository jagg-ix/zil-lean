#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

report="$ZIL_ROOT/.zil/install-self-check.tsv"
quiet=false

usage() {
  cat <<'EOF'
Usage: bash scripts/self-check.sh [--report FILE] [--quiet]

Checks the installation, packaging, and test infrastructure without building Lean or
running the Clojure test suite. Optional parsers are used when Clojure, PowerShell,
Docker, or Make are available. If an optional parser is present, rejection is a
failure. The tracked-content privacy audit is always required.
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
      zil_die "unknown self-check option: $1"
      ;;
  esac
done

report="$(zil_abs_path "$report")"
zil_mkdir_parent "$report"
cd "$ZIL_ROOT"
rows="$(mktemp "${TMPDIR:-/tmp}/zil-self-check.XXXXXX")"
trap 'rm -f "$rows"' EXIT
failures=0

record() {
  local check="$1" required="$2" status="$3" detail="$4"
  printf '%s\t%s\t%s\t%s\n' \
    "$(zil_tsv_escape "$check")" "$required" "$status" \
    "$(zil_tsv_escape "$detail")" >> "$rows"
  if [[ "$required" == yes && "$status" != pass ]]; then
    failures=$((failures + 1))
  fi
  if [[ "$quiet" != true ]]; then
    printf '%-8s %-8s %-28s %s\n' "$status" "$required" "$check" "$detail"
  fi
}

required_files=(
  config/test-profiles.edn
  scripts/lib/common.sh
  scripts/self-check.sh
  scripts/public-content-audit.sh
  scripts/doctor.sh
  scripts/setup.sh
  scripts/test.sh
  scripts/package.sh
  scripts/install.sh
  scripts/verify-install.sh
  scripts/uninstall.sh
  scripts/install-lifecycle-test.sh
  scripts/setup.ps1
  scripts/test.ps1
  Dockerfile.test
  compose.test.yml
  Makefile
  TESTING.md
  INSTALL-BUNDLES.md
  PUBLIC-CONTENT-POLICY.md
  spec/install-test-infrastructure-v1.md
  spec/install-bundle-lifecycle-v1.md
)

for path in "${required_files[@]}"; do
  if [[ -f "$path" ]]; then
    record "file:$path" yes pass present
  else
    record "file:$path" yes fail missing
  fi
done

bash_files=(
  bin/zil bin/zil-legacy bin/build-jar
  scripts/lib/common.sh scripts/public-content-audit.sh scripts/doctor.sh
  scripts/setup.sh scripts/test.sh scripts/self-check.sh scripts/package.sh
  scripts/install.sh scripts/verify-install.sh scripts/uninstall.sh
  scripts/install-lifecycle-test.sh
)
for path in "${bash_files[@]}"; do
  if bash -n "$path"; then
    record "bash:$path" yes pass 'syntax accepted'
  else
    record "bash:$path" yes fail 'bash -n rejected the file'
  fi
done

privacy_report="$ZIL_ROOT/.zil/public-content-audit.tsv"
if bash scripts/public-content-audit.sh --quiet --report "$privacy_report"; then
  record public-content yes pass "$privacy_report"
else
  record public-content yes fail "$privacy_report"
fi

if zil_command_exists clojure && clojure -Sdescribe >/dev/null 2>&1; then
  if (cd "${TMPDIR:-/tmp}" && ZIL_ROOT="$ZIL_ROOT" \
      clojure -Sdeps '{:deps {}}' -M -e \
      '(require (quote clojure.edn)) (let [root (System/getenv "ZIL_ROOT")] (doseq [p ["config/test-profiles.edn" "port-gate.edn"]] (clojure.edn/read-string (slurp (str root "/" p)))))' \
      >/dev/null 2>&1); then
    record edn yes pass 'profile and port-gate EDN parsed'
  else
    record edn yes fail 'available Clojure EDN parser rejected a file'
  fi
else
  record edn optional skip 'official Clojure CLI unavailable'
fi

powershell_command=""
if zil_command_exists pwsh; then
  powershell_command=pwsh
elif zil_command_exists powershell; then
  powershell_command=powershell
fi
if [[ -n "$powershell_command" ]]; then
  if "$powershell_command" -NoProfile -Command \
      '$allErrors=@(); foreach ($path in @("scripts/setup.ps1","scripts/test.ps1")) { $tokens=$null; $parseErrors=$null; [System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors) > $null; if ($parseErrors) { $allErrors += $parseErrors } }; if ($allErrors.Count -gt 0) { exit 1 }' \
      >/dev/null 2>&1; then
    record powershell yes pass 'PowerShell parsers accepted setup and test scripts'
  else
    record powershell yes fail 'available PowerShell parser rejected a script'
  fi
else
  record powershell optional skip 'PowerShell unavailable'
fi

if zil_command_exists docker && docker compose version >/dev/null 2>&1; then
  if docker compose -f compose.test.yml config --quiet >/dev/null 2>&1; then
    record compose yes pass 'Compose configuration is valid'
  else
    record compose yes fail 'available Docker Compose rejected compose.test.yml'
  fi
else
  record compose optional skip 'Docker Compose unavailable'
fi

if zil_command_exists make; then
  if make -n help >/dev/null 2>&1; then
    record make yes pass 'Makefile help target parsed'
  else
    record make yes fail 'available Make rejected the Makefile'
  fi
else
  record make optional skip 'Make unavailable'
fi

if grep -q '^FROM ubuntu:24\.04$' Dockerfile.test \
   && grep -q '^ENTRYPOINT \["bash", "scripts/test.sh"\]$' Dockerfile.test; then
  record dockerfile yes pass 'base image and profile entry point are pinned'
else
  record dockerfile yes fail 'required Dockerfile pins are missing'
fi

if grep -q 'git archive --format=tar' scripts/package.sh \
   && grep -q 'ZIL-BUNDLE-MANIFEST/1' scripts/package.sh; then
  record source-bundle yes pass 'packager is commit-bound and manifest-producing'
else
  record source-bundle yes fail 'packager lacks committed-source or manifest contract'
fi

if grep -q 'ZIL-INSTALL-WRAPPER/1' scripts/install.sh \
   && grep -q 'MUST NOT delete the linked source tree' spec/install-bundle-lifecycle-v1.md; then
  record install-safety yes pass 'wrapper ownership and linked-source protection are declared'
else
  record install-safety yes fail 'installation lifecycle safety markers are incomplete'
fi

{
  printf 'ZIL-INSTALL-SELF-CHECK/1\n'
  printf 'root\t%s\n' "$(zil_tsv_escape "$ZIL_ROOT")"
  printf 'os\t%s\n' "$(zil_os)"
  printf 'arch\t%s\n' "$(zil_arch)"
  printf 'check\trequired\tstatus\tdetail\n'
  cat "$rows"
  printf 'failures\t%s\n' "$failures"
  printf 'result\t%s\n' "$([[ $failures -eq 0 ]] && printf pass || printf fail)"
} > "$report"

[[ "$quiet" == true ]] || zil_log "self-check report: $report"
if [[ $failures -eq 0 ]]; then
  exit 0
fi
exit 1
