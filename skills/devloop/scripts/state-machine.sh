#!/usr/bin/env sh
# state-machine.sh — slice + stage transitions for devloop
# Usage:
#   state-machine.sh validate --from S --to S       # 切片状态
#   state-machine.sh can --from S --to S            # exit 0 if allowed
#   state-machine.sh transitions --from S
#   state-machine.sh stage-validate|stage-can|stage-transitions ...   # 管线阶段
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

  state-machine.sh stage-validate --from STAGE --to STAGE
  state-machine.sh stage-can --from STAGE --to STAGE
  state-machine.sh stage-transitions --from STAGE

Canonical slice statuses: open | implementing | reviewing | done | pending | paused
Canonical pipeline stages: intent | spec | plan | loop | done
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

# ── 管线阶段（intent → spec → plan → loop → done）────────────
stage_normalize() {
  case "$1" in
    intent|spec|plan|loop|done) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

stage_allowed() {
  case "${1}__${2}" in
    intent__spec) return 0 ;;   # gate intent 通过后编译 spec
    spec__plan) return 0 ;;     # gate spec 通过后编译 plan
    spec__intent) return 0 ;;   # spec 被打回，回到 grill
    plan__loop) return 0 ;;     # gate plan 通过 + 用户确认，进入 loop
    plan__spec) return 0 ;;     # plan 被打回，回到 spec 修订
    loop__done) return 0 ;;     # 全部切片验收通过
    loop__plan) return 0 ;;     # loop 中发现规划失效，重新编译 plan
    done__loop) return 0 ;;     # 收尾后被打回，重开 loop
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
      *) dl_die "unknown arg: $1" ;;
    esac
  done
  [ -n "$from" ] || dl_die "--from required"
  [ -n "$to" ] || dl_die "--to required"
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

cmd_stage_validate() {
  parse_ft "$@"
  FROM=$(stage_normalize "$FROM")
  TO=$(stage_normalize "$TO")
  if stage_allowed "$FROM" "$TO"; then
    printf 'ok=1\nkind=stage\nfrom=%s\nto=%s\n' "$FROM" "$TO"
    exit 0
  fi
  printf 'ok=0\nkind=stage\nfrom=%s\nto=%s\nerror=illegal_stage_transition\n' "$FROM" "$TO" >&2
  exit 1
}

cmd_stage_can() {
  parse_ft "$@"
  stage_allowed "$(stage_normalize "$FROM")" "$(stage_normalize "$TO")" || exit 1
  exit 0
}

cmd_stage_transitions() {
  from=
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from=$2; shift 2 ;;
      -h|--help) usage ;;
      *) dl_die "unknown arg: $1" ;;
    esac
  done
  [ -n "$from" ] || dl_die "--from required"
  FROM=$(stage_normalize "$from")
  for cand in intent spec plan loop done; do
    if stage_allowed "$FROM" "$cand"; then
      printf '%s\n' "$cand"
    fi
  done
}

cmd_transitions() {
  from=
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from=$2; shift 2 ;;
      -h|--help) usage ;;
      *) dl_die "unknown arg: $1" ;;
    esac
  done
  [ -n "$from" ] || dl_die "--from required"
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
  stage-validate) cmd_stage_validate "$@" ;;
  stage-can) cmd_stage_can "$@" ;;
  stage-transitions) cmd_stage_transitions "$@" ;;
  -h|--help) usage ;;
  *) dl_die "unknown command: $cmd" ;;
esac
