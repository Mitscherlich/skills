#!/usr/bin/env sh
# gate.sh — devloop 阶段准出门禁（intent / spec / plan / goal）
#
# Usage:
#   gate.sh intent --file PATH
#   gate.sh spec   --file PATH [--intent PATH]
#   gate.sh plan   --file PATH [--spec PATH]
#   gate.sh goal   --file PATH [--spec PATH] [--plan PATH]
#
# stdout: key=value；每条失败输出一行 fail=<id>: <说明>
# exit: 0 通过 / 1 未通过 / 2 参数错误
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage:
  gate.sh intent --file PATH
  gate.sh spec   --file PATH [--intent PATH]
  gate.sh plan   --file PATH [--spec PATH]
  gate.sh goal   --file PATH [--spec PATH] [--plan PATH]

Exit: 0 pass / 1 fail / 2 usage
EOF
  exit 2
}

# 参数/输入错误退 2（与「门禁未通过」的 1 区分）；门禁失败才用 1
usage_err() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

FAILN=0
CHECKN=0

pass_check() { CHECKN=$((CHECKN + 1)); }
fail_check() {
  CHECKN=$((CHECKN + 1))
  FAILN=$((FAILN + 1))
  printf 'fail=%s: %s\n' "$1" "$2"
}

# 标题按前缀匹配：允许 "## 确认记录（进入 loop 前必填）" 这类带补充说明的写法
# section_body FILE HEADING — 打印该二级标题下、到下一个 "## " 之前的正文
section_body() {
  awk -v h="$2" '
    index($0, h) == 1 { inside = 1; next }
    /^## / { if (inside) exit }
    inside { print }
  ' "$1"
}

# has_heading FILE HEADING
has_heading() {
  awk -v h="$2" 'index($0, h) == 1 { found = 1; exit } END { exit(found ? 0 : 1) }' "$1"
}

# field_value TEXT KEY — 从 "- KEY: value" / "KEY：value" 抽值
field_value() {
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*[-*][[:space:]]*$2[:：][[:space:]]*//p" | head -n 1
}

# loose_field_value TEXT KEY — 同 field_value，但列表前缀 -/* 可选（next-goal 的字段行是裸行）
loose_field_value() {
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*[-*]\\{0,1\\}[[:space:]]*${2}[:：][[:space:]]*//p" | head -n 1
}

# header_value FILE KEY — 抽行首裸 "KEY: value"（next-goal header 不是列表项）
header_value() {
  sed -n "s/^${2}[:：][[:space:]]*//p" "$1" | head -n 1 | sed 's/[[:space:]]*$//'
}

# goal_self_sha FILE — 删掉所有 GOAL_SHA256 行后再算 sha256（防自引用的既定口径）
goal_self_sha() {
  _gtmp=$(mktemp "${TMPDIR:-/tmp}/devloop-goalsha.XXXXXX") || return 1
  grep -v '^GOAL_SHA256[:：]' "$1" >"$_gtmp" || true
  dl_sha256_file "$_gtmp"
  rm -f "$_gtmp"
}

# 必备标题集合
check_headings() {
  _file=$1
  _prefix=$2
  shift 2
  for _h in "$@"; do
    if has_heading "$_file" "$_h"; then
      pass_check
    else
      fail_check "$_prefix-heading" "缺少标题：$_h"
    fi
  done
}

# 未填占位符：模板用 {{...}} 标记待填内容
check_placeholders() {
  _file=$1
  _prefix=$2
  if grep -q '{{' "$_file"; then
    _n=$(grep -c '{{' "$_file" | tr -d ' ')
    fail_check "$_prefix-placeholder" "仍有 $_n 处未填占位符 {{...}}"
  else
    pass_check
  fi
}

# 未完成标记
check_todo_markers() {
  _file=$1
  _prefix=$2
  if grep -qE 'TODO|TBD|FIXME|XXX|待填|待补|待定' "$_file"; then
    _hit=$(grep -nE 'TODO|TBD|FIXME|XXX|待填|待补|待定' "$_file" | head -n 1)
    fail_check "$_prefix-todo" "仍有未完成标记：$_hit"
  else
    pass_check
  fi
}

