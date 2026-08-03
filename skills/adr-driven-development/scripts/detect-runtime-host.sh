#!/usr/bin/env sh
# detect-runtime-host.sh — 确定性探测 ADR loop 执行宿主（host）
#
# 进入 loop 时由协调 agent 直接执行本脚本；不要靠读文档/环境变量自行推理。
# 零第三方依赖；只依赖 POSIX sh + 本机 PATH 中的命令。
#
# 用法:
#   detect-runtime-host.sh                 # 自动探测
#   detect-runtime-host.sh --prefer orca   # 优先 orca，不可用则降级
#   detect-runtime-host.sh --force tmux    # 强制 host（仍会填可用字段）
#   detect-runtime-host.sh --json          # JSON 输出（默认 key=value）
#   ADR_HOST=orca detect-runtime-host.sh   # 环境变量等同 --force
#
# 退出码:
#   0  已选出可用 host（orca 或 tmux）
#   1  无可用 host（tmux 也不在 PATH）
#   2  参数错误
#
# 输出字段（key=value，一行一个）:
#   host=orca|tmux
#   reason=...
#   orca_env=0|1
#   orca_cli=...          # 解析到的可执行路径或空
#   orca_cli_name=...     # 逻辑名：ORCA_CLI_COMMAND|orca-dev|orca-ide|orca|""
#   orca_status=ok|fail|skip|missing
#   orca_worktree_id=...  # 环境注入或空
#   orca_terminal_handle=...
#   tmux_available=0|1
#   preferred=auto|orca|tmux
#   forced=0|1
set -eu

FORMAT=kv
PREFER=auto
FORCE=""

usage() {
  _usage_status=${1:-2}
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
  exit "$_usage_status"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    --prefer)
      [ $# -ge 2 ] || usage
      PREFER=$2
      case "$PREFER" in orca|tmux|auto) ;; *)
        echo "error: --prefer must be orca|tmux|auto" >&2
        exit 2
        ;;
      esac
      shift 2
      ;;
    --force)
      [ $# -ge 2 ] || usage
      FORCE=$2
      case "$FORCE" in orca|tmux) ;; *)
        echo "error: --force must be orca|tmux" >&2
        exit 2
        ;;
      esac
      shift 2
      ;;
    -h|--help) usage 0 ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# 环境变量覆盖（与 --force 同效；CLI --force 优先）
if [ -z "$FORCE" ] && [ -n "${ADR_HOST:-}" ]; then
  case "$ADR_HOST" in
    orca|tmux) FORCE=$ADR_HOST ;;
    *)
      echo "error: ADR_HOST must be orca|tmux (got: $ADR_HOST)" >&2
      exit 2
      ;;
  esac
fi

# ── 探测 Orca 环境信号 ──────────────────────────────────────
ORCA_ENV=0
ORCA_WORKTREE_ID_VAL=${ORCA_WORKTREE_ID:-}
ORCA_TERMINAL_HANDLE_VAL=${ORCA_TERMINAL_HANDLE:-}

if [ "${TERM_PROGRAM:-}" = "Orca" ]; then
  ORCA_ENV=1
fi
if [ -n "${ORCA_WORKTREE_ID:-}" ] || [ -n "${ORCA_WORKSPACE_ID:-}" ]; then
  ORCA_ENV=1
fi
if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then
  ORCA_ENV=1
fi
# 部分 Orca 注入但不一定有 TERM_PROGRAM
if [ -n "${ORCA_PANE_KEY:-}" ] || [ -n "${ORCA_TAB_ID:-}" ]; then
  ORCA_ENV=1
fi

# ── 解析 ORCA 可执行文件 ────────────────────────────────────
# 顺序与 orca-cli skill / orca-host.md 一致；禁止在 Linux 非托管终端误用读屏器 orca。
ORCA_CLI=""
ORCA_CLI_NAME=""
ORCA_STATUS=skip

is_exec() {
  command -v "$1" >/dev/null 2>&1
}

