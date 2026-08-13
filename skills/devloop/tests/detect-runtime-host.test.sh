#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DETECT="$TEST_DIR/../scripts/detect-runtime-host.sh"
LAUNCH="$TEST_DIR/../scripts/launch-runner-template.sh"
TMP_BASE=$(mktemp -d "${TMPDIR:-/tmp}/detect-runtime-host.test.XXXXXX") || exit 1
SYSTEM_PATH=/usr/bin:/bin
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMP_BASE"
}
trap cleanup EXIT HUP INT TERM

ok() {
  PASS=$((PASS + 1))
  printf 'ok %s - %s\n' "$PASS" "$1"
}

not_ok() {
  FAIL=$((FAIL + 1))
  printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2
}

assert_status() {
  _name=$1
  _expected=$2
  _actual=$3
  if [ "$_actual" -eq "$_expected" ]; then
    ok "$_name"
  else
    not_ok "$_name (expected status $_expected, got $_actual)"
  fi
}

assert_contains() {
  _name=$1
  _file=$2
  _pattern=$3
  if grep -Eq "$_pattern" "$_file"; then
    ok "$_name"
  else
    not_ok "$_name (missing pattern: $_pattern)"
  fi
}

assert_empty_file() {
  _name=$1
  _file=$2
  if [ ! -s "$_file" ]; then
    ok "$_name"
  else
    not_ok "$_name (unexpected Orca invocation)"
  fi
}

make_bin() {
  _dir=$1
  mkdir -p "$_dir"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$_dir/tmux"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "${FAKE_UNAME:-Darwin}"' >"$_dir/uname"
  chmod +x "$_dir/tmux" "$_dir/uname"
}

