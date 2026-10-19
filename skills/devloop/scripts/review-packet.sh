#!/usr/bin/env sh
# review-packet.sh — compact human-facing summary of a devloop control-plane dir
# Usage: review-packet.sh --devloop-dir PATH
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: review-packet.sh --devloop-dir PATH [--mode default|acpus]
EOF
  exit 2
}

devloop_dir=
requested_mode=
while [ $# -gt 0 ]; do
  case "$1" in
    --devloop-dir) devloop_dir=$2; shift 2 ;;
    --mode)
      [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$requested_mode" ] || { printf 'error: --mode 缺值或重复\n' >&2; exit 2; }
      requested_mode=$2; dl_validate_mode "$requested_mode"; shift 2 ;;
    -h|--help) usage ;;
    *) dl_die "unknown arg: $1" ;;
  esac
done
[ -n "$devloop_dir" ] || dl_die "--devloop-dir required"
[ -d "$devloop_dir" ] || dl_die "not a directory: $devloop_dir"

plan="$devloop_dir/plan.md"
progress="$devloop_dir/progress.md"
run_dir="$devloop_dir/run"
mode=$(dl_resolve_mode "$requested_mode" "$devloop_dir/intent.md" "$plan")

printf '# devloop review packet\n\n'
printf 'devloop_dir: %s\n' "$devloop_dir"
printf 'execution_mode: %s\n' "$mode"
if [ "$mode" = acpus ]; then
  printf 'Acpus 子任务状态需读取已记录的 Run；本摘要不查询 Runtime，也不将运行完成视为验收通过。\n'
  printf '执行参考：%s\n' "$HERE/../references/acpus-mode.md"
fi
printf 'generated: %s\n\n' "$(dl_utc_stamp)"

intent="$devloop_dir/intent.md"
spec="$devloop_dir/spec.md"

printf '## Pipeline\n\n'
printf '| 阶段 | 产物 | 门禁 |\n|---|---|---|\n'
gate_row() {
  _stage=$1
  _file=$2
  shift 2
  if [ ! -f "$_file" ]; then
    printf '| %s | 缺失 | - |\n' "$_stage"
    return
  fi
  if _out=$(sh "$HERE/gate.sh" "$_stage" --file "$_file" "$@" 2>/dev/null); then
    printf '| %s | %s | pass |\n' "$_stage" "$(basename "$_file")"
  else
    _n=$(printf '%s\n' "$_out" | grep -c '^fail=' || true)
    printf '| %s | %s | **FAIL**(%s) |\n' "$_stage" "$(basename "$_file")" "$(printf '%s' "$_n" | tr -d ' ')"
  fi
}
gate_row intent "$intent"
if [ -f "$intent" ]; then
  gate_row spec "$spec" --intent "$intent"
else
  gate_row spec "$spec"
fi
if [ -f "$spec" ]; then
  gate_row plan "$plan" --spec "$spec"
else
  gate_row plan "$plan"
fi
printf '\n'

if [ -f "$plan" ]; then
  printf '## Status\n\n'
  printf '```\n'
  sh "$HERE/status.sh" --plan "$plan" 2>/dev/null || sh "$HERE/status.sh" --plan "$plan" 2>&1 || true
  printf '```\n\n'
  printf '## Next action (pipeline)\n\n'
  printf '```\n'
  sh "$HERE/next-action.sh" --dir "$devloop_dir" 2>/dev/null || true
  printf '```\n\n'
  printf '## Next action (slice)\n\n'
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
if [ "$mode" = acpus ]; then
  printf -- '- Acpus evidence root: %s/acpus\n' "$run_dir"
  printf -- '- 以下为批次 attempt 目录，不代表运行状态或验收结论；Run ID 映射见 progress。\n'
  if [ -d "$run_dir/acpus" ]; then
    find "$run_dir/acpus" -mindepth 2 -maxdepth 2 -type d | sort
  fi
elif [ -d "$run_dir" ]; then
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

if [ -f "$devloop_dir/closeout.md" ]; then
  printf '\n## 收尾清单\n\n%s\n' "$devloop_dir/closeout.md"
  printf '知识去向、未验证项、发布状态和下一轮候选见该清单；此摘要不证明验收完成。\n'
fi

exit 0
