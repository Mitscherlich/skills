#!/usr/bin/env sh
# 真实模板 → 填写 → 绑定 → 门禁 → next，及并行合同的反例。
set -u
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
DL="$ROOT/scripts/devloop"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-acpus-plan.test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'not ok - %s\n%s\n' "$1" "$OUT" >&2; }
run() { OUT=$(sh "$DL" "$@" 2>&1); RC=$?; }
expect() { if [ "$RC" -eq "$1" ] && printf '%s\n' "$OUT" | grep -qF -- "$2"; then ok "$3"; else bad "$3 (rc=$RC)"; fi; }
fill() { sed 's/{{[^{}]*}}/已填内容/g' "$1"; }
replace() { sed "$1" "$2" >"$TMP/replaced" && mv "$TMP/replaced" "$2"; }

run init --id integration --root "$TMP/tasks" --mode acpus
expect 0 'execution_mode=acpus' '初始化 Acpus 测试任务'
D="$TMP/tasks/integration"
fill "$D/intent.md" >"$TMP/filled"
mv "$TMP/filled" "$D/intent.md"
replace 's/^- \[ \] 已填内容$/- 无/;s/^- 结论：已填内容$/- 结论：通过/' "$D/intent.md"
run gate intent --file "$D/intent.md"
expect 0 'ok=1' 'Acpus intent 正式门禁'
ISHA=$(printf '%s\n' "$OUT" | sed -n 's/^sha256=//p')
run init --id integration --root "$TMP/tasks" --stage spec
expect 0 'execution_mode=acpus' 'spec 初始化继承模式'
fill "$D/spec.md" >"$TMP/filled"
mv "$TMP/filled" "$D/spec.md"
replace "s/^> intent_sha256: 已填内容$/> intent_sha256: $ISHA/;s/^- 结论：已填内容$/- 结论：通过/" "$D/spec.md"
run gate spec --file "$D/spec.md" --intent "$D/intent.md"
expect 0 'ok=1' 'Acpus spec 正式绑定'
SSHA=$(printf '%s\n' "$OUT" | sed -n 's/^sha256=//p')
run init --id integration --root "$TMP/tasks" --stage plan
expect 0 'execution_mode=acpus' 'plan 自动追加并行合同'
fill "$D/plan.md" >"$TMP/filled"
mv "$TMP/filled" "$D/plan.md"
replace "s/^> spec_sha256: 已填内容$/> spec_sha256: $SSHA/;s/^- 进入 loop 结论：已填内容$/- 进入 loop 结论：通过/" "$D/plan.md"
run gate plan --file "$D/plan.md" --spec "$D/spec.md"
expect 0 'ok=1' '完整 Acpus 模板可通过正式门禁'
run next --dir "$D"
expect 0 'phase_hint=acpus_workflow' '正式门禁后完整管线路由 Acpus'
cp "$D/plan.md" "$TMP/good-plan"

# 有向依赖无须按表格顺序排列；合法 DAG 可以通过。
replace 's/| T2 | F2 | - |/| T2 | F2 | T3 |/' "$D/plan.md"
run gate plan --file "$D/plan.md" --spec "$D/spec.md"
expect 0 'ok=1' '合法反向表格依赖仍可拓扑调度'

check_invalid() {
  run gate plan --file "$D/plan.md" --spec "$D/spec.md"
  expect 1 "$1" "$2"
  run gate plan --draft --file "$D/plan.md" --spec "$D/spec.md"
  expect 1 'P-acpus' "$2（草稿门禁同样约束）"
}
replace 's/| T3 | F2 | - |/| T3 | F2 | T2 |/' "$D/plan.md"
check_invalid '循环依赖' '拒绝依赖环'
cp "$TMP/good-plan" "$D/plan.md"
replace 's/| T2 | F2 | - |/| T2 | F2 | T99 |/' "$D/plan.md"
check_invalid '未知依赖' '拒绝悬空依赖'
cp "$TMP/good-plan" "$D/plan.md"
replace 's/| T2 | F2 | - |/| T2 | F2 | T1 |/' "$D/plan.md"
check_invalid '跨切片依赖' '跨批次依赖不能混入同批次 DAG'
cp "$TMP/good-plan" "$D/plan.md"
replace 's/| T2 | F2 |/| T2 | F8 |/' "$D/plan.md"
check_invalid '未知切片' '拒绝不存在的所属切片'
cp "$TMP/good-plan" "$D/plan.md"
replace 's/| T3 |/| T2 |/' "$D/plan.md"
check_invalid '重复子任务' '拒绝重复任务 ID'
cp "$TMP/good-plan" "$D/plan.md"
replace '/^| T1 |/d' "$D/plan.md"
check_invalid 'F1 缺少子任务' '每个活动批次须有可执行子任务'
cp "$TMP/good-plan" "$D/plan.md"
replace 's/| T1 | F1 | - | 已填内容 |/| T1 | F1 | - | |/' "$D/plan.md"
check_invalid '缺依赖、写入边界或验收命令' '拒绝空写入边界'
for key in max_parallel max_attempts task_timeout_minutes run_timeout_minutes; do
  cp "$TMP/good-plan" "$D/plan.md"
  replace "s/^acpus_$key: .*/acpus_$key: 0/" "$D/plan.md"
  check_invalid '必须为正整数' "拒绝 $key 无界或零预算"
done
cp "$TMP/good-plan" "$D/plan.md"
printf '\nacpus_max_parallel: 2\n' >>"$D/plan.md"
check_invalid '必须声明一次' '拒绝重复预算字段'
cp "$TMP/good-plan" "$D/plan.md"
replace '/^acpus_max_parallel:/d' "$D/plan.md"
check_invalid '必须声明一次' '拒绝缺失预算字段'
cp "$TMP/good-plan" "$D/plan.md"
replace 's/^- 进入 loop 结论：通过$/- 进入 loop 结论：打回/' "$D/plan.md"
run gate plan --file "$D/plan.md" --spec "$D/spec.md"
expect 1 'P-verdict' '并行模式不绕过人工执行确认'
cp "$TMP/good-plan" "$D/plan.md"
printf '\n上游变更\n' >>"$D/spec.md"
run gate plan --file "$D/plan.md" --spec "$D/spec.md"
expect 1 'P-bind' '并行模式不绕过冻结输入绑定'
printf '1..%s\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
