#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INIT="$TEST_DIR/../scripts/init.sh"
GATE="$TEST_DIR/../scripts/gate.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-init.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$INIT"; then ok 'sh -n init.sh'; else not_ok 'sh -n init.sh'; fi

ROOT="$TMP/.devloop"
out=$(sh "$INIT" --id 0001-demo --title '演示需求' --root "$ROOT")
D="$ROOT/0001-demo"

[ -f "$D/intent.md" ] && ok 'intent.md 落盘' || not_ok 'intent.md 落盘'
[ -f "$D/progress.md" ] && ok 'progress.md 落盘' || not_ok 'progress.md 落盘'
[ -d "$D/run" ] && ok 'run/ 创建' || not_ok 'run/ 创建'
echo "$out" | grep -q '^stage=intent$' && ok '输出 stage=intent' || not_ok '输出 stage=intent'
echo "$out" | grep -q '^next=devloop gate intent' && ok '输出下一步命令' || not_ok '输出下一步命令'

# 变量替换
grep -q '0001-demo' "$D/intent.md" && ok '{{id}} 已替换' || not_ok '{{id}} 已替换'
grep -q '演示需求' "$D/intent.md" && ok '{{title}} 已替换' || not_ok '{{title}} 已替换'
grep -q '{{id}}' "$D/intent.md" && not_ok '{{id}} 无残留' || ok '{{id}} 无残留'
grep -q '{{created}}' "$D/progress.md" && not_ok '{{created}} 无残留' || ok '{{created}} 无残留'

# 内容占位符保留，使门禁能挡住未填文档
grep -q '{{' "$D/intent.md" && ok '内容占位符保留' || not_ok '内容占位符保留'
if sh "$GATE" intent --file "$D/intent.md" >/dev/null 2>&1; then
  not_ok '新建 intent 未通过门禁'
else
  ok '新建 intent 未通过门禁'
fi

# 幂等：默认不覆盖
out2=$(sh "$INIT" --id 0001-demo --root "$ROOT" 2>&1) || true
echo "$out2" | grep -q '^skipped=' && ok '已存在时不覆盖' || not_ok '已存在时不覆盖'

printf 'edited\n' >>"$D/intent.md"
sh "$INIT" --id 0001-demo --root "$ROOT" --force >/dev/null 2>&1
grep -q '^edited$' "$D/intent.md" && not_ok '--force 覆盖' || ok '--force 覆盖'

# --stage 单独落盘
sh "$INIT" --id 0001-demo --root "$ROOT" --stage spec >/dev/null 2>&1
[ -f "$D/spec.md" ] && ok '--stage spec 落盘' || not_ok '--stage spec 落盘'
[ -f "$D/plan.md" ] && not_ok '--stage 只落指定阶段' || ok '--stage 只落指定阶段'

# 参数校验
if sh "$INIT" --root "$ROOT" >/dev/null 2>&1; then not_ok '缺 --id 报错'; else ok '缺 --id 报错'; fi
if sh "$INIT" --id 'a/b' --root "$ROOT" >/dev/null 2>&1; then not_ok '拒绝路径分隔符 id'; else ok '拒绝路径分隔符 id'; fi
if sh "$INIT" --id ok1 --root "$ROOT" --stage nope >/dev/null 2>&1; then not_ok '拒绝未知 stage'; else ok '拒绝未知 stage'; fi

# 模板 title 缺省回落到 id
sh "$INIT" --id 0002-notitle --root "$ROOT" >/dev/null 2>&1
grep -q '0002-notitle · 0002-notitle' "$ROOT/0002-notitle/intent.md" && ok 'title 缺省回落 id' || not_ok 'title 缺省回落 id'

sh "$INIT" --id 0001-demo --root "$ROOT" --stage closeout >/dev/null 2>&1
[ -f "$D/closeout.md" ] && ok '收尾模板可单独初始化' || not_ok '收尾模板可单独初始化'

# 新流程默认联审，Git 默认排除运行记录；重复 init 不改写 exclude。
grep -qx 'review_mode: joint' "$D/intent.md" && ok '默认 joint 联审' || not_ok '默认 joint 联审'
git init -q "$TMP/repo"
sh "$INIT" --id 0003-git --root "$TMP/repo/.devloop" >/dev/null 2>&1
git -C "$TMP/repo" check-ignore -q .devloop/0003-git/intent.md && ok '新控制面默认 Git ignored' || not_ok '新控制面默认 Git ignored'
cp "$TMP/repo/.git/info/exclude" "$TMP/exclude.before"
sh "$INIT" --id 0003-git --root "$TMP/repo/.devloop" --stage spec >/dev/null 2>&1
cmp -s "$TMP/exclude.before" "$TMP/repo/.git/info/exclude" && ok 'exclude 幂等' || not_ok 'exclude 幂等'
[ "$(git -C "$TMP/repo" ls-files --others --exclude-standard)" = '.devloop/.gitignore' ] && ok '只产生可提交的过程忽略规则' || not_ok '只产生可提交的过程忽略规则'
# 路径含 Git glob 元字符必须字面排除，不能顺带隐藏相似名字。
sh "$INIT" --id 'task[1]' --root "$TMP/repo/.devloop" >/dev/null 2>&1
git -C "$TMP/repo" check-ignore -q '.devloop/task[1]/intent.md' && ok '排除路径中的 glob 按字面处理' || not_ok '排除路径中的 glob 按字面处理'
git -C "$TMP/repo" check-ignore -q '.devloop/task1/deliverable.txt' && not_ok '不会排除非过程产物' || ok '不会排除非过程产物'
cp "$TMP/repo/.git/info/exclude" "$TMP/exclude.safe"
bad_id=$(printf 'bad\nrule')
sh "$INIT" --id "$bad_id" --root "$TMP/repo/.devloop" >/dev/null 2>&1 && not_ok '拒绝 exclude 换行注入' || ok '拒绝 exclude 换行注入'
cmp -s "$TMP/exclude.safe" "$TMP/repo/.git/info/exclude" && ok '拒绝后 exclude 未改动' || not_ok '拒绝后 exclude 未改动'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
