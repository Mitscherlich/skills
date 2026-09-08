#!/usr/bin/env sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DL="$HERE/../scripts/devloop"
IGNORE="$HERE/../scripts/gitignore.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-ignore.test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
git init -q "$TMP/repo"
repo="$TMP/repo"
mkdir -p "$repo/.devloop/old/run" "$repo/docs/knowledge/specs/auth"
printf 'legacy\n' >"$repo/.devloop/old/intent.md"
printf 'contract\n' >"$repo/docs/knowledge/specs/auth/spec.md"
printf '# keep\n.env\n/.devloop/\n' >"$repo/.gitignore"
printf '\n/.devloop/old/\nkeep-local\n' >>"$repo/.git/info/exclude"
mkdir -p "$repo/.devloop/legacy[1]"
printf 'legacy\n' >"$repo/.devloop/legacy[1]/intent.md"
printf '%s\n' '/.devloop/legacy\[1\]/' >>"$repo/.git/info/exclude"
cp "$repo/.gitignore" "$TMP/before"
sh "$IGNORE" "$repo/.devloop" --check >/dev/null 2>&1 && exit 1
cmp "$TMP/before" "$repo/.gitignore"
[ ! -e "$repo/.devloop/.gitignore" ]
sh "$IGNORE" "$repo/.devloop" >/dev/null
sh "$IGNORE" "$repo/.devloop" --check >/dev/null
grep -qx '.env' "$repo/.gitignore"
grep -qx 'keep-local' "$repo/.git/info/exclude"
grep -Fxq '/.devloop/' "$repo/.gitignore" && exit 1
grep -Fxq '/.devloop/old/' "$repo/.git/info/exclude" && exit 1
git -C "$repo" check-ignore -q .devloop/old/intent.md
git -C "$repo" check-ignore -q .devloop/old/run/a.log
git -C "$repo" check-ignore -q docs/knowledge/specs/auth/spec.md && exit 1
git -C "$repo" check-ignore -q .devloop/.gitignore && exit 1
# 非过程文件保持可见，规则不屏蔽整个任务目录。
git -C "$repo" check-ignore -q .devloop/old/deliverable.txt && exit 1
git -C "$repo" check-ignore -q '.devloop/legacy[1]/deliverable.txt' && exit 1
cp "$repo/.devloop/.gitignore" "$TMP/child"
cp "$repo/.git/info/exclude" "$TMP/exclude"
printf '\n!/specs/\n!/specs/**\n' >>"$repo/.devloop/.gitignore"
sh "$IGNORE" "$repo/.devloop" >/dev/null
grep -Fq '!/specs/' "$repo/.devloop/.gitignore" && exit 1
cp "$repo/.devloop/.gitignore" "$TMP/child"
sh "$IGNORE" "$repo/.devloop" >/dev/null
cmp "$TMP/child" "$repo/.devloop/.gitignore"
cmp "$TMP/exclude" "$repo/.git/info/exclude"
[ -z "$(git -C "$repo" diff --cached --name-only)" ]
# 初始化覆盖此规程，保留 specs 这个目录名。
sh "$DL" init --id next --root "$repo/.devloop" >/dev/null 2>&1
git -C "$repo" check-ignore -q .devloop/next/spec.md
sh "$DL" init --id specs --root "$repo/.devloop" >/dev/null 2>&1 && exit 1
[ ! -e "$repo/.devloop/specs/intent.md" ]
# 仍被更宽泛规则遮蔽时明确失败，不假报 specs 可提交。
printf '**/.devloop/\n' >>"$repo/.gitignore"
sh "$IGNORE" "$repo/.devloop" --check >/dev/null 2>&1 && exit 1
# 拒绝改写符号链接指向的文件。
mkdir -p "$TMP/unsafe"
ln -s "$TMP/before" "$TMP/unsafe/.gitignore"
sh "$IGNORE" "$TMP/unsafe" >/dev/null 2>&1 && exit 1
cmp "$TMP/before" "$TMP/unsafe/.gitignore"
printf 'gitignore integration passed\n'