# 审阅/签署记录：需要 <who_key> 非空 且 结论: 通过
check_signoff() {
  _body=$1
  _prefix=$2
  _who_key=$3
  _who=$(field_value "$_body" "$_who_key")
  if [ -n "$_who" ]; then
    pass_check
  else
    fail_check "$_prefix-signer" "$_who_key 为空——人工审阅未落名"
  fi
  _verdict=$(field_value "$_body" "结论")
  case "$_verdict" in
    通过*) pass_check ;;
    "") fail_check "$_prefix-verdict" "结论 字段缺失" ;;
    *) fail_check "$_prefix-verdict" "结论 不是「通过」：$_verdict" ;;
  esac
}

# sha 绑定：BOUND_FILE 里的 KEY: <hex> 必须等于 SRC 的 sha256
check_sha_binding() {
  _bound=$1
  _key=$2
  _src=$3
  _prefix=$4
  # 绑定行可出现在 blockquote（"> key: v"）或列表项（"- key: v"）中
  _declared=$(sed -n "s/^[[:space:]>]*[-*]\{0,1\}[[:space:]]*$_key[:：][[:space:]]*//p" "$_bound" | head -n 1 | tr -d ' `')
  if [ -z "$_declared" ]; then
    fail_check "$_prefix-bind" "缺少 $_key 绑定行"
    return
  fi
  if [ ! -f "$_src" ]; then
    fail_check "$_prefix-bind" "上游文件不存在：$_src"
    return
  fi
  _actual=$(dl_sha256_file "$_src")
  if [ "$_declared" = "$_actual" ]; then
    pass_check
  else
    fail_check "$_prefix-bind" "$_key 与上游漂移（声明 ${_declared} != 实际 ${_actual}）——上游改过，需重新编译"
  fi
}

gate_intent() {
  file=$1
  check_headings "$file" I \
    '## 问题陈述' '## 期望结果' '## 影响范围' '## 约束与非目标' \
    '## 裁决记录' '## 未决问题' '## 人工审阅'
  check_placeholders "$file" I
  check_todo_markers "$file" I

  decisions=$(section_body "$file" '## 裁决记录' | grep -cE '^[0-9]+\. ' || true)
  decisions=$(printf '%s' "$decisions" | tr -d ' ')
  if [ "${decisions:-0}" -ge 1 ]; then
    pass_check
  else
    fail_check "I-decision" "裁决记录为空——grill 没有产出任何编号裁决"
  fi

  openq=$(section_body "$file" '## 未决问题' | grep -c '^- \[ \]' || true)
  openq=$(printf '%s' "$openq" | tr -d ' ')
  if [ "${openq:-0}" -eq 0 ]; then
    pass_check
  else
    fail_check "I-openq" "还有 $openq 条未决问题未勾选——grill 未收敛"
  fi

  check_signoff "$(section_body "$file" '## 人工审阅')" I 审阅人
}

