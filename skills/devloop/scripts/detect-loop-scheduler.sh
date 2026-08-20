#!/usr/bin/env sh
# detect-loop-scheduler.sh — 探测协调者是否支持 /loop，并选出哨兵调度
#
# 进入 loop 点火哨兵前由协调 agent 执行；禁止靠读文档/环境变量自行推理。
# 零第三方依赖；只依赖 POSIX sh。
#
# 自动决策:
#   1. 协调者支持 /loop（claude-code / codex / grok）→ scheduler=loop
#   2. 不支持且当前是 Orca 环境 → scheduler=orca-automation（自动，告知用户）
#   3. 其他场景 → scheduler=ask（询问用户）
#
# 用法:
#   detect-loop-scheduler.sh                      # 自动探测
#   detect-loop-scheduler.sh --force cron         # 用户已选 cronjob
#   detect-loop-scheduler.sh --force loop         # 用户已选 /loop（仅当协调者支持）
#   detect-loop-scheduler.sh --force orca-automation
#   detect-loop-scheduler.sh --json
#   ADR_SCHEDULER=cron detect-loop-scheduler.sh
#   ADR_COORDINATOR=omp detect-loop-scheduler.sh
#
# 退出码:
#   0  调度已决定（scheduler=loop|orca-automation|cron）
#   1  必须询问用户（scheduler=ask）
#   2  参数错误
#
# 输出字段:
#   coordinator=claude-code|codex|grok|omp|pi|unknown
#   loop_supported=0|1
#   orca_env=0|1
#   scheduler=loop|orca-automation|cron|ask
#   reason=...
#   supported_loop_agents=claude-code,codex,grok
#   forced=0|1
set -eu

FORMAT=kv
FORCE=""
COORD_OVERRIDE=""

usage() {
  _usage_status=${1:-2}
  sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
  exit "$_usage_status"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    --force)
      [ $# -ge 2 ] || usage
      FORCE=$2
      case "$FORCE" in loop|cron|orca-automation) ;; *)
        echo "error: --force must be loop|cron|orca-automation" >&2
        exit 2
        ;;
      esac
      shift 2
      ;;
    --coordinator)
      [ $# -ge 2 ] || usage
      COORD_OVERRIDE=$2
      shift 2
      ;;
    -h|--help) usage 0 ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$FORCE" ] && [ -n "${ADR_SCHEDULER:-}" ]; then
  case "$ADR_SCHEDULER" in
    loop|cron|orca-automation) FORCE=$ADR_SCHEDULER ;;
    *)
      echo "error: ADR_SCHEDULER must be loop|cron|orca-automation" >&2
      exit 2
      ;;
  esac
fi

if [ -z "$COORD_OVERRIDE" ] && [ -n "${ADR_COORDINATOR:-}" ]; then
  COORD_OVERRIDE=$ADR_COORDINATOR
fi

# ── 探测协调者 ──────────────────────────────────────────────
# omp 会同时注入 CLAUDECODE=1；OMP 信号必须优先于 Claude。
detect_coordinator() {
  if [ -n "$COORD_OVERRIDE" ]; then
    printf '%s' "$COORD_OVERRIDE"
    return
  fi
  if [ "${OMPCODE:-}" = "1" ] || [ -n "${ORCA_OMP_SOURCE_AGENT_DIR:-}" ]; then
    printf 'omp'
    return
  fi
  if [ -n "${ORCA_PI_SOURCE_AGENT_DIR:-}" ] && [ -z "${CLAUDECODE:-}" ] \
    && [ -z "${CODEX_HOME:-}" ] && [ -z "${GROKCODE:-}" ]; then
    printf 'pi'
    return
  fi
  if [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ] \
    || [ -n "${CODEX_SANDBOX:-}" ]; then
    printf 'codex'
    return
  fi
  if [ "${GROKCODE:-}" = "1" ] || [ -n "${GROK_SESSION:-}" ]; then
    printf 'grok'
    return
  fi
  if [ "${CLAUDECODE:-}" = "1" ]; then
    printf 'claude-code'
    return
  fi
  printf 'unknown'
}

