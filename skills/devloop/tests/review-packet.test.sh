#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RP="$TEST_DIR/../scripts/review-packet.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-rp.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$RP"; then ok 'sh -n review-packet.sh'; else not_ok 'sh -n review-packet.sh'; fi

mkdir -p "$TMP/dl/run"
cat >"$TMP/dl/plan.md" <<'EOF'
| F1 | a | done | x | y |
| F2 | b | open | x | y |
EOF
printf '## log\n' >"$TMP/dl/progress.md"
printf 'r\n' >"$TMP/dl/run/x-report.md"

out=$(sh "$RP" --devloop-dir "$TMP/dl")
echo "$out" | grep -q 'devloop review packet' && ok 'has title' || not_ok 'has title'
echo "$out" | grep -q '^## Pipeline$' && ok 'has pipeline section' || not_ok 'has pipeline section'
echo "$out" | grep -q '^| intent | 缺失 | - |$' && ok 'reports missing intent' || not_ok 'reports missing intent'
echo "$out" | grep -q '^| plan | plan.md | \*\*FAIL\*\*' && ok 'reports failing plan gate' || not_ok 'reports failing plan gate'
echo "$out" | grep -q 'open_id=F2' && ok 'embeds status' || not_ok 'embeds status'
echo "$out" | grep -q 'reports: 1' && ok 'counts reports' || not_ok 'counts reports'
echo "$out" | grep -q '^## Next action (pipeline)$' && ok 'has pipeline next' || not_ok 'has pipeline next'
echo "$out" | grep -qx 'action=init_intent' && ok 'pipeline next flags missing intent' || not_ok 'pipeline next flags missing intent'
echo "$out" | grep -q '^## Next action (slice)$' && ok 'has slice next' || not_ok 'has slice next'
echo "$out" | grep -q 'action=work_open_slice' && ok 'embeds slice next' || not_ok 'embeds slice next'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
