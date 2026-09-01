#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
GATE="$TEST_DIR/../scripts/gate.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-gate.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

# 期望门禁通过
expect_pass() {
  _msg=$1
  shift
  if sh "$GATE" "$@" >/dev/null 2>&1; then ok "$_msg"; else not_ok "$_msg"; fi
}
# 期望门禁失败，且失败码里含指定 check id
expect_fail() {
  _msg=$1
  _check=$2
  shift 2
  _out=$(sh "$GATE" "$@" 2>/dev/null)
  if [ -n "$_check" ]; then
    printf '%s\n' "$_out" | grep -q "^fail=$_check" && ok "$_msg" || not_ok "$_msg"
  else
    printf '%s\n' "$_out" | grep -q '^ok=0' && ok "$_msg" || not_ok "$_msg"
  fi
}

if sh -n "$GATE"; then ok 'sh -n gate.sh'; else not_ok 'sh -n gate.sh'; fi

write_intent() {
  cat >"$1" <<'EOF'
# demo · intent

## 问题陈述

登录接口没有限流。

## 期望结果

单 IP 每分钟超过 60 次返回 429。

## 影响范围

| 系统 | 影响 | 归属 |
|---|---|---|
| gateway | 新增中间件 | 平台组 |

## 约束与非目标

- 硬约束：不引入 Redis。
- 非目标：不做验证码。

## 裁决记录

1. **计数存储**：进程内滑动窗口 —— 单机部署。

## 未决问题

- 无

## 人工审阅

- 审阅人：tester
- 审阅时间：2026-01-01T00:00:00Z
- 审阅要点：核对阈值
- 结论：通过
EOF
}

I="$TMP/intent.md"
write_intent "$I"
expect_pass 'intent 完整时通过' intent --file "$I"

# 未填占位符
cp "$I" "$TMP/i-ph.md" && printf '\n{{待填}}\n' >>"$TMP/i-ph.md"
expect_fail 'intent 有 {{}} 占位符被拦' I-placeholder intent --file "$TMP/i-ph.md"

# 未决问题未收敛
sed 's/^- 无$/- [ ] 阈值还没定/' "$I" >"$TMP/i-openq.md"
expect_fail 'intent 未决问题未勾选被拦' I-openq intent --file "$TMP/i-openq.md"

# 人工审阅未签
sed 's/^- 结论：通过$/- 结论：打回/' "$I" >"$TMP/i-verdict.md"
expect_fail 'intent 审阅结论非通过被拦' I-verdict intent --file "$TMP/i-verdict.md"
sed 's/^- 审阅人：tester$/- 审阅人：/' "$I" >"$TMP/i-signer.md"
expect_fail 'intent 审阅人为空被拦' I-signer intent --file "$TMP/i-signer.md"

# 无编号裁决
sed 's/^1\. \*\*计数存储\*\*.*$//' "$I" >"$TMP/i-nodec.md"
expect_fail 'intent 无编号裁决被拦' I-decision intent --file "$TMP/i-nodec.md"

# 带括号后缀的标题应被前缀匹配接受
sed 's/^## 人工审阅$/## 人工审阅（准出签字）/' "$I" >"$TMP/i-suffix.md"
expect_pass 'intent 标题带括号后缀仍识别' intent --file "$TMP/i-suffix.md"

ISHA=$(sh "$GATE" intent --file "$I" | sed -n 's/^sha256=//p')

