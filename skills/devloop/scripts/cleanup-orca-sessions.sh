#!/usr/bin/env sh
# cleanup-orca-sessions.sh — 关闭 devloop worktree 里已完成的 Orca terminal/session
#
# host=orca 时每个哨兵 tick、以及 impl/reviewer/compiler 完成后调用。
# 只关「已完成且不在 keep 列表」的 devloop runner terminal；
# 不关协调者自己、当前 live impl/reviewer，也不 worktree rm / terminal stop --worktree。
#
# 用法:
#   cleanup-orca-sessions.sh --orca-cli orca --worktree id:<repo>::<path> \
#     --keep term_live_impl,term_live_review \
#     --title-prefix devloop-<id>- \
#     [--also-close term_old1,term_old2] [--dry-run] [--json]
#
# 退出码:
#   0  扫描完成（可能关闭 0 个）
#   1  orca 调用失败
#   2  参数错误
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"

ORCA_CLI=""
WORKTREE=""
KEEP=""
ALSO_CLOSE=""
TITLE_PREFIX=""
DRY_RUN=0
FORMAT=kv

usage() {
  cat <<'EOF'
Usage: cleanup-orca-sessions.sh --orca-cli PATH --worktree id:<repo>::<path>
       [--keep h1,h2] [--also-close h3,h4] [--title-prefix devloop-<id>-]
       [--dry-run] [--json]
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --orca-cli) ORCA_CLI=$2; shift 2 ;;
    --worktree) WORKTREE=$2; shift 2 ;;
    --keep) KEEP=$2; shift 2 ;;
    --also-close) ALSO_CLOSE=$2; shift 2 ;;
    --title-prefix) TITLE_PREFIX=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage ;;
    *) dl_die "unknown arg: $1" ;;
  esac
done

[ -n "$ORCA_CLI" ] || dl_die "--orca-cli required"
[ -n "$WORKTREE" ] || dl_die "--worktree required"

SELF=${ORCA_TERMINAL_HANDLE:-}

# comma-list → newline, drop empties
csv_lines() {
  printf '%s' "$1" | tr ',' '\n' | sed '/^$/d'
}

is_kept() {
  _h=$1
  [ -n "$SELF" ] && [ "$_h" = "$SELF" ] && return 0
  case ",$KEEP," in
    *",$_h,"*) return 0 ;;
  esac
  return 1
}

# 用 python3 标准库解析 orca JSON；没有 python3 则只处理 --also-close。
HAVE_PY=0
if command -v python3 >/dev/null 2>&1; then
  HAVE_PY=1
fi

SCAN_HANDLES=""
SCAN_ERR=""

if [ "$HAVE_PY" -eq 1 ]; then
  _scan_dir=$(mktemp -d "${TMPDIR:-/tmp}/devloop-cleanup.XXXXXX") || _scan_dir=""
  if [ -n "$_scan_dir" ]; then
    if "$ORCA_CLI" terminal list --worktree "$WORKTREE" --json >"$_scan_dir/list.json" 2>/dev/null; then
      "$ORCA_CLI" worktree ps --json >"$_scan_dir/ps.json" 2>/dev/null || printf '%s\n' '{}' >"$_scan_dir/ps.json"
      SCAN_HANDLES=$(
        WORKTREE="$WORKTREE" TITLE_PREFIX="$TITLE_PREFIX" python3 - "$_scan_dir/list.json" "$_scan_dir/ps.json" <<'PY'
import json, os, sys

def load(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}

def unwrap(obj):
    if isinstance(obj, dict) and "result" in obj:
        return obj["result"]
    return obj

list_obj = unwrap(load(sys.argv[1]))
ps_obj = unwrap(load(sys.argv[2]))
worktree = os.environ.get("WORKTREE", "")
prefix = os.environ.get("TITLE_PREFIX", "")

terminals = []
if isinstance(list_obj, dict):
    terminals = list_obj.get("terminals") or []
elif isinstance(list_obj, list):
    terminals = list_obj

done_pane = set()
if isinstance(ps_obj, dict):
    for wt in ps_obj.get("worktrees") or []:
        if not isinstance(wt, dict):
            continue
        if wt.get("worktreeId") != worktree:
            continue
        for ag in wt.get("agents") or []:
            if isinstance(ag, dict) and ag.get("state") == "done" and ag.get("paneKey"):
                done_pane.add(ag["paneKey"])

seen = set()
for t in terminals:
    if not isinstance(t, dict):
        continue
    handle = t.get("handle") or ""
    if not handle or handle in seen:
        continue
    title = t.get("title") or ""
    tab = t.get("tabId") or ""
    leaf = t.get("leafId") or ""
    pane = "%s:%s" % (tab, leaf) if tab and leaf else ""
    prefixed = bool(prefix) and prefix in title
    done = pane in done_pane
    if done or prefixed:
        seen.add(handle)
        print(handle)
PY
      ) || SCAN_ERR=1
    else
      SCAN_ERR=1
    fi
    rm -rf "$_scan_dir"
  else
    SCAN_ERR=1
  fi
