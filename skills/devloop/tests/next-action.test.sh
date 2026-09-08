#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NX="$TEST_DIR/../scripts/next-action.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-next.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$NX"; then ok 'sh -n next-action.sh'; else not_ok 'sh -n next-action.sh'; fi

cat >"$TMP/plan.md" <<'EOF'
| F1 | a | done | x | y |
| F2 | b | open | x | y |
| F3 | c | pending | x | y |
EOF

out=$(sh "$NX" --plan "$TMP/plan.md")
echo "$out" | grep -qx 'action=work_open_slice' && ok 'work open' || not_ok 'work open'
echo "$out" | grep -qx 'slice_id=F2' && ok 'slice F2' || not_ok 'slice F2'
echo "$out" | grep -qx 'phase_hint=compile_goal' && ok 'compile hint' || not_ok 'compile hint'

mkdir -p "$TMP/run"
printf 'r\n' >"$TMP/run/x-report.md"
out2=$(sh "$NX" --plan "$TMP/plan.md" --run-dir "$TMP/run")
echo "$out2" | grep -qx 'phase_hint=review' && ok 'review hint when report only' || not_ok 'review hint when report only'

cat >"$TMP/plan_all_done.md" <<'EOF'
| F1 | a | done | x | y |
| F2 | b | done | x | y |
EOF
out3=$(sh "$NX" --plan "$TMP/plan_all_done.md")
echo "$out3" | grep -qx 'action=finalize' && ok 'finalize when all done' || not_ok 'finalize when all done'

cat >"$TMP/plan_paused.md" <<'EOF'
| F1 | a | done | x | y |
| F2 | b | paused(x) | x | y |
EOF
out4=$(sh "$NX" --plan "$TMP/plan_paused.md")
echo "$out4" | grep -qx 'action=resolve_paused' && ok 'resolve paused' || not_ok 'resolve paused'


# ── 全管线 --dir 模式 ─────────────────────────────────────────
INIT="$TEST_DIR/../scripts/init.sh"
GATE="$TEST_DIR/../scripts/gate.sh"
D="$TMP/.devloop/0001-p"

nd=$(sh "$NX" --dir "$TMP" 2>/dev/null) || true
echo "$nd" | grep -qx 'action=init_intent' && ok 'dir 无 intent → init_intent' || not_ok 'dir 无 intent → init_intent'

sh "$INIT" --id 0001-p --title p --root "$TMP/.devloop" >/dev/null
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'stage=intent' && ok 'stage=intent' || not_ok 'stage=intent'
echo "$nd" | grep -qx 'action=grill_intent' && ok '未填 intent → grill_intent' || not_ok '未填 intent → grill_intent'
echo "$nd" | grep -q '^fail=I-placeholder' && ok '带出门禁失败项' || not_ok '带出门禁失败项'

cat >"$D/intent.md" <<'EOF'
# p · intent

## 问题陈述
x
## 期望结果
y
## 影响范围
| a | b | c |
|---|---|---|
| m | n | o |
## 约束与非目标
- 硬约束：无额外依赖。
## 裁决记录
1. **d**：e —— f
## 未决问题
- 无
## 人工审阅
- 审阅人：tester
- 审阅时间：2026-01-01T00:00:00Z
- 结论：通过
EOF
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=compile_spec' && ok 'intent 过门禁 → compile_spec' || not_ok 'intent 过门禁 → compile_spec'
echo "$nd" | grep -q '^intent_sha256=' && ok '输出 intent_sha256' || not_ok '输出 intent_sha256'
echo "$nd" | grep -q "^write=$D/spec.md$" && ok '指出 spec 写入路径' || not_ok '指出 spec 写入路径'

ISHA=$(sh "$GATE" intent --file "$D/intent.md" | sed -n 's/^sha256=//p')
cat >"$D/spec.md" <<EOF
# p · spec
> intent_sha256: $ISHA

