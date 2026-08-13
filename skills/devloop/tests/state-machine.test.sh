#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SM="$TEST_DIR/../scripts/state-machine.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$SM"; then ok 'sh -n state-machine.sh'; else not_ok 'sh -n state-machine.sh'; fi

if sh "$SM" can --from open --to implementing; then ok 'open->implementing'; else not_ok 'open->implementing'; fi
if sh "$SM" can --from implementing --to reviewing; then ok 'implementing->reviewing'; else not_ok 'implementing->reviewing'; fi
if sh "$SM" can --from reviewing --to done; then ok 'reviewing->done'; else not_ok 'reviewing->done'; fi
if sh "$SM" can --from pending --to open; then ok 'pending->open'; else not_ok 'pending->open'; fi
if sh "$SM" can --from done --to open; then ok 're-open allowed'; else not_ok 're-open allowed'; fi

if sh "$SM" can --from pending --to done 2>/dev/null; then
  not_ok 'pending->done illegal'
else
  ok 'pending->done illegal'
fi

if sh "$SM" can --from done --to reviewing 2>/dev/null; then
  not_ok 'done->reviewing illegal'
else
  ok 'done->reviewing illegal'
fi

# normalize done (commit, 3)
if sh "$SM" validate --from reviewing --to 'done (abc, 1)' >/dev/null; then
  ok 'normalize done(...)'
else
  not_ok 'normalize done(...)'
fi

out=$(sh "$SM" transitions --from open)
echo "$out" | grep -qx implementing && ok 'transitions lists implementing' || not_ok 'transitions lists implementing'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
