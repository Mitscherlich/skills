#!/usr/bin/env sh
# init.sh — 初始化 devloop 控制面目录并落盘阶段模板
#
# Usage:
#   init.sh --id <id> [--title T] [--root DIR] [--stage S] [--force]
#
# 默认（不带 --stage）：创建 <root>/<id>/{run/}，落盘 intent.md + progress.md
# --stage intent|spec|plan|next-goal|progress：只落盘该阶段模板
#
# 模板中 {{id}} / {{title}} / {{created}} 会被替换；其余 {{...}} 保留为待填标记，
# 由 `devloop gate <stage>` 强制填完才放行。
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
ROOT_SKILL=$(dl_skill_root "$HERE/init.sh")

usage() {
  cat <<'EOF'
Usage: init.sh --id <id> [--title T] [--root DIR] [--stage intent|spec|plan|next-goal|progress] [--force]

Defaults: --root .devloop ; 不带 --stage 时落盘 intent.md + progress.md 并建 run/
Exit: 0 ok / 1 refuse (exists without --force) / 2 usage
EOF
  exit 2
}

id=
title=
root=.devloop
stage=
force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --id) id=$2; shift 2 ;;
    --title) title=$2; shift 2 ;;
    --root) root=$2; shift 2 ;;
    --stage) stage=$2; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) usage ;;
    *) dl_die "unknown arg: $1" ;;
  esac
done

[ -n "$id" ] || dl_die "--id required"
case "$id" in
  */*|*' '*|.*) dl_die "invalid --id: $id (禁止路径分隔符 / 空格 / 前导点)" ;;
esac
[ -n "$title" ] || title=$id

created=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || dl_utc_stamp)
dir="$root/$id"
tpl_dir="$ROOT_SKILL/templates"
[ -d "$tpl_dir" ] || dl_die "templates dir missing: $tpl_dir"

# 字面量替换，避开 sed 的分隔符 / 元字符问题
render() {
  awk -v id="$1" -v title="$2" -v created="$3" '
    function rep(s, from, to,   out, p) {
      out = ""
      while ((p = index(s, from)) > 0) {
        out = out substr(s, 1, p - 1) to
        s = substr(s, p + length(from))
      }
      return out s
    }
    {
      line = rep($0, "{{id}}", id)
      line = rep(line, "{{title}}", title)
      line = rep(line, "{{created}}", created)
      print line
    }
  ' "$4"
}

materialize() {
  _stage=$1
  _src="$tpl_dir/$_stage.md"
  _dst="$dir/$_stage.md"
  [ -f "$_src" ] || dl_die "no template for stage: $_stage"
  if [ -e "$_dst" ] && [ "$force" -eq 0 ]; then
    printf 'skipped=%s (exists; use --force to overwrite)\n' "$_dst"
    return 1
  fi
  render "$id" "$title" "$created" "$_src" >"$_dst.tmp"
  mv -f "$_dst.tmp" "$_dst"
  printf 'wrote=%s\n' "$_dst"
  return 0
}

mkdir -p "$dir"
printf 'dir=%s\n' "$dir"
printf 'id=%s\n' "$id"
printf 'created=%s\n' "$created"

rc=0
if [ -n "$stage" ]; then
  case "$stage" in
    intent|spec|plan|next-goal|progress) ;;
    *) dl_die "unknown --stage: $stage" ;;
  esac
  materialize "$stage" || rc=1
  printf 'stage=%s\n' "$stage"
else
  mkdir -p "$dir/run"
  printf 'run_dir=%s\n' "$dir/run"
  materialize intent || rc=1
  materialize progress || rc=1
  printf 'stage=intent\n'
  printf 'next=devloop gate intent --file %s/intent.md\n' "$dir"
fi

exit "$rc"
