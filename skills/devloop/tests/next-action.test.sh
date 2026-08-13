#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NX="$TEST_DIR/../scripts/next-action.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/adr-next.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$NX"; then ok 'sh -n next-action.sh'; else not_ok 'sh -n next-action.sh'; fi

cat >"$TMP/plan.md" <<'EOF'
| F1 | a | done | x | y |
| F2 | b | open | x | y |
| F3 | c | pending | x | y |
EOF

out=$(sh "$NX" --plan "$TMP/plan.md")
echo "$out" | grep -qx 'action=work_open_slice' && ok 'work open' || not_ok 'work open'
echo "$out" | grep -qx 'slice_id=F2' && ok 'slice F2' || not_ok 'slice F2'
echo "$out" | grep -qx 'phase_hint=compile_goal' && ok 'compile hint' || not_ok 'compile hint'

mkdir -p "$TMP/run"
printf 'r\n' >"$TMP/run/x-report.md"
out2=$(sh "$NX" --plan "$TMP/plan.md" --run-dir "$TMP/run")
echo "$out2" | grep -qx 'phase_hint=review' && ok 'review hint when report only' || not_ok 'review hint when report only'

cat >"$TMP/plan_all_done.md" <<'EOF'
| F1 | a | done | x | y |
| F2 | b | done | x | y |
EOF
out3=$(sh "$NX" --plan "$TMP/plan_all_done.md")
echo "$out3" | grep -qx 'action=finalize' && ok 'finalize when all done' || not_ok 'finalize when all done'

cat >"$TMP/plan_paused.md" <<'EOF'
| F1 | a | done | x | y |
| F2 | b | paused(x) | x | y |
EOF
out4=$(sh "$NX" --plan "$TMP/plan_paused.md")
echo "$out4" | grep -qx 'action=resolve_paused' && ok 'resolve paused' || not_ok 'resolve paused'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
