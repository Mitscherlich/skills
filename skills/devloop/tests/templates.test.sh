#!/usr/bin/env sh
# templates.test.sh — 出厂模板填完占位符后必须能通过自己的门禁
# 防止模板与 gate.sh 的结构契约漂移（模板是 agent 直接复制的东西）。
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
INIT="$ROOT/scripts/init.sh"
GATE="$ROOT/scripts/gate.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-tpl.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

# 把 {{...}} 机械替换掉，模拟「占位符已被填写」，只校验结构契约
fill() {
  sed -e 's/{{[^{}]*}}/已填内容/g' "$1"
}

for t in intent spec plan next-goal progress; do
  [ -f "$ROOT/templates/$t.md" ] && ok "template $t.md 存在" || not_ok "template $t.md 存在"
done

ROOTDIR="$TMP/.devloop"
sh "$INIT" --id 0001-t --title t --root "$ROOTDIR" >/dev/null 2>&1
for st in spec plan next-goal; do
  sh "$INIT" --id 0001-t --root "$ROOTDIR" --stage "$st" >/dev/null 2>&1
done
D="$ROOTDIR/0001-t"

# ── intent ────────────────────────────────────────────────────
fill "$D/intent.md" >"$TMP/intent.md"
# 「未决问题」被机械替换成一条已填的 - [ ]，模拟收敛后写「无」
sed -i.bak 's/^- \[ \] 已填内容$/- 无/' "$TMP/intent.md" && rm -f "$TMP/intent.md.bak"
# 「结论」需为通过
sed -i.bak 's/^- 结论：已填内容$/- 结论：通过/' "$TMP/intent.md" && rm -f "$TMP/intent.md.bak"
out=$(sh "$GATE" intent --file "$TMP/intent.md" 2>&1)
if printf '%s\n' "$out" | grep -q '^ok=1$'; then
  ok 'templates/intent.md 填完后过门禁'
else
  not_ok "templates/intent.md 填完后过门禁: $(printf '%s\n' "$out" | grep '^fail=' | tr '\n' ' ')"
fi
ISHA=$(sh "$GATE" intent --file "$TMP/intent.md" | sed -n 's/^sha256=//p')

# ── spec ──────────────────────────────────────────────────────
fill "$D/spec.md" >"$TMP/spec.md"
sed -i.bak "s|^> intent_sha256: 已填内容\$|> intent_sha256: $ISHA|" "$TMP/spec.md" && rm -f "$TMP/spec.md.bak"
sed -i.bak 's/^- 结论：已填内容$/- 结论：通过/' "$TMP/spec.md" && rm -f "$TMP/spec.md.bak"
out=$(sh "$GATE" spec --file "$TMP/spec.md" --intent "$TMP/intent.md" 2>&1)
if printf '%s\n' "$out" | grep -q '^ok=1$'; then
  ok 'templates/spec.md 填完后过门禁'
else
  not_ok "templates/spec.md 填完后过门禁: $(printf '%s\n' "$out" | grep '^fail=' | tr '\n' ' ')"
fi
SSHA=$(sh "$GATE" spec --file "$TMP/spec.md" --intent "$TMP/intent.md" | sed -n 's/^sha256=//p')

# ── plan ──────────────────────────────────────────────────────
fill "$D/plan.md" >"$TMP/plan.md"
sed -i.bak "s|^> spec_sha256: 已填内容\$|> spec_sha256: $SSHA|" "$TMP/plan.md" && rm -f "$TMP/plan.md.bak"
out=$(sh "$GATE" plan --file "$TMP/plan.md" --spec "$TMP/spec.md" 2>&1)
if printf '%s\n' "$out" | grep -q '^ok=1$'; then
  ok 'templates/plan.md 填完后过门禁'
else
  not_ok "templates/plan.md 填完后过门禁: $(printf '%s\n' "$out" | grep '^fail=' | tr '\n' ' ')"
fi

# 模板 roadmap 恰好一个 open
openn=$(sh "$ROOT/scripts/status.sh" --plan "$TMP/plan.md" | sed -n 's/^open=//p')
[ "$openn" = "1" ] && ok 'plan 模板 roadmap 恰好一个 open' || not_ok "plan 模板 roadmap 恰好一个 open (got $openn)"

# 模板不得包含会被 todo 门禁拦下的词（占位符之外）
for t in intent spec plan; do
  if fill "$D/$t.md" | grep -qE 'TODO|TBD|FIXME|XXX|待填|待补|待定'; then
    not_ok "$t 模板正文无 todo 标记"
  else
    ok "$t 模板正文无 todo 标记"
  fi
done

# next-goal 模板须含 impl runner 依赖的绑定字段
for k in STATUS SLICE ATTEMPT_ID TASK SPEC_SHA256 PLAN_SHA256 GOAL_SHA256 BASE_SHA HEAD_SHA; do
  grep -q "^$k:" "$D/next-goal.md" && ok "next-goal 含 $k" || not_ok "next-goal 含 $k"
done

# 「工具 goal 指令」段的七字段句式已内联在模板里（不依赖 qiaomu-goal-meta-skill）
for f in 目标 验证 约束 边界 迭代策略 完成条件 暂停条件; do
  grep -q "^${f}：" "$D/next-goal.md" && ok "next-goal 含 goal 字段「${f}」" || not_ok "next-goal 含 goal 字段「${f}」"
done

# ── next-goal ─────────────────────────────────────────────────
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

fill "$D/next-goal.md" >"$TMP/next-goal.md"
# GOAL_SHA256 口径：删除所有以 GOAL_SHA256: 开头的整行后，对剩余内容算 SHA-256（避免自引用）
grep -v '^GOAL_SHA256:' "$TMP/next-goal.md" >"$TMP/next-goal.nohash"
GSHA=$(sha256_of "$TMP/next-goal.nohash")
sed -i.bak "s|^GOAL_SHA256: .*\$|GOAL_SHA256: $GSHA|" "$TMP/next-goal.md" && rm -f "$TMP/next-goal.md.bak"
# 不传 --spec/--plan：模板里的 SPEC_SHA256/PLAN_SHA256 是机械填充值，只校验结构与自哈希
out=$(sh "$GATE" goal --file "$TMP/next-goal.md" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^ok=1$'; then
  ok 'templates/next-goal.md 填完后过门禁'
else
  not_ok "templates/next-goal.md 填完后过门禁 (rc=$rc): $(printf '%s\n' "$out" | grep '^fail=' | tr '\n' ' ')"
fi

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
