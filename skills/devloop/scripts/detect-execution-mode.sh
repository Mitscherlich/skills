#!/usr/bin/env sh
# 只读检查模式与 Acpus 接口；不安装、不创建 Run、不自动降级。
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/lib/common.sh"

requested=
dir=
acpus_cli=acpus
while [ $# -gt 0 ]; do
  case "$1" in
    --mode|--dir|--acpus-cli)
      [ $# -ge 2 ] && [ -n "$2" ] || { printf 'error: %s 需要值\n' "$1" >&2; exit 2; }
      case "$1" in
        --mode)
          [ -z "$requested" ] || { printf 'error: 重复 --mode\n' >&2; exit 2; }
          requested=$2; dl_validate_mode "$requested" ;;
        --dir) dir=$2 ;;
        --acpus-cli) acpus_cli=$2 ;;
      esac
      shift 2 ;;
    -h|--help)
      printf 'Usage: detect-execution-mode.sh [--mode host|acpus] [--dir DIR] [--acpus-cli PATH]\n'
      exit 0 ;;
    *) printf 'error: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [ -n "$dir" ]; then
  [ -d "$dir" ] || dl_die "not a directory: $dir"
  mode=$(dl_resolve_mode "$requested" "$dir/intent.md" "$dir/plan.md")
else
  mode=$(dl_resolve_mode "$requested")
fi

status=missing
version=
resolved=$(command -v "$acpus_cli" 2>/dev/null || true)
if [ -n "$resolved" ]; then
  status=present
  # host 只报告可选安装是否存在，不执行第三方 CLI，也不依赖其健康。
  if [ "$mode" = acpus ]; then
    if version=$("$resolved" --version 2>/dev/null) && [ -n "$version" ]; then
      status=ok
      # 本集成采用 TypeScript Workflow 接口；旧 YAML CLI 不能混用。
      for capability in 'skill read' 'workflow check' 'workflow run' 'runs inspect' 'runs pause' 'runs resume' 'runs fork'; do
        set -- $capability
        if ! "$resolved" "$1" "$2" --help >/dev/null 2>&1; then
          status=incompatible
          break
        fi
      done
      if [ "$status" = ok ] && ! "$resolved" doctor >/dev/null 2>&1; then
        status=unhealthy
      fi
    else
      status=broken
    fi
  fi
fi
printf 'execution_mode=%s\nacpus_status=%s\nacpus_cli=%s\n' "$mode" "$status" "$resolved"
printf 'acpus_version=%s\n' "$(printf '%s' "$version" | head -n 1 | tr -d '\r' | cut -c 1-200)"
printf 'acpus_agents_status=unchecked\n'
printf 'installation_reference=%s\n' "$HERE/../references/installation-acpus.md"
if [ "$mode" = acpus ]; then
  printf 'execution_reference=%s\n' "$HERE/../references/acpus-mode.md"
  if [ "$status" != ok ]; then
    printf 'error: Acpus 不可用（%s）；按 installation-acpus.md 安装或修复；unhealthy 时运行 acpus doctor 查看详情，不自动切回 host\n' "$status" >&2
    exit 1
  fi
else
  printf 'execution_reference=%s\n' "$HERE/../references/loop.md"
fi
