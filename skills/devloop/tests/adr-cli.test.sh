#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ADR="$TEST_DIR/../scripts/adr"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/adr-cli.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$ADR"; then ok 'sh -n adr'; else not_ok 'sh -n adr'; fi

ver=$(sh "$ADR" version)
[ "$ver" = "0.5.0" ] && ok 'version 0.5.0' || not_ok 'version 0.5.0'

if sh "$ADR" help >/dev/null; then ok 'help exits 0'; else not_ok 'help exits 0'; fi

if sh "$ADR" doctor >/dev/null; then ok 'doctor via adr'; else not_ok 'doctor via adr'; fi

id=$(sh "$ADR" attempt new --prefix cli)
case "$id" in cli-*) ok 'attempt via adr' ;; *) not_ok 'attempt via adr' ;; esac

if sh "$ADR" state can --from open --to implementing; then
  ok 'state via adr'
else
  not_ok 'state via adr'
fi

cat >"$TMP/plan.md" <<'EOF'
| F1 | a | open | x | y |
EOF
out=$(sh "$ADR" status --plan "$TMP/plan.md")
echo "$out" | grep -qx 'open_id=F1' && ok 'status via adr' || not_ok 'status via adr'

out2=$(sh "$ADR" next --plan "$TMP/plan.md")
echo "$out2" | grep -qx 'action=work_open_slice' && ok 'next via adr' || not_ok 'next via adr'

mkdir -p "$TMP/adr"
cp "$TMP/plan.md" "$TMP/adr/plan.md"
if sh "$ADR" review-packet --adr-dir "$TMP/adr" | grep -q 'review packet'; then
  ok 'review-packet via adr'
else
  not_ok 'review-packet via adr'
fi

if sh "$ADR" not-a-cmd >/dev/null 2>&1; then
  not_ok 'unknown command fails'
else
  ok 'unknown command fails'
fi

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
