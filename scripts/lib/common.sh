#!/usr/bin/env bash

# Shared helpers for ZIL bootstrap, diagnostics, packaging, and local test scripts.

ZIL_SCRIPT_LIB_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ZIL_ROOT="$(CDPATH= cd -- "$ZIL_SCRIPT_LIB_DIR/../.." && pwd)"

zil_log() {
  printf '[zil] %s\n' "$*"
}

zil_warn() {
  printf '[zil] warning: %s\n' "$*" >&2
}

zil_die() {
  printf '[zil] error: %s\n' "$*" >&2
  exit 2
}

zil_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

zil_first_line() {
  "$@" 2>&1 | sed -n '1p'
}

zil_os() {
  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    FreeBSD) printf 'freebsd' ;;
    CYGWIN*|MINGW*|MSYS*) printf 'windows-posix' ;;
    *) printf 'unknown' ;;
  esac
}

zil_arch() {
  uname -m 2>/dev/null || printf unknown
}

zil_temp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/zil-test.XXXXXX"
}

zil_epoch() {
  date +%s
}

zil_mkdir_parent() {
  local path="$1"
  local parent
  parent="$(dirname -- "$path")"
  mkdir -p "$parent"
}

zil_tsv_escape() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

zil_sha256_text() {
  if zil_command_exists sha256sum; then
    printf '%s' "$1" | sha256sum | awk '{print "sha256:" $1}'
  elif zil_command_exists shasum; then
    printf '%s' "$1" | shasum -a 256 | awk '{print "sha256:" $1}'
  elif zil_command_exists openssl; then
    printf '%s' "$1" | openssl dgst -sha256 | awk '{print "sha256:" $NF}'
  else
    zil_die 'sha256sum, shasum, or openssl is required'
  fi
}

zil_sha256_file() {
  local path="$1"
  if zil_command_exists sha256sum; then
    sha256sum "$path" | awk '{print "sha256:" $1}'
  elif zil_command_exists shasum; then
    shasum -a 256 "$path" | awk '{print "sha256:" $1}'
  elif zil_command_exists openssl; then
    openssl dgst -sha256 "$path" | awk '{print "sha256:" $NF}'
  else
    zil_die 'sha256sum, shasum, or openssl is required'
  fi
}

zil_file_size() {
  local path="$1"
  if stat -c %s "$path" >/dev/null 2>&1; then
    stat -c %s "$path"
  elif stat -f %z "$path" >/dev/null 2>&1; then
    stat -f %z "$path"
  else
    wc -c < "$path" | tr -d ' '
  fi
}

zil_abs_path() {
  local value="$1"
  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$PWD" "$value"
  fi
}

zil_canonical_dir() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  (CDPATH= cd -- "$path" && pwd -P)
}

# Replace a symlink path without allowing an existing symlink-to-directory to be
# interpreted as a destination directory. The temporary link must be in the same
# directory as the destination so the rename remains on one filesystem.
zil_replace_symlink() {
  local temporary="$1" destination="$2"
  if [[ ! -L "$temporary" ]]; then
    printf '[zil] error: temporary activation link is invalid: %s\n' "$temporary" >&2
    return 1
  fi
  if mv --help 2>/dev/null | grep -q -- '--no-target-directory'; then
    mv -Tf "$temporary" "$destination"
  elif mv -h "$temporary" "$destination" >/dev/null 2>&1; then
    return 0
  else
    printf '[zil] error: safe activation requires mv -T or mv -h on this platform\n' >&2
    return 1
  fi
}