resolve_orca_cli() {
  if [ -n "${ORCA_CLI_COMMAND:-}" ]; then
    ORCA_CLI_NAME=ORCA_CLI_COMMAND
    # 只接受单个可执行名/路径；拒绝参数和 shell 元字符，后续始终按 argv 调用。
    case "$ORCA_CLI_COMMAND" in
      *[[:space:]]*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'`'*|*'$'*|*'('*|*')'*|*'{'*|*'}'*|*'['*|*']'*|*'*'*|*'?'*|*'!'*|*'\\'*)
        ORCA_STATUS=fail
        return 1
        ;;
    esac
    if is_exec "$ORCA_CLI_COMMAND" || [ -x "$ORCA_CLI_COMMAND" ]; then
      ORCA_CLI=$ORCA_CLI_COMMAND
      return 0
    fi
    ORCA_STATUS=fail
    return 1
  fi
  if [ -n "${ORCA_DEV_REPO_ROOT:-}" ] && is_exec orca-dev; then
    ORCA_CLI=orca-dev
    ORCA_CLI_NAME=orca-dev
    return 0
  fi
  # Linux 无条件优先 orca-ide，避免把 /usr/bin/orca 读屏器当成 Orca CLI。
  _uname=$(uname -s 2>/dev/null || echo unknown)
  if [ "$_uname" = "Linux" ]; then
    if is_exec orca-ide; then
      ORCA_CLI=orca-ide
      ORCA_CLI_NAME=orca-ide
      return 0
    fi
    if [ "$ORCA_ENV" -eq 1 ] && is_exec orca; then
      ORCA_CLI=orca
      ORCA_CLI_NAME=orca
      return 0
    fi
    # 非托管 Linux 即使 prefer=orca，也不回落到可能是读屏器的 orca。
    return 1
  fi
  if is_exec orca; then
    ORCA_CLI=orca
    ORCA_CLI_NAME=orca
    return 0
  fi
  ORCA_CLI=""
  ORCA_CLI_NAME=""
  return 1
}

check_orca_status() {
  if [ "$ORCA_STATUS" != "fail" ]; then
    ORCA_STATUS=missing
  fi
  if [ -z "$ORCA_CLI" ]; then
    return 1
  fi
  # status --json；始终有界，且把 CLI 当作单个 argv 执行，不经过 sh -c。
  _out=""
  if is_exec timeout; then
    _out=$(timeout 8 "$ORCA_CLI" status --json 2>/dev/null || true)
  elif is_exec gtimeout; then
    _out=$(gtimeout 8 "$ORCA_CLI" status --json 2>/dev/null || true)
  else
    _status_file=${TMPDIR:-/tmp}/detect-runtime-host-status.$$
    rm -f "$_status_file"
    "$ORCA_CLI" status --json >"$_status_file" 2>/dev/null &
    _status_pid=$!
    _status_waited=0
    while kill -0 "$_status_pid" 2>/dev/null && [ "$_status_waited" -lt 8 ]; do
      sleep 1
      _status_waited=$((_status_waited + 1))
    done
    if kill -0 "$_status_pid" 2>/dev/null; then
      kill "$_status_pid" 2>/dev/null || true
    fi
    wait "$_status_pid" 2>/dev/null || true
    if [ -f "$_status_file" ]; then
      _out=$(cat "$_status_file")
      rm -f "$_status_file"
    fi
  fi
  if [ -z "$_out" ]; then
    ORCA_STATUS=fail
    return 1
  fi
  # 健康条件至少要求 runtime reachable；任意层 ok:true 都不能替代它。
  if printf '%s' "$_out" | grep -Eq '"reachable"[[:space:]]*:[[:space:]]*true'; then
    ORCA_STATUS=ok
    return 0
  fi
  ORCA_STATUS=fail
  return 1
}

TMUX_AVAILABLE=0
if is_exec tmux; then
  TMUX_AVAILABLE=1
fi

ORCA_CLI_OK=0
NEED_ORCA=0
if [ "$FORCE" = "orca" ]; then
  NEED_ORCA=1
elif [ -z "$FORCE" ]; then
  case "$PREFER" in
    orca) NEED_ORCA=1 ;;
    auto)
      if [ "$ORCA_ENV" -eq 1 ]; then
        NEED_ORCA=1
      fi
      ;;
  esac
fi

if [ "$NEED_ORCA" -eq 1 ]; then
  resolve_orca_cli || true
  if [ -n "$ORCA_CLI" ] && check_orca_status; then
    ORCA_CLI_OK=1
  elif [ "$ORCA_STATUS" != "fail" ]; then
    ORCA_STATUS=missing
  fi
fi

# ── 决策 ────────────────────────────────────────────────────
HOST=""
REASON=""
FORCED=0

if [ -n "$FORCE" ]; then
  FORCED=1
  PREFER=$FORCE
  if [ "$FORCE" = "orca" ]; then
    if [ "$ORCA_CLI_OK" -eq 1 ]; then
      HOST=orca
      REASON="forced orca; cli status ok"
    else
      # 强制 orca 但不可用 → 仍返回 host=orca 并说明失败，exit 1
      HOST=orca
      REASON="forced orca but cli unavailable or status not ok (orca_status=$ORCA_STATUS)"
    fi
  else
    if [ "$TMUX_AVAILABLE" -eq 1 ]; then
      HOST=tmux
      REASON="forced tmux"
    else
      HOST=tmux
      REASON="forced tmux but tmux not in PATH"
    fi
  fi
