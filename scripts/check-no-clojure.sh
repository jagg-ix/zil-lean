#!/usr/bin/env bash
# Fail if anything in the repository needs Clojure to build, test, install or run.
#
#   scripts/check-no-clojure.sh
#
# ZIL is Lean. The Clojure runtime was removed (see spec/clojure-removal.md); this keeps it removed.
#   1. No tracked file is Clojure source or Clojure configuration: .clj .cljc .cljs .cljd, any .edn file, deps.edn,
#      project.clj, build.clj.
#   2. No tool, script, build file or container file calls Clojure or Leiningen, selects a deps alias, or reaches for
#      the removed legacy entry points. Full-line comments and prose are not calls.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
failures=0

files="$(git ls-files | grep -E '(\.(clj|cljc|cljs|cljd|edn)$|(^|/)(deps\.edn|project\.clj|build\.clj|bb\.edn)$)' || true)"
if [[ -n "$files" ]]; then
  echo "Clojure source or configuration is tracked:" >&2
  printf '  %s\n' $files >&2
  failures=$((failures + 1))
fi

# A call: the command word in command position, a deps alias, or a removed entry point. Case-sensitive on purpose:
# prose says "Clojure"; a command is lowercase.
pattern='(^|[;&|(`]|[[:space:]])(clojure|clj|lein|bb)([[:space:]]|$)|[[:space:]](-M|-X|-T):[a-z]|deps\.edn|zil-legacy|ZIL_LEGACY_MODE|zil\.cli|zil-standalone'
calls="$(
  git ls-files bin scripts tools Makefile Dockerfile.test compose.test.yml lakefile.lean .github .gitlab-ci.yml 2>/dev/null \
    | grep -v -e '^scripts/check-no-clojure.sh$' \
    | while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        grep -n -E "$pattern" "$file" 2>/dev/null | while IFS= read -r hit; do
          text="${hit#*:}"
          case "$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//')" in "#"*|"//"*|"--"*) continue ;; esac
          printf '%s:%s\n' "$file" "$hit"
        done || true
      done
)"
if [[ -n "$calls" ]]; then
  echo "these lines call Clojure:" >&2
  printf '%s\n' "$calls" | cut -c1-160 >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  exit 1
fi
echo "no Clojure: no source or configuration, and no call from $(git ls-files bin scripts tools Makefile Dockerfile.test compose.test.yml lakefile.lean | wc -l | tr -d ' ') tool and build files"
