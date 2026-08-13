#!/usr/bin/env sh
# next-action.sh — emit the next coordinator action from plan status + run dir
# Usage: next-action.sh --plan PATH [--run-dir DIR]
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: next-action.sh --plan PATH [--run-dir DIR]
EOF
  exit 2
}

plan=
run_dir=
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) plan=$2; shift 2 ;;
    --run-dir) run_dir=$2; shift 2 ;;
    -h|--help) usage ;;
    *) adr_die "unknown arg: $1" ;;
  esac
done
[ -n "$plan" ] || adr_die "--plan required"
[ -f "$plan" ] || adr_die "plan not found: $plan"

# shellcheck disable=SC1091
status_out=$(sh "$HERE/status.sh" --plan "$plan") || {
  # status may fail if multiple open; still parse
  true
}
eval "$(printf '%s\n' "$status_out" | grep -E '^(open_id|open_name|open|done|pending|paused)=')"

if [ "${open:-0}" -eq 0 ]; then
  if [ "${pending:-0}" -gt 0 ]; then
    printf 'action=advance_next_pending\n'
    printf 'reason=no open slice but pending remain\n'
    printf 'read=%s\n' "$plan"
    exit 0
  fi
  if [ "${paused:-0}" -gt 0 ]; then
    printf 'action=resolve_paused\n'
    printf 'reason=all non-done slices are paused\n'
    printf 'read=%s\n' "$plan"
    exit 0
  fi
  printf 'action=finalize\n'
  printf 'reason=all slices done\n'
  printf 'read=%s\n' "$plan"
  exit 0
fi

printf 'action=work_open_slice\n'
printf 'slice_id=%s\n' "$open_id"
printf 'slice_name=%s\n' "$open_name"
printf 'read=%s\n' "$plan"

if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
  # Heuristic: presence of report without acceptance => need review
  reports=$(find "$run_dir" -maxdepth 1 -name '*-report.md' 2>/dev/null | wc -l | tr -d ' ')
  accepts=$(find "$run_dir" -maxdepth 1 -name '*-acceptance.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$reports" -gt 0 ] && [ "$accepts" -lt "$reports" ]; then
    printf 'phase_hint=review\n'
  elif [ -f "$(dirname "$plan")/next-goal.md" ]; then
    printf 'phase_hint=impl\n'
  else
    printf 'phase_hint=compile_goal\n'
  fi
  printf 'run_dir=%s\n' "$run_dir"
else
  printf 'phase_hint=compile_goal\n'
fi
exit 0