make_orca() {
  _path=$1
  printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s\n" "${0##*/}" >> "${ORCA_CALL_LOG:?}"' \
    'if [ -n "${FAKE_ORCA_JSON:-}" ]; then' \
    '  printf "%s\n" "$FAKE_ORCA_JSON"' \
    'else' \
    '  printf "%s\n" '\''{"ok":true,"result":{"runtime":{"reachable":true}}}'\''' \
    'fi' \
    >"$_path"
  chmod +x "$_path"
}

BIN="$TMP_BASE/bin"
make_bin "$BIN"
make_orca "$BIN/orca"
OUT="$TMP_BASE/out"
ERR="$TMP_BASE/err"
CALLS="$TMP_BASE/orca.calls"
: >"$CALLS"

env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  "$DETECT" --help >"$OUT" 2>"$ERR"
assert_status '--help exits 0' 0 $?
assert_contains '--help documents --prefer' "$OUT" '^  detect-runtime-host\.sh --prefer orca'
if grep -Eq '^(set -eu|FORMAT=kv)$' "$OUT"; then
  not_ok '--help only prints usage comments'
else
  ok '--help only prints usage comments'
fi

env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  "$DETECT" --force foo >"$OUT" 2>"$ERR"
assert_status 'invalid --force exits 2' 2 $?

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  ADR_HOST=tmux TERM_PROGRAM=Orca ORCA_CALL_LOG="$CALLS" \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'ADR_HOST=tmux exits 0' 0 $?
assert_contains 'ADR_HOST=tmux selects tmux' "$OUT" '^host=tmux$'
assert_contains 'ADR_HOST=tmux reports status skip' "$OUT" '^orca_status=skip$'
assert_empty_file 'ADR_HOST=tmux does not call Orca status' "$CALLS"

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  TERM_PROGRAM=Orca ORCA_CALL_LOG="$CALLS" \
  "$DETECT" --force tmux >"$OUT" 2>"$ERR"
assert_status '--force tmux exits 0' 0 $?
assert_contains '--force tmux selects tmux' "$OUT" '^host=tmux$'
assert_contains '--force tmux reports status skip' "$OUT" '^orca_status=skip$'
assert_empty_file '--force tmux does not call Orca status' "$CALLS"

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  ORCA_CALL_LOG="$CALLS" \
  "$DETECT" --prefer tmux >"$OUT" 2>"$ERR"
assert_status '--prefer tmux exits 0' 0 $?
assert_contains '--prefer tmux selects tmux' "$OUT" '^host=tmux$'
assert_contains '--prefer tmux reports status skip' "$OUT" '^orca_status=skip$'
assert_empty_file '--prefer tmux does not call Orca status' "$CALLS"

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  ORCA_CALL_LOG="$CALLS" \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'auto without Orca signal exits 0' 0 $?
assert_contains 'auto without Orca signal selects tmux' "$OUT" '^host=tmux$'
assert_contains 'auto without Orca signal reports status skip' "$OUT" '^orca_status=skip$'
assert_empty_file 'auto without Orca signal does not call Orca status' "$CALLS"

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  TERM_PROGRAM=Orca ORCA_CALL_LOG="$CALLS" \
  FAKE_ORCA_JSON='{"ok":true,"result":{"runtime":{"reachable":false}}}' \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'reachable=false degrades to available tmux' 0 $?
assert_contains 'reachable=false never selects Orca' "$OUT" '^host=tmux$'
assert_contains 'reachable=false marks Orca failed' "$OUT" '^orca_status=fail$'

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  TERM_PROGRAM=Orca ORCA_CALL_LOG="$CALLS" \
  FAKE_ORCA_JSON='{"ok":true,"result":{"runtime":{"reachable":false}},"terminal":{"reachable":true}}' \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'runtime unreachable with terminal reachable degrades to tmux' 0 $?
assert_contains 'non-runtime reachable true never selects Orca' "$OUT" '^host=tmux$'
assert_contains 'runtime unreachable with terminal reachable marks failure' "$OUT" '^orca_status=fail$'

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  TERM_PROGRAM=Orca ORCA_CALL_LOG="$CALLS" \
  FAKE_ORCA_JSON='{"ok":true,"result":{"runtime":{"reachable":false}}}' \
  "$DETECT" --force orca >"$OUT" 2>"$ERR"
assert_status '--force orca stays strict when unreachable' 1 $?
assert_contains '--force orca preserves requested host on failure' "$OUT" '^host=orca$'
assert_contains '--force orca reports status failure' "$OUT" '^orca_status=fail$'

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  TERM_PROGRAM=Orca ORCA_CALL_LOG="$CALLS" \
  FAKE_ORCA_JSON='{"ok":true,"result":{"runtime":{"reachable":true}}}' \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'reachable=true auto exits 0' 0 $?
assert_contains 'reachable=true auto selects Orca' "$OUT" '^host=orca$'
assert_contains 'reachable=true marks Orca healthy' "$OUT" '^orca_status=ok$'

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  ORCA_CALL_LOG="$CALLS" \
  FAKE_ORCA_JSON='{"result":{"runtime":{"reachable":true}}}' \
  "$DETECT" --prefer orca >"$OUT" 2>"$ERR"
assert_status '--prefer orca can select healthy Orca without env signal' 0 $?
assert_contains '--prefer orca selects Orca' "$OUT" '^host=orca$'

: >"$CALLS"
env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  TERM_PROGRAM=Orca ORCA_CALL_LOG="$CALLS" ORCA_CLI_COMMAND='orca; echo unsafe' \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'unsafe ORCA_CLI_COMMAND degrades to tmux' 0 $?
assert_contains 'unsafe ORCA_CLI_COMMAND marks failure' "$OUT" '^orca_status=fail$'
assert_empty_file 'unsafe ORCA_CLI_COMMAND is never executed' "$CALLS"

LINUX_BIN="$TMP_BASE/linux-bin"
make_bin "$LINUX_BIN"
make_orca "$LINUX_BIN/orca"
make_orca "$LINUX_BIN/orca-ide"
: >"$CALLS"
env -i PATH="$LINUX_BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  TERM_PROGRAM=Orca FAKE_UNAME=Linux ORCA_CALL_LOG="$CALLS" \
  "$DETECT" >"$OUT" 2>"$ERR"
assert_status 'Linux managed environment exits 0' 0 $?
assert_contains 'Linux prioritizes orca-ide' "$OUT" '^orca_cli_name=orca-ide$'

LINUX_UNMANAGED_BIN="$TMP_BASE/linux-unmanaged-bin"
make_bin "$LINUX_UNMANAGED_BIN"
make_orca "$LINUX_UNMANAGED_BIN/orca"
: >"$CALLS"
env -i PATH="$LINUX_UNMANAGED_BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  FAKE_UNAME=Linux ORCA_CALL_LOG="$CALLS" \
  "$DETECT" --prefer orca >"$OUT" 2>"$ERR"
assert_status 'Linux unmanaged bare orca degrades to tmux' 0 $?
assert_contains 'Linux unmanaged bare orca selects tmux' "$OUT" '^host=tmux$'
assert_empty_file 'Linux unmanaged bare orca is not called' "$CALLS"

env -i PATH="$BIN:$SYSTEM_PATH" HOME="$TMP_BASE" TMPDIR="$TMP_BASE" \
  "$DETECT" --force tmux --json >"$OUT" 2>"$ERR"
assert_status 'JSON mode exits 0' 0 $?
assert_contains 'JSON mode contains host field' "$OUT" '^  "host": "tmux",$'

if sh -n "$DETECT"; then
  ok 'sh -n detect-runtime-host.sh'
else
  not_ok 'sh -n detect-runtime-host.sh'
fi

if sh -n "$LAUNCH"; then
  ok 'sh -n launch-runner-template.sh'
else
  not_ok 'sh -n launch-runner-template.sh'
fi

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
if [ "$FAIL" -ne 0 ]; then
  printf '%s test(s) failed\n' "$FAIL" >&2
  exit 1
fi
printf '%s test(s) passed\n' "$PASS"
