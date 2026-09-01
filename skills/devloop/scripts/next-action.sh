#!/usr/bin/env sh
# next-action.sh — 从控制面目录（或单独的 plan）推导协调者的下一步动作
#
# Usage:
#   next-action.sh --dir .devloop/<id>          # 全管线：intent → spec → plan → loop
#   next-action.sh --plan PATH [--run-dir DIR]  # 仅 loop 内切片层
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  next-action.sh --dir .devloop/<id>
  next-action.sh --plan PATH [--run-dir DIR]
EOF
  exit 2
}

dir=
plan=
run_dir=
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir=$2; shift 2 ;;
    --plan) plan=$2; shift 2 ;;
    --run-dir) run_dir=$2; shift 2 ;;
    -h|--help) usage ;;
    *) dl_die "unknown arg: $1" ;;
  esac
done

emit_gate_failures() {
  printf '%s\n' "$1" | grep '^fail=' || true
}

# ── 管线层：--dir 模式 ────────────────────────────────────────
if [ -n "$dir" ]; then
  [ -d "$dir" ] || dl_die "not a directory: $dir"
  intent="$dir/intent.md"
  spec="$dir/spec.md"
  plan="$dir/plan.md"
  [ -n "$run_dir" ] || run_dir="$dir/run"
  printf 'dir=%s\n' "$dir"

  if [ ! -f "$intent" ]; then
    printf 'stage=intent\naction=init_intent\n'
    printf 'reason=intent.md 不存在——先 devloop init 落盘活文档，再开始 grill\n'
    printf 'run=devloop init --id <id> --root %s\n' "$(dirname "$dir")"
    exit 0
  fi

  if gate_out=$(sh "$HERE/gate.sh" intent --file "$intent" 2>/dev/null); then
    intent_sha=$(printf '%s\n' "$gate_out" | sed -n 's/^sha256=//p')
    printf 'intent_sha256=%s\n' "$intent_sha"
  else
    printf 'stage=intent\naction=grill_intent\n'
    printf 'reason=intent 准出门禁未通过——继续 grill 并回写结论\n'
    printf 'read=%s\n' "$intent"
    emit_gate_failures "$gate_out"
    exit 0
  fi

  if [ ! -f "$spec" ]; then
    printf 'stage=intent\naction=compile_spec\n'
    printf 'reason=intent 门禁已过，尚未编译 spec.md\n'
    printf 'read=%s\n' "$intent"
    printf 'write=%s\n' "$spec"
    exit 0
  fi

  if gate_out=$(sh "$HERE/gate.sh" spec --file "$spec" --intent "$intent" 2>/dev/null); then
    spec_sha=$(printf '%s\n' "$gate_out" | sed -n 's/^sha256=//p')
    printf 'spec_sha256=%s\n' "$spec_sha"
  else
    printf 'stage=spec\naction=fix_spec\n'
    printf 'reason=spec 准出门禁未通过\n'
    printf 'read=%s\n' "$spec"
    emit_gate_failures "$gate_out"
    exit 0
  fi

  if [ ! -f "$plan" ]; then
    printf 'stage=spec\naction=compile_plan\n'
    printf 'reason=spec 门禁已过，尚未编译 plan.md\n'
    printf 'read=%s\n' "$spec"
    printf 'write=%s\n' "$plan"
    exit 0
  fi

  if ! gate_out=$(sh "$HERE/gate.sh" plan --file "$plan" --spec "$spec" 2>/dev/null); then
    printf 'stage=plan\naction=fix_plan\n'
    printf 'reason=plan 准出门禁未通过——不得进入 loop\n'
    printf 'read=%s\n' "$plan"
    emit_gate_failures "$gate_out"
    exit 0
  fi
  printf 'stage=loop\n'
fi

# ── 切片层 ───────────────────────────────────────────────────
[ -n "$plan" ] || dl_die "--dir or --plan required"
[ -f "$plan" ] || dl_die "plan not found: $plan"

status_out=$(sh "$HERE/status.sh" --plan "$plan") || true
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