## 目标与验收终态
z
## 需求
| # | 需求 | 验收标准 | 来源 |
|---|---|---|---|
| R1 | a | \`make test\` | I-1 |
## 设计
b
## 关注点与冲突
| # | 关注点 | 影响 | 建议 | 拍板 |
|---|---|---|---|---|
| C1 | 无 | 无 | 无 | 无 |
## 非目标
- 无。
## 签署记录
- 签署人：tester
- 签署时间：2026-01-01T01:00:00Z
- 结论：通过
EOF
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=compile_plan' && ok 'spec 过门禁 → compile_plan' || not_ok 'spec 过门禁 → compile_plan'

SSHA=$(sh "$GATE" spec --file "$D/spec.md" --intent "$D/intent.md" | sed -n 's/^sha256=//p')
cat >"$D/plan.md" <<EOF
# p · plan
> spec_sha256: $SSHA

## 背景与目标
g
## 需求追溯
| 需求 | 覆盖切片 | 说明 |
|---|---|---|
| R1 | F1 | h |
## 确认记录
- 确认人：tester
- 确认时间：2026-01-01T02:00:00Z
- 进入 loop 结论：确认进入
## 切片 roadmap
| # | 切片 | 状态 | 范围 | DoD |
|---|---|---|---|---|
| F1 | i | open | R1 | j |
## 每片统一 DoD
1. 门禁全绿。
EOF
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'stage=loop' && ok 'plan 过门禁 → stage=loop' || not_ok 'plan 过门禁 → stage=loop'
echo "$nd" | grep -qx 'action=work_open_slice' && ok 'loop 落到切片层' || not_ok 'loop 落到切片层'
echo "$nd" | grep -qx 'slice_id=F1' && ok 'loop 取到 open 切片' || not_ok 'loop 取到 open 切片'

sed 's/^- 确认人：tester$//' "$D/plan.md" >"$D/plan.bad" && mv "$D/plan.bad" "$D/plan.md"
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=await_plan_review' && ok '只缺确认 → await_plan_review' || not_ok '只缺确认 → await_plan_review'
echo "$nd" | grep -qx 'stage=loop' && not_ok 'plan 不过时不得进 loop' || ok 'plan 不过时不得进 loop'

if sh "$NX" >/dev/null 2>&1; then not_ok '缺 --dir/--plan 报错'; else ok '缺 --dir/--plan 报错'; fi

# 新流程 joint：未签 spec 可以生成 plan，两个正式门禁仍要过。
printf '\nreview_mode: joint\n' >>"$D/intent.md"
ISHA=$(sh "$GATE" intent --file "$D/intent.md" | sed -n 's/^sha256=//p')
sed "s/^> intent_sha256: .*/> intent_sha256: $ISHA/; s/^- 签署人：tester$/- 签署人：{{用户}}/; s/^- 结论：通过$/- 结论：{{通过或打回}}/" "$D/spec.md" >"$D/s.tmp"
mv "$D/s.tmp" "$D/spec.md"
mv "$D/plan.md" "$D/saved-plan"
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=compile_plan' && ok 'joint 未签 spec → compile_plan' || not_ok 'joint 未签 spec → compile_plan'
SSHA=$(sh "$GATE" spec --draft --file "$D/spec.md" --intent "$D/intent.md" | sed -n 's/^sha256=//p')
sed "s/^> spec_sha256: .*/> spec_sha256: $SSHA/" "$D/saved-plan" >"$D/plan.md"
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=await_design_review' && ok 'joint 两份草稿齐 → 等联审' || not_ok 'joint 两份草稿齐 → 等联审'
echo "$nd" | grep -qx 'stage=loop' && not_ok '草稿不得进 loop' || ok '草稿不得进 loop'

sed 's/^- 结论：{{通过或打回}}$/- 结论：打回/' "$D/spec.md" >"$D/s.tmp"
mv "$D/s.tmp" "$D/spec.md"
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=fix_spec' && ok 'spec 打回 → 修订而非重复索要签字' || not_ok 'spec 打回 → 修订而非重复索要签字'

# 模拟用户实际联审后落签字；正式 spec 改 sha 后重绑 plan。
sed 's/{{用户}}/tester/; s/^- 结论：打回$/- 结论：通过/' "$D/spec.md" >"$D/s.tmp"
mv "$D/s.tmp" "$D/spec.md"
SSHA=$(sh "$GATE" spec --file "$D/spec.md" --intent "$D/intent.md" | sed -n 's/^sha256=//p')
sed "s/^> spec_sha256: .*/> spec_sha256: $SSHA/" "$D/saved-plan" >"$D/plan.md"
printf '\n' >>"$D/plan.md"
sed '/^## 确认记录/a\
- 确认人：tester' "$D/plan.md" >"$D/p.tmp"
mv "$D/p.tmp" "$D/plan.md"
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=work_open_slice' && ok 'joint 实际签署后才进 loop' || not_ok 'joint 实际签署后才进 loop'

sed 's/^- 审阅人：tester$/- 审阅人：{{用户}}/' "$D/intent.md" >"$D/i.tmp"
mv "$D/i.tmp" "$D/intent.md"
nd=$(sh "$NX" --dir "$D")
echo "$nd" | grep -qx 'action=await_intent_review' && ok 'intent 只缺签署不继续 grill' || not_ok 'intent 只缺签署不继续 grill'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
