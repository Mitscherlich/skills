#!/usr/bin/env sh
# common.sh — shared helpers for devloop control-plane scripts
# Usage: . "$DEVLOOP_LIB/common.sh"  (or source via relative path)
# Zero third-party deps; POSIX sh only.

# Resolve skill root from a script under scripts/ or scripts/lib/
dl_skill_root() {
  _here=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd) || return 1
  case "$_here" in
    */scripts/lib) CDPATH= cd -- "$_here/../.." && pwd ;;
    */scripts) CDPATH= cd -- "$_here/.." && pwd ;;
    *) CDPATH= cd -- "$_here" && pwd ;;
  esac
}

dl_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

dl_warn() {
  printf 'warn: %s\n' "$*" >&2
}

dl_info() {
  printf '%s\n' "$*"
}

# Atomic write: write to temp then rename into place.
# Usage: dl_atomic_write <dest> < content via stdin
dl_atomic_write() {
  _dest=$1
  _dir=$(dirname -- "$_dest")
  mkdir -p "$_dir" || return 1
  _tmp=$(mktemp "${TMPDIR:-/tmp}/devloop-write.XXXXXX") || return 1
  cat >"$_tmp" || { rm -f "$_tmp"; return 1; }
  mv -f "$_tmp" "$_dest"
}

# ISO-ish UTC timestamp for attempt ids
dl_utc_stamp() {
  date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%Y%m%dT%H%M%S
}

# Simple portable sha256 of a file (sha256sum or shasum)
dl_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    dl_die "need sha256sum or shasum"
  fi
}

# execution_mode 是执行后端；与 gate 的 mode=full|draft、review_mode 无关。
dl_validate_mode() {
  case "$1" in
    host|acpus) return 0 ;;
    *) printf 'error: --mode 只允许 host|acpus：%s\n' "$1" >&2; return 2 ;;
  esac
}

# 缺字段的旧文件按 host 处理；拒绝重复/非法声明，不能静默切换后端。
dl_file_mode() {
  _dm_file=$1
  [ -f "$_dm_file" ] || return 0
  _dm_count=$(grep -c '^execution_mode:' "$_dm_file" || true)
  [ "$_dm_count" -le 1 ] || { printf 'error: 重复 execution_mode：%s\n' "$_dm_file" >&2; return 2; }
  if [ "$_dm_count" -eq 0 ]; then
    printf 'host\n'
    return
  fi
  _dm_value=$(sed -n 's/^execution_mode:[[:space:]]*//p' "$_dm_file" | sed 's/[[:space:]]*$//')
  [ "$_dm_value" != default ] || _dm_value=host
  dl_validate_mode "$_dm_value" || return $?
  printf '%s\n' "$_dm_value"
}

# 显式参数与持久记录必须一致。切换已有任务时先修订并重审受影响文档。
dl_resolve_mode() {
  _dm_requested=$1
  shift
  [ -z "$_dm_requested" ] || dl_validate_mode "$_dm_requested" || return $?
  _dm_recorded=
  for _dm_path in "$@"; do
    _dm_next=$(dl_file_mode "$_dm_path") || return $?
    [ -n "$_dm_next" ] || continue
    if [ -n "$_dm_recorded" ] && [ "$_dm_recorded" != "$_dm_next" ]; then
      printf 'error: intent/plan 的 execution_mode 不一致；先修订并重审受影响文档\n' >&2
      return 1
    fi
    _dm_recorded=$_dm_next
  done
  if [ -n "$_dm_requested" ] && [ -n "$_dm_recorded" ] && [ "$_dm_requested" != "$_dm_recorded" ]; then
    printf 'error: --mode=%s 与任务记录 %s 不一致；先修订并重审受影响文档\n' "$_dm_requested" "$_dm_recorded" >&2
    return 1
  fi
  printf '%s\n' "${_dm_recorded:-${_dm_requested:-host}}"
}

# auto 仅用于未指定宿主的持久记录；CLI --host 必须为具体宿主。
dl_validate_host() {
  case "$1" in tmux|herdr|orca) return 0 ;; esac
  printf 'error: --host 只允许 tmux|herdr|orca：%s\n' "$1" >&2
  return 2
}

dl_resolve_host() {
  _dh_requested=$1
  shift
  [ -z "$_dh_requested" ] || dl_validate_host "$_dh_requested" || return $?
  _dh_recorded=
  for _dh_path in "$@"; do
    [ -f "$_dh_path" ] || continue
    _dh_count=$(grep -c '^runtime_host:' "$_dh_path" || true)
    [ "$_dh_count" -le 1 ] || { printf 'error: 重复 runtime_host\n' >&2; return 2; }
    [ "$_dh_count" -eq 1 ] || continue
    _dh_value=$(sed -n 's/^runtime_host:[[:space:]]*//p' "$_dh_path" | sed 's/[[:space:]]*$//')
    [ "$_dh_value" = auto ] || dl_validate_host "$_dh_value" || return $?
    if [ -n "$_dh_recorded" ] && [ "$_dh_recorded" != "$_dh_value" ]; then
      printf 'error: intent/plan 的 runtime_host 不一致\n' >&2; return 1
    fi
    _dh_recorded=$_dh_value
  done
  if [ -n "$_dh_requested" ] && [ -n "$_dh_recorded" ] && [ "$_dh_recorded" != "$_dh_requested" ]; then
    printf 'error: --host 与任务记录不一致；先修订并重审受影响文档\n' >&2; return 1
  fi
  printf '%s\n' "${_dh_recorded:-${_dh_requested:-auto}}"
}