fi

CANDIDATES=$(
  {
    csv_lines "$ALSO_CLOSE"
    printf '%s\n' "$SCAN_HANDLES"
  } | sed '/^$/d' | awk 'NF && !seen[$0]++'
)

CLOSED=""
SKIPPED=""
CLOSED_N=0
SKIPPED_N=0

close_one() {
  _h=$1
  if is_kept "$_h"; then
    SKIPPED="${SKIPPED}${SKIPPED:+,}$_h"
    SKIPPED_N=$((SKIPPED_N + 1))
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    CLOSED="${CLOSED}${CLOSED:+,}$_h"
    CLOSED_N=$((CLOSED_N + 1))
    return 0
  fi
  if "$ORCA_CLI" terminal close --terminal "$_h" --json >/dev/null 2>&1; then
    CLOSED="${CLOSED}${CLOSED:+,}$_h"
    CLOSED_N=$((CLOSED_N + 1))
  else
    SKIPPED="${SKIPPED}${SKIPPED:+,}$_h"
    SKIPPED_N=$((SKIPPED_N + 1))
  fi
}

if [ -n "$CANDIDATES" ]; then
  printf '%s\n' "$CANDIDATES" | while IFS= read -r h; do
    printf '%s\n' "$h"
  done >"${TMPDIR:-/tmp}/devloop-cleanup-handles.$$"
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    close_one "$h"
  done <"${TMPDIR:-/tmp}/devloop-cleanup-handles.$$"
  rm -f "${TMPDIR:-/tmp}/devloop-cleanup-handles.$$"
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if [ "$FORMAT" = "json" ]; then
  printf '{\n'
  printf '  "closed": "%s",\n' "$(json_escape "$CLOSED")"
  printf '  "skipped": "%s",\n' "$(json_escape "$SKIPPED")"
  printf '  "closed_n": %s,\n' "$CLOSED_N"
  printf '  "skipped_n": %s,\n' "$SKIPPED_N"
  printf '  "dry_run": %s,\n' "$DRY_RUN"
  printf '  "have_python": %s\n' "$HAVE_PY"
  printf '}\n'
else
  printf 'closed=%s\n' "$CLOSED"
  printf 'skipped=%s\n' "$SKIPPED"
  printf 'closed_n=%s\n' "$CLOSED_N"
  printf 'skipped_n=%s\n' "$SKIPPED_N"
  printf 'dry_run=%s\n' "$DRY_RUN"
  printf 'have_python=%s\n' "$HAVE_PY"
fi

# 扫描解析失败不阻断 --also-close；完全没 python 也允许只关 also-close
if [ -n "$SCAN_ERR" ] && [ -z "$ALSO_CLOSE" ] && [ "$CLOSED_N" -eq 0 ]; then
  exit 1
fi
exit 0
