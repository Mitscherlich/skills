#!/usr/bin/env sh
# status.sh — project open/done/pending/paused counts from plan.md roadmap table
# Usage: status.sh --plan PATH [--json]
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: status.sh --plan PATH [--json] [--mode default|acpus]
EOF
  exit 2
}

plan=
json=0
requested_mode=
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) plan=$2; shift 2 ;;
    --json) json=1; shift ;;
    --mode)
      [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$requested_mode" ] || { printf 'error: --mode 缺值或重复\n' >&2; exit 2; }
      requested_mode=$2; dl_validate_mode "$requested_mode"; shift 2 ;;
    -h|--help) usage ;;
    *) dl_die "unknown arg: $1" ;;
  esac
done
[ -n "$plan" ] || dl_die "--plan required"
[ -f "$plan" ] || dl_die "plan not found: $plan"
mode=$(dl_resolve_mode "$requested_mode" "$plan")

open_id=
open_name=
done_n=0
pending_n=0
paused_n=0
open_n=0
invalid_n=0

# Parse markdown table rows like: | F1 | name | open | ...
# shellcheck disable=SC2016
while IFS= read -r line; do
  case "$line" in
    \|[[:space:]]*F[0-9]*\|*)
      ;;
    *) continue ;;
  esac
  # strip leading |
  rest=${line#|}
  # fields split by |
  id=$(printf '%s\n' "$rest" | cut -d'|' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  name=$(printf '%s\n' "$rest" | cut -d'|' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  st=$(printf '%s\n' "$rest" | cut -d'|' -f3 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$id" in
    F[0-9]*) ;;
    *) continue ;;
  esac
  case "$st" in
    open)
      open_n=$((open_n + 1))
      open_id=$id
      open_name=$name
      ;;
    done*) done_n=$((done_n + 1)) ;;
    pending) pending_n=$((pending_n + 1)) ;;
    paused*) paused_n=$((paused_n + 1)) ;;
    *) invalid_n=$((invalid_n + 1)); dl_warn "非法 plan 状态：$id($st)" ;;
  esac
done <"$plan"
[ "$invalid_n" -eq 0 ] || exit 1

if [ "$json" -eq 1 ]; then
  printf '{\n'
  printf '  "execution_mode": "%s",\n' "$mode"
  printf '  "open_id": "%s",\n' "$open_id"
  printf '  "open_name": "%s",\n' "$open_name"
  printf '  "open": %s,\n' "$open_n"
  printf '  "done": %s,\n' "$done_n"
  printf '  "pending": %s,\n' "$pending_n"
  printf '  "paused": %s\n' "$paused_n"
  printf '}\n'
else
  printf 'execution_mode=%s\n' "$mode"
  printf 'open_id=%s\n' "$open_id"
  printf 'open_name=%s\n' "$open_name"
  printf 'open=%s\n' "$open_n"
  printf 'done=%s\n' "$done_n"
  printf 'pending=%s\n' "$pending_n"
  printf 'paused=%s\n' "$paused_n"
fi

if [ "$open_n" -gt 1 ]; then
  dl_warn "multiple open slices: $open_n"
  exit 1
fi
exit 0
