#!/usr/bin/env sh
# common.sh — shared helpers for adr control-plane scripts
# Usage: . "$ADR_LIB/common.sh"  (or source via relative path)
# Zero third-party deps; POSIX sh only.

# Resolve skill root from a script under scripts/ or scripts/lib/
adr_skill_root() {
  _here=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd) || return 1
  case "$_here" in
    */scripts/lib) CDPATH= cd -- "$_here/../.." && pwd ;;
    */scripts) CDPATH= cd -- "$_here/.." && pwd ;;
    *) CDPATH= cd -- "$_here" && pwd ;;
  esac
}

adr_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

adr_warn() {
  printf 'warn: %s\n' "$*" >&2
}

adr_info() {
  printf '%s\n' "$*"
}

# Atomic write: write to temp then rename into place.
# Usage: adr_atomic_write <dest> < content via stdin
adr_atomic_write() {
  _dest=$1
  _dir=$(dirname -- "$_dest")
  mkdir -p "$_dir" || return 1
  _tmp=$(mktemp "${TMPDIR:-/tmp}/adr-write.XXXXXX") || return 1
  cat >"$_tmp" || { rm -f "$_tmp"; return 1; }
  mv -f "$_tmp" "$_dest"
}

# ISO-ish UTC timestamp for attempt ids
adr_utc_stamp() {
  date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%Y%m%dT%H%M%S
}

# Simple portable sha256 of a file (sha256sum or shasum)
adr_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    adr_die "need sha256sum or shasum"
  fi
}
