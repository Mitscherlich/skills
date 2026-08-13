#!/usr/bin/env sh
set -u
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ADR="$TEST_DIR/../scripts/adr"
RT="$TEST_DIR/../scripts/run-tests.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$RT"; then ok 'sh -n run-tests.sh'; else not_ok 'sh -n run-tests.sh'; fi
if sh -n "$ADR"; then ok 'sh -n adr'; else not_ok 'sh -n adr'; fi

help=$(sh "$ADR" help 2>&1)
echo "$help" | grep -q 'run-tests' && ok 'help lists run-tests' || not_ok 'help lists run-tests'

# Do not invoke full suite here (would recurse when run-tests runs this file).
# Smoke: script header documents exit semantics.
grep -q 'exit non-zero' "$RT" && ok 'run-tests documents failure semantics' || not_ok 'run-tests documents failure semantics'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