gate_spec() {
  file=$1
  intent=$2
  check_headings "$file" S \
    '## 目标与验收终态' '## 需求' '## 设计' '## 关注点与冲突' '## 非目标' '## 签署记录'
  check_placeholders "$file" S
  check_todo_markers "$file" S

  # 需求表：至少一行 | R<n> | ...，且描述/验收标准/来源三列非空
  reqs=$(grep -cE '^\|[[:space:]]*R[0-9]+[[:space:]]*\|' "$file" || true)
  reqs=$(printf '%s' "$reqs" | tr -d ' ')
  if [ "${reqs:-0}" -ge 1 ]; then
    pass_check
  else
    fail_check "S-req" "没有任何 | R<n> | 需求行——spec 不 actionable"
  fi

  bad_rows=$(grep -E '^\|[[:space:]]*R[0-9]+[[:space:]]*\|' "$file" | awk -F'|' '
    { for (i = 3; i <= 5; i++) { g = $i; gsub(/[[:space:]]/, "", g); if (g == "") { print $2; next } } }
  ' | tr -d ' ' | tr '\n' ',' | sed 's/,$//')
  if [ -z "$bad_rows" ]; then
    pass_check
  else
    fail_check "S-req-cell" "需求行缺列（描述/验收标准/来源）：${bad_rows}"
  fi

  # 过程性残留：intent 的过程小节不得出现在 spec
  leaked=""
  for h in '## 裁决记录' '## 未决问题' '## 对话记录' '## 过程记录' '## 人工审阅'; do
    if has_heading "$file" "$h"; then
      leaked="$leaked $h"
    fi
  done
  if [ -z "$leaked" ]; then
    pass_check
  else
    fail_check "S-procedural" "spec 残留 intent 的过程性小节：${leaked}（应已编译掉）"
  fi

  if grep -qE '^[[:space:]]*(Q|A|问|答)[:：]|第[[:space:]]*[0-9]+[[:space:]]*轮|grill 记录' "$file"; then
    _hit=$(grep -nE '^[[:space:]]*(Q|A|问|答)[:：]|第[[:space:]]*[0-9]+[[:space:]]*轮|grill 记录' "$file" | head -n 1)
    fail_check "S-procedural-line" "spec 残留问答/轮次记录：$_hit"
  else
    pass_check
  fi

  check_signoff "$(section_body "$file" '## 签署记录')" S 签署人

  if [ -n "$intent" ]; then
    check_sha_binding "$file" intent_sha256 "$intent" S
  fi
}

gate_plan() {
  file=$1
  spec=$2
  check_headings "$file" P \
    '## 背景与目标' '## 需求追溯' '## 确认记录' '## 切片 roadmap' '## 每片统一 DoD'
  check_placeholders "$file" P
  check_todo_markers "$file" P

  # roadmap 表 + 唯一 open（复用 status.sh）
  status_out=$(sh "$HERE/status.sh" --plan "$file" 2>/dev/null) || status_out=""
  open_n=$(printf '%s\n' "$status_out" | sed -n 's/^open=//p')
  done_n=$(printf '%s\n' "$status_out" | sed -n 's/^done=//p')
  pending_n=$(printf '%s\n' "$status_out" | sed -n 's/^pending=//p')
  paused_n=$(printf '%s\n' "$status_out" | sed -n 's/^paused=//p')
  total=$(( ${open_n:-0} + ${done_n:-0} + ${pending_n:-0} + ${paused_n:-0} ))
  if [ "$total" -ge 1 ]; then
    pass_check
  else
    fail_check "P-roadmap" "切片 roadmap 没有任何 | F<n> | 行"
  fi
  if [ "${open_n:-0}" -eq 1 ]; then
    pass_check
  elif [ "${open_n:-0}" -eq 0 ] && [ "${done_n:-0}" -ge 1 ]; then
    pass_check
  else
    fail_check "P-open" "open 切片数为 ${open_n:-0}（进入 loop 时必须恰好 1 个）"
  fi

  # 非法状态词
  bad_status=$(awk -F'|' '
    /^\|[[:space:]]*F[0-9]+[[:space:]]*\|/ {
      s = $4; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (s !~ /^(open|pending|done|paused)/) { id = $2; gsub(/[[:space:]]/, "", id); printf "%s(%s) ", id, s }
    }' "$file")
  if [ -z "$bad_status" ]; then
    pass_check
  else
    fail_check "P-status" "非法状态词：${bad_status}（只允许 open/done/pending/paused）"
  fi

  # 需求追溯：至少一行 | R<n> | F...
  trace=$(section_body "$file" '## 需求追溯' | grep -cE '^\|[[:space:]]*R[0-9]+[[:space:]]*\|.*F[0-9]+' || true)
  trace=$(printf '%s' "$trace" | tr -d ' ')
  if [ "${trace:-0}" -ge 1 ]; then
    pass_check
  else
    fail_check "P-trace" "需求追溯表没有 R<n> → F<n> 映射——无法证明 spec 需求已被切片覆盖"
  fi

  confirm=$(section_body "$file" '## 确认记录')
  for k in 确认人 确认时间 '进入 loop 结论'; do
    v=$(field_value "$confirm" "$k")
    if [ -n "$v" ]; then
      pass_check
    else
      fail_check "P-confirm" "确认记录缺少「${k}」"
    fi
  done

  if [ -n "$spec" ]; then
    check_sha_binding "$file" spec_sha256 "$spec" P
  fi
}

gate_goal() {
  file=$1
  spec=$2
  plan=$3
  check_headings "$file" G \
    '## 工具 goal 指令' '## 阶段提示词' '## 现状代码锚点' '## 分阶段任务清单' \
    '## 设计约束' '## 统一 DoD' '## 验收 checklist' '## BLOCKED 条件'
  check_placeholders "$file" G
  check_todo_markers "$file" G

  # header：9 个字段必须存在且非空
  for k in STATUS SLICE ATTEMPT_ID TASK SPEC_SHA256 PLAN_SHA256 GOAL_SHA256 BASE_SHA HEAD_SHA; do
    v=$(header_value "$file" "$k")
    if [ -n "$v" ]; then
      pass_check
    else
      fail_check "G-header" "header 字段缺失或为空：${k}"
    fi
  done

  goal_status=$(header_value "$file" STATUS)
  case "$goal_status" in
    pending|open|implementing|reviewing|done|paused|BLOCKED) pass_check ;;
    *) fail_check "G-status" "STATUS 非法：${goal_status}（只允许 pending/open/implementing/reviewing/done/paused/BLOCKED）" ;;
  esac

  # 工具 goal 指令：7 个字段行缺一不可
  goal_body=$(section_body "$file" '## 工具 goal 指令')
  for k in 目标 验证 约束 边界 迭代策略 完成条件 暂停条件; do
    v=$(loose_field_value "$goal_body" "$k")
    if [ -n "$v" ]; then
      pass_check
    else
      fail_check "G-field" "工具 goal 指令缺少字段行「${k}：…」"
    fi
  done

  # 自引用 sha：删掉 GOAL_SHA256 行后算
  declared=$(header_value "$file" GOAL_SHA256 | tr -d ' `')
  actual=$(goal_self_sha "$file")
  if [ -z "$declared" ]; then
    fail_check "G-goalsha" "缺少 GOAL_SHA256 绑定行"
  elif [ "$declared" = "$actual" ]; then
    pass_check
  else
    fail_check "G-goalsha" "GOAL_SHA256 与正文不符（声明 ${declared} != 实际 ${actual}）——goal 改过需重算"
  fi

  if [ -n "$spec" ]; then
    check_sha_binding "$file" SPEC_SHA256 "$spec" G
  fi
  if [ -n "$plan" ]; then
    check_sha_binding "$file" PLAN_SHA256 "$plan" G
  fi
}