detect_orca_env() {
  if [ "${TERM_PROGRAM:-}" = "Orca" ]; then
    return 0
  fi
  if [ -n "${ORCA_WORKTREE_ID:-}" ] || [ -n "${ORCA_WORKSPACE_ID:-}" ]; then
    return 0
  fi
  if [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || [ -n "${ORCA_PANE_KEY:-}" ] \
    || [ -n "${ORCA_TAB_ID:-}" ]; then
    return 0
  fi
  if [ -n "${ORCA_OMP_SOURCE_AGENT_DIR:-}" ] || [ -n "${ORCA_APP_VERSION:-}" ]; then
    return 0
  fi
  return 1
}

loop_ok_for() {
  case "$1" in
    claude-code|codex|grok) return 0 ;;
    *) return 1 ;;
  esac
}

COORDINATOR=$(detect_coordinator)
case "$COORDINATOR" in
  claude-code|codex|grok|omp|pi|unknown) ;;
  *)
    echo "error: --coordinator must be claude-code|codex|grok|omp|pi|unknown" >&2
    exit 2
    ;;
esac

LOOP_SUPPORTED=0
if loop_ok_for "$COORDINATOR"; then
  LOOP_SUPPORTED=1
fi

ORCA_ENV=0
if detect_orca_env; then
  ORCA_ENV=1
fi

SUPPORTED_AGENTS='claude-code,codex,grok'
FORCED=0
SCHEDULER=ask
REASON=""

if [ -n "$FORCE" ]; then
  FORCED=1
  if [ "$FORCE" = "loop" ]; then
    if [ "$LOOP_SUPPORTED" -eq 1 ]; then
      SCHEDULER=loop
      REASON="user requested /loop and coordinator=$COORDINATOR supports it"
    else
      SCHEDULER=ask
      REASON="user requested /loop but coordinator=$COORDINATOR does not support /loop"
    fi
  elif [ "$FORCE" = "orca-automation" ]; then
    SCHEDULER=orca-automation
    REASON="user requested Orca automation (coordinator=$COORDINATOR loop_supported=$LOOP_SUPPORTED)"
  else
    SCHEDULER=cron
    REASON="user requested cronjob fallback (coordinator=$COORDINATOR loop_supported=$LOOP_SUPPORTED)"
  fi
elif [ "$LOOP_SUPPORTED" -eq 1 ]; then
  SCHEDULER=loop
  REASON="coordinator=$COORDINATOR supports /loop"
elif [ "$ORCA_ENV" -eq 1 ]; then
  SCHEDULER=orca-automation
  REASON="coordinator=$COORDINATOR does not support /loop; orca env present, auto-use Orca automation and tell the user"
else
  SCHEDULER=ask
  REASON="coordinator=$COORDINATOR does not support /loop and not in orca; ask user"
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

emit_kv() {
  printf 'coordinator=%s\n' "$COORDINATOR"
  printf 'loop_supported=%s\n' "$LOOP_SUPPORTED"
  printf 'orca_env=%s\n' "$ORCA_ENV"
  printf 'scheduler=%s\n' "$SCHEDULER"
  printf 'reason=%s\n' "$REASON"
  printf 'supported_loop_agents=%s\n' "$SUPPORTED_AGENTS"
  printf 'forced=%s\n' "$FORCED"
}

emit_json() {
  printf '{\n'
  printf '  "coordinator": "%s",\n' "$(json_escape "$COORDINATOR")"
  printf '  "loop_supported": %s,\n' "$LOOP_SUPPORTED"
  printf '  "orca_env": %s,\n' "$ORCA_ENV"
  printf '  "scheduler": "%s",\n' "$(json_escape "$SCHEDULER")"
  printf '  "reason": "%s",\n' "$(json_escape "$REASON")"
  printf '  "supported_loop_agents": "%s",\n' "$(json_escape "$SUPPORTED_AGENTS")"
  printf '  "forced": %s\n' "$FORCED"
  printf '}\n'
}

if [ "$FORMAT" = "json" ]; then
  emit_json
else
  emit_kv
fi

if [ "$SCHEDULER" = "ask" ]; then
  exit 1
fi
exit 0
