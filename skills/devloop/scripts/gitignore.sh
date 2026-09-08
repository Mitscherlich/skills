#!/usr/bin/env sh
# 共享给 setup/init：规则放在控制面内，迁移可明确识别的旧整目录排除。
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib/common.sh"
[ $# -ge 1 ] && [ $# -le 2 ] || dl_die 'Usage: gitignore.sh ROOT [--check]'
root=$1
check=${2:-}
[ -z "$check" ] || [ "$check" = --check ] || dl_die 'expected --check'
[ ! -L "$root" ] || dl_die "控制面不能是符号链接：$root"
[ ! -e "$root/specs" ] && [ ! -L "$root/specs" ] || dl_die '发现旧 .devloop/specs；先归并到 docs/knowledge/specs 并修正相对链接，再初始化'
if [ "$check" = --check ]; then
  [ -d "$root" ] || exit 1
else
  mkdir -p "$root"
fi
root=$(CDPATH= cd -- "$root" && pwd -P)
ignore="$root/.gitignore"
[ ! -L "$ignore" ] || dl_die "不能改写符号链接：$ignore"
[ ! -e "$ignore" ] || [ -f "$ignore" ] || dl_die "应为文件：$ignore"
template="$HERE/../templates/process.gitignore"

if [ -z "$check" ]; then
  # 只删除精确匹配的已知旧规则；其它项目规则保留。
  remove_rule() {
    file=$1 rule=$2
    [ ! -L "$file" ] || dl_die "不能改写符号链接：$file"
    [ -f "$file" ] || return 0
    if grep -Fxq -- "$rule" "$file"; then
      temporary=$(mktemp "$(dirname -- "$file")/.devloop-ignore.XXXXXX")
      cp -p "$file" "$temporary"
      DL_IGNORE_RULE="$rule" awk '$0 != ENVIRON["DL_IGNORE_RULE"]' "$file" >"$temporary"
      mv "$temporary" "$file"
    fi
  }
  remove_rule "$ignore" '!/specs/'
  remove_rule "$ignore" '!/specs/**'
  remove_rule "$ignore" '# devloop：只忽略任务过程材料；定稿 specs 纳入版本管理。'
  if repo=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null); then
    relative=${root#"$repo"/}
    [ "$relative" != "$root" ] || dl_die '控制面必须位于仓库内的子目录'
    exclude=$(git -C "$root" rev-parse --git-path info/exclude)
    case "$exclude" in /*) ;; *) exclude="$root/$exclude" ;; esac
    pattern=$(printf '%s' "$relative" | sed 's/[][?*\\]/\\&/g')
    for file in "$repo/.gitignore" "$exclude"; do
      for rule in "$pattern" "$pattern/" "/$pattern" "/$pattern/" "$pattern/**" "/$pattern/**"; do
        remove_rule "$file" "$rule"
      done
      for task in "$root"/*; do
        [ -d "$task" ] || continue
        [ -f "$task/intent.md" ] || [ -f "$task/plan.md" ] || continue
        task_pattern=$(printf '%s' "$(basename -- "$task")" | sed 's/[][?*\\]/\\&/g')
        remove_rule "$file" "/$pattern/$task_pattern/"
        remove_rule "$file" "$pattern/$task_pattern/"
      done
    done
  fi
  while IFS= read -r line; do
    if [ ! -f "$ignore" ] || ! grep -Fxq -- "$line" "$ignore"; then
      printf '\n%s\n' "$line" >>"$ignore"
    fi
  done <"$template"
fi
[ -f "$ignore" ] || exit 1
while IFS= read -r line; do
  grep -Fxq -- "$line" "$ignore" || exit 1
done <"$template"
if repo=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null); then
  if git -C "$root" check-ignore --no-index -q -- "$ignore"; then
    git -C "$root" check-ignore --no-index -v -- "$ignore" >&2
    dl_die '过程忽略文件仍被忽略；请调整上述实际命中的规则'
  fi
  for name in intent.md spec.md plan.md next-goal.md progress.md closeout.md run/check.log; do
    git -C "$root" check-ignore --no-index -q -- "$root/__devloop_process_check__/$name" || dl_die "过程忽略规则未生效：$name"
  done
fi
printf 'process_ignore=%s\n' "$ignore"