else
  # auto / prefer
  _want_orca=0
  case "$PREFER" in
    orca) _want_orca=1 ;;
    tmux) _want_orca=0 ;;
    auto)
      # 仅当处于 Orca 托管环境（环境变量信号）时才自动选 orca。
      # 本机装了 orca CLI、app 在跑但当前 shell 不是 Orca 终端 → 仍用 tmux，
      # 避免「装了 Orca 就到处扇出」；需要时用 --force orca / ADR_HOST=orca。
      if [ "$ORCA_ENV" -eq 1 ]; then
        _want_orca=1
      fi
      ;;
  esac

  if [ "$_want_orca" -eq 1 ] && [ "$ORCA_CLI_OK" -eq 1 ]; then
    HOST=orca
    if [ "$ORCA_ENV" -eq 1 ]; then
      REASON="orca env signals present and cli status ok"
    else
      REASON="prefer/force orca and cli status ok"
    fi
  elif [ "$_want_orca" -eq 1 ] && [ "$ORCA_CLI_OK" -eq 0 ]; then
    if [ "$TMUX_AVAILABLE" -eq 1 ]; then
      HOST=tmux
      REASON="wanted orca but cli unavailable/status=$ORCA_STATUS; degraded to tmux"
    else
      HOST=tmux
      REASON="wanted orca but cli unavailable/status=$ORCA_STATUS; tmux also missing"
    fi
  else
    if [ "$TMUX_AVAILABLE" -eq 1 ]; then
      HOST=tmux
      if [ "$ORCA_ENV" -eq 0 ] && [ "$ORCA_CLI_OK" -eq 1 ]; then
        REASON="default tmux (orca cli healthy but not in Orca-managed env; use --force orca to override)"
      else
        REASON="default tmux (no orca env signals or prefer=tmux)"
      fi
    else
      HOST=tmux
      REASON="tmux preferred/default but tmux not in PATH"
    fi
  fi
fi

# ── 输出 ────────────────────────────────────────────────────
emit_kv() {
  printf 'host=%s\n' "$HOST"
  printf 'reason=%s\n' "$REASON"
  printf 'orca_env=%s\n' "$ORCA_ENV"
  printf 'orca_cli=%s\n' "$ORCA_CLI"
  printf 'orca_cli_name=%s\n' "$ORCA_CLI_NAME"
  printf 'orca_status=%s\n' "$ORCA_STATUS"
  printf 'orca_worktree_id=%s\n' "$ORCA_WORKTREE_ID_VAL"
  printf 'orca_terminal_handle=%s\n' "$ORCA_TERMINAL_HANDLE_VAL"
  printf 'tmux_available=%s\n' "$TMUX_AVAILABLE"
  printf 'preferred=%s\n' "$PREFER"
  printf 'forced=%s\n' "$FORCED"
}

json_escape() {
  # 最小转义：反斜杠与双引号
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

emit_json() {
  printf '{\n'
  printf '  "host": "%s",\n' "$(json_escape "$HOST")"
  printf '  "reason": "%s",\n' "$(json_escape "$REASON")"
  printf '  "orca_env": %s,\n' "$ORCA_ENV"
  printf '  "orca_cli": "%s",\n' "$(json_escape "$ORCA_CLI")"
  printf '  "orca_cli_name": "%s",\n' "$(json_escape "$ORCA_CLI_NAME")"
  printf '  "orca_status": "%s",\n' "$(json_escape "$ORCA_STATUS")"
  printf '  "orca_worktree_id": "%s",\n' "$(json_escape "$ORCA_WORKTREE_ID_VAL")"
  printf '  "orca_terminal_handle": "%s",\n' "$(json_escape "$ORCA_TERMINAL_HANDLE_VAL")"
  printf '  "tmux_available": %s,\n' "$TMUX_AVAILABLE"
  printf '  "preferred": "%s",\n' "$(json_escape "$PREFER")"
  printf '  "forced": %s\n' "$FORCED"
  printf '}\n'
}

if [ "$FORMAT" = "json" ]; then
  emit_json
else
  emit_kv
fi

# 退出码：选出的 host 是否真正可跑
if [ "$HOST" = "orca" ]; then
  if [ "$ORCA_CLI_OK" -eq 1 ]; then
    exit 0
  fi
  exit 1
fi
# host=tmux
if [ "$TMUX_AVAILABLE" -eq 1 ]; then
  exit 0
fi
exit 1
