#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DETECT="$TEST_DIR/../scripts/detect-loop-scheduler.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/detect-loop-scheduler.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

assert_status() {
  _name=$1
  _want=$2
  _got=$3
  if [ "$_want" -eq "$_got" ]; then
    ok "$_name"
  else
    not_ok "$_name (want $_want got $_got)"
  fi
}

assert_contains() {
  _name=$1
  _file=$2
  _pat=$3
  if grep -Eq "$_pat" "$_file"; then
    ok "$_name"
  else
    not_ok "$_name"
  fi
}

OUT="$TMP/out"
ERR="$TMP/err"

if sh -n "$DETECT"; then ok 'sh -n detect-loop-scheduler.sh'; else not_ok 'sh -n detect-loop-scheduler.sh'; fi

env -i PATH="/usr/bin:/bin" "$DETECT" --help >"$OUT" 2>"$ERR"
assert_status '--help exits 0' 0 $?
assert_contains '--help documents --force cron' "$OUT" 'detect-loop-scheduler\.sh --force cron'

env -i PATH="/usr/bin:/bin" "$DETECT" --force foo >"$OUT" 2>"$ERR"
assert_status 'invalid --force exits 2' 2 $?

env -i PATH="/usr/bin:/bin" OMPCODE=1 CLAUDECODE=1 \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'omp without orca asks' 1 $?
assert_contains 'omp wins over CLAUDECODE' "$OUT" '^coordinator=omp$'
assert_contains 'omp does not support /loop' "$OUT" '^loop_supported=0$'
assert_contains 'omp without orca is ask' "$OUT" '^scheduler=ask$'

env -i PATH="/usr/bin:/bin" OMPCODE=1 CLAUDECODE=1 TERM_PROGRAM=Orca \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'omp in orca auto-uses automation' 0 $?
assert_contains 'omp in orca still omp' "$OUT" '^coordinator=omp$'
assert_contains 'omp in orca marks orca_env' "$OUT" '^orca_env=1$'
assert_contains 'omp in orca scheduler automation' "$OUT" '^scheduler=orca-automation$'

env -i PATH="/usr/bin:/bin" ORCA_OMP_SOURCE_AGENT_DIR=/tmp/omp \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'ORCA_OMP_SOURCE_AGENT_DIR auto automation' 0 $?
assert_contains 'ORCA_OMP_SOURCE_AGENT_DIR → omp' "$OUT" '^coordinator=omp$'
assert_contains 'ORCA_OMP_SOURCE_AGENT_DIR → automation' "$OUT" '^scheduler=orca-automation$'

env -i PATH="/usr/bin:/bin" CLAUDECODE=1 TERM_PROGRAM=Orca \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'claude in orca still uses /loop' 0 $?
assert_contains 'claude coordinator' "$OUT" '^coordinator=claude-code$'
assert_contains 'claude scheduler loop' "$OUT" '^scheduler=loop$'

env -i PATH="/usr/bin:/bin" CLAUDECODE=1 \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'claude-code supports /loop' 0 $?
assert_contains 'claude loop_supported' "$OUT" '^loop_supported=1$'

env -i PATH="/usr/bin:/bin" CODEX_HOME=/tmp/codex \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'codex supports /loop' 0 $?
assert_contains 'codex coordinator' "$OUT" '^coordinator=codex$'

env -i PATH="/usr/bin:/bin" GROKCODE=1 \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'grok supports /loop' 0 $?
assert_contains 'grok coordinator' "$OUT" '^coordinator=grok$'

env -i PATH="/usr/bin:/bin" \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'unknown coordinator must ask' 1 $?
assert_contains 'unknown coordinator' "$OUT" '^coordinator=unknown$'
assert_contains 'unknown scheduler ask' "$OUT" '^scheduler=ask$'

env -i PATH="/usr/bin:/bin" TERM_PROGRAM=Orca \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'unknown in orca uses automation' 0 $?
assert_contains 'unknown in orca scheduler' "$OUT" '^scheduler=orca-automation$'

env -i PATH="/usr/bin:/bin" OMPCODE=1 \
  "$DETECT" --force cron >"$OUT" 2>"$ERR"
assert_status '--force cron on omp exits 0' 0 $?
assert_contains '--force cron scheduler' "$OUT" '^scheduler=cron$'

env -i PATH="/usr/bin:/bin" OMPCODE=1 \
  "$DETECT" --force loop >"$OUT" 2>"$ERR"
assert_status '--force loop on omp still asks' 1 $?
assert_contains '--force loop on omp stays ask' "$OUT" '^scheduler=ask$'

env -i PATH="/usr/bin:/bin" CLAUDECODE=1 \
  "$DETECT" --force loop >"$OUT" 2>"$ERR"
assert_status '--force loop on claude exits 0' 0 $?
assert_contains '--force loop on claude uses loop' "$OUT" '^scheduler=loop$'

env -i PATH="/usr/bin:/bin" ADR_SCHEDULER=cron OMPCODE=1 \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'ADR_SCHEDULER=cron on omp exits 0' 0 $?
assert_contains 'ADR_SCHEDULER=cron selects cron' "$OUT" '^scheduler=cron$'

env -i PATH="/usr/bin:/bin" ADR_COORDINATOR=grok \
  "$DETECT" --json >"$OUT" 2>"$ERR"
assert_status '--json grok override exits 0' 0 $?
assert_contains 'json coordinator' "$OUT" '"coordinator": "grok"'
assert_contains 'json scheduler' "$OUT" '"scheduler": "loop"'

env -i PATH="/usr/bin:/bin" "$DETECT" --coordinator omp --json >"$OUT" 2>"$ERR"
assert_status '--coordinator omp without orca asks' 1 $?
assert_contains 'json omp ask' "$OUT" '"scheduler": "ask"'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
printf '%s test(s) passed\n' "$PASS"
