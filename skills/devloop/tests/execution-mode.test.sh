#!/usr/bin/env sh
# 后端选择、依赖检查、恢复和只读路由；不安装 Acpus、不调用模型。
set -u
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
DL="$ROOT/scripts/devloop"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-mode.test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'not ok - %s\n%s\n' "$1" "$OUT" >&2; }
run() { OUT=$(sh "$DL" "$@" 2>&1); RC=$?; }
expect() { if [ "$RC" -eq "$1" ] && printf '%s\n' "$OUT" | grep -qF -- "$2"; then ok "$3"; else bad "$3 (rc=$RC)"; fi; }

mkdir -p "$TMP/bin space"
cat >"$TMP/bin space/acpus" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$ACPUS_TEST_LOG"
case "$*" in
  --version)
    [ "${ACPUS_TEST_CASE:-}" != broken ] || exit 1
    [ "${ACPUS_TEST_CASE:-}" != empty ] || exit 0
    printf 'acpus test-version\n'; exit 0 ;;
  'skill read --help'|'workflow check --help'|'workflow run --help'|'runs inspect --help'|'runs pause --help'|'runs resume --help'|'runs fork --help')
    [ "${ACPUS_TEST_CASE:-}" != legacy ] || exit 2
    [ "${ACPUS_TEST_CASE:-}" != missing-control ] || [ "$*" != 'runs pause --help' ] || exit 2
    [ "${ACPUS_TEST_CASE:-}" != missing-fork ] || [ "$*" != 'runs fork --help' ] || exit 2
    exit 0 ;;
  doctor) [ "${ACPUS_TEST_CASE:-}" != unhealthy ]; exit $? ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TMP/bin space/acpus"
ACPUS_TEST_LOG="$TMP/acpus.log"
export ACPUS_TEST_LOG
FAKE="$TMP/bin space/acpus"

run detect-mode --mode default --acpus-cli "$TMP/missing"
expect 0 'acpus_status=missing' 'default 允许 Acpus 未安装'
run detect-mode --mode acpus --acpus-cli "$TMP/missing"
expect 1 'installation-acpus.md' '显式 acpus 缺依赖失败并提供安装说明'
run detect-mode --mode default --acpus-cli "$FAKE"
expect 0 'acpus_status=present' 'default 报告可选安装'
[ ! -e "$ACPUS_TEST_LOG" ] && ok 'default 不执行第三方 CLI' || bad 'default 不执行第三方 CLI'
run --mode acpus detect-mode --acpus-cli "$FAKE"
expect 0 'acpus_status=ok' '前置 --mode 及含空格的 CLI 路径可用'
expect 0 'acpus_agents_status=unchecked' 'CLI 健康不能冒充 Agent 已验证'
grep -qx 'runs inspect --help' "$ACPUS_TEST_LOG" && ok '探测必要命令族' || bad '探测必要命令族'
grep -qx 'doctor' "$ACPUS_TEST_LOG" && ok '执行原生 Runtime 健康检查' || bad '执行原生 Runtime 健康检查'
for scenario in broken empty legacy missing-control missing-fork unhealthy; do
  ACPUS_TEST_CASE=$scenario
  export ACPUS_TEST_CASE
  run detect-mode --mode acpus --acpus-cli "$FAKE"
  case "$scenario" in legacy|missing-control|missing-fork) state=incompatible ;; unhealthy) state=unhealthy ;; *) state=broken ;; esac
  expect 1 "acpus_status=$state" "拒绝 $scenario 安装且不降级"
done
unset ACPUS_TEST_CASE
for cmd in detect-mode doctor init next status gate review-packet; do
  case "$cmd" in gate) run gate plan --mode invalid ;; *) run "$cmd" --mode invalid ;; esac
  expect 2 'default|acpus' "$cmd 拒绝非法模式"
done
run detect-mode --mode
expect 2 '需要值' '缺少 mode 值报参数错误'
run detect-mode --mode default --mode acpus
expect 2 '重复' '拒绝重复尾部 mode'
run --mode default detect-mode --mode acpus
expect 2 '重复' '拒绝全局与子命令重复 mode'
run --mode acpus setup
expect 2 '不接受' '不向无关子命令静默传 mode'

# PATH 中只有必要标准工具和假 Acpus，没有 tmux；检查不依赖本机宿主。
mkdir "$TMP/minimal-bin"
for tool in sh dirname basename grep sed awk head tr cut git; do
  ln -s "$(command -v "$tool")" "$TMP/minimal-bin/$tool"
