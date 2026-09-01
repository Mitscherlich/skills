#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLEAN="$TEST_DIR/../scripts/cleanup-orca-sessions.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-orca-sessions.test.XXXXXX") || exit 1
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

if sh -n "$CLEAN"; then ok 'sh -n cleanup-orca-sessions.sh'; else not_ok 'sh -n cleanup-orca-sessions.sh'; fi

WT='repo-1::/tmp/devloop-wt'
BIN="$TMP/bin"
mkdir -p "$BIN"
CALLS="$TMP/orca.calls"
: >"$CALLS"

cat >"$BIN/orca" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${ORCA_CALL_LOG:?}"
cmd=$1
sub=${2:-}
if [ "$cmd" = "terminal" ] && [ "$sub" = "list" ]; then
  printf '%s\n' "${FAKE_LIST_JSON:-}"
  exit 0
fi
if [ "$cmd" = "worktree" ] && [ "$sub" = "ps" ]; then
  printf '%s\n' "${FAKE_PS_JSON:-}"
  exit 0
fi
if [ "$cmd" = "terminal" ] && [ "$sub" = "close" ]; then
  h=""
  while [ $# -gt 0 ]; do
    if [ "$1" = "--terminal" ]; then
      h=$2
      break
    fi
    shift
  done
  printf '%s\n' "$h" >> "${ORCA_CLOSE_LOG:?}"
  printf '%s\n' '{"ok":true}'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN/orca"

LIST_JSON='{"ok":true,"result":{"terminals":[{"handle":"term_done","title":"old review","tabId":"tabA","leafId":"leafA"},{"handle":"term_live","title":"devloop-0001-f9-impl-att1","tabId":"tabB","leafId":"leafB"},{"handle":"term_self","title":"coordinator","tabId":"tabC","leafId":"leafC"},{"handle":"term_prefix","title":"devloop-0001-f5-impl-old","tabId":"tabD","leafId":"leafD"}]}}'
PS_JSON='{"ok":true,"result":{"worktrees":[{"worktreeId":"repo-1::/tmp/devloop-wt","agents":[{"state":"done","paneKey":"tabA:leafA"},{"state":"working","paneKey":"tabB:leafB"}]}]}}'

OUT="$TMP/out"
ERR="$TMP/err"
CLOSE_LOG="$TMP/close.log"
: >"$CLOSE_LOG"

env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMP" \
  "$CLEAN" >"$OUT" 2>"$ERR"
assert_status 'missing args exits 1 or 2' 1 $?

: >"$CALLS"
: >"$CLOSE_LOG"
env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMP" \
  ORCA_CALL_LOG="$CALLS" ORCA_CLOSE_LOG="$CLOSE_LOG" \
  FAKE_LIST_JSON="$LIST_JSON" FAKE_PS_JSON="$PS_JSON" \
  ORCA_TERMINAL_HANDLE=term_self \
  "$CLEAN" --orca-cli "$BIN/orca" --worktree "$WT" \
    --keep term_live --title-prefix devloop-0001- >"$OUT" 2>"$ERR"
assert_status 'cleanup exits 0' 0 $?
assert_contains 'closes done session' "$OUT" 'term_done'
assert_contains 'closes prefixed leftover' "$OUT" 'term_prefix'
assert_contains 'counts two closes' "$OUT" '^closed_n=2$'
if grep -q 'term_live' "$CLOSE_LOG"; then
  not_ok 'does not close kept live impl'
else
  ok 'does not close kept live impl'
fi
if grep -q 'term_self' "$CLOSE_LOG"; then
  not_ok 'does not close coordinator self'
else
  ok 'does not close coordinator self'
fi
if grep -qx 'term_done' "$CLOSE_LOG" && grep -qx 'term_prefix' "$CLOSE_LOG"; then
  ok 'close log has done and prefixed handles'
else
  not_ok 'close log has done and prefixed handles'
fi

: >"$CALLS"
: >"$CLOSE_LOG"
env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMP" \
  ORCA_CALL_LOG="$CALLS" ORCA_CLOSE_LOG="$CLOSE_LOG" \
  FAKE_LIST_JSON="$LIST_JSON" FAKE_PS_JSON="$PS_JSON" \
  "$CLEAN" --orca-cli "$BIN/orca" --worktree "$WT" \
    --also-close term_old --dry-run >"$OUT" 2>"$ERR"
assert_status 'dry-run exits 0' 0 $?
assert_contains 'dry-run reports also-close' "$OUT" 'term_old'
if [ -s "$CLOSE_LOG" ]; then
  not_ok 'dry-run does not call terminal close'
else
  ok 'dry-run does not call terminal close'
fi

: >"$CLOSE_LOG"
env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" TMPDIR="$TMP" \
  ORCA_CALL_LOG="$CALLS" ORCA_CLOSE_LOG="$CLOSE_LOG" \
  FAKE_LIST_JSON="$LIST_JSON" FAKE_PS_JSON="$PS_JSON" \
  "$CLEAN" --orca-cli "$BIN/orca" --worktree "$WT" \
    --keep term_done --also-close term_done --json >"$OUT" 2>"$ERR"
assert_status 'keep wins over also-close' 0 $?
assert_contains 'json skipped kept also-close' "$OUT" 'term_done'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
printf '%s test(s) passed\n' "$PASS"