write_spec() {
  cat >"$1" <<EOF
# demo · spec

> intent_sha256: $2

## 目标与验收终态

限流生效。

## 需求

| # | 需求 | 验收标准 | 来源 |
|---|---|---|---|
| R1 | 滑动窗口计数 | \`go test ./auth\` 全绿 | I-1 |

## 设计

进程内桶按 IP 分片。

## 关注点与冲突

| # | 关注点 | 影响 | 建议 | 拍板 |
|---|---|---|---|---|
| C1 | 无 | 无 | 无 | 无 |

## 非目标

- 分布式限流。

## 签署记录

- 签署人：tester
- 签署时间：2026-01-01T01:00:00Z
- 签署范围：R1
- 结论：通过
EOF
}

S="$TMP/spec.md"
write_spec "$S" "$ISHA"
expect_pass 'spec 完整时通过' spec --file "$S" --intent "$I"
expect_pass 'spec 不带 --intent 时跳过绑定校验' spec --file "$S"

# sha 漂移
write_spec "$TMP/s-drift.md" "0000000000000000000000000000000000000000000000000000000000000000"
expect_fail 'spec sha 漂移被拦' S-bind spec --file "$TMP/s-drift.md" --intent "$I"

# 缺绑定行
grep -v 'intent_sha256' "$S" >"$TMP/s-nobind.md"
expect_fail 'spec 缺绑定行被拦' S-bind spec --file "$TMP/s-nobind.md" --intent "$I"

# 过程性残留（小节）
cp "$S" "$TMP/s-proc.md" && printf '\n## 裁决记录\n\n1. **x**：y\n' >>"$TMP/s-proc.md"
expect_fail 'spec 残留裁决记录小节被拦' S-procedural spec --file "$TMP/s-proc.md" --intent "$I"

# 过程性残留（问答体）
cp "$S" "$TMP/s-qa.md" && printf '\nQ: 阈值多少？\n' >>"$TMP/s-qa.md"
expect_fail 'spec 残留问答体被拦' S-procedural-line spec --file "$TMP/s-qa.md" --intent "$I"

# 无需求行
grep -v '^| R1 |' "$S" >"$TMP/s-noreq.md"
expect_fail 'spec 无 R 需求行被拦' S-req spec --file "$TMP/s-noreq.md" --intent "$I"

# 需求行缺列
sed 's/^| R1 | 滑动窗口计数 | .* | I-1 |$/| R1 | 滑动窗口计数 |  | I-1 |/' "$S" >"$TMP/s-cell.md"
expect_fail 'spec 需求行缺验收标准被拦' S-req-cell spec --file "$TMP/s-cell.md" --intent "$I"

SSHA=$(sh "$GATE" spec --file "$S" --intent "$I" | sed -n 's/^sha256=//p')

write_plan() {
  cat >"$1" <<EOF
# demo · plan

> spec_sha256: $2

## 背景与目标

加限流。

## 需求追溯

| 需求 | 覆盖切片 | 说明 |
|---|---|---|
| R1 | F1 | F1 实现计数器 |

## 确认记录

- 确认人：tester
- 确认时间：2026-01-01T02:00:00Z
- 进入 loop 结论：确认进入

## 切片 roadmap

| # | 切片 | 状态 | 范围 | DoD |
|---|---|---|---|---|
| F1 | 计数器 | open | R1 | 单测 |
| F2 | 接中间件 | pending | R1 | 集成测试 |

## 每片统一 DoD

1. 门禁全绿。
EOF
}

P="$TMP/plan.md"
write_plan "$P" "$SSHA"
expect_pass 'plan 完整时通过' plan --file "$P" --spec "$S"

# 两个 open
sed 's/^| F2 | 接中间件 | pending |/| F2 | 接中间件 | open |/' "$P" >"$TMP/p-2open.md"
expect_fail 'plan 多个 open 被拦' P-open plan --file "$TMP/p-2open.md" --spec "$S"

# 非法状态词
sed 's/^| F2 | 接中间件 | pending |/| F2 | 接中间件 | doing |/' "$P" >"$TMP/p-status.md"
expect_fail 'plan 非法状态词被拦' P-status plan --file "$TMP/p-status.md" --spec "$S"

# 缺追溯
grep -v '^| R1 | F1 |' "$P" >"$TMP/p-notrace.md"
expect_fail 'plan 缺 R→F 追溯被拦' P-trace plan --file "$TMP/p-notrace.md" --spec "$S"

# 缺确认记录字段
grep -v '^- 确认人：' "$P" >"$TMP/p-noconfirm.md"
expect_fail 'plan 缺确认人被拦' P-confirm plan --file "$TMP/p-noconfirm.md" --spec "$S"

# spec 漂移
write_plan "$TMP/p-drift.md" "1111111111111111111111111111111111111111111111111111111111111111"
expect_fail 'plan spec_sha 漂移被拦' P-bind plan --file "$TMP/p-drift.md" --spec "$S"

PSHA=$(sh "$GATE" plan --file "$P" --spec "$S" | sed -n 's/^sha256=//p')

sha_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# 与 gate.sh 同口径：删掉 GOAL_SHA256 行后算 sha，再把该行插回 PLAN_SHA256 之后
seal_goal_sha() {
  _f=$1
  _b="$TMP/.goal-body"
  grep -v '^GOAL_SHA256:' "$_f" >"$_b" || true
  _s=$(sha_file "$_b")
  awk -v s="$_s" '{ print } /^PLAN_SHA256: /{ print "GOAL_SHA256: " s }' "$_b" >"$_f"
  rm -f "$_b"
}

write_goal() {
  cat >"$1" <<EOF
# next-goal

STATUS: open
SLICE: F2
ATTEMPT_ID: 20260101T030000Z-7f3a
TASK: demo · F2 接中间件（把计数器接进 gateway）
SPEC_SHA256: $2
PLAN_SHA256: $3
BASE_SHA: 1111111111111111111111111111111111111111
HEAD_SHA: 2222222222222222222222222222222222222222

## 工具 goal 指令

> 七行字段缺一不可，每行形如 \`字段：内容\`。

目标：gateway 接入 F1 的滑动窗口计数器，单 IP 超阈值返回 429。
验证：\`go test ./gateway\` 全绿；\`grep -n rateLimit gateway/mw.go\` 有命中。
约束：不引入 Redis；不改 auth 包对外签名。
边界：只写 gateway/ 下文件；禁止触碰 .devloop/ 与 plan.md 切片状态。
迭代策略：一次一个聚焦改动，改完立刻重跑验证命令，失败先定位再改。
完成条件：验证命令全绿 + 本片 commit 已产生 + 报告已落盘。
暂停条件：门禁 3 轮修复不过 / 需求语义歧义 / 需要外部凭据。

## 阶段提示词

> 动手前先读 spec.md 与 plan.md。

## 现状代码锚点（精确 file:line）

| 锚点 | 位置 | 现状 | 本片目标 |
|---|---|---|---|
| Handler | \`gateway/mw.go:20-40\` | 无限流 | 接入计数器 |

## 分阶段任务清单

### 阶段 1：接线

1. gateway/mw.go：注册限流中间件。

## 设计约束（不可破）

- 只能实现本切片，不得推进下一片。
- 本地 commit，绝不 push。

## 统一 DoD

1. 门禁全绿。

## 验收 checklist

- [ ] \`go test ./gateway\` 全绿
- [ ] commit feat(demo-F2): … 产生

## BLOCKED 条件（满足即停、报告写明）

1. 门禁 3 轮修复不过
2. 需要外部凭据
EOF
  seal_goal_sha "$1"
}

G="$TMP/goal.md"
write_goal "$G" "$SSHA" "$PSHA"
expect_pass 'goal 完整时通过' goal --file "$G" --spec "$S" --plan "$P"
expect_pass 'goal 不带上游时跳过绑定校验' goal --file "$G"

# 缺二级标题
grep -v '^## 验收 checklist$' "$G" >"$TMP/g-heading.md"
seal_goal_sha "$TMP/g-heading.md"
expect_fail 'goal 缺二级标题被拦' G-heading goal --file "$TMP/g-heading.md" --spec "$S" --plan "$P"

# 未填占位符
cp "$G" "$TMP/g-ph.md" && printf '\n{{未填}}\n' >>"$TMP/g-ph.md"
seal_goal_sha "$TMP/g-ph.md"
expect_fail 'goal 有 {{}} 占位符被拦' G-placeholder goal --file "$TMP/g-ph.md" --spec "$S" --plan "$P"

# 未完成标记
cp "$G" "$TMP/g-todo.md" && printf '\n补充：TODO\n' >>"$TMP/g-todo.md"
seal_goal_sha "$TMP/g-todo.md"
expect_fail 'goal 残留 TODO 被拦' G-todo goal --file "$TMP/g-todo.md" --spec "$S" --plan "$P"

# goal 指令缺字段行
grep -v '^完成条件：' "$G" >"$TMP/g-field.md"
seal_goal_sha "$TMP/g-field.md"
expect_fail 'goal 缺「完成条件」字段行被拦' G-field goal --file "$TMP/g-field.md" --spec "$S" --plan "$P"

# STATUS 非法
sed 's/^STATUS: open$/STATUS: doing/' "$G" >"$TMP/g-status.md"
seal_goal_sha "$TMP/g-status.md"
expect_fail 'goal STATUS 非法被拦' G-status goal --file "$TMP/g-status.md" --spec "$S" --plan "$P"

# header 字段为空
sed 's/^ATTEMPT_ID: .*$/ATTEMPT_ID:/' "$G" >"$TMP/g-header.md"
seal_goal_sha "$TMP/g-header.md"
expect_fail 'goal ATTEMPT_ID 为空被拦' G-header goal --file "$TMP/g-header.md" --spec "$S" --plan "$P"

# GOAL_SHA256 自引用不符（故意不重算）
sed 's/^GOAL_SHA256: .*$/GOAL_SHA256: 3333333333333333333333333333333333333333333333333333333333333333/' "$G" >"$TMP/g-gsha.md"
expect_fail 'goal GOAL_SHA256 与正文不符被拦' G-goalsha goal --file "$TMP/g-gsha.md" --spec "$S" --plan "$P"

# 缺 GOAL_SHA256 行
grep -v '^GOAL_SHA256:' "$G" >"$TMP/g-nogsha.md"
expect_fail 'goal 缺 GOAL_SHA256 行被拦' G-goalsha goal --file "$TMP/g-nogsha.md" --spec "$S" --plan "$P"

# 上游 spec 漂移
cp "$S" "$TMP/s-moved.md" && printf '\n补一句设计说明。\n' >>"$TMP/s-moved.md"
expect_fail 'goal SPEC_SHA256 漂移被拦' G-bind goal --file "$G" --spec "$TMP/s-moved.md"

# 上游 plan 漂移
cp "$P" "$TMP/p-moved.md" && printf '\n补一句范围说明。\n' >>"$TMP/p-moved.md"
expect_fail 'goal PLAN_SHA256 漂移被拦' G-bind goal --file "$G" --plan "$TMP/p-moved.md"

# 参数错误
if sh "$GATE" nope --file "$P" >/dev/null 2>&1; then not_ok 'unknown stage rejected'; else ok 'unknown stage rejected'; fi
if sh "$GATE" intent --file "$TMP/nope.md" >/dev/null 2>&1; then not_ok 'missing file rejected'; else ok 'missing file rejected'; fi

# 退出码契约：0 通过 / 1 门禁未通过 / 2 参数或输入错误
expect_code() {
  _msg=$1; _want=$2; shift 2
  sh "$GATE" "$@" >/dev/null 2>&1
  _got=$?
  [ "$_got" = "$_want" ] && ok "$_msg" || not_ok "$_msg (want $_want, got $_got)"
}
expect_code '--help 打 usage 并退 2' 2 --help
expect_code 'unknown stage 退 2' 2 nope --file "$P"
expect_code '缺 --file 退 2' 2 goal
expect_code '文件不存在退 2' 2 goal --file "$TMP/nope.md"
expect_code 'unknown arg 退 2' 2 goal --file "$G" --bogus x
expect_code '门禁未通过退 1（不是 2）' 1 goal --file "$TMP/g-nogsha.md"
expect_code '门禁通过退 0' 0 goal --file "$G" --spec "$S" --plan "$P"

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
