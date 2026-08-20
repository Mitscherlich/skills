#!/usr/bin/env sh
# doctor.sh — health check for devloop skill layout and scripts
set -eu

SCRIPT=$0
HERE=$(CDPATH= cd -- "$(dirname -- "$SCRIPT")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
ROOT=$(adr_skill_root "$HERE/doctor.sh")

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf 'ok  %s\n' "$1"
}

bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
}

need_file() {
  if [ -f "$1" ]; then
    ok "file:$1"
  else
    bad "missing file:$1"
  fi
}

need_exec() {
  if [ -f "$1" ] && [ -x "$1" ]; then
    ok "exec:$1"
  elif [ -f "$1" ]; then
    # allow non-executable if runnable via sh
    ok "present:$1"
  else
    bad "missing:$1"
  fi
}

need_sh_n() {
  if sh -n "$1" 2>/dev/null; then
    ok "sh -n $(basename "$1")"
  else
    bad "sh -n failed: $1"
  fi
}

printf 'adr doctor — root=%s\n' "$ROOT"

need_file "$ROOT/SKILL.md"
need_file "$ROOT/ROADMAP.md"
need_file "$ROOT/references/plan-template.md"
need_file "$ROOT/references/goal-template.md"
need_file "$ROOT/scripts/detect-runtime-host.sh"
need_file "$ROOT/scripts/detect-loop-scheduler.sh"
need_file "$ROOT/scripts/cleanup-orca-sessions.sh"
need_file "$ROOT/scripts/launch-runner-template.sh"
need_file "$ROOT/scripts/lib/common.sh"
need_file "$ROOT/scripts/doctor.sh"

need_sh_n "$ROOT/scripts/detect-runtime-host.sh"
need_sh_n "$ROOT/scripts/detect-loop-scheduler.sh"
need_sh_n "$ROOT/scripts/cleanup-orca-sessions.sh"
need_sh_n "$ROOT/scripts/launch-runner-template.sh"
need_sh_n "$ROOT/scripts/lib/common.sh"
need_sh_n "$ROOT/scripts/doctor.sh"

# PATH tools used by host/tmux path
if command -v tmux >/dev/null 2>&1; then
  ok "path:tmux"
else
  adr_warn "tmux not on PATH (tmux host unavailable)"
  bad "path:tmux"
fi

if command -v git >/dev/null 2>&1; then
  ok "path:git"
else
  bad "path:git"
fi

# version line in SKILL.md
if grep -Eq '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/SKILL.md"; then
  ok "skill:version"
else
  bad "skill:version missing"
fi

printf '\nsummary: %s passed, %s failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
