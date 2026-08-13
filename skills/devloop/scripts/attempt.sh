#!/usr/bin/env sh
# attempt.sh — generate attempt ids and archive previous attempt artifacts
# Usage:
#   attempt.sh new [--prefix <p>]
#   attempt.sh archive --run-dir <dir> --attempt-id <id> [--patterns <glob...>]
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  attempt.sh new [--prefix PREFIX]
  attempt.sh archive --run-dir DIR --attempt-id ID
EOF
  exit 2
}

cmd_new() {
  prefix=att
  while [ $# -gt 0 ]; do
    case "$1" in
      --prefix) prefix=$2; shift 2 ;;
      -h|--help) usage ;;
      *) adr_die "unknown arg: $1" ;;
    esac
  done
  stamp=$(adr_utc_stamp)
  # random-ish suffix from pid + RANDOM if available
  suf=${RANDOM:-$$}
  printf '%s-%s-%s\n' "$prefix" "$stamp" "$suf"
}

cmd_archive() {
  run_dir=
  attempt_id=
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir) run_dir=$2; shift 2 ;;
      --attempt-id) attempt_id=$2; shift 2 ;;
      -h|--help) usage ;;
      *) adr_die "unknown arg: $1" ;;
    esac
  done
  [ -n "$run_dir" ] || adr_die "--run-dir required"
  [ -n "$attempt_id" ] || adr_die "--attempt-id required"
  [ -d "$run_dir" ] || adr_die "run-dir not a directory: $run_dir"

  dest="$run_dir/archive/$attempt_id"
  mkdir -p "$dest"
  # Move common product files that match previous attempt markers if present
  moved=0
  for f in "$run_dir"/*-report.md "$run_dir"/*-acceptance.md "$run_dir"/*-acceptance-prompt.md "$run_dir"/*-acceptance.log; do
    [ -e "$f" ] || continue
    base=$(basename -- "$f")
    mv -f "$f" "$dest/$base"
    moved=$((moved + 1))
  done
  printf 'archived=%s\n' "$moved"
  printf 'archive_dir=%s\n' "$dest"
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in
  new) cmd_new "$@" ;;
  archive) cmd_archive "$@" ;;
  -h|--help) usage ;;
  *) adr_die "unknown command: $cmd" ;;
esac
