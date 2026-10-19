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
  next-action.sh --dir .devloop/<id> [--mode default|acpus]
  next-action.sh --plan PATH [--run-dir DIR] [--mode default|acpus]
EOF
  exit 2
}

dir=
plan=
run_dir=
requested_mode=
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir=$2; shift 2 ;;
    --plan) plan=$2; shift 2 ;;
    --run-dir) run_dir=$2; shift 2 ;;
    --mode)
      [ $# -ge 2 ] && [ -n "$2" ] && [ -z "$requested_mode" ] || { printf 'error: --mode 缺值或重复\n' >&2; exit 2; }
      requested_mode=$2; dl_validate_mode "$requested_mode"; shift 2 ;;
    -h|--help) usage ;;
    *) dl_die "unknown arg: $1" ;;
  esac
done

if [ -n "$dir" ]; then
  mode=$(dl_resolve_mode "$requested_mode" "$dir/intent.md" "$dir/plan.md")
else
  mode=$(dl_resolve_mode "$requested_mode" "$plan")
fi
printf 'execution_mode=%s\n' "$mode"

emit_gate_failures() {
  printf '%s\n' "$1" | grep '^fail=' || true
}

rejected() {
  grep -qE '^[-*] (结论|进入 loop 结论)[:：][[:space:]]*(打回|拒绝|不通过)' "$1"
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
    if sh "$HERE/gate.sh" intent --draft --file "$intent" >/dev/null 2>&1 && ! rejected "$intent"; then
      printf 'stage=intent\naction=await_intent_review\n'
      printf 'reason=内容检查通过，仅等待用户审阅；无需继续提问\n'
    else
      printf 'stage=intent\naction=grill_intent\n'
      printf 'reason=解决本阶段阻塞问题并同步当前决定\n'
    fi
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

  # 无标记的旧流程继续分开签署；新模板默认 joint。
  review_mode=$(sed -n 's/^review_mode:[[:space:]]*//p' "$intent" | head -n 1 | tr -d '[:space:]')
  [ -n "$review_mode" ] || review_mode=separate
  spec_signed=1
  if gate_out=$(sh "$HERE/gate.sh" spec --file "$spec" --intent "$intent" 2>/dev/null); then
    spec_sha=$(printf '%s\n' "$gate_out" | sed -n 's/^sha256=//p')
    printf 'spec_sha256=%s\n' "$spec_sha"
  else
    spec_signed=0
    if ! sh "$HERE/gate.sh" spec --draft --file "$spec" --intent "$intent" >/dev/null 2>&1 || rejected "$spec"; then
      printf 'stage=spec\naction=fix_spec\nreason=修订 spec 内容或处理打回意见\n'
      printf 'read=%s\n' "$spec"
      emit_gate_failures "$gate_out"
      exit 0
    fi
    if [ "$review_mode" = separate ]; then
      printf 'stage=spec\naction=await_spec_review\nreason=等待 spec 单独签署\n'
      printf 'read=%s\n' "$spec"
      emit_gate_failures "$gate_out"
      exit 0
    fi
    printf 'spec_sha256=%s\n' "$(dl_sha256_file "$spec")"
  fi

  if [ ! -f "$plan" ]; then
    printf 'stage=spec\naction=compile_plan\n'
    printf 'reason=spec 内容已检查，生成 plan 草稿；joint 模式在两份草稿齐后联审\n'
    printf 'read=%s\n' "$spec"
    printf 'write=%s\n' "$plan"
    exit 0
  fi

  if ! sh "$HERE/gate.sh" plan --draft --file "$plan" --spec "$spec" >/dev/null 2>&1 || rejected "$plan"; then
    gate_out=$(sh "$HERE/gate.sh" plan --file "$plan" --spec "$spec" 2>/dev/null) || true
    printf 'stage=plan\naction=fix_plan\n'
    printf 'reason=plan 准出门禁未通过——不得进入 loop\n'
    printf 'read=%s\n' "$plan"
    emit_gate_failures "$gate_out"
    exit 0
  fi
  if ! gate_out=$(sh "$HERE/gate.sh" plan --file "$plan" --spec "$spec" 2>/dev/null) || [ "$spec_signed" -eq 0 ]; then
    if [ "$review_mode" = joint ]; then action=await_design_review; else action=await_plan_review; fi
    printf 'stage=plan\naction=%s\nreason=等待实际审阅与执行授权；草稿检查不能授权点火\n' "$action"
    printf 'read=%s\nread=%s\n' "$spec" "$plan"
    emit_gate_failures "$gate_out"
    exit 0
  fi
  printf 'stage=loop\n'
fi

# ── 切片层 ───────────────────────────────────────────────────
[ -n "$plan" ] || dl_die "--dir or --plan required"
[ -f "$plan" ] || dl_die "plan not found: $plan"

status_out=$(sh "$HERE/status.sh" --plan "$plan") || dl_die 'plan 状态非法；不能推断下一步'
# plan 名称是数据，不能 eval 为 shell 代码。
open_id=$(printf '%s\n' "$status_out" | sed -n 's/^open_id=//p')
open_name=$(printf '%s\n' "$status_out" | sed -n 's/^open_name=//p')
open=$(printf '%s\n' "$status_out" | sed -n 's/^open=//p')
done_n=$(printf '%s\n' "$status_out" | sed -n 's/^done=//p')
pending=$(printf '%s\n' "$status_out" | sed -n 's/^pending=//p')
paused=$(printf '%s\n' "$status_out" | sed -n 's/^paused=//p')
[ "$((open + done_n + pending + paused))" -gt 0 ] || dl_die 'plan 没有切片；不能判定完成'

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
  printf 'read=%s\n' "$HERE/../references/closeout.md"
  exit 0
fi

printf 'action=work_open_slice\n'
printf 'slice_id=%s\n' "$open_id"
printf 'slice_name=%s\n' "$open_name"
printf 'read=%s\n' "$plan"

if [ "$mode" = acpus ]; then
  printf 'phase_hint=acpus_workflow\n'
  printf 'read=%s\n' "$HERE/../references/acpus-mode.md"
  printf 'reason=按当前切片的 Acpus Run 状态推进；不要使用 default 的报告数量或终端哨兵判定\n'
  exit 0
fi

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
