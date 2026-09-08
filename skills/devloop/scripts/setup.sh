#!/usr/bin/env sh
# setup.sh — 项目知识入口；只建索引，内容由 Agent 查证维护。
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib/common.sh"

usage() {
  printf 'Usage: devloop setup [--project DIR] [--check]\n'
  printf '默认当前 Git worktree 根目录，否则当前目录；--project 精确指定项目目录。\n'
}
project=
check=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) [ $# -ge 2 ] && [ -n "$2" ] || { usage >&2; exit 2; }; project=$2; shift 2 ;;
    --check) check=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "$project" ] || project=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
[ -d "$project" ] || dl_die "项目目录不存在：$project"
project=$(CDPATH= cd -- "$project" && pwd -P)
index="$project/docs/knowledge/index.md"
agents="$project/AGENTS.md"
printf 'knowledge_project=%s\nknowledge_index=%s\n' "$project" "$index"

# 不沿符号链接修改其它位置；失败前先检查全部写入路径。
for path in "$project/docs" "$project/docs/knowledge" "$index" "$agents" "$project/.devloop" "$project/docs/knowledge/specs" "$project/docs/knowledge/specs/index.md"; do
  [ ! -L "$path" ] || dl_die "知识入口路径是符号链接，需按项目约定处理：$path"
done
for path in "$project/docs" "$project/docs/knowledge" "$project/.devloop" "$project/docs/knowledge/specs"; do
  [ ! -e "$path" ] || [ -d "$path" ] || dl_die "应为目录：$path"
done
for path in "$index" "$agents" "$project/docs/knowledge/specs/index.md"; do
  [ ! -e "$path" ] || [ -f "$path" ] || dl_die "应为普通文件：$path"
done

has_pointer() {
  [ -f "$agents" ] && grep -Fq '](docs/knowledge/index.md)' "$agents"
}
# 规格已移入知识库；可见性检查在真实项目目录进行，避免自定义控制面路径影响定位。
check_specs_visible() {
  if git -C "$project" rev-parse --show-toplevel >/dev/null 2>&1; then
    for spec_path in docs/knowledge/specs/index.md docs/knowledge/specs/knowledge-check/spec.md; do
      if git -C "$project" check-ignore --no-index -q -- "$spec_path"; then
        git -C "$project" check-ignore --no-index -v -- "$spec_path" >&2
        return 1
      else
        ignore_rc=$?
        [ "$ignore_rc" -eq 1 ] || return "$ignore_rc"
      fi
    done
  fi
}
if [ "$check" -eq 1 ]; then
  printf 'knowledge_content=unchecked\n'
  if [ -s "$index" ] && grep -Fq '](specs/index.md)' "$index" && [ -s "$project/docs/knowledge/specs/index.md" ] && has_pointer && check_specs_visible && sh "$HERE/gitignore.sh" "$project/.devloop" --check; then
    printf 'knowledge_status=initialized\n'
    exit 0
  fi
  printf 'knowledge_status=incomplete\nknowledge_action=setup\n'
  exit 1
fi

if [ -e "$index" ] && [ ! -s "$index" ]; then
  dl_die "已有索引为空，保留原件；请补充内容：$index"
fi
sh "$HERE/gitignore.sh" "$project/.devloop"
mkdir -p "$project/docs/knowledge/specs"
if [ ! -e "$project/docs/knowledge/specs/index.md" ]; then
  (set -C; cat "$HERE/../templates/specs-index.md" >"$project/docs/knowledge/specs/index.md")
fi
[ -s "$project/docs/knowledge/specs/index.md" ] || dl_die '已有规格索引为空，请补充内容'
mkdir -p "$project/docs/knowledge"
if [ ! -e "$index" ]; then
  tmp=$(mktemp "$project/docs/knowledge/.setup.XXXXXX")
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  cat "$HERE/../templates/knowledge-index.md" >"$tmp"
  # 只引用实际存在的常用入口；其它项目文档由 Agent 按需求补进索引。
  for source in CONTEXT.md docs/README.md docs/index.md docs/adr docs/domain docs/conventions docs/runbooks; do
    if [ -e "$project/$source" ]; then
      printf '| [%s](../../%s) | 已有项目资料；首次读取后补充适用范围 |\n' "$source" "$source" >>"$tmp"
    fi
  done
  # 排他发布：并发 setup 也不会覆盖已有索引。
  ln "$tmp" "$index"
  printf 'knowledge_created=%s\n' "$index"
fi
if grep -Fq '](../../.devloop/specs/index.md)' "$index"; then
  tmp=$(mktemp "$project/docs/knowledge/.setup.XXXXXX")
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  cp -p "$index" "$tmp"
  sed 's|](../../.devloop/specs/index.md)|](specs/index.md)|g' "$index" >"$tmp"
  mv "$tmp" "$index"
fi
if ! grep -Fq '](specs/index.md)' "$index"; then
  printf '\n定稿需求与验收场景见[规格索引](specs/index.md)；domain 只保存跨能力共用的概念与不变量。\n' >>"$index"
fi
check_specs_visible || dl_die '持久规格被忽略；请调整上述实际命中的规则'
if ! has_pointer; then
  # ponytail: 首次 setup 按项目串行执行；如需并发初始化，再加项目锁避免重复入口。
  printf '\n新开、继续或收尾 devloop 时，先读[项目知识库](docs/knowledge/index.md)，按索引读取相关知识；收尾更新生效知识和索引。\n' >>"$agents"
  printf 'knowledge_updated=%s\n' "$agents"
fi
printf 'knowledge_status=initialized\nknowledge_content=unchecked\n'
