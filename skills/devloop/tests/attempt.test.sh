#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ATT="$TEST_DIR/../scripts/attempt.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-attempt.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$ATT"; then ok 'sh -n attempt.sh'; else not_ok 'sh -n attempt.sh'; fi

id1=$(sh "$ATT" new --prefix t)
id2=$(sh "$ATT" new --prefix t)
case "$id1" in t-*) ok 'new attempt has prefix' ;; *) not_ok 'new attempt has prefix' ;; esac
if [ "$id1" != "$id2" ]; then ok 'attempt ids differ'; else not_ok 'attempt ids differ'; fi

mkdir -p "$TMP/run"
printf 'x\n' >"$TMP/run/claude-f1-report.md"
printf 'y\n' >"$TMP/run/claude-f1-acceptance.md"
out=$(sh "$ATT" archive --run-dir "$TMP/run" --attempt-id "$id1")
echo "$out" | grep -q 'archived=2' && ok 'archive moves 2 files' || not_ok 'archive moves 2 files'
[ -f "$TMP/run/archive/$id1/claude-f1-report.md" ] && ok 'archived report exists' || not_ok 'archived report exists'
[ ! -f "$TMP/run/claude-f1-report.md" ] && ok 'source report removed' || not_ok 'source report removed'

# second archive is empty
out2=$(sh "$ATT" archive --run-dir "$TMP/run" --attempt-id "$id2")
echo "$out2" | grep -q 'archived=0' && ok 'second archive zero' || not_ok 'second archive zero'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
