#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ST="$TEST_DIR/../scripts/status.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-status.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$ST"; then ok 'sh -n status.sh'; else not_ok 'sh -n status.sh'; fi

cat >"$TMP/plan.md" <<'EOF'
# plan
| # | 切片 | 状态 | 范围 | DoD |
|---|---|---|---|---|
| F1 | a | done (c1) | x | y |
| F2 | b | open | x | y |
| F3 | c | pending | x | y |
| F4 | d | paused(need key) | x | y |
EOF

out=$(sh "$ST" --plan "$TMP/plan.md")
echo "$out" | grep -qx 'open_id=F2' && ok 'open_id F2' || not_ok 'open_id F2'
echo "$out" | grep -qx 'open_name=b' && ok 'open_name b' || not_ok 'open_name b'
echo "$out" | grep -qx 'done=1' && ok 'done=1' || not_ok 'done=1'
echo "$out" | grep -qx 'pending=1' && ok 'pending=1' || not_ok 'pending=1'
echo "$out" | grep -qx 'paused=1' && ok 'paused=1' || not_ok 'paused=1'

# multiple open fails
cat >"$TMP/plan2.md" <<'EOF'
| F1 | a | open | x | y |
| F2 | b | open | x | y |
EOF
if sh "$ST" --plan "$TMP/plan2.md" >/dev/null 2>&1; then
  not_ok 'multiple open rejected'
else
  ok 'multiple open rejected'
fi

json=$(sh "$ST" --plan "$TMP/plan.md" --json)
echo "$json" | grep -q '"open_id": "F2"' && ok 'json open_id' || not_ok 'json open_id'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
