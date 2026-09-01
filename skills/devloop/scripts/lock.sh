#!/usr/bin/env sh
# lock.sh — atomic phase locks via mkdir
# Usage:
#   lock.sh acquire --run-dir DIR --phase PHASE [--timeout-sec N]
#   lock.sh release --run-dir DIR --phase PHASE
#   lock.sh check   --run-dir DIR --phase PHASE
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  lock.sh acquire --run-dir DIR --phase PHASE [--timeout-sec N]
  lock.sh release --run-dir DIR --phase PHASE
  lock.sh check   --run-dir DIR --phase PHASE
Phases: compile|impl|review|advance
EOF
  exit 2
}

valid_phase() {
  case "$1" in
    compile|impl|review|advance) return 0 ;;
    *) return 1 ;;
  esac
}

parse_common() {
  run_dir=
  phase=
  timeout=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir) run_dir=$2; shift 2 ;;
      --phase) phase=$2; shift 2 ;;
      --timeout-sec) timeout=$2; shift 2 ;;
      -h|--help) usage ;;
      *) dl_die "unknown arg: $1" ;;
    esac
  done
  [ -n "$run_dir" ] || dl_die "--run-dir required"
  [ -n "$phase" ] || dl_die "--phase required"
  valid_phase "$phase" || dl_die "invalid phase: $phase"
  mkdir -p "$run_dir"
  LOCK_PATH="$run_dir/.lock-$phase"
}

cmd_acquire() {
  parse_common "$@"
  end=$(( $(date +%s) + timeout ))
  while :; do
    if mkdir "$LOCK_PATH" 2>/dev/null; then
      printf '%s\n' "$$" >"$LOCK_PATH/owner"
      printf 'lock=acquired\nphase=%s\npath=%s\n' "$phase" "$LOCK_PATH"
      return 0
    fi
    if [ "$timeout" -le 0 ] || [ "$(date +%s)" -ge "$end" ]; then
      printf 'lock=busy\nphase=%s\npath=%s\n' "$phase" "$LOCK_PATH" >&2
      exit 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
}

cmd_release() {
  parse_common "$@"
  if [ -d "$LOCK_PATH" ]; then
    rm -rf "$LOCK_PATH"
    printf 'lock=released\nphase=%s\n' "$phase"
  else
    printf 'lock=absent\nphase=%s\n' "$phase"
  fi
}

cmd_check() {
  parse_common "$@"
  if [ -d "$LOCK_PATH" ]; then
    printf 'lock=held\nphase=%s\n' "$phase"
    exit 0
  fi
  printf 'lock=free\nphase=%s\n' "$phase"
  exit 1
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in
  acquire) cmd_acquire "$@" ;;
  release) cmd_release "$@" ;;
  check) cmd_check "$@" ;;
  -h|--help) usage ;;
  *) dl_die "unknown command: $cmd" ;;
esac