[ $# -ge 1 ] || usage
stage=$1
shift

# stage 合法性先于参数校验，否则 `gate.sh --help` / `gate.sh bogus` 会被报成 "--file required"
case "$stage" in
  -h|--help|help) usage ;;
  intent|spec|plan|goal) ;;
  *) usage_err "unknown stage: $stage (want intent|spec|plan|goal)" ;;
esac

file=
up_intent=
up_spec=
up_plan=
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file=$2; shift 2 ;;
    --intent) up_intent=$2; shift 2 ;;
    --spec) up_spec=$2; shift 2 ;;
    --plan) up_plan=$2; shift 2 ;;
    -h|--help) usage ;;
    *) usage_err "unknown arg: $1" ;;
  esac
done

[ -n "$file" ] || usage_err "--file required"
[ -f "$file" ] || usage_err "file not found: $file"
[ -s "$file" ] || usage_err "file is empty: $file"

printf 'stage=%s\n' "$stage"
printf 'file=%s\n' "$file"

case "$stage" in
  intent) gate_intent "$file" ;;
  spec) gate_spec "$file" "$up_intent" ;;
  plan) gate_plan "$file" "$up_spec" ;;
  goal) gate_goal "$file" "$up_spec" "$up_plan" ;;
  *) dl_die "unknown stage: $stage (want intent|spec|plan|goal)" ;;
esac

printf 'sha256=%s\n' "$(dl_sha256_file "$file")"
printf 'checks=%s\n' "$CHECKN"
printf 'failed=%s\n' "$FAILN"
if [ "$FAILN" -eq 0 ]; then
  printf 'ok=1\n'
  exit 0
fi
printf 'ok=0\n'
exit 1
