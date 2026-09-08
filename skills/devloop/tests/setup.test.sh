#!/usr/bin/env sh
# 在真实临时项目检查初始化、保留人工内容、只读语义及 worktree 隔离。
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DL="$HERE/../scripts/devloop"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-setup.test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
project="$TMP/项目 with spaces"
mkdir -p "$project/docs/adr"
printf '已有规则，无末尾换行' >"$project/AGENTS.md"
cp "$project/AGENTS.md" "$TMP/agents.before"
printf '# 领域事实\n' >"$project/CONTEXT.md"
sh -n "$HERE/../scripts/setup.sh"
if sh "$DL" setup --project "$project" --check >"$TMP/check"; then
  printf 'FAIL: 缺入口却检查成功\n' >&2; exit 1
fi
grep -qx 'knowledge_status=incomplete' "$TMP/check"
[ ! -e "$project/docs/knowledge" ]
cmp "$TMP/agents.before" "$project/AGENTS.md"

sh "$DL" setup --project "$project" >"$TMP/setup"
index="$project/docs/knowledge/index.md"
[ -s "$index" ]
[ -s "$project/docs/knowledge/specs/index.md" ]
[ ! -e "$project/.devloop/specs" ]
[ "$(find "$project/docs/knowledge" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 1 ]
[ ! -d "$project/docs/knowledge/domain" ]
grep -Fq '[CONTEXT.md](../../CONTEXT.md)' "$index"
grep -Fq '[docs/adr](../../docs/adr)' "$index"
grep -Fq '已有规则，无末尾换行' "$project/AGENTS.md"
grep -Fq '](docs/knowledge/index.md)' "$project/AGENTS.md"
printf '\n人工维护的知识\n' >>"$index"
cp "$index" "$TMP/index.before"
cp "$project/AGENTS.md" "$TMP/agents.after"
sh "$DL" setup --project "$project" >/dev/null
sh "$DL" setup --project "$project" --check >"$TMP/check"
grep -qx 'knowledge_status=initialized' "$TMP/check"
grep -qx 'knowledge_content=unchecked' "$TMP/check"
cmp "$TMP/index.before" "$index"
cmp "$TMP/agents.after" "$project/AGENTS.md"

# 旧入口链接只替换目标，人工内容保留；真实旧目录先提示归并，绝不覆盖。
printf '\n[旧规格入口](../../.devloop/specs/index.md)\n' >>"$index"
sh "$DL" setup --project "$project" >/dev/null
grep -Fq '[旧规格入口](specs/index.md)' "$index"
grep -Fq '../../.devloop/specs' "$index" && exit 1
cp "$index" "$TMP/index.before"
legacy="$TMP/legacy"
mkdir -p "$legacy/.devloop/specs/auth"
printf '保留旧规格\n' >"$legacy/.devloop/specs/auth/spec.md"
sh "$DL" setup --project "$legacy" >/dev/null 2>&1 && exit 1
[ "$(cat "$legacy/.devloop/specs/auth/spec.md")" = '保留旧规格' ]
[ ! -e "$legacy/docs/knowledge/specs" ]

# 已有自定义索引仅加 AGENTS 入口，不替换索引；删入口后可恢复。
other="$TMP/existing"
mkdir -p "$other/docs/knowledge"
printf '# 已有知识\n' >"$other/docs/knowledge/index.md"
cp "$other/docs/knowledge/index.md" "$TMP/custom.before"
sh "$DL" setup --project "$other" >/dev/null
head -n 1 "$other/docs/knowledge/index.md" >"$TMP/custom.after"
cmp "$TMP/custom.before" "$TMP/custom.after"
grep -Fq '](specs/index.md)' "$other/docs/knowledge/index.md"
rm "$other/AGENTS.md"
sh "$DL" setup --project "$other" --check >/dev/null && exit 1
[ ! -e "$other/AGENTS.md" ]
sh "$DL" setup --project "$other" >/dev/null

# 链接和类型冲突拒绝写入，外部文件保持原状。
unsafe="$TMP/unsafe"
mkdir "$unsafe"
ln -s "$TMP/agents.before" "$unsafe/AGENTS.md"
sh "$DL" setup --project "$unsafe" >/dev/null 2>&1 && exit 1
[ ! -e "$unsafe/docs" ]
[ "$(cat "$TMP/agents.before")" = '已有规则，无末尾换行' ]
rm "$unsafe/AGENTS.md"
ln -s "$project/docs" "$unsafe/docs"
sh "$DL" setup --project "$unsafe" >/dev/null 2>&1 && exit 1
cmp "$TMP/index.before" "$index"
rm "$unsafe/docs"
printf '不是目录\n' >"$unsafe/docs"
sh "$DL" setup --project "$unsafe" >/dev/null 2>&1 && exit 1
[ ! -e "$unsafe/AGENTS.md" ]
sh "$DL" setup --project >/dev/null 2>&1 && exit 1
sh "$DL" setup --bogus >/dev/null 2>&1 && exit 1

# 空索引不能被当作就绪或静默覆盖。
: >"$other/docs/knowledge/index.md"
sh "$DL" setup --project "$other" --check >/dev/null && exit 1
sh "$DL" setup --project "$other" >/dev/null 2>&1 && exit 1
[ ! -s "$other/docs/knowledge/index.md" ]

sh "$DL" init --id plain --root "$project/.devloop" >"$TMP/init"
grep -qx 'knowledge_status=initialized' "$TMP/init"
cmp "$TMP/index.before" "$index"
cmp "$TMP/agents.after" "$project/AGENTS.md"

# init 根据目标路径检查，不在调用者 cwd 创建知识，也不把缺入口当任务失败。
git init -q "$TMP/repo"
mkdir -p "$TMP/repo/nested"
sh "$DL" init --id first --root "$TMP/repo/.devloop" >"$TMP/init" 2>"$TMP/warning"
grep -qx 'knowledge_status=incomplete' "$TMP/init"
[ -f "$TMP/repo/.devloop/first/intent.md" ]
[ ! -e "$TMP/repo/docs" ]
[ "$(git -C "$TMP/repo" ls-files --others --exclude-standard)" = '.devloop/.gitignore' ]
(cd "$TMP/repo/nested" && sh "$DL" setup >/dev/null)
[ -s "$TMP/repo/docs/knowledge/index.md" ]
[ ! -e "$TMP/repo/nested/docs" ]
sh "$DL" init --id second --root "$TMP/repo/.devloop" >"$TMP/init"
grep -qx 'knowledge_status=initialized' "$TMP/init"
[ -z "$(git -C "$TMP/repo" diff --cached --name-only)" ]
printf 'docs/knowledge/specs/\n' >"$TMP/repo/.gitignore"
sh "$DL" setup --project "$TMP/repo" --check >/dev/null 2>&1 && exit 1
rm "$TMP/repo/.gitignore"

# linked worktree 不会借用主 worktree 的已初始化状态。
git -C "$TMP/repo" -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m baseline
git -C "$TMP/repo" worktree add -q -b test-linked "$TMP/linked"
sh "$DL" init --id linked --root "$TMP/linked/.devloop" >"$TMP/init" 2>/dev/null
grep -qx 'knowledge_status=incomplete' "$TMP/init"
[ ! -e "$TMP/linked/docs" ]

printf 'setup integration passed\n'
