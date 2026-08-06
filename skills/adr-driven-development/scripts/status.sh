#!/usr/bin/env sh
# status.sh — project open/done/pending/paused counts from plan.md roadmap table
# Usage: status.sh --plan PATH [--json]
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: status.sh --plan PATH [--json]
EOF
  exit 2
}

plan=
json=0
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) plan=$2; shift 2 ;;
    --json) json=1; shift ;;
    -h|--help) usage ;;
    *) adr_die "unknown arg: $1" ;;
  esac
done
[ -n "$plan" ] || adr_die "--plan required"
[ -f "$plan" ] || adr_die "plan not found: $plan"

open_id=
open_name=
done_n=0
pending_n=0
paused_n=0
open_n=0

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
  esac
done <"$plan"

if [ "$json" -eq 1 ]; then
  printf '{\n'
  printf '  "open_id": "%s",\n' "$open_id"
  printf '  "open_name": "%s",\n' "$open_name"
  printf '  "open": %s,\n' "$open_n"
  printf '  "done": %s,\n' "$done_n"
  printf '  "pending": %s,\n' "$pending_n"
  printf '  "paused": %s\n' "$paused_n"
  printf '}\n'
else
  printf 'open_id=%s\n' "$open_id"
  printf 'open_name=%s\n' "$open_name"
  printf 'open=%s\n' "$open_n"
  printf 'done=%s\n' "$done_n"
  printf 'pending=%s\n' "$pending_n"
  printf 'paused=%s\n' "$paused_n"
fi

if [ "$open_n" -gt 1 ]; then
  adr_warn "multiple open slices: $open_n"
  exit 1
fi
exit 0
