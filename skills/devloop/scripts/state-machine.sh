#!/usr/bin/env sh
# state-machine.sh — slice status transitions for ADR loop
# Usage:
#   state-machine.sh validate --from S --to S
#   state-machine.sh can --from S --to S   # exit 0 if allowed
#   state-machine.sh transitions --from S
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  state-machine.sh validate --from STATUS --to STATUS
  state-machine.sh can --from STATUS --to STATUS
  state-machine.sh transitions --from STATUS

Canonical statuses: open | implementing | reviewing | done | pending | paused
EOF
  exit 2
}

# Normalize: done(...) -> done; paused(...) -> paused
normalize() {
  case "$1" in
    done*) printf 'done\n' ;;
    paused*) printf 'paused\n' ;;
    open|implementing|reviewing|pending) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Allowed edges. Use __ separator — never | (case OR) in patterns.
allowed() {
  from=$1
  to=$2
  case "${from}__${to}" in
    pending__open) return 0 ;;
    open__implementing) return 0 ;;
    open__paused) return 0 ;;
    open__pending) return 0 ;;
    implementing__reviewing) return 0 ;;
    implementing__open) return 0 ;;
    implementing__paused) return 0 ;;
    reviewing__done) return 0 ;;
    reviewing__open) return 0 ;;
    reviewing__paused) return 0 ;;
    paused__open) return 0 ;;
    paused__pending) return 0 ;;
    done__open) return 0 ;; # re-open
    *) return 1 ;;
  esac
}

parse_ft() {
  from=
  to=
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from=$2; shift 2 ;;
      --to) to=$2; shift 2 ;;
      -h|--help) usage ;;
      *) adr_die "unknown arg: $1" ;;
    esac
  done
  [ -n "$from" ] || adr_die "--from required"
  [ -n "$to" ] || adr_die "--to required"
  FROM=$(normalize "$from")
  TO=$(normalize "$to")
}

cmd_validate() {
  parse_ft "$@"
  if allowed "$FROM" "$TO"; then
    printf 'ok=1\nfrom=%s\nto=%s\n' "$FROM" "$TO"
    exit 0
  fi
  printf 'ok=0\nfrom=%s\nto=%s\nerror=illegal_transition\n' "$FROM" "$TO" >&2
  exit 1
}

cmd_can() {
  parse_ft "$@"
  if allowed "$FROM" "$TO"; then
    exit 0
  fi
  exit 1
}

cmd_transitions() {
  from=
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from=$2; shift 2 ;;
      -h|--help) usage ;;
      *) adr_die "unknown arg: $1" ;;
    esac
  done
  [ -n "$from" ] || adr_die "--from required"
  FROM=$(normalize "$from")
  for cand in open implementing reviewing done pending paused; do
    if allowed "$FROM" "$cand"; then
      printf '%s\n' "$cand"
    fi
  done
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in
  validate) cmd_validate "$@" ;;
  can) cmd_can "$@" ;;
  transitions) cmd_transitions "$@" ;;
  -h|--help) usage ;;
  *) adr_die "unknown command: $cmd" ;;
esac