done
OUT=$(PATH="$TMP/minimal-bin" /bin/sh "$DL" doctor --mode acpus --acpus-cli "$FAKE" 2>&1); RC=$?
expect 0 '0 failed' 'acpus doctor 不依赖 tmux/Orca'
OUT=$(PATH="$TMP/minimal-bin" /bin/sh "$DL" doctor --mode default --acpus-cli "$TMP/missing" 2>&1); RC=$?
expect 1 'path:tmux' 'default 保留既有宿主检查'
run doctor --mode acpus --acpus-cli "$TMP/missing"
expect 1 'installation-acpus.md' 'doctor 对必需 Acpus 缺失返回失败'

run init --id native --root "$TMP/tasks" --mode default
expect 0 'execution_mode=default' '显式 default 初始化'
run init --id native --root "$TMP/tasks" --stage plan
expect 0 'execution_mode=default' 'default 创建下游 plan'
if ! grep -q '^acpus_max_parallel:' "$TMP/tasks/native/plan.md"; then ok '默认模板不追加 Acpus 合同'; else bad '默认模板不追加 Acpus 合同'; fi
run --mode acpus init --id parallel --root "$TMP/tasks"
expect 0 'execution_mode=acpus' '新 Acpus 任务可先准备材料'
run init --id parallel --root "$TMP/tasks" --stage plan
expect 0 'execution_mode=acpus' '恢复阶段初始化沿用已选模式'
D="$TMP/tasks/parallel"
grep -qx 'execution_mode: acpus' "$D/intent.md" && grep -q '^acpus_max_parallel:' "$D/plan.md" && ok '模式持久化且 plan 有执行合同' || bad '模式持久化且 plan 有执行合同'
cp "$D/plan.md" "$TMP/original-plan"
run init --id parallel --root "$TMP/tasks" --stage plan --force --mode default
expect 1 '不一致' 'force 不能绕过模式冲突'
cmp -s "$D/plan.md" "$TMP/original-plan" && ok '冲突不改写既有计划' || bad '冲突不改写既有计划'
run init --id partial --root "$TMP/tasks" --stage spec --mode acpus
expect 1 '先 init' '新 Acpus 任务不能只写无模式阶段'
[ ! -e "$TMP/tasks/partial" ] && ok '无效初始化不留下目录' || bad '无效初始化不留下目录'

mkdir "$TMP/legacy"
printf '| F1 | legacy | open | x | y |\n' >"$TMP/legacy/plan.md"
run status --plan "$TMP/legacy/plan.md"
expect 0 'execution_mode=default' '旧计划无字段时为 default'
run next --plan "$TMP/legacy/plan.md" --mode acpus
expect 1 '不一致' '不隐式迁移旧计划'
run next --plan "$D/plan.md"
expect 0 'phase_hint=acpus_workflow' 'Acpus 下一步路由到独立执行规程'
printf 'old\n' >"$D/run/old-report.md"
run next --plan "$D/plan.md" --run-dir "$D/run"
expect 0 'phase_hint=acpus_workflow' '旧 default 报告不能误导 Acpus 阶段'
run status --plan "$D/plan.md" --json
expect 0 '"execution_mode": "acpus"' 'JSON 状态带执行模式'
mkdir -p "$D/run/acpus/F1/attempt-1"
run review-packet --devloop-dir "$D"
expect 0 'execution_mode: acpus' '审阅摘要标识 Acpus 模式'
expect 0 'run/acpus/F1/attempt-1' '审阅摘要定位 Acpus 嵌套证据'
run detect-mode --dir "$D" --acpus-cli "$FAKE"
expect 0 'execution_mode=acpus' '环境检查继承任务模式'
printf 'execution_mode: default\n' >"$D/intent.md"
run next --dir "$D"
expect 1 '不一致' 'intent/plan 不一致不能继续'
printf 'execution_mode: acpus\nexecution_mode: acpus\n' >"$D/intent.md"
run detect-mode --dir "$D" --acpus-cli "$FAKE"
expect 2 '重复' '拒绝重复的持久模式记录'

# 状态错误不能误报 finalize；计划名称作为数据，不作为 shell 执行。
for state in implementing reviewing nonsense; do
  printf '| F1 | test | %s | x | y |\n' "$state" >"$TMP/state.md"
  run next --plan "$TMP/state.md"
  expect 1 '状态非法' "拒绝 $state 的错误完成投影"
done
printf '| F1 | one | open | x | y |\n| F2 | two | open | x | y |\n' >"$TMP/state.md"
run next --plan "$TMP/state.md"
expect 1 '状态非法' '多 open 不得被 next 忽略'
printf '# empty\n' >"$TMP/state.md"
run next --plan "$TMP/state.md"
expect 1 '没有切片' '空计划不判定完成'
printf '| F1 | name $(touch %s) with spaces | open | x | y |\n' "$TMP/executed" >"$TMP/state.md"
run next --plan "$TMP/state.md"
expect 0 'with spaces' '名称中的 shell 文本与空格完整保留'
[ ! -e "$TMP/executed" ] && ok '计划文本不会执行为命令' || bad '计划文本不会执行为命令'
printf '1..%s\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
