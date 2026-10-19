#!/usr/bin/env sh
# doctor.sh — health check for devloop skill layout and scripts
set -eu

SCRIPT=$0
HERE=$(CDPATH= cd -- "$(dirname -- "$SCRIPT")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib/common.sh"
ROOT=$(dl_skill_root "$HERE/doctor.sh")
mode=default
mode_seen=0
acpus_cli=acpus
while [ $# -gt 0 ]; do
  case "$1" in
    --mode|--acpus-cli)
      [ $# -ge 2 ] && [ -n "$2" ] || { printf 'error: %s 需要值\n' "$1" >&2; exit 2; }
      if [ "$1" = --mode ]; then
        [ "$mode_seen" -eq 0 ] || { printf 'error: 重复 --mode\n' >&2; exit 2; }
        mode=$2; mode_seen=1; dl_validate_mode "$mode"
      else acpus_cli=$2; fi
      shift 2 ;;
    -h|--help) printf 'Usage: doctor.sh [--mode default|acpus] [--acpus-cli PATH]\n'; exit 0 ;;
    *) printf 'error: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

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

printf 'devloop doctor — root=%s\n' "$ROOT"

need_file "$ROOT/SKILL.md"
need_file "$ROOT/ROADMAP.md"
need_file "$ROOT/references/pipeline.md"
need_file "$ROOT/references/goal-template.md"
need_file "$ROOT/references/control-plane.md"
need_file "$ROOT/references/loop.md"
need_file "$ROOT/references/closeout.md"
need_file "$ROOT/references/knowledge.md"
need_file "$ROOT/references/installation-acpus.md"
need_file "$ROOT/references/acpus-mode.md"
need_file "$ROOT/templates/plan-acpus.md"
need_file "$ROOT/scripts/detect-execution-mode.sh"
need_file "$ROOT/scripts/validate-acpus-plan.awk"
need_file "$ROOT/templates/knowledge-index.md"
need_file "$ROOT/scripts/setup.sh"
need_file "$ROOT/scripts/gitignore.sh"
need_file "$ROOT/templates/process.gitignore"
need_file "$ROOT/templates/specification.md"
need_file "$ROOT/templates/specs-index.md"
need_file "$ROOT/templates/intent.md"
need_file "$ROOT/templates/spec.md"
need_file "$ROOT/templates/plan.md"
need_file "$ROOT/templates/next-goal.md"
need_file "$ROOT/templates/progress.md"
need_file "$ROOT/templates/closeout.md"
need_file "$ROOT/scripts/gate.sh"
need_file "$ROOT/scripts/init.sh"
need_file "$ROOT/scripts/detect-runtime-host.sh"
need_file "$ROOT/scripts/detect-loop-scheduler.sh"
need_file "$ROOT/scripts/cleanup-orca-sessions.sh"
need_file "$ROOT/scripts/launch-runner-template.sh"
need_file "$ROOT/scripts/lib/common.sh"
need_file "$ROOT/scripts/doctor.sh"

need_sh_n "$ROOT/scripts/gate.sh"
need_sh_n "$ROOT/scripts/init.sh"
need_sh_n "$ROOT/scripts/setup.sh"
need_sh_n "$ROOT/scripts/gitignore.sh"
need_sh_n "$ROOT/scripts/next-action.sh"
need_sh_n "$ROOT/scripts/state-machine.sh"
need_sh_n "$ROOT/scripts/detect-runtime-host.sh"
need_sh_n "$ROOT/scripts/detect-loop-scheduler.sh"
need_sh_n "$ROOT/scripts/cleanup-orca-sessions.sh"
need_sh_n "$ROOT/scripts/launch-runner-template.sh"
need_sh_n "$ROOT/scripts/lib/common.sh"
need_sh_n "$ROOT/scripts/doctor.sh"
need_sh_n "$ROOT/scripts/detect-execution-mode.sh"

# PATH tools used by host/tmux path
if [ "$mode" = acpus ]; then
  ok 'host:acpus (不要求 tmux/Orca)'
elif command -v tmux >/dev/null 2>&1; then
  ok "path:tmux"
else
  dl_warn "tmux not on PATH (tmux host unavailable)"
  bad "path:tmux"
fi

if sh "$HERE/detect-execution-mode.sh" --mode "$mode" --acpus-cli "$acpus_cli"; then
  ok "mode:$mode"
else
  bad "mode:$mode (见 references/installation-acpus.md)"
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
