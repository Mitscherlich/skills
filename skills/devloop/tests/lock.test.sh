#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOCK="$TEST_DIR/../scripts/lock.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-lock.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$LOCK"; then ok 'sh -n lock.sh'; else not_ok 'sh -n lock.sh'; fi

if sh "$LOCK" acquire --run-dir "$TMP" --phase impl >/dev/null; then
  ok 'acquire impl'
else
  not_ok 'acquire impl'
fi

if sh "$LOCK" acquire --run-dir "$TMP" --phase impl >/dev/null 2>&1; then
  not_ok 'second acquire fails'
else
  ok 'second acquire fails'
fi

if sh "$LOCK" check --run-dir "$TMP" --phase impl >/dev/null; then
  ok 'check held'
else
  not_ok 'check held'
fi

if sh "$LOCK" release --run-dir "$TMP" --phase impl >/dev/null; then
  ok 'release'
else
  not_ok 'release'
fi

if sh "$LOCK" check --run-dir "$TMP" --phase impl >/dev/null 2>&1; then
  not_ok 'check free exits non-zero'
else
  ok 'check free exits non-zero'
fi

if sh "$LOCK" acquire --run-dir "$TMP" --phase review >/dev/null; then
  ok 'acquire other phase'
else
  not_ok 'acquire other phase'
fi

if sh "$LOCK" acquire --run-dir "$TMP" --phase bogon >/dev/null 2>&1; then
  not_ok 'invalid phase rejected'
else
  ok 'invalid phase rejected'
fi

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
