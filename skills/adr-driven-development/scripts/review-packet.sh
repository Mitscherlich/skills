#!/usr/bin/env sh
# review-packet.sh — compact human-facing summary of an ADR control-plane dir
# Usage: review-packet.sh --adr-dir PATH
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: review-packet.sh --adr-dir PATH
EOF
  exit 2
}

adr_dir=
while [ $# -gt 0 ]; do
  case "$1" in
    --adr-dir) adr_dir=$2; shift 2 ;;
    -h|--help) usage ;;
    *) adr_die "unknown arg: $1" ;;
  esac
done
[ -n "$adr_dir" ] || adr_die "--adr-dir required"
[ -d "$adr_dir" ] || adr_die "not a directory: $adr_dir"

plan="$adr_dir/plan.md"
progress="$adr_dir/progress.md"
run_dir="$adr_dir/run"

printf '# ADR review packet\n\n'
printf 'adr_dir: %s\n' "$adr_dir"
printf 'generated: %s\n\n' "$(adr_utc_stamp)"

if [ -f "$plan" ]; then
  printf '## Status\n\n'
  printf '```\n'
  sh "$HERE/status.sh" --plan "$plan" 2>/dev/null || sh "$HERE/status.sh" --plan "$plan" 2>&1 || true
  printf '```\n\n'
  printf '## Next action\n\n'
  printf '```\n'
  if [ -d "$run_dir" ]; then
    sh "$HERE/next-action.sh" --plan "$plan" --run-dir "$run_dir" 2>/dev/null || true
  else
    sh "$HERE/next-action.sh" --plan "$plan" 2>/dev/null || true
  fi
  printf '```\n\n'
else
  printf '## Status\n\nmissing plan.md\n\n'
fi

printf '## Artifacts\n\n'
if [ -d "$run_dir" ]; then
  n_report=$(find "$run_dir" -maxdepth 1 -name '*-report.md' 2>/dev/null | wc -l | tr -d ' ')
  n_acc=$(find "$run_dir" -maxdepth 1 -name '*-acceptance.md' 2>/dev/null | wc -l | tr -d ' ')
  n_arch=$(find "$run_dir/archive" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  printf -- '- reports: %s\n' "$n_report"
  printf -- '- acceptances: %s\n' "$n_acc"
  printf -- '- archived attempts: %s\n' "$n_arch"
else
  printf -- '- run/ absent\n'
fi

if [ -f "$progress" ]; then
  printf '\n## Progress tail\n\n'
  printf '```\n'
  tail -n 12 "$progress" 2>/dev/null || true
  printf '```\n'
fi

exit 0
